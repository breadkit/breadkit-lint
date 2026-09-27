# frozen_string_literal: true

require "json_schemer"

RSpec.describe "lint JSON schema" do
  it "validates formatter output and rejects malformed counts" do
    path = File.expand_path("../../site/schemas/lint-v1.json", __dir__)
    schemer = JSONSchemer.schema(JSON.parse(File.read(path, encoding: "UTF-8")))
    offense = Breadkit::Lint::Offense.new(
      rule: "Layout/HoleConflict", severity: "error", message: "two pins in a1",
      location: Breadkit::SourceLocation.new(path: "circuit.bk.rb", line: 2),
      state: nil, targets: { holes: ["a1"] }, column: 7
    )
    files = [{ path: "circuit.bk.rb", skipped: false, offenses: [offense] }]
    result = JSON.parse(Breadkit::Lint::Formatter.new.json(files))
    expect(schemer.valid?(result)).to be(true)
    expect(result.dig("files", 0, "offenses", 0, "docs_url"))
      .to eq("https://breadkit.github.io/breadkit-lint/rules/Layout/HoleConflict/")
    result["summary"]["errors"] = -1
    expect(schemer.valid?(result)).to be(false)
  end

  it "links SARIF rules to the same published reference pages" do
    result = JSON.parse(Breadkit::Lint::Formatter.new.sarif([]))
    rules = result.dig("runs", 0, "tool", "driver", "rules")
    rule = rules.find { |item| item["id"] == "Electrical/ShortCircuit" }
    expect(rule["helpUri"]).to eq("https://breadkit.github.io/breadkit-lint/rules/Electrical/ShortCircuit/")
  end
end
