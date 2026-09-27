# Electrical/ResistorPowerRating

Checks resistors with an explicit power rating, such as `resistor :R1, "100 1/4W", pins: %w[a1 a2]`. The check uses the voltage across the resistor and the lowest resistance allowed by an optional tolerance (`"100 5% 1/4W"`). A resistor network is evaluated at the nominal supply voltage unless the resistor is directly across a ranged supply.

Choose a resistor with a higher power rating or increase its resistance when the estimated dissipation exceeds the rating.
