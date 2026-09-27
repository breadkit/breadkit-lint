# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe "Ruby source fixes" do
  def run_lint(*args)
    root = File.expand_path("../..", __dir__)
    Open3.capture3(RbConfig.ruby, "-I#{File.join(root, 'lib')}", File.join(root, "exe/bklint"), *args, chdir: root)
  end

  it "previews and applies only unambiguous edits without changing surrounding syntax" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      source = <<~RUBY
        board :half
        supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
          wire 'B-2', 'B-3', color: :blu
        lint_disable 'Style/WireColor'
      RUBY
      File.write(path, source)

      _stdout, stderr, status = run_lint("--fix-check", path)
      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("would replace wire color", "would remove unused lint_disable")
      expect(File.read(path)).to eq(source)

      _stdout, stderr, status = run_lint("--fix-dry-run", path)
      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("would replace wire color")
      expect(File.read(path)).to eq(source)

      _stdout, stderr, status = run_lint("--fix", path)
      expect(status.exitstatus).to eq(0), stderr
      expect(File.read(path)).to eq(source.sub(":blu", ":blue").sub("lint_disable 'Style/WireColor'\n", ""))
    end
  end

  it "leaves ambiguous colors and commented or compound suppression lines untouched" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      source = "board :half\nwire 'B-1', 'B-2', color: :gren\nlint_disable 'Style/WireColor' # keep this explanation\n"
      File.write(path, source)
      _stdout, _stderr, status = run_lint("--fix", path)
      expect(status.exitstatus).to eq(1)
      expect(File.read(path)).to eq(source)
    end
  end

  it "keeps string quotes and unrelated bytes while fixing a wire color" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      source = "board :half\r\nwire 'B-1', 'B-2', color: 'blu'  # wire note\r\n"
      File.binwrite(path, source)
      _stdout, stderr, status = run_lint("--fix", "--only", "Layout/InvalidColor", path)
      expect(status.exitstatus).to eq(0), stderr
      expect(File.binread(path)).to eq(source.sub("'blu'", "'blue'"))
    end
  end

  it "does not rewrite malformed Ruby" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      source = "board :half\nwire('a1',\n"
      File.write(path, source)
      _stdout, _stderr, status = run_lint("--fix", path)
      expect(status.exitstatus).to eq(2)
      expect(File.read(path)).to eq(source)
    end
  end

  it "rejects an output path in fix mode before changing source" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      source = "board :half\nwire 'B-1', 'B-2', color: :blu\n"
      File.write(path, source)
      _stdout, stderr, status = run_lint("--fix", "--out", path, path)
      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("cannot be combined")
      expect(File.read(path)).to eq(source)
    end
  end

  it "includes a precise one-based column in JSON, GitHub, and SARIF reports" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      line = "  wire 'B-1', 'B-2', color: :blu"
      File.write(path, "board :half\n#{line}\n")
      expected = line.index(":blu") + 1

      json, _stderr, _status = run_lint("--format", "json", path)
      location = JSON.parse(json).dig("files", 0, "offenses", 0, "location")
      expect(location).to include("line" => 2, "column" => expected)

      github, _stderr, _status = run_lint("--format", "github", path)
      expect(github).to include("line=2,col=#{expected}")

      sarif, _stderr, _status = run_lint("--format", "sarif", path)
      region = JSON.parse(sarif).dig("runs", 0, "results", 0, "locations", 0, "physicalLocation", "region")
      expect(region).to include("startLine" => 2, "startColumn" => expected)
    end
  end
end
