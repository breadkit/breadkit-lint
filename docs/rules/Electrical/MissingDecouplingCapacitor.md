# Electrical/MissingDecouplingCapacitor

A part categorized as an `ic` has explicit power and ground pins connected across a modeled voltage source, but no capacitor bridges those resolved nets. Place a suitable decoupling capacitor across the IC's supply pins.

This is an informational advisory. It excludes offboard modules, which may contain their own decoupling, and does not assess capacitor value or physical distance from the IC. Unpowered pins are handled by `Electrical/PowerPinUnconnected` instead.
