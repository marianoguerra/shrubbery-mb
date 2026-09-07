#!/usr/bin/env bash
# Publish the published modules to mooncakes, in dependency order.
#
# Two things this exists to make impossible:
#
#   1. Publishing the ROOT module. `moon.mod` has no `private` field, so a bare
#      `moon publish` at the repository root would upload the corpus, the
#      goldens and the porting tools as `marianoguerra/shrubbery-dev`. This
#      script can only address the names below.
#   2. Publishing out of order. `shrubbery` declares `error-report@0.1.0` and
#      `shrubbery-cli` declares both, and the registry rejects a module whose
#      dependency it has never seen. The order below is the dependency order.
#
# It also reads the dry run's RESULT rather than its exit code: `moon publish
# --dry-run` reports "202 Accepted ... Dry run completed successfully" and then
# exits 255 regardless, so an exit-code check would call every dry run a
# failure.
#
# usage: tools/publish.sh [--dry-run] [module ...]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

dry=0
if [ "${1-}" = "--dry-run" ]; then
  dry=1
  shift
fi

# Dependency order. Not alphabetical, and not a set: `error-report` must exist
# in the registry before `shrubbery` can name it, and `css`/`html` before the
# two `shrub-*` bridges that lower shrubbery into them.
all=(error-report lib css html shrub-css shrub-html cli)

if [ "$#" -gt 0 ]; then
  for m in "$@"; do
    case " ${all[*]} " in
      *" $m "*) ;;
      *)
        echo "publish: '$m' is not a published module (one of: ${all[*]})" >&2
        exit 2
        ;;
    esac
  done
  # Keep the declared order whatever order the arguments came in.
  selected=()
  for m in "${all[@]}"; do
    case " $* " in *" $m "*) selected+=("$m") ;; esac
  done
else
  selected=("${all[@]}")
fi

status=0
for m in "${selected[@]}"; do
  name="$(sed -n 's/^name = "\(.*\)"$/\1/p' "$root/$m/moon.mod")"
  version="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$root/$m/moon.mod")"
  if [ "$dry" -eq 1 ]; then
    echo "=== dry run: $name@$version ($m/) ==="
    log="$(mktemp)"
    # The exit code is not the answer here; the server's reply is.
    moon -C "$root/$m" publish --dry-run >"$log" 2>&1 || true
    if grep -q 'Dry run completed successfully' "$log"; then
      echo "publish: $name@$version would publish"
    elif grep -q 'is duplicated with an existing version' "$log"; then
      # Not a failure either: this version is already on mooncakes. A release
      # that only moves some of the modules forward leaves the rest here, and
      # the point of the dry run is to see which ones those are.
      echo "publish: $name@$version already published"
    elif grep -qE 'module was not found in the registry|no version satisfies requirement' "$log"; then
      # Not a failure: `moon publish` verifies the packaged zip by resolving it
      # against the REGISTRY, and a module of ours that has not been published
      # yet is not there. This resolves itself as the loop walks the order.
      #
      # Two spellings, and the second is easy to miss. A module nobody has ever
      # published is "not found"; a module that is up there at an OLDER version
      # than this release needs is "no version satisfies requirement", which is
      # the same pending situation and used to be reported as a failure -- so a
      # release that bumped a dependency looked broken until it was published.
      missing="$(grep -o "Failed to resolve registry dependency \`[^\`]*\`" "$log" \
                 | sed 's/.*`\(.*\)`/\1/' | sort -u | tr '\n' ' ')"
      echo "publish: $name@$version pending -- waits on: ${missing% }"
    else
      echo "publish: $name@$version FAILED" >&2
      cat "$log" >&2
      status=1
    fi
    rm -f "$log"
  else
    echo "=== publishing: $name@$version ($m/) ==="
    log="$(mktemp)"
    if moon -C "$root/$m" publish >"$log" 2>&1; then
      cat "$log"
      # The next module in the order declares this one. Without refreshing the
      # index, its own publish would verify against a registry that has never
      # heard of what was just uploaded.
      moon update
    elif grep -q 'is duplicated with an existing version' "$log"; then
      # Not a failure, and the same reading the dry run gives it. A release that
      # moves only SOME of the modules forward -- which is every release after
      # the first -- leaves the rest at versions already on mooncakes, and the
      # registry answers 409 for each. Aborting on the first one made the whole
      # script usable exactly once.
      echo "publish: $name@$version already published"
    else
      cat "$log" >&2
      rm -f "$log"
      echo "publish: $name@$version FAILED" >&2
      exit 1
    fi
    rm -f "$log"
  fi
done

exit "$status"
