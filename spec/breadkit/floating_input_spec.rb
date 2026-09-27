# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Electrical/FloatingInput" do
  def check(source)
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "input.yml"), <<~YAML)
        id: input_probe
        category: ic
        placement: leads
        pins:
          - {num: 1, name: IN, type: input}
          - {num: 2, name: GND, type: ground}
      YAML
      File.write(File.join(directory, "output.yml"), <<~YAML)
        id: output_probe
        category: ic
        placement: leads
        pins:
          - {num: 1, name: OUT, type: output}
      YAML
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nuse_parts #{File.join(directory, '*.yml').inspect}\npart :U1, :input_probe, pins: %w[a10 f10]\n#{source}")
      Breadkit::Lint::Engine.new.run([path], only: ["Electrical/FloatingInput"]).first[:offenses]
    end
  end

  it "identifies an input connected only to passive wiring" do
    found = check("wire 'b10', 'a11'\n")
    expect(found.map(&:rule)).to eq(["Electrical/FloatingInput"])
    expect(found.first.targets).to include(components: ["U1"], pins: ["U1.IN"], holes: ["a10"])
    expect(found.first.severity).to eq("info")
  end

  it "accepts a direct supply or an output driver" do
    expect(check("supply :USB, voltage: 5, plus: 'B+1', minus: 'B-1'\nwire 'b10', 'B+2'\n")).to be_empty
    expect(check("part :U2, :output_probe, pins: %w[a20]\nwire 'b10', 'b20'\n")).to be_empty
  end

  it "accepts a fixed resistor pull to a driven net, including a resistor chain" do
    source = "supply :USB, voltage: 5, plus: 'B+1', minus: 'B-1'\nresistor :R1, '10k', pins: %w[a11 a12]\nwire 'b10', 'b11'\nwire 'b12', 'B+2'\n"
    expect(check(source)).to be_empty
    expect(check(source.sub("'10k'", "'0'"))).to be_empty
    chain = "resistor :R2, '10k', pins: %w[a13 a14]\nwire 'b12', 'b13'\nwire 'b14', 'B+2'\n"
    expect(check(source.sub("wire 'b12', 'B+2'\n", chain))).to be_empty
  end

  it "does not mistake an unpowered resistor or capacitor for a pull source" do
    resistor = "resistor :R1, '10k', pins: %w[a11 a12]\nwire 'b10', 'b11'\n"
    expect(check(resistor).map(&:rule)).to eq(["Electrical/FloatingInput"])
    capacitor = "supply :USB, voltage: 5, plus: 'B+1', minus: 'B-1'\ncapacitor :C1, '10n', pins: %w[a11 a12]\nwire 'b10', 'b11'\nwire 'b12', 'B+2'\n"
    expect(check(capacitor).map(&:rule)).to eq(["Electrical/FloatingInput"])
  end

  it "leaves an unused input and a bare input to existing pin checks" do
    expect(check("")).to be_empty
    pins = check("part :U2, :input_probe, pins: %w[a20 f20], unused: ['IN']\n")
           .flat_map { |offense| offense.targets[:pins] || [] }
    expect(pins).not_to include("U2.IN")
  end
end
