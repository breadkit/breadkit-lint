# Electrical/VoltageDomainMismatch

A signal pin with `max_voltage` metadata is above its allowed voltage relative to the component ground. Add a level shifter or divider, or use a compatible voltage source.

Pins without a declared limit are not checked.
When DC bounds are available, the check uses the paired voltage difference between the signal and ground pins at each source and resistor tolerance scenario. This includes resistor networks. Direct source endpoints remain checkable when the full DC model is unavailable. Diode circuits use endpoint estimates; `Electrical/DcBoundsIncomplete` warns when a passing check does not establish safety across the full range.
