# Electrical/MissingSeriesResistor

An LED has a known unprotected path across a supply or GPIO output. The check follows conductive diode and transistor paths but cannot prove current through every active device.

```ruby
led :D1, anode: "b10", cathode: "g12"
wire "a10", "B+"
wire "h12", "B-"
```

Add a current-limiting resistor in series with the LED and verify its two pins land on distinct nets.

When the part definition declares `forward_voltage` (volts) and `max_forward_current` (amperes), and the LED is directly across one known supply, the report suggests the next E12 resistor value above `(maximum supply voltage - forward voltage) / maximum current`. This is an estimate from the declared values. Check the LED datasheet, tolerances, and resistor power rating before building the circuit. The report omits a number when any input is unknown.
