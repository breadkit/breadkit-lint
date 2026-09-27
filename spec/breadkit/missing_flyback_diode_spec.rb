# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Electrical/MissingFlybackDiode" do
  def inspect_source(source, flag: true, polarity: true)
    Dir.mktmpdir do |directory|
      definition = [
        "id: relay_coil",
        "category: relay",
        "placement: leads",
        "pins:",
        "  - {num: 1, name: POS}",
        "  - {num: 2, name: NEG}",
        ("flags: [needs_flyback_diode]" if flag),
        ("polarity: {positive: POS, negative: NEG}" if polarity)
      ].compact.join("\n")
      file = File.join(directory, "relay.yml")
      File.write(file, "#{definition}\n")
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nuse_parts #{file.inspect}\n#{source}")
      Breadkit::Lint::Engine.new.run([path], only: ["Electrical/MissingFlybackDiode"]).first[:offenses]
    end
  end

  let(:powered_coil) do
    <<~RUBY
      supply :V, voltage: 5, plus: "T+1", minus: "T-1"
      part :K1, :relay_coil, pins: %w[a10 a12]
      wire "K1.POS", "T+2"
      wire "K1.NEG", "T-2"
    RUBY
  end

  it "warns for an explicitly inductive load without a reverse diode" do
    offenses = inspect_source(powered_coil)

    expect(offenses.map(&:rule)).to eq(["Electrical/MissingFlybackDiode"])
    expect(offenses.first.severity).to eq("warning")
    expect(offenses.first.targets[:components]).to eq(["K1"])
    expect(offenses.first.targets[:pins]).to contain_exactly("K1.POS", "K1.NEG")
  end

  it "accepts a diode with cathode on coil positive and anode on coil negative" do
    source = powered_coil + "diode :D1, anode: 'b12', cathode: 'b10'\n"
    expect(inspect_source(source)).to be_empty
  end

  it "does not accept a forward diode or a diode on unrelated nets" do
    forward = powered_coil + "diode :D1, anode: 'b10', cathode: 'b12'\n"
    unrelated = powered_coil + "diode :D1, anode: 'b12', cathode: 'b14'\n"
    expect(inspect_source(forward).map(&:rule)).to eq(["Electrical/MissingFlybackDiode"])
    expect(inspect_source(unrelated).map(&:rule)).to eq(["Electrical/MissingFlybackDiode"])
  end

  it "skips ordinary parts, unspecified coil polarity, and unpowered coils" do
    expect(inspect_source(powered_coil, flag: false)).to be_empty
    expect(inspect_source(powered_coil, polarity: false)).to be_empty
    unpowered = "part :K1, :relay_coil, pins: %w[a10 a12]\n"
    expect(inspect_source(unpowered)).to be_empty
  end

  it "does not warn when the other coil terminal is unconnected" do
    positive_only = <<~RUBY
      supply :V, voltage: 5, plus: "T+1", minus: "T-1"
      part :K1, :relay_coil, pins: %w[a10 a12]
      wire "K1.POS", "T+2"
    RUBY
    negative_only = <<~RUBY
      supply :V, voltage: 5, plus: "T+1", minus: "T-1"
      part :K1, :relay_coil, pins: %w[a10 a12]
      wire "K1.NEG", "T-2"
    RUBY

    expect(inspect_source(positive_only)).to be_empty
    expect(inspect_source(negative_only)).to be_empty
  end

  it "recognizes a coil switched through a transistor as an active load" do
    source = <<~RUBY
      supply :V, voltage: 5, plus: "T+1", minus: "T-1"
      part :K1, :relay_coil, pins: %w[a10 a12]
      transistor :Q1, "BC547", pins: %w[a20 a21 a22]
      wire "K1.POS", "T+2"
      wire "K1.NEG", "Q1.collector"
      wire "Q1.emitter", "T-2"
    RUBY

    expect(inspect_source(source).map(&:rule)).to eq(["Electrical/MissingFlybackDiode"])
  end

  it "ignores a jumper that ends on an otherwise empty strip" do
    source = <<~RUBY
      supply :V, voltage: 5, plus: "T+1", minus: "T-1"
      part :K1, :relay_coil, pins: %w[a10 a12]
      wire "K1.POS", "T+2"
      wire "K1.NEG", "a20"
    RUBY

    expect(inspect_source(source)).to be_empty
  end

  it "does not treat a diode alone as a powered return path" do
    source = <<~RUBY
      supply :V, voltage: 5, plus: "T+1", minus: "T-1"
      part :K1, :relay_coil, pins: %w[a10 a12]
      wire "K1.POS", "T+2"
      diode :D1, anode: "b10", cathode: "b12"
    RUBY

    expect(inspect_source(source)).to be_empty
  end
end
