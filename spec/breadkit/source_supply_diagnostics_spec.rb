# frozen_string_literal: true

require "tmpdir"

RSpec.describe "offboard supply diagnostics" do
  def inspect_source(source)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "supply.bk.rb")
      File.write(path, source)
      Breadkit::Lint::Engine.new.run([path]).first
    end
  end

  it "reports a missing provided output and skips dependent electrical rules" do
    result = inspect_source(<<~RUBY)
      board :half
      supply from: "UNO.5V", plus: "T+", minus: "T-"
    RUBY

    offense = result[:offenses].find { |item| item.rule == "Layout/UnknownSupplySource" }
    expect(offense&.severity).to eq("error")
    expect(offense&.location&.line).to eq(2)
    expect(result[:skipped]).to be(true)
  end

  it "reports an ambiguous provided output without trying to route it" do
    result = inspect_source(<<~RUBY)
      board :half
      duplicate = Marshal.load(Marshal.dump(Breadkit::PartLibrary.new.find("arduino_uno").data))
      duplicate["override"] = true
      duplicate["provides"] << { "positive" => "5V", "negative" => "GND2", "voltage" => 5 }
      document.part_definitions << duplicate
      offboard :UNO, :arduino_uno
      supply from: "UNO.5V", plus: "T+", minus: "T-"
    RUBY

    offense = result[:offenses].find { |item| item.rule == "Layout/AmbiguousSupplySource" }
    expect(offense&.severity).to eq("error")
    expect(offense&.location&.line).to eq(7)
    expect(result[:skipped]).to be(true)
  end

  it "accepts a valid provided output" do
    result = inspect_source(<<~RUBY)
      board :half
      offboard :UNO, :arduino_uno
      supply from: "UNO.5V", plus: "T+", minus: "T-"
    RUBY

    expect(result[:offenses].map(&:rule)).not_to include("Layout/UnknownSupplySource", "Layout/AmbiguousSupplySource")
    expect(result[:skipped]).to be(false)
  end
end
