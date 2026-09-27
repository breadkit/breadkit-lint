# frozen_string_literal: true

require "tmpdir"
require "stringio"

RSpec.describe "multi-board lint guard" do
  def with_multi_board_files
    Dir.mktmpdir do |directory|
      dsl = File.join(directory, "boards.bk.rb")
      File.write(dsl, <<~RUBY)
        board :mini, as: :B1
        board :mini, as: :B2
        wire "B1.a1", "B2.a1"
      RUBY
      circuit = Breadkit::Resolver.new.call(Breadkit::DSL.load_file(dsl))
      ir = File.join(directory, "boards.json")
      File.write(ir, JSON.pretty_generate(circuit.to_ir))
      yield dsl, ir
    end
  end

  it "reports one explicit fatal diagnostic for DSL and v2 IR without running single-board rules" do
    with_multi_board_files do |dsl, ir|
      expect(JSON.parse(File.read(ir)).fetch("schema_version")).to eq(2)
      [dsl, ir].each do |path|
        engine = Breadkit::Lint::Engine.new
        results = engine.run([path], only: ["Layout/InvalidHole"])
        expect(results.first[:offenses].map(&:rule)).to eq(["Fatal/UnsupportedMultiBoard"])
        expect(results.first[:offenses].first.message).to include("multi-board", "not supported")
        expect(engine.fatal?(results)).to be(true)
      end
    end
  end

  it "returns an error status and a readable CLI message for v2 IR" do
    with_multi_board_files do |_dsl, ir|
      output = StringIO.new
      previous = $stdout
      $stdout = output
      expect(Breadkit::Lint::CLI.new.run([ir])).to eq(2)
      expect(output.string).to include("Fatal/UnsupportedMultiBoard", "multi-board circuits are not supported")
    ensure
      $stdout = previous
    end
  end
end
