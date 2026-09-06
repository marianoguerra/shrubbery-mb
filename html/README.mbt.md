# marianoguerra/html

A semantic **markup** tree for MoonBit — HTML, SVG and MathML — with a tolerant
parser, a printer with pretty, compact and minified modes, and structured
diagnostics.

It knows nothing about shrubbery notation. The bridge between the two lives in
[`marianoguerra/shrubbery-html`](https://mooncakes.io/docs/marianoguerra/shrubbery-html),
so a project that wants only a markup parser does not fetch a notation port, and
a project that wants only the notation does not fetch the HTML tables.

## Parse and print

```mbt check
///|
test "parse then print" {
  let p = @html.parse("<div class=\"card\"><p>hi</p></div>")
  inspect(
    @html.to_html(p.document()),
    content=(
      #|<div class="card">
      #|  <p>hi</p>
      #|</div>
      #|
    ),
  )
  inspect(
    @html.to_html(p.document(), style=Minified),
    content="<div class=card><p>hi</p></div>",
  )
}
```

## Markup, not a document

This is a tree of **what was written**, not of what a browser would build.
`<p>a<p>b` is two start tags and no end tags; nothing is invented and nothing
moves. That is the difference between this library and a conforming WHATWG
parser such as
[`moonbit-community/html`](https://mooncakes.io/docs/moonbit-community/html),
and it is the reason this one can print its tree back.

What it does take from tree construction is the part the specification states as
*tables* rather than as algorithms — implied end tags, void elements, raw text,
and namespaces — so real markup still nests the way it reads:

```mbt check
///|
test "an implied end tag is recognised, and stays implied" {
  let p = @html.parse("<ul><li>one<li>two</ul>")
  inspect(
    @html.to_html(p.document()),
    content=(
      #|<ul>
      #|  <li>one
      #|  <li>two
      #|</ul>
      #|
    ),
  )
}
```

What it does not take is the algorithmic residue: the adoption agency, foster
parenting, and the invented `html`/`head`/`body`.

## Tolerant by default

A stray end tag is dropped and an unclosed element is closed, exactly as a
browser does, and the rest of the file still parses. Nothing is dropped
silently: what could not be read becomes a diagnostic.

```mbt check
///|
test "a stray end tag does not take the document with it" {
  let p = @html.parse("<div>a</span>b</div>")
  inspect(@html.to_html(p.document(), style=Minified), content="<div>ab</div>")
  inspect(p.diagnostics().length(), content="1")
  inspect(p.diagnostics()[0].kind.code(), content="html::stray_end_tag")
}
```

Pass `strict=true` when the file is yours and you want the first problem raised
instead.

## Whitespace is the whole problem, and the printer knows it

A pretty-printer that adds a newline between two inline elements changes what
the page looks like. So whitespace is rearranged only where it is already
insignificant — inside a block-level element all of whose children are
themselves block-level or whitespace:

```mbt check
///|
test "inline content is never reflowed" {
  let p = @html.parse("<p>Read <em>this</em> now</p>")
  inspect(
    @html.to_html(p.document()),
    content=(
      #|<p>Read <em>this</em> now</p>
      #|
    ),
  )
}
```

The policy is Prettier's, under Prettier's names: `whitespace=Css` (the
default), `Strict`, or `Ignore`.

## SVG and MathML are not decoration

The namespace decides four things that are otherwise ambiguous in the same
bytes: whether `/>` closes an element or does nothing, whether an attribute name
is lowercased or restored from a table, whether `<![CDATA[` is CDATA or a
comment, and whether `<title>` holds text or elements.

```mbt check
///|
test "foreign content keeps the case its vocabulary spells names with" {
  let p = @html.parse(
    "<svg viewbox=\"0 0 1 1\"><lineargradient/><circle r=\"1\"/></svg>",
  )
  inspect(
    @html.to_html(p.document(), style=Minified),
    content="<svg viewBox=\"0 0 1 1\"><linearGradient/><circle r=1 /></svg>",
  )
}
```

## What survives a round trip, and what does not

This is a semantic tree, so `parse` then `to_html` gives back markup that
*means* the same thing, not the same bytes. Four things are preserved anyway,
because losing them would be a semantic loss rather than a formatting one: a
character reference's spelling, attribute order, `disabled` against
`disabled=""`, and how an element was closed.

```mbt check
///|
test "a character reference keeps its spelling" {
  let p = @html.parse("<p>a &amp; b &nbsp; c</p>")
  inspect(
    @html.to_html(p.document(), style=Minified),
    content="<p>a &amp; b &nbsp; c</p>",
  )
}
```

Everything else is normalised: tag and attribute name case, attribute quoting,
and insignificant whitespace under the configured policy.

## Text cannot escape its node

A tree built in memory and printed is a template engine, and the question a
template engine has to answer is whether a value can break out of the node it
was put in.

```mbt check
///|
test "what goes in comes back out" {
  let p = @html.parse("<p title=\"x\">y</p>")
  let hostile = "</p><script>alert(1)</script>"
  match p.document().children[0] {
    Element(e) => {
      let d : @ast.Document = {
        children: [Element({ ..e, children: [Text(@ast.Text::new(hostile))], })],
        span: @span.nowhere,
      }
      let printed = @html.to_html(d, style=Minified)
      inspect(
        printed,
        content="<p title=x>&lt;/p&gt;&lt;script&gt;alert(1)&lt;/script&gt;</p>",
      )
      match @html.parse(printed).document().children[0] {
        Element(back) =>
          inspect(@html.text_content(Element(back)), content=hostile)
        _ => fail("expected a p")
      }
    }
    _ => fail("expected a p")
  }
}
```

There is one context with no escape at all — a `script` body containing
`</script` — and there the printer refuses rather than rewriting the script:
`to_html` emits the bytes unchanged and `@write.document_checked` returns an
`html::unprintable_raw_text` alongside them.

## Typed readings, on demand

The tree is untyped by design: an attribute's value is a string, because that is
what it is in the source. Asking what one *means* is a separate question,
answered by a lens — a pure function computed on demand and stored nowhere.

```mbt check
///|
test "lenses read an untyped tree" {
  let p = @html.parse("<input id=\"q\" class=\"a  b\" size=\"12\" disabled>")
  match @value.by_id(p.document(), "q") {
    Some(e) => {
      inspect(@html.class_list(e).length(), content="2")
      assert_eq(@value.as_int(e, "size"), Some(12))
      // HTML ignores a boolean attribute's value, so this lens does too.
      inspect(@value.as_bool(e, "disabled"), content="true")
    }
    None => fail("expected to find #q")
  }
}
```

## Layout

| package | what | depends on |
|---|---|---|
| `span` | source ranges, in UTF-16 code units | nothing |
| `kind` | the closed set of error kinds, named after the specification's | nothing |
| `names` | the tables: void, raw text, implied end tags, default `display`, SVG/MathML case adjust, 2,231 named references | nothing |
| `ast` | the tree | `span`, `kind` |
| `write` | the printer, three modes and one whitespace policy | `ast`, `names` |
| `error` | diagnostics, and the one bridge to `error-report` | `span`, `kind` |
| `token` | the markup tokenizer | `span`, `names` |
| `value` | typed lenses over elements and attributes | `ast`, `names` |
| `parse` | markup text to a tree | all of the above |

Building a tree and printing it links neither the diagnostic library nor the
parser: `ast`, `names` and `write` have no dependency outside this module.

## Licence

Apache-2.0.
