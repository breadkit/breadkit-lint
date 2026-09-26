# frozen_string_literal: true

module Breadkit
  module Lint
    class Checks
      def label_conflicts(circuit, rule, state)
        circuit.nets(state).filter_map do |net|
          next unless net.labels.length > 1
          message = translate("label_conflict", "net has conflicting labels: #{net.labels.join(', ')}", labels: net.labels.join(", "))
          offense(rule.id, message, nil, targets: { nets: [net.name] }, state: state.name)
        end
      end

      def expectations(circuit, rule, state)
        return [] if rule.id == "Intent/UnknownNet" && circuit.diagnostics.any? { |item| item.code == "unknown_net" }
        circuit.expectations.flat_map do |expectation|
          strict = expectation["strict"] || expectation[:strict]
          Array(expectation["entries"] || expectation[:entries]).filter_map do |item|
            kind = item["kind"] || item[:kind]
            refs = item["refs"] || item[:refs] || []
            expected_name = item["name"] || item[:name]
            loc = item["location"] || item[:location]
            names = refs.map(&:to_s)
            nets = names.empty? && kind == "net" ? [circuit.net_of(expected_name, state)] : names.map { |reference| circuit.net_of(reference, state) }
            if nets.any?(&:nil?)
              next unless rule.id == "Intent/UnknownNet"
              references = (names.empty? ? [expected_name] : names).join(", ")
              offense(rule.id, translate("unknown_expectation", "unknown reference in expectation: #{references}", refs: references),
                      location_from(loc), targets: {})
            elsif rule.id == "Intent/ConnectionMismatch" && kind == "connected" && nets.map(&:name).uniq.length > 1
              message = translate("expected_connected", "expected #{names.join(', ')} to be connected", refs: names.join(", "))
              offense(rule.id, message, location_from(loc), targets: { nets: nets.map(&:name) }, state: state.name)
            elsif rule.id == "Intent/ConnectionMismatch" && kind == "isolated" && nets.map(&:name).uniq.length != names.length
              message = translate("expected_isolated", "expected #{names.join(', ')} to be isolated", refs: names.join(", "))
              offense(rule.id, message, location_from(loc), targets: { nets: nets.map(&:name) }, state: state.name)
            elsif rule.id == "Intent/ConnectionMismatch" && kind == "net"
              actual_pins = nets.compact.flat_map(&:members).select do |member|
                circuit.components.keys.any? { |ref| member.start_with?("#{ref}.") }
              end.uniq
              declared_pins = names.map { |name| canonical_pin(circuit, name) }
              extra_pins = strict ? actual_pins - declared_pins : []
              name_matches = nets.first.name == expected_name.to_s
              next if nets.map(&:name).uniq.length == 1 && extra_pins.empty? && name_matches
              detail = if !extra_pins.empty?
                translate("undeclared_pins", "undeclared pins on expected net: #{extra_pins.join(', ')}", pins: extra_pins.join(", "))
              elsif !name_matches
                translate("expected_net_name", "expected net #{expected_name}, found #{nets.first.name}", expected: expected_name, actual: nets.first.name)
              else
                translate("expected_one_net", "expected #{names.join(', ')} on one net", refs: names.join(", "))
              end
              offense(rule.id, detail, location_from(loc), targets: { nets: nets.compact.map(&:name), components: extra_pins.map { |pin| pin.split('.', 2).first } }, state: state.name)
            end
          end
        end
      end

    end
  end
end
