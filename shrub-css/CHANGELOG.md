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

### Notes

- The lowering is a pure function of the shrubbery tree: it reads `Node.span`
  for diagnostics and never `Node.meta`. That is what makes it total over
  hand-built trees, which is what will let the round-trip properties generate
  trees rather than text.
- Selector lists are `[h1, h2]`, not `is(h1, h2)`. `:is()` gives every arm the
  specificity of its most specific member, so spelling a list that way would
  silently change what the stylesheet matches.
