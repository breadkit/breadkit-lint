# Electrical/SupplyOverload

A supply with `current_limit:` is delivering more current than its declared
limit. The value is in amperes: `current_limit: 0.02` means 20 mA.

The check includes declared source voltage ranges and resistor tolerances when
complete DC bounds are available. It runs only when the DC solver supports the
whole circuit. Diode circuits use endpoint estimates, and
`Electrical/DcBoundsIncomplete` warns when a passing check does not establish
safety across the full range. The model cannot account for module loads without
a DC model. Size the real supply for startup current and unmodeled loads.

Reduce the load or choose a supply with adequate current capacity.
