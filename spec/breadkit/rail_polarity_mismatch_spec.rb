# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Electrical/RailPolarityMismatch" do
  def check(source)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\n#{source}")
      Breadkit::Lint::Engine.new.run([path], only: ["Electrical/RailPolarityMismatch"]).first[:offenses]
    end
  end

  it "warns when an explicit supply drives both rails opposite their declared polarity" do
    found = check("supply :USB, voltage: 5, plus: 'B-1', minus: 'B+1'\n")
    expect(found.map(&:rule)).to eq(["Electrical/RailPolarityMismatch"])
    expect(found.first.targets).to include(holes: %w[B-1 B+1])
    expect(found.first.message).to include("USB", "B-", "B+")
  end

  it "follows electrical wires from source terminals to rails" do
    found = check("supply :USB, voltage: 5, plus: 'a1', minus: 'f1'\nwire 'b1', 'B-1'\nwire 'g1', 'B+1'\n")
    expect(found.map(&:rule)).to eq(["Electrical/RailPolarityMismatch"])
  end

  it "checks explicitly declared source polarity on a providing module" do
    found = check("offboard :UNO, :arduino_uno\nwire 'UNO.5V', 'B-1'\nwire 'UNO.GND', 'B+1'\n")
    expect(found.map(&:rule)).to eq(["Electrical/RailPolarityMismatch"])
  end

  it "leaves correct, one-sided bipolar, isolated, and visual connections alone" do
    expect(check("supply :USB, voltage: 5, plus: 'B+1', minus: 'B-1'\n")).to be_empty
    expect(check("supply :NEG, voltage: 5, plus: 'B-1', minus: 'a1'\n")).to be_empty
    expect(check("supply :ISO, voltage: 5, plus: 'B-1', minus: 'B+1', isolated: true\n")).to be_empty
    expect(check("supply :USB, voltage: 5, plus: 'a1', minus: 'f1'\nwire 'b1', 'B-1', electrical: false\nwire 'g1', 'B+1', electrical: false\n")).to be_empty
    expect(check("supply :USB, voltage: 5, plus: 'B-1', minus: 'B+1'\nwire 'B-2', 'T+2'\n")).to be_empty
  end

  it "does not infer polarity from rail names without a declared sign" do
    Dir.mktmpdir do |directory|
      board = File.join(directory, "neutral.yml")
      File.write(board, <<~YAML)
        id: neutral
        terminal:
          columns: 3
          rows: [a, b]
          groups: [[a], [b]]
        rails:
          - {id: HIGH, side: top, order: 0}
          - {id: LOW, side: bottom, order: 0}
        rail_layout:
          segments: [[1, 3]]
      YAML
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "use_boards #{board.inspect}\nboard :neutral\nsupply :USB, voltage: 5, plus: 'LOW1', minus: 'HIGH1'\n")
      found = Breadkit::Lint::Engine.new.run([path], only: ["Electrical/RailPolarityMismatch"]).first[:offenses]
      expect(found).to be_empty
    end
  end
end
