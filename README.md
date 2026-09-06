# shrubbery-mb

[Shrubbery notation](https://docs.racket-lang.org/shrubbery/) for MoonBit: a
parser, a source-faithful printer, a reformatting pretty printer, and structured
diagnostics.

Shrubbery is the line- and indentation-sensitive notation layer under
[Rhombus](https://docs.racket-lang.org/rhombus/). It groups input without fully
parsing it, leaving the rest to a language built on top — so it is a good
foundation for anything that wants Rhombus-shaped syntax without Racket.

This is a port of the Racket reference implementation in
[racket/rhombus](https://github.com/racket/rhombus), and its correctness is
decided by a differential harness against that reference rather than by
inspection.

## Layout

| directory | module | what |
|---|---|---|
| `error-report/` | [`marianoguerra/error-report`](https://mooncakes.io/docs/marianoguerra/error-report) | a generic diagnostic library — data first, renderers second |
| `lib/` | [`marianoguerra/shrubbery`](https://mooncakes.io/docs/marianoguerra/shrubbery) | the notation: lexer, parser, AST, printers |
| `css/` | [`marianoguerra/css`](https://mooncakes.io/docs/marianoguerra/css) | a semantic CSS tree: tokenizer, tolerant parser, printer |
| `shrub-css/` | [`marianoguerra/shrubbery-css`](https://mooncakes.io/docs/marianoguerra/shrubbery-css) | the bridge: CSS written in shrubbery notation |
| `html/` | [`marianoguerra/html`](https://mooncakes.io/docs/marianoguerra/html) | a semantic markup tree -- HTML, SVG, MathML: tokenizer, tolerant parser, printer |
| `shrub-html/` | [`marianoguerra/shrubbery-html`](https://mooncakes.io/docs/marianoguerra/shrubbery-html) | the bridge: HTML written in shrubbery notation |
| `cli/` | [`marianoguerra/shrubbery-cli`](https://mooncakes.io/docs/marianoguerra/shrubbery-cli) | the command-line tool |
| `.` | `marianoguerra/shrubbery-dev` | corpus, goldens and the harness; never published |

`error-report/` is a guest: it has no dependencies, never names this project,
and is meant to be lifted into its own repository. See its
[README](error-report/README.mbt.md).

## Working on it

```sh
just            # list every task
just quick      # check, format, test, boundaries
just ci         # everything CI enforces
```

`AGENTS.md` is the guide for the details that are easy to get wrong.

## Correctness

### The notation

Four oracles, over a 696-file corpus — the reference's own test inputs, its 66
rejection cases, and 610 real Rhombus modules. All at 100%:

| oracle | claim |
|---|---|
| `tokens` | the token stream, with values and columns |
| `parse` | the parse tree, and the error message for a file that is rejected |
| `source` | the source rebuilt from the tree's metadata |
| `print` | re-formatted output, in all eleven layout modes |

The suite is hermetic: the corpus and the goldens are committed, so it runs with
neither Racket nor the reference checkout present.

### CSS and markup

Both are held to properties of their own, over their own committed corpora, with
a floor per bucket in `test/css-oracle-policy.json` and
`test/html-oracle-policy.json` that fails from both sides:

| oracle | claim | reference |
|---|---|---|
| `loop` | source → tree → shrubbery → tree → source is the source | itself |
| `roundtrip` | printing is a fixed point | itself |
| `lower` | the authored shrubbery corpus lowers with no diagnostic | itself |
| `survive` | nothing crashes, on anything | itself |
| `conform` | markup only: our output builds the same document the input does | [`moonbit-community/html`](https://mooncakes.io/docs/moonbit-community/html) |

`conform` is the only one with an outside opinion, and it is what makes the
markup module's central decision — a tree of what was *written*, not of what a
browser builds — checkable rather than merely argued. It is a MoonBit dependency
of the development module alone, so it needs no extra toolchain and the suite
stays hermetic.

`survive` is pointed at every corpus in the repository, not only its own: almost
none of the 696 notation files is CSS or markup, so both are free adversarial
input for the other two modules. On top of that, `test/css/prop` and
`test/html/prop` generate trees nobody wrote down and shrink the ones that fail.

## Installing

```sh
moon add marianoguerra/shrubbery       # the notation
moon add marianoguerra/shrubbery-cli   # the command-line tool
moon add marianoguerra/css             # a CSS tree
moon add marianoguerra/shrubbery-css   # CSS in the notation
moon add marianoguerra/html            # a markup tree: HTML, SVG, MathML
moon add marianoguerra/shrubbery-html  # HTML in the notation
```

## Status

Usable. Lexer, parser, raw-text metadata, both printers, `@` notation and
`#{}` escapes are done and checked against the reference. The DrRacket editor
services — the incremental colourer, indentation, navigation, armouring — are
not ported.

## Licence

Apache-2.0.
