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
          family = color_family(wire.color) if wire.color
          next unless expected && family && !expected.include?(family)
          message = translate("wire_color", "#{wire.id} uses #{wire.color}; expected #{expected.join(' or ')}",
                              wire: wire.id, color: wire.color, expected: expected.join(" / "))
          offense(rule.id, message, wire.location,
                  targets: { wires: [wire.id], nets: [net.name] })
        end
      end

      def color_family(color)
        value = color.to_s.downcase
        return "gray" if value.match?(/gr[ae]y|silver|white/)
        return "black" if value == "black"
        return "red" if value.match?(/red|crimson|maroon|firebrick|coral|tomato/)
        return "orange" if value.match?(/orange|gold|salmon/)
        return "blue" if value.match?(/blue|navy|azure|cyan|teal|turquoise/)
        return value if %w[green yellow purple pink brown].include?(value)
        if (match = /\Ahsl\(\s*(\d+)\s*,\s*(\d+)%\s*,\s*(\d+)%\s*\)\z/.match(value))
          hue, saturation, lightness = match.captures.map(&:to_i)
          return "black" if lightness <= 15
          return "gray" if saturation < 25
          return "red" if hue < 15 || hue >= 345
          return "orange" if hue < 50
          return "yellow" if hue < 75
          return "green" if hue < 165
          return "blue" if hue.between?(195, 255)
          return "purple"
        end
        if (match = /\Argb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)\z/.match(value))
          red, green, blue = match.captures.map(&:to_i)
        elsif value.match?(/\A#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})\z/)
          digits = value.delete_prefix("#")
          digits = digits.chars.map { |digit| digit * 2 }.join if digits.length <= 4
          red, green, blue = digits.scan(/../).first(3).map { |pair| pair.to_i(16) }
        else
          return nil
        end
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
        return "yellow" if hue < 75
        return "green" if hue < 165
        return "blue" if hue.between?(195, 255)
        "purple"
      end

    end
  end
end
