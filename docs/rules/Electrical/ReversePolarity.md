# Electrical/ReversePolarity

The positive pin of a polarized part is at a lower known potential than its negative pin.

```ruby
led :D1, anode: "b10", cathode: "g12"
# Connect anode to GND and cathode to VCC.
```

Swap accidental reverse connections. For an intentional reverse-biased LED, use `bias: :reverse`. Part definitions can declare `max_reverse_voltage`; ordinary diodes are not flagged by this rule.
