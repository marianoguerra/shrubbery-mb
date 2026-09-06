# marianoguerra/css

A semantic CSS syntax tree for MoonBit: a tolerant parser, a printer with
pretty, compact and minified modes, and structured diagnostics.

It knows nothing about shrubbery notation. The bridge between the two lives in
[`marianoguerra/shrubbery-css`](https://mooncakes.io/docs/marianoguerra/shrubbery-css),
so a project that wants only a CSS parser does not fetch a notation port, and a
project that wants only the notation does not fetch the CSS tables.

## Parse and print

```mbt check
///|
test "parse then print" {
  let p = @css.parse(".card{display:grid;gap:1rem}")
  inspect(
    @css.to_css(p.sheet()),
    content=(
      #|.card {
      #|  display: grid;
      #|  gap: 1rem;
      #|}
      #|
    ),
  )
  inspect(
    @css.to_css(p.sheet(), style=Minified),
    content=".card{display:grid;gap:1rem}",
  )
}
```

## Tolerant by default

A malformed declaration is skipped to the next `;`, exactly as the CSS
specification says, and the rest of the file still parses. Nothing is dropped
silently: what could not be read becomes a diagnostic.

```mbt check
///|
test "a bad declaration does not take the rule with it" {
  let p = @css.parse("a { color red; margin: 0 }")
  inspect(@css.to_css(p.sheet(), style=Minified), content="a{margin:0}")
  inspect(p.diagnostics().length(), content="1")
  inspect(p.diagnostics()[0].kind.code(), content="css::expected_colon")
}
```

Pass `strict=true` when the file is yours and you want the first problem
raised instead.

## What survives a round trip, and what does not

This is a semantic tree, so `parse` then `to_css` gives back CSS that *means*
the same thing, not the same bytes. Two things are preserved anyway, because
losing them would be a semantic loss rather than a formatting one:

```mbt check
///|
test "numbers and hex colours keep their spelling" {
  let p = @css.parse("a{w:1.50;c:#FFF}")
  inspect(@css.to_css(p.sheet(), style=Minified), content="a{w:1.50;c:#FFF}")
}
```

Everything else is normalised: `'x'` becomes `"x"`, `:before` becomes
`::before`, `url(a.png)` and `url("a.png")` become the same node, and
`:nth-child(odd)` becomes `:nth-child(2n+1)`.

## An at-rule it does not know is kept whole

CSS gains at-rules faster than any parser learns them, so an unrecognised one
is a warning and not an error, and its prelude and block are kept unparsed.

```mbt check
///|
test "an unknown at-rule survives" {
  let p = @css.parse("@tailwind base;\na{b:c}")
  inspect(
    @css.to_css(p.sheet(), style=Minified),
    content="@tailwind base;a{b:c}",
  )
  inspect(p.diagnostics()[0].kind.code(), content="css::unknown_at_rule")
}
```

## Typed readings, on demand

Values parse into a generic component-value tree, which is what makes coverage
total. Asking what one *means* is a separate question, answered by a lens: a
pure function computed on demand and stored nowhere.

```mbt check
///|
test "lenses read an untyped tree" {
  let p = @css.parse("a { width: 10px; color: #f80 }")
  match p.sheet().items[0] {
    Rule(Style(r)) => {
      match r.body[0] {
        Decl(d) =>
          match @css.as_length(d.value[0]) {
            Some(len) => inspect(len.unit, content="px")
            None => fail("10px is a length")
          }
        _ => fail("expected a declaration")
      }
      match r.body[1] {
        Decl(d) =>
          match @css.as_color(d.value[0]) {
            Some(c) =>
              match @value.to_rgba(c) {
                Some((r, g, b, _)) => {
                  assert_eq(r, 255)
                  assert_eq(g, 136)
                  assert_eq(b, 0)
                }
                None => fail("#f80 resolves")
              }
            None => fail("#f80 is a colour")
          }
        _ => fail("expected a declaration")
      }
    }
    _ => fail("expected a style rule")
  }
}
```

Specificity is a lens too, rather than a field kept correct through every
rewrite for a question nobody has asked yet:

```mbt check
///|
test "specificity is computed, not stored" {
  let p = @css.parse("#a .b c { x: y }")
  match p.sheet().items[0] {
    Rule(Style(r)) => {
      let (a, b, c) = @css.specificity(r.selectors[0]).to_triple()
      assert_eq(a, 1)
      assert_eq(b, 1)
      assert_eq(c, 1)
    }
    _ => fail("expected a style rule")
  }
}
```

`:is()` takes the specificity of its most specific argument and `:where()`
contributes nothing — which is exactly why a selector list may not be spelled
`is(...)` in the shrubbery syntax.

## Layout

| package | what | depends on |
|---|---|---|
| `span` | source ranges, in UTF-16 code units | nothing |
| `kind` | the closed set of error kinds | nothing |
| `ast` | the tree | `span`, `kind` |
| `write` | the printer, three modes | `ast` |
| `error` | diagnostics, and the one bridge to `error-report` | `span`, `kind` |
| `token` | the CSS Syntax Level 3 tokenizer | `span` |
| `value` | typed lenses over values, and specificity | `ast` |
| `parse` | CSS text to a tree | all of the above |

Building a tree and printing it links neither the diagnostic library nor the
parser: `ast` and `write` have no dependency outside this module.

## Licence

Apache-2.0.
