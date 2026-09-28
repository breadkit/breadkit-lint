# Electrical/ResistorPowerRating

Checks resistors with an explicit power rating, such as `resistor :R1, "100 1/4W", pins: %w[a1 a2]`. Complete DC bounds account for declared source voltage ranges and resistor tolerances across the network, including power peaks at interior resistance values. Diode circuits use endpoint estimates. If complete bounds are unavailable, the rule falls back to a known voltage estimate and the lowest allowed resistance, while `Electrical/DcBoundsIncomplete` warns that a passing check does not establish safety.

Choose a resistor with a higher power rating or increase its resistance when the estimated dissipation exceeds the rating.
