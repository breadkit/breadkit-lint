# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Electrical/I2CPullupMissing" do
  def inspect_source(source, boards: "board :half")
    Dir.mktmpdir do |directory|
      path = File.join(directory, "i2c.bk.rb")
      File.write(path, <<~RUBY + source)
        #{boards}
        File.write(File.join(__dir__, "sensor.yml"), "id: sensor\\nplacement: offboard\\npins:\\n  - {num: 1, name: SDA, role: data}\\n  - {num: 2, name: SCL, role: clock}\\n")
        use_parts File.join(__dir__, "sensor.yml")
        offboard :S, :sensor, address: "0x44"
      RUBY
      Breadkit::Lint::Engine.new.run([path], only: ["Electrical/I2CPullupMissing"]).first[:offenses]
    end
  end

  let(:base) do
    <<~RUBY
      supply :V, voltage: 3.3, plus: "T+1", minus: "T-1"
      wire "S.SDA", "a10"
      wire "S.SCL", "a12"
    RUBY
  end

  it "advises for each externally wired I2C line without a modeled pullup" do
    offenses = inspect_source(base)

    expect(offenses.map(&:rule)).to eq(["Electrical/I2CPullupMissing", "Electrical/I2CPullupMissing"])
    expect(offenses.map(&:severity)).to eq(%w[info info])
    expect(offenses.map(&:message)).to include(include("SDA"), include("SCL"))
  end

  it "accepts a positive fixed resistor from each line to the supply positive net" do
    source = base + <<~RUBY
      resistor :R1, "4.7k", pins: %w[b10 b11]
      wire "c11", "T+2"
      resistor :R2, "4.7k", pins: %w[b12 b13]
      wire "c13", "T+3"
    RUBY

    expect(inspect_source(source)).to be_empty
  end

  it "still reports an unpulled line and does not count a zero-ohm link" do
    source = base + <<~RUBY
      resistor :R1, "4.7k", pins: %w[b10 b11]
      wire "c11", "T+2"
      resistor :R2, "0", pins: %w[b12 b13]
      wire "c13", "T+3"
    RUBY

    expect(inspect_source(source).map(&:message)).to contain_exactly(include("SCL"))
  end

  it "does not mistake a resistor leaving a directly tied supply net for a pullup" do
    source = <<~RUBY
      supply :V, voltage: 3.3, plus: "T+1", minus: "T-1"
      wire "S.SDA", "T+2"
      wire "S.SCL", "a12"
      resistor :R1, "4.7k", pins: %w[T+3 a20]
    RUBY

    expect(inspect_source(source).map(&:message)).to include(include("SDA"), include("SCL"))
  end

  it "skips an unpowered bus and an isolated pin with no external connection" do
    expect(inspect_source("wire 'S.SDA', 'a10'\nwire 'S.SCL', 'a12'\n")).to be_empty
    expect(inspect_source("supply :V, voltage: 3.3, plus: 'T+1', minus: 'T-1'\n")).to be_empty
  end

  it "does not borrow a supply from an independent board" do
    source = <<~RUBY
      supply :V, voltage: 3.3, plus: "A.T+1", minus: "A.T-1"
      wire "S.SDA", "B.a10"
      wire "S.SCL", "B.a12"
    RUBY

    expect(inspect_source(source, boards: "board :half, as: :A\nboard :half, as: :B")).to be_empty
  end

  it "supports a released single-board core without board_id_for" do
    allow_any_instance_of(Breadkit::Board).to receive(:respond_to?).and_call_original
    allow_any_instance_of(Breadkit::Board).to receive(:respond_to?).with(:board_id_for).and_return(false)
    allow_any_instance_of(Breadkit::Board).to receive(:board_id_for).and_raise(NoMethodError)

    expect(inspect_source(base).map(&:rule)).to eq(["Electrical/I2CPullupMissing", "Electrical/I2CPullupMissing"])
  end
end
