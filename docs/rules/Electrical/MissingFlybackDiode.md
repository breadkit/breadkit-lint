# Electrical/MissingFlybackDiode

A part explicitly marked with `flags: [needs_flyback_diode]` has named positive and negative coil pins, but no reverse diode bridges their resolved nets. The rule checks a load only when a modeled supply terminal connects to one side and the other side connects to a modeled supply terminal or a non-diode component pin. A jumper ending on an empty strip is ignored. A protective diode must have its cathode on the coil's positive net and its anode on the negative net.

Declare the coil terminals in a custom part definition:

```yaml
id: relay_coil
category: relay
placement: leads
pins:
  - {num: 1, name: POS}
  - {num: 2, name: NEG}
polarity: {positive: POS, negative: NEG}
flags: [needs_flyback_diode]
```

This warning is opt-in because ordinary parts do not identify an inductive coil. A different protection method, such as an internal clamp or snubber, is not modeled as a diode and can be documented with `lint_disable`.
