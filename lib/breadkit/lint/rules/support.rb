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
                holes: circuit.board.holes.keys,
                pins: circuit.components.values.flat_map { |component| component.pins.values.map { |pin| "#{component.ref}.#{pin.name}" } },
                nets: circuit.nets.map(&:name) }
        Array(values).each_with_object({}) do |value, targets|
          canonical = canonical_pin(circuit, value)
          kind = ids.find { |_type, known| known.include?(canonical) }&.first
          (targets[kind] ||= []) << canonical if kind
        end
      end

      def diagnostic_message(diagnostic)
        target = Array(diagnostic.targets).join(", ")
        target = diagnostic.message[/unknown pin ([^;]+)/, 1] || target if diagnostic.code == "unknown_pin"
        target = diagnostic.message[/unknown board: (.+)/, 1] || target if diagnostic.code == "unknown_board"
        option = diagnostic.message[/unknown component option ([^ ]+)/, 1] if diagnostic.code == "unknown_option"
        reason = case diagnostic.message
        when /must straddle the center gap/ then translate("placement_straddle", "must straddle the center gap")
        when /extends beyond the board or into the center gap/ then translate("placement_bounds_or_gap", "extends beyond the board or into the center gap")
        when /extends beyond the board/ then translate("placement_bounds", "extends beyond the board")
        when /pins do not match its footprint/ then translate("placement_footprint", "pins do not match the footprint")
        when /needs a terminal hole anchor/ then translate("placement_anchor", "needs a terminal hole anchor")
        else diagnostic.message
        end
        translate("diagnostic_#{diagnostic.code}", diagnostic.message, target: target, option: option, reason: reason)
      end

      def translate(key, english, **values)
        template = @messages[key]
        template ? format(template, **values) : english
      end

      def offense(rule_id, message, location, targets: {}, state: nil, suggestion: nil)
        rule = Registry.all.find { |item| item.id == rule_id }
        Offense.new(rule: rule_id, severity: rule ? @config.severity(rule) : "error", message: message,
                    location: location, targets: targets, state: state, suggestion: suggestion)
      end

      def suppress(offenses, disables, circuit, path:, only: nil, except: nil, skipped: false)
        invalid_disables = []
        invalid = disables.filter_map do |disable|
          rule_id = disable[:rule] || disable["rule"]
          reason = disable[:reason] || disable["reason"]
          unknown = Registry.all.none? { |rule| rule.id == rule_id }
          message = if unknown
            translate("unknown_disable", "unknown rule in lint_disable: #{rule_id}", rule: rule_id)
          elsif @config.data.dig("AllRules", "RequireDisableReason") && reason.to_s.strip.empty?
            translate("disable_reason", "lint_disable for #{rule_id} requires a reason", rule: rule_id)
          end
          next unless message
          invalid_disables << disable
          if unknown
            rule = Rules::Lint::UnknownRuleInDisable
            next if !@config.enabled?(rule) || !@config.rule_applies?(rule, path) || (only && !only.include?(rule.id)) || except&.include?(rule.id)
          end
          offense(unknown ? "Lint/UnknownRuleInDisable" : "Config/InvalidDisable", message,
                  location_from(disable[:location] || disable["location"]))
        end
        valid = disables - invalid_disables
        used = []
        kept = offenses.reject do |item|
          match = valid.find do |disable|
            rule = disable[:rule] || disable["rule"]
            target = disable[:on] || disable["on"]
            line = disable[:line] || disable["line"]
            rule == item.rule && (!line || item.location&.line == line) &&
              (!target || item.targets.values.flatten.include?(canonical_pin(circuit, target)))
          end
          used << match if match
          !!match
        end
        redundant_selected = (!only || only.include?("Lint/RedundantDisable")) && !except&.include?("Lint/RedundantDisable")
        redundant = valid.filter_map do |disable|
          next unless redundant_selected
          rule_id = disable[:rule] || disable["rule"]
          rule = Registry.all.find { |item| item.id == rule_id }
          next if used.include?(disable) || !rule || !@config.enabled?(rule) || !@config.rule_applies?(rule, path)
          next if only && !only.include?(rule_id)
          next if except&.include?(rule_id)
          next if skipped && rule_id.start_with?("Electrical/", "Intent/")
          next unless @config.enabled?(Rules::Lint::RedundantDisable) && @config.rule_applies?(Rules::Lint::RedundantDisable, path)
          offense("Lint/RedundantDisable", translate("redundant_disable", "lint_disable for #{rule_id} suppresses no offense", rule: rule_id),
                  location_from(disable[:location] || disable["location"]))
        end
        (kept + invalid + redundant).sort_by { |item| [item.location&.path.to_s, item.location&.line.to_i, item.rule, item.message] }
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
