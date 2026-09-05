#!/usr/bin/env python3
"""The differential suite: what the port answers versus what the reference did.

Hermetic. `test/corpus/` and `test/golden/` are committed, so this runs with
neither Racket nor the reference checkout present -- which is what lets CI
check a pull request from someone who has set up neither.

    tools/shrubdiff.py tokens                  # every corpus file
    tools/shrubdiff.py tokens --filter rhm/li  # only paths containing that
    tools/shrubdiff.py tokens --show 3         # print the first 3 diffs

Goldens come in two forms and the reason is size. The `spec` and `tabs` buckets
carry the reference's full answer, because those are the files a person reads
when something breaks. The 610-file real-world bucket carries a digest only: the
full dumps are 26 MB of intermediate artifact, and a digest detects a divergence
just as well. When one does diverge, `just golden-for FILE` recreates the full
answer for that one file.
"""

import argparse
import hashlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "test" / "corpus"
GOLDEN = ROOT / "test" / "golden"
IMPL = ROOT / "_build/native/debug/build/marianoguerra/shrubbery-cli/shrubbery/shrubbery.exe"


def corpus_files(pattern):
    files = sorted(p for p in CORPUS.rglob("*.shrub"))
    if pattern:
        files = [p for p in files if pattern in str(p.relative_to(CORPUS))]
    return files


def read_index(name):
    """`sha1  relative/path` lines, hash by path."""
    out = {}
    path = GOLDEN / name
    if not path.exists():
        sys.exit(f"missing {path}; run `just goldens`")
    for line in path.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        digest, rel = line.split("  ", 1)
        out[rel] = digest
    return out


def run_impl(command, files):
    """One process for the whole batch, split on the `==== path` headers.

    Batched because there are 630 corpus files and process startup, paid per
    file on either side, is the difference between a gate people run and one
    they stop running.
    """
    if not IMPL.exists():
        sys.exit(f"missing {IMPL}; run `just build`")
    proc = subprocess.run(
        [str(IMPL), command] + [str(f) for f in files],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"{IMPL} failed:\n{proc.stderr}")
    sections = {}
    current = None
    lines = []
    for line in proc.stdout.splitlines():
        if line.startswith("==== "):
            if current is not None:
                sections[current] = "\n".join(lines) + ("\n" if lines else "")
            current = line[5:]
            lines = []
        else:
            lines.append(line)
    if current is not None:
        sections[current] = "\n".join(lines) + ("\n" if lines else "")
    return sections


def unified(want, got, rel, context=3):
    import difflib

    return "".join(
        difflib.unified_diff(
            want.splitlines(keepends=True),
            got.splitlines(keepends=True),
            fromfile=f"reference/{rel}",
            tofile=f"shrubbery-mb/{rel}",
            n=context,
        )
    )


def load_policy():
    """What each bucket is expected to achieve, as data rather than code.

    The expectations FLIP as the port grows -- `@` notation is unimplemented
    today, so most of the real-world bucket cannot match yet -- and a gate that
    fails on every run says nothing on the run where something actually breaks.
    So this is a ratchet: a bucket may not drop below its floor, and when it
    rises the floor is raised deliberately, in a commit whose diff says what
    improved.
    """
    import json

    path = ROOT / "test" / "oracle-policy.json"
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def bucket_of(rel):
    return rel.split("/", 1)[0]


def cmd_tokens(args):
    index = read_index("tokens.index")
    files = corpus_files(args.filter)
    if not files:
        sys.exit("no corpus files matched")
    sections = run_impl("tokens", files)

    passed, failures = 0, []
    for path in files:
        rel = str(path.relative_to(CORPUS))
        got = sections.get(str(path))
        if got is None:
            failures.append((rel, "no output from the port", None))
            continue
        want_digest = index.get(rel)
        if want_digest is None:
            failures.append((rel, "not in the golden index", None))
            continue
        got_digest = hashlib.sha1(got.encode()).hexdigest()
        if got_digest == want_digest:
            passed += 1
            continue
        full = GOLDEN / Path(rel).with_suffix(".tokens")
        detail = unified(full.read_text(), got, rel) if full.exists() else None
        failures.append((rel, "token streams differ", detail))

    print(f"tokens: {passed}/{len(files)} files agree with the reference")
    for i, (rel, why, detail) in enumerate(failures):
        if args.show and i < args.show:
            print(f"  FAIL {rel}: {why}")
            if detail:
                print("".join("    " + l for l in detail.splitlines(keepends=True)))
        elif args.verbose:
            print(f"  FAIL {rel}: {why}")

    if args.filter:
        # A filtered run is the inner loop, not a gate.
        return 1 if failures else 0

    floors = load_policy().get("tokens", {})
    if not floors:
        return 1 if failures else 0
    status = 0
    for bucket, floor in sorted(floors.items()):
        got = sum(1 for p in files
                  if bucket_of(str(p.relative_to(CORPUS))) == bucket
                  and str(p.relative_to(CORPUS)) not in {f[0] for f in failures})
        if got < floor:
            print(f"  REGRESSION {bucket}: {got} agree, floor is {floor}")
            status = 1
        elif got > floor:
            print(f"  IMPROVED {bucket}: {got} agree, floor is {floor} -- "
                  "raise it in test/oracle-policy.json")
            status = 1
    if status == 0:
        print("tokens: at the floor in every bucket")
    return status


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    t = sub.add_parser("tokens", help="compare token streams")
    t.add_argument("--filter", help="only paths containing this substring")
    t.add_argument("--show", type=int, default=1, help="print this many diffs")
    t.add_argument("--verbose", action="store_true", help="list every failing file")
    t.set_defaults(func=cmd_tokens)
    args = ap.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
