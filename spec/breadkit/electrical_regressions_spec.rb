# frozen_string_literal: true

require "tmpdir"

RSpec.describe "electrical regressions" do
  def offenses(source, only:)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      Breadkit::Lint::Engine.new.run([path], only: [only]).first[:offenses]
    end
  end

  it "does not warn for a shared reference in dual supplies" do
    source = <<~RUBY
      board :half
      supply :POS, voltage: 5, plus: 'T+1', minus: 'B-1'
      supply :NEG, voltage: 5, plus: 'B-2', minus: 'B+1'
    RUBY
    expect(offenses(source, only: "Electrical/NoCommonGround")).to be_empty
  end

  it "excludes explicitly isolated supplies from common-ground checks" do
    source = <<~RUBY
      board :half
      supply :LOGIC, voltage: 5, plus: 'B+1', minus: 'B-1'
      supply :ISOLATED, voltage: 5, plus: 'T+1', minus: 'T-1', isolated: true
    RUBY
    expect(offenses(source, only: "Electrical/NoCommonGround")).to be_empty
  end

  it "ignores an intentionally reverse-biased LED and an ordinary protection diode" do
    source = <<~RUBY
      board :half
      supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
      led :D1, anode: 'a10', cathode: 'a11', bias: :reverse
      diode :D2, anode: 'a12', cathode: 'a13'
      wire 'b10', 'B-'
      wire 'b11', 'B+'
      wire 'b12', 'B-'
      wire 'b13', 'B+'
    RUBY
    expect(offenses(source, only: "Electrical/ReversePolarity")).to be_empty
  end

  it "respects a declared reverse-voltage limit" do
    Dir.mktmpdir do |directory|
      definition = File.join(directory, "led.yml")
      File.write(definition, "id: led\noverride: true\ncategory: diode\nplacement: leads\nmax_reverse_voltage: 6\npins:\n  - {num: 1, name: anode}\n  - {num: 2, name: cathode}\npolarity: {positive: anode, negative: cathode}\n")
      source = <<~RUBY
        board :half
        use_parts #{definition.inspect}
        supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
        led :D1, anode: 'a10', cathode: 'a11'
        wire 'b10', 'B-'
        wire 'b11', 'B+'
      RUBY
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      checked = Breadkit::Lint::Engine.new.run([path], only: ["Electrical/ReversePolarity"]).first[:offenses]
      expect(checked.map(&:rule)).not_to include("Electrical/ReversePolarity")
      File.write(path, source.sub("voltage: 5", "voltage: 12"))
      checked = Breadkit::Lint::Engine.new.run([path], only: ["Electrical/ReversePolarity"]).first[:offenses]
      expect(checked.map(&:rule)).to include("Electrical/ReversePolarity")
    end
  end

  it "uses offboard power pins in short-circuit analysis" do
    source = <<~RUBY
      board :half
      offboard :UNO, :arduino_uno
      wire 'UNO.5V', 'UNO.GND'
    RUBY
    expect(offenses(source, only: "Electrical/ShortCircuit").map(&:rule)).to include("Electrical/ShortCircuit")
  end

  it "recognizes an LED directly across an offboard power source" do
    source = <<~RUBY
      board :half
      offboard :UNO, :arduino_uno
      led :D1, anode: 'a10', cathode: 'a11'
      wire 'b10', 'UNO.5V'
      wire 'b11', 'UNO.GND'
    RUBY
    expect(offenses(source, only: "Electrical/MissingSeriesResistor").map(&:rule)).to include("Electrical/MissingSeriesResistor")
    reverse = source.sub("'b10', 'UNO.5V'", "'b10', 'UNO.GND'")
                    .sub("'b11', 'UNO.GND'", "'b11', 'UNO.5V'")
    expect(offenses(reverse, only: "Electrical/ReversePolarity").map(&:rule)).to include("Electrical/ReversePolarity")
  end

  it "finds an LED directly between Arduino A0 and ground" do
    source = <<~RUBY
      board :half
      offboard :UNO, :arduino_uno
      led :D1, anode: 'a10', cathode: 'a11'
      wire 'b10', 'UNO.A0'
      wire 'b11', 'UNO.GND'
    RUBY
    expect(offenses(source, only: "Electrical/MissingSeriesResistor").map(&:rule)).to include("Electrical/MissingSeriesResistor")
  end

  it "finds an LED driven from VCC into a GPIO sink" do
    source = <<~RUBY
      board :half
      offboard :UNO, :arduino_uno
      led :D1, anode: 'a10', cathode: 'a11'
      wire 'b10', 'UNO.5V'
      wire 'b11', 'UNO.A0'
    RUBY
    expect(offenses(source, only: "Electrical/MissingSeriesResistor").map(&:rule)).to include("Electrical/MissingSeriesResistor")
  end

  it "uses output_capable metadata without changing a data pin's role" do
    Dir.mktmpdir do |directory|
      definition = File.join(directory, "controller.yml")
      File.write(definition, "id: controller\nplacement: offboard\npins:\n  - {num: 1, name: GND, role: ground}\n  - {num: 2, name: GP0, role: data, output_capable: true}\n")
      source = <<~RUBY
        board :half
        use_parts #{definition.inspect}
        offboard :U, :controller
        led :D1, anode: 'a10', cathode: 'a11'
        wire 'b10', 'U.GP0'
        wire 'b11', 'U.GND'
      RUBY
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      found = Breadkit::Lint::Engine.new.run([path], only: ["Electrical/MissingSeriesResistor"]).first[:offenses]
      expect(found.map(&:rule)).to include("Electrical/MissingSeriesResistor")
    end
  end

  it "checks the high endpoint of a variable supply against part and pin limits" do
    Dir.mktmpdir do |directory|
      definition = File.join(directory, "sensor.yml")
      File.write(definition, "id: sensor\nplacement: offboard\nsupply_range: [2.7, 4.0]\npins:\n  - {num: 1, name: GND, role: ground}\n  - {num: 2, name: VCC, role: power}\n  - {num: 3, name: SIG, role: input, max_voltage: 3.3}\n")
      source = <<~RUBY
        board :half
        use_parts #{definition.inspect}
        offboard :U, :sensor
        supply :P, voltage: 3.0..4.2, plus: 'B+1', minus: 'B-1'
        wire 'U.GND', 'B-'
        wire 'U.VCC', 'B+'
        wire 'U.SIG', 'B+'
      RUBY
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      found = Breadkit::Lint::Engine.new.run([path], only: %w[Electrical/SupplyVoltageRange Electrical/VoltageDomainMismatch]).first[:offenses]
      expect(found.map(&:rule)).to include("Electrical/SupplyVoltageRange", "Electrical/VoltageDomainMismatch")
      via_resistor = source.sub("wire 'U.SIG', 'B+'", "resistor :R1, '1k', pins: %w[a20 a22]\nwire 'b20', 'B+'\nwire 'U.SIG', 'b22'")
      File.write(path, via_resistor)
      found = Breadkit::Lint::Engine.new.run([path], only: ["Electrical/VoltageDomainMismatch"]).first[:offenses]
      expect(found.map(&:rule)).to include("Electrical/VoltageDomainMismatch")
    end
  end
end
