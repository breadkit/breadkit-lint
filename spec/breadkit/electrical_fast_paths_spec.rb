# frozen_string_literal: true

RSpec.describe "Electrical/ShortCircuit without a source" do
  it "skips potential solving when the circuit has no voltage sources" do
    circuit = double("circuit", voltage_sources: [])
    expect(circuit).not_to receive(:potentials)
    state = Breadkit::State.new(name: "SW1", closed_switches: [[:switch, ["1", "2"]]])
    checks = Breadkit::Lint::Checks.new(Breadkit::Lint::Config.new, {})

    expect(checks.short_circuit(circuit, Breadkit::Lint::Rules::Electrical::ShortCircuit, state)).to be_empty
  end
end

RSpec.describe "Electrical/FloatingInput without an input" do
  it "skips network anchoring when no component has an input pin" do
    circuit = double("circuit", components: {})
    state = Breadkit::State.new(name: nil, closed_switches: [])
    checks = Breadkit::Lint::Checks.new(Breadkit::Lint::Config.new, {})
    expect(checks).not_to receive(:anchored_input_nets)

    expect(checks.floating_inputs(circuit, Breadkit::Lint::Rules::Electrical::FloatingInput, state)).to be_empty
  end
end

RSpec.describe "source-free potential ranges" do
  it "does not solve node potentials without a voltage source" do
    circuit = double("circuit", voltage_sources: [])
    expect(circuit).not_to receive(:potentials)
    checks = Breadkit::Lint::Checks.new(Breadkit::Lint::Config.new, {})
    state = Breadkit::State.new(name: nil, closed_switches: [])

    expect(checks.potential_ranges(circuit, state)).to eq([{}, {}])
  end
end

RSpec.describe "unrated component checks" do
  let(:checks) { Breadkit::Lint::Checks.new(Breadkit::Lint::Config.new, {}) }
  let(:state) { Breadkit::State.new(name: nil, closed_switches: []) }
  let(:circuit) { double("circuit", components: {}) }

  it "skips potential solving when no component declares a supply range" do
    expect(circuit).not_to receive(:potentials)
    expect(checks.supply_ranges(circuit, Breadkit::Lint::Rules::Electrical::SupplyVoltageRange, state)).to be_empty
  end

  it "skips potential solving when no power pins are present" do
    allow(circuit).to receive(:voltage_sources).and_return([])
    expect(circuit).not_to receive(:potentials)
    expect(checks.power_pins(circuit, Breadkit::Lint::Rules::Electrical::PowerPinUnconnected, state)).to be_empty
  end

  it "skips DC analysis when no pin declares a voltage limit" do
    allow(circuit).to receive(:voltage_sources).and_return([])
    expect(circuit).not_to receive(:dc_analysis)
    expect(checks.voltage_domain_mismatches(circuit, Breadkit::Lint::Rules::Electrical::VoltageDomainMismatch, state)).to be_empty
  end

  it "skips DC analysis when no LED current rating is present" do
    expect(circuit).not_to receive(:dc_analysis)
    expect(checks.led_overcurrent(circuit, Breadkit::Lint::Rules::Electrical::LedOvercurrent, state)).to be_empty
  end

  it "skips DC analysis when no output current rating is present" do
    expect(circuit).not_to receive(:dc_analysis)
    expect(checks.gpio_overcurrent(circuit, Breadkit::Lint::Rules::Electrical::GpioOvercurrent, state)).to be_empty
  end
end

RSpec.describe "Electrical/SupplyOverload without a limit" do
  it "skips DC analysis when no supply declares a current limit" do
    circuit = double("circuit", supplies: [])
    expect(circuit).not_to receive(:dc_analysis)
    checks = Breadkit::Lint::Checks.new(Breadkit::Lint::Config.new, {})
    state = Breadkit::State.new(name: nil, closed_switches: [])

    expect(checks.supply_overloads(circuit, Breadkit::Lint::Rules::Electrical::SupplyOverload, state)).to be_empty
  end
end
