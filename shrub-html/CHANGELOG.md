# Changelog

All notable changes to `marianoguerra/shrubbery-html` are recorded here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this module follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] — 2026-10-19

### Changed

- **Builds clean on moonc v0.10.16** (moon 0.1.20261016). The trait methods
  each package keeps live — `Show::to_string`, `Compare::compare` and this
  project's own trait methods — are re-exported with an explicit `pub extend`;
  the derived Eq/Debug/Hash/ToJson/Default methods, `Show::output` and the
  Compare operators are deprecated and hidden, as the toolchain now expects.
  No change in behaviour.
- Takes `marianoguerra/html@0.1.1`, `marianoguerra/shrubbery@0.1.2` and
  `marianoguerra/error-report@0.1.1`.

## [0.1.0] — 2026-09-07

### Added

- **Shrubbery HTML**, a surface syntax for HTML, SVG and MathML in shrubbery
  notation, resting on three laws: an element is a call and its children are
  its block; its attributes are its arguments, and an attribute is a
  declaration; text is a string literal.
- **`lower`**: shrubbery to a markup tree, tolerant, and a pure function of the
  shrubbery tree -- it reads `Node.span` for diagnostics and never `Node.meta`,
  so it is total over hand-built trees as well as parsed ones.
- **`emit`**: a markup tree back to shrubbery, one child per line.
- **Diagnostics** (`kind`, `error`) in the `error-report` style, reached from
  exactly one function, with codes namespaced `shrubhtml::` so a consumer can
  tell a notation problem from a markup one without parsing the string.
- **A raw-text hook** on `lower`, so a `style()` body can be lowered by
  something else -- shrubbery CSS, say -- without `marianoguerra/shrubbery-css`
  becoming a dependency every consumer of this module fetches.

### Notes

- Whitespace is never in the layout. Shrubbery's tree does not record it, so a
  space cannot mean anything unless it is inside a string -- which means the
  indentation is free and HTML's whitespace-sensitivity problem does not arise
  in this direction at all.
- `to_shrubbery` is a normalisation, not an inverse. Three things do not survive
  the detour: a character reference's spelling, because a shrubbery string holds
  a value and not a spelling; a void element's slash, because `<br/>` and `<br>`
  are one element and the notation has no house styles; and an implied end tag,
  because the notation has no end tags at all.
- One construct parses cleanly and means the wrong thing: a block runs to the
  end of its line, so in `p(): "Hello " strong(): "world" "!"` the `"!"` is a
  child of the `strong`. It gets its own warning,
  `shrubhtml::trailing_run_after_block`, guarded tightly enough that the shapes
  which merely resemble it stay quiet -- and `emit` never writes such a line, so
  nothing this module produces can be it.
