# Electrical/SupplyOverload

A supply with `current_limit:` is delivering more current than its declared
limit. The value is in amperes: `current_limit: 0.02` means 20 mA.

This check uses the circuit's nominal DC operating point and runs only when
the DC solver supports the whole circuit. It cannot account for module loads
without a DC model. Size the real supply for startup current, tolerances, and
loads that are not modeled here.

Reduce the load or choose a supply with adequate current capacity.
