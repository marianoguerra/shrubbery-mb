# marianoguerra/shrubbery

[Shrubbery notation](https://docs.racket-lang.org/shrubbery/) for MoonBit: a
parser, a source-faithful printer, a reformatting pretty printer, and structured
diagnostics.

Shrubbery is the line- and indentation-sensitive notation layer under
[Rhombus](https://docs.racket-lang.org/rhombus/). It groups input without fully
parsing it — the rest is left to whatever language is built on top — so it is a
good foundation for anything that wants Rhombus-shaped syntax.

## Installing

```sh
moon add marianoguerra/shrubbery
```

A package is the unit of naming here, so import the façade for the calls and
the packages whose types you name:

```
import {
  "marianoguerra/shrubbery" @shrub,
  "marianoguerra/shrubbery/ast",
}
```

## Parsing

The tree is the reference's own representation: `multi`, `group`, `block`,
`alts`, `parens`, `brackets`, `braces`, `quotes`, operators and atoms.

```mbt check
///|
test {
  let parsed = @shrub.parse("def pi = 3.14\n")
  inspect(
    parsed.root().canonical(),
    content="(multi (group |def| |pi| (op |=|) #f64:40091eb851eb851f))",
  )
}
```

Blocks come from `:` and indentation, and alternatives from `|`:

```mbt check
///|
test {
  let parsed = @shrub.parse("if x\n| yes\n| no\n")
  inspect(
    parsed.root().canonical(),
    content="(multi (group |if| |x| (alts (block (group |yes|)) (block (group |no|)))))",
  )
}
```

## Every node remembers its source

Whitespace, comments, the `:` that opened a block, the `)` that closed a
parenthesis — all of it is attached to the tree, so the source rebuilds from it
exactly.

```mbt check
///|
test {
  let src =
    #|f(1, /* two */ 2):
    #|  body  // trailing
    #|
  let parsed = @shrub.parse(src)
  assert_eq(@shrub.to_source(parsed.root()), src)
}
```

That is what makes a formatter or a refactoring tool possible: you can rewrite
one node and print the rest back untouched.

## Printing

`write` re-formats from the tree, ignoring how it was written. The contract is
that reading the output back gives the same tree.

```mbt check
///|
test {
  let parsed = @shrub.parse("hello:\n  world\n  universe\n")
  // Line- and column-insensitive: safe to re-indent, wrap, or paste anywhere.
  inspect(@shrub.write(parsed.root()), content="hello:« world; universe »")
  // Or laid out to a width.
  inspect(
    @shrub.write(parsed.root(), style=Pretty, width=Some(0)),
    content=(
      #|hello:
      #|  world
      #|  universe
    ),
  )
}
```

`layout` gives you the document instead — every legal layout at once — for a
consumer with its own renderer.

## Errors are data

A failure is a `Diagnostic`: a closed `ErrorKind` with its parameters, a span,
and any related spans worth pointing at. Match on it, or hand it to the
formatter.

```mbt check
///|
test {
  let src = "hello:\n  world\n universe\n"
  let kind = try {
    let _ = @shrub.parse(src)
    None
  } catch {
    ShrubberyError(d) => Some(d.kind)
  }
  assert_true(kind is Some(WrongIndentation(_)))
}
```

`recover` collects them instead of raising, which is what an editor wants:

```mbt check
///|
test {
  let parsed = @shrub.parse("a:\n  b\n c\nd:\n  e\n f\n", recover=true)
  assert_eq(parsed.diagnostics().length(), 2)
}
```

And `to_report` renders one, through
[error-report](https://mooncakes.io/docs/marianoguerra/error-report):

```mbt check
///|
test {
  let src = "hello:\n  world\n universe\n"
  let sources = @report.Sources::new()
  let id = sources.add("greeting.shrub", src)
  let out = try {
    let _ = @shrub.parse(src)
    ""
  } catch {
    ShrubberyError(d) =>
      @render.render_string(@shrub.to_report(d, id), sources, {
        ..@render.default_config,
        theme: @style.mono_theme,
        color: Never,
      })
  }
  inspect(
    out,
    content=(
      #|error[shrubbery::wrong_indentation]: this group is not indented like the ones around it
      #|  ╭─[ greeting.shrub:3:2 ]
      #|  │
      #|2 │   world
      #|3 │  universe
      #|  │  ───┬────
      #|  │     ╰─ this column does not line up
      #|  │
      #|  ├─ help: every group in a sequence starts at the same column
      #|  ╰─
      #|
    ),
  )
}
```

## Tokens

For an editor or a highlighter that wants the scan rather than the tree. Every
code unit belongs to exactly one token's text, so the stream reassembles into
the source exactly.

```mbt check
///|
test {
  let toks = @shrub.tokens("x + y\n")
  inspect(toks.length(), content="7")
  let buf = StringBuilder()
  for t in toks {
    buf.write_string(t.text)
  }
  assert_eq(buf.to_string(), "x + y\n")
}
```

## Correctness

Every claim above is checked against the Racket reference implementation over a
696-file corpus — the reference's own test inputs, its 66 rejection cases, and
610 real Rhombus modules. Four oracles, all at 100%: the token stream, the parse
tree and the error message, the reproduced source, and re-formatted output in
all eleven layout modes the reference's own suite exercises.

## Licence

Apache-2.0.
