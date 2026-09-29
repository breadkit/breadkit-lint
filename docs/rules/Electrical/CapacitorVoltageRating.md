# Electrical/CapacitorVoltageRating

Checks electrolytic capacitors with an explicit voltage rating, such as `electrolytic :C1, "10u 16V", plus: "a1", minus: "a2"`. When DC bounds are available, the check uses the largest paired voltage difference across the capacitor at each source and resistor tolerance scenario, including resistor networks. Otherwise, it uses the highest known voltage estimate. Diode circuits use endpoint estimates; `Electrical/DcBoundsIncomplete` warns when a passing check does not establish safety across the full range.

Use a capacitor rated above the voltage it can see in the circuit.
