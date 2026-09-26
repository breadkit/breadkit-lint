# frozen_string_literal: true

require "tmpdir"

RSpec.describe "reviewed lint behavior" do
  def inspect_source(source, only: nil, config: Breadkit::Lint::Config.new)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      Breadkit::Lint::Engine.new(config: config).run([path], only: only).first[:offenses]
    end
  end

  it "recognizes grounds shared by positive and negative supplies" do
    common = <<~RUBY
      board :half
      supply :POS, voltage: 5, plus: 'B+1', minus: 'B-1'
      supply :NEG, voltage: -5, plus: 'T-1', minus: 'B-2'
    RUBY
    separate = common.sub("minus: 'B-2'", "minus: 'T+1'")
    expect(inspect_source(common, only: ["Electrical/NoCommonGround"])).to be_empty
    expect(inspect_source(separate, only: ["Electrical/NoCommonGround"]).map(&:rule)).to include("Electrical/NoCommonGround")
  end

  it "maps new core board and placement diagnostics to blocking layout rules" do
    unknown = inspect_source("board :missing_board\n", only: ["Layout/UnknownBoard"])
    unplaced = inspect_source("board :half\nresistor :R1, '330', pins: ['a1']\n", only: ["Layout/UnplacedPin"])
    expect(unknown.map(&:rule)).to include("Layout/UnknownBoard")
    expect(unplaced.map(&:rule)).to include("Layout/UnplacedPin")
  end

  it "reports one short at the connecting wire, with the conflicting terminals" do
    source = <<~RUBY
      board :half
      supply :USB, voltage: 5, plus: 'B+1', minus: 'B-1'
      supply :REG, voltage: 3.3, plus: 'T+1', minus: 'B-2'
      wire 'B+3', 'T+3'
    RUBY
    offenses = inspect_source(source, only: ["Electrical/ShortCircuit"])
    expect(offenses.length).to eq(1)
    expect(offenses.first.message).to include("USB.+", "REG.+", "path:")
    expect(offenses.first.location.line).to eq(4)
  end

  it "does not repeat a baseline short for a switch state" do
    source = <<~RUBY
      board :half
      supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
      button :SW1, at: 'e20'
      wire 'a10', 'B+'
      wire 'b10', 'B-'
    RUBY
    offenses = inspect_source(source, only: ["Electrical/ShortCircuit"])
    expect(offenses.length).to eq(1)
    expect(offenses.first.state).to be_nil
  end

  it "normalizes pin numbers in strict net expectations and checks the net name" do
    base = <<~RUBY
      board :half
      ic :U1, 'NE555', at: 'e20'
      net :VCC, at: 'f20'
      expect strict: true do
        net :VCC, 'U1.8'
      end
    RUBY
    expect(inspect_source(base, only: ["Intent/ConnectionMismatch"])).to be_empty
    wrong_name = base.sub("net :VCC, 'U1.8'", "net :WRONG, 'U1.8'")
    expect(inspect_source(wrong_name, only: ["Intent/ConnectionMismatch"]).first.message).to include("expected net WRONG")
  end

  it "finds LEDs in an unprotected series chain and on a GPIO output" do
    chain = <<~RUBY
      board :half
      supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
      led :D1, anode: 'b10', cathode: 'b11'
      led :D2, anode: 'c11', cathode: 'b12'
      wire 'a10', 'B+'
      wire 'a12', 'B-'
    RUBY
    gpio = <<~RUBY
      board :half
      offboard :UNO, :arduino_uno
      led :D1, anode: 'b10', cathode: 'b11'
      wire 'UNO.D13', 'a10'
      wire 'UNO.GND', 'a11'
    RUBY
    protected_led = chain.sub("led :D2, anode: 'c11', cathode: 'b12'", "resistor :R1, '330', pins: %w[c11 b12]")
    rule = ["Electrical/MissingSeriesResistor"]
    expect(inspect_source(chain, only: rule).map { |item| item.targets[:components].first }).to contain_exactly("D1", "D2")
    expect(inspect_source(gpio, only: rule).map(&:rule)).to include(rule.first)
    expect(inspect_source(protected_led, only: rule)).to be_empty
  end

  it "finds reversed LEDs behind a resistor and leaves forward LEDs alone" do
    reverse = <<~RUBY
      board :half
      supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
      resistor :R1, '330', pins: %w[a10 a11]
      led :D1, anode: 'b12', cathode: 'b11'
      wire 'b10', 'B+'
      wire 'a12', 'B-'
    RUBY
    forward = reverse.sub("anode: 'b12', cathode: 'b11'", "anode: 'b11', cathode: 'b12'")
    rule = ["Electrical/ReversePolarity"]
    expect(inspect_source(reverse, only: rule).map(&:rule)).to include(rule.first)
    expect(inspect_source(forward, only: rule)).to be_empty
  end

  it "validates lint disables and resolves pin aliases" do
    source = <<~RUBY
      board :half
      led :D1, anode: 'b10', cathode: 'b11'
      lint_disable 'Electrical/FloatingPin', on: 'D1.a'
      lint_disable 'Missing/Rule'
    RUBY
    offenses = inspect_source(source, only: ["Electrical/FloatingPin"])
    expect(offenses.map(&:rule)).to include("Config/InvalidDisable")
    expect(offenses.select { |item| item.rule == "Electrical/FloatingPin" }.map(&:message)).to eq(["D1.cathode has no external connection"])
  end

  it "requires disable reasons when configured and gates pending rules" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, ".bklint.yml")
      File.write(path, "AllRules:\n  RequireDisableReason: true\n  NewRules: pending\nStyle/WireColor:\n  Enabled: pending\n")
      config = Breadkit::Lint::Config.new(path)
      color_rule = Breadkit::Lint::Registry.all.find { |rule| rule.id == "Style/WireColor" }
      expect(config.enabled?(color_rule)).to be(false)
      config.data["AllRules"]["NewRules"] = "enable"
      expect(config.enabled?(color_rule)).to be(true)
      source = "board :half\nled :D1, anode: 'b10', cathode: 'b11'\nlint_disable 'Electrical/FloatingPin'\n"
      expect(inspect_source(source, config: config).map(&:rule)).to include("Config/InvalidDisable")
      allowed = source.sub("lint_disable 'Electrical/FloatingPin'", "lint_disable 'Electrical/FloatingPin', reason: 'intentional'")
      expect(inspect_source(allowed, config: config).map(&:rule)).not_to include("Config/InvalidDisable")
    end
  end

  it "accepts conventional HEX colors and preserves source paths in formatted output" do
    source = <<~RUBY
      board :half
      supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
      wire 'a10', 'B+', color: '#E24B4A'
      wire 'a11', 'B-', color: '#222222'
      wire 'a12', 'B-', color: '#888780'
    RUBY
    expect(inspect_source(source, only: ["Style/WireColor"])).to be_empty
    expect(inspect_source(source.sub("#E24B4A", "#00FF00"), only: ["Style/WireColor"]).map(&:rule)).to include("Style/WireColor")
    item = Breadkit::Lint::Offense.new(rule: "Layout/InvalidHole", severity: "error", message: "bad hole",
                                      location: Breadkit::SourceLocation.new(path: "source.bk.rb", line: 12), targets: {})
    files = [{ path: "circuit.json", offenses: [item] }]
    formatter = Breadkit::Lint::Formatter.new
    text = formatter.text(files)
    expect(text).to include("source.bk.rb:12:")
    expect(formatter.github(files)).to include("file=source.bk.rb,line=12")
    expect(JSON.parse(formatter.json(files)).dig("files", 0, "offenses", 0, "location", "path")).to eq("source.bk.rb")
    item.location = nil
    expect(formatter.text(files)).to include("circuit.json: E:")
    expect(formatter.github(files)).not_to include("line=1")
  end
end
