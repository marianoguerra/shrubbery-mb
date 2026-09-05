#!/usr/bin/env bash
# `error-report` is built here but is meant to be lifted out into its own
# repository unchanged. Two things have to stay true for that to be a
# `git filter-repo` rather than an untangling, and both erode quietly:
#
#   1. It imports nothing but `moonbitlang/core` and its own siblings.
#   2. It never learns the word "shrubbery".
#
# The pressure will be to reach into it for one shrubbery-shaped convenience.
# This makes that a CI failure rather than a discovery at spin-out time.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mod="$root/error-report"
status=0

while IFS= read -r pkg; do
  # Every quoted import path in the file, comments stripped.
  while IFS= read -r dep; do
    case "$dep" in
      moonbitlang/core*|marianoguerra/error-report*) ;;
      *)
        echo "boundary: ${pkg#"$root/"} imports '$dep'" >&2
        status=1
        ;;
    esac
  # A dependency path always has a slash; `for "test"` does not.
  done < <(sed 's://.*::' "$pkg" | grep -o '"[^"]*/[^"]*"' | tr -d '"')
done < <(find "$mod" -name moon.pkg)

# `moon.mod` must have no `import` block at all.
if grep -qE '^[[:space:]]*import[[:space:]]*\{' "$mod/moon.mod"; then
  echo "boundary: error-report/moon.mod declares a dependency" >&2
  status=1
fi

# The name check. `.mbti` files are generated and name the module itself, so
# they are excluded; everything a human writes is in scope.
if grep -rniE 'shrubbery|rhombus' "$mod" \
     --include='*.mbt' --include='*.md' --include='moon.pkg' --include='moon.mod' \
     | grep -v 'pkg.generated.mbti' >&2; then
  echo "boundary: error-report mentions the consumer it was extracted for" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "boundary: error-report is self-contained"
fi
exit "$status"
