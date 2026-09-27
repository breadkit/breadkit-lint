# Electrical/FloatingInput

An explicitly typed `input` pin has an electrical connection, but its net has no modeled voltage source, output driver, or fixed resistor path to one. Check whether it needs a pull-up, pull-down, or output connection.

```ruby
board :half
ic :U1, "74hc08", at: "e10"
wire "a10", "a11" # U1.1A is connected to an undriven net
```

The rule follows chains of fixed resistors to a source, and ignores visual wires and pins marked `unused`. Bare pins are covered by `Electrical/FloatingPin`. Only pins whose part definition has `type: input` are checked. This is informational because firmware or hardware internal pulls are not modeled.
