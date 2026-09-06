// The bridge: shrubbery notation to a CSS syntax tree, and back.
//
// This is the only module that names both sides, and that is the whole reason
// it exists. `marianoguerra/css` knows nothing about shrubbery;
// `marianoguerra/shrubbery` knows nothing about CSS. Keeping the join in a
// module of its own is what lets a consumer take either half without paying
// for the other -- a module's dependencies are fetched by every consumer
// regardless of which packages they import, so a bridge folded into either
// side would tax everyone who wanted only that side.
//
// It is also the module most likely to change, because the surface syntax it
// implements is still being argued about. Nothing downstream of a decision
// here has to move when one is revised.
name = "marianoguerra/shrubbery-css"

version = "0.1.0"

import {
  "marianoguerra/css@0.1.0",
  "marianoguerra/shrubbery@0.1.1",
  "marianoguerra/error-report@0.1.0",
}

readme = "README.mbt.md"

repository = "https://github.com/marianoguerra/shrubbery-mb"

license = "Apache-2.0"

keywords = [ "css", "shrubbery", "rhombus", "syntax", "transpiler" ]

preferred_target = "wasm"

description = "CSS in shrubbery notation: lower shrubbery to a CSS tree, and print a CSS tree back as shrubbery"
