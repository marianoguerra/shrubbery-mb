# shrubbery-cli

The `shrubbery` command: read, check and re-format
[Shrubbery notation](https://docs.racket-lang.org/shrubbery/).

```sh
moon add marianoguerra/shrubbery-cli
```

## Checking

```sh
shrubbery check src/*.shrub
```

Reports every problem in each file, not just the first, with the source shown
and a caret under the column that is wrong. Exits 1 if anything was reported.

```
error[shrubbery::wrong_indentation]: this group is not indented like the ones around it
  ╭─[ greeting.shrub:3:2 ]
  │
2 │   world
3 │  universe
  │  ───┬────
  │     ╰─ this column does not line up
  │
  ├─ help: every group in a sequence starts at the same column
  ╰─
```

`--error-format short` gives one line per problem, in the shape editors and
`grep` already understand; `--error-format json` gives one JSON object per line.
`--color always|never|auto` decides the escapes.

## Re-formatting

```sh
shrubbery fmt --width 80 --write src/*.shrub
```

Four styles, and the difference between them is what carries the grouping:

| `--style` | grouping is carried by |
|---|---|
| `flat` | `«»`, `;` and `,` only — one line, and re-indenting it cannot change what it says |
| `pretty` | line breaks where they help, `«»` where they are needed (the default) |
| `armoured` | `«»` everywhere, but laid out over lines |
| `multiline` | line breaks in preference to `«»` |

`--width N` applies to everything but `flat`; omit it and no line is broken that
could be one. `--write` rewrites in place. A file that does not parse is
reported and **left alone**.

## The rest

`tokens`, `parse`, `source`, `print` and `doc` exist to drive the differential
test suite against the Racket reference implementation. Their output formats are
shared with the harness rather than chosen for looks, and `print` and `doc` are
the tools for working out whether a formatting difference is a layout decision
or a construction one.

## Licence

Apache-2.0.
