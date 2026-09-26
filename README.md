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
intent. It accepts Ruby DSL files or resolved JSON IR and can report results to
a terminal, CI log, or SARIF viewer.

## Quick start

Install the gem with Ruby 3.3 or newer. The compatible Breadkit core gem is
installed automatically.

```sh
gem install breadkit-lint
bklint circuit.bk.rb
```

Focus on one rule, or write a machine-readable report:

```sh
bklint circuit.bk.rb --only Electrical/ShortCircuit
bklint circuit.bk.rb --format json --out lint.json
bklint circuit.bk.rb --format sarif --out lint.sarif
```

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
[rule reference](docs/rules) includes examples.

## Configuration

Create `.bklint.yml` next to the circuit:

```yaml
Electrical/FloatingPin:
  Severity: error

Style/WireColor:
  Enabled: true
  PositiveColors: [red, orange]
  GroundColors: [black, blue]
```

The [default configuration](config/default.yml) lists built-in rules and their
settings. Use `inherit_from` to share settings and `use_parts` to load custom
part definitions. You can also set the failure level, switch states,
exclusions, and custom rule files. Use `lint_disable` in a circuit to suppress
a rule for a specific part, pin, or wire. Unknown rule IDs are errors; set
`AllRules.RequireDisableReason` to require a `reason:` on suppressions.
`AllRules.NewRules` controls whether new rules start enabled or pending. Pair
`bklint --format json` with `bkrender --annotations` to show offenses on a
diagram.

## Command reference

`bklint [options] [FILES...]` accepts `.bk.rb` and Breadkit IR `.json` files.
Directories are scanned recursively. With no files, it scans visible inputs in
the current directory and skips `node_modules`. Each file uses the nearest
`.bklint.yml` unless you pass `--config`.

| Option | Description |
| --- | --- |
| `-f, --format FORMAT` | `text` (default), `json`, `github`, or `sarif`. |
| `-o, --out PATH` | Write output to a file. |
| `-c, --config PATH` | Load a specific configuration. |
| `--fail-level LEVEL` | `error`, `warning` (default), or `info`. |
| `--only RULES` / `--except RULES` | Select or skip comma-separated rule IDs. |
| `--switch-states MODE` | Evaluate `none`, `single` (default), or `all` switch states. |
| `--list-rules` / `--explain RULE` | Discover rules and read guidance. |
| `--locale LOCALE` | Select `en` or `ja` messages and rule descriptions. |

Exit status is `0` when no offense reaches the failure level, `1` when one
does, and `2` for invalid input, configuration, or command usage. Use
`--format github` for GitHub Actions annotations.

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
