# frozen_string_literal: true

require_relative "rules/support"
require_relative "rules/layout"
require_relative "rules/electrical"
require_relative "rules/intent"
require_relative "rules/style"

module Breadkit
  module Lint
    class BuiltinRule < Rule
      private

      def emit(context, checker)
        context.offenses.concat(context.checks.public_send(checker, context.circuit, self.class, context.state))
      end

      def emit_diagnostics(context)
        emit(context, :diagnostics)
      end
    end

    class DiagnosticRule < BuiltinRule
    end

    module Rules
      module Layout
        class InvalidHole < DiagnosticRule
          rule "Layout/InvalidHole", severity: :error, description: "Unknown board hole"

          def check(context) = emit_diagnostics(context)
        end

        class UnknownBoard < DiagnosticRule
          rule "Layout/UnknownBoard", severity: :error, description: "Unknown board definition"

          def check(context) = emit_diagnostics(context)
        end

        class UnknownPart < DiagnosticRule
          rule "Layout/UnknownPart", severity: :error, description: "Unknown part definition"

          def check(context) = emit_diagnostics(context)
        end

        class UnknownTransistorModel < DiagnosticRule
          rule "Layout/UnknownTransistorModel", severity: :warning, description: "Unknown transistor model uses a generic pinout"

          def check(context) = emit_diagnostics(context)
        end

        class UnknownPin < DiagnosticRule
          rule "Layout/UnknownPin", severity: :error, description: "Unknown pin reference"

          def check(context) = emit_diagnostics(context)
        end

        class UnknownOption < DiagnosticRule
          rule "Layout/UnknownOption", severity: :error, description: "Unknown component option"

          def check(context) = emit_diagnostics(context)
        end

        class UnplacedPin < DiagnosticRule
          rule "Layout/UnplacedPin", severity: :error, description: "A component pin has no board hole"

          def check(context) = emit_diagnostics(context)
        end

        class DuplicateRef < DiagnosticRule
          rule "Layout/DuplicateRef", severity: :error, description: "Duplicate component or wire reference"

          def check(context) = emit_diagnostics(context)
        end

        class InvalidPlacement < DiagnosticRule
          rule "Layout/InvalidPlacement", severity: :error, description: "Invalid component placement"

          def check(context) = emit_diagnostics(context)
        end

        class HoleConflict < DiagnosticRule
          rule "Layout/HoleConflict", severity: :error, description: "Multiple leads occupy one hole"

          def check(context) = emit_diagnostics(context)
        end

        class NoFreeHole < DiagnosticRule
          rule "Layout/NoFreeHole", severity: :error, description: "No free hole is available"

          def check(context) = emit_diagnostics(context)
        end

        class SplitNetLabel < DiagnosticRule
          rule "Layout/SplitNetLabel", severity: :error, description: "A label names disconnected nets"

          def check(context) = emit_diagnostics(context)
        end

        class PinsInSameStrip < BuiltinRule
          rule "Layout/PinsInSameStrip", severity: :error, description: "Two component pins share one conductive strip"

          def check(context) = emit(context, :same_strip)
        end

      end

      module Electrical
        class ShortCircuit < BuiltinRule
          rule "Electrical/ShortCircuit", severity: :error, description: "Power constraints conflict", state_sensitive: true

          def check(context) = emit(context, :short_circuit)
        end

        class ShortedComponent < BuiltinRule
          rule "Electrical/ShortedComponent", severity: :warning, description: "A two-pin part is bypassed"

          def check(context) = emit(context, :shorted_component)
        end

        class FloatingPin < BuiltinRule
          rule "Electrical/FloatingPin", severity: :warning, description: "A component pin has no external connection"

          def check(context) = emit(context, :floating_pins)
        end

        class DanglingWire < BuiltinRule
          rule "Electrical/DanglingWire", severity: :warning, description: "A wire end has no other connection"

          def check(context) = emit(context, :dangling_wires)
        end

        class SplitRail < BuiltinRule
          rule "Electrical/SplitRail", severity: :warning, description: "A used split rail segment has no supply"

          def check(context) = emit(context, :split_rails)
        end

        class MissingSeriesResistor < BuiltinRule
          rule "Electrical/MissingSeriesResistor", severity: :error, description: "An LED has an unprotected path across a supply", state_sensitive: true

          def check(context) = emit(context, :missing_series_resistors)
        end

        class ReversePolarity < BuiltinRule
          rule "Electrical/ReversePolarity", severity: :error, description: "A polarized part is connected backwards", state_sensitive: true

          def check(context) = emit(context, :reverse_polarity)
        end

        class PowerPinUnconnected < BuiltinRule
          rule "Electrical/PowerPinUnconnected", severity: :warning, description: "An IC power or ground pin is not connected to a supply"

          def check(context) = emit(context, :power_pins)
        end

        class SupplyVoltageRange < BuiltinRule
          rule "Electrical/SupplyVoltageRange", severity: :error, description: "An IC supply voltage is outside its rated range", state_sensitive: true

          def check(context) = emit(context, :supply_ranges)
        end

        class NoCommonGround < BuiltinRule
          rule "Electrical/NoCommonGround", severity: :warning, description: "Power supplies do not share a ground"

          def check(context) = emit(context, :common_ground)
        end

        class NetLabelConflict < BuiltinRule
          rule "Electrical/NetLabelConflict", severity: :error, description: "Different labels name one net"

          def check(context) = emit(context, :label_conflicts)
        end

      end

      module Intent
        class ConnectionMismatch < BuiltinRule
          rule "Intent/ConnectionMismatch", severity: :error, description: "Wiring differs from declared expectations"

          def check(context) = emit(context, :expectations)
        end

        class UnknownNet < BuiltinRule
          rule "Intent/UnknownNet", severity: :error, description: "An expectation refers to an unknown net"

          def check(context)
            emit_diagnostics(context)
            emit(context, :expectations)
          end
        end

      end

      module Style
        class WireColor < BuiltinRule
          rule "Style/WireColor", severity: :info, description: "A wire color differs from the supply color convention"

          def check(context) = emit(context, :wire_colors)
        end

      end
    end
  end
end
