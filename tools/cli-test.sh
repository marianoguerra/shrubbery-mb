#!/usr/bin/env bash
# The CLI's own behaviour: exit codes, flag handling, which stream things land
# on. The library's behaviour is covered by the oracles and by `moon test`;
# none of them runs the binary, so none of them would notice `--width` being
# ignored or `check` exiting 0 on a broken file.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
IMPL=_build/native/debug/build/marianoguerra/shrubbery-cli/shrubbery/shrubbery.exe
[ -x "$IMPL" ] || { echo "cli-test: run 'just build' first" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf 'hello:\n  world\n  universe\n' > "$work/ok.shrub"
printf 'a:\n  b\n c\nd:\n  e\n f\n' > "$work/bad.shrub"

fails=0
check() { # name expected-exit expected-output command...
  local name=$1 want_code=$2 want=$3; shift 3
  local got; got=$("$@" 2>&1); local code=$?
  if [ "$code" != "$want_code" ]; then
    echo "FAIL $name: exit $code, wanted $want_code" >&2; fails=$((fails+1)); return
  fi
  if [ "$got" != "$want" ]; then
    echo "FAIL $name:" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/  /' >&2
    fails=$((fails+1))
  fi
}

check "fmt default is pretty" 0 \
  'hello: world; universe' \
  "$IMPL" fmt "$work/ok.shrub"

check "fmt --style flat" 0 \
  'hello:« world; universe »' \
  "$IMPL" fmt --style flat "$work/ok.shrub"

check "fmt --width 0 breaks everything" 0 \
  'hello:
  world
  universe' \
  "$IMPL" fmt --width 0 "$work/ok.shrub"

check "check on a good file says nothing and exits 0" 0 '' \
  "$IMPL" check --color never "$work/ok.shrub"

# Recovery is the point: a file with two mistakes reports two.
check "check reports every problem, not just the first" 1 \
  "$work/bad.shrub:3:2: error[shrubbery::wrong_indentation]: this group is not indented like the ones around it
$work/bad.shrub:6:2: error[shrubbery::wrong_indentation]: this group is not indented like the ones around it" \
  "$IMPL" check --error-format short --color never "$work/bad.shrub"

check "an unknown flag value is a usage error" 2 \
  "shrubbery: --style needs flat, pretty, armoured or multiline" \
  "$IMPL" fmt --style sideways "$work/ok.shrub"

check "an unknown command is a usage error" 2 \
  "shrubbery: unknown command 'wibble'
$($IMPL help)" \
  "$IMPL" wibble

# `--write` rewrites in place, and only when the text actually changes.
cp "$work/ok.shrub" "$work/w.shrub"
"$IMPL" fmt --write --style flat "$work/w.shrub" >/dev/null
if [ "$(cat "$work/w.shrub")" != 'hello:« world; universe »' ]; then
  echo "FAIL fmt --write did not rewrite the file" >&2; fails=$((fails+1))
fi

# A file that does not parse is reported and LEFT ALONE. Reformatting something
# you could not read is how a formatter loses someone's work.
cp "$work/bad.shrub" "$work/b2.shrub"
"$IMPL" fmt --write "$work/b2.shrub" >/dev/null
if ! cmp -s "$work/bad.shrub" "$work/b2.shrub"; then
  echo "FAIL fmt --write touched a file that does not parse" >&2; fails=$((fails+1))
fi

if [ "$fails" -eq 0 ]; then
  echo "cli-test: all cases pass"
else
  echo "cli-test: $fails case(s) failed" >&2
fi
exit $(( fails > 0 ))
