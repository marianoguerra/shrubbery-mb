// The library. Its dependency list is short on purpose and adding to it is a
// design decision rather than a manifest edit: a module's dependencies are
// fetched by every consumer regardless of which packages they import, so
// anything here is paid for by a project that wanted only the parser.
//
// The two dependencies are the ones that could not be avoided:
//
//   * `error-report` is the diagnostic library, built in this repository and
//     kept dependency-free itself.
//   * `kawaz/grapheme` is UAX #29 grapheme segmentation, which indentation
//     columns are counted in. It is on Unicode 17 and Racket 8.18 is on its
//     own version, so a skew is possible; the answer to that is the parity
//     oracle in `unicode/parity_test.mbt`, not the packaging. The first
//     candidate for this slot, `moonbit-community/find_cluster_break`, was
//     rejected BY that oracle: it splits a Hangul L+V+T syllable into three
//     clusters and CRLF into two.
//
// The pretty-fast-pretty-printer layout engine is deliberately NOT here. It
// lives in its own module, because the reference's own renderer is what makes
// byte-exact output true by construction -- see the addendum in the plan.
name = "marianoguerra/shrubbery"

version = "0.1.1"

import {
  "marianoguerra/error-report@0.1.0",
  "kawaz/grapheme@0.10.4",
}

readme = "README.mbt.md"

repository = "https://github.com/marianoguerra/shrubbery-mb"

license = "Apache-2.0"

keywords = [ "shrubbery", "rhombus", "parser", "pretty-printer", "syntax" ]

preferred_target = "wasm"

description = "Shrubbery notation for MoonBit: parser, source-faithful and reformatting printers, and structured diagnostics"
