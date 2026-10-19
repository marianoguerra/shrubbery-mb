# Changelog

All notable changes to `marianoguerra/shrubbery-css` are recorded here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this module follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-10-19

### Changed

- **Builds clean on moonc v0.10.16** (moon 0.1.20261016). The trait methods
  each package keeps live — `Show::to_string`, `Compare::compare` and this
  project's own trait methods — are re-exported with an explicit `pub extend`;
  the derived Eq/Debug/Hash/ToJson/Default methods, `Show::output` and the
  Compare operators are deprecated and hidden, as the toolchain now expects.
  No change in behaviour.
- Takes `marianoguerra/css@0.1.2`, `marianoguerra/shrubbery@0.1.2` and
  `marianoguerra/error-report@0.1.1`.

## [0.2.0] - 2026-09-07

Four findings from the first outside consumer, and a fifth found while fixing
them. Three were diagnostics that could not fire.

### Fixed

- **`declaration_at_top_level` never fired.** The context is the first level of
  the rule-versus-declaration cascade, and at the top of a file it answered
  "rule" before any shape was read — so `color: red` lowered to a rule with a
  type selector called `color` and printed `color{ red}`, which reads as valid
  CSS and is not. What a group *is* and what it *looks like* are now two
  questions: the context still decides the first, and the second is what lets
  the refusal say `declaration_at_top_level` and point at `root():`. The
  `a: hover` mistake keeps `colon_pseudo`, which is the more useful reading.
- **`rule_in_declaration_context` never fired either**, for the same reason one
  level in: `font_face()` said "declaration" by fiat, so a nested rule in there
  was read as one and printed `@font-face{a:color : red}`.
- **A top-level-only at-rule was accepted inside a style rule**, with no
  diagnostic at all. `@font-face`, `@page`, `@property`, `@counter-style`,
  `@keyframes`, `@import`, `@charset`, `@namespace` and the rest cannot nest,
  and a browser *drops* one rather than complaining — so accepting it printed
  CSS that silently did nothing. New kind: `at_rule_not_nestable`. The
  conditional group rules (`media`, `supports`, `container`, `layer`, `scope`,
  `starting_style`) do nest and are unaffected, and the check is against the
  *enclosing* context, so a `@font-face` inside an `@media` at the top of a file
  is still legal. Blockless at-rules reach the check too; they used to be
  reported as a bare word.
- **A refusal carried source layout into `Minified` output.** The echo came from
  `Node::to_source`, which reproduces the source — newline and indentation
  included — so a minified stylesheet contained a literal line break. It is now
  the shrubbery printed flat. That also restores the module's own rule: the
  lowering reads `Node.span` and never `Node.meta`, and `to_source` reads
  `meta`, so the echo had been empty for exactly the hand-built trees the
  property tests generate.

### Added

- **`lower_block`** (and `lower_block_source` in `lower`), for a consumer
  holding a SCOPED fragment — everything that goes inside one
  `[data-cid="3"] { ... }`. `lower` starts at the top of a file, where CSS has
  no declarations, so a fragment made of exactly those could not be lowered
  without wrapping it in a synthetic rule and unwrapping the result. This is the
  same lowering in the context that admits both.
- `names.is_nestable_at_rule`, the table the new check reads.

### Changed

- `ErrorKind` has a new member, `AtRuleNotNestable(String)`. It is `pub(all)`,
  so an exhaustive match over it needs a new arm — which is why this is a minor
  bump rather than a patch.
- The `loop` oracle's `prettier` floor rises from 96 to 100: four more files
  survive the detour now that an echoed unparsable region no longer swallows the
  declaration after it.

## [0.1.0] - 2026-09-06

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
