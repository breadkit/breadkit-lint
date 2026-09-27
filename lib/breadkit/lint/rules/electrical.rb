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

      def floating_inputs(circuit, rule, state)
        anchored = anchored_input_nets(circuit, state)
        circuit.components.values.flat_map do |component|
          component.pins.values.filter_map do |pin|
            next unless pin.role == "input" && pin.hole_id
            next if component.unused.include?(pin.name) || component.unused.include?(pin.number)
            reference = "#{component.ref}.#{pin.name}"
            net = circuit.net_of(reference, state)
            next unless net && !anchored[net.name]
            connected = net.members.any? do |member|
              member != reference && (!member.include?(".") || member.split(".", 2).first != component.ref)
            end
            next unless connected
            offense(rule.id, translate("floating_input", "#{reference} has no modeled source or pull resistor", pin: reference),
                    component.location, targets: { components: [component.ref], pins: [reference], holes: [pin.hole_id], nets: [net.name] },
                    state: state.name)
          end
        end
      end

      def anchored_input_nets(circuit, state)
        anchored = {}
        circuit.voltage_sources.each do |source|
          [source.plus, source.minus].each do |terminal|
            net = circuit.net_of(terminal, state)
            anchored[net.name] = true if net
          end
        end
        circuit.components.each_value do |component|
          component.pins.each_value do |pin|
            output = %w[output gpio open_drain].include?(pin.role) || component.part.pin(pin.number)&.fetch("output_capable", false)
            next unless output
            net = circuit.net_of("#{component.ref}.#{pin.name}", state)
            anchored[net.name] = true if net
          end
        end
        neighbors = Hash.new { |hash, key| hash[key] = [] }
        circuit.components.each_value do |component|
          next unless conductive_resistor?(component)
          nets = component.pins.values.map { |pin| circuit.net_of("#{component.ref}.#{pin.name}", state)&.name }
          next unless nets.length == 2 && nets.all? && nets[0] != nets[1]
          neighbors[nets[0]] << nets[1]
          neighbors[nets[1]] << nets[0]
        end
        queue = anchored.keys
        until queue.empty?
          neighbors[queue.shift].each do |name|
            next if anchored[name]
            anchored[name] = true
            queue << name
          end
        end
        anchored
      end

      def conductive_resistor?(component)
        component.part.id == "resistor" && Breadkit::Value.parse(component.value) >= 0
      rescue ArgumentError, TypeError
        false
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
            source_holes = entries.find { |_holes, _net, potential| !potential.nil? }&.first
            target_hole = segment_holes.first.id
            source_hole = source_holes&.min_by { |hole| (hole.y - segment_holes.first.y).abs }&.id
            connection = source_hole ? "#{source_hole} to #{target_hole}" : target_hole
            location = circuit.wires.find { |wire| net.members.include?(wire.id) }&.location ||
                       circuit.components.values.find { |component| net.members.any? { |member| member.start_with?("#{component.ref}.") } }&.location
            offense(rule.id, translate("split_rail", "used segment of #{rail} has no supply; bridge #{connection}", rail: rail, bridge: connection),
                    location, targets: { holes: [source_hole, target_hole].compact, nets: [net.name] })
          end
        end
      end

      def rail_polarity_mismatch(circuit, rule, _state)
        circuit.voltage_sources.filter_map do |source|
          next if source.isolated
          positive_net = circuit.net_of(source.plus)
          negative_net = circuit.net_of(source.minus)
          next unless positive_net && negative_net && positive_net != negative_net
          positive_rails = polarized_rails(circuit, positive_net)
          negative_rails = polarized_rails(circuit, negative_net)
          next unless positive_rails.map(&:first).uniq == ["-"] && negative_rails.map(&:first).uniq == ["+"]
          board_id = lambda do |hole|
            circuit.board.respond_to?(:board_id_for) ? circuit.board.board_id_for(hole.id) : nil
          end
          positive_by_board = positive_rails.group_by { |_polarity, hole| board_id.call(hole) }
          negative_by_board = negative_rails.group_by { |_polarity, hole| board_id.call(hole) }
          common_boards = positive_by_board.keys & negative_by_board.keys
          next if common_boards.empty?
          common_board = common_boards.first
          wrong_positive = positive_by_board.fetch(common_board).first.last
          wrong_negative = negative_by_board.fetch(common_board).first.last
          offense(rule.id, translate("rail_polarity_mismatch",
                                     "#{source.name} positive terminal is on #{wrong_positive.rail} and negative terminal is on #{wrong_negative.rail}",
                                     source: source.name, positive_rail: wrong_positive.rail, negative_rail: wrong_negative.rail),
                  source.location,
                  targets: { holes: [wrong_positive.id, wrong_negative.id], nets: [positive_net.name, negative_net.name] })
        end
      end

      def polarized_rails(circuit, net)
        net.holes.filter_map do |id|
          hole = circuit.board.hole(id)
          polarity = hole&.rail && circuit.board.rail_polarity(hole.rail)
          [polarity, hole] if polarity
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

      def minimum_resistances(circuit, rule, state)
        pots = circuit.components.values.select { |component| component.part.id == "pot" }
        circuit.components.values.filter_map do |led|
          next unless led.part.id == "led" && pots.any?
          polarity = led.part.data["polarity"] || {}
          high = circuit.net_of("#{led.ref}.#{polarity['positive']}", state)&.name
          low = circuit.net_of("#{led.ref}.#{polarity['negative']}", state)&.name
          next unless high && low
          next if unprotected_path?(circuit, high, low, led, state)

          pot = pots.find do |candidate|
            %w[left right].any? { |end_pin| unprotected_path?(circuit, high, low, led, state, zero_pot: [candidate, end_pin]) }
          end
          next unless pot
          offense(rule.id, translate("minimum_resistance", "#{led.ref} relies on #{pot.ref} for current limiting; its wiper can reach 0 Ω",
                                     led: led.ref, pot: pot.ref), led.location,
                  targets: { components: [led.ref, pot.ref] }, state: state.name)
        end
      end

      def unprotected_path?(circuit, start, finish, excluded_component, state, zero_pot: nil)
        adjacency = Hash.new { |hash, key| hash[key] = [] }
        circuit.components.each_value do |component|
          next if component == excluded_component
          pins = if component == zero_pot&.first
            [component.pin("wiper"), component.pin(zero_pot.last)].compact
          elsif component.part.data["category"] == "transistor"
            [component.pin("collector"), component.pin("emitter")].compact
          elsif component.pins.length == 2 &&
                (component.part.data["category"] == "diode" || (component.part.id == "resistor" && !current_limiter?(component)))
            component.pins.values
          else
            []
          end
          next unless pins.length == 2
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
        pairs = circuit.voltage_sources.filter_map do |supply|
          high = circuit.net_of(supply.plus, state)&.name
          low = circuit.net_of(supply.minus, state)&.name
          [high, low] if high && low
        end
        circuit.components.each_value do |component|
          next unless component.part.placement == "offboard" || component.part.data["category"] == "module"
          pins = component.pins.values
          grounds = pins.select { |pin| pin.role == "ground" }.filter_map { |pin| circuit.net_of("#{component.ref}.#{pin.name}", state)&.name }
          outputs = pins.select do |pin|
            %w[gpio output].include?(pin.role) || component.part.pin(pin.number)&.fetch("output_capable", false)
          end
          outputs.each do |pin|
            gpio = circuit.net_of("#{component.ref}.#{pin.name}", state)&.name
            next unless gpio
            grounds.each { |ground| pairs << [gpio, ground] }
            pairs.concat(circuit.voltage_sources.filter_map do |source|
              high = circuit.net_of(source.plus, state)&.name
              [high, gpio] if high
            end)
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
          flags = Array(component.part.data["flags"])
          next unless %w[led electrolytic].include?(component.part.id) || flags.include?("needs_series_resistor") || component.part.data["category"] == "capacitor"
          next if component.attrs[:bias].to_s == "reverse" || component.attrs["bias"].to_s == "reverse"
          next if flags.include?("reverse_bias_ok")
          polarity = component.part.data["polarity"]
          next unless polarity
          positive = component.pins[polarity["positive"]]
          negative = component.pins[polarity["negative"]]
          next unless positive && negative
          high = circuit.net_of("#{component.ref}.#{positive.name}", state)
          low = circuit.net_of("#{component.ref}.#{negative.name}", state)
          next unless high && low && ranges[high.name] && ranges[low.name]
          next unless domains[high.name] && domains[high.name] == domains[low.name]
          reverse_voltage = ranges[low.name][0] - ranges[high.name][1]
          next unless reverse_voltage > component.part.data.fetch("max_reverse_voltage", 0).to_f
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
        circuit.voltage_sources.each do |supply|
          high = circuit.net_of(supply.plus, state)&.name
          low = circuit.net_of(supply.minus, state)&.name
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
        grounds = circuit.voltage_sources.filter_map { |supply| circuit.net_of(supply.minus, state)&.name }
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
          rated = component.part.data["supply_range"]
          next [] unless rated
          powers = component.pins.values.select { |pin| pin.role == "power" }
          grounds = component.pins.values.select { |pin| pin.role == "ground" }
          powers.product(grounds).filter_map do |power, ground|
            high = circuit.net_of("#{component.ref}.#{power.name}", state)
            low = circuit.net_of("#{component.ref}.#{ground.name}", state)
            next unless high && low && values.key?(high.name) && values.key?(low.name)
            next unless domains[high.name] && domains[high.name] == domains[low.name]
            nominal = values[high.name] - values[low.name]
            actual = direct_source_range(circuit, state, high.name, low.name) || [nominal, nominal]
            next if actual[0] >= rated[0].to_f && actual[1] <= rated[1].to_f
            voltage = actual[0] == actual[1] ? actual[0].round(3).to_s : "#{actual[0]}..#{actual[1]}"
            message = translate("supply_range", "#{component.ref} #{power.name}/#{ground.name} supply is #{voltage} V; expected #{rated[0]}..#{rated[1]} V",
                                ref: component.ref, power: power.name, ground: ground.name, voltage: voltage, minimum: rated[0], maximum: rated[1])
            offense(rule.id, message, component.location,
                    targets: { components: [component.ref], pins: ["#{component.ref}.#{power.name}", "#{component.ref}.#{ground.name}"],
                               nets: [high.name, low.name] }, state: state.name)
          end
        end
      end

      def common_ground(circuit, rule, state)
        supplies = circuit.voltage_sources.reject { |supply| supply.respond_to?(:isolated) && supply.isolated }
        return [] if supplies.length < 2
        domains = supply_domains(circuit, state)
        references = supplies.filter_map { |supply| circuit.net_of(supply.minus, state)&.name }
        return [] if references.filter_map { |name| domains[name] }.uniq.length <= 1
        location = supplies.find { |supply| supply.location }&.location
        [offense(rule.id, translate("common_ground", "power supplies do not share a ground"), location,
                 targets: { nets: references.uniq })]
      end

      def voltage_domain_mismatches(circuit, rule, state)
        ranges, domains = potential_ranges(circuit, state)
        circuit.components.values.flat_map do |component|
          ground_names = component.pins.values.select { |pin| pin.role == "ground" }
                                  .filter_map { |pin| circuit.net_of("#{component.ref}.#{pin.name}", state)&.name }
          component.pins.values.filter_map do |pin|
            limit = component.part.pin(pin.number)&.fetch("max_voltage", nil)
            next unless limit && !ground_names.empty?
            net = circuit.net_of("#{component.ref}.#{pin.name}", state)
            next unless net && ranges.key?(net.name)
            ground = ground_names.find { |name| ranges.key?(name) && domains[name] == domains[net.name] }
            next unless ground
            voltage = direct_source_range(circuit, state, net.name, ground)&.last || (ranges[net.name][1] - ranges[ground][0])
            next unless voltage > limit.to_f
            message = translate("voltage_domain", "#{component.ref}.#{pin.name} can see up to #{voltage.round(3)} V; maximum is #{limit} V",
                                pin: "#{component.ref}.#{pin.name}", voltage: voltage.round(3), maximum: limit)
            offense(rule.id, message, component.location,
                    targets: { components: [component.ref], pins: ["#{component.ref}.#{pin.name}"], nets: [net.name] },
                    state: state.name)
          end
        end
      end

      def resistor_power_ratings(circuit, rule, state)
        ranges, domains = potential_ranges(circuit, state)
        circuit.components.values.filter_map do |component|
          next unless component.part.id == "resistor" && component.value
          rating = Breadkit::Value.power_rating(component.value)
          next unless rating
          voltage = rated_voltage(circuit, component, state, ranges, domains)
          next unless voltage
          minimum = Breadkit::Value.parse(component.value) * (1.0 - (Breadkit::Value.tolerance(component.value) || 0.0))
          next unless minimum.positive?
          watts = voltage**2 / minimum
          next unless watts > rating
          offense(rule.id, "#{component.ref} may dissipate #{watts.round(3)} W; rated for #{rating} W",
                  component.location, targets: { components: [component.ref] }, state: state.name)
        end
      end

      def capacitor_voltage_ratings(circuit, rule, state)
        ranges, domains = potential_ranges(circuit, state)
        circuit.components.values.filter_map do |component|
          next unless component.part.id == "electrolytic" && component.value
          rating = Breadkit::Value.voltage_rating(component.value)
          next unless rating
          voltage = rated_voltage(circuit, component, state, ranges, domains)
          next unless voltage && voltage > rating
          offense(rule.id, "#{component.ref} may see #{voltage.round(3)} V; rated for #{rating} V",
                  component.location, targets: { components: [component.ref] }, state: state.name)
        end
      end

      def led_overcurrent(circuit, rule, state)
        analysis = circuit.dc_analysis(state)
        return [] unless analysis.success?

        circuit.components.values.filter_map do |component|
          limit = component.part.data["max_forward_current"]
          next unless limit && component.part.id == "led"
          current = analysis.currents[component.ref]
          next unless current && current > limit
          offense(rule.id, "#{component.ref} may carry #{(current * 1000).round(2)} mA; maximum is #{(limit * 1000).round(2)} mA",
                  component.location, targets: { components: [component.ref] }, state: state.name)
        end
      end

      def supply_overloads(circuit, rule, state)
        analysis = circuit.dc_analysis(state)
        return [] unless analysis.success?

        circuit.supplies.filter_map do |supply|
          limit = supply.current_limit
          next unless limit
          delivered = -analysis.currents.fetch(supply.name, 0.0)
          next unless delivered > limit * (1 + 1e-9)

          actual_ma, limit_ma = [delivered, limit].map { |value| (value * 1000).round(2) }
          message = translate("supply_overload", "#{supply.name} supplies #{actual_ma} mA; limit is #{limit_ma} mA",
                              supply: supply.name, current: actual_ma, limit: limit_ma)
          nets = [supply.plus, supply.minus].filter_map { |terminal| circuit.net_of(terminal, state)&.name }
          offense(rule.id, message, supply.location, targets: { nets: nets, holes: [supply.plus, supply.minus] }, state: state.name)
        end
      end

      def rated_voltage(circuit, component, state, ranges, domains)
        pins = component.pins.values
        return unless pins.length == 2
        left, right = pins.map { |pin| circuit.net_of("#{component.ref}.#{pin.name}", state)&.name }
        return unless left && right && ranges[left] && ranges[right] && domains[left] && domains[left] == domains[right]
        direct = direct_source_range(circuit, state, left, right) || direct_source_range(circuit, state, right, left)
        return direct.map(&:abs).max if direct
        [(ranges[left][0] - ranges[right][1]).abs, (ranges[left][1] - ranges[right][0]).abs].max
      end

      def i2c_address_conflicts(circuit, rule, state)
        devices = circuit.components.values.filter_map do |component|
          address = component.attrs[:address] || component.attrs["address"]
          next unless address && component.pin("SDA") && component.pin("SCL")
          parsed = Integer(address.to_s, 0) rescue nil
          next unless parsed
          sda = circuit.net_of("#{component.ref}.SDA", state)&.name
          scl = circuit.net_of("#{component.ref}.SCL", state)&.name
          [[sda, scl, parsed], component] if sda && scl
        end
        devices.group_by(&:first).filter_map do |(sda, scl, address), entries|
          next if entries.length < 2
          components = entries.map(&:last)
          refs = components.map(&:ref)
          message = translate("i2c_address", "#{refs.join(', ')} share I2C address 0x#{address.to_s(16).upcase} on the same bus",
                              refs: refs.join(", "), address: "0x#{address.to_s(16).upcase}")
          offense(rule.id, message, components.last.location,
                  targets: { components: refs, pins: refs.flat_map { |ref| ["#{ref}.SDA", "#{ref}.SCL"] },
                             nets: [sda, scl] }, state: state.name)
        end
      end

      def i2c_pullup_missing(circuit, rule, state)
        board_id = lambda do |hole|
          circuit.board.respond_to?(:board_id_for) ? circuit.board.board_id_for(hole) : nil
        end
        positive_nets = circuit.voltage_sources.filter_map do |source|
          net = circuit.net_of(source.plus, state)
          [net.name, net.holes.map(&board_id).uniq] if net
        end
        return [] if positive_nets.empty?

        devices = circuit.components.values.select do |component|
          address = component.attrs[:address] || component.attrs["address"]
          address && component.pin("SDA") && component.pin("SCL") && (Integer(address.to_s, 0) rescue nil)
        end
        devices.group_by do |component|
          %w[SDA SCL].map { |pin| circuit.net_of("#{component.ref}.#{pin}", state)&.name }
        end.flat_map do |(sda, scl), components|
          next [] unless sda && scl && sda != scl

          { "SDA" => sda, "SCL" => scl }.filter_map do |pin, net_name|
            net = circuit.net_of("#{components.first.ref}.#{pin}", state)
            next unless net && components.any? { |component| net.members.any? { |member| member != "#{component.ref}.#{pin}" } }
            boards = net.holes.map(&board_id).uniq
            sources = positive_nets.filter_map { |name, ids| name unless (boards & ids).empty? }
            next if sources.empty? || i2c_pullup_resistor?(circuit, state, net_name, sources)

            refs = components.map(&:ref)
            message = translate("i2c_pullup_missing", "I2C #{pin} on #{refs.join(', ')} has no modeled pull-up resistor",
                                line: pin, refs: refs.join(", "))
            offense(rule.id, message, components.first.location,
                    targets: { components: refs, pins: refs.map { |ref| "#{ref}.#{pin}" }, nets: [net_name] }, state: state.name)
          end
        end
      end

      def i2c_pullup_resistor?(circuit, state, bus_net, positive_nets)
        circuit.components.values.any? do |component|
          next false unless component.part.id == "resistor"
          resistance = Breadkit::Value.parse(component.value) rescue nil
          next false unless resistance&.positive?
          nets = component.pins.values.map { |pin| circuit.net_of("#{component.ref}.#{pin.name}", state)&.name }
          nets.length == 2 && nets.include?(bus_net) && nets.uniq.length == 2 && positive_nets.include?((nets - [bus_net]).first)
        end
      end

      def missing_decoupling_capacitors(circuit, rule, state)
        source_pairs = circuit.voltage_sources.filter_map do |source|
          high = circuit.net_of(source.plus, state)&.name
          low = circuit.net_of(source.minus, state)&.name
          [high, low] if high && low && high != low
        end
        return [] if source_pairs.empty?

        circuit.components.values.flat_map do |component|
          next [] unless component.part.data["category"] == "ic" && component.part.placement != "offboard"
          powers = component.pins.values.select { |pin| pin.role == "power" && !component.unused.include?(pin.name) && !component.unused.include?(pin.number) }
          grounds = component.pins.values.select { |pin| pin.role == "ground" && !component.unused.include?(pin.name) && !component.unused.include?(pin.number) }
          pairs = {}
          powers.product(grounds).each do |power, ground|
            high = circuit.net_of("#{component.ref}.#{power.name}", state)&.name
            low = circuit.net_of("#{component.ref}.#{ground.name}", state)&.name
            pairs[[high, low]] ||= [power, ground] if source_pairs.include?([high, low])
          end
          pairs.filter_map do |(high, low), (power, ground)|
            next if decoupling_capacitor?(circuit, state, high, low)
            message = translate("missing_decoupling_capacitor", "#{component.ref} has no modeled capacitor across #{power.name} and #{ground.name}",
                                ref: component.ref, power: power.name, ground: ground.name)
            offense(rule.id, message, component.location,
                    targets: { components: [component.ref], pins: ["#{component.ref}.#{power.name}", "#{component.ref}.#{ground.name}"],
                               nets: [high, low] }, state: state.name)
          end
        end
      end

      def decoupling_capacitor?(circuit, state, high, low)
        circuit.components.values.any? do |component|
          next false unless %w[capacitor electrolytic].include?(component.part.id)
          nets = component.pins.values.map { |pin| circuit.net_of("#{component.ref}.#{pin.name}", state)&.name }
          nets.length == 2 && nets.all? && nets.sort == [high, low].sort
        end
      end

      def missing_base_resistors(circuit, rule, state)
        outputs = Hash.new { |hash, key| hash[key] = [] }
        circuit.components.each_value do |component|
          component.pins.each_value do |pin|
            next unless pin.role == "output"
            next if component.unused.include?(pin.name) || component.unused.include?(pin.number)
            net = circuit.net_of("#{component.ref}.#{pin.name}", state)
            outputs[net.name] << [component, pin] if net
          end
        end

        circuit.components.values.filter_map do |transistor|
          next unless transistor.part.data["category"] == "transistor"
          base = transistor.pin("base")
          next unless base && !transistor.unused.include?(base.name) && !transistor.unused.include?(base.number)
          net = circuit.net_of("#{transistor.ref}.#{base.name}", state)
          next unless net
          driver, output = outputs[net.name].find { |component, _pin| component.ref != transistor.ref }
          next unless driver
          message = translate("missing_base_resistor", "#{driver.ref}.#{output.name} drives #{transistor.ref}.#{base.name} without a series resistor",
                              driver: "#{driver.ref}.#{output.name}", base: "#{transistor.ref}.#{base.name}")
          offense(rule.id, message, transistor.location,
                  targets: { components: [transistor.ref, driver.ref], pins: ["#{transistor.ref}.#{base.name}", "#{driver.ref}.#{output.name}"],
                             nets: [net.name] }, state: state.name)
        end
      end

      def direct_source_range(circuit, state, high_name, low_name)
        sources = circuit.voltage_sources.select do |source|
          circuit.net_of(source.plus, state)&.name == high_name && circuit.net_of(source.minus, state)&.name == low_name
        end
        return unless sources.length == 1
        sources.first.voltage_range
      end

    end
  end
end
