#!/usr/bin/env python3
"""Run the markup oracles over the corpus, and hold them to a ratchet.

This is the markup half of what ``tools/cssdiff.py`` does for CSS and
``tools/shrubdiff.py`` for the notation, and it is deliberately the same shape:
one binary process for a whole bucket, output split on ``==== path`` headers,
and a floor per bucket that fails in BOTH directions.  Dropping below a floor is
a regression; rising above one is an improvement that has to be recorded in a
commit whose diff says what got better.

There is no external reference here.  ``shrubdiff.py`` compares against Racket;
this compares the library against *itself*, which is what makes it hermetic:

  loop       markup -> tree -> shrubbery -> tree -> markup must equal markup ->
             tree -> markup, modulo the three things the notation cannot say.
             The headline property, and the only one that exercises both
             directions of the bridge at once.
  roundtrip  printing is a fixed point: print, reparse, print again, compare.
  lower      the authored Shrubbery HTML corpus lowers with no diagnostic.
  survive    nothing crashes, on any input, including the deliberately broken
             bucket, the 696 shrubbery files that are not markup at all, and
             the CSS corpus.

The last one costs nothing and catches the most: ``test/corpus`` and
``test/css/corpus`` are already in the repository for other suites, and almost
none of either is markup -- so they are a free adversarial corpus for both the
parser and the lowering.
"""

import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORACLE = os.path.join(
    ROOT,
    "_build/native/debug/build/marianoguerra/shrubbery-dev/tools/oracle-html/oracle-html.exe",
)
CORPUS = os.path.join(ROOT, "test/html/corpus")
POLICY = os.path.join(ROOT, "test/html-oracle-policy.json")
SHRUB_CORPUS = os.path.join(ROOT, "test/corpus")
CSS_CORPUS = os.path.join(ROOT, "test/css/corpus")

# Which buckets each oracle is answerable for.
#
# `loop` includes `broken`, which the CSS harness's equivalent excludes. It can:
# the comparison normalises away everything the notation is known to be unable
# to express, so a recovery that survives the detour is a real claim rather than
# a lucky one -- and a recovery that does not is a bug in the bridge.
MARKUP_BUCKETS = ["ok", "broken", "foreign"]


def files(bucket, ext=".html"):
    d = os.path.join(CORPUS, bucket)
    if not os.path.isdir(d):
        return []
    return sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(ext))


def tree_files(root, limit=None):
    """Every regular file under a directory, for the adversarial buckets."""
    out = []
    for dirpath, _, names in os.walk(root):
        for n in sorted(names):
            if n.endswith(".json") or n.endswith(".md"):
                continue
            out.append(os.path.join(dirpath, n))
    out.sort()
    return out[:limit] if limit else out


def run(command, paths):
    """One process for the whole batch, split back into per-file answers.

    Read as bytes and decode once, splitting on "\\n" alone: a bare "\\r" is
    data in a markup file, and `splitlines()` would treat it as a line ending
    and silently reshape the answer.
    """
    if not paths:
        return {}
    out, path, buf = {}, None, []
    # Argument lists have a limit, and the notation corpus is 696 files.
    for chunk in [paths[i : i + 200] for i in range(0, len(paths), 200)]:
        proc = subprocess.run([ORACLE, command] + chunk, capture_output=True)
        text = proc.stdout.decode("utf-8", errors="replace")
        for line in text.split("\n"):
            if line.startswith("==== "):
                if path is not None:
                    out[path] = "\n".join(buf)
                path = line[5:]
                buf = []
            else:
                buf.append(line)
        if path is not None:
            out[path] = "\n".join(buf)
            path, buf = None, []
    return out


def indent(text):
    return "\n".join("    " + line for line in text.strip().split("\n"))


def report(results, bucket, paths, answers, ok_of, show):
    passed = sum(1 for a in answers.values() if ok_of(a))
    results[bucket] = (passed, len(paths))
    shown = 0
    for p, a in sorted(answers.items()):
        if not ok_of(a) and shown < show:
            print("  {}\n{}".format(os.path.basename(p), indent(a)))
            shown += 1


def oracle_loop(show):
    """Markup the short way and the long way round must be the same markup."""
    results = {}
    for bucket in MARKUP_BUCKETS:
        paths = files(bucket)
        report(
            results,
            bucket,
            paths,
            run("loop", paths),
            lambda a: "loop: closed" in a,
            show,
        )
    return results


def oracle_roundtrip(show):
    """Printing is a fixed point, in every mode."""
    results = {}
    for bucket in MARKUP_BUCKETS:
        paths = files(bucket)
        report(
            results,
            bucket,
            paths,
            run("roundtrip", paths),
            lambda a: "NOT STABLE" not in a and "!error" not in a,
            show,
        )
    return results


def oracle_lower(show):
    """The authored corpus lowers with nothing to complain about."""
    paths = files("shrub", ".shrubhtml")
    results = {}
    report(
        results,
        "shrub",
        paths,
        run("lower", paths),
        # A line STARTING with `!`, not a `!` anywhere: the answer is markup,
        # and `<!DOCTYPE html>` is not a diagnostic.
        lambda a: not any(l.startswith("!") for l in a.split("\n")),
        show,
    )
    return results


def oracle_survive(show):
    """Nothing crashes, on anything."""
    results = {}
    for bucket in MARKUP_BUCKETS + ["shrub"]:
        ext = ".shrubhtml" if bucket == "shrub" else ".html"
        paths = files(bucket, ext)
        report(
            results,
            bucket,
            paths,
            run("survive", paths),
            lambda a: "survive: ok" in a,
            show,
        )
    for name, root in (("notation", SHRUB_CORPUS), ("css", CSS_CORPUS)):
        paths = tree_files(root)
        report(
            results,
            name,
            paths,
            run("survive", paths),
            lambda a: "survive: ok" in a,
            show,
        )
    return results


ORACLES = {
    "loop": oracle_loop,
    "roundtrip": oracle_roundtrip,
    "lower": oracle_lower,
    "survive": oracle_survive,
}


def load_policy():
    with open(POLICY, encoding="utf-8") as f:
        return json.load(f)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "oracle", nargs="?", default="all", choices=list(ORACLES) + ["all"]
    )
    ap.add_argument("--show", type=int, default=3, help="failing files to print")
    ap.add_argument(
        "--no-ratchet",
        action="store_true",
        help="report the numbers without holding them to the policy",
    )
    args = ap.parse_args()

    if not os.path.exists(ORACLE):
        print("htmldiff: build first: moon build --target native", file=sys.stderr)
        return 2

    policy = load_policy()
    names = list(ORACLES) if args.oracle == "all" else [args.oracle]
    status = 0
    for name in names:
        print("=== {}".format(name))
        results = ORACLES[name](args.show)
        floors = policy.get(name, {})
        for bucket in sorted(results):
            passed, total = results[bucket]
            floor = floors.get(bucket)
            mark = ""
            if not args.no_ratchet and floor is not None:
                if passed < floor:
                    mark = "  REGRESSION (floor {})".format(floor)
                    status = 1
                elif passed > floor:
                    mark = "  IMPROVED (floor {}); record it".format(floor)
                    status = 1
            print("  {:10} {:5}/{:<5}{}".format(bucket, passed, total, mark))
            if not args.no_ratchet and floor is None:
                print("  {:10} no floor in the policy".format(bucket))
                status = 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
