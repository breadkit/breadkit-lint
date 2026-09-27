# Intent/ConnectionMismatch

Actual connectivity differs from a declared `connected`, `isolated`, or `net` expectation.
The rule also reports calculated DC voltage or current outside a declared
`expect_voltage` or `expect_current` range.

```ruby
expect { connected "R1.1", "D1.anode" }
```

Correct the wiring or update the expectation to match the intended circuit. `strict: true` rejects extra pins on declared nets and pins on nets omitted from the expectation. If the connection is correct but its name differs, add a `net` label at one of its holes.
