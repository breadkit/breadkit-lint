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

`bklint` checks [Breadkit](https://github.com/breadkit/breadkit) circuits for
placement, electrical, and connection-intent errors. It accepts Ruby DSL,
YAML, TOML, and JSON IR.

## Quick start

```sh
gem install breadkit-lint
bklint circuit.bk.rb
bklint circuit.bk.rb --format sarif --out lint.sarif
```

This README follows main (0.2.0), which requires Breadkit core 0.2.x. If the
published gems are older, run both main branches from sibling checkouts:

```sh
git clone https://github.com/breadkit/breadkit.git
git clone https://github.com/breadkit/breadkit-lint.git
cd breadkit-lint
bundle install
bundle exec bklint ../breadkit/examples/01_led_button.bk.rb
```

## What it checks

| Area | Example |
| --- | --- |
| [Layout](docs/rules/Layout/HoleConflict.md) | Conflicting or invalid placements. |
| [Electrical](docs/rules/Electrical/ShortCircuit.md) | Shorts, polarity, ratings, and missing protection. |
| [Intent](docs/rules/Intent/ConnectionMismatch.md) | Connections that differ from declared expectations. |
| [Style](docs/rules/Style/WireColor.md) | Wire colors that conflict with their net role. |

Run `bklint --list-rules` to discover rules or `bklint --explain RULE` for
specific guidance. The [rule reference](https://breadkit.github.io/breadkit-lint/rules/)
contains the full list.

## Documentation

- [Configuration, CLI options, and integrations](docs/REFERENCE.md)
- [Default configuration](config/default.yml) and [lint JSON schema](https://breadkit.github.io/breadkit-lint/schemas/lint-v1.json)
- [Core circuit DSL](https://github.com/breadkit/breadkit/blob/main/docs/dsl.md) for named boards and connection expectations

Ruby DSL files and configuration `require` entries can execute code. Inspect
only trusted files; use JSON IR for data-only input.

## Development

From the sibling checkout above, run `bundle exec rake` for the local checks.

## License

[MIT](LICENSE.txt).
