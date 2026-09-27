# Layout/BodyOverlap

Two component bodies intersect even though their leads use different holes. This rule checks rectangular modules with `render.size_mm` and circular 5 mm LED bodies (`led_5mm` or `rgb_led_5mm`). Touching edges do not count as an overlap.

```ruby
board :half
led :D1, anode: "a10", cathode: "a11"
led :D2, anode: "b11", cathode: "b12"
```

Move one part until its body clears the other. Other component shapes, including DIP bodies without physical dimensions, are not checked. Module comparisons are skipped when the installed Breadkit version cannot provide body bounds.
