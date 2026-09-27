# Changelog

## Unreleased

- Recognize shared supply domains and offboard voltage sources in electrical checks, and honor explicitly isolated supplies.
- Reduce polarity false positives for intentionally reverse-biased parts and improve LED path detection.
- Report invalid values, colors, routes, and part options as layout errors.
- Show source lines and relative paths in text, JSON, GitHub, and SARIF output.
- Report unused lint suppressions and check all pins in strict expectations.
- Add Japanese rule explanations and publish the lint JSON schema.
- Limit DSL evaluation with `--timeout`.
- Detect signal voltage limit violations and duplicate I2C addresses on one bus when part metadata is available.

## 0.1.0 — 2026-09-27

- Initial release
