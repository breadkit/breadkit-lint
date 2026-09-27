board :half

document.part_definitions << {
  "id" => "fixed_driver",
  "category" => "offboard",
  "placement" => "offboard",
  "pins" => [
    { "num" => 1, "name" => "OUT", "type" => "gpio", "max_current" => 0.01 },
    { "num" => 2, "name" => "GND", "type" => "ground" }
  ],
  "provides" => [{ "positive" => "OUT", "negative" => "GND", "voltage" => 5 }]
}

offboard :MCU, :fixed_driver
resistor :R1, "100", pins: %w[a10 a11]
wire "MCU.OUT", "b10"
wire "MCU.GND", "b11"
