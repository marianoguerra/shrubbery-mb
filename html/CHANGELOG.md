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

### Fixed

Twelve divergences from the specification, found by checking against a
conforming WHATWG parser and against the specification's own tokenizer suite
rather than against ourselves.

From the html5lib tokenizer suite:

- A CR was not preprocessed to an LF. It is now — but only when it was in the
  source, because references are resolved after preprocessing and `&#013;`
  really is a carriage return.
- The data state replaced a NUL with U+FFFD; it should emit it. Every other
  state should replace it and several did not, including tag and attribute
  names, where NUL is a name character.
- A trailing `--` or `--!` on an unterminated comment was kept. The comment-end
  states hold those back and never append them at end of input.
- `</xmp` ended a raw-text run even when what followed could not end a tag, so
  `foo</xmp<` lost everything after the name.
- A `<script>` body ended at the first `</script>` even inside `<!-- <script>
  ... </script> -->`, cutting the script in half. It now has the escaped and
  double-escaped states.
- `</` at end of input became a comment; it is two characters.
- The doctype force-quirks flag was set by the problem rather than by the state
  it was met in. `doctype` is now written as the specification's states in
  sequence, which is what those rules require.

From the conformance oracle:

- A `<title>` or `<textarea>` body was escaped as if it were an attribute value,
  which left `<` live — so a title whose text contained `</title>` ended its own
  element. An injection, in the one raw-text context that has an escape and can
  therefore be printed safely.
- A tag that ran to the end of the input was completed rather than discarded,
  putting an element in the tree that no browser sees. It is now a `Bogus`
  carrying its source, so the printer echoes what was there.
- `<`, `"` and `'` were treated as ending a name. They are name characters:
  `<a<b>` is one tag called `a<b`.
- `<div =x>` dropped the `=`, silently renaming the attribute. The `=` before a
  name is part of it.

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
