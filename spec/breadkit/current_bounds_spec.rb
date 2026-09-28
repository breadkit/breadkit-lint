# frozen_string_literal: true

require "tmpdir"

RSpec.describe "worst-case current checks" do
  def lint(source, only:)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      Breadkit::Lint::Engine.new.run([path], only: only).first[:offenses]
    end
  end

  let(:resistor_circuit) do
    <<~RUBY
      board :half
      supply :BAT, voltage: 3.0..4.2, plus: 'B+1', minus: 'B-1', current_limit: 0.04
      resistor :R1, '100 5%', pins: %w[a10 a11]
      wire 'b10', 'B+2'
      wire 'b11', 'B-2'
    RUBY
  end

  it "reports a supply whose worst-case load exceeds its limit" do
    findings = lint(resistor_circuit, only: ["Electrical/SupplyOverload"])
    expect(findings.map(&:rule)).to eq(["Electrical/SupplyOverload"])
    expect(findings.first.message).to include("44.21 mA", "40.0 mA")
  end

  it "uses resistor tolerance when checking a provided GPIO" do
    Dir.mktmpdir do |directory|
      part = File.join(directory, "driver.yml")
      File.write(part, <<~YAML)
        id: fixed_driver
        category: offboard
        placement: offboard
        pins:
          - {num: 1, name: OUT, type: gpio, max_current: 0.052}
          - {num: 2, name: GND, type: ground}
        provides:
          - {positive: OUT, negative: GND, voltage: 5}
      YAML
      source = <<~RUBY
        board :half
        use_parts #{part.inspect}
        offboard :MCU, :fixed_driver
        resistor :R1, '100 5%', pins: %w[a10 a11]
        wire 'MCU.OUT', 'b10'
        wire 'MCU.GND', 'b11'
      RUBY
      found = lint(source, only: ["Electrical/GpioOvercurrent"])
      expect(found.map(&:rule)).to eq(["Electrical/GpioOvercurrent"])
      expect(found.first.message).to include("52.63 mA", "52.0 mA")
    end
  end

  it "reports a diode current endpoint as an estimate" do
    Dir.mktmpdir do |directory|
      part = File.join(directory, "led.yml")
      File.write(part, <<~YAML)
        id: rated_led
        category: diode
        placement: leads
        flags: [needs_series_resistor]
        pins:
          - {num: 1, name: anode}
          - {num: 2, name: cathode}
        polarity: {positive: anode, negative: cathode}
        forward_voltage: 2
        max_forward_current: 0.02
      YAML
      source = <<~RUBY
        board :half
        use_parts #{part.inspect}
        supply :BAT, voltage: 3.0..4.2, plus: 'B+1', minus: 'B-1'
        resistor :R1, '100 5%', pins: %w[a10 a11]
        part :D1, :rated_led, pins: {anode: 'a12', cathode: 'a13'}
        wire 'b10', 'B+2'
        wire 'b11', 'b12'
        wire 'b13', 'B-2'
      RUBY
      found = lint(source, only: ["Electrical/LedOvercurrent"])
      expect(found.map(&:rule)).to eq(["Electrical/LedOvercurrent"])
      expect(found.first.message).to include("endpoint")
    end
  end

  it "checks the built-in datasheet-rated LED model" do
    source = <<~RUBY
      board :half
      supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
      resistor :R1, '100', pins: %w[a10 a11]
      part :D1, :kingbright_wp7113id, pins: {anode: 'a12', cathode: 'a13'}
      wire 'b10', 'B+2'
      wire 'b11', 'b12'
      wire 'b13', 'B-2'
    RUBY
    found = lint(source, only: ["Electrical/LedOvercurrent"])
    expect(found.map(&:rule)).to eq(["Electrical/LedOvercurrent"])
    expect(found.first.message).to include("30.0 mA")
  end

  it "warns when too many uncertain values prevent a complete bound" do
    source = <<~RUBY
      board :half
      supply :BAT, voltage: 3.0..4.2, plus: 'B+1', minus: 'B-1', current_limit: 0.04
      10.times do |index|
        resistor "R\#{index}", '100 5%', pins: ["a\#{index * 2 + 1}", "a\#{index * 2 + 2}"]
      end
    RUBY
    findings = lint(source, only: ["Electrical/DcBoundsIncomplete"])
    expect(findings.map(&:rule)).to eq(["Electrical/DcBoundsIncomplete"])
    expect(findings.first.message).to include("too complex")
  end

  it "checks resistor power at an interior tolerance value" do
    source = <<~RUBY
      board :half
      supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
      resistor :R1, '800 50% 0.00622W', pins: %w[a10 a11]
      resistor :R2, '1k', pins: %w[a12 a13]
      wire 'b10', 'B+2'
      wire 'b11', 'b12'
      wire 'b13', 'B-2'
    RUBY
    found = lint(source, only: ["Electrical/ResistorPowerRating"])
    expect(found.map(&:rule)).to eq(["Electrical/ResistorPowerRating"])
    expect(found.first.message).to include("0.00625 W")
  end
end
