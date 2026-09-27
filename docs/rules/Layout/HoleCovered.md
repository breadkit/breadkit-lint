# Layout/HoleCovered

A module body covers a hole used by another component lead or an electrical wire endpoint. The check uses the module's `render.size_mm` and physical hole positions. Move the lead or wire endpoint to a visible hole; a hole on the same conductive strip is fine if it is outside the body.

```ruby
board :half
part :U1, :pico, at: "d1"
resistor :R1, "330", pins: %w[e10 a25] # e10 is under U1
```

The module's own pins, holes on the body boundary, and visual wires (`electrical: false`) are ignored. This rule currently checks module rectangles with known dimensions; DIP bodies and older Breadkit versions without body geometry are not checked.
