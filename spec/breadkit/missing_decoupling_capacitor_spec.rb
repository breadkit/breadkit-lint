# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Electrical/MissingDecouplingCapacitor" do
  def inspect_source(source)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      Breadkit::Lint::Engine.new.run([path], only: ["Electrical/MissingDecouplingCapacitor"]).first[:offenses]
    end
  end

  let(:powered_ic) do
    <<~RUBY
      board :half
      supply :V, voltage: 5, plus: "T+1", minus: "T-1"
      ic :U1, :ne555, at: "e20"
      wire "U1.VCC", "T+2"
      wire "U1.GND", "T-2"
    RUBY
  end

  it "advises once for a powered IC with no capacitor between its supply nets" do
    offenses = inspect_source(powered_ic)

    expect(offenses.map(&:rule)).to eq(["Electrical/MissingDecouplingCapacitor"])
    expect(offenses.first.severity).to eq("info")
    expect(offenses.first.targets[:components]).to eq(["U1"])
    expect(offenses.first.targets[:pins]).to contain_exactly("U1.VCC", "U1.GND")
  end

  it "accepts a ceramic or electrolytic capacitor bridging the same nets" do
    %w[capacitor electrolytic].each do |kind|
      source = powered_ic + <<~RUBY
        #{kind} :C1, "100n", pins: %w[a10 a12]
        wire "b10", "T+3"
        wire "b12", "T-3"
      RUBY
      expect(inspect_source(source)).to be_empty, kind
    end
  end

  it "does not count a capacitor connected to another net" do
    source = powered_ic + <<~RUBY
      capacitor :C1, "100n", pins: %w[a10 a12]
      wire "b10", "T+3"
    RUBY

    expect(inspect_source(source).map(&:rule)).to eq(["Electrical/MissingDecouplingCapacitor"])
  end

  it "skips unpowered ICs and offboard modules with their own power pins" do
    unpowered = "board :half\nic :U1, :ne555, at: 'e20'\n"
    expect(inspect_source(unpowered)).to be_empty

    module_source = <<~RUBY
      board :half
      supply :V, voltage: 5, plus: "T+1", minus: "T-1"
      offboard :M, :arduino_uno
      wire "M.5V", "T+2"
      wire "M.GND", "T-2"
    RUBY
    expect(inspect_source(module_source)).to be_empty
  end
end
