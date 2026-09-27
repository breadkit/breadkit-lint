# frozen_string_literal: true

require "breadkit/lint/rake_task"

RSpec.describe Breadkit::RakeTask do
  it "runs bklint on configured files and fails the Rake task for errors" do
    previous = Rake.application
    Rake.application = Rake::Application.new
    cli = instance_double(Breadkit::Lint::CLI)
    allow(Breadkit::Lint::CLI).to receive(:new).and_return(cli)
    expect(cli).to receive(:run).with(["--format", "json", "circuit.bk.rb"]).and_return(0, 1)
    described_class.new(:circuits) do |task|
      task.options = ["--format", "json"]
      task.files = ["circuit.bk.rb"]
    end
    expect { Rake::Task[:circuits].invoke }.not_to raise_error
    described_class.new(:failed) do |task|
      task.options = ["--format", "json"]
      task.files = ["circuit.bk.rb"]
    end
    expect { Rake::Task[:failed].invoke }.to raise_error(Breadkit::Lint::Error, /status 1/)
  ensure
    Rake.application = previous
  end
end
