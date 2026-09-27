# Electrical/CapacitorVoltageRating

Checks electrolytic capacitors with an explicit voltage rating, such as `electrolytic :C1, "10u 16V", plus: "a1", minus: "a2"`. The check uses the highest known voltage across the capacitor, including both endpoints of a ranged supply when connected directly.

Use a capacitor rated above the voltage it can see in the circuit.
