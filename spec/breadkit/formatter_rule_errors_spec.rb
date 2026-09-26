# frozen_string_literal: true

require "tmpdir"

RSpec.describe "formatter and rule errors" do
  it "percent-encodes a SARIF source root with spaces and non-ASCII characters" do
    Dir.mktmpdir do |root_directory|
      directory = File.join(root_directory, "lint space Δ")
      Dir.mkdir(directory)
      Dir.chdir(directory) do
        item = Breadkit::Lint::Offense.new(rule: "Layout/InvalidHole", severity: "error", message: "bad hole",
                                          targets: {})
        sarif = JSON.parse(Breadkit::Lint::Formatter.new.sarif([{ path: "board.bk.rb", offenses: [item] }]))
        root = sarif.dig("runs", 0, "originalUriBaseIds", "%SRCROOT%", "uri")
        expect(root).to include("%20", "%CE%94")
        expect(root).to end_with("/")
      end
    end
  end

  it "turns a missing custom check method into a per-rule fatal offense" do
    missing_check = Class.new(Breadkit::Lint::Rule) do
      rule "Custom/MissingCheck", severity: :error, description: "Missing check implementation"
    end
    Dir.mktmpdir do |directory|
      path = File.join(directory, "board.bk.rb")
      File.write(path, "board :half\n")
      offenses = Breadkit::Lint::Engine.new.run([path], only: ["Custom/MissingCheck"]).first[:offenses]
      expect(offenses.map(&:rule)).to include("Fatal/RuleError")
    end
  ensure
    Breadkit::Lint::Registry.all.delete(missing_check) if missing_check
  end
end
