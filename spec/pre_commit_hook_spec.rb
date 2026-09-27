# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"

RSpec.describe "pre-commit hook" do
  let(:hook) { File.expand_path("../scripts/pre-commit", __dir__) }
  let(:invalid) { "board :half\nresistor :R1, '330', pins: %w[a1 a3]\nresistor :R2, '330', pins: %w[a1 a5]\n" }

  def fixture(staged_source, filename: "circuit.bk.rb")
    Dir.mktmpdir do |repo|
      _output, error, status = Open3.capture3("git", "init", "-q", repo)
      raise error unless status.success?

      path = File.join(repo, filename)
      File.write(path, staged_source)
      _output, error, status = Open3.capture3("git", "add", "--", filename, chdir: repo)
      raise error unless status.success?

      yield repo, path
    end
  end

  it "checks staged source rather than invalid working-copy changes" do
    fixture("board :half\n") do |repo, path|
      File.write(path, invalid)

      _output, _error, status = Open3.capture3(RbConfig.ruby, hook, chdir: repo)

      expect(status).to be_success
    end
  end

  it "blocks the commit for errors in staged source" do
    fixture(invalid) do |repo, path|
      File.write(path, "board :half\n")

      output, _error, status = Open3.capture3(RbConfig.ruby, hook, chdir: repo)

      expect(status.exitstatus).to eq(1)
      expect(output).to include("Layout/HoleConflict")
    end
  end

  it "checks staged declarative YAML with spaces in its name" do
    fixture("board: half\n", filename: "sensor circuit.bk.yml") do |repo, path|
      File.write(path, "board: missing\n")

      _output, _error, status = Open3.capture3(RbConfig.ruby, hook, chdir: repo)

      expect(status).to be_success
    end
  end

  it "blocks invalid staged declarative TOML despite valid working-copy changes" do
    fixture("board = 'missing'\n", filename: "sensor.bk.toml") do |repo, path|
      File.write(path, "board = 'half'\n")

      output, _error, status = Open3.capture3(RbConfig.ruby, hook, chdir: repo)

      expect(status.exitstatus).to eq(1)
      expect(output).to include("Layout/UnknownBoard")
    end
  end

  it "checks staged .bk.yaml files" do
    fixture("board: missing\n", filename: "sensor.bk.yaml") do |repo, path|
      File.write(path, "board: half\n")

      output, _error, status = Open3.capture3(RbConfig.ruby, hook, chdir: repo)

      expect(status.exitstatus).to eq(1)
      expect(output).to include("Layout/UnknownBoard")
    end
  end
end
