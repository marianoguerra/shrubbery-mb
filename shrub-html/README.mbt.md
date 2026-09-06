# marianoguerra/shrubbery-html

HTML — and SVG, and MathML — written in
[shrubbery notation](https://docs.racket-lang.org/shrubbery/), lowered to a
[markup tree](https://mooncakes.io/docs/marianoguerra/html).

This is the only module that names both sides. `marianoguerra/html` knows
nothing about shrubbery; `marianoguerra/shrubbery` knows nothing about markup.
Keeping the join here is what lets a project take either half without paying for
the other.

## The syntax, in three laws

1. **An element is a call; its children are its block.**
2. **Its attributes are its arguments; an attribute is a declaration.**
3. **Text is a string literal.** Whitespace only ever exists inside one.

```mbt check
///|
test "a page" {
  let src =
    #|doctype()
    #|html(lang: "en"):
    #|  head():
    #|    meta(charset: "utf-8")
    #|    title(): "Shrubbery HTML"
    #|  body():
    #|    main(class: "card"):
    #|      h1(): "Hello"
  inspect(
    @shrubbery_html.to_html(src),
    content=(
      #|<!DOCTYPE html>
      #|<html lang="en">
      #|  <head>
      #|    <meta charset="utf-8">
      #|    <title>Shrubbery HTML</title>
      #|  </head>
      #|  <body>
      #|    <main class="card">
      #|      <h1>Hello</h1>
      #|    </main>
      #|  </body>
      #|</html>
      #|
    ),
  )
}
```

Every one of `<`, `>`, `</`, `/>`, `=`, `&…;` and `<!-- -->` disappears.

| HTML | what it is | Shrubbery HTML |
|---|---|---|
| `<div>…</div>` | an element | `div(): …` |
| `<br>` | a void element | `br()` |
| `src="a.png"` | an attribute | `src: "a.png"` |
| `checked` | a valueless attribute | `checked` |
| `data-id="3"` | a hyphenated name | `data_id: "3"` |
| `xlink:href="#a"` | a name `_`→`-` cannot reach | `attr("xlink:href", "#a")` |
| `<my-element>` | a custom element | `my_element():` |
| `<text>` (SVG) | a name this syntax has taken | `element("text"):` |
| `Hello` | text | `"Hello"` |
| `&nbsp;` | a character reference | the character, inside the string |
| `<!-- x -->` | a comment | `comment(" x ")` |
| `<!DOCTYPE html>` | the doctype | `doctype()` |
| `<script>…</script>` | raw text | `script(): @{…}` |
| `<svg>…</svg>` | foreign content | `svg(): …` |
| `<![CDATA[…]]>` | CDATA, foreign only | `cdata("…")` |

## Whitespace is never in the layout

HTML formatting is hard for exactly one reason: whitespace is significant, so a
pretty-printer that adds a newline changes what the page looks like. Prettier
needs a three-valued option for it. Here the question does not arise —
shrubbery's tree does not record whitespace, so a space cannot mean anything
unless it is inside a string, and the string says so:

```mbt check
///|
test "the space is in the string, or it is nowhere" {
  inspect(
    @shrubbery_html.to_html(
      "p():\n  \"Read \"\n  a(href: \"/x\"): \"more\"\n",
      style=Minified,
    ),
    content="<p>Read <a href=/x>more</a></p>",
  )
  inspect(
    @shrubbery_html.to_html(
      "p():\n  \"Read\"\n  a(href: \"/x\"): \"more\"\n",
      style=Minified,
    ),
    content="<p>Read<a href=/x>more</a></p>",
  )
}
```

Reindent the source however you like: the rendered page is unchanged.

## The namespace follows the element

`svg()` and `math()` enter a vocabulary and an HTML integration point leaves
one, exactly as in HTML — so there is no keyword for it. SVG's camelCase names
are already legal shrubbery identifiers, so they are written as they are spelled:

```mbt check
///|
test "SVG, and HTML again inside it" {
  let src =
    #|svg(viewBox: "0 0 24 24"):
    #|  linearGradient(id: "g"):
    #|    stop(offset: "0%", stop_color: "#2F6B4F")
    #|  foreignObject():
    #|    br()
  inspect(
    @shrubbery_html.to_html(src, style=Minified),
    content="<svg viewBox=\"0 0 24 24\"><linearGradient id=g><stop offset=0% stop-color=#2F6B4F /></linearGradient><foreignObject><br></foreignObject></svg>",
  )
}
```

`br` is void in that `foreignObject` and would not be one line further out.
That is the whole reason a markup parser has to know about namespaces at all.

## Raw text has a native spelling

Shrubbery's `@` notation is an indentation-stripping literal text block, which
is exactly what `script`, `style`, `pre` and `textarea` need:

```mbt check
///|
test "a script is text, not markup" {
  let src =
    #|script(type: "module"):
    #|  @{
    #|    if (a < b) { go() }
    #|  }
  inspect(
    @shrubbery_html.to_html(src, style=Minified),
    content="<script type=module>if (a < b) { go() }</script>",
  )
}
```

The obvious next thought — let a `style()` body hold shrubbery CSS — is not a
dependency here, because a module's dependencies are fetched by every consumer
and an HTML user should not pay for the CSS tables. `lower` takes a `hook` for
it instead, so a consumer that already depends on both halves — a site
generator, say — gets the composition, and everyone else pays nothing.

## Both directions

HTML in, shrubbery out, and the loop closes: what comes back lowers to the same
tree it came from.

```mbt check
///|
test "HTML becomes shrubbery, and back again" {
  let shrub = @shrubbery_html.to_shrubbery(
    "<p>Read <a href=\"/x\">more</a>.</p>",
  )
  inspect(
    shrub,
    content=(
      #|p():
      #|  "Read "
      #|  a(href: "/x"):
      #|    "more"
      #|  "."
      #|
    ),
  )
  inspect(
    @shrubbery_html.to_html(shrub, style=Minified),
    content="<p>Read <a href=/x>more</a>.</p>",
  )
}
```

It is a normalisation rather than an inverse, and three things do not survive
the detour. A character reference loses its spelling, because a shrubbery string
holds a value and not a spelling. A void element loses its slash: `<br/>` comes
back as `<br>`, since the two are one element and the notation has no house
styles. And an implied end tag becomes explicit — the notation has no end tags
at all, so `<ul><li>a<li>b</ul>` comes back with both `</li>`s written.

## The one construct that means the wrong thing

A block runs to the end of its line, so everything after a `:` goes *inside* it:

```mbt check
///|
test "a block swallows the rest of its line" {
  let l = @shrubbery_html.lower("p(): \"Hello \" strong(): \"world\" \"!\"\n")
  // The `!` is a child of the `strong`, not a sibling of it.
  inspect(
    @write.document(l.document(), style=Minified),
    content="<p>Hello <strong>world!</strong></p>",
  )
  inspect(
    l.diagnostics()[0].kind.code(),
    content="shrubhtml::trailing_run_after_block",
  )
}
```

An element with children has to come last in its run. `to_shrubbery` never
writes such a line — it puts one child per line, always — so nothing this module
emits can be it.

## Diagnostics name the fix

A syntax nobody has seen before is worth diagnosing precisely, so where the
mistake is recognisable the message says what to type instead.

```mbt check
///|
test "an HTML habit is met with its replacement" {
  let l = @shrubbery_html.lower("<div>\n")
  inspect(l.diagnostics()[0].kind.code(), content="shrubhtml::sigil_tag")
}
```

## Layout

| package | what |
|---|---|
| `names` | the tables: `_` ⇄ `-`, the reserved calls, string quoting |
| `kind`, `error` | diagnostics, and the one bridge to `error-report` |
| `lower` | shrubbery → a markup tree |
| `emit` | a markup tree → shrubbery |

## Licence

Apache-2.0.
