# Layout/LeadSpan

A two-lead part is placed farther apart than its declared `max_lead_span_mm`. The rule measures the straight-line distance between the two board holes using the board's 2.54 mm pitch.

```yaml
id: limited_resistor
category: passive
placement: leads
pins:
  - {num: 1, name: "1"}
  - {num: 2, name: "2"}
max_lead_span_mm: 7.62
```

```ruby
board :half
use_parts "limited_resistor.yml"
part :R1, :limited_resistor, pins: %w[a10 a14] # 10.16 mm exceeds 7.62 mm
```

Move the holes closer together or choose a part with a suitable lead span. Parts without declared `max_lead_span_mm` and incomplete placements are skipped; the rule does not assume a generic lead length.
