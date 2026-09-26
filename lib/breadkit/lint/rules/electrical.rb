# frozen_string_literal: true

module Breadkit
  module Lint
    class Checks
      def short_circuit(circuit, rule, state)
        baseline = if state.closed_switches.empty?
          []
        else
          circuit.potentials(Breadkit::State.new(name: nil, closed_switches: [])).conflicts.map { |item| item[:supply].name }
        end
        circuit.potentials(state).conflicts.reject { |item| baseline.include?(item[:supply].name) }.map do |conflict|
          first, second = conflict.values_at(:terminal_a, :terminal_b)
          path = conflict[:path] || []
          detail = "#{first} (#{conflict[:expected]} V) and #{second} (#{conflict[:actual]} V) conflict on #{conflict[:net]} (path: #{path.join(' → ')})"
          message = translate("short_circuit", detail, first: first, first_voltage: conflict[:expected], second: second,
                              second_voltage: conflict[:actual], net: conflict[:net], path: path.join(" → "))
          offense(rule.id, message, conflict[:location],
                  targets: { nets: [conflict[:net]], holes: path.select { |item| circuit.board.hole(item) },
                             wires: conflict[:wires] || [] }, state: state.name)
        end
      end

      def shorted_component(circuit, rule, state)
        circuit.components.values.filter_map do |component|
          pins = component.pins.values
          next unless pins.length == 2 && pins.all?(&:hole_id)
          next if circuit.board.hole(pins[0].hole_id).strip_id == circuit.board.hole(pins[1].hole_id).strip_id
          next unless circuit.net_of("#{component.ref}.#{pins[0].name}", state) == circuit.net_of("#{component.ref}.#{pins[1].name}", state)
          offense(rule.id, translate("shorted_component", "#{component.ref} pins are connected to the same net", ref: component.ref), component.location,
                  targets: { components: [component.ref], pins: pins.map { |pin| "#{component.ref}.#{pin.name}" } }, state: state.name)
        end
      end

      def floating_pins(circuit, rule, state)
        circuit.components.values.flat_map do |component|
          next [] if component.part.placement == "offboard"
          shared = component.pins.values.group_by { |pin| pin.hole_id && circuit.board.hole(pin.hole_id)&.strip_id }
                            .reject { |strip, pins| !strip || pins.length < 2 }
                            .values.flatten.map(&:name)
          component.pins.values.filter_map do |pin|
            next if component.unused.include?(pin.number) || component.unused.include?(pin.name)
            next if shared.include?(pin.name)
            if pin.hole_id.nil?
              next offense(rule.id, translate("unplaced_pin", "#{component.ref}.#{pin.name} has no board hole",
                                              pin: "#{component.ref}.#{pin.name}"), component.location,
                           targets: { components: [component.ref], pins: ["#{component.ref}.#{pin.name}"] }, state: state.name)
            end
            net = circuit.net_of("#{component.ref}.#{pin.name}", state)
            next unless net
            externally_connected = net.members.any? do |member|
              member != "#{component.ref}.#{pin.name}" &&
                (!member.include?(".") || member.split(".", 2).first != component.ref)
            end
            next if externally_connected
            offense(rule.id, translate("floating_pin", "#{component.ref}.#{pin.name} has no external connection",
                                       pin: "#{component.ref}.#{pin.name}"), component.location,
                    targets: { components: [component.ref], pins: ["#{component.ref}.#{pin.name}"],
                               holes: [pin.hole_id].compact }, state: state.name)
          end
        end
      end

      def dangling_wires(circuit, rule, state)
        attachments = Hash.new { |hash, key| hash[key] = [] }
        circuit.components.each_value do |component|
          component.pins.each_value do |pin|
            strip = pin.hole_id && circuit.board.hole(pin.hole_id)&.strip_id
            attachments[strip] << component.ref if strip
          end
        end
        circuit.supplies.each do |supply|
          [supply.plus, supply.minus].each do |id|
            strip = circuit.board.hole(id)&.strip_id
            attachments[strip] << supply.name if strip
          end
        end
        circuit.wires.each do |wire|
          next if wire.electrical == false
          [wire.from, wire.to].each do |id|
            strip = circuit.board.hole(id)&.strip_id
            attachments[strip] << wire.id if strip
          end
        end
        circuit.wires.filter_map do |wire|
          next if wire.electrical == false

          attached = [wire.from, wire.to].map do |endpoint|
            hole = circuit.board.hole(endpoint)
            if hole.nil?
              parsed = HoleId.parse(endpoint) rescue nil
              component = parsed&.kind == :pin && circuit.components[parsed.ref]
              next component&.part&.placement == "offboard"
            end
            hole && attachments[hole.strip_id].any? { |owner| owner != wire.id }
          end
          next if attached.all?
          offense(rule.id, translate("dangling_wire", "#{wire.id} has an unconnected end", wire: wire.id),
                  wire.location, targets: { wires: [wire.id] }, state: state.name)
        end
      end

      def split_rails(circuit, rule, _state)
        circuit.board.holes.values.select(&:rail).group_by(&:rail).flat_map do |rail, holes|
          segments = holes.group_by(&:strip_id)
          next [] if segments.length < 2
          entries = segments.map do |_strip, segment_holes|
            ids = segment_holes.map(&:id)
            net = circuit.nets.find { |item| !(item.holes & ids).empty? }
            voltage = net && circuit.potentials.values[net.name]
            [segment_holes, net, voltage]
          end
          next [] unless entries.any? { |_holes, _net, voltage| !voltage.nil? }
          entries.filter_map do |segment_holes, net, voltage|
            touched = net&.members&.any? do |member|
              circuit.wires.any? { |wire| wire.id == member } || circuit.components.keys.any? { |ref| member.start_with?("#{ref}.") }
            end
            next unless net && voltage.nil? && touched
            offense(rule.id, translate("split_rail", "used segment of #{rail} has no supply", rail: rail), nil,
                    targets: { holes: [segment_holes.first.id], nets: [net.name] })
          end
        end
      end

      def missing_series_resistors(circuit, rule, state)
        circuit.components.values.filter_map do |component|
          next unless Array(component.part.data["flags"]).include?("needs_series_resistor")
          polarity = component.part.data["polarity"] || {}
          positive = component.pins[polarity["positive"]]
          negative = component.pins[polarity["negative"]]
          next unless positive && negative
          high = circuit.net_of("#{component.ref}.#{positive.name}", state)
          low = circuit.net_of("#{component.ref}.#{negative.name}", state)
          next unless high && low
          next unless unprotected_path?(circuit, high.name, low.name, component, state)
          offense(rule.id, translate("missing_series_resistor", "#{component.ref} has no current-limiting resistor in series",
                                     ref: component.ref), component.location,
                  targets: { components: [component.ref], pins: ["#{component.ref}.#{positive.name}", "#{component.ref}.#{negative.name}"],
                             nets: [high.name, low.name] }, state: state.name)
        end
      end

      def unprotected_path?(circuit, start, finish, excluded_component, state)
        adjacency = Hash.new { |hash, key| hash[key] = [] }
        circuit.components.each_value do |component|
          next if component == excluded_component || component.pins.length != 2
          next unless component.part.data["category"] == "diode" || (component.part.id == "resistor" && !current_limiter?(component))
          pins = component.pins.values
          left, right = pins.map { |pin| circuit.net_of("#{component.ref}.#{pin.name}", state)&.name }
          next unless left && right && left != right
          adjacency[left] << right
          adjacency[right] << left
        end
        left_reachable = reachable_nets(adjacency, start)
        right_reachable = reachable_nets(adjacency, finish)
        source_pairs(circuit, state).any? do |high, low|
          (left_reachable[high] && right_reachable[low]) ||
            (left_reachable[low] && right_reachable[high])
        end
      end

      def reachable_nets(adjacency, start)
        seen, queue = { start => true }, [start]
        until queue.empty?
          current = queue.shift
          adjacency[current].each do |target|
            next if seen[target]
            seen[target] = true
            queue << target
          end
        end
        seen
      end

      def source_pairs(circuit, state)
        pairs = circuit.supplies.filter_map do |supply|
          high = circuit.net_of("#{supply.name}.+", state)&.name
          low = circuit.net_of("#{supply.name}.-", state)&.name
          [high, low] if high && low
        end
        circuit.components.each_value do |component|
          next unless component.part.placement == "offboard" || component.part.data["category"] == "module"
          pins = component.pins.values
          grounds = pins.select { |pin| pin.role == "ground" }.filter_map { |pin| circuit.net_of("#{component.ref}.#{pin.name}", state)&.name }
          outputs = pins.select { |pin| pin.role == "power" || pin.name.match?(/\A(?:GP|GPIO|D)\d+\z/i) }
          outputs.each do |pin|
            high = circuit.net_of("#{component.ref}.#{pin.name}", state)&.name
            grounds.each { |low| pairs << [high, low] } if high
          end
        end
        pairs
      end

      def current_limiter?(component)
        component.part.id == "resistor" && Breadkit::Value.parse(component.value).positive?
      rescue ArgumentError
        false
      end

      def reverse_polarity(circuit, rule, state)
        ranges, domains = potential_ranges(circuit, state)
        circuit.components.values.filter_map do |component|
          polarity = component.part.data["polarity"]
          next unless polarity
          positive = component.pins[polarity["positive"]]
          negative = component.pins[polarity["negative"]]
          next unless positive && negative
          high = circuit.net_of("#{component.ref}.#{positive.name}", state)
          low = circuit.net_of("#{component.ref}.#{negative.name}", state)
          next unless high && low && ranges[high.name] && ranges[low.name]
          next unless domains[high.name] && domains[high.name] == domains[low.name]
          next unless ranges[high.name][1] < ranges[low.name][0]
          offense(rule.id, translate("reverse_polarity", "#{component.ref} positive pin is below its negative pin",
                                     ref: component.ref), component.location,
                  targets: { components: [component.ref], pins: ["#{component.ref}.#{positive.name}", "#{component.ref}.#{negative.name}"],
                             nets: [high.name, low.name] }, state: state.name)
        end
      end

      def potential_ranges(circuit, state)
        # ponytail: resistor-only DC leaves active-device voltages unknown; add device models when those cases matter.
        known = circuit.potentials(state).values
        ranges = known.transform_values { |value| [value, value] }
        domains = supply_domains(circuit, state)
        adjacency = Hash.new { |hash, key| hash[key] = [] }
        circuit.components.each_value do |component|
          next unless current_limiter?(component) && component.pins.length == 2
          left, right = component.pins.values.map { |pin| circuit.net_of("#{component.ref}.#{pin.name}", state)&.name }
          next unless left && right
          conductance = 1.0 / Breadkit::Value.parse(component.value)
          adjacency[left] << [right, conductance]
          adjacency[right] << [left, conductance]
        end
        visited = {}
        adjacency.each_key do |start|
          next if visited[start]
          queue = [start]
          visited[start] = true
          nodes = []
          until queue.empty?
            node = queue.shift
            nodes << node
            adjacency[node].each do |neighbor, _conductance|
              next if visited[neighbor]
              visited[neighbor] = true
              queue << neighbor
            end
          end
          anchors = nodes.filter_map { |name| domains[name] }.uniq
          next unless anchors.length == 1
          fixed = known.select { |name, _value| domains[name] == anchors.first }
          unknown = nodes.reject { |name| fixed.key?(name) }
          index = unknown.each_with_index.to_h
          matrix = Array.new(unknown.length) { Array.new(unknown.length + 1, 0.0) }
          unknown.each_with_index do |node, row|
            adjacency[node].each do |neighbor, conductance|
              matrix[row][row] += conductance
              fixed.key?(neighbor) ? matrix[row][-1] += conductance * fixed[neighbor] : matrix[row][index[neighbor]] -= conductance
            end
          end
          solution = solve_linear(matrix)
          if solution
            unknown.each_with_index do |name, index|
              ranges[name] = [solution[index], solution[index]]
              domains[name] = anchors.first
            end
          end
        end
        [ranges, domains]
      end

      def supply_domains(circuit, state)
        adjacency = Hash.new { |hash, key| hash[key] = [] }
        circuit.supplies.each do |supply|
          high = circuit.net_of("#{supply.name}.+", state)&.name
          low = circuit.net_of("#{supply.name}.-", state)&.name
          next unless high && low
          adjacency[high] << low
          adjacency[low] << high
        end
        domains = {}
        adjacency.each_key do |start|
          next if domains.key?(start)
          domains[start] = start
          queue = [start]
          until queue.empty?
            adjacency[queue.shift].each do |neighbor|
              next if domains.key?(neighbor)
              domains[neighbor] = start
              queue << neighbor
            end
          end
        end
        domains
      end

      def solve_linear(matrix)
        size = matrix.length
        size.times do |column|
          pivot = (column...size).max_by { |row| matrix[row][column].abs }
          return nil if matrix[pivot][column].abs < 1e-12
          matrix[column], matrix[pivot] = matrix[pivot], matrix[column]
          divisor = matrix[column][column]
          (column..size).each { |offset| matrix[column][offset] /= divisor }
          size.times do |row|
            next if row == column
            factor = matrix[row][column]
            (column..size).each { |offset| matrix[row][offset] -= factor * matrix[column][offset] }
          end
        end
        matrix.map(&:last)
      end

      def power_pins(circuit, rule, state)
        grounds = circuit.supplies.filter_map { |supply| circuit.net_of("#{supply.name}.-", state)&.name }
        values = circuit.potentials(state).values
        circuit.components.values.reject { |component| component.part.placement == "offboard" }.flat_map do |component|
          component.pins.values.filter_map do |pin|
            next unless %w[power ground].include?(pin.role)
            next if component.unused.include?(pin.number) || component.unused.include?(pin.name)
            net = circuit.net_of("#{component.ref}.#{pin.name}", state)
            voltage = net && values[net.name]
            connected = if pin.role == "ground"
              grounds.include?(net&.name)
            else
              !voltage.nil? && grounds.any? { |name| values.key?(name) && voltage > values[name] }
            end
            next if connected
            message = translate("power_pin", "#{component.ref}.#{pin.name} is not connected to a valid #{pin.role} supply",
                                pin: "#{component.ref}.#{pin.name}", role: pin.role)
            offense(rule.id, message, component.location,
                    targets: { components: [component.ref], pins: ["#{component.ref}.#{pin.name}"],
                               holes: [pin.hole_id].compact }, state: state.name)
          end
        end
      end

      def supply_ranges(circuit, rule, state)
        values = circuit.potentials(state).values
        domains = supply_domains(circuit, state)
        circuit.components.values.flat_map do |component|
          range = component.part.data["supply_range"]
          next [] unless range
          powers = component.pins.values.select { |pin| pin.role == "power" }
          grounds = component.pins.values.select { |pin| pin.role == "ground" }
          powers.product(grounds).filter_map do |power, ground|
            high = circuit.net_of("#{component.ref}.#{power.name}", state)
            low = circuit.net_of("#{component.ref}.#{ground.name}", state)
            next unless high && low && values.key?(high.name) && values.key?(low.name)
            next unless domains[high.name] && domains[high.name] == domains[low.name]
            voltage = values[high.name] - values[low.name]
            next if voltage >= range[0].to_f && voltage <= range[1].to_f
            message = translate("supply_range", "#{component.ref} #{power.name}/#{ground.name} supply is #{voltage.round(3)} V; expected #{range[0]}..#{range[1]} V",
                                ref: component.ref, power: power.name, ground: ground.name, voltage: voltage.round(3), minimum: range[0], maximum: range[1])
            offense(rule.id, message, component.location,
                    targets: { components: [component.ref], pins: ["#{component.ref}.#{power.name}", "#{component.ref}.#{ground.name}"],
                               nets: [high.name, low.name] }, state: state.name)
          end
        end
      end

      def common_ground(circuit, rule, state)
        return [] if circuit.supplies.length < 2
        grounds = circuit.supplies.filter_map { |supply| circuit.net_of("#{supply.name}.-", state)&.name }.uniq
        return [] if grounds.length <= 1
        [offense(rule.id, translate("common_ground", "power supplies do not share a ground"), nil, targets: { nets: grounds })]
      end

    end
  end
end
