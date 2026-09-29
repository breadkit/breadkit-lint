# Electrical/DcBoundsIncomplete

The declared source ranges and resistor tolerances could not be bounded
completely. Current, power, and voltage findings can still identify an observed violation,
but an absence of findings does not establish that every operating point is safe.

Diode switching can create extrema between sampled endpoints. Analysis also
stops when there are more than 512 endpoint combinations, an endpoint cannot
be solved, or a connected part has no DC model. Reduce independent uncertain
values or check the circuit with a dedicated simulator before relying on a
component rating.
