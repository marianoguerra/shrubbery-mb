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
| `error-report/` | `marianoguerra/error-report` | a generic diagnostic library — data first, renderers second |
| `lib/` | `marianoguerra/shrubbery` | the notation: lexer, parser, AST, printers |
| `cli/` | `marianoguerra/shrubbery-cli` | the command-line tool |
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

## Status

Early. `error-report` is usable; the notation itself is being built.

## Licence

Apache-2.0.
