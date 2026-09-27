# Multi-board circuits

`bklint` checks named multi-board circuits from Ruby DSL or Breadkit IR schema version 2. Hole IDs are qualified with the board name, and electrical wires can connect boards.

```ruby
board :half, as: :B1
board :half, as: :B2
supply :USB, voltage: 5, plus: "B1.B+1", minus: "B1.B-1"
wire "B1.a10", "B2.a10"
```

The same rules apply to both boards. Board strips and rails remain independent until an electrical wire connects them. Layout findings identify the owning board in each hole ID, and `Electrical/RailPolarityMismatch` compares marked rails on the same board. Suppressions and source locations work as they do for single-board circuits.

Use `bklint circuit.bk.rb` or `bklint circuit.json` for a resolved v2 IR file. Directory scans also discover v2 JSON files. Single-board circuits continue to use IR schema version 1.
