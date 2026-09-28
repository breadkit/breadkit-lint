# Electrical/DcBoundsIncomplete

The declared source ranges and resistor tolerances could not be bounded
completely. Current and power findings can still identify an observed violation,
but an absence of findings does not establish that every operating point is safe.

Diode switching can create extrema between sampled endpoints. Analysis also
stops when there are more than 512 endpoint combinations or an endpoint cannot
be solved. Reduce independent uncertain values or check the circuit with a
dedicated simulator before relying on a component rating.
