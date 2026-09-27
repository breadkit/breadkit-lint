# Electrical/MissingBaseResistor

A pin explicitly typed `output` shares a conductive net with a part categorized as a transistor's explicit `base` pin. There is no series resistor between those two pins. Add a suitable resistor between the driver output and the transistor base.

This is an informational advisory. Bidirectional `gpio` pins, power rails, and resistor bias networks are excluded because their drive state or purpose cannot be inferred from the circuit model. Transistor parts without an explicit `base` pin are also excluded.
