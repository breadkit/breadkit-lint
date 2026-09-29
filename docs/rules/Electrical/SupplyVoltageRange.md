# Electrical/SupplyVoltageRange

The known voltage difference between a part's power and ground pins is outside its declared `supply_range`.

```ruby
supply :USB, voltage: 3.3, plus: "B+1", minus: "B-1"
ic :U1, "NE555", at: "e20" # NE555 requires at least 4.5 V
```

Use a valid supply voltage or a part rated for the circuit voltage.
When DC bounds are available, the check uses the paired voltage difference across the power and ground pins at each source and resistor tolerance scenario. This includes resistor networks. Direct source endpoints remain checkable when the full DC model is unavailable. Diode circuits use endpoint estimates; `Electrical/DcBoundsIncomplete` warns when a passing check does not establish safety across the full range.
