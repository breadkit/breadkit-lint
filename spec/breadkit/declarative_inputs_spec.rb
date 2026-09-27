# frozen_string_literal: true

require "tmpdir"
require "stringio"

RSpec.describe "declarative circuit inputs" do
  it "lints YAML and TOML circuits through the structured parser" do
    Dir.mktmpdir do |directory|
      sources = {
        "circuit.bk.yml" => "board: mini\nwires:\n  - {from: a999, to: a1}\n",
        "circuit.bk.yaml" => "board: mini\nwires:\n  - {from: a999, to: a1}\n",
        "circuit.bk.toml" => "board = \"mini\"\n[[wires]]\nfrom = \"a999\"\nto = \"a1\"\n"
      }
      sources.each do |name, source|
        path = File.join(directory, name)
        File.write(path, source)
        result = Breadkit::Lint::Engine.new.run([path], only: ["Layout/InvalidHole"]).first

        expect(result[:offenses].map(&:rule)).to eq(["Layout/InvalidHole"]), name
        expect(result[:offenses].first.location.path).to eq(File.expand_path(path))
      end
    end
  end

  it "reports malformed structured data as a located evaluation error" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "invalid.bk.yml")
      File.write(path, "board: mini\ncomponents: []\n")
      result = Breadkit::Lint::Engine.new.run([path]).first

      expect(result[:offenses].map(&:rule)).to eq(["Fatal/EvaluationError"])
      expect(result[:offenses].first.message).to include("components")
      expect(result[:offenses].first.location.path).to eq(File.expand_path(path))
      expect(result[:offenses].first.location.line).to eq(1)
    end
  end

  it "applies configured custom parts to declarative circuits" do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "sensor.yml"), "id: custom_sensor\nplacement: offboard\npins:\n  - {num: 1, name: SIG, role: input}\n")
      config_path = File.join(directory, ".bklint.yml")
      File.write(config_path, "use_parts:\n  - sensor.yml\n")
      path = File.join(directory, "circuit.bk.yml")
      File.write(path, "board: mini\noffboard:\n  - {ref: S, type: custom_sensor}\n")

      config = Breadkit::Lint::Config.new(config_path)
      result = Breadkit::Lint::Engine.new(config: config).run([path], only: ["Layout/UnknownPart"]).first
      expect(result[:offenses]).to be_empty
    end
  end

  it "explains unsupported declarative input without breaking Ruby DSL or JSON IR" do
    Dir.mktmpdir do |directory|
      ruby = File.join(directory, "circuit.bk.rb")
      yaml = File.join(directory, "circuit.bk.yml")
      json = File.join(directory, "circuit.json")
      File.write(ruby, "board :mini\n")
      File.write(yaml, "board: mini\n")
      File.write(json, JSON.pretty_generate(Breadkit.load(ruby).to_ir))
      hide_const("Breadkit::StructuredInput")

      results = Breadkit::Lint::Engine.new.run([ruby, yaml, json])
      expect(results[0][:offenses]).to be_empty
      expect(results[1][:offenses].map(&:rule)).to eq(["Fatal/EvaluationError"])
      expect(results[1][:offenses].first.message).to include("requires a newer breadkit gem")
      expect(results[2][:offenses]).to be_empty
    end
  end

  it "discovers declarative circuits while ignoring ordinary part definitions" do
    Dir.mktmpdir do |directory|
      %w[one.bk.yml two.bk.yaml three.bk.toml part.yml].each do |name|
        File.write(File.join(directory, name), "board: mini\n")
      end
      File.write(File.join(directory, "three.bk.toml"), "board = \"mini\"\n")
      output = StringIO.new
      previous = $stdout
      $stdout = output
      status = Breadkit::Lint::CLI.new.run(["--format", "json", directory])
      expect(status).to eq(0)
      paths = JSON.parse(output.string).fetch("files").map { |item| File.basename(item.fetch("path")) }
      expect(paths).to contain_exactly("one.bk.yml", "two.bk.yaml", "three.bk.toml")
    ensure
      $stdout = previous
    end
  end
end
