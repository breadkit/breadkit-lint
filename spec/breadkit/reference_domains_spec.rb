# frozen_string_literal: true

require "tmpdir"

RSpec.describe "independent voltage references" do
  def offenses_for(source, rule)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      Breadkit::Lint::Engine.new.run([path], only: [rule]).first[:offenses].map(&:rule)
    end
  end

  it "does not compare LED pin voltages from independent supplies" do
    source = <<~RUBY
      board :half
      supply :ONE, voltage: 5, plus: 'B+1', minus: 'B-1'
      supply :TWO, voltage: 3.3, plus: 'T+1', minus: 'T-1'
      led :D1, anode: 'a10', cathode: 'a12'
      wire 'b10', 'B-2'
      wire 'b12', 'T+2'
    RUBY
    expect(offenses_for(source, "Electrical/ReversePolarity")).to be_empty
  end

  it "does not treat a disconnected GND label as a resistor divider anchor" do
    source = <<~RUBY
      board :half
      supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
      resistor :R1, '1k', pins: %w[a10 a11]
      resistor :R2, '1k', pins: %w[b11 a12]
      net :GND, at: 'b12'
      wire 'b10', 'B+2'
      led :D1, anode: 'c11', cathode: 'c10'
    RUBY
    expect(offenses_for(source, "Electrical/ReversePolarity")).to be_empty
  end

  it "does not compare a module's power and ground across independent supplies" do
    Dir.mktmpdir do |directory|
      part = File.join(directory, "meter.yml")
      File.write(part, <<~YAML)
        id: meter
        category: offboard
        placement: offboard
        pins:
          - {num: 1, name: VCC, role: power}
          - {num: 2, name: GND, role: ground}
        supply_range: [3, 6]
      YAML
      source = <<~RUBY
        board :half
        use_parts #{part.inspect}
        supply :ONE, voltage: 10, plus: 'B+1', minus: 'B-1'
        supply :TWO, voltage: 3.3, plus: 'T+1', minus: 'T-1'
        offboard :M, :meter
        wire 'M.VCC', 'B+2'
        wire 'M.GND', 'T-2'
      RUBY
      expect(offenses_for(source, "Electrical/SupplyVoltageRange")).to be_empty
      shared_reference = source.sub("wire 'M.GND', 'T-2'", "wire 'M.GND', 'B-2'")
      expect(offenses_for(shared_reference, "Electrical/SupplyVoltageRange")).to include("Electrical/SupplyVoltageRange")
    end
  end
end
