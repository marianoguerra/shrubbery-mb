#!/usr/bin/env bash
# Restore the reference checkout at the pinned commit.
#
# `reference/` is gitignored, read-only material, used for exactly two things:
# as the source this port is written from, and as the input to `just corpus`
# and `just goldens`. It is NEVER a build or CI input -- the moment it becomes
# one, the hermetic property of the test suite is gone.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
pin=tools/reference.json

want=$(python3 -c "import json;print(json.load(open('$pin'))['upstream_commit'])")
url=$(python3 -c "import json;print(json.load(open('$pin'))['upstream'])")
want_racket=$(python3 -c "import json;print(json.load(open('$pin'))['racket_version'])")

have_racket=$(racket -e '(display (version))' 2>/dev/null || echo "none")
if [ "$have_racket" != "$want_racket" ]; then
  echo "reference: Racket is $have_racket, the pin says $want_racket." >&2
  echo "  The oracle's answers depend on it -- its Unicode tables are where the" >&2
  echo "  generated character tables come from. Regenerate them and review the" >&2
  echo "  diff before trusting the suite, or install the pinned version." >&2
fi

if [ ! -d reference/.git ]; then
  echo "reference: cloning $url"
  git clone --quiet "$url" reference
fi

cd reference
have=$(git rev-parse HEAD)
if [ "$have" = "$want" ]; then
  echo "reference: at $want"
  exit 0
fi
echo "reference: moving from $have to $want"
git fetch --quiet origin
git checkout --quiet "$want"
echo "reference: at $want"
echo ""
echo "The pin moved. `just corpus` and `just goldens` need re-running, and the"
echo "diff they produce is what says what upstream changed."
