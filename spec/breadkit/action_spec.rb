# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe "GitHub Action" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:metadata) { YAML.safe_load(File.read(File.join(root, "action.yml"))) }

  it "runs lint and uploads SARIF through a composite action" do
    expect(metadata.dig("runs", "using")).to eq("composite")
    expect(metadata.fetch("inputs").keys).to include("path", "upload-sarif", "fail-level")
    steps = metadata.dig("runs", "steps")
    expect(steps.any? { |step| step["uses"].to_s.start_with?("ruby/setup-ruby@") }).to be(true)
    upload_index = steps.index { |step| step["uses"].to_s.start_with?("github/codeql-action/upload-sarif@") }
    failure_index = steps.index { |step| step["name"] == "Fail on findings" }
    expect(upload_index).not_to be_nil
    expect(failure_index).to be > upload_index
    expect(steps.any? { |step| step["run"].to_s.include?("action-run.sh") }).to be(true)
    expect(steps.filter_map { |step| step["run"] }.join).not_to include("${{ inputs.path }}")
  end

  it "preserves a lint finding for the final step while producing a SARIF report" do
    Dir.mktmpdir do |directory|
      bin = File.join(directory, "bin")
      Dir.mkdir(bin)
      File.write(File.join(bin, "bundle"), <<~SH)
        #!/usr/bin/env bash
        if [[ "$1" == "install" ]]; then exit 0; fi
        if [[ "$1" == "exec" && "$2" == "ruby" && "$3" == */exe/bklint ]]; then
          while [[ "$#" -gt 0 ]]; do
            if [[ "$1" == "--out" ]]; then printf '{"runs":[]}' > "$2"; break; fi
            shift
          done
          if [[ "$#" -eq 0 ]]; then printf '::warning file=example.bk.rb,line=1::example finding\n'; fi
          exit 1
        fi
        exit 2
      SH
      File.chmod(0o755, File.join(bin, "bundle"))
      output = File.join(directory, "output")
      env = { "PATH" => "#{bin}:#{ENV.fetch('PATH')}", "GITHUB_ACTION_PATH" => root,
              "GITHUB_WORKSPACE" => directory, "RUNNER_TEMP" => directory, "GITHUB_OUTPUT" => output,
              "BREADKIT_ACTION_CORE_DIR" => File.expand_path("../breadkit", root),
              "INPUT_PATH" => "example.bk.rb", "INPUT_UPLOAD_SARIF" => "true", "INPUT_FAIL_LEVEL" => "warning" }
      _stdout, stderr, status = Open3.capture3(env, "bash", File.join(root, "scripts/action-run.sh"))
      expect(status.success?).to be(true), stderr
      expect(File.read(output)).to include("exit-code=1")
      report = File.read(output)[/^sarif-file=(.+)$/, 1]
      expect(JSON.parse(File.read(File.join(directory, report)))).to eq("runs" => [])

      env["INPUT_UPLOAD_SARIF"] = "false"
      env["GITHUB_OUTPUT"] = File.join(directory, "annotations-output")
      stdout, stderr, status = Open3.capture3(env, "bash", File.join(root, "scripts/action-run.sh"))
      expect(status.success?).to be(true), stderr
      expect(stdout).to include("::warning file=example.bk.rb,line=1::example finding")
      expect(File.read(env.fetch("GITHUB_OUTPUT"))).to eq("exit-code=1\n")
    end
  end
end
