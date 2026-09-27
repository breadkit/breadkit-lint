# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Layout/LeadSpan" do
  def check(source)
    Dir.mktmpdir do |directory|
      definition = File.join(directory, "limited_resistor.yml")
      File.write(definition, <<~YAML)
        id: limited_resistor
        category: passive
        placement: leads
        pins:
          - {num: 1, name: "1"}
          - {num: 2, name: "2"}
        max_lead_span_mm: 7.62
      YAML
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nuse_parts #{definition.inspect}\n#{source}")
      Breadkit::Lint::Engine.new.run([path], only: ["Layout/LeadSpan"]).first[:offenses]
    end
  end

  it "flags a declared two-lead part whose holes are farther apart than its maximum span" do
    found = check("part :R1, :limited_resistor, pins: %w[a10 a14]\n")
    expect(found.map(&:rule)).to eq(["Layout/LeadSpan"])
    expect(found.first.targets).to include(components: ["R1"], pins: %w[R1.1 R1.2], holes: %w[a10 a14])
    expect(found.first.message).to include("10.16", "7.62")
  end

  it "accepts a span at the limit and measures diagonal distance" do
    expect(check("part :R1, :limited_resistor, pins: %w[a10 a13]\n")).to be_empty
    found = check("part :R1, :limited_resistor, pins: %w[a10 d13]\n")
    expect(found.map(&:rule)).to eq(["Layout/LeadSpan"])
  end

  it "skips parts without a declared maximum and incomplete placements" do
    expect(check("resistor :R1, '330', pins: %w[a10 a30]\n")).to be_empty
    expect(check("part :R1, :limited_resistor, pins: %w[a10]\n")).to be_empty
  end

  it "skips the check when the installed core lacks the metadata accessor" do
    allow_any_instance_of(Breadkit::PartDef).to receive(:respond_to?).and_call_original
    allow_any_instance_of(Breadkit::PartDef).to receive(:respond_to?).with(:max_lead_span_mm).and_return(false)
    expect(check("part :R1, :limited_resistor, pins: %w[a10 a14]\n")).to be_empty
  end
end
