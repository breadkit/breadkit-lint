<p align="center">
  <img src="site/favicon.svg" width="72" height="72" alt="">
</p>

<h1 align="center">breadkit-lint</h1>

<p align="center">
  <strong>Catch breadboard wiring mistakes before you build.</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/breadkit-lint"><img src="https://img.shields.io/gem/v/breadkit-lint.svg" alt="RubyGems version"></a>
  <a href="https://github.com/breadkit/breadkit-lint/actions/workflows/ci.yml"><img src="https://github.com/breadkit/breadkit-lint/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <img src="https://img.shields.io/badge/Ruby-%3E%3D%203.3-CC342D.svg" alt="Ruby 3.3 or newer">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#what-it-checks">Rules</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#command-reference">CLI reference</a> ·
  <a href="https://breadkit.github.io/breadkit-lint/">Website</a>
</p>

---

`bklint` checks [Breadkit](https://github.com/breadkit/breadkit) circuits for
placement errors, electrical problems, and connections that differ from your
intent. It accepts Ruby DSL, declarative YAML/TOML, or resolved JSON IR and can report results to
a terminal, CI log, or SARIF viewer.

Named multi-board circuits are supported in Ruby DSL, declarative YAML/TOML, and IR schema version 2.
See the [multi-board guide](docs/MULTI_BOARD.md).

## Quick start

RubyGems currently provides breadkit-lint 0.1.0 and Breadkit core 0.1.0. To
use those published versions with Ruby 3.3 or newer:

```sh
gem install breadkit-lint
bklint circuit.bk.rb
```

The features documented below track this main branch. It requires Breadkit
core 0.2.x, which is not yet on RubyGems; `gem install breadkit-lint` does not
install these main-branch features. Check out both repositories as siblings:

```sh
git clone https://github.com/breadkit/breadkit.git
git clone https://github.com/breadkit/breadkit-lint.git
cd breadkit-lint
bundle install
bundle exec bklint ../breadkit/examples/01_led_button.bk.rb
```

From the source checkout, focus on one rule or write a machine-readable report:

```sh
bundle exec bklint circuit.bk.rb --only Electrical/ShortCircuit
bundle exec bklint circuit.bk.rb --format json --out lint.json
bundle exec bklint circuit.bk.rb --format sarif --out lint.sarif
bundle exec bklint circuit.bk.rb --format markdown --out lint.md
bundle exec bklint circuit.bk.rb --format rdjson --out lint.rdjson
bundle exec bklint circuit.bk.rb --teach
bundle exec bklint circuit.bk.rb --fix-check
bundle exec bklint circuit.bk.rb --fix
cat circuit.bk.rb | bundle exec bklint --stdin circuit.bk.rb
```

JSON and SARIF findings include a short fix suggestion and link to the
[published rule reference](https://breadkit.github.io/breadkit-lint/rules/).

Try the [shared circuit examples](https://github.com/breadkit/breadkit/tree/main/examples)
or browse the [project site](https://breadkit.github.io/breadkit-lint/).

## What it checks

| Area | Example |
| --- | --- |
| [Layout](docs/rules/Layout/HoleConflict.md) | Two parts occupy the same hole, or a pin is left off the board. |
| [Electrical](docs/rules/Electrical/ShortCircuit.md) | A short circuit, floating pin, reversed polarity, or missing ground. |
| [Intent](docs/rules/Intent/ConnectionMismatch.md) | The resolved circuit does not match an expected connection. |
| [Style](docs/rules/Style/WireColor.md) | Wire colors do not match their power or ground role. |

Run `bklint --list-rules` to see every rule and
`bklint --explain Electrical/ShortCircuit` for guidance. The complete
[rule reference](https://breadkit.github.io/breadkit-lint/rules/) includes examples.

## Configuration

Create `.bklint.yml` next to the circuit:

```yaml
Electrical/FloatingPin:
  Severity: error
  Include: ['circuits/**/*.bk.rb']
  Exclude: ['circuits/legacy/**/*.bk.rb']

Style/WireColor:
  Enabled: true
  PositiveColors: [red, orange]
  GroundColors: [black, blue]
```

The [default configuration](config/default.yml) lists built-in rules and their
settings. Use `inherit_from` to share settings and `use_parts` to load custom
part definitions. Rule `Include` and `Exclude` patterns match paths relative to
the configuration file; `Exclude` wins when both match. `AllRules.Exclude`
skips an entire file. You can also set the failure level, switch states, and
custom rule files. Use `lint_disable` in a circuit to suppress
a rule for a specific part, pin, or wire. Unknown rule IDs are errors; set
`AllRules.RequireDisableReason` to require a `reason:` on suppressions.
`AllRules.NewRules` controls whether new rules start enabled or pending. Pair
`bklint --format json` with `bkrender --annotations` to show offenses on a
diagram.
Use `expect(when: "SW1") { connected "SW1.1", "SW1.3" }` in a circuit to
check a connection when that switch is closed.
Named expectations evaluate only their named switch combination; they do not
consume the exhaustive state budget.
Use `expect_voltage "VCC", 3.0..3.6` and `expect_current "R1", 0.001..0.02`
to check calculated DC ranges. Current uses amperes and is compared by
magnitude. Add a ground label for absolute voltage checks; unsupported DC
models report `Intent/MeasurementUnavailable`.
Set `current_limit: 0.02` on a `supply` to check a 20 mA supply against
modeled DC loads with `Electrical/SupplyOverload`.

To adopt lint in a project with existing findings, generate a baseline once.
The saved entries omit line numbers, so moving code does not bring known
findings back. New findings still affect the exit status.

```sh
bklint --generate-baseline .bklint-baseline.json
bklint --baseline .bklint-baseline.json
bklint --diff origin/main --format github
```

The [lint JSON schema](https://breadkit.github.io/breadkit-lint/schemas/lint-v1.json)
describes the report format for integrations.

## GitHub Action

The repository root is a composite Action. It installs the current lint source
and a pinned Breadkit core source checkout, so it works while the required
Breadkit 0.2 gem is unpublished. The pinned core revision lives in
`scripts/action-run.sh`; update it alongside compatibility checks. Pass one
circuit file or a directory of circuits. A push workflow can upload SARIF to
GitHub code scanning:

```yaml
name: Circuit lint
on: push
permissions:
  contents: read
  security-events: write
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: breadkit/breadkit-lint@main
        with:
          path: circuits
```

`upload-sarif` defaults to `true`. The Action uploads the report even when a
lint finding fails the job. Set `fail-level` to `error`, `warning` (default), or
`info`. Pin the Action to a commit SHA when you need a reproducible workflow.

For pull request annotations, use a separate read-only workflow. Set
`upload-sarif: "false"` to emit GitHub Check annotations without a write token:

```yaml
name: Circuit PR lint
on: pull_request
permissions:
  contents: read
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: breadkit/breadkit-lint@main
        with:
          path: circuits
          upload-sarif: "false"
```

Ruby DSL circuits and `.bklint.yml` `require` entries can execute code. Keep
the PR workflow on `pull_request` with read-only permissions and no secrets;
do not use `pull_request_target` to run proposed circuit files. The Action
does not post PR comments.

In a Rakefile, define a lint task with selected files and CLI options:

```ruby
require "breadkit/lint/rake_task"

Breadkit::RakeTask.new(:circuits) do |task|
  task.files = FileList["circuits/**/*.bk.rb"]
  task.options = ["--format", "github"]
end
```

For a local pre-commit check, copy [scripts/pre-commit](scripts/pre-commit) to
your project's `.git/hooks/pre-commit` and make it executable. It lints the
staged contents of changed `.bk.rb` files and blocks a commit when bklint
fails. Declarative YAML and TOML files are not included because `--stdin`
currently accepts Ruby DSL only.

If your project already uses Guard, add the `guard` gem and this optional
plugin to its `Guardfile`:

```ruby
require "guard/breadkit"

guard :breadkit, files: ["circuits"] do
  watch(%r{^circuits/.*\.bk\.(?:rb|ya?ml|toml|json)$})
  watch(%r{^parts/.*\.ya?ml$})
  watch(".bklint.yml")
end
```

Changed circuits are linted directly. Changes to part definitions or the lint
configuration rerun all paths listed in `files`. Set `args: ["--format", "github"]`
to pass additional bklint options.

## Command reference

`bklint [options] [FILES...]` accepts `.bk.rb`, `.bk.yml`, `.bk.yaml`, `.bk.toml`, and Breadkit IR `.json` files.
Directories are scanned recursively. With no files, it scans visible inputs in
the current directory and skips `node_modules`. Each file uses the nearest
`.bklint.yml` unless you pass `--config`.

| Option | Description |
| --- | --- |
| `-f, --format FORMAT` | `text` (default), `json`, `github`, `sarif`, `markdown`, `junit`, `checkstyle`, or `rdjson`. |
| `-o, --out PATH` | Write output to a file. |
| `-c, --config PATH` | Load a specific configuration. |
| `--stdin PATH` | Lint Ruby DSL from standard input using PATH for diagnostics and relative part files. |
| `--generate-baseline PATH` | Save current nonfatal findings and exit successfully. |
| `--baseline PATH` | Hide findings listed in a generated baseline. |
| `--diff REF` | Report findings added since a local Git revision, using its archived circuit and part files. |
| `--watch` | Rerun lint when circuit, part, or configuration files change; press Ctrl-C to stop. |
| `--fix-check` / `--fix-dry-run` | Preview safe Ruby DSL source edits without writing; exit `1` when an edit is available. |
| `--fix` | Apply safe Ruby DSL source edits, then lint the updated files. |
| `--teach` | Add short rule explanations to text output. |
| `--fail-level LEVEL` | `error`, `warning` (default), or `info`. |
| `--only RULES` / `--except RULES` | Select or skip comma-separated rule IDs. |
| `--switch-states MODE` | Evaluate `none`, `single` (default), or `all` switch states. |
| `--state-budget COUNT` | Limit exhaustive switch combinations (default: 256); report an error instead of silently skipping states when the limit is exceeded. Also available as `AllRules.StateBudget` in `.bklint.yml`. |
| `--timeout SECONDS` | Limit DSL evaluation time per circuit (default: 10). |
| `--list-rules` / `--explain RULE` | Discover rules and read guidance. |
| `--locale LOCALE` | Select `en`, `ja`, `zh`, or `ko` messages and rule descriptions. |

Exit status is `0` when no offense reaches the failure level, `1` when one
does, and `2` for invalid input, configuration, or command usage. Use
`--format github` for GitHub Actions annotations.

Source fixing currently handles a uniquely identifiable one-character typo in
a named wire color and an unused `lint_disable` that occupies its whole line.
Ambiguous colors, comments on suppression lines, malformed Ruby, and
declarative/JSON inputs are left unchanged. Fix modes cannot be combined with
stdin, diff, baseline, or `--out`. Ruby DSL reports include source columns when
the location can be identified unambiguously.

## Input safety

Breadkit DSL files execute Ruby code, and configuration `require` entries
execute Ruby files. Inspect only trusted files. Use JSON IR for data-only input.

## Development

The specs use examples from a sibling Breadkit checkout:

```sh
git clone https://github.com/breadkit/breadkit.git
git clone https://github.com/breadkit/breadkit-lint.git
cd breadkit-lint
bundle install
bundle exec rake
```

## License

breadkit-lint is available under the [MIT License](LICENSE.txt).
