# frozen_string_literal: true

module Breadkit
  module Lint
    class Checks
      def same_strip(circuit, rule, _state)
        circuit.components.values.flat_map do |component|
          next [] if component.part.placement == "offboard"
          pins = component.pins.values.select(&:hole_id)
          groups = pins.group_by { |pin| circuit.board.hole(pin.hole_id)&.strip_id }
          groups.flat_map do |strip, members|
            next [] unless strip && members.length > 1
            members.combination(2).filter_map do |left, right|
              allowed = Array(component.part.data["same_strip_ok"]).any? do |pair|
                pair = pair.map(&:to_s)
                left_keys = [left.name, left.number]
                right_keys = [right.name, right.number]
                (left_keys & pair).any? && (right_keys & pair).any?
              end
              next if allowed
              message = translate("same_strip", "#{component.ref} pins #{left.name}, #{right.name} share strip #{strip}",
                                  ref: component.ref, left: left.name, right: right.name, strip: strip)
              offense(rule.id, message, component.location,
                      targets: { components: [component.ref], pins: ["#{component.ref}.#{left.name}", "#{component.ref}.#{right.name}"],
                                 holes: [left.hole_id, right.hole_id] })
            end
          end
        end
      end

    end
  end
end
