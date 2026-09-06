// The DEVELOPMENT module. Never published; it exists so that the differential
// harness, the corpus tests and the porting tools depend on the three published
// modules the way an outside consumer would -- through their public API only,
// which is what keeps that API honest.
//
// It sits at the repository root rather than in a directory of its own so that
// `test/corpus/`, `test/golden/` and `tools/` keep the paths the justfile, the
// Python harness and AGENTS.md all use.
//
// "Never published" is a rule, not a mechanism: `moon.mod` has no `private`
// field, so a bare `moon publish` HERE would upload the corpus and the porting
// tools under this name. Always `moon -C lib` / `moon -C cli`, or better,
// `just publish-dry` and `just publish`, which cannot address this module.
name = "marianoguerra/shrubbery-dev"

version = "0.0.0"

import {
  "marianoguerra/error-report@0.1.0",
  "marianoguerra/shrubbery@0.1.1",
  "marianoguerra/shrubbery-cli@0.1.1",
  "marianoguerra/css@0.1.0",
  "marianoguerra/shrubbery-css@0.1.0",
  "moonbitlang/x@0.5.1",
}

license = "Apache-2.0"

preferred_target = "wasm"

description = "Development module for shrubbery-mb: corpus, goldens, differential harness and porting tools"
