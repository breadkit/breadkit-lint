# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Electrical/MissingPullResistor" do
  def inspect_source(extra, only: ["Electrical/MissingPullResistor"])
    Dir.mktmpdir do |directory|
      definition = File.join(directory, "input.yml")
      File.write(definition, <<~YAML)
        id: input_probe
        category: ic
        placement: leads
        pins:
          - {num: 1, name: IN, type: input}
      YAML
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, <<~RUBY)
        board :half
        use_parts #{definition.inspect}
        supply :USB, voltage: 5, plus: 'B+1', minus: 'B-1'
        part :U1, :input_probe, pins: %w[c10]
        part :SW1, :slide_switch_spst, pins: %w[a10 a12]
        wire 'b12', 'B+2'
        #{extra}
      RUBY
      Breadkit::Lint::Engine.new.run([path], only: only).first[:offenses]
    end
  end

  it "advises when a supply-switch input has no pull in the open state" do
    found = inspect_source("")
    expect(found.map(&:rule)).to eq(["Electrical/MissingPullResistor"])
    expect(found.first.severity).to eq("info")
    expect(found.first.targets[:pins]).to include("U1.IN")
    expect(found.first.targets[:components]).to contain_exactly("U1", "SW1")
  end

  it "accepts a fixed pull to ground or a direct supply connection" do
    pull = "resistor :R1, '10k', pins: %w[d10 a13]\nwire 'b13', 'B-2'\n"
    expect(inspect_source(pull)).to be_empty
    expect(inspect_source("wire 'd10', 'B-2'\n")).to be_empty
  end

  it "does not infer a pull requirement for a switch without a source" do
    source = <<~RUBY
      board :half
      part :SW1, :slide_switch_spst, pins: %w[a10 a12]
    RUBY
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      expect(Breadkit::Lint::Engine.new.run([path], only: ["Electrical/MissingPullResistor"]).first[:offenses]).to be_empty
    end
  end

  it "keeps one specific finding when both floating-input rules are selected" do
    expect(inspect_source("", only: %w[Electrical/FloatingInput Electrical/MissingPullResistor]).map(&:rule))
      .to eq(["Electrical/MissingPullResistor"])
    expect(inspect_source("", only: ["Electrical/FloatingInput"]).map(&:rule)).to eq(["Electrical/FloatingInput"])
  end
end
