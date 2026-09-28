# breadkit-lint reference

Start with the [README](../README.md) for installation and a first lint run.
For individual checks, use the [rule reference](https://breadkit.github.io/breadkit-lint/rules/).

## Inputs and results

`bklint [options] [FILES...]` accepts Ruby DSL (`.bk.rb`), declarative YAML
and TOML (`.bk.yml`, `.bk.yaml`, `.bk.toml`), and Breadkit JSON IR. It scans
directories recursively. With no file argument, it scans the current directory.
Named multi-board circuits and IR v2 are supported; board holes use qualified
IDs such as `B1.a10`.

The nearest `.bklint.yml` configures each file unless `--config` is given.
Exit status is `0` when no finding reaches the failure level, `1` for
findings, and `2` for invalid input or configuration. Ruby DSL circuits and
configuration `require` entries execute code; inspect only trusted files.
JSON IR is data-only.

## Rules and configuration

Run `bklint --list-rules` to discover IDs and
`bklint --explain Electrical/ShortCircuit` for a rule's guidance. The
[default configuration](../config/default.yml) lists every rule and setting.

Create `.bklint.yml` beside a circuit to override only what you need:

```yaml
Electrical/FloatingPin:
  Severity: error
  Include: ['circuits/**/*.bk.rb']
  Exclude: ['circuits/legacy/**/*.bk.rb']

Style/WireColor:
  Enabled: true
```

`Include` and `Exclude` match paths relative to the config file; `Exclude`
wins. `AllRules.Exclude` skips entire files. Use `inherit_from` for shared
settings and `use_parts` for custom definitions. Unknown rule IDs are errors.
A circuit can use `lint_disable` with an optional target and reason;
`AllRules.RequireDisableReason` makes reasons mandatory.

Connection expectations may name a switch state. `expect_voltage` and
`expect_current` check supported DC ranges; unknown operating points produce
`Intent/MeasurementUnavailable`. See the
[core DSL reference](https://github.com/breadkit/breadkit/blob/main/docs/dsl.md)
for declaration syntax.
LED current, GPIO current, and supply-load estimates use nominal component
values. Supply ranges and resistor tolerances are not propagated through those
DC current estimates.

To adopt lint with existing findings:

```sh
bklint --generate-baseline .bklint-baseline.json
bklint --baseline .bklint-baseline.json
bklint --diff origin/main --format github
```

Baseline entries omit line numbers, so moving known findings does not make
them new. The [lint JSON schema](https://breadkit.github.io/breadkit-lint/schemas/lint-v1.json)
describes machine-readable output.

## CLI options

| Option | Use |
| --- | --- |
| `--format FORMAT` | `text`, `json`, `github`, `sarif`, `markdown`, `junit`, `checkstyle`, or `rdjson`. |
| `--out PATH` | Write the report to a file. |
| `--only RULES`, `--except RULES` | Select rule IDs. |
| `--fail-level LEVEL` | Fail on `error`, `warning` (default), or `info`. |
| `--switch-states MODE` | Check `none`, `single` (default), or `all` switch states. |
| `--state-budget COUNT` | Limit exhaustive states (default 256); report incomplete analysis when exceeded. |
| `--fix-check`, `--fix` | Preview or apply unambiguous Ruby DSL edits. |
| `--watch` | Rerun when circuit, part, or config files change. |
| `--stdin PATH` | Read a Ruby, YAML, or TOML circuit from standard input. |
| `--teach`, `--locale LOCALE` | Show short explanations or select `en`, `ja`, `zh`, or `ko` messages. |

Use `bklint --help` for all flags. Fixing currently covers one-character
wire-color typos and standalone unused suppressions; ambiguous edits and
declarative/JSON files are left unchanged. Fix modes cannot be combined with
stdin, diff, baseline, or `--out`.

## GitHub Action

The repository root is a composite Action. It installs this source and a
pinned compatible Breadkit core revision. This push workflow uploads SARIF:

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

Pin the Action to a commit SHA for reproducible runs. `upload-sarif` defaults
to `true`; the report is uploaded even when findings fail the job. For
untrusted pull requests, run on `pull_request` with `contents: read`, no
secrets, and `upload-sarif: "false"` to emit check annotations. Do not run
proposed Ruby DSL files with a write token or `pull_request_target`.
The Action does not post PR comments.

## Local integrations

A Rakefile can lint selected files:

```ruby
require "breadkit/lint/rake_task"

Breadkit::RakeTask.new(:circuits) do |task|
  task.files = FileList["circuits/**/*.bk.rb"]
  task.options = ["--format", "github"]
end
```

The [pre-commit hook](../scripts/pre-commit) reads staged circuit files from
Git's index. An optional Guard plugin is available as
`require "guard/breadkit"`; configure watched circuits in your Guardfile.
Use `bklint --format json` with `bkrender --annotations` to draw findings
on a diagram.
