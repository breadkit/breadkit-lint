# frozen_string_literal: true

require "tmpdir"

RSpec.describe "series resistor recommendations" do
  def lint_led(voltage:, rated: true, source: nil, extra_supply: nil, locale: "en")
    Dir.mktmpdir do |directory|
      definition = File.join(directory, "rated_led.yml")
      File.write(definition, <<~YAML)
        id: led
        override: true
        category: diode
        placement: leads
        flags: [needs_series_resistor]
        #{"forward_voltage: 2\nmax_forward_current: 0.02" if rated}
        pins:
          - {num: 1, name: anode}
          - {num: 2, name: cathode}
        polarity: {positive: anode, negative: cathode}
      YAML
      circuit = File.join(directory, "circuit.bk.rb")
      File.write(circuit, <<~RUBY)
        board :half
        use_parts #{definition.inspect}
        #{source || "supply :P, voltage: #{voltage}, plus: 'B+1', minus: 'B-1'"}
        #{extra_supply}
        led :D1, anode: 'a10', cathode: 'a11'
        wire 'b10', #{source ? "'UNO.A0'" : "'B+'"}
        wire 'b11', #{source ? "'UNO.GND'" : "'B-'"}
      RUBY
      files = Breadkit::Lint::Engine.new(locale: locale).run([circuit], only: ["Electrical/MissingSeriesResistor"])
      yield(files, files.first[:offenses].first)
    end
  end

  it "recommends the next E12 value from declared LED ratings and a direct supply" do
    lint_led(voltage: "5") do |files, item|
      expect(item.rule).to eq("Electrical/MissingSeriesResistor")
      expect(item.suggestion).to include("150Ω", "E12", "5 V", "2 V", "20 mA")
      formatted = Breadkit::Lint::Formatter.new
      expect(JSON.parse(formatted.json(files)).dig("files", 0, "offenses", 0, "suggestion")).to include("150Ω")
      expect(JSON.parse(formatted.sarif(files)).dig("runs", 0, "results", 0, "properties", "suggestion")).to include("150Ω")
      expect(formatted.text(files, teach: true)).to include("150Ω")
    end
  end

  it "uses the upper voltage bound and rounds the required resistance up to E12" do
    lint_led(voltage: "(5.0..6.0)") do |_files, item|
      expect(item.suggestion).to include("220Ω", "6 V")
    end
  end

  it "keeps the generic advice when LED ratings are absent" do
    lint_led(voltage: "5", rated: false) do |files, item|
      expect(item.suggestion).to be_nil
      expect(JSON.parse(Breadkit::Lint::Formatter.new.json(files)).dig("files", 0, "offenses", 0, "suggestion"))
        .to eq("Add a current-limiting resistor in series with the LED.")
    end
  end

  it "does not invent a voltage for an uncharacterized GPIO output" do
    lint_led(voltage: "5", source: "offboard :UNO, :arduino_uno") do |_files, item|
      expect(item.rule).to eq("Electrical/MissingSeriesResistor")
      expect(item.suggestion).to be_nil
    end
  end

  it "does not recommend a resistor when the declared forward drop exceeds the supply" do
    lint_led(voltage: "1") do |_files, item|
      expect(item.rule).to eq("Electrical/MissingSeriesResistor")
      expect(item.suggestion).to be_nil
    end
  end

  it "withholds a number when another supply drives the LED nets in reverse" do
    reverse = "supply :Q, voltage: 5, plus: 'B-2', minus: 'B+2'"
    lint_led(voltage: "5", extra_supply: reverse) do |_files, item|
      expect(item.rule).to eq("Electrical/MissingSeriesResistor")
      expect(item.suggestion).to be_nil
    end
  end

  it "localizes the numerical recommendation" do
    lint_led(voltage: "5", locale: "ja") do |files, item|
      expect(item.suggestion).to include("150Ω", "E12", "直列")
      expect(JSON.parse(Breadkit::Lint::Formatter.new.json(files, locale: "ja"))
        .dig("files", 0, "offenses", 0, "suggestion")).to include("150Ω", "直列")
    end
  end

  it "does not print an empty teaching line for an offense without guidance" do
    item = Breadkit::Lint::Offense.new(rule: "Fatal/EvaluationError", severity: "error", message: "failed", targets: {})
    report = Breadkit::Lint::Formatter.new.text([{ path: "circuit.bk.rb", offenses: [item] }], teach: true)
    expect(report).not_to include("Why:")
  end
end
