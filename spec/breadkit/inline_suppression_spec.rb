# frozen_string_literal: true

require "tmpdir"

RSpec.describe "inline rule suppression" do
  def inspect_source(source, config: Breadkit::Lint::Config.new)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "circuit.bk.rb")
      File.write(path, source)
      Breadkit::Lint::Engine.new(config: config).run([path]).first[:offenses]
    end
  end

  let(:circuit) { "board :half\nled :D1, anode: 'a10', cathode: 'a11'\n" }

  it "suppresses the named rule on the current or following line only" do
    same_line = circuit.sub("'a11'", "'a11' # bklint:disable Electrical/FloatingPin -- deliberately open")
    next_line = circuit.sub("led :D1", "# bklint:disable-next-line Electrical/FloatingPin -- deliberately open\nled :D1")
    expect(inspect_source(circuit).map(&:rule)).to include("Electrical/FloatingPin")
    expect(inspect_source(same_line).map(&:rule)).not_to include("Electrical/FloatingPin", "Lint/RedundantDisable")
    expect(inspect_source(next_line).map(&:rule)).not_to include("Electrical/FloatingPin", "Lint/RedundantDisable")
    expect(inspect_source("# bklint:disable Electrical/FloatingPin\n#{circuit}").map(&:rule)).to include("Electrical/FloatingPin")
  end

  it "treats only Ruby comments as directives and reports invalid or unused directives" do
    quoted = circuit + "note = '# bklint:disable Electrical/FloatingPin'\n"
    expect(inspect_source(quoted).map(&:rule)).to include("Electrical/FloatingPin")
    unknown = circuit + "# bklint:disable Missing/Rule\n"
    expect(inspect_source(unknown).map(&:rule)).to include("Lint/UnknownRuleInDisable")
    unused = circuit + "# bklint:disable-next-line Electrical/FloatingPin\nputs :ok\n"
    expect(inspect_source(unused).map(&:rule)).to include("Lint/RedundantDisable")
  end

  it "does not suppress a finding from an included file at the same line" do
    Dir.mktmpdir do |directory|
      main = File.join(directory, "main.bk.rb")
      child = File.join(directory, "child.bk.rb")
      File.write(main, "board :half\ninclude 'child.bk.rb'\n# bklint:disable Electrical/FloatingPin\n")
      File.write(child, "# child\n# line two\nled :D1, anode: 'a10', cathode: 'a11'\n")

      findings = Breadkit::Lint::Engine.new.run([main]).first[:offenses]
      expect(findings.map(&:rule)).to include("Electrical/FloatingPin", "Lint/RedundantDisable")
    end
  end
end
