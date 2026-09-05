// The library. `marianoguerra/error-report` is its ONLY module dependency, and
// that is a deliberate exception rather than the start of a habit: a module's
// dependencies are fetched by every consumer regardless of which packages they
// import, so anything added here is paid for by a project that wanted only the
// parser.
//
// Two things are therefore NOT here. The UAX #29 grapheme segmenter is
// vendored into `unicode/grapheme/` under a pinned sha256. The
// pretty-fast-pretty-printer layout engine lives in its own module, because the
// reference's own renderer is what makes byte-exact output true by construction
// -- see the addendum in the plan.
name = "marianoguerra/shrubbery"

version = "0.1.0"

import {
  "marianoguerra/error-report@0.1.0",
}

readme = "README.mbt.md"

repository = ""

license = "Apache-2.0"

keywords = [ "shrubbery", "rhombus", "parser", "pretty-printer", "syntax" ]

preferred_target = "wasm"

description = "Shrubbery notation for MoonBit: parser, source-faithful and reformatting printers, and structured diagnostics"
