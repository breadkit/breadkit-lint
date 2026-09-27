# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Layout/WireOverIC" do
  def check(source)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nic :U1, :ne555, at: 'e10'\n#{source}")
      Breadkit::Lint::Engine.new.run([path], only: ["Layout/WireOverIC"]).first[:offenses]
    end
  end

  it "flags a straight electrical jumper crossing the DIP body" do
    found = check("wire 'a11', 'j11'\n")
    expect(found.map(&:rule)).to eq(["Layout/WireOverIC"])
    expect(found.first.targets).to include(components: ["U1"], wires: ["W1"])
  end

  it "ignores routes that do not cross the body and non-electrical alternatives" do
    expect(check("wire 'a9', 'j9'\n")).to be_empty
    expect(check("wire 'a11', 'd11'\n")).to be_empty
    expect(check("wire 'a11', 'j11', route: :edge\n")).to be_empty
    expect(check("wire 'a11', 'j11', electrical: false\n")).to be_empty
  end

  it "does not infer a body from incomplete DIP pins" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nic :U1, :ne555, pins: %w[e10 e11]\nwire 'a11', 'j11'\n")
      found = Breadkit::Lint::Engine.new.run([path], only: ["Layout/WireOverIC"]).first[:offenses]
      expect(found).to be_empty
    end
  end

  it "does not infer a body from misaligned DIP rows" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, "board :half\nic :U1, :ne555, pins: %w[e10 e11 e12 e13 f14 f13 f12 f11]\nwire 'a11', 'j11'\n")
      found = Breadkit::Lint::Engine.new.run([path], only: ["Layout/WireOverIC"]).first[:offenses]
      expect(found).to be_empty
    end
  end
end
