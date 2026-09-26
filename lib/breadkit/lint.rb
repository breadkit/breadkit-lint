# frozen_string_literal: true

require "breadkit"
require "json"
require "yaml"
require "optparse"
require "pathname"
require "uri"
require "find"
require_relative "lint/version"

module Breadkit
  module Lint
    class Error < StandardError; end

    Offense = Struct.new(:rule, :severity, :message, :location, :targets, :state, keyword_init: true)

    class Rule
      attr_reader :id, :severity, :description, :state_sensitive, :checker

      def initialize(config = nil, id: nil, severity: nil, description: nil, state_sensitive: false, checker: nil)
        @config, @id, @severity, @description = config, id || self.class.id, severity || self.class.severity, description || self.class.description
        @state_sensitive, @checker = id ? state_sensitive : self.class.state_sensitive, checker
      end

      def self.rule(id, severity:, description:, state_sensitive: false)
        @id, @severity, @description, @state_sensitive = id, severity.to_s, description, state_sensitive
        Registry.register(self)
      end

      def self.id
        @id
      end

      def self.severity
        @severity
      end

      def self.description
        @description
      end

      def self.state_sensitive
        @state_sensitive
      end

      def check(_context)
        raise NotImplementedError
      end

      private

      def add_offense(context, message, location:, targets: {})
        context.offenses << Offense.new(rule: self.class.id, severity: context.config.severity(self.class), message: message,
                                        location: location, targets: targets, state: context.state.name)
      end
    end

    class Context
      attr_reader :circuit, :state, :config, :checks, :offenses

      def initialize(circuit, state, config, checks = nil)
        @circuit, @state, @config, @checks, @offenses = circuit, state, config, checks, []
      end
    end

    class Registry
      @rules = []

      def self.all
        @rules
      end

      def self.register(rule)
        raise Error, "duplicate rule #{rule.id}" if @rules.any? { |item| item.id == rule.id }
        @rules << rule
      end
    end

    class Config
      DEFAULT_PATH = File.expand_path("../../config/default.yml", __dir__)

      attr_reader :data

      def initialize(path = nil)
        @data = YAML.safe_load(File.read(DEFAULT_PATH, encoding: "UTF-8"), aliases: false) || {}
        @config_dir = path ? File.dirname(File.expand_path(path)) : Dir.pwd
        raise Error, "config not found: #{path}" if path && !File.file?(path)
        merge_file(path) if path
        Array(data["require"]).each { |file| require File.expand_path(file, @config_dir) }
        validate!
      end

      def severity(rule)
        value = data.dig(rule.id, "Severity") || rule.severity
        value.to_s.downcase
      end

      def enabled?(rule)
        enabled = data.dig(rule.id, "Enabled")
        return data.dig("AllRules", "NewRules") == "enable" if enabled.to_s == "pending"
        enabled != false
      end

      def switch_states
        data.dig("AllRules", "SwitchStates") || "single"
      end

      def fail_level
        data.dig("AllRules", "FailLevel") || "warning"
      end

      def excludes
        Array(data.dig("AllRules", "Exclude"))
      end

      def extra_parts
        Array(data["use_parts"]).flat_map { |pattern| Dir.glob(File.expand_path(pattern, @config_dir)) }
      end

      def unknown_rules
        reserved = %w[AllRules inherit_from require use_parts]
        (data.keys - reserved - Registry.all.map(&:id))
      end

      def excluded?(path)
        absolute = File.expand_path(path)
        relative = Pathname.new(absolute).relative_path_from(Pathname.new(@config_dir)).to_s
        excludes.any? do |pattern|
          File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_EXTGLOB) ||
            File.fnmatch?(pattern, absolute, File::FNM_PATHNAME | File::FNM_EXTGLOB)
        end
      end

      private

      def merge_file(path)
        @data = deep_merge(@data, load_config(path, []))
      rescue Psych::Exception => e
        raise Error, "invalid config #{path}: #{e.message}"
      end

      def load_config(path, stack)
        absolute = File.expand_path(path)
        raise Error, "cyclic config inheritance: #{(stack + [absolute]).join(' -> ')}" if stack.include?(absolute)
        override = YAML.safe_load(File.read(absolute, encoding: "UTF-8"), aliases: false) || {}
        parents = Array(override.delete("inherit_from")).reduce({}) do |merged, parent|
          parent_path = File.expand_path(parent, File.dirname(absolute))
          deep_merge(merged, load_config(parent_path, stack + [absolute]))
        end
        deep_merge(parents, override)
      end

      def deep_merge(left, right)
        left.merge(right) do |_key, current, replacement|
          current.is_a?(Hash) && replacement.is_a?(Hash) ? deep_merge(current, replacement) : replacement
        end
      end

      def validate!
        fail_level = data.dig("AllRules", "FailLevel")
        switch_states = data.dig("AllRules", "SwitchStates")
        new_rules = data.dig("AllRules", "NewRules")
        raise Error, "invalid fail level: #{fail_level}" if fail_level && !%w[error warning info].include?(fail_level.to_s)
        raise Error, "invalid switch state mode: #{switch_states}" if switch_states && !%w[none single all].include?(switch_states.to_s)
        raise Error, "invalid new rules mode: #{new_rules}" if new_rules && !%w[pending enable disable].include?(new_rules.to_s)
        Registry.all.each do |rule|
          severity_value = data.dig(rule.id, "Severity")
          next unless severity_value && !%w[error warning info].include?(severity_value.to_s.downcase)
          raise Error, "invalid severity for #{rule.id}: #{severity_value}"
        end
      end
    end

    require_relative "lint/rules"
    Registry.const_set(:RULES, Registry.all.dup.freeze)

    class Engine
      BLOCKING_DIAGNOSTICS = %w[invalid_hole unknown_board unknown_part unknown_pin unknown_option unplaced_pin invalid_placement no_free_hole].freeze
      LEVELS = { "info" => 0, "warning" => 1, "error" => 2 }.freeze

      def initialize(config: Config.new, locale: "en")
        @config = config
        path = File.expand_path("../../locales/#{locale}.yml", __dir__)
        messages = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false)&.fetch("messages", {}) || {}
        @checks = Checks.new(@config, messages)
      end

      def run(paths, only: nil, except: nil)
        Array(paths).filter_map do |path|
          next if excluded?(path)
          begin
            circuit = if path.end_with?(".json")
              Breadkit.load(path)
            else
              document = Breadkit::DSL.load_file(path)
              document.part_paths.concat(@config.extra_parts)
              Breadkit::Resolver.new.call(document)
            end
            offenses = inspect_circuit(circuit, only, except)
            { path: path, offenses: @checks.suppress(offenses, circuit.lint_disables, circuit),
              skipped: circuit.diagnostics.any? { |item| BLOCKING_DIAGNOSTICS.include?(item.code) } }
          rescue StandardError => e
            offense = Offense.new(rule: "Fatal/EvaluationError", severity: "error", message: e.message,
                                  location: Breadkit::SourceLocation.new(path: path, line: nil), targets: {}, state: nil)
            { path: path, offenses: [offense] }
          end
        end
      end

      def fail?(files, threshold = @config.fail_level)
        minimum = LEVELS.fetch(threshold.to_s, 1)
        files.any? { |file| file[:offenses].any? { |item| LEVELS.fetch(item.severity, 2) >= minimum } }
      end

      def fatal?(files)
        files.any? { |file| file[:offenses].any? { |item| item.rule.start_with?("Fatal/") } }
      end

      private

      def inspect_circuit(circuit, only, except)
        offenses = []
        broken_layout = circuit.diagnostics.any? { |item| BLOCKING_DIAGNOSTICS.include?(item.code) }
        states = circuit.states(@config.switch_states)
        Registry.all.each do |rule|
          next unless @config.enabled?(rule) && selected?(rule.id, only, except)
          next if broken_layout && rule.id.start_with?("Electrical/", "Intent/")
          relevant_states = rule.state_sensitive ? states : [states.first]
          relevant_states.each do |state|
            context = Context.new(circuit, state, @config, @checks)
            checked = begin
              rule.new(@config).check(context)
              context.offenses
            rescue StandardError, NotImplementedError => e
              [@checks.offense("Fatal/RuleError",
                               @checks.translate("rule_error", "#{rule.id} failed: #{e.message}", rule: rule.id, error: e.message),
                               nil)]
            end
            checked.each { |item| item.state = nil if state.closed_switches.empty? }
            offenses.concat(checked)
          end
        end
        baseline = offenses.select { |item| item.state.nil? }.map { |item| [item.rule, item.message, item.location&.line] }
        offenses.reject { |item| item.state && baseline.include?([item.rule, item.message, item.location&.line]) }
                .uniq { |item| [item.rule, item.message, item.location&.line, item.state] }
                .sort_by { |item| [item.location&.path.to_s, item.location&.line.to_i, item.rule] }
      end

      def selected?(id, only, except)
        return false if only && !only.include?(id)
        return false if except && except.include?(id)
        true
      end

      def excluded?(path)
        @config.excluded?(path)
      end
    end

    class Formatter
      def text(files, locale: "en")
        lines = files.flat_map do |file|
          entries = file[:offenses].map do |item|
            level = { "error" => "E", "warning" => "W", "info" => "I" }.fetch(item.severity, "E")
            state = item.state ? (locale == "ja" ? " (#{item.state} の状態)" : " (#{item.state} state)") : ""
            path = item.location&.path || file[:path]
            line = item.location&.line ? ":#{item.location.line}" : ""
            "#{path}#{line}: #{level}: [#{item.rule}] #{item.message}#{state}"
          end
          entries << (locale == "ja" ? "#{file[:path]}: 配置エラーのため電気・意図の検査を省略しました" :
                                           "#{file[:path]}: electrical and intent checks skipped because of layout errors") if file[:skipped]
          entries
        end
        errors, warnings, infos = files.flat_map { |file| file[:offenses] }.group_by(&:severity).values_at("error", "warning", "info").map { |items| items ? items.length : 0 }
        summary = if locale == "ja"
          "#{files.length} ファイルを検査、#{errors + warnings + infos} 件の指摘（エラー #{errors} 件、警告 #{warnings} 件、情報 #{infos} 件）"
        else
          count = errors + warnings + infos
          "#{files.length} #{files.length == 1 ? 'file' : 'files'} inspected, #{count} #{count == 1 ? 'offense' : 'offenses'} (#{errors} #{errors == 1 ? 'error' : 'errors'}, #{warnings} #{warnings == 1 ? 'warning' : 'warnings'}, #{infos} #{infos == 1 ? 'info' : 'infos'})"
        end
        (lines + [summary]).join("\n")
      end

      def json(files)
        offenses = files.flat_map { |file| file[:offenses] }
        JSON.pretty_generate(
          schema_version: 1,
          tool: { name: "bklint", version: VERSION },
          files: files.map do |file|
            { path: File.expand_path(file[:path]), analysis_skipped: !!file[:skipped], offenses: file[:offenses].map do |item|
              { rule: item.rule, severity: item.severity, message: item.message,
                location: { path: item.location&.path || file[:path], line: item.location&.line },
                state: item.state, targets: item.targets }
            end }
          end,
          summary: { files: files.length, errors: offenses.count { |item| item.severity == "error" },
                     warnings: offenses.count { |item| item.severity == "warning" }, infos: offenses.count { |item| item.severity == "info" } }
        )
      end

      def github(files)
        files.flat_map do |file|
          file[:offenses].map do |item|
            level = { "error" => "error", "warning" => "warning", "info" => "notice" }.fetch(item.severity, "error")
            line = item.location&.line
            message = escape_data(item.message)
            location = "file=#{escape_property(item.location&.path || file[:path])}"
            location += ",line=#{line}" if line
            "::#{level} #{location},title=#{escape_property(item.rule)}::#{message}"
          end
        end.join("\n")
      end

      def sarif(files)
        rules = (Registry.all.map do |rule|
          level = { "error" => "error", "warning" => "warning", "info" => "note" }.fetch(rule.severity, "error")
          definition = { id: rule.id, shortDescription: { text: rule.description }, defaultConfiguration: { level: level } }
          path = File.expand_path("../../docs/rules/#{rule.id}.md", __dir__)
          definition[:helpUri] = "https://github.com/breadkit/breadkit-lint/blob/main/docs/rules/#{rule.id}.md" if File.file?(path)
          definition
        end + %w[Fatal/EvaluationError Fatal/RuleError Config/InvalidDisable].map do |id|
          { id: id, shortDescription: { text: id.split("/").last }, defaultConfiguration: { level: "error" } }
        end)
        results = files.flat_map do |file|
          file[:offenses].map do |item|
            result = { ruleId: item.rule, level: { "error" => "error", "warning" => "warning", "info" => "note" }.fetch(item.severity, "error"),
                       message: { text: item.message }, properties: { targets: item.targets, state: item.state } }
            path = item.location&.path || file[:path]
            relative = Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(Dir.pwd)).to_s.tr("\\", "/")
            uri = URI::DEFAULT_PARSER.escape(relative, /[^A-Za-z0-9\-._~\/]/)
            physical = { artifactLocation: { uri: uri, uriBaseId: "%SRCROOT%" } }
            physical[:region] = { startLine: item.location.line } if item.location&.line.to_i.positive?
            result[:locations] = [{ physicalLocation: physical }]
            result
          end
        end
        root_path = URI::DEFAULT_PARSER.escape("#{File.expand_path(Dir.pwd)}/", /[^A-Za-z0-9\-._~\/]/)
        root_uri = URI::File.build(path: root_path).to_s
        JSON.pretty_generate(version: "2.1.0", "$schema" => "https://json.schemastore.org/sarif-2.1.0.json",
                             runs: [{ tool: { driver: { name: "bklint", version: VERSION, rules: rules } },
                                      originalUriBaseIds: { "%SRCROOT%" => { uri: root_uri } }, results: results }])
      end

      private

      def escape_data(value)
        value.to_s.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")
      end

      def escape_property(value)
        escape_data(value).gsub(":", "%3A").gsub(",", "%2C")
      end
    end

    class CLI
      def run(argv)
        options = { format: "text", fail_level: nil }
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: bklint [options] [FILES...]"
          opts.on("-f", "--format FORMAT", %w[text json github sarif]) { |value| options[:format] = value }
          opts.on("-o", "--out PATH") { |value| options[:out] = value }
          opts.on("-c", "--config PATH") { |value| options[:config] = value }
          opts.on("--fail-level LEVEL", %w[error warning info]) { |value| options[:fail_level] = value }
          opts.on("--only RULES") { |value| options[:only] = value.split(",") }
          opts.on("--except RULES") { |value| options[:except] = value.split(",") }
          opts.on("--switch-states MODE", %w[none single all]) { |value| options[:switch_states] = value }
          opts.on("--list-rules") { options[:list_rules] = true }
          opts.on("--explain RULE") { |value| options[:explain] = value }
          opts.on("--locale LOCALE", %w[ja en]) { |value| options[:locale] = value }
          opts.on("-v", "--version") { puts "bklint #{VERSION}"; return 0 }
          opts.on("-h", "--help") { puts opts; return 0 }
        end
        parser.parse!(argv)
        locale = options[:locale] || locale_from_environment
        return list_rules(locale) if options[:list_rules]
        return explain(options[:explain], locale) if options[:explain]
        files = expand_inputs(argv)
        configs = {}
        results = files.flat_map do |path|
          config_path = options[:config] || nearest_config(path)
          unless configs.key?(config_path)
            configs[config_path] = Config.new(config_path)
            configs[config_path].unknown_rules.each do |rule|
              suggestion = DidYouMean::SpellChecker.new(dictionary: Registry.all.map(&:id)).correct(rule).first
              warn "bklint: unknown rule #{rule.inspect}#{suggestion ? "; did you mean #{suggestion.inspect}?" : ""}"
            end
          end
          config = configs[config_path]
          config.data["AllRules"] ||= {}
          config.data["AllRules"]["SwitchStates"] = options[:switch_states] if options[:switch_states]
          Engine.new(config: config, locale: locale).run([path], only: options[:only], except: options[:except])
        end
        formatter = Formatter.new
        output = case options[:format]
        when "json" then formatter.json(results)
        when "github" then formatter.github(results)
        when "sarif" then formatter.sarif(results)
        else formatter.text(results, locale: locale)
        end
        options[:out] ? File.write(options[:out], output + "\n") : puts(output)
        return 2 if results.any? { |file| file[:offenses].any? { |item| item.rule.start_with?("Fatal/") } }
        results.any? do |file|
          config = configs[options[:config] || nearest_config(file[:path])]
          Engine.new(config: config).fail?([file], options[:fail_level] || config.fail_level)
        end ? 1 : 0
      rescue StandardError, ScriptError => e
        warn "bklint: #{e.message}"
        2
      end

      private

      def locale_from_environment
        value = %w[LC_ALL LC_MESSAGES LANG].map { |key| ENV[key] }.find { |item| !item.to_s.empty? }
        value.to_s.start_with?("ja") ? "ja" : "en"
      end

      def nearest_config(path)
        directory = File.directory?(path) ? File.expand_path(path) : File.dirname(File.expand_path(path))
        loop do
          config = File.join(directory, ".bklint.yml")
          return config if File.file?(config)
          parent = File.dirname(directory)
          return nil if parent == directory
          directory = parent
        end
      end

      def expand_inputs(paths)
        roots = paths.empty? ? ["."] : paths
        roots.flat_map do |root|
          next [root] unless File.directory?(root)
          found = []
          Find.find(root) do |path|
            if File.directory?(path)
              Find.prune if path != root && (File.basename(path).start_with?(".") || File.basename(path) == "node_modules")
            elsif path.end_with?(".bk.rb") || (path.end_with?(".json") && ir_json?(path))
              found << path
            end
          end
          found
        end.flatten.uniq.sort
      end

      def ir_json?(path)
        return true if path.end_with?(".bk.json", ".breadkit.json")
        data = JSON.parse(File.read(path, encoding: "UTF-8"))
        data.is_a?(Hash) && data["schema_version"] == 1
      rescue JSON::ParserError, Encoding::InvalidByteSequenceError
        false
      end

      def list_rules(locale)
        Registry.all.each { |rule| puts "#{rule.id}\t#{rule.severity}\t#{localized_description(rule, locale)}" }
        0
      end

      def explain(id, locale)
        rule = Registry.all.find { |item| item.id == id }
        raise Error, "unknown rule #{id}" unless rule
        path = File.expand_path("../../docs/rules/#{rule.id}.md", __dir__)
        puts File.file?(path) ? File.read(path, encoding: "UTF-8") : "#{rule.id} (#{rule.severity})\n#{localized_description(rule, locale)}"
        0
      end

      def localized_description(rule, locale)
        path = File.expand_path("../../locales/#{locale}.yml", __dir__)
        translations = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false) || {}
        translations.dig("rules", rule.id) || rule.description
      rescue Errno::ENOENT, Psych::Exception
        rule.description
      end
    end
  end
end
