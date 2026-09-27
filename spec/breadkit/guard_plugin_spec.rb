# frozen_string_literal: true

RSpec.describe "Guard integration" do
  before do
    stub_const("Guard", Module.new)
    stub_const("Guard::Plugin", Class.new do
      attr_reader :options

      def initialize(options = {})
        @options = options
      end
    end)
    $LOADED_FEATURES << "guard/plugin.rb"
    load File.expand_path("../../lib/guard/breadkit.rb", __dir__)
  end

  after { $LOADED_FEATURES.delete("guard/plugin.rb") }

  it "lints changed circuits and reruns all configured inputs for a part change" do
    cli = instance_double(Breadkit::Lint::CLI)
    allow(Breadkit::Lint::CLI).to receive(:new).and_return(cli)
    plugin = Guard::Breadkit.new(files: ["circuits"], args: ["--format", "github"])
    allow(File).to receive(:file?).with("circuits/led.bk.rb").and_return(true)
    expect(cli).to receive(:run).with(["--format", "github", "circuits/led.bk.rb"]).and_return(0)
    plugin.run_on_changes(["circuits/led.bk.rb"])
    expect(cli).to receive(:run).with(["--format", "github", "circuits"]).and_return(0)
    plugin.run_on_changes(["parts/custom.yml"])
  end

  it "signals a Guard task failure when lint finds an error" do
    cli = instance_double(Breadkit::Lint::CLI, run: 1)
    allow(Breadkit::Lint::CLI).to receive(:new).and_return(cli)
    plugin = Guard::Breadkit.new(files: ["circuits"])
    expect(catch(:task_has_failed) { plugin.run_all; :passed }).to be_nil
  end
end
