# Electrical/GpioOvercurrent

A GPIO or output pin with a declared `max_current` carries more current than its rating in the DC model. The limit is in amperes in the part definition. This rule only evaluates a pin that is also an explicit, fixed-voltage `provides` terminal, so the output state and load current are known.

```yaml
id: fixed_driver
category: offboard
placement: offboard
pins:
  - {num: 1, name: OUT, type: gpio, max_current: 0.01}
  - {num: 2, name: GND, type: ground}
provides:
  - {positive: OUT, negative: GND, voltage: 5}
```

Connecting a 100 Ω resistor across `OUT` and `GND` draws 50 mA, which exceeds the 10 mA limit. Increase the load resistance or use a suitable driver.

Ordinary GPIO pins without an explicit output state, unrated pins, and circuits whose DC analysis is unsupported are skipped. The check includes source and sink current and reports each rated pin separately.
