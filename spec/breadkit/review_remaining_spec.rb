# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "stringio"

RSpec.describe "remaining lint review findings" do
  def inspect_source(source, only: nil, locale: "en")
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      Breadkit::Lint::Engine.new(locale: locale).run([path], only: only).first
    end
  end

  it "keeps distinct supply reference nets distinct even when their positive nets meet" do
    source = <<~RUBY
      board :half
      supply :A, voltage: 5, plus: 'B+1', minus: 'B-1'
      supply :B, voltage: 3.3, plus: 'B+2', minus: 'T-1'
    RUBY
    offenses = inspect_source(source, only: ["Electrical/NoCommonGround"])[:offenses]
    expect(offenses.map(&:rule)).to include("Electrical/NoCommonGround")
  end

  it "uses the core conflict witnesses instead of nominal supply voltages" do
    source = <<~RUBY
      board :half
      supply :POS, voltage: 5, plus: 'B+1', minus: 'B-1'
      supply :NEG, voltage: -5, plus: 'T-1', minus: 'B-2'
      wire 'B+3', 'T-3'
    RUBY
    item = inspect_source(source, only: ["Electrical/ShortCircuit"])[:offenses].first
    expect(item.message).to include("POS.+", "NEG.+", "path:")
    expect(item.targets[:wires]).to include("W1")
    expect(item.location.line).to eq(4)
  end

  it "checks net expectations with no pin references without a fatal error" do
    source = <<~RUBY
      board :half
      net :GND, at: 'B-1'
      expect { net :GND }
    RUBY
    expect(inspect_source(source)[:offenses].map(&:rule)).not_to include("Fatal/EvaluationError", "Intent/ConnectionMismatch")
    missing = source.sub("net :GND, at: 'B-1'", "").sub("net :GND }", "net :MISSING }")
    expect(inspect_source(missing)[:offenses].map(&:rule)).to include("Intent/UnknownNet")
  end

  it "infers a resistor divider midpoint for polarity checks" do
    reverse = <<~RUBY
      board :half
      supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
      resistor :R1, '1k', pins: %w[a10 a11]
      resistor :R2, '1k', pins: %w[b11 a12]
      led :D1, anode: 'b12', cathode: 'c11'
      wire 'b10', 'B+'
      wire 'c12', 'B-'
    RUBY
    forward = reverse.sub("anode: 'b12', cathode: 'c11'", "anode: 'c11', cathode: 'b12'")
    rule = ["Electrical/ReversePolarity"]
    expect(inspect_source(reverse, only: rule)[:offenses].map(&:rule)).to include(rule.first)
    expect(inspect_source(forward, only: rule)[:offenses]).to be_empty
  end

  it "keeps layout diagnostics when one rule crashes and classifies their targets" do
    broken = Class.new(Breadkit::Lint::Rule) do
      rule "Custom/BrokenReview", severity: :error, description: "Raises"

      def check(_context)
        raise "intentional failure"
      end
    end
    source = "board :half\nresistor :R1, '330', pins: %w[a1 a3]\nresistor :R2, '330', pins: %w[a1 a5]\n"
    result = inspect_source(source, only: ["Layout/HoleConflict", "Custom/BrokenReview"])
    expect(result[:offenses].map(&:rule)).to include("Layout/HoleConflict", "Fatal/RuleError")
    expect(result[:offenses].find { |item| item.rule == "Layout/HoleConflict" }.targets[:holes]).to include("a1")
  ensure
    Breadkit::Lint::Registry.all.delete(broken) if broken
  end

  it "emits GitHub-compatible SARIF locations and escaped workflow properties" do
    item = Breadkit::Lint::Offense.new(rule: "Layout/HoleConflict", severity: "error", message: "bad %, line\nnext",
                                      location: nil, targets: {})
    files = [{ path: "a,b:c.bk.rb", offenses: [item] }]
    formatter = Breadkit::Lint::Formatter.new
    github = formatter.github(files)
    expect(github).to include("file=a%2Cb%3Ac.bk.rb", "bad %25, line%0Anext")
    sarif = JSON.parse(formatter.sarif(files))
    run = sarif.fetch("runs").first
    location = run.dig("results", 0, "locations", 0, "physicalLocation", "artifactLocation")
    expect(location).to include("uriBaseId" => "%SRCROOT%")
    expect(run.dig("originalUriBaseIds", "%SRCROOT%", "uri")).to start_with("file:")
    rule = run.dig("tool", "driver", "rules").find { |entry| entry["id"] == "Layout/HoleConflict" }
    expect(rule["helpUri"]).to start_with("https://")
    expect(rule.dig("defaultConfiguration", "level")).to eq("error")
  end

  it "counts infos, uses a singular file label, and explains skipped checks" do
    item = Breadkit::Lint::Offense.new(rule: "Style/WireColor", severity: "info", message: "color", targets: {})
    text = Breadkit::Lint::Formatter.new.text([{ path: "sample.bk.rb", offenses: [item], skipped: true }])
    expect(text).to include("1 file inspected", "1 info", "electrical and intent checks skipped")
  end

  it "ignores visual wires as electrical attachments and suppresses duplicate floating pins" do
    visual = <<~RUBY
      board :half
      resistor :R1, '330', pins: %w[b11 a13]
      wire 'a10', 'a11'
      wire 'b10', 'c10', electrical: false
    RUBY
    expect(inspect_source(visual, only: ["Electrical/DanglingWire"])[:offenses].map(&:rule)).to include("Electrical/DanglingWire")
    shared = "board :half\nresistor :R1, '330', pins: %w[a1 b1]\n"
    result = inspect_source(shared, only: ["Layout/PinsInSameStrip", "Electrical/FloatingPin"])
    expect(result[:offenses].map(&:rule)).to include("Layout/PinsInSameStrip")
    expect(result[:offenses].map(&:rule)).not_to include("Electrical/FloatingPin")
  end

  it "translates rule messages and honors LC_ALL before LC_MESSAGES and LANG" do
    source = "board :half\nled :D1, anode: 'b10', cathode: 'b11'\n"
    messages = inspect_source(source, only: ["Electrical/FloatingPin"], locale: "ja")[:offenses].map(&:message)
    expect(messages).to include(a_string_including("外部に接続されていません"))
    cli = Breadkit::Lint::CLI.new
    old = ENV.to_h.slice("LC_ALL", "LC_MESSAGES", "LANG")
    ENV["LANG"], ENV["LC_MESSAGES"], ENV["LC_ALL"] = "en_US.UTF-8", "ja_JP.UTF-8", "C"
    expect(cli.send(:locale_from_environment)).to eq("en")
    ENV["LC_ALL"] = nil
    expect(cli.send(:locale_from_environment)).to eq("ja")
  ensure
    %w[LC_ALL LC_MESSAGES LANG].each { |key| old.key?(key) ? ENV[key] = old[key] : ENV.delete(key) } if old
  end

  it "discovers IR JSON and nested configuration while pruning node_modules" do
    Dir.mktmpdir do |directory|
      Dir.chdir(directory) do
        File.write("sample.bk.rb", "board :half\n")
        File.write("circuit.json", JSON.generate(schema_version: 1, board: { type: "half" }))
        File.write("package.json", JSON.generate(name: "unrelated"))
        FileUtils.mkdir_p("node_modules/ignored")
        File.write("node_modules/ignored/bad.bk.rb", "not ruby")
        FileUtils.mkdir_p("nested")
        File.write("nested/.bklint.yml", "Electrical/FloatingPin: {Enabled: false}\n")
        File.write("nested/led.bk.rb", "board :half\nled :D1, anode: 'b10', cathode: 'b11'\n")
        cli = Breadkit::Lint::CLI.new
        expect(cli.send(:expand_inputs, [])).to include("./sample.bk.rb", "./circuit.json", "./nested/led.bk.rb")
        expect(cli.send(:expand_inputs, [])).not_to include("./package.json", "./node_modules/ignored/bad.bk.rb")
        expect(cli.send(:nearest_config, "nested/led.bk.rb")).to eq(File.join(Dir.pwd, "nested/.bklint.yml"))
        output = StringIO.new
        previous = $stdout
        $stdout = output
        expect(cli.run(["--only", "Electrical/FloatingPin", "-f", "json", "nested"])).to eq(0)
        expect(JSON.parse(output.string).dig("files", 0, "offenses")).to be_empty
      ensure
        $stdout = previous if previous
      end
    end
  end

  it "checks every power pin on offboard modules" do
    Dir.mktmpdir do |directory|
      part = File.join(directory, "test_module.yml")
      File.write(part, <<~YAML)
        id: test_module
        category: offboard
        placement: offboard
        pins:
          - {num: 1, name: P1, role: power}
          - {num: 2, name: P2, role: power}
          - {num: 3, name: GND, role: ground}
        supply_range: [3, 6]
      YAML
      source = <<~RUBY
        board :half
        use_parts #{part.inspect}
        supply :FIVE, voltage: 5, plus: 'B+1', minus: 'B-1'
        supply :TEN, voltage: 10, plus: 'T+1', minus: 'B-2'
        offboard :M, :test_module
        wire 'M.P1', 'B+2'
        wire 'M.P2', 'T+2'
        wire 'M.GND', 'B-3'
      RUBY
      rule = ["Electrical/SupplyVoltageRange"]
      offenses = inspect_source(source, only: rule)[:offenses]
      expect(offenses.map(&:rule)).to include(rule.first)
      expect(offenses.map(&:message).join).to include("P2/GND")
      expect(Breadkit::Lint::Registry.all.find { |item| item.id == rule.first }.state_sensitive).to be(true)
      switched = source.sub("wire 'M.P2', 'T+2'", "button :SW1, at: 'e20'\nwire 'M.P2', 'SW1.1'\nwire 'SW1.3', 'T+2'")
      state_offenses = inspect_source(switched, only: rule)[:offenses]
      expect(state_offenses.map(&:state)).to include("SW1")
    end
  end
end
