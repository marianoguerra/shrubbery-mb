# shrubbery-mb — the tasks this project is developed, tested and shipped with.
#
# `just` with no arguments lists everything, grouped. Each recipe is the real
# command, so this file doubles as the index of what can be done here and as the
# place those commands are kept honest.
#
# Two properties of this project decide how the recipes below are split up:
#
#   * The differential suite is HERMETIC. `test/corpus/` and `test/golden/` are
#     committed, so everything in the `diff` group runs with neither Racket nor
#     the `reference/` checkout present. Recipes that DO need them are grouped
#     separately and each says so.
#   * Regenerating a committed artifact -- the goldens, the corpus, the Unicode
#     tables -- is a deliberate act whose diff is the review artifact. Those are
#     in `regen`, and none of them runs in CI.
#
# Note on the listing: `just --list` shows the LAST comment line above a recipe,
# so that line is always the one-line summary and any explanation sits above it.

# The differential harness, and the built binary it drives.
diff := justfile_directory() / "tools/shrubdiff.py"
impl := justfile_directory() / "_build/native/debug/build/marianoguerra/shrubbery-cli/shrubbery/shrubbery.exe"

# Where the read-only Racket reference lives. Never a build or CI input.
reference := justfile_directory() / "reference"
# `shrubbery-lib` declares `collection 'multi`, so putting the checkout on the
# collection path is enough -- nothing is installed into Racket.
rkt := "PLTCOLLECTS=" + reference + "/shrubbery-lib:"

# List every task, grouped.
default:
    @just --list --unsorted

# ---------------------------------------------------------------------------
# Everyday development
# ---------------------------------------------------------------------------

# Type-check everything, warnings fatal (what CI gates on).
[group('dev')]
check:
    moon check --deny-warn

# Native is the fastest backend to build; `test-all` is the four-backend run
# CI does.
#
# Run the unit tests (native).
[group('dev')]
test:
    moon test --target native

# Run the unit tests on every backend: wasm, wasm-gc, js, native.
[group('dev')]
test-all:
    moon test --target all

# Run one package's tests, e.g. `just test-pkg error-report/render`.
[group('dev')]
test-pkg pkg:
    moon test -p marianoguerra/{{pkg}} --target native

# Accept new snapshot output (`inspect` blocks).
[group('dev')]
test-update:
    moon test --target native -u

# Format every source file (generated files opt out in their `moon.pkg`).
[group('dev')]
fmt:
    moon fmt

# A diff in a `.mbti` is a public-API change and wants reviewing as one.
#
# Regenerate the committed `pkg.generated.mbti` files.
[group('dev')]
interfaces:
    moon info --target all

# Build the native executables.
[group('dev')]
build:
    moon build --target native

# Drop build outputs.
[group('dev')]
clean:
    moon clean

# Refresh the package registry index (CI does this before building).
[group('dev')]
update:
    moon update

# ---------------------------------------------------------------------------
# The gates
# ---------------------------------------------------------------------------

# `error-report` is built here but is meant to leave. This asserts it imports
# nothing but core and its siblings, and that it never names its consumer --
# both of which erode quietly, which is why they are a gate and not a note.
#
# Check that error-report is still spin-out ready.
[group('gates')]
boundary-check:
    tools/boundary-check.sh

# A consumer that builds trees and prints them -- a code generator -- should not
# pay for the lexer or the parser. This reads the `-i` flags off the real
# compile command rather than trusting the manifest.
#
# Check that an AST-and-printer consumer does not link the front end.
[group('gates')]
embed-smoke:
    tools/embed-smoke.sh

# The only coverage of the BINARY's behaviour rather than the library's: exit
# codes, flag handling, which stream things land on. No oracle runs the binary,
# so none of them would notice `--width` being ignored.
#
# Run the CLI's own tests.
[group('gates')]
cli-test: build
    tools/cli-test.sh

# ---------------------------------------------------------------- html

# Unit tests for the HTML module only -- the inner loop while working on it.
[group('html')]
html-test:
    moon test -p marianoguerra/html --target native

# The table it writes is committed, so the suite stays hermetic and CI needs
# no network. Regenerating is a deliberate act and the diff is the review.
#
# Regenerate the named character reference table from the WHATWG list.
[group('html')]
entities-regen:
    curl -fsSL https://html.spec.whatwg.org/entities.json -o /tmp/entities.json
    {{justfile_directory()}}/tools/gen-entities.py /tmp/entities.json {{justfile_directory()}}/html/names/entities.mbt
    moon fmt

# ---------------------------------------------------------------- css

# Unit tests for the CSS module only -- the inner loop while working on it.
[group('css')]
css-test:
    moon test -p marianoguerra/css --target native

# Unit tests for the shrubbery-to-CSS bridge only.
[group('css')]
bridge-test:
    moon test -p marianoguerra/shrubbery-css --target native

# Every CSS oracle over the committed corpus, held to the ratchet.
[group('css')]
css-diff *args: build
    {{justfile_directory()}}/tools/cssdiff.py {{args}} --show 0

# One CSS oracle, with the failing files shown -- the inner loop, not a gate.
[group('css')]
css-only oracle: build
    {{justfile_directory()}}/tools/cssdiff.py {{oracle}} --no-ratchet --show 5

# The generated properties and the fuzzer. Seeded, so a failure is reproducible.
[group('css')]
css-prop:
    moon test -p marianoguerra/shrubbery-dev/test/css/prop --target native

# Check, format, unit tests, boundaries -- run before committing.
[group('gates')]
quick: check fmt test boundary-check embed-smoke diff css-diff cli-test

# Mirrors .github/workflows/check.yml, including the two `git diff --exit-code`
# steps -- which is how a stale `.mbti` or an unformatted file is caught.
#
# Everything CI enforces, in CI's order.
[group('gates')]
ci:
    moon check --deny-warn
    moon info --target all
    git diff --exit-code
    moon fmt
    git diff --exit-code
    moon test --target all
    tools/boundary-check.sh
    tools/embed-smoke.sh
    moon build --target native
    tools/shrubdiff.py tokens --show 0
    tools/shrubdiff.py parse --show 0
    tools/shrubdiff.py source --show 0
    tools/shrubdiff.py print --show 0
    tools/cssdiff.py --show 0
    tools/cli-test.sh

# ---------------------------------------------------------------------------
# The differential suite -- the project's real correctness gate
# ---------------------------------------------------------------------------
#
# Hermetic: `test/corpus/` and `test/golden/` are committed, so everything here
# runs with neither Racket nor the reference checkout present.

# Compare our token stream against the reference's, over the whole corpus.
[group('diff')]
diff-tokens *args: build
    {{diff}} tokens --show 0 {{args}}

# The inner loop when something is failing:
#
#     just diff-only spec/input5
#
# Run both oracles over only the files whose path contains PATTERN.
[group('diff')]
diff-only pattern: build
    {{diff}} tokens --filter {{pattern}} --show 3
    {{diff}} parse --filter {{pattern}} --show 3
    {{diff}} source --filter {{pattern}} --show 3
    {{diff}} print --filter {{pattern}} --show 3

# The inner loop when the port rejects something the reference accepts.
#
# Parse a file and show whatever goes wrong, with the source.
[group('diff')]
explain file: build
    {{impl}} check {{file}}

# Separates a LAYOUT disagreement -- the renderer chose differently -- from a
# CONSTRUCTION one, where the two documents were never the same to begin with.
#
# Dump the layout document for a file, to compare with the reference's.
[group('diff')]
doc style file: build
    {{impl}} doc {{style}} {{file}}

# One comparison rather than two: a file the reference rejects has its error
# message as its golden, so accepting such a file is a failure HERE rather than
# a silence in one oracle and a pass in another.
#
# Compare our parse trees, and our errors, against the reference's.
[group('diff')]
diff-parse *args: build
    {{diff}} parse --show 0 {{args}}

# The strongest single claim in the suite: what we rebuild from the tree is
# what the REFERENCE rebuilds from its own. Not what the input said --
# `shrubbery-syntax->string` re-prints a `#{...}` escape from the datum, so a
# multi-line escape comes back on one line and the reference does not reproduce
# such a file either.
#
# Compare the source rebuilt from the tree against the reference's.
[group('diff')]
diff-source *args: build
    {{diff}} source --show 0 {{args}}

# All eleven layout modes the reference's own suite exercises, byte for byte.
# The strongest claim about the printer, and the one that says the layout
# ALGORITHM agrees and not merely the output on the easy cases.
#
# Compare re-formatted output against the reference's.
[group('diff')]
diff-print *args: build
    {{diff}} print --show 0 {{args}}

# Everything hermetic that gates.
[group('diff')]
diff: diff-tokens diff-parse diff-source diff-print

# ---------------------------------------------------------------------------
# Regenerating committed artifacts (needs Racket; never in CI)
# ---------------------------------------------------------------------------
#
# Each of these rewrites a committed file from the reference's own answers. The
# resulting diff IS the review artifact: it shows exactly what upstream, or
# Racket's Unicode version, changed. Never edit the outputs by hand.

# Sweeps `char-alphabetic?` and friends over the whole code-point space and
# expands the reference's own emoji table, then writes the boundary probes that
# test the lookup rather than the data.
#
# Regenerate the Unicode tables and their parity test.
[group('regen')]
unicode-regen:
    racket tools/gen-unicode-tables.rkt
    racket tools/gen-unicode-tests.rkt

# The 612 .rhm files in the reference tree contain no tabs, so nothing in the
# corpus exercises the partial order. These probes are that coverage.
#
# Regenerate the column parity test.
[group('regen')]
column-regen:
    racket tools/gen-column-tests.rkt

# Copies the corpus out of the reference checkout: the 12 inputs from its own
# test suite, 610 real .rhm modules with their `#lang` lines stripped, and the
# hand-written tab cases that nothing in the real corpus reaches.
#
# Rebuild test/corpus from the reference.
[group('regen')]
corpus:
    racket tools/collect-corpus.rkt

# Full goldens for the buckets a person reads, a digest for the 610-file
# real-world bucket -- the full dumps are 26 MB of intermediate artifact and a
# digest detects a divergence just as well.
#
# Rebuild test/golden from the reference.
[group('regen')]
goldens:
    racket tools/oracle/collect-goldens.rkt

# The real-world bucket carries digests only, so this is how you see what a
# divergence there actually is.
#
# Recreate the reference's full answer for ONE file, for reading.
[group('regen')]
golden-for file:
    racket tools/oracle/tokens.rkt {{file}}

# Every generated artifact, then check nothing moved.
[group('regen')]
regen-all: unicode-regen column-regen
    moon fmt
    git diff --stat

# ---------------------------------------------------------------------------
# The reference (needs Racket; never in CI)
# ---------------------------------------------------------------------------

# The acceptance test for the reference checkout: if this fails, every oracle
# below is meaningless.
#
# `reference/` is gitignored read-only material. It is used for exactly two
# things -- as the source this port is written from, and as the input to
# `corpus` and `goldens` -- and is never a build or CI input.
#
# Restore the reference checkout at the pinned commit.
[group('reference')]
reference-fetch:
    tools/fetch-reference.sh

# Prove the reference implementation loads and its own suite passes.
[group('reference')]
reference-check:
    {{rkt}} racket -e '(require shrubbery/parse) (displayln "shrubbery/parse: ok")'
    {{rkt}} racket {{reference}}/shrubbery/shrubbery/tests/parse.rkt

# Parse one file with the REFERENCE and print its S-expression. The inner loop
# when our answer and theirs disagree and you want to see theirs.
#
# Ask the reference what a file parses to.
[group('reference')]
oracle-parse file:
    {{rkt}} racket -e '(require shrubbery/parse racket/pretty) \
        (pretty-write (syntax->datum (call-with-input-file "{{file}}" parse-all)))'

# ---------------------------------------------------------------------------
# Publishing to mooncakes
# ---------------------------------------------------------------------------
#
# Three modules go out; the root one never does. `tools/publish.sh` is what
# makes that structural rather than a habit -- it can only address the three
# names, and it walks them in dependency order.

# `lib` and `cli` report "pending" until their dependencies exist in the
# registry: `moon publish` verifies the packaged zip against the registry, and
# on a first release the dependency is not there yet.
#
# Show what would go to mooncakes, without sending it.
[group('publish')]
publish-dry:
    tools/publish.sh --dry-run

# A published version cannot be withdrawn, so the full gate runs first.
#
# Publish every module, in dependency order.
[group('publish')]
publish: ci
    tools/publish.sh

# For a follow-up release of one module, e.g. `just publish-one lib`.
[group('publish')]
publish-one module: ci
    tools/publish.sh {{module}}
