# frozen_string_literal: true

require "json_schemer"

RSpec.describe "lint JSON schema" do
  it "validates formatter output and rejects malformed counts" do
    path = File.expand_path("../../site/schemas/lint-v1.json", __dir__)
    schemer = JSONSchemer.schema(JSON.parse(File.read(path, encoding: "UTF-8")))
    offense = Breadkit::Lint::Offense.new(
      rule: "Layout/HoleConflict", severity: "error", message: "two pins in a1",
      location: Breadkit::SourceLocation.new(path: "circuit.bk.rb", line: 2),
      state: nil, targets: { holes: ["a1"] }
    )
    files = [{ path: "circuit.bk.rb", skipped: false, offenses: [offense] }]
    result = JSON.parse(Breadkit::Lint::Formatter.new.json(files))
    expect(schemer.valid?(result)).to be(true)
    result["summary"]["errors"] = -1
    expect(schemer.valid?(result)).to be(false)
  end
end
