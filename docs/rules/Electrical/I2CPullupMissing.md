# Electrical/I2CPullupMissing

An addressed component with both `SDA` and `SCL` pins has an externally connected bus line without a modeled positive resistance to a declared supply's positive net. The rule checks each line separately and ignores unconnected or unpowered buses.

Add a fixed pull-up resistor from each bus line to the appropriate supply rail. This is an informational advisory: a module may already contain pull-up resistors, or firmware may enable internal pull-ups, and the circuit model cannot currently represent those facts.
