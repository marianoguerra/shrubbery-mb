// The CSS library: a semantic CSS syntax tree, a tolerant parser from CSS text,
// and a printer back to it. It knows nothing about shrubbery notation.
//
// That ignorance is the point, and it is why this is a module rather than a
// package inside `lib/`. A module's dependencies are fetched by every consumer
// regardless of which packages they import, so folding CSS into `shrubbery`
// would make a project that wanted only the notation pay for the CSS tables,
// and folding the notation in here would make a project that wanted only a CSS
// parser fetch the whole port. The bridge between the two lives in
// `shrubbery-css`, which is the only module that names both.
//
// The single dependency is `error-report`, and it is reached from exactly one
// function, in `error/`. Everything below that -- `span`, `kind`, `ast`,
// `write` -- has no dependency at all, so building a tree and printing it links
// neither the diagnostic library nor the parser.
name = "marianoguerra/css"

version = "0.1.0"

import {
  "marianoguerra/error-report@0.1.0",
}

readme = "README.mbt.md"

repository = "https://github.com/marianoguerra/shrubbery-mb"

license = "Apache-2.0"

keywords = [ "css", "parser", "printer", "ast", "stylesheet" ]

preferred_target = "wasm"

description = "A semantic CSS syntax tree for MoonBit: a tolerant parser, a printer with pretty, compact and minified modes, and structured diagnostics"
