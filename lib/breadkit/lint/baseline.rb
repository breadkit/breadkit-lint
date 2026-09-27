# frozen_string_literal: true

module Breadkit
  module Lint
    class Baseline
      def initialize(path)
        @path = File.expand_path(path)
      end

      def write(files)
        raise Error, "cannot baseline fatal errors" if files.any? { |file| file[:offenses].any? { |item| item.rule.start_with?("Fatal/") } }

        entries = files.flat_map { |file| file[:offenses].map { |item| entry(file, item) } }.uniq
        File.write(@path, JSON.pretty_generate(schema_version: 1, entries: entries) + "\n", encoding: "UTF-8")
        entries.length
      end

      def filter(files)
        data = JSON.parse(File.read(@path, encoding: "UTF-8"))
        raise Error, "invalid baseline: expected schema_version 1 and entries" unless data.is_a?(Hash) && data["schema_version"] == 1 && data["entries"].is_a?(Array) && data["entries"].all? { |item| item.is_a?(Hash) }

        known = data["entries"].to_set
        files.map { |file| file.merge(offenses: file[:offenses].reject { |item| known.include?(entry(file, item)) }) }
      end

      private

      def entry(file, item)
        path = item.location&.path || file[:path]
        relative = Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(File.dirname(@path))).to_s.tr("\\", "/")
        targets = item.targets.to_h.sort_by { |key, _value| key.to_s }.to_h.transform_keys(&:to_s)
                      .transform_values { |value| Array(value).map(&:to_s).sort }
        { "path" => relative, "rule" => item.rule, "severity" => item.severity,
          "message" => item.message, "state" => item.state, "targets" => targets }
      end
    end
  end
end
