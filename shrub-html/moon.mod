// The bridge: shrubbery notation to a markup tree, and back.
//
// This is the only module that names both sides, and that is the whole reason
// it exists. `marianoguerra/html` knows nothing about shrubbery;
// `marianoguerra/shrubbery` knows nothing about markup. Keeping the join in a
// module of its own is what lets a consumer take either half without paying
// for the other -- a module's dependencies are fetched by every consumer
// regardless of which packages they import, so a bridge folded into either
// side would tax everyone who wanted only that side.
//
// The same rule is why `marianoguerra/shrubbery-css` is NOT a dependency here,
// tempting as it is to let a `style()` body hold shrubbery CSS: every consumer
// of this module would then fetch the CSS tables. `lower` takes an optional
// hook for a raw-text element's body instead, and the CLI -- which already
// depends on everything -- is where the two halves meet.
//
// It is also the module most likely to change, because the surface syntax it
// implements is still being argued about. Nothing downstream of a decision
// here has to move when one is revised.
name = "marianoguerra/shrubbery-html"

version = "0.1.0"

import {
  "marianoguerra/html@0.1.0",
  "marianoguerra/shrubbery@0.1.1",
  "marianoguerra/error-report@0.1.0",
}

readme = "README.mbt.md"

repository = "https://github.com/marianoguerra/shrubbery-mb"

license = "Apache-2.0"

keywords = [ "html", "shrubbery", "rhombus", "syntax", "transpiler" ]

preferred_target = "wasm"

description = "HTML in shrubbery notation: lower shrubbery to a markup tree, and print a markup tree back as shrubbery"
