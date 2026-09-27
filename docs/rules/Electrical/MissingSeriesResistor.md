# Electrical/MissingSeriesResistor

An LED has a known unprotected path across a supply or GPIO output. The check follows conductive diode and transistor paths but cannot prove current through every active device.

```ruby
led :D1, anode: "b10", cathode: "g12"
wire "a10", "B+"
wire "h12", "B-"
```

Add a current-limiting resistor in series with the LED and verify its two pins land on distinct nets.
