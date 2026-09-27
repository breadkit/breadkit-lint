# Electrical/RailPolarityMismatch

An explicit voltage source drives both rails opposite their marked polarities: its positive terminal connects to a `−` rail and its negative terminal to a `+` rail. The check follows electrical jumper connections and uses rail polarity from the board definition. It does not infer polarity from wire colors or net labels.

```ruby
board :half
supply :USB, voltage: 5, plus: "B-1", minus: "B+1"
```

This warning reports the reversed pair once for the source. It skips isolated sources, a source tied to only one marked rail, nets that touch both `+` and `−` rails, and rails without declared polarity. Those cases can be valid in bipolar or custom power layouts. Multi-board circuits are outside this check until rail domains can be evaluated per board.
