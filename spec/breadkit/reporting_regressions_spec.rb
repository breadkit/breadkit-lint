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
  end

  it "reports an unused suppression in source order" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nlint_disable 'Electrical/FloatingPin'\nsupply :P, voltage: 5, plus: 'B+1', minus: 'B-1'\nwire 'a10', 'B+', color: :blue\n")
      result = Breadkit::Lint::Engine.new.run([path]).first
      expect(result[:offenses].map(&:rule)).to include("Lint/RedundantDisable", "Style/WireColor")
      relevant = result[:offenses].select { |item| %w[Lint/RedundantDisable Style/WireColor].include?(item.rule) }
      expect(relevant.map { |item| item.location&.line }).to eq([2, 4])
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
