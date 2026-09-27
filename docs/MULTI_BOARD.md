# Multi-board circuits

Breadkit core can create and load multi-board circuits (IR schema version 2). This version of `bklint` does not analyze them yet. It reports `Fatal/UnsupportedMultiBoard` and exits with status 2 for both DSL and v2 IR inputs, so CI cannot mistake an incomplete lint pass for success.

Single-board circuits and IR schema version 1 continue to use the normal rule set.
