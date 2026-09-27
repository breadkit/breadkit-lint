# frozen_string_literal: true

require "tmpdir"

RSpec.describe Breadkit::Lint::CLI do
  it "reruns lint when a watched circuit changes" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "circuit.bk.rb")
      output = File.join(directory, "report.txt")
      File.write(input, "board :mini\n")
      cli = described_class.new
      ticks = 0
      allow(cli).to receive(:sleep) do
        ticks += 1
        if ticks == 1
          File.write(input, "board :mini\npart :R1, :missing, at: 'a1'\n")
        else
          raise Interrupt
        end
      end

      expect(cli.run([input, "--watch", "-o", output])).to eq(0)
      expect(ticks).to eq(2)
      expect(File.read(output)).to include("UnknownPart")
    end
  end

  it "rejects watch with standard input or source fixes" do
    cli = described_class.new
    expect { expect(cli.run(["--watch", "--stdin", "virtual.bk.rb"])).to eq(2) }
      .to output(/--watch cannot be combined/).to_stderr
    expect { expect(cli.run(["--watch", "--fix"])).to eq(2) }
      .to output(/--watch cannot be combined/).to_stderr
  end
end
