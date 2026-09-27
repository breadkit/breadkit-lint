# frozen_string_literal: true

require "tmpdir"

RSpec.describe "switch state budget" do
  let(:source) do
    <<~RUBY
      board :half
      button :SW1, at: 'e10'
      button :SW2, at: 'e15'
      button :SW3, at: 'e20'
    RUBY
  end

  it "reports an incomplete exhaustive analysis instead of silently falling back" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "switches.bk.rb")
      File.write(path, source)
      config = Breadkit::Lint::Config.new
      config.data.fetch("AllRules")["SwitchStates"] = "all"
      config.data.fetch("AllRules")["StateBudget"] = 4

      result = Breadkit::Lint::Engine.new(config: config).run([path]).first
      expect(result[:offenses].map(&:rule)).to eq(["Fatal/EvaluationError"])
      expect(result[:offenses].first.message).to include("8", "4")

      config.data.fetch("AllRules")["StateBudget"] = 8
      expect(Breadkit::Lint::Engine.new(config: config).run([path]).first[:offenses].map(&:rule))
        .not_to include("Fatal/EvaluationError")
    end
  end

  it "accepts a positive integer from config and command line" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "switches.bk.rb")
      config_path = File.join(directory, ".bklint.yml")
      File.write(input, source)
      File.write(config_path, "AllRules:\n  StateBudget: 0\n")
      expect { Breadkit::Lint::Config.new(config_path) }.to raise_error(Breadkit::Lint::Error, /StateBudget/)
      File.write(config_path, "AllRules:\n  StateBudget: 8\n")
      expect(Breadkit::Lint::Config.new(config_path).state_budget).to eq(8)

      expect { expect(Breadkit::Lint::CLI.new.run(["--switch-states", "all", "--state-budget", "4", input])).to eq(2) }
        .to output(/8.*4/).to_stdout
      expect { expect(Breadkit::Lint::CLI.new.run(["--state-budget", "0", input])).to eq(2) }
        .to output(/state budget/i).to_stderr
    end
  end

  it "rejects more than the default 256 combinations in all mode" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "switches.bk.rb")
      switches = (0...9).map { |index| "button :SW#{index + 1}, at: 'e#{3 + index * 5}'" }
      File.write(input, (["board :full"] + switches).join("\n"))
      config = Breadkit::Lint::Config.new
      config.data.fetch("AllRules")["SwitchStates"] = "all"
      expect(config.state_budget).to eq(256)
      result = Breadkit::Lint::Engine.new(config: config).run([input]).first
      expect(result[:offenses].map(&:rule)).to eq(["Fatal/EvaluationError"])
      expect(result[:offenses].first.message).to include("512", "256")
    end
  end

  it "checks explicitly named states without enumerating unrelated combinations" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "switches.bk.rb")
      switches = (0...9).map { |index| "button :SW#{index + 1}, at: 'e#{3 + index * 5}'" }
      expectation = "expect(when: 'SW1,SW2') { isolated 'SW1.1', 'SW1.3' }"
      File.write(input, (["board :full"] + switches + [expectation]).join("\n"))

      result = Breadkit::Lint::Engine.new.run([input], only: ["Intent/ConnectionMismatch"]).first
      expect(result[:offenses].map(&:rule)).not_to include("Fatal/EvaluationError")
      expect(result[:offenses].map(&:state)).to include("SW1,SW2")
    end
  end
end
