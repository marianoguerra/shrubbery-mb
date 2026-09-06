#!/usr/bin/env python3
"""Run the CSS oracles over the corpus, and hold them to a ratchet.

This is the CSS half of what ``tools/shrubdiff.py`` does for the notation, and
it is deliberately the same shape: one binary process for a whole bucket, output
split on ``==== path`` headers, and a floor per bucket that fails in BOTH
directions.  Dropping below a floor is a regression; rising above one is an
improvement that has to be recorded in a commit whose diff says what got better.

There is no external reference here.  ``shrubdiff.py`` compares against Racket;
this compares the library against *itself*, which is what makes it hermetic:

  loop       CSS -> tree -> shrubbery -> tree -> CSS must equal CSS -> tree ->
             CSS.  The headline property, and the only one that exercises both
             directions of the bridge at once.
  roundtrip  printing is a fixed point: print, reparse, print again, compare.
  lower      the authored shrubbery corpus lowers with no error diagnostic.
  survive    nothing crashes, on any input, including the deliberately broken
             bucket and the 696 shrubbery files that are not CSS at all.

The last one costs nothing and catches the most: ``test/corpus`` is already in
the repository for the notation's own suite, and almost none of it is valid
Shrubbery CSS, so it is a free adversarial corpus for the lowering.
"""

import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORACLE = os.path.join(
    ROOT,
    "_build/native/debug/build/marianoguerra/shrubbery-dev/tools/oracle-css/oracle-css.exe",
)
CORPUS = os.path.join(ROOT, "test/css/corpus")
POLICY = os.path.join(ROOT, "test/css-oracle-policy.json")
SHRUB_CORPUS = os.path.join(ROOT, "test/corpus")

# Which buckets each oracle is answerable for.
#
# `loop` deliberately excludes `biome-error`: those files are invalid CSS, the
# parser recovers from them, and a recovery is not required to survive a round
# trip through a different syntax.  Asking it to would be measuring the wrong
# thing, and would make the floor meaningless.
LOOP_BUCKETS = ["biome-ok", "prettier", "vendor"]
ALL_CSS_BUCKETS = ["biome-ok", "biome-error", "prettier", "vendor"]


def files(bucket, ext=".css"):
    d = os.path.join(CORPUS, bucket)
    if not os.path.isdir(d):
        return []
    return sorted(
        os.path.join(d, f) for f in os.listdir(d) if f.endswith(ext)
    )


def run(command, paths):
    """One process for the whole batch, split back into per-file answers.

    Read as bytes and decode once, splitting on "\\n" alone: a bare "\\r" is
    data in a CSS file, and `splitlines()` would treat it as a line ending and
    silently reshape the answer.
    """
    if not paths:
        return {}
    proc = subprocess.run([ORACLE, command] + paths, capture_output=True)
    text = proc.stdout.decode("utf-8", errors="replace")
    out, path, buf = {}, None, []
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
    return out


def oracle_loop(show):
    """CSS the short way and the long way round must be the same CSS."""
    results = {}
    for bucket in LOOP_BUCKETS:
        paths = files(bucket)
        answers = run("loop", paths)
        closed = sum(1 for a in answers.values() if "loop: closed" in a)
        results[bucket] = (closed, len(paths))
        shown = 0
        for p, a in sorted(answers.items()):
            if "loop: closed" not in a and shown < show:
                print("  {}\n{}".format(os.path.basename(p), indent(a)))
                shown += 1
    return results


def oracle_roundtrip(show):
    """Printing is a fixed point, in every mode."""
    results = {}
    for bucket in ALL_CSS_BUCKETS:
        paths = files(bucket)
        answers = run("roundtrip", paths)
        ok = sum(
            1
            for a in answers.values()
            if "NOT STABLE" not in a and "!error" not in a
        )
        results[bucket] = (ok, len(paths))
        shown = 0
        for p, a in sorted(answers.items()):
            if ("NOT STABLE" in a or "!error" in a) and shown < show:
                print("  {}\n{}".format(os.path.basename(p), indent(a)))
                shown += 1
    return results


def oracle_lower(show):
    """The authored shrubbery corpus lowers cleanly."""
    paths = files("shrub", ".shrubcss")
    answers = run("lower", paths)
    ok = sum(1 for a in answers.values() if "!" not in a.split("\n")[0])
    shown = 0
    for p, a in sorted(answers.items()):
        first = a.split("\n")[0]
        if first.startswith("!") and shown < show:
            print("  {}\n{}".format(os.path.basename(p), indent(a)))
            shown += 1
    return {"shrub": (ok, len(paths))}


def oracle_survive(show):
    """Nothing crashes, on anything.

    The shrubbery corpus is the interesting half: 696 files that are valid
    notation and almost never valid Shrubbery CSS, so nearly every one exercises
    a path the authored corpus never reaches.
    """
    del show
    results = {}
    for bucket in ALL_CSS_BUCKETS:
        paths = files(bucket)
        answers = run("print", paths)
        results[bucket] = (len(answers), len(paths))
    shrub_paths = sorted(
        os.path.join(dirpath, f)
        for dirpath, _, fs in os.walk(SHRUB_CORPUS)
        for f in fs
        if f.endswith(".shrub")
    )
    answers = run("lower", shrub_paths)
    results["notation"] = (len(answers), len(shrub_paths))
    return results


def indent(text):
    return "\n".join("      " + line for line in text.split("\n") if line)


ORACLES = {
    "loop": oracle_loop,
    "roundtrip": oracle_roundtrip,
    "lower": oracle_lower,
    "survive": oracle_survive,
}


def load_policy():
    if not os.path.exists(POLICY):
        return {}
    with open(POLICY, "rb") as f:
        return json.loads(f.read().decode("utf-8"))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("oracle", nargs="?", default="all", choices=list(ORACLES) + ["all"])
    ap.add_argument("--show", type=int, default=3, help="failing files to print")
    ap.add_argument(
        "--no-ratchet",
        action="store_true",
        help="report without holding to the floors (the inner loop, not a gate)",
    )
    args = ap.parse_args()

    if not os.path.exists(ORACLE):
        print("cssdiff: build first -- `just build`", file=sys.stderr)
        return 2

    names = list(ORACLES) if args.oracle == "all" else [args.oracle]
    policy = load_policy()
    status = 0
    for name in names:
        results = ORACLES[name](args.show)
        floors = policy.get(name, {})
        for bucket, (got, total) in sorted(results.items()):
            print("{}: {} {}/{}".format(name, bucket, got, total))
            if args.no_ratchet:
                continue
            floor = floors.get(bucket)
            if floor is None:
                print(
                    "  NO FLOOR for {}.{} -- add one to {}".format(
                        name, bucket, os.path.relpath(POLICY, ROOT)
                    )
                )
                status = 1
            elif got < floor:
                print("  REGRESSION {}.{}: {} < floor {}".format(name, bucket, got, floor))
                status = 1
            elif got > floor:
                print(
                    "  IMPROVED {}.{}: {} > floor {} -- raise it in {}".format(
                        name, bucket, got, floor, os.path.relpath(POLICY, ROOT)
                    )
                )
                status = 1
    if status == 0 and not args.no_ratchet:
        print("css: at the floor in every bucket")
    return status


if __name__ == "__main__":
    sys.exit(main())
