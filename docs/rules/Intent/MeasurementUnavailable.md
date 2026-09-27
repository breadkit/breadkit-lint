# Intent/MeasurementUnavailable

An `expect_voltage` or `expect_current` declaration cannot be checked because
the DC model has no value for that net or component. The warning includes the
reason, such as an active GPIO output with an unknown drive state or a floating
voltage reference.

Connect a grounded source and supported passive parts, or check the circuit
with a simulator that models the unsupported device. This warning does not
mean the declared range passed.
