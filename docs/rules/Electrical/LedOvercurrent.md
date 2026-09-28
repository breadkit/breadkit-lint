# Electrical/LedOvercurrent

Checks an LED whose part definition declares `max_forward_current`. The DC model estimates its current using the supply, resistors, and that part's optional `forward_voltage` and `on_resistance` values. The rule reports a current above the declared limit.

The rule skips circuits with an indeterminate or unsupported DC operating point. Add an explicit series resistor and use a part-specific current rating; a generic LED has no assumed safe current limit.

The current estimate uses nominal supply voltage and resistance. It does not calculate the maximum current from a supply voltage range or resistor tolerance; check those extremes before choosing a resistor.
