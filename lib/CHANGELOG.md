# Changelog

All notable changes to `marianoguerra/shrubbery` are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
module follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-09-05

First release: a port of the Racket reference implementation of Shrubbery
notation, with correctness decided by a differential harness against that
reference rather than by inspection.

### Added

- **Lexer** — every token form the notation has, both number states, all five
  comment forms, `@` notation and `#{...}` S-expression escapes. Token texts
  concatenate back to the input exactly.
- **Parser** — the grouping and blocking layer: groups, blocks, alternatives,
  `;` and `,`, the four bracket pairs, `«»`, `\` continuations and `#//` group
  comments. A `recover` mode collects diagnostics and carries on, which is what
  an editor wants.
- **AST** — a typed tree carrying spans and the nine raw-text properties, so
  the source can be rebuilt from the tree.
- **Printers** — `to_source` reproduces what was written; `write` re-formats in
  four styles (flat, pretty, armoured, prefer-multiline) at a chosen width, and
  `layout` hands back the layout document for a consumer with its own renderer.
- **Diagnostics** — a closed `ErrorKind` enum with the reference's own wording,
  and one adapter to `marianoguerra/error-report` for consumers that want it
  rendered rather than matched on.
- **Column algebra** — indentation columns as the partial order tabs make them,
  with `Incomparable` and `Unordered` as answers rather than as accidents.
- **Unicode tables** generated from the pinned Racket itself, so the character
  classes agree with the reference by construction.

### Conformance

Against the Racket reference over a 696-file corpus: token streams 685/685
(11 files the reference itself cannot lex), parse trees and error messages
696/696, source reproduction 696/696, and re-formatted output 696/696 across
all eleven layout modes.

### Not included

The DrRacket editor services — the incremental colourer, indentation,
navigation and armouring.
