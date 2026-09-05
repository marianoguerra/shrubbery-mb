// A GENERIC diagnostic library in the lineage of Rust's miette,
// codespan-reporting and ariadne. It currently shares a repository with its
// first consumer, but it is written to be lifted out of that repository
// unchanged -- so it must never name that consumer, and it must never grow a
// dependency.
//
// `tools/boundary-check.sh` enforces both, because both erode quietly: every
// `moon.pkg` under this module may import only `moonbitlang/core` and its
// siblings, and no file here may mention the consumer. That is what keeps the
// spin-out a `git filter-repo` rather than an untangling.
name = "marianoguerra/error-report"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/marianoguerra/shrubbery-mb"

license = "Apache-2.0"

keywords = [
  "diagnostics",
  "errors",
  "error-reporting",
  "source-code",
  "compiler",
]

preferred_target = "wasm"

description = "Source-annotated diagnostic reports: data first, renderers second. Inspired by miette, codespan-reporting and ariadne."
