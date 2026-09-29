# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Chinese and Korean locales" do
  let(:locale_dir) { File.expand_path("../../locales", __dir__) }

  it "covers every existing rule, guidance, and message key with matching placeholders" do
    reference = YAML.safe_load(File.read(File.join(locale_dir, "ja.yml"), encoding: "UTF-8"))
    %w[zh ko].each do |locale|
      translated = YAML.safe_load(File.read(File.join(locale_dir, "#{locale}.yml"), encoding: "UTF-8"))
      %w[rules guidance messages].each do |section|
        expect(translated.fetch(section).keys).to match_array(reference.fetch(section).keys)
      end
      reference.fetch("messages").each do |key, template|
        expect(translated.dig("messages", key).scan(/%\{[^}]+\}/).sort).to eq(template.scan(/%\{[^}]+\}/).sort)
      end
    end
  end

  it "selects Chinese and Korean from the CLI or environment" do
    cli = Breadkit::Lint::CLI.new
    old = ENV.to_h.slice("LC_ALL", "LC_MESSAGES", "LANG")
    ENV["LC_ALL"], ENV["LC_MESSAGES"], ENV["LANG"] = "zh_CN.UTF-8", nil, nil
    expect(cli.send(:locale_from_environment)).to eq("zh")
    ENV["LC_ALL"] = "ko_KR.UTF-8"
    expect(cli.send(:locale_from_environment)).to eq("ko")

    expect { expect(cli.run(["--explain", "Layout/HoleConflict", "--locale", "zh"])).to eq(0) }
      .to output(/同一个孔/).to_stdout
    expect { expect(cli.run(["--explain", "Layout/HoleConflict", "--locale", "ko"])).to eq(0) }
      .to output(/같은 구멍/).to_stdout
  ensure
    %w[LC_ALL LC_MESSAGES LANG].each { |key| old.key?(key) ? ENV[key] = old[key] : ENV.delete(key) } if old
  end

  it "localizes rule messages and text report labels" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "invalid.bk.rb")
      File.write(path, "board :half\nwire 'a999', 'a1'\n")
      expect(Breadkit::Lint::Engine.new(locale: "zh").run([path], only: ["Layout/InvalidHole"]).first[:offenses].first.message)
        .to include("无效的孔位")
      expect(Breadkit::Lint::Engine.new(locale: "ko").run([path], only: ["Layout/InvalidHole"]).first[:offenses].first.message)
        .to include("잘못된 구멍")
    end

    item = Breadkit::Lint::Offense.new(rule: "Electrical/ShortedComponent", severity: "warning",
                                      message: "example", targets: {}, state: "SW1")
    files = [{ path: "circuit.bk.rb", offenses: [item], skipped: true }]
    expect(Breadkit::Lint::Formatter.new.text(files, locale: "zh")).to include("检查了 1 个文件", "跳过电气与意图检查", "SW1 状态")
    expect(Breadkit::Lint::Formatter.new.text(files, locale: "ko")).to include("파일 1개 검사", "전기 및 의도 검사 생략", "SW1 상태")
  end

  it "localizes rated current and incomplete-bound findings" do
    source = <<~RUBY
      board :half
      supply :P, voltage: 4.8..5.5, plus: 'B+1', minus: 'B-1'
      resistor :R1, '100 5%', pins: %w[a10 a11]
      part :D1, :kingbright_wp7113id, pins: {anode: 'a12', cathode: 'a13'}
      wire 'b10', 'B+2'
      wire 'b11', 'b12'
      wire 'b13', 'B-2'
    RUBY
    Dir.mktmpdir do |directory|
      path = File.join(directory, "rated.bk.rb")
      File.write(path, source)
      { "ja" => /[ぁ-んァ-ン一-龯]/, "zh" => /[一-龯]/, "ko" => /[가-힣]/ }.each do |locale, script|
        findings = Breadkit::Lint::Engine.new(locale: locale).run([path], only: %w[Electrical/LedOvercurrent Electrical/DcBoundsIncomplete])
        expect(findings.first[:offenses].map(&:rule)).to contain_exactly("Electrical/LedOvercurrent", "Electrical/DcBoundsIncomplete")
        findings.first[:offenses].each { |offense| expect(offense.message).to match(script) }
      end
    end
  end

  it "localizes resistor and capacitor rating findings" do
    source = <<~RUBY
      board :half
      supply :P, voltage: 5, plus: 'B+1', minus: 'B-1'
      resistor :R1, '10 1/4W', pins: %w[a10 a11]
      electrolytic :C1, '10u 3V', plus: 'a20', minus: 'a21'
      wire 'b10', 'B+'
      wire 'b11', 'B-'
      wire 'b20', 'B+'
      wire 'b21', 'B-'
    RUBY
    Dir.mktmpdir do |directory|
      path = File.join(directory, "rated.bk.rb")
      File.write(path, source)
      { "ja" => /[ぁ-んァ-ン一-龯]/, "zh" => /[一-龯]/, "ko" => /[가-힣]/ }.each do |locale, script|
        findings = Breadkit::Lint::Engine.new(locale: locale).run([path], only: %w[Electrical/ResistorPowerRating Electrical/CapacitorVoltageRating])
        expect(findings.first[:offenses].map(&:rule)).to contain_exactly("Electrical/ResistorPowerRating", "Electrical/CapacitorVoltageRating")
        findings.first[:offenses].each { |offense| expect(offense.message).to match(script) }
      end
    end
  end
end
