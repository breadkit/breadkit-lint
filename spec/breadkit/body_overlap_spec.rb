# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Layout/BodyOverlap" do
  def check(source, size_mm: [5.08, 5.08])
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
        render: {shape: module, size_mm: #{size_mm.inspect}}
      YAML
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nuse_parts #{definition.inspect}\n#{source}")
      Breadkit::Lint::Engine.new.run([path], only: ["Layout/BodyOverlap"]).first[:offenses]
    end
  end

  it "reports overlapping module bodies once per pair" do
    found = check("part :A, :test_module, at: 'a10'\npart :B, :test_module, at: 'a11'\n")
    expect(found.map(&:rule)).to eq(["Layout/BodyOverlap"])
    expect(found.first.targets[:components]).to contain_exactly("A", "B")
  end

  it "reports overlapping 5 mm LED bodies" do
    found = check("led :D1, anode: 'a10', cathode: 'a11'\nled :D2, anode: 'b11', cathode: 'b12'\n")
    expect(found.map(&:rule)).to eq(["Layout/BodyOverlap"])
    expect(found.first.targets[:components]).to contain_exactly("D1", "D2")
  end

  it "reports an LED body intersecting a module body" do
    found = check("part :M, :test_module, at: 'a10'\nled :D1, anode: 'b11', cathode: 'b12'\n")
    expect(found.map(&:rule)).to eq(["Layout/BodyOverlap"])
    expect(found.first.targets[:components]).to contain_exactly("M", "D1")
  end

  it "does not report touching module edges or separated LED bodies" do
    expect(check("part :A, :test_module, at: 'a10'\npart :B, :test_module, at: 'a12'\n")).to be_empty
    expect(check("led :D1, anode: 'a10', cathode: 'a11'\nled :D2, anode: 'b13', cathode: 'b14'\n")).to be_empty
    expect(check("part :M, :test_module, at: 'a10'\nled :D1, anode: 'b12', cathode: 'b13'\n")).to be_empty
  end

  it "still evaluates LED sizes when older core lacks module bounds" do
    allow_any_instance_of(Breadkit::Component).to receive(:respond_to?).and_call_original
    allow_any_instance_of(Breadkit::Component).to receive(:respond_to?).with(:body_bounds).and_return(false)
    expect(check("part :A, :test_module, at: 'a10'\npart :B, :test_module, at: 'a11'\n")).to be_empty
    expect(check("led :D1, anode: 'a10', cathode: 'a11'\nled :D2, anode: 'b11', cathode: 'b12'\n").map(&:rule))
      .to eq(["Layout/BodyOverlap"])
  end

  it "reports a module crossing a DIP body and ignores a clear gap" do
    overlapping = check("ic :U1, :ne555, at: 'e10'\npart :M, :test_module, at: 'e14'\n", size_mm: [10.16, 7.62])
    expect(overlapping.map(&:rule)).to eq(["Layout/BodyOverlap"])
    expect(overlapping.first.targets[:components]).to contain_exactly("U1", "M")

    clear = check("ic :U1, :ne555, at: 'e10'\npart :M, :test_module, at: 'e20'\n", size_mm: [10.16, 7.62])
    expect(clear).to be_empty
  end
end
