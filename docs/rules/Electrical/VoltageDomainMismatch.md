# Electrical/VoltageDomainMismatch

A signal pin with `max_voltage` metadata is above its allowed voltage relative to the component ground. Add a level shifter or divider, or use a compatible voltage source.

Pins without a declared limit are not checked.
Range endpoints are checked when the signal and ground connect directly to one source. For resistor networks, the check uses the nominal solved potential.
