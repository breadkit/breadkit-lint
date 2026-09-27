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

      def hole_covered(circuit, rule, _state)
        circuit.components.values.flat_map do |owner|
          next [] unless owner.part.data.dig("render", "shape") == "module" && owner.respond_to?(:body_bounds)
          bounds = owner.body_bounds(circuit.board)
          next [] unless bounds
          left, top, width, height = bounds
          inside = lambda do |hole|
            hole && hole.x > left + 1e-6 && hole.x < left + width - 1e-6 &&
              hole.y > top + 1e-6 && hole.y < top + height - 1e-6
          end
          leads = circuit.components.values.reject { |component| component.equal?(owner) }.flat_map do |component|
            component.pins.values.filter_map do |pin|
              hole = pin.hole_id && circuit.board.hole(pin.hole_id)
              next unless inside.call(hole)
              reference = "#{component.ref}.#{pin.name}"
              offense(rule.id, translate("hole_covered_lead", "#{reference} is under #{owner.ref} at #{hole.id}",
                                         pin: reference, module: owner.ref, hole: hole.id), component.location,
                      targets: { components: [owner.ref, component.ref], pins: [reference], holes: [hole.id] })
            end
          end
          wires = circuit.wires.flat_map do |wire|
            next [] if wire.electrical == false
            [wire.from, wire.to].uniq.filter_map do |endpoint|
              hole = circuit.board.hole(endpoint)
              next unless inside.call(hole)
              offense(rule.id, translate("hole_covered_wire", "#{wire.id} ends under #{owner.ref} at #{hole.id}",
                                         wire: wire.id, module: owner.ref, hole: hole.id), wire.location,
                      targets: { components: [owner.ref], wires: [wire.id], holes: [hole.id] })
            end
          end
          leads + wires
        end
      end

      def body_overlap(circuit, rule, _state)
        bodies = circuit.components.values.filter_map do |component|
          body = physical_body(component, circuit.board)
          [component, body] if body
        end
        bodies.combination(2).filter_map do |(first, a), (second, b)|
          next unless bodies_overlap?(a, b)
          offense(rule.id, translate("body_overlap", "#{first.ref} and #{second.ref} bodies overlap",
                                     first: first.ref, second: second.ref), second.location,
                  targets: { components: [first.ref, second.ref] })
        end
      end

      def physical_body(component, board)
        shape = component.part.data.dig("render", "shape")
        if shape == "module" && component.respond_to?(:body_bounds)
          bounds = component.body_bounds(board)
          return [:rect, *bounds] if bounds
        elsif %w[led_5mm rgb_led_5mm].include?(shape)
          holes = component.pins.values.filter_map { |pin| board.hole(pin.hole_id) if pin.hole_id }
          return unless holes.length == component.pins.length && !holes.empty?
          return [:circle, holes.sum(&:x) / holes.length, holes.sum(&:y) / holes.length, 2.5 / 2.54]
        end
        nil
      end

      def bodies_overlap?(a, b)
        if a.first == :rect && b.first == :rect
          _kind, ax, ay, aw, ah = a
          _kind, bx, by, bw, bh = b
          return ax < bx + bw - 1e-6 && bx < ax + aw - 1e-6 &&
                 ay < by + bh - 1e-6 && by < ay + ah - 1e-6
        end
        if a.first == :circle && b.first == :circle
          dx, dy = a[1] - b[1], a[2] - b[2]
          return dx * dx + dy * dy < (a[3] + b[3] - 1e-6)**2
        end
        circle, rect = a.first == :circle ? [a, b] : [b, a]
        _kind, cx, cy, radius = circle
        _kind, rx, ry, width, height = rect
        dx = cx - cx.clamp(rx, rx + width)
        dy = cy - cy.clamp(ry, ry + height)
        dx * dx + dy * dy < (radius - 1e-6)**2
      end

    end
  end
end
