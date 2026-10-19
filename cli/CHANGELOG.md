# Changelog

All notable changes to `marianoguerra/shrubbery-cli` are recorded here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this module follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] — 2026-10-19

### Changed

- **Builds clean on moonc v0.10.16** (moon 0.1.20261016). The trait methods
  each package keeps live — `Show::to_string`, `Compare::compare` and this
  project's own trait methods — are re-exported with an explicit `pub extend`;
  the derived Eq/Debug/Hash/ToJson/Default methods, `Show::output` and the
  Compare operators are deprecated and hidden, as the toolchain now expects.
  No change in behaviour.
- Takes `marianoguerra/shrubbery@0.1.2`, `marianoguerra/error-report@0.1.1`
  and `moonbitlang/x@0.5.5`.

## [0.1.1] — 2026-09-05

### Fixed

- Takes `marianoguerra/shrubbery@0.1.1`, so `check` no longer dies with a
  signal on an `@`-notation body whose `@` has nothing valid after it. `check`
  parses in recovery mode, which is the mode the crash was in.

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
