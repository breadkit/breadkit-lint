# Electrical/LedOvercurrent

Checks an LED whose part definition declares `max_forward_current`. This includes model-specific diode parts with the `needs_series_resistor` flag. The DC model estimates its current using the supply, resistors, and that part's optional `forward_voltage` and `on_resistance` values. The rule reports a current above the declared limit.

The rule skips circuits with an indeterminate or unsupported DC operating point. Add an explicit series resistor and use a part-specific current rating; a generic LED has no assumed safe current limit.

The check uses source voltage ranges and resistor tolerances when complete DC bounds are available. Diode switching can put the true maximum between sampled endpoints. Such a finding is marked as an endpoint estimate, and `Electrical/DcBoundsIncomplete` warns that a passing check does not establish safety.
