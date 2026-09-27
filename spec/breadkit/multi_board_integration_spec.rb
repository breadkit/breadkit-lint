# frozen_string_literal: true

require "tmpdir"
require "stringio"

RSpec.describe "multi-board lint integration" do
  def check(source, only: nil, boards: "board :half, as: :B1\nboard :half, as: :B2")
    Dir.mktmpdir do |directory|
      path = File.join(directory, "boards.bk.rb")
      File.write(path, "#{boards}\n#{source}")
      result = Breadkit::Lint::Engine.new.run([path], only: only).first
      yield result, path if block_given?
      result[:offenses]
    end
  end

  it "detects a short made through a cross-board jumper and respects a suppression" do
    source = <<~RUBY
      supply :USB, voltage: 5, plus: 'B1.a1', minus: 'B1.a3'
      wire 'B1.b1', 'B2.a1'
      wire 'B2.b1', 'B1.b3'
    RUBY
    found = check(source, only: ["Electrical/ShortCircuit"])
    expect(found.map(&:rule)).to eq(["Electrical/ShortCircuit"])
    expect(found.first.targets[:wires]).to include("W1", "W2")
    suppressed_source = source + "lint_disable 'Electrical/ShortCircuit'\n"
    suppressed = check(suppressed_source, only: ["Electrical/ShortCircuit"]) do |_result, dsl|
      circuit = Breadkit::Resolver.new.call(Breadkit::DSL.load_file(dsl))
      ir = File.join(File.dirname(dsl), "suppressed.json")
      File.write(ir, JSON.pretty_generate(circuit.to_ir))
      json_result = Breadkit::Lint::Engine.new.run([ir], only: ["Electrical/ShortCircuit"]).first
      expect(json_result[:offenses]).to be_empty
    end
    expect(suppressed).to be_empty
  end

  it "keeps rails independent and interprets polarity per named board" do
    source = <<~RUBY
      supply :A, voltage: 5, plus: 'B1.B+1', minus: 'B1.B-1'
      supply :B, voltage: 3.3, plus: 'B2.B-1', minus: 'B2.B+1'
    RUBY
    found = check(source, only: %w[Electrical/ShortCircuit Electrical/RailPolarityMismatch])
    expect(found.map(&:rule)).to eq(["Electrical/RailPolarityMismatch"])
    expect(found.first.targets[:holes]).to all(start_with("B2."))
    cross_board = check("supply :A, voltage: 5, plus: 'B1.B-1', minus: 'B2.B+1'\n",
                        only: ["Electrical/RailPolarityMismatch"])
    expect(cross_board).to be_empty
  end

  it "checks split rail segments only within their own board" do
    boards = "board :full, as: :B1, split_rails: true\nboard :full, as: :B2, split_rails: true"
    source = "supply :USB, voltage: 5, plus: 'B1.B+1', minus: 'B1.B-1'\nwire 'B1.a10', 'B1.B+30'\n"
    found = check(source, only: ["Electrical/SplitRail"], boards: boards)
    expect(found.map(&:rule)).to eq(["Electrical/SplitRail"])
    expect(found.first.targets[:holes]).to all(start_with("B1."))
  end

  it "checks placement on the owning board without confusing equal local hole names" do
    clean = check("resistor :R1, '330', pins: %w[B1.a1 B1.a3]\nresistor :R2, '330', pins: %w[B2.a1 B2.a3]\n",
                  only: ["Layout/HoleConflict"])
    expect(clean).to be_empty
    conflict = check("resistor :R1, '330', pins: %w[B1.a1 B1.a3]\nresistor :R2, '330', pins: %w[B2.a1 B2.a3]\nresistor :R3, '330', pins: %w[B2.a1 B2.a4]\n",
                     only: ["Layout/HoleConflict"])
    expect(conflict.map(&:rule)).to eq(["Layout/HoleConflict"])
    expect(conflict.first.targets[:holes]).to eq(["B2.a1"])
  end

  it "keeps module body checks on the owning board" do
    source = "part :P, :pico, at: 'B2.d1'\nresistor :R1, '330', pins: %w[B1.e10 B1.a25]\n"
    expect(check(source, only: ["Layout/HoleCovered"])).to be_empty
    found = check(source + "resistor :R2, '330', pins: %w[B2.e10 B2.a25]\n", only: ["Layout/HoleCovered"])
    expect(found.map(&:rule)).to eq(["Layout/HoleCovered"])
    expect(found.first.targets[:holes]).to eq(["B2.e10"])
  end

  it "produces the same findings from DSL and v2 IR" do
    source = "supply :USB, voltage: 5, plus: 'B1.a1', minus: 'B1.a3'\nwire 'B1.b1', 'B2.a1'\nwire 'B2.b1', 'B1.b3'\n"
    check(source, only: ["Electrical/ShortCircuit"]) do |dsl_result, dsl|
      circuit = Breadkit::Resolver.new.call(Breadkit::DSL.load_file(dsl))
      ir = File.join(File.dirname(dsl), "boards.json")
      File.write(ir, JSON.pretty_generate(circuit.to_ir))
      expect(JSON.parse(File.read(ir)).fetch("schema_version")).to eq(2)
      json_result = Breadkit::Lint::Engine.new.run([ir], only: ["Electrical/ShortCircuit"]).first
      expect(json_result[:offenses].map { |offense| [offense.rule, offense.targets] })
        .to eq(dsl_result[:offenses].map { |offense| [offense.rule, offense.targets] })
    end
  end

  it "discovers v2 IR when scanning a directory" do
    check("") do |_result, dsl|
      circuit = Breadkit::Resolver.new.call(Breadkit::DSL.load_file(dsl))
      directory = File.join(File.dirname(dsl), "ir")
      Dir.mkdir(directory)
      File.write(File.join(directory, "boards.json"), JSON.pretty_generate(circuit.to_ir))
      output = StringIO.new
      previous = $stdout
      $stdout = output
      expect(Breadkit::Lint::CLI.new.run(["--only", "Layout/InvalidHole", directory])).to eq(0)
      expect(output.string).to include("1 file inspected")
    ensure
      $stdout = previous
    end
  end

  it "runs the full rule set without a fatal error on a valid multi-board circuit" do
    found = check("resistor :R1, '330', pins: %w[B1.a1 B1.a3]\nwire 'B1.b1', 'B2.a1'\n")
    expect(found.map(&:rule)).not_to include(a_string_starting_with("Fatal/"))
  end
end
