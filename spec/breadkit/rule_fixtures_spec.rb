# frozen_string_literal: true

require "tmpdir"
require "yaml"

RSpec.describe "rule fixtures" do
  fixture_path = File.expand_path("../fixtures/rules.yml", __dir__)
  cases = File.file?(fixture_path) ? YAML.safe_load_file(fixture_path) : {}

  it "provides offense and no_offense examples for every registered rule" do
    expect(cases.keys.sort).to eq(Breadkit::Lint::Registry::RULES.map(&:id).sort)
  end

  cases.each do |rule_id, examples|
    it "detects #{rule_id} in its offense fixture and clears its no_offense fixture" do
      expect(examples.keys.sort).to eq(%w[no_offense offense])
      Dir.mktmpdir do |directory|
        examples.each do |kind, source|
          path = File.join(directory, "#{kind}.bk.rb")
          File.write(path, source)
          offenses = Breadkit::Lint::Engine.new.run([path], only: [rule_id]).first[:offenses].map(&:rule)
          if kind == "offense"
            expect(offenses).to include(rule_id), source
          else
            expect(offenses).not_to include(rule_id), source
          end
        end
      end
    end
  end
end
