# frozen_string_literal: true

require "prism"
require "tempfile"
require "did_you_mean"

module Breadkit
  module Lint
    class SourceEditor
      Edit = Struct.new(:start, :finish, :replacement, :description, :line, keyword_init: true)

      def initialize(path, source: nil)
        @path = path
        @source = source || File.binread(path)
        parsed = Prism.parse(@source)
        @valid = parsed.errors.empty?
        @calls = []
        collect(parsed.value) if @valid
        @calls_by_line = @calls.group_by { |call| call.location.start_line }
      end

      def annotate(offenses)
        return unless @valid

        offenses.each do |offense|
          call = call_for(offense)
          next unless call
          node = offense.rule == "Layout/InvalidColor" && wire_color_node(call) || call
          offense.column = node.location.start_character_column + 1
        end
      end

      def plan(offenses)
        return [] unless @valid

        offenses.filter_map do |offense|
          case offense.rule
          when "Layout/InvalidColor" then color_edit(offense)
          when "Lint/RedundantDisable" then disable_edit(offense)
          end
        end.uniq { |edit| [edit.start, edit.finish, edit.replacement] }.sort_by(&:start)
      end

      def apply(edits)
        return false if edits.empty? || File.symlink?(@path)
        raise Error, "source changed while fixing #{@path}" unless File.binread(@path) == @source

        updated = @source.dup
        edits.reverse_each { |edit| updated[edit.start...edit.finish] = edit.replacement }
        mode = File.stat(@path).mode & 0o7777
        Tempfile.create([".bklint-fix-", ".tmp"], File.dirname(@path)) do |temp|
          temp.binmode
          temp.chmod(mode)
          temp.write(updated)
          temp.flush
          temp.fsync
          temp.close
          raise Error, "source changed while fixing #{@path}" unless File.binread(@path) == @source
          File.rename(temp.path, @path)
        end
        true
      end

      private

      def collect(node)
        return unless node
        @calls << node if node.is_a?(Prism::CallNode) && node.receiver.nil?
        node.compact_child_nodes.each { |child| collect(child) }
      end

      def call_for(offense, name = nil)
        location = offense.location
        return unless location&.line && location.path && File.expand_path(location.path) == File.expand_path(@path)

        calls = @calls_by_line[location.line] || []
        return unless calls.one?
        return if name && calls.first.name != name

        calls.first
      end

      def wire_color_node(call)
        return unless call.name == :wire
        hashes = Array(call.arguments&.arguments).grep(Prism::KeywordHashNode)
        entries = hashes.flat_map(&:elements).grep(Prism::AssocNode).select do |entry|
          entry.key.is_a?(Prism::SymbolNode) && entry.key.value == "color"
        end
        entries.first.value if entries.one?
      end

      def color_edit(offense)
        return if Array(offense.targets[:wires]).empty?
        call = call_for(offense, :wire)
        return unless call
        node = wire_color_node(call)
        return unless node.is_a?(Prism::SymbolNode) || node.is_a?(Prism::StringNode)

        color = node.is_a?(Prism::StringNode) ? node.unescaped : node.value
        return unless color.match?(/\A[a-z]+\z/i) && !Breadkit::Color.valid?(color)
        candidates = Breadkit::Color::NAMES.select { |name| DidYouMean::Levenshtein.distance(color.downcase, name) == 1 }
        return unless candidates.one?

        original = node.location.slice
        corrected = if node.is_a?(Prism::SymbolNode) && original == ":#{color}"
          ":#{candidates.first}"
        elsif node.is_a?(Prism::StringNode) && original.match?(/\A(["'])[a-z]+\1\z/i)
          "#{original[0]}#{candidates.first}#{original[0]}"
        end
        return unless corrected

        Edit.new(start: node.location.start_offset, finish: node.location.end_offset, replacement: corrected,
                 description: "replace wire color #{original} with #{corrected}", line: offense.location.line)
      end

      def disable_edit(offense)
        call = call_for(offense, :lint_disable)
        return unless call && call.location.start_line == call.location.end_line

        line_start = @source.lines.take(call.location.start_line - 1).sum(&:bytesize)
        newline = @source.index("\n", line_start)
        line_end = newline ? newline + 1 : @source.bytesize
        content_end = newline && @source.getbyte(newline - 1) == 13 ? newline - 1 : (newline || line_end)
        before = @source.byteslice(line_start...call.location.start_offset)
        after = @source.byteslice(call.location.end_offset...content_end)
        return unless before.match?(/\A[ \t]*\z/) && after.match?(/\A[ \t]*\z/)

        Edit.new(start: line_start, finish: line_end, replacement: "",
                 description: "remove unused lint_disable", line: offense.location.line)
      end
    end
  end
end
