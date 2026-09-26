# frozen_string_literal: true

require "tmpdir"

RSpec.describe "built-in rule structure" do
  it "runs every built-in rule through its own Rule subclass" do
    Breadkit::Lint::Registry::RULES.each do |rule|
      expect(rule).to be_a(Class)
      expect(rule).to be < Breadkit::Lint::Rule
      expect(rule.instance_methods(false)).to include(:check)
    end
  end

  it "reports an unknown transistor model as a warning" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "transistor.bk.rb")
      File.write(path, "board :mini\ntransistor :Q1, 'unknown_123', pins: %w[a1 a2 a3]\n")
      result = Breadkit::Lint::Engine.new.run([path], only: ["Layout/UnknownTransistorModel"]).first
      item = result[:offenses].find { |offense| offense.rule == "Layout/UnknownTransistorModel" }
      expect(item).not_to be_nil
      expect(item.severity).to eq("warning")
      expect(item.targets[:components]).to include("Q1")
    end
  end

  it "reports unknown component options as blocking layout errors" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "option.bk.rb")
      File.write(path, "board :half\nresistor :R1, '330', pins: %w[a1 a2], not_a_real_option: true\n")
      result = Breadkit::Lint::Engine.new.run([path]).first
      item = result[:offenses].find { |offense| offense.rule == "Layout/UnknownOption" }
      expect(item).not_to be_nil
      expect(item.severity).to eq("error")
      expect(item.targets[:components]).to include("R1")
      expect(result[:skipped]).to be(true)
    end
  end
end
