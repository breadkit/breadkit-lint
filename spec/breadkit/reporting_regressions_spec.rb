# frozen_string_literal: true

require "tmpdir"

RSpec.describe "lint reporting regressions" do
  it "normalizes CSS color names and functions by family" do
    checks = Breadkit::Lint::Checks.new(Breadkit::Lint::Config.new, {})
    expect(%w[darkred crimson maroon].map { |color| checks.color_family(color) }).to all(eq("red"))
    expect(checks.color_family("grey")).to eq("gray")
    expect(checks.color_family("navy")).to eq("blue")
    expect(checks.color_family("rgb(255, 0, 0)")).to eq("red")
    expect(checks.color_family("hsl(210, 100%, 50%)")).to eq("blue")
    expect(checks.color_family("rgb(0, 255, 255)")).to eq("blue")
    expect(checks.color_family("hsl(180, 100%, 50%)")).to eq("blue")
  end

  it "does not flag functional cyan on a negative rail" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "cyan.bk.rb")
      File.write(path, "board :half\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nwire 'a10', 'B-', color: 'rgb(0, 255, 255)'\n")
      found = Breadkit::Lint::Engine.new.run([path], only: ["Style/WireColor"]).first[:offenses]
      expect(found).to be_empty
    end
  end

  it "reports an unused suppression in source order" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nlint_disable 'Electrical/FloatingPin'\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nwire 'a10', 'B+', color: :blue\n")
      result = Breadkit::Lint::Engine.new.run([path]).first
      expect(result[:offenses].map(&:rule)).to include("Lint/RedundantDisable", "Style/WireColor")
      relevant = result[:offenses].select { |item| %w[Lint/RedundantDisable Style/WireColor].include?(item.rule) }
      expect(relevant.map { |item| item.location&.line }).to eq([2, 4])
      expect(Breadkit::Lint::Engine.new.run([path], only: ["Electrical/FloatingPin"]).first[:offenses].map(&:rule))
        .not_to include("Lint/RedundantDisable")
      expect(Breadkit::Lint::Engine.new.run([path], except: ["Lint/RedundantDisable"]).first[:offenses].map(&:rule))
        .not_to include("Lint/RedundantDisable")
    end
  end

  it "reports a duplicate suppression after the first one hides an offense" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nled :D1, anode: 'a10', cathode: 'a11'\nlint_disable 'Electrical/FloatingPin'\nlint_disable 'Electrical/FloatingPin'\n")
      found = Breadkit::Lint::Engine.new.run([path]).first[:offenses]
      expect(found.count { |item| item.rule == "Lint/RedundantDisable" }).to eq(1)
    end
  end

  it "keeps invalid and redundant suppressions in source order" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "suppression.bk.rb")
      config_path = File.join(directory, ".bklint.yml")
      File.write(config_path, "AllRules:\n  RequireDisableReason: true\n")
      File.write(path, "board :half\nlint_disable 'Missing/Rule'\nlint_disable 'Electrical/FloatingPin'\nlint_disable 'Electrical/FloatingPin', reason: 'planned'\n")
      found = Breadkit::Lint::Engine.new(config: Breadkit::Lint::Config.new(config_path)).run([path]).first[:offenses]
      selected = found.select { |item| %w[Lint/UnknownRuleInDisable Config/InvalidDisable Lint/RedundantDisable].include?(item.rule) }
      expect(selected.map { |item| [item.rule, item.location&.line] }).to eq([
        ["Lint/UnknownRuleInDisable", 2], ["Config/InvalidDisable", 3], ["Lint/RedundantDisable", 4]
      ])
    end
  end

  it "finds pins outside every declared strict net" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nresistor :R1, '330', pins: %w[a1 a2]\nresistor :R2, '220', pins: %w[a5 a6]\nnet :SIGNAL, at: 'b1'\nexpect strict: true do\n  net :SIGNAL, 'R1.1'\nend\n")
      found = Breadkit::Lint::Engine.new.run([path], only: ["Intent/ConnectionMismatch"]).first[:offenses]
      expect(found.map(&:message).join).to include("R2.1")
    end
  end

  it "does not call an electrical suppression unused when layout errors skip that check" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nlint_disable 'Electrical/FloatingPin'\nresistor :R1, 'bad', pins: %w[a1 a2]\n")
      result = Breadkit::Lint::Engine.new.run([path]).first
      expect(result[:offenses].map(&:rule)).to include("Layout/InvalidValue")
      expect(result[:offenses].map(&:rule)).not_to include("Lint/RedundantDisable")
    end
  end

  it "shows relative paths and a source line for fatal DSL errors" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nexit 3\n")
      result = Breadkit::Lint::Engine.new.run([path]).first
      expect(result[:offenses].first.rule).to eq("Fatal/EvaluationError")
      expect(result[:offenses].first.location.line).to eq(2)
      output = Breadkit::Lint::Formatter.new.github([result])
      expect(output).to include("line=2")
      expect(output).not_to include("file=#{directory}/")
    end
  end

  it "continues inspecting later files after a DSL exit" do
    Dir.mktmpdir do |directory|
      first = File.join(directory, "exit.bk.rb")
      second = File.join(directory, "next.bk.rb")
      File.write(first, "board :half\nexit 3\n")
      File.write(second, "board :half\n")
      files = Breadkit::Lint::Engine.new.run([first, second])
      expect(files.map { |item| File.basename(item[:path]) }).to eq(%w[exit.bk.rb next.bk.rb])
      expect(files.first[:offenses].map(&:rule)).to include("Fatal/EvaluationError")
    end
  end

  it "explains a rule in Japanese when explicitly requested" do
    expect do
      expect(Breadkit::Lint::CLI.new.run(["--explain", "Electrical/SplitRail", "--locale", "ja"])).to eq(0)
    end.to output(/橋渡ししてください/).to_stdout
  end

  it "explains unknown suppression rules in Japanese" do
    expect { expect(Breadkit::Lint::CLI.new.run(["--explain", "Lint/UnknownRuleInDisable", "--locale", "ja"])).to eq(0) }
      .to output(/不明なルール/).to_stdout
  end

  it "explains newly added rules in Japanese" do
    expect { expect(Breadkit::Lint::CLI.new.run(["--explain", "Layout/LeadSpan", "--locale", "ja"])).to eq(0) }
      .to output(/リード長の上限.*穴を近づける/m).to_stdout
  end

  it "has Japanese descriptions and guidance for every listed rule" do
    translations = YAML.safe_load(File.read(File.expand_path("../../locales/ja.yml", __dir__), encoding: "UTF-8"))
    rule_ids = Breadkit::Lint::Registry::RULES.map(&:id)
    expect(rule_ids - translations.fetch("rules").keys).to be_empty
    expect(rule_ids - translations.fetch("guidance").keys).to be_empty
  end

  it "adds rule guidance to text findings in teach mode" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "short.bk.rb")
      File.write(path, "board :half\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nwire 'B+', 'B-'\n")
      expect do
        expect(Breadkit::Lint::CLI.new.run(["--teach", "--only", "Electrical/ShortCircuit", path])).to eq(1)
      end.to output(/Why: Power constraints assign incompatible voltages/).to_stdout
      expect do
        expect(Breadkit::Lint::CLI.new.run(["--teach", "--locale", "ja", "--only", "Electrical/ShortCircuit", path])).to eq(1)
      end.to output(/説明: 短絡経路/).to_stdout
      expect(Breadkit::Lint::CLI.new.run(["--teach", "--format", "json", path])).to eq(2)
    end
  end

  it "locates and suggests the bridge for a used split rail" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :full, split_rails: true\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nwire 'a10', 'B+30'\n")
      result = Breadkit::Lint::Engine.new.run([path], only: ["Electrical/SplitRail"]).first
      item = result[:offenses].find { |entry| entry.rule == "Electrical/SplitRail" }
      expect(item.location.line).to eq(3)
      expect(item.message).to match(/bridge B\+\d+ to B\+\d+/)
      expect(item.targets[:holes].length).to eq(2)
    end
  end
end
