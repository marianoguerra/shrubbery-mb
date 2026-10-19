# Changelog

All notable changes to `marianoguerra/css` are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
module follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-10-19

### Changed

- **Builds clean on moonc v0.10.16** (moon 0.1.20261016). The trait methods
  each package keeps live — `Show::to_string`, `Compare::compare` and this
  project's own trait methods — are re-exported with an explicit `pub extend`;
  the derived Eq/Debug/Hash/ToJson/Default methods, `Show::output` and the
  Compare operators are deprecated and hidden, as the toolchain now expects.
  No change in behaviour.
- Takes `marianoguerra/error-report@0.1.1`.

## [0.1.1] - 2026-09-07

### Fixed

- **A `Bogus` closed itself with nothing.** An unparsable region is echoed
  rather than deleted, and the echo is arbitrary text — but it was printed with
  no separator after it, so in `Minified`, where the newline between statements
  is not written, the next declaration ran straight into it:
  `.a{*zoom: 1display:block}`. Both statement positions now bound it with a
  `;` — inside a rule body and at the top of a file — which is what CSS's own
  error recovery looks for and so bounds the damage instead of spreading it.
  A rule that is a `Bogus` is bounded the same way; a real rule closes itself
  with `}` and is unchanged.

## [0.1.0] - 2026-09-06

### Added

- A **semantic CSS syntax tree**, modelled on lightningcss for vocabulary and on
  biome for tolerance. Typed selectors, typed at-rule preludes, n-ary
  conditions, and a `Bogus` member on every enum a parse can fail inside of, so
  a parse always yields a tree that covers the whole source.
- A **CSS Syntax Level 3 tokenizer** (`token`), which never fails: malformed
  input produces `BadStr` and `BadUrl` tokens rather than an error, leaving the
  parser to decide what a failure means.
- A **tolerant parser** (`parse`) following the specification's own recovery —
  skip a bad declaration to the next `;`, skip a bad rule to the end of its
  block — with a strict mode that raises on the first error instead.
- A **printer** (`write`) with three modes: `Pretty`, `Compact` and `Minified`.
- **Diagnostics** (`error`) in the `error-report` style, reached from exactly
  one function.
- **Typed lenses** (`value`): `as_length`, `as_color`, `as_var`, `as_keyword`
  and the rest, plus specificity. All computed on demand and stored nowhere,
  the way biome layers `value_ext.rs` over its untyped tree -- which is what
  keeps the parser's question ("what does the text say") apart from the
  consumer's ("what does it mean").

### Notes

- The tree is semantic, not lossless: `parse` then `write` gives back CSS that
  means the same thing, not the same bytes. Numbers keep their source spelling
  and hex colours keep their digits and case, because losing those is a
  semantic loss rather than a formatting one.
- `ast` and `write` have no dependency outside this module, so building a tree
  and printing it links neither the diagnostic library nor the parser.
