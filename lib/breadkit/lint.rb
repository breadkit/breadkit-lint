# frozen_string_literal: true

require "breadkit"
require "json"
require "yaml"
require "optparse"
require "pathname"
require "uri"
require "find"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "lint/version"

module Breadkit
  module Lint
    class Error < StandardError; end
    require_relative "lint/baseline"

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
        matches_path?(excludes, path)
      end

      def rule_applies?(rule, path)
        include_patterns = data.dig(rule.id, "Include")
        (include_patterns.nil? || matches_path?(Array(include_patterns), path)) &&
          !matches_path?(Array(data.dig(rule.id, "Exclude")), path)
      end

      private

      def matches_path?(patterns, path)
        absolute = File.expand_path(path)
        relative = Pathname.new(absolute).relative_path_from(Pathname.new(@config_dir)).to_s
        patterns.any? do |pattern|
          File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_EXTGLOB) ||
            File.fnmatch?(pattern, absolute, File::FNM_PATHNAME | File::FNM_EXTGLOB)
        end
      end

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
          %w[Include Exclude].each do |key|
            patterns = data.dig(rule.id, key)
            next if patterns.nil? || patterns.is_a?(String) || (patterns.is_a?(Array) && patterns.all? { |pattern| pattern.is_a?(String) })
            raise Error, "invalid #{rule.id} #{key} patterns"
          end
          severity_value = data.dig(rule.id, "Severity")
          next unless severity_value && !%w[error warning info].include?(severity_value.to_s.downcase)
          raise Error, "invalid severity for #{rule.id}: #{severity_value}"
        end
      end
    end

    require_relative "lint/rules"
    Registry.const_set(:RULES, Registry.all.dup.freeze)

    class Engine
      BLOCKING_DIAGNOSTICS = %w[invalid_hole unknown_board unknown_part unknown_pin unknown_supply_source ambiguous_supply_source unknown_option invalid_option invalid_value invalid_color invalid_route invalid_wire_id unplaced_pin invalid_placement no_free_hole].freeze
      LEVELS = { "info" => 0, "warning" => 1, "error" => 2 }.freeze

      def initialize(config: Config.new, locale: "en")
        @config = config
        path = File.expand_path("../../locales/#{locale}.yml", __dir__)
        messages = YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: false)&.fetch("messages", {}) || {}
        @checks = Checks.new(@config, messages)
      end

      def run(paths, only: nil, except: nil, timeout: 10, source: nil)
        Array(paths).filter_map do |path|
          next if excluded?(path)
          begin
            circuit = if path.end_with?(".json")
              Breadkit.load(path)
            else
              document = Breadkit::DSL.load_file(path, timeout: timeout, source: source)
              document.part_paths.concat(@config.extra_parts)
              Breadkit::Resolver.new.call(document)
            end
            offenses = inspect_circuit(circuit, path, only, except)
            skipped = circuit.diagnostics.any? { |item| BLOCKING_DIAGNOSTICS.include?(item.code) }
            { path: path, offenses: @checks.suppress(offenses, circuit.lint_disables, circuit, path: path, only: only, except: except, skipped: skipped),
              skipped: skipped }
          rescue StandardError, ScriptError, SystemStackError => e
            location = e.respond_to?(:location) && e.location
            location ||= begin
              line = e.message[/\A(?:#{Regexp.escape(path)}|#{Regexp.escape(File.expand_path(path))}):(\d+):/, 1]
              Breadkit::SourceLocation.new(path: path, line: line&.to_i)
            end
            offense = Offense.new(rule: "Fatal/EvaluationError", severity: "error", message: e.message,
                                  location: location, targets: {}, state: nil)
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

      def inspect_circuit(circuit, path, only, except)
        offenses = []
        broken_layout = circuit.diagnostics.any? { |item| BLOCKING_DIAGNOSTICS.include?(item.code) }
        states = circuit.states(@config.switch_states)
        scoped_expectations = circuit.expectations.any? { |item| item["when"] || item[:when] }
        intent_states = scoped_expectations ? circuit.states("all") : states
        Registry.all.each do |rule|
          next unless @config.enabled?(rule) && @config.rule_applies?(rule, path) && selected?(rule.id, only, except)
          next if broken_layout && rule.id.start_with?("Electrical/", "Intent/")
          relevant_states = if rule.id.start_with?("Intent/") && scoped_expectations
            intent_states
          else
            rule.state_sensitive ? states : [states.first]
          end
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
                .sort_by { |item| [item.location&.path.to_s, item.location&.line.to_i, item.rule, item.message] }
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
      def text(files, locale: "en", teach: false)
        lines = files.flat_map do |file|
          entries = file[:offenses].flat_map do |item|
            level = { "error" => "E", "warning" => "W", "info" => "I" }.fetch(item.severity, "E")
            state = item.state ? (locale == "ja" ? " (#{item.state} の状態)" : " (#{item.state} state)") : ""
            path = display_path(item.location&.path || file[:path])
            line = item.location&.line ? ":#{item.location.line}" : ""
            heading = "#{path}#{line}: #{level}: [#{item.rule}] #{item.message}#{state}"
            guidance = teach && teach_guidance(item.rule, locale)
            guidance ? [heading, "  #{locale == 'ja' ? '説明' : 'Why'}: #{guidance}"] : [heading]
          end
          entries << (locale == "ja" ? "#{display_path(file[:path])}: 配置エラーのため電気・意図の検査を省略しました" :
                                           "#{display_path(file[:path])}: electrical and intent checks skipped because of layout errors") if file[:skipped]
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
            { path: display_path(file[:path]), analysis_skipped: !!file[:skipped], offenses: file[:offenses].map do |item|
              { rule: item.rule, severity: item.severity, message: item.message,
                location: { path: display_path(item.location&.path || file[:path]), line: item.location&.line },
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
            location = "file=#{escape_property(display_path(item.location&.path || file[:path]))}"
            location += ",line=#{line}" if line
            "::#{level} #{location},title=#{escape_property(item.rule)}::#{message}"
          end
        end.join("\n")
      end

      def markdown(files)
        rows = files.flat_map do |file|
          file[:offenses].map do |item|
            path = display_path(item.location&.path || file[:path])
            [path, item.location&.line, item.severity, item.rule, item.message].map do |value|
              xml_escape(value).gsub("|", "\\|").gsub(/\r?\n/, "<br>")
            end.join(" | ").then { |row| "| #{row} |" }
          end
        end
        (["| File | Line | Severity | Rule | Message |", "| --- | ---: | --- | --- | --- |"] + rows).join("\n")
      end

      def junit(files)
        failures = files.count { |file| file[:offenses].any? { |item| item.severity == "error" } }
        cases = files.map do |file|
          name = xml_escape(display_path(file[:path]))
          errors, notices = file[:offenses].partition { |item| item.severity == "error" }
          details = errors.map do |item|
            "<failure type=\"#{xml_escape(item.rule)}\" message=\"#{xml_escape(item.message)}\"/>"
          end
          details << "<system-out>#{xml_escape(notices.map { |item| "#{item.severity}: #{item.rule}: #{item.message}" }.join("\n"))}</system-out>" unless notices.empty?
          "<testcase name=\"#{name}\">#{details.join}</testcase>"
        end
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><testsuites><testsuite name=\"bklint\" tests=\"#{files.length}\" failures=\"#{failures}\">#{cases.join}</testsuite></testsuites>"
      end

      def checkstyle(files)
        entries = files.map do |file|
          errors = file[:offenses].map do |item|
            line = item.location&.line ? " line=\"#{item.location.line}\"" : ""
            "<error#{line} severity=\"#{xml_escape(item.severity)}\" message=\"#{xml_escape(item.message)}\" source=\"#{xml_escape(item.rule)}\"/>"
          end
          "<file name=\"#{xml_escape(display_path(file[:path]))}\">#{errors.join}</file>"
        end
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><checkstyle version=\"10.0\">#{entries.join}</checkstyle>"
      end

      def rdjson(files)
        diagnostics = files.flat_map do |file|
          file[:offenses].map do |item|
            location = { path: display_path(item.location&.path || file[:path]) }
            location[:range] = { start: { line: item.location.line } } if item.location&.line.to_i.positive?
            { message: item.message, location: location, severity: item.severity.upcase,
              code: { value: item.rule } }
          end
        end
        JSON.pretty_generate(source: { name: "bklint", url: "https://github.com/breadkit/breadkit-lint" }, diagnostics: diagnostics)
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
            relative = display_path(path)
            uri = URI::DEFAULT_PARSER.escape(relative, /[^A-Za-z0-9\-._~\/]/)
            physical = { artifactLocation: { uri: uri, uriBaseId: "%SRCROOT%" } }
            physical[:region] = { startLine: item.location.line } if item.location&.line.to_i.positive?
            result[:locations] = [{ physicalLocation: physical }]
            result
          end
        end
        root_uri = source_root_uri(Dir.pwd)
        JSON.pretty_generate(version: "2.1.0", "$schema" => "https://json.schemastore.org/sarif-2.1.0.json",
                             runs: [{ tool: { driver: { name: "bklint", version: VERSION, rules: rules } },
                                      originalUriBaseIds: { "%SRCROOT%" => { uri: root_uri } }, results: results }])
      end

      private

      def source_root_uri(root)
        path = root.tr("\\", "/")
        path = File.expand_path(path) unless path.match?(/\A[A-Za-z]:\//)
        path = "/#{path}" if path.match?(/\A[A-Za-z]:\//)
        escaped = URI::DEFAULT_PARSER.escape("#{path}/", /[^A-Za-z0-9\-._~\/:]/)
        URI::File.build(path: escaped).to_s
      end

      def teach_guidance(rule_id, locale)
        @teach_guidance ||= {}
        @teach_guidance[[rule_id, locale]] ||= if locale == "ja"
          translations = YAML.safe_load(File.read(File.expand_path("../../locales/ja.yml", __dir__), encoding: "UTF-8"), aliases: false)
          translations.dig("guidance", rule_id) || translations.dig("rules", rule_id)
        else
          path = File.expand_path("../../docs/rules/#{rule_id}.md", __dir__)
          File.read(path, encoding: "UTF-8").split(/\n\s*\n/)[1]&.gsub(/\s+/, " ")&.strip if File.file?(path)
        end
      end

      def display_path(path)
        return path.tr("\\", "/").delete_prefix("./") unless Pathname.new(path).absolute?
        absolute = File.expand_path(path)
        Pathname.new(absolute).relative_path_from(Pathname.new(Dir.pwd)).to_s.tr("\\", "/")
      end

      def xml_escape(value)
        value.to_s.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "\uFFFD")
             .gsub(/[&<>"']/) { |char| { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;", "'" => "&apos;" }.fetch(char) }
      end

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
          opts.on("-f", "--format FORMAT", %w[text json github sarif markdown junit checkstyle rdjson]) { |value| options[:format] = value }
          opts.on("-o", "--out PATH") { |value| options[:out] = value }
          opts.on("-c", "--config PATH") { |value| options[:config] = value }
          opts.on("--fail-level LEVEL", %w[error warning info]) { |value| options[:fail_level] = value }
          opts.on("--only RULES") { |value| options[:only] = value.split(",") }
          opts.on("--except RULES") { |value| options[:except] = value.split(",") }
          opts.on("--switch-states MODE", %w[none single all]) { |value| options[:switch_states] = value }
          opts.on("--timeout SECONDS", Float) { |value| options[:timeout] = value }
          opts.on("--stdin PATH") { |value| options[:stdin] = value }
          opts.on("--baseline PATH") { |value| options[:baseline] = value }
          opts.on("--generate-baseline PATH") { |value| options[:generate_baseline] = value }
          opts.on("--diff REF") { |value| options[:diff] = value }
          opts.on("--teach") { options[:teach] = true }
          opts.on("--list-rules") { options[:list_rules] = true }
          opts.on("--explain RULE") { |value| options[:explain] = value }
          opts.on("--locale LOCALE", %w[ja en]) { |value| options[:locale] = value }
          opts.on("-v", "--version") { puts "bklint #{VERSION}"; return 0 }
          opts.on("-h", "--help") { puts opts; return 0 }
        end
        parser.parse!(argv)
        raise Error, "timeout must be positive" if options[:timeout] && !options[:timeout].positive?
        raise Error, "--teach requires --format text" if options[:teach] && options[:format] != "text"
        locale = options[:locale] || locale_from_environment
        return list_rules(locale) if options[:list_rules]
        return explain(options[:explain], locale) if options[:explain]
        raise Error, "--stdin accepts no additional file arguments" if options[:stdin] && !argv.empty?
        raise Error, "--stdin PATH requires a .bk.rb path" if options[:stdin] && !options[:stdin].end_with?(".bk.rb")
        raise Error, "choose --baseline or --generate-baseline" if options[:baseline] && options[:generate_baseline]
        raise Error, "--diff cannot be combined with a baseline" if options[:diff] && (options[:baseline] || options[:generate_baseline])
        files = options[:stdin] ? [options[:stdin]] : expand_inputs(argv)
        source = $stdin.read if options[:stdin]
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
          Engine.new(config: config, locale: locale).run([path], only: options[:only], except: options[:except],
                                                         timeout: options[:timeout] || 10, source: source)
        end
        if options[:generate_baseline]
          count = Baseline.new(options[:generate_baseline]).write(results)
          puts "Wrote #{count} baseline offenses to #{options[:generate_baseline]}"
          return 0
        end
        results = Baseline.new(options[:baseline]).filter(results) if options[:baseline]
        results = filter_diff(results, files, options, locale: locale) if options[:diff]
        formatter = Formatter.new
        output = case options[:format]
        when "json" then formatter.json(results)
        when "github" then formatter.github(results)
        when "sarif" then formatter.sarif(results)
        when "markdown" then formatter.markdown(results)
        when "junit" then formatter.junit(results)
        when "checkstyle" then formatter.checkstyle(results)
        when "rdjson" then formatter.rdjson(results)
        else formatter.text(results, locale: locale, teach: options[:teach])
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

      def filter_diff(results, files, options, locale:)
        root, error, status = Open3.capture3("git", "rev-parse", "--show-toplevel")
        raise Error, "--diff requires a Git repository: #{error.strip}" unless status.success?

        root = root.strip
        Dir.mktmpdir("bklint-diff-") do |directory|
          archive = File.join(directory, "base.tar")
          base_root = File.join(directory, "base")
          FileUtils.mkdir_p(base_root)
          _out, error, status = Open3.capture3("git", "-C", root, "archive", "--format=tar", "-o", archive, options[:diff])
          raise Error, "cannot read Git revision #{options[:diff]}: #{error.strip}" unless status.success?
          _out, error, status = Open3.capture3("tar", "-xf", "base.tar", "-C", "base", chdir: directory)
          raise Error, "cannot unpack Git revision #{options[:diff]}: #{error.strip}" unless status.success?

          baseline_files = files.flat_map do |file|
            relative = Pathname.new(File.expand_path(file)).relative_path_from(Pathname.new(root)).to_s
            raise Error, "--diff input is outside the Git repository: #{file}" if relative == ".." || relative.start_with?("../")

            base_path = File.join(base_root, relative)
            next [] unless File.file?(base_path)

            config = Config.new(options[:config] || nearest_config(base_path))
            config.data["AllRules"] ||= {}
            config.data["AllRules"]["SwitchStates"] = options[:switch_states] if options[:switch_states]
            Engine.new(config: config, locale: locale).run([base_path], only: options[:only], except: options[:except],
                                                            timeout: options[:timeout] || 10).map do |result|
              result[:path] = File.expand_path(file)
              result[:offenses].each do |item|
                if item.location&.path&.start_with?("#{base_root}/")
                  item.location.path = File.join(root, item.location.path.delete_prefix("#{base_root}/"))
                end
                item.message = item.message.gsub(base_root, root)
              end
              result
            end
          end
          baseline = Baseline.new(File.join(directory, "baseline.json"))
          baseline.write(baseline_files)
          baseline.filter(results)
        end
      end

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
        data.is_a?(Hash) && [1, 2].include?(data["schema_version"])
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
        if locale == "ja"
          translations = YAML.safe_load(File.read(File.expand_path("../../locales/ja.yml", __dir__), encoding: "UTF-8"), aliases: false) || {}
          description = translations.dig("rules", rule.id) || rule.description
          guidance = translations.dig("guidance", rule.id)
          puts "# #{rule.id}\n\n#{description}#{guidance ? "\n\n#{guidance}" : ""}"
          return 0
        end
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
