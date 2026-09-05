# Changelog

All notable changes to `marianoguerra/shrubbery-cli` are recorded here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this module follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-09-05

First release.

### Added

- `shrubbery check` — parse and report any problem with the source shown, with
  `--error-format human|short|json` and `--color always|never|auto`.
- `shrubbery fmt` — re-format, ignoring how the source was written, with
  `--style flat|pretty|armoured|multiline`, `--width N` and `--write`.
- `shrubbery tokens`, `parse`, `source`, `print` and `doc` — the other half of
  the differential harness. Their output formats are shared with the Racket
  oracle rather than chosen for looks, so changing one changes what the suite
  compares.
