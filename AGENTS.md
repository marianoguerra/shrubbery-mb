# Agent guide

This is a [MoonBit](https://docs.moonbitlang.com) project: an implementation of
**Shrubbery notation** — the bicameral surface-syntax layer under
[Rhombus](https://docs.racket-lang.org/rhombus/) — ported from the Racket
reference in [racket/rhombus](https://github.com/racket/rhombus).

The specification is <https://docs.racket-lang.org/shrubbery/spec.html>.

## Four modules in one workspace

`moon.work` lists them. Every `moon` command below runs at the repository root
and covers all four.

| directory | module | published |
|---|---|---|
| `error-report/` | `marianoguerra/error-report` | yes — **and it has no dependencies**; keep it that way |
| `lib/` | `marianoguerra/shrubbery` | yes; only `error-report` and `kawaz/grapheme` |
| `cli/` | `marianoguerra/shrubbery-cli` | yes; `moonbitlang/x` lives here |
| `.` (root) | `marianoguerra/shrubbery-dev` | no: `test/`, `tools/` |

Two rules follow from the split, and both are load-bearing:

- **A module's dependencies are fetched by every consumer** regardless of which
  packages they import, so one convenience dependency in `lib/moon.mod` is paid
  for by a project that wanted only the parser. Adding one is a design decision,
  not a manifest edit.
- **`shrubbery-dev` reaches the other three through their public API only.** That
  is what keeps the API honest — whatever the harness needs is, by construction,
  a name that has to stay public.

## `error-report` is a guest

It is built here because this project needed it, and it is written to be lifted
out into its own repository unchanged. Two things must stay true, and both erode
quietly:

1. It imports nothing but `moonbitlang/core` and its own siblings.
2. It never names the consumer it was extracted for.

`tools/boundary-check.sh` gates both, and CI runs it. If you find yourself
wanting to reach into `error-report` for one shrubbery-shaped convenience, that
is the moment the rule is doing its job — put the adapter on the shrubbery side
instead. There is to be exactly **one** function that connects the two, and it
lives in `lib/error`.

## The reference checkout

`reference/` is gitignored — a read-only clone of `racket/rhombus`, pinned at
`cefc758d`. **Never edit it**, and never let it become a build or CI input.

Nothing is installed into Racket: `shrubbery-lib/info.rkt` declares
`collection 'multi`, so putting the checkout on `PLTCOLLECTS` is enough. That is
what `just reference-check` and `just oracle-parse` do.

The Racket needed is Ubuntu's `racket` 8.18 or newer — verified, not assumed:
`shrubbery-lib` declares `base >= 8.8.0.5`, `syntax-color-lib` and
`parser-tools-lib`, all in the full distribution, and its only version-sensitive
API is `string-grapheme-span` (Racket 8.5).

## Non-negotiable: the reference is the specification

This port is only worth having if it is *provably* equivalent to the reference.
Correctness is not decided by reading the Racket and agreeing the MoonBit looks
similar — it is decided by a differential harness that runs both over a corpus
and compares parse trees, raw-text metadata, error messages and printed output.

If you change front-end behaviour, run the harness. Do not "fix" a golden file
to make a test pass; a golden diff means either you changed behaviour or
upstream did, and both need explaining.

## The suite is hermetic; keep it that way

`test/corpus/` and `test/golden/` are **committed**. That is what lets the
differential suite run with neither Racket nor `reference/` present — CI needs
only this repository. Regenerating them is a deliberate act, and the resulting
diff is the point: it shows exactly what changed.

## Conventions

- Config is the **new DSL**, not JSON: `moon.work`, `moon.mod`, `moon.pkg`. Deps
  go in an `import { ... }` block, with a separate `import { ... } for "test"`
  block for test-only deps (and `for "wbtest"` for white-box tests). `moon fmt`
  reformats these files too and strips comments from `moon.work` — put the
  explanation in this document instead.
- `///|` before every top-level item.
- `_test.mbt` = black-box, `_wbtest.mbt` = white-box.
- `pkg.generated.mbti` is committed for every package; CI enforces that it is
  current. A diff there is a public-API change.
- `README.mbt.md` is compiled as a doctest, so every example in it is verified.
- Generated sources opt out of the formatter: `formatter(ignore: [...])`.
- Prefer `assert_eq` for stable results and `inspect` snapshots for structured
  output; update snapshots with `moon test -u`.

## Porting notes that are easy to get wrong

- **Columns are not integers.** A tab advances to a stop that depends on what
  came before it, so two columns reached through different tab/space mixes are
  only *partially* ordered. `private/column.rkt` stores the run list
  rightmost-first and its comparator has a fourth answer, `Incomparable`, which
  is the user-facing "incomparable indentation due to mixed tabs" error and not
  a comparison failure to default to `Eq`. There is also a `+0.5` convention: a
  `|` at column N takes part in comparisons as N.5.
- **Column advance is per extended grapheme cluster** (UAX #29), not per code
  point. Racket uses `string-grapheme-span`. The segmenter is a dependency and
  is gated by `lib/unicode/parity_test.mbt`, which compares against Racket's own
  `string-grapheme-count`. That gate has already rejected one candidate package
  for splitting Hangul L+V+T into three clusters and CRLF into two.
- **Two things are called "column".** The port position Racket reports
  (`port-next-location`, in code points, what `raw-srcloc` carries and what the
  oracle compares) and the indentation column above. Conflating them is the
  first bug this port would ship.
- **Two lexer states** differing only in the number pattern — `initial` reads
  `+2` as a signed literal, `continuing` (after an identifier, literal, closer
  or keyword) reads it as `+` applied to `2`. That single bit is what makes
  `1+2` addition and `1 +2` two terms.
- **Identifiers admit emoji sequences**, including ZWJ sequences, and
  single-codepoint emoji are *excluded* from operator characters.
- **Raw-text metadata is nine properties** whose field order is emission order.
  A bug in the final `normalize_group_raw` pass breaks round-tripping without
  breaking parsing, and often without changing the concatenation either — which
  is why it is checked node by node against the reference and not only by byte
  equality of the whole file.
- **Numeric literals stay raw strings** through the front end. Parsing them
  early would break round-tripping.
