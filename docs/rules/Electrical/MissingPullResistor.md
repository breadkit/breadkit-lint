# Electrical/MissingPullResistor

An explicitly typed input connects to one side of a switch, and the other side reaches a declared supply terminal. With the switch open, the input has no modeled drive or pull resistor. Add a fixed pull-up or pull-down resistor to a supply terminal so the open state is defined.

```ruby
board :half
supply :USB, voltage: 5, plus: "B+1", minus: "B-1"
ic :U1, "74hc08", at: "e10"
part :SW1, :slide_switch_spst, pins: %w[a10 a12]
wire "b12", "B+2"
resistor :R1, "10k", pins: %w[b10 b13]
wire "a13", "B-2"
```

The rule reports an info advisory when the pull resistor is missing. It checks declared `input` pins and switch contacts with an explicit supply on the opposite side. It accepts a direct source, an output driver, or a fixed resistor pull as an anchor. Firmware pull-ups are not modeled, so an intentional internal pull-up can be documented with `lint_disable`.

When this rule applies, its specific finding replaces the general `Electrical/FloatingInput` finding for the same pin. Selecting only `Electrical/FloatingInput` still reports the general finding.
