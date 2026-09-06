# marianoguerra/shrubbery-css

CSS written in [shrubbery notation](https://docs.racket-lang.org/shrubbery/),
lowered to a [CSS syntax tree](https://mooncakes.io/docs/marianoguerra/css).

This is the only module that names both sides. `marianoguerra/css` knows nothing
about shrubbery; `marianoguerra/shrubbery` knows nothing about CSS. Keeping the
join here is what lets a project take either half without paying for the other.

## The syntax, in one rule

**Write the thing's name, not a symbol for it.** A thing is a call; a relation
is a keyword.

```mbt check
///|
test "a rule" {
  let src =
    #|class(card):
    #|  display: grid
    #|  gap: rem(1)
  inspect(
    @shrubbery_css.to_css(src, style=Minified),
    content=".card{display:grid;gap:1rem}",
  )
}
```

| CSS | what it is | shrubbery |
|---|---|---|
| `.card` | a class | `class(card)` |
| `div` | an element | `div`, or `tag("…")` when the name needs quoting |
| `#sidebar` | an id | `id(sidebar)` |
| `:hover` | a pseudo-class | `hover()` |
| `::before` | a pseudo-element | `element(before)` |
| `[type="text"]` | an attribute match | `has_attr(type = "text")` |
| `*` | any element | `any()` |
| `&` | the parent selector | `parent()` |
| `#f7f7f7` | a hex colour | `hex(f7f7f7)` |
| `10px` | ten pixels | `px(10)` |
| `50%` | fifty percent | `percent(50)` |
| `!important` | the important flag | `important()` |
| `@media (…)` | the media at-rule | `media(…)` |
| `a b` | b is inside a | `a ~in b` |
| `a > b` | b is a child of a | `a ~child b` |
| `a + b` | b is the next sibling | `a ~next b` |
| `a ~ b` | b is a later sibling | `a ~sibling b` |

A declaration needs no translation at all: `color: red` is already a shrubbery
group with a block.

## Whitespace is not a relation

Shrubbery's tree does not record whitespace, so a space cannot mean anything.
Juxtaposition is one compound selector, and every relation is written out. That
is the cost of the design, and it buys a distinction CSS's own spelling cannot
survive here:

```mbt check
///|
test "compound and descendant are different, and both are expressible" {
  inspect(
    @shrubbery_css.to_css("a class(b):\n  x: y\n", style=Minified),
    content="a.b{x:y}",
  )
  inspect(
    @shrubbery_css.to_css("a ~in class(b):\n  x: y\n", style=Minified),
    content="a .b{x:y}",
  )
}
```

## Hyphens

A hyphen is an operator in shrubbery, so identifiers use `_`:

```mbt check
///|
test "underscores become hyphens" {
  inspect(
    @shrubbery_css.to_css("a:\n  font_family: system_ui\n", style=Minified),
    content="a{font-family:system-ui}",
  )
}
```

A name that genuinely contains `_` has no bare spelling, so it is written
literally — and which call does it depends on where the name sits, because a
class, an element and a value are three different things:

```mbt check
///|
test "the literal escape, in each position it is needed" {
  let src =
    #|class("btn__primary"):
    #|  color: hex(fff)
    #|
    #|tag("side_bar"):
    #|  font_family: ident("side_bar")
  inspect(
    @shrubbery_css.to_css(src, style=Minified),
    content=".btn__primary{color:#fff}side_bar{font-family:side_bar}",
  )
}
```

Custom properties keep their dashes, since `--brand` is already a prefix
operator and a name.

## Both directions

CSS in, shrubbery out, and the loop closes: what comes back lowers to the same
tree it came from.

```mbt check
///|
test "CSS becomes shrubbery, and back again" {
  let shrub = @shrubbery_css.to_shrubbery(".card { display: grid }")
  inspect(
    shrub,
    content=(
      #|class(card):
      #|  display: grid
      #|
    ),
  )
  inspect(
    @shrubbery_css.to_css(shrub, style=Minified),
    content=".card{display:grid}",
  )
}
```

It is a normalisation rather than an inverse, and two things do not survive the
detour. A number loses its source spelling, because shrubbery's literal holds a
value and not a spelling -- `1.50` comes back as `1.5`, `+1` as `1`. And a CSS
comment becomes a line comment. Recovering either would mean reading the
shrubbery node's raw metadata, which the lowering deliberately never does; that
purity is what makes it total over hand-built trees.

## Diagnostics name the fix

A syntax nobody has seen before is worth diagnosing precisely, so where the
mistake is recognisable the message says what to type instead.

```mbt check
///|
test "a CSS habit is met with its replacement" {
  let l = @shrubbery_css.lower(".card:\n  a: b\n")
  inspect(l.diagnostics()[0].kind.code(), content="shrubcss::sigil_selector")
}
```

The one construct that parses cleanly and means the wrong thing is `a: hover`,
which is structurally a declaration of a property called `a`. It gets its own
diagnostic, guarded so that `cursor: default` stays quiet.

## Layout

| package | what |
|---|---|
| `names` | the tables: units, pseudo-classes, at-rules, relations, `_` ⇄ `-` |
| `kind`, `error` | diagnostics, and the one bridge to `error-report` |
| `lower` | shrubbery → a CSS tree |
| `emit` | a CSS tree → shrubbery |

## Licence

Apache-2.0.
