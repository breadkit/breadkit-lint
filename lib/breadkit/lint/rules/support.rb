# frozen_string_literal: true

module Breadkit
  module Lint
    class Checks
      def initialize(config, messages)
        @config, @messages = config, messages
      end

      def diagnostics(circuit, rule, _state)
        circuit.diagnostics.filter_map do |diagnostic|
          next unless diagnostic_rule(diagnostic.code) == rule.id
          offense(rule.id, diagnostic_message(diagnostic), diagnostic.location,
                  targets: diagnostic_targets(circuit, diagnostic.targets), state: nil)
        end
      end

      def diagnostic_rule(code)
        return "Intent/UnknownNet" if code == "unknown_net"
        Registry.all.find { |rule| rule < DiagnosticRule && rule.id.split("/").last.gsub(/([a-z])([A-Z])/, '\\1_\\2').downcase == code }&.id
      end

      def diagnostic_targets(circuit, values)
        ids = { components: circuit.components.keys, wires: circuit.wires.map(&:id),
                holes: circuit.board.holes.keys, nets: circuit.nets.map(&:name) }
        Array(values).each_with_object({}) do |value, targets|
          kind = ids.find { |_type, known| known.include?(value) }&.first
          (targets[kind] ||= []) << value if kind
        end
      end

      def diagnostic_message(diagnostic)
        target = Array(diagnostic.targets).join(", ")
        target = diagnostic.message[/unknown pin ([^;]+)/, 1] || target if diagnostic.code == "unknown_pin"
        option = diagnostic.message[/unknown component option ([^ ]+)/, 1] if diagnostic.code == "unknown_option"
        translate("diagnostic_#{diagnostic.code}", diagnostic.message, target: target, option: option)
      end

      def translate(key, english, **values)
        template = @messages[key]
        template ? format(template, **values) : english
      end

      def offense(rule_id, message, location, targets: {}, state: nil)
        rule = Registry.all.find { |item| item.id == rule_id }
        Offense.new(rule: rule_id, severity: rule ? @config.severity(rule) : "error", message: message,
                    location: location, targets: targets, state: state)
      end

      def suppress(offenses, disables, circuit)
        invalid_disables = []
        invalid = disables.filter_map do |disable|
          rule_id = disable[:rule] || disable["rule"]
          reason = disable[:reason] || disable["reason"]
          message = if Registry.all.none? { |rule| rule.id == rule_id }
            translate("unknown_disable", "unknown rule in lint_disable: #{rule_id}", rule: rule_id)
          elsif @config.data.dig("AllRules", "RequireDisableReason") && reason.to_s.strip.empty?
            translate("disable_reason", "lint_disable for #{rule_id} requires a reason", rule: rule_id)
          end
          next unless message
          invalid_disables << disable
          offense("Config/InvalidDisable", message, location_from(disable[:location] || disable["location"]))
        end
        valid = disables - invalid_disables
        kept = offenses.reject do |item|
          valid.any? do |disable|
            rule = disable[:rule] || disable["rule"]
            target = disable[:on] || disable["on"]
            rule == item.rule && (!target || item.targets.values.flatten.include?(canonical_pin(circuit, target)))
          end
        end
        kept + invalid
      end

      def canonical_pin(circuit, reference)
        ref, pin = reference.to_s.split(".", 2)
        resolved = pin && circuit.components[ref]&.pin(pin)
        resolved ? "#{ref}.#{resolved.name}" : reference.to_s
      end

      def location_from(value)
        return value if value.is_a?(SourceLocation)
        return nil unless value
        SourceLocation.new(path: value["path"] || value[:path], line: value["line"] || value[:line])
      end
    end
  end
end
