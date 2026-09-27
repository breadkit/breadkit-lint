# Layout/HoleCovered

A module or DIP body covers a hole used by another component lead or an electrical wire endpoint. The check uses the module's `render.size_mm`, or a complete DIP pin arrangement, and physical hole positions. Move the lead or wire endpoint to a visible hole; a hole on the same conductive strip is fine if it is outside the body.

```ruby
board :half
part :U1, :pico, at: "d1"
resistor :R1, "330", pins: %w[e10 a25] # e10 is under U1
```

The owner's own pins, holes on the body boundary, and visual wires (`electrical: false`) are ignored. A standard DIP sits in the breadboard ravine, so it normally covers no holes. Module checks are skipped when an older Breadkit version cannot provide body geometry.
