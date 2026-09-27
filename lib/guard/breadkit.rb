# frozen_string_literal: true

require "guard/plugin"
require "breadkit/lint"

module Guard
  class Breadkit < Plugin
    def run_all
      lint(Array(options.fetch(:files, ["."])))
    end

    def run_on_changes(paths)
      return if paths.empty?

      circuits = paths.select { |path| path.match?(/\.bk\.(?:rb|ya?ml|toml|json)\z/) && File.file?(path) }
      lint(circuits.length == paths.length ? circuits : Array(options.fetch(:files, ["."])))
    end

    private

    def lint(paths)
      throw :task_has_failed unless ::Breadkit::Lint::CLI.new.run(Array(options[:args]) + paths).zero?
      true
    end
  end
end
