# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe "parallel circuit lint" do
  it "preserves report order and isolates failures across workers" do
    Dir.mktmpdir do |directory|
      files = %w[first second third].map { |name| File.join(directory, "#{name}.bk.rb") }
      File.write(files[0], "board :half\nled :D1, anode: 'a10', cathode: 'a11'\n")
      File.write(files[1], "board :missing_board\n")
      File.write(files[2], "board :half\nregistor :R1, '100', pins: %w[a10 a11]\n")
      command = [RbConfig.ruby, "-I#{File.expand_path('../../lib', __dir__)}", File.expand_path("../../exe/bklint", __dir__),
                 "--format", "json"]

      serial, _errors, serial_status = Open3.capture3(*command, "--jobs", "1", *files)
      parallel, _errors, parallel_status = Open3.capture3(*command, "--jobs", "2", *files)
      expect(serial_status.exitstatus).to eq(2)
      expect(parallel_status.exitstatus).to eq(2)
      expect(JSON.parse(parallel)).to eq(JSON.parse(serial))
      expect(JSON.parse(parallel).fetch("files").map { |file| File.basename(file.fetch("path")) }).to eq(files.map { |path| File.basename(path) })
    end
  end

  it "rejects a nonpositive worker count" do
    _output, errors, status = Open3.capture3(RbConfig.ruby, "-I#{File.expand_path('../../lib', __dir__)}",
                                              File.expand_path("../../exe/bklint", __dir__), "--jobs", "0")
    expect(status.exitstatus).to eq(2)
    expect(errors).to include("jobs must be positive")
  end

  it "rejects a worker count above the bounded pool size" do
    _output, errors, status = Open3.capture3(RbConfig.ruby, "-I#{File.expand_path('../../lib', __dir__)}",
                                              File.expand_path("../../exe/bklint", __dir__), "--jobs", "33")
    expect(status.exitstatus).to eq(2)
    expect(errors).to include("jobs must be at most 32")
  end
end
