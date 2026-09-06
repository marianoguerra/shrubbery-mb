#!/usr/bin/env bash
# The modularity claim, tested rather than asserted.
#
# A consumer that builds trees and prints them -- a code generator, a template
# engine -- should not pay for the lexer or the parser. `test/embed` and
# `test/embed-html` import exactly what such a consumer would; this checks what
# the compiler actually links for each, by reading the `-i` flags off the real
# compile command rather than trusting the manifest.
#
# It is a real risk and not a hypothetical one: `write` reaching into `lexer`
# for one convenience -- a token kind, a character predicate -- would double
# what an embedder compiles, and nothing else in the suite would notice. The
# markup half has a second claim on top of that one: a page built in memory has
# nothing to diagnose, so it must not link `error-report` either.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

plan=$(moon check --dry-run --target native 2>/dev/null)
status=0

check() {
  local pkg="$1"
  local what="$2"
  shift 2
  local line
  line=$(grep -E "moonc check .*-pkg ${pkg} " <<<"$plan" | head -1)
  if [ -z "$line" ]; then
    echo "embed-smoke: could not find the compile command for ${pkg}" >&2
    status=1
    return
  fi
  local forbidden
  for forbidden in "$@"; do
    if grep -q -- "${forbidden}/" <<<"$line"; then
      echo "embed-smoke: ${what} now links ${forbidden}" >&2
      status=1
    fi
  done
}

check marianoguerra/shrubbery-dev/test/embed \
      "an AST-and-printer consumer" \
      shrubbery/lexer shrubbery/parser shrubbery/column shrubbery/unicode

check marianoguerra/shrubbery-dev/test/embed-html \
      "a markup-tree-and-printer consumer" \
      html/token html/parse html/error error-report

# The `-i` flags name a package's DIRECT imports, so the two checks above see
# what the embedder itself reaches for. The claim underneath -- that the tree
# and the printer have nothing behind them either -- has to be made of those
# packages directly, which is what these do.
check marianoguerra/html/ast \
      "the markup tree" \
      html/token html/parse html/error html/value error-report

check marianoguerra/html/write \
      "the markup printer" \
      html/token html/parse html/error html/value error-report

if [ "$status" -eq 0 ]; then
  echo "embed-smoke: the front end is not linked by an AST-and-printer consumer"
fi
exit "$status"
