# frozen_string_literal: true

module Breadkit
  module Lint
    class Checks
      def wire_colors(circuit, rule, _state)
        positive = Array(@config.data.dig(rule.id, "PositiveColors") || %w[red orange]).map { |color| color.downcase }
        ground = Array(@config.data.dig(rule.id, "GroundColors") || %w[black blue gray]).map { |color| color.downcase }
        circuit.wires.filter_map do |wire|
          net = circuit.nets.find { |item| item.members.include?(wire.id) }
          voltage = net && circuit.potentials.values[net.name]
          expected = voltage&.positive? ? positive : (voltage == 0.0 ? ground : nil)
          next unless expected && wire.color && !expected.include?(color_family(wire.color))
          message = translate("wire_color", "#{wire.id} uses #{wire.color}; expected #{expected.join(' or ')}",
                              wire: wire.id, color: wire.color, expected: expected.join(" / "))
          offense(rule.id, message, wire.location,
                  targets: { wires: [wire.id], nets: [net.name] })
        end
      end

      def color_family(color)
        value = color.to_s.downcase
        return value unless value.match?(/\A#(?:[0-9a-f]{3}|[0-9a-f]{6})\z/)
        digits = value.delete_prefix("#")
        digits = digits.chars.map { |digit| digit * 2 }.join if digits.length == 3
        red, green, blue = digits.scan(/../).map { |pair| pair.to_i(16) }
        max, min = [red, green, blue].max, [red, green, blue].min
        return "black" if max <= 76
        return "gray" if max == min || (max - min).fdiv(max) < 0.25
        hue = case max
        when red then 60.0 * (green - blue) / (max - min)
        when green then 120.0 + 60.0 * (blue - red) / (max - min)
        else 240.0 + 60.0 * (red - green) / (max - min)
        end % 360
        return "red" if hue < 15 || hue >= 345
        return "orange" if hue < 50
        return "blue" if hue.between?(195, 255)
        value
      end

    end
  end
end
