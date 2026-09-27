# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Electrical/GpioOvercurrent" do
  def inspect_source(resistance:, limit: 0.01, source: true)
    Dir.mktmpdir do |directory|
      definition = File.join(directory, "driver.yml")
      pin = { "num" => 1, "name" => "OUT", "type" => "gpio" }
      pin["max_current"] = limit if limit
      data = { "id" => "fixed_driver", "category" => "offboard", "placement" => "offboard",
               "pins" => [pin, { "num" => 2, "name" => "GND", "type" => "ground" }] }
      data["provides"] = [{ "positive" => "OUT", "negative" => "GND", "voltage" => 5 }] if source
      File.write(definition, data.to_yaml)
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, <<~RUBY)
        board :half
        use_parts #{definition.inspect}
        offboard :MCU, :fixed_driver
        resistor :R1, '#{resistance}', pins: %w[a10 a11]
        wire 'MCU.OUT', 'b10'
        wire 'MCU.GND', 'b11'
      RUBY
      Breadkit::Lint::Engine.new.run([path], only: ["Electrical/GpioOvercurrent"]).first[:offenses]
    end
  end

  it "flags a rated provided GPIO output above its modeled current limit" do
    found = inspect_source(resistance: "100")
    expect(found.map(&:rule)).to eq(["Electrical/GpioOvercurrent"])
    expect(found.first.targets[:pins]).to eq(["MCU.OUT"])
    expect(found.first.message).to include("50.0 mA", "10.0 mA")
  end

  it "accepts a load below the limit and skips a pin with no rating" do
    expect(inspect_source(resistance: "1k")).to be_empty
    expect(inspect_source(resistance: "100", limit: nil)).to be_empty
  end

  it "does not guess a GPIO state when no output voltage is provided" do
    expect(inspect_source(resistance: "100", source: false)).to be_empty
  end
end
