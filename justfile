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

# Check, format, unit tests, boundaries -- run before committing.
[group('gates')]
quick: check fmt test boundary-check

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

# ---------------------------------------------------------------------------
# The reference (needs Racket; never in CI)
# ---------------------------------------------------------------------------

# The acceptance test for the reference checkout: if this fails, every oracle
# below is meaningless.
#
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
