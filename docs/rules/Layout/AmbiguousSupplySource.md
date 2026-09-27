# Layout/AmbiguousSupplySource

`supply from:` refers to a pin that matches more than one provided power output. Give each output a distinct positive pin in the part definition so the source has one matching return pin and voltage.

This error prevents dependent electrical checks from running because the intended source cannot be determined.
