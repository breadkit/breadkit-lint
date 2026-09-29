# Changelog

## Unreleased

### Analysis and diagnostics

- Check supported current, power, and voltage ratings across supply ranges and resistor tolerances; report incomplete bounds when the DC model cannot certify them.
- Recognize model-specific rated LEDs and localize the new electrical diagnostics.
- Support line-scoped suppression comments and safe fixes for unambiguous missing labels and occupied wire endpoints.

### Workflow

- Add bounded `--jobs` parallel inspection with deterministic report order.
- Extend the GitHub Action to generate an annotated PNG and provide a permission-separated pull request comment example.

## 0.2.0 — 2026-09-28

### Electrical and layout checks

- Lint declarative YAML and TOML circuits, named multi-board circuits, and version 2 circuit IR.
- Check I2C pull-ups and address conflicts, supply overloads, voltage domains, GPIO current limits, missing input pull resistors, missing IC decoupling capacitors, direct transistor base drive, and missing flyback diodes when the circuit supplies enough metadata.
- Check resistor power, capacitor voltage, LED current, zero-ohm potentiometer paths, component lead spans, covered holes, overlapping bodies, and wires crossing DIP bodies.
- Evaluate connection expectations in named switch states and check declared voltage and current ranges. An explicit switch-state budget reports incomplete exhaustive analysis instead of silently skipping states.
- Avoid false common-ground and reverse-polarity findings for shared or isolated supplies and intentionally reverse-biased parts.
- Recognize offboard power outputs and GPIO pin roles from part definitions when checking shorts, current paths, and voltage limits.

### Reports and integrations

- Add Markdown, JUnit, Checkstyle, and reviewdog JSON reports; portable baselines; `--diff`; `--watch`; `--stdin`; and short explanations with `--teach`.
- Publish the lint JSON schema and rule reference, including English, Japanese, Chinese, and Korean messages and guidance.
- Provide a GitHub Action, Rake task, Guard plugin, and pre-commit hook. The hook checks staged Ruby DSL, YAML, and TOML circuits.

### Diagnostics and fixes

- Show accurate source columns and add safe `--fix` edits for unambiguous wire-color typos and unused standalone suppressions.
- Preserve useful source paths and locations in terminal, GitHub, JSON, and SARIF reports, including evaluation errors.
- Report invalid circuit values, colors, routes, and part options as layout errors before electrical checks run.
- Reduce redundant findings from switch states, unused suppressions, unplaced pins, and missing pull resistors.

### Compatibility

- Require Breadkit core 0.2.x. Projects using core 0.1.x should remain on breadkit-lint 0.1.0 until they upgrade both gems.

## 0.1.0 — 2026-09-26

- Initial release.
