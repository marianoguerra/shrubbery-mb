#!/usr/bin/env bash
# The modularity claim, tested rather than asserted.
#
# A consumer that builds trees and prints them -- a code generator -- should not
# pay for the lexer or the parser. `test/embed` imports exactly what such a
# consumer would; this checks what the compiler actually links for it, by
# reading the `-i` flags off the real compile command rather than trusting the
# manifest.
#
# It is a real risk and not a hypothetical one: `write` reaching into `lexer`
# for one convenience -- a token kind, a character predicate -- would double
# what an embedder compiles, and nothing else in the suite would notice.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

line=$(moon check --dry-run --target native 2>/dev/null \
       | grep -E 'moonc check .*-pkg marianoguerra/shrubbery-dev/test/embed ' \
       | head -1)

if [ -z "$line" ]; then
  echo "embed-smoke: could not find the compile command for test/embed" >&2
  exit 1
fi

status=0
for forbidden in shrubbery/lexer shrubbery/parser shrubbery/column shrubbery/unicode; do
  if grep -q -- "$forbidden/" <<<"$line"; then
    echo "embed-smoke: an AST-and-printer consumer now links $forbidden" >&2
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "embed-smoke: the front end is not linked by an AST-and-printer consumer"
fi
exit "$status"
