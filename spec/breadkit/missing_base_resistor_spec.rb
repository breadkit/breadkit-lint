# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Electrical/MissingBaseResistor" do
  def inspect_source(source)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      Breadkit::Lint::Engine.new.run([path], only: ["Electrical/MissingBaseResistor"]).first[:offenses]
    end
  end

  let(:parts) do
    <<~RUBY
      board :half
      ic :U1, "74hc14", at: "e10"
      transistor :Q1, "BC547", pins: %w[a25 a26 a27]
    RUBY
  end

  it "advises when a declared output drives a transistor base on the same net" do
    offenses = inspect_source(parts + "wire 'U1.1Y', 'Q1.base'\n")

    expect(offenses.map(&:rule)).to eq(["Electrical/MissingBaseResistor"])
    expect(offenses.first.severity).to eq("info")
    expect(offenses.first.targets[:components]).to contain_exactly("Q1", "U1")
    expect(offenses.first.targets[:pins]).to contain_exactly("Q1.base", "U1.1Y")
  end

  it "accepts a resistor in series between output and base" do
    source = parts + <<~RUBY
      resistor :R1, "1k", pins: %w[a21 a22]
      wire "U1.1Y", "b21"
      wire "Q1.base", "b22"
    RUBY

    expect(inspect_source(source)).to be_empty
  end

  it "ignores supply bias and bidirectional GPIO without an explicit output role" do
    bias = parts + <<~RUBY
      supply :V, voltage: 5, plus: "T+1", minus: "T-1"
      resistor :R1, "10k", pins: %w[a21 a22]
      resistor :R2, "10k", pins: %w[a22 a23]
      wire "b21", "T+2"
      wire "b23", "T-2"
      wire "Q1.base", "c22"
    RUBY
    expect(inspect_source(bias)).to be_empty

    gpio = parts + "offboard :UNO, :arduino_uno\nwire 'UNO.D13', 'Q1.base'\n"
    expect(inspect_source(gpio)).to be_empty
  end

  it "ignores parts without an explicit transistor base definition" do
    source = <<~RUBY
      board :half
      File.write(File.join(__dir__, 'unknown.yml'), "id: unknown\\ncategory: transistor\\nplacement: leads\\npins:\\n  - {num: 1, name: E}\\n  - {num: 2, name: B}\\n  - {num: 3, name: C}\\n")
      use_parts File.join(__dir__, 'unknown.yml')
      ic :U1, '74hc14', at: 'e10'
      part :Q1, :unknown, pins: %w[a25 a26 a27]
      wire 'U1.1Y', 'Q1.B'
    RUBY

    expect(inspect_source(source)).to be_empty
  end
end
