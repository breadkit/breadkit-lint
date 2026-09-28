# frozen_string_literal: true

require "prism"
require "tempfile"
require "did_you_mean"

module Breadkit
  module Lint
    class SourceEditor
      Edit = Struct.new(:start, :finish, :replacement, :description, :line, keyword_init: true)

      def initialize(path, source: nil, circuit: nil)
        @path = path
        @source = source || File.binread(path)
        @circuit = circuit
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
          if node != call && node.location.start_line != offense.location.line
            offense.location = Breadkit::SourceLocation.new(path: offense.location.path, line: node.location.start_line)
          end
        end
      end

      def plan(offenses)
        return [] unless @valid

        @occupied = occupied_holes if @circuit
        edits = offenses.filter_map do |offense|
          case offense.rule
          when "Layout/InvalidColor" then color_edit(offense)
          when "Lint/RedundantDisable" then disable_edit(offense)
          when "Intent/ConnectionMismatch" then label_edit(offense)
          when "Layout/HoleConflict" then wire_hole_edit(offense)
          end
        end.uniq { |edit| [edit.start, edit.finish, edit.replacement] }.sort_by(&:start)
        edits.each_with_object([]) do |edit, safe|
          safe << edit unless safe.any? { |prior| edit.start < prior.finish && prior.start < edit.finish }
        end
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

        calls = @calls_by_line[location.line] || @calls.select do |call|
          call.location.start_line < location.line && location.line <= call.location.end_line
        end
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

      def label_edit(offense)
        return unless @circuit && !@source.match?(/^__END__\s*$/)
        return unless Array(offense.targets[:components]).empty? && Array(offense.targets[:nets]).one?
        call = call_for(offense, :net)
        args = call&.arguments&.arguments
        return unless args&.length == 2 && args[0].is_a?(Prism::SymbolNode) && args[1].is_a?(Prism::StringNode)

        name, reference = args[0].value.to_s, args[1].unescaped
        return unless physical_anchor?(reference)
        net = @circuit.net_of(reference)
        return unless net && net.labels.empty? && net.name != name
        return if @circuit.labels.any? { |label| label.name == name }
        expected_names = @circuit.expectations.flat_map do |expectation|
          Array(expectation["entries"] || expectation[:entries]).filter_map do |entry|
            next unless (entry["kind"] || entry[:kind]) == "net"
            refs = Array(entry["refs"] || entry[:refs])
            names = refs.filter_map { |ref| @circuit.net_of(ref)&.name }.uniq
            entry["name"] || entry[:name] if names == [net.name]
          end
        end.uniq
        return unless expected_names == [name]
        return unless @calls.count { |node| node.name == :net && node.arguments&.arguments&.first&.location&.slice == args[0].location.slice } == 1

        newline = @source.include?("\r\n") ? "\r\n" : "\n"
        prefix = @source.end_with?("\n") ? "" : newline
        declaration = "net #{args[0].location.slice}, at: #{args[1].location.slice}"
        Edit.new(start: @source.bytesize, finish: @source.bytesize, replacement: "#{prefix}#{declaration}#{newline}",
                 description: "add net label #{name}", line: offense.location.line)
      end

      def physical_anchor?(reference)
        return true if @circuit.board.hole(reference)

        ref, pin = reference.split(".", 2)
        pin && @circuit.components[ref]&.pin(pin)&.hole_id
      end

      def wire_hole_edit(offense)
        return unless @circuit && Array(offense.targets[:wires]).one? && Array(offense.targets[:holes]).one?
        call = call_for(offense, :wire)
        args = call&.arguments&.arguments
        return unless args && args.length >= 2
        source_wires = @circuit.wires.select do |wire|
          wire.location&.line == call.location.start_line && wire.location.path &&
            File.expand_path(wire.location.path) == File.expand_path(@path)
        end
        return unless source_wires.one? && source_wires.first.id == offense.targets[:wires].first

        current = offense.targets[:holes].first
        endpoints = args.first(2).select { |node| node.is_a?(Prism::StringNode) && node.unescaped == current }
        return unless endpoints.one?

        origin = @circuit.board.hole(current)
        return unless origin && !@circuit.board.solder_pad?(current)
        candidates = Array(@circuit.board.strip(current)).filter_map { |id| @circuit.board.hole(id) }
                          .reject { |hole| @occupied[hole.id] }
        replacement = candidates.min_by { |hole| [(hole.x - origin.x)**2 + (hole.y - origin.y)**2, hole.id] }
        return unless replacement

        node = endpoints.first
        original = node.location.slice
        quote = original[0]
        return unless %w[' "].include?(quote) && original[-1] == quote

        @occupied[replacement.id] = true
        Edit.new(start: node.location.start_offset, finish: node.location.end_offset,
                 replacement: "#{quote}#{replacement.id}#{quote}",
                 description: "move wire endpoint #{current} to #{replacement.id}", line: offense.location.line)
      end

      def occupied_holes
        occupied = {}
        @circuit.components.each_value do |component|
          component.pins.each_value { |pin| occupied[pin.hole_id] = true if pin.hole_id }
        end
        @circuit.supplies.each do |supply|
          [supply.plus, supply.minus].each { |id| occupied[id] = true if @circuit.board.hole(id) }
        end
        @circuit.wires.each do |wire|
          next unless wire.electrical
          [wire.from, wire.to].each { |id| occupied[id] = true if @circuit.board.hole(id) }
        end
        occupied
      end
    end
  end
end
