// The HTML library: a semantic MARKUP tree -- HTML, SVG and MathML -- a
// tolerant parser from markup text, and a printer back to it. It knows nothing
// about shrubbery notation.
//
// It is a module rather than a package inside `lib/` for the reason `css` is:
// a module's dependencies are fetched by every consumer regardless of which
// packages they import, so folding this into `shrubbery` would make a project
// that wanted only the notation pay for the HTML tables, and folding the
// notation in here would make a project that wanted only a markup parser fetch
// the whole port. The bridge lives in `shrubbery-html`, which is the only
// module that names both.
//
// MARKUP tree, not document tree, and the distinction is the whole design.
// This is what was written -- `<p>a<p>b` is two start tags and no end tags,
// every byte accounted for, nothing invented and nothing moved. A conforming
// WHATWG parse is a different tree: it invents `html`/`head`/`body`, repairs
// misnesting through the adoption agency, and foster-parents text out of
// tables. That tree is not reversible, so a formatter cannot be built on it.
//
// The single dependency is `error-report`, and it is reached from exactly one
// function, in `error/`. Everything below that -- `span`, `kind`, `names`,
// `ast`, `write` -- has no dependency at all, so building a tree and printing
// it links neither the diagnostic library nor the parser.
name = "marianoguerra/html"

version = "0.1.0"

import {
  "marianoguerra/error-report@0.1.0",
}

readme = "README.mbt.md"

repository = "https://github.com/marianoguerra/shrubbery-mb"

license = "Apache-2.0"

keywords = [ "html", "svg", "mathml", "parser", "printer" ]

preferred_target = "wasm"

description = "A semantic markup tree for MoonBit: HTML, SVG and MathML, with a tolerant parser, a printer with pretty, compact and minified modes, and structured diagnostics"
