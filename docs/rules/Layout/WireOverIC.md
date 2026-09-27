# Layout/WireOverIC

A straight electrical jumper crosses a DIP IC body in the layout. This informational finding helps when planning a build where the jumper should not pass above the chip. Route the wire around the chip if clearance matters.

```ruby
board :half
ic :U1, :ne555, at: "e10"
wire "a11", "j11" # Crosses U1
```

The rule estimates the standard DIP body from all placed pins: it requires two pin rows separated by three hole pitches. It checks only straight electrical wires whose endpoints are board holes. Curved and edge routes, visual alternatives, incomplete ICs, and non-DIP packages are outside this check.
