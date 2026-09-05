# Changelog

All notable changes to `marianoguerra/error-report` are recorded here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this module follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-09-05

First release.

### Added

- The data model: `Report`, `Label`, `Severity`, `LabelStyle`, `Fix`, and the
  `Span` / `SourceId` pair that ties a label to a place. A report is a value;
  nothing about how it looks is decided when it is built.
- `Source` and `Sources`: a name, its text, and the line index used to turn an
  offset into a line and a column. Offsets are UTF-16 code units — MoonBit's
  native string index — with `Source::span_of_chars` for producers that count
  code points instead.
- Four renderers: `rich` (source snippets, box drawing, multi-line brackets),
  `short` (one line per label, the `file:line:col: message` form editors
  parse), `json` (the whole report as data), and the width-aware machinery
  they share.
- `Config`, with a charset (Unicode or ASCII), a theme, a colour mode, a tab
  width, a context-line count and a width. `render` takes `is_tty` as a
  parameter rather than looking for a file descriptor, so the module can stay
  free of dependencies.
