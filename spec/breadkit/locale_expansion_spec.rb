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
end
