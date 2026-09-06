# Changelog

All notable changes to `marianoguerra/html` are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
module follows [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A **semantic markup tree** — HTML, SVG and MathML — modelled on biome for
  tolerance and on html5ever for vocabulary. A `Bogus` member on every enum a
  parse can fail inside of, so a parse always yields a tree that covers the
  whole source, and an element's name is a namespace and a local name rather
  than a string.
- A **markup tokenizer** (`token`), which never fails: anything it cannot read
  becomes a token carrying the source it covered, leaving the parser to decide
  what a failure means. It resolves all 2,231 named character references, with
  and without their `;`, and applies the Windows-1252 remapping that makes
  `&#147;` a curly quote.
- A **tolerant parser** (`parse`): a stray end tag is dropped and an unclosed
  element is closed, both with a diagnostic, and a strict mode raises on the
  first error instead.
- A **printer** (`write`) with three modes — `Pretty`, `Compact` and `Minified`
  — and Prettier's three-valued whitespace policy under Prettier's names.
- **Diagnostics** (`error`) in the `error-report` style, reached from exactly
  one function, with kinds named after the WHATWG parse-error catalogue.
- **Tables** (`names`): void elements, raw text, implied end tags, default
  `display`, the SVG and MathML case-adjust tables, and the named character
  references.
- **Typed lenses** (`value`): `attr`, `as_int`, `as_bool`, `class_list`,
  `text_content`, `elements`, `by_id`, `by_tag`, `display_of`. All computed on
  demand and stored nowhere.

### Notes

- This is a **markup** tree, not a document tree. `<p>a<p>b` is two start tags
  and no end tags: nothing is invented and nothing moves. A conforming WHATWG
  parse is a different tree and is not reversible, so a formatter cannot be
  built on one. The part of tree construction the specification states as
  *tables* — implied end tags, void elements, raw text, namespaces — is applied;
  the algorithmic residue — the adoption agency, foster parenting, the invented
  `html`/`head`/`body` — is not.
- The tree is semantic, not lossless: `parse` then `write` gives back markup
  that means the same thing, not the same bytes. A character reference's
  spelling, attribute order, `disabled` against `disabled=""`, and how an
  element was closed are all preserved, because losing those is a semantic loss
  rather than a formatting one.
- There is exactly one thing the printer cannot write: a raw-text body
  containing its own end tag. It refuses rather than rewriting the script —
  `document_checked` returns `html::unprintable_raw_text` — because silently
  changing the text of a `<script>` is how a formatter becomes a security bug.
- `ast`, `names` and `write` have no dependency outside this module, so building
  a tree and printing it links neither the diagnostic library nor the parser.
