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
#
# The second rule here is about a different boundary with the same shape.
# `moonbit-community/html` is a conforming WHATWG parser and the reference the
# `conform` oracle asks. A published module that imported it would stop being
# answerable TO it and start being built ON it, which is the difference between
# a library that is checked and a library that is a wrapper -- and it would put
# an entire tree builder in the dependency set of everyone who wanted a
# formatter. It belongs to the development module and nowhere else.
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

# The name check. Two exemptions, both narrow:
#
#   * `.mbti` files are generated and name the module itself.
#   * `moon.mod`'s `repository` line, which says where the source is HOSTED
#     today. That is a packaging fact, not a dependency: this module shares a
#     repository with its first consumer until it is spun out, and the spin-out
#     changes that one line. Everything else a human writes is in scope.
if grep -rniE 'shrubbery|rhombus|\bcss\b' "$mod" \
     --include='*.mbt' --include='*.md' --include='moon.pkg' --include='moon.mod' \
     | grep -v 'pkg.generated.mbti' \
     | grep -vE '^[^:]*moon\.mod:[0-9]+:repository = ' >&2; then
  echo "boundary: error-report mentions the consumer it was extracted for" >&2
  status=1
fi

# The reference is a dev dependency. A published module may not name it.
for published in lib css html shrub-css shrub-html cli error-report; do
  if grep -rn 'moonbit-community/html' "$root/$published" \
       --include='moon.pkg' --include='moon.mod' --include='*.mbt' >&2; then
    echo "boundary: $published names the conformance reference" >&2
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "boundary: error-report is self-contained, and the reference is dev-only"
fi
exit "$status"
