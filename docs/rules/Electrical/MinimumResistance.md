# Electrical/MinimumResistance

A potentiometer wiper can reach either end of its resistive track. If it is the only current-limiting element in an LED path, the resistance can approach 0 Ω and the LED may be damaged. This rule checks connected power and GPIO paths at both wiper extremes. It does not flag a pot used only between its two end pins.

```ruby
supply :P, voltage: 5, plus: "B+1", minus: "B-1"
pot :VR1, "10k", at: "a5"
led :D1, anode: "a10", cathode: "a11"
wire "b5", "B+"
wire "b6", "b10"
wire "b11", "B-"
```

Add a fixed resistor in series with the LED. Its value should keep LED current within the part's rating at the highest supply voltage.
