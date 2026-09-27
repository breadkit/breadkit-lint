# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Layout/HoleCovered" do
  def check(source)
    Dir.mktmpdir do |directory|
      definition = File.join(directory, "module.yml")
      File.write(definition, <<~YAML)
        id: test_module
        category: module
        placement: footprint
        pins:
          - {num: 1, name: P1}
          - {num: 2, name: P2}
        footprint:
          "1": [0, 0]
          "2": [0, 2]
        render: {shape: module, size_mm: [5.08, 5.08]}
      YAML
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nuse_parts #{definition.inspect}\npart :M, :test_module, at: 'a10'\n#{source}")
      Breadkit::Lint::Engine.new.run([path], only: ["Layout/HoleCovered"]).first[:offenses]
    end
  end

  it "flags another component lead under a module body" do
    found = check("resistor :R1, '330', pins: %w[b10 e20]\n")
    expect(found.map(&:rule)).to include("Layout/HoleCovered")
    expect(found.first.targets).to include(components: %w[M R1], holes: ["b10"])
  end

  it "flags an electrical wire endpoint under a module body" do
    found = check("wire 'b10', 'e20'\n")
    expect(found.map(&:rule)).to include("Layout/HoleCovered")
    expect(found.first.targets).to include(components: ["M"], wires: ["W1"], holes: ["b10"])
  end

  it "leaves boundary holes, visible holes on the same strip, and visual wires alone" do
    expect(check("resistor :R1, '330', pins: %w[b9 e20]\n")).to be_empty
    expect(check("wire 'e10', 'e20'\n")).to be_empty
    expect(check("wire 'b10', 'e20', electrical: false\n")).to be_empty
    expect(check("")).to be_empty
  end

  it "skips body checks when the installed core lacks body geometry" do
    allow_any_instance_of(Breadkit::Component).to receive(:respond_to?).and_call_original
    allow_any_instance_of(Breadkit::Component).to receive(:respond_to?).with(:body_bounds).and_return(false)
    expect(check("resistor :R1, '330', pins: %w[b10 e20]\n")).to be_empty
  end
end
