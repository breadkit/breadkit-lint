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
          bounds = body_rectangle(owner, circuit.board)
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

      def wire_over_ic(circuit, rule, _state)
        circuit.components.values.flat_map do |component|
          bounds = dip_body_bounds(component, circuit.board)
          next [] unless bounds
          circuit.wires.filter_map do |wire|
            next unless wire.electrical != false && wire.route == "straight"
            from = circuit.board.hole(wire.from)
            to = circuit.board.hole(wire.to)
            next unless from && to
            next unless segment_crosses_rect?(from, to, bounds)
            offense(rule.id, translate("wire_over_ic", "#{wire.id} crosses #{component.ref} body",
                                       wire: wire.id, ic: component.ref), wire.location,
                    targets: { components: [component.ref], wires: [wire.id] })
          end
        end
      end

      def lead_span(circuit, rule, _state)
        circuit.components.values.filter_map do |component|
          part = component.part
          next unless part.respond_to?(:max_lead_span_mm)
          limit = part.max_lead_span_mm
          next unless limit
          pins = component.pins.values
          next unless pins.length == 2
          holes = pins.map { |pin| pin.hole_id && circuit.board.hole(pin.hole_id) }
          next unless holes.all?
          actual = Math.hypot(holes[0].x - holes[1].x, holes[0].y - holes[1].y) * 2.54
          next unless actual > limit + 1e-6
          actual_text, limit_text = format("%.3f", actual), format("%.3f", limit)
          offense(rule.id, translate("lead_span", "#{component.ref} spans #{actual_text} mm; limit is #{limit_text} mm",
                                     ref: component.ref, actual: actual_text, limit: limit_text),
                  component.location,
                  targets: { components: [component.ref], pins: pins.map { |pin| "#{component.ref}.#{pin.name}" }, holes: holes.map(&:id) })
        end
      end

      def dip_body_bounds(component, board)
        return unless component.part.placement == "dip" && component.part.data.dig("render", "shape") == "dip"
        holes = component.pins.values.filter_map { |pin| board.hole(pin.hole_id) if pin.hole_id }
        return unless holes.length == component.part.pins.length && holes.all? { |hole| hole.kind == :terminal }
        xs, ys = holes.map(&:x), holes.map(&:y).uniq.sort
        return unless ys.length == 2 && (ys.last - ys.first - 3).abs < 1e-6
        rows = holes.group_by(&:y).values.map { |row| row.map(&:x).sort }
        return unless rows[0] == rows[1] && rows[0].length * 2 == holes.length
        [xs.min - 0.4, (ys.first + ys.last) / 2.0 - 0.4, xs.max - xs.min + 0.8, 0.8]
      end

      def segment_crosses_rect?(from, to, bounds)
        left, top, width, height = bounds
        ranges = [[left + 1e-6, left + width - 1e-6, from.x, to.x],
                  [top + 1e-6, top + height - 1e-6, from.y, to.y]]
        entry, exit = 0.0, 1.0
        ranges.each do |minimum, maximum, start, finish|
          delta = finish - start
          return false if delta.abs < 1e-9 && !(start > minimum && start < maximum)
          next if delta.abs < 1e-9
          first, last = [(minimum - start) / delta, (maximum - start) / delta].minmax
          entry = [entry, first].max
          exit = [exit, last].min
        end
        entry < exit - 1e-9
      end

      def physical_body(component, board)
        shape = component.part.data.dig("render", "shape")
        if %w[module dip].include?(shape)
          bounds = body_rectangle(component, board)
          return [:rect, *bounds] if bounds
        elsif %w[led_5mm rgb_led_5mm].include?(shape)
          holes = component.pins.values.filter_map { |pin| board.hole(pin.hole_id) if pin.hole_id }
          return unless holes.length == component.pins.length && !holes.empty?
          return [:circle, holes.sum(&:x) / holes.length, holes.sum(&:y) / holes.length, 2.5 / 2.54]
        end
        nil
      end

      def body_rectangle(component, board)
        shape = component.part.data.dig("render", "shape")
        return component.body_bounds(board) if shape == "module" && component.respond_to?(:body_bounds)
        dip_body_bounds(component, board) if shape == "dip"
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
