# frozen_string_literal: true

require "tmpdir"

RSpec.describe "worst-case voltage checks" do
  def lint(source, parts:, only:)
    Dir.mktmpdir do |directory|
      definition = File.join(directory, "sensor.yml")
      path = File.join(directory, "circuit.bk.rb")
      File.write(definition, parts)
      File.write(path, "use_parts #{definition.inspect}\n#{source}")
      Breadkit::Lint::Engine.new.run([path], only: only).first[:offenses]
    end
  end

  let(:sensor) do
    <<~YAML
      id: sensor
      placement: offboard
      provides: []
      supply_range: [1.0, 2.1]
      pins:
        - {num: 1, name: GND, role: ground}
        - {num: 2, name: VCC, role: power}
        - {num: 3, name: SIG, role: input, max_voltage: 2.1}
    YAML
  end

  let(:divider) do
    <<~RUBY
      board :half
      offboard :U, :sensor
      supply :P, voltage: 3.0..5.0, plus: 'B+1', minus: 'B-1'
      resistor :R1, '1k', pins: %w[a10 a11]
      resistor :R2, '1k', pins: %w[a12 a13]
      wire 'b10', 'B+'
      wire 'b11', 'b12'
      wire 'b13', 'B-'
      wire 'U.GND', 'B-'
      wire 'U.VCC', 'c11'
      wire 'U.SIG', 'd11'
    RUBY
  end

  it "checks source endpoints across a resistor divider for supply and signal limits" do
    findings = lint(divider, parts: sensor, only: %w[Electrical/SupplyVoltageRange Electrical/VoltageDomainMismatch])
    expect(findings.map(&:rule)).to contain_exactly("Electrical/SupplyVoltageRange", "Electrical/VoltageDomainMismatch")
    expect(findings.map(&:message).join).to include("2.5")
  end

  it "uses paired voltage differences to avoid a false signal overvoltage" do
    source = divider.sub("wire 'U.GND', 'B-'", <<~RUBY.chomp)
      resistor :R3, '1k', pins: %w[a20 a21]
      resistor :R4, '1k', pins: %w[a22 a23]
      wire 'b20', 'B+'
      wire 'b21', 'b22'
      wire 'b23', 'B-'
      wire 'U.GND', 'c21'
    RUBY
    findings = lint(source, parts: sensor.sub("max_voltage: 2.1", "max_voltage: 0.2"), only: ["Electrical/VoltageDomainMismatch"])
    expect(findings).to be_empty
  end

  it "checks a capacitor rating at the high divider endpoint" do
    source = divider.sub("wire 'U.SIG', 'd11'", "electrolytic :C1, '10u 2.2V', plus: 'e11', minus: 'e13'")
    findings = lint(source, parts: sensor, only: ["Electrical/CapacitorVoltageRating"])
    expect(findings.map(&:rule)).to eq(["Electrical/CapacitorVoltageRating"])
    expect(findings.first.message).to include("2.5 V")
  end

  it "warns when an unmodeled sensor prevents voltage bounds" do
    findings = lint(divider, parts: sensor.sub("provides: []\n", ""), only: ["Electrical/DcBoundsIncomplete"])
    expect(findings.map(&:rule)).to eq(["Electrical/DcBoundsIncomplete"])
    expect(findings.first.message).to include("voltage check does not establish safety")
  end
end
