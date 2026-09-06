# Changelog

All notable changes to `marianoguerra/shrubbery-css` are recorded here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this module follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **The lowering**: shrubbery notation to a `marianoguerra/css` syntax tree.
  Selectors, declarations, values, and the at-rules with typed preludes.
- **Name tables** (`names`): units, pseudo-classes, pseudo-elements, at-rules,
  relations, and the `_` ⇄ `-` identifier transform with its two escapes.
- **Diagnostics** (`error`, `kind`) that name the replacement rather than
  describing the problem, since the syntax is new to every reader.
- **The emitter** (`emit`): a CSS tree back to shrubbery notation, closing the
  loop. CSS → tree → shrubbery → tree → CSS reproduces the CSS.

### Notes

- The lowering is a pure function of the shrubbery tree: it reads `Node.span`
  for diagnostics and never `Node.meta`. That is what makes it total over
  hand-built trees, which is what will let the round-trip properties generate
  trees rather than text.
- The loop is a normalisation, not an inverse. A number loses its source
  spelling on the way through the notation (`1.50` → `1.5`, `+1` → `1`),
  because shrubbery's numeric literal holds a value rather than a spelling.
  Recovering it would mean reading raw metadata, which the lowering refuses to
  do on purpose.
- Selector lists are `[h1, h2]`, not `is(h1, h2)`. `:is()` gives every arm the
  specificity of its most specific member, so spelling a list that way would
  silently change what the stylesheet matches.
