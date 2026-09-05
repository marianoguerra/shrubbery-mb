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
    # Bytes, not text: `text=True` turns on universal newlines, which rewrites
    # a bare carriage return to a linefeed. Shrubbery treats a bare `\r` as a
    # line terminator, so it appears inside the very text being compared, and
    # the translation turns an exact reproduction into a difference.
    proc = subprocess.run(
        [str(IMPL), command] + [str(f) for f in files],
        capture_output=True,
    )
    if proc.returncode != 0:
        sys.exit(f"{IMPL} failed:\n{proc.stderr.decode()}")
    # Split on "\n" and nothing else. `splitlines` also breaks on a bare
    # carriage return, which shrubbery treats as a line terminator and which
    # therefore appears inside the very text being compared -- splitting there
    # silently deletes it and turns an exact reproduction into a difference.
    sections = {}
    current = None
    lines = []
    raw = proc.stdout.decode("utf-8")
    if raw.endswith("\n"):
        raw = raw[:-1]
    for line in raw.split("\n"):
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


def read_lex_failures():
    """Files the reference's own lexer aborts on.

    `lex-all` reports the first failure token and stops, so there is no token
    stream to compare -- by design, since those files exist to be rejected.
    They are skipped by the token oracle and covered by the parse oracle, whose
    golden records the error instead.
    """
    path = GOLDEN / "lex-failures.txt"
    if not path.exists():
        return set()
    return {line.split("\t", 1)[0] for line in path.read_text().splitlines() if line}


def compare(oracle, index_name, suffix, args, what, skip=frozenset()):
    index = read_index(index_name)
    files = corpus_files(args.filter)
    if not files:
        sys.exit("no corpus files matched")
    sections = run_impl(oracle, files)

    passed, failures, skipped = 0, [], 0
    for path in files:
        rel = str(path.relative_to(CORPUS))
        if rel in skip:
            skipped += 1
            continue
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
        full = GOLDEN / Path(rel).with_suffix(suffix)
        detail = unified(full.read_text(), got, rel) if full.exists() else None
        failures.append((rel, what, detail))
    return files, passed, failures, skipped


def cmd_source(args):
    """What we rebuild from the tree must equal what the REFERENCE rebuilds.

    Not what the input said. `shrubbery-syntax->string` re-prints a `#{...}`
    escape from the datum rather than from the source, so a multi-line escape
    comes back on one line and the reference does not reproduce such a file
    either. Comparing against the input would make that a failure of the port;
    comparing against the reference makes it what it is -- agreement.

    The count of files that come back byte-identical to the INPUT is reported
    alongside, because that is the number a consumer actually cares about.
    """
    index = read_index("source.index")
    files = corpus_files(args.filter)
    if not files:
        sys.exit("no corpus files matched")
    sections = run_impl("source", files)
    passed, failures, skipped, exact = 0, [], 0, 0
    for path in files:
        rel = str(path.relative_to(CORPUS))
        got = sections.get(str(path), "")
        if got.startswith("!error"):
            body = "!error\n"
        elif got.startswith("<<<<\n") and "\x00" in got:
            body = got[len("<<<<\n"):]
            body = body[: body.rindex("\x00")]
        else:
            failures.append((rel, "malformed output from the port", None))
            continue
        want_digest = index.get(rel)
        if want_digest is None:
            failures.append((rel, "not in the golden index", None))
            continue
        if body == path.read_text():
            exact += 1
        if hashlib.sha1(body.encode()).hexdigest() == want_digest:
            passed += 1
            continue
        full = GOLDEN / Path(rel).with_suffix(".source")
        detail = unified(full.read_text(), body, rel) if full.exists() else None
        failures.append((rel, "rebuilt source differs", detail))
    status = report("source", files, passed, failures, skipped, args)
    print(f"source: {exact}/{len(files)} come back byte-identical to the input")
    return status


def cmd_print(args):
    files, passed, failures, skipped = compare(
        "print", "print.index", ".print", args, "printed output differs"
    )
    return report("print", files, passed, failures, skipped, args)


def cmd_parse(args):
    files, passed, failures, skipped = compare(
        "parse", "parse.index", ".sexp", args, "parse trees differ"
    )
    return report("parse", files, passed, failures, skipped, args)


def cmd_tokens(args):
    skip = read_lex_failures()
    files, passed, failures, skipped = compare(
        "tokens", "tokens.index", ".tokens", args, "token streams differ", skip=skip
    )
    return report("tokens", files, passed, failures, skipped, args)


def report(oracle, files, passed, failures, skipped, args):
    total = len(files) - skipped
    tail = f" ({skipped} the reference cannot lex)" if skipped else ""
    print(f"{oracle}: {passed}/{total} files agree with the reference{tail}")
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

    floors = load_policy().get(oracle, {})
    if not floors:
        return 1 if failures else 0
    skip = read_lex_failures() if oracle == "tokens" else frozenset()
    skipped_paths = skip
    status = 0
    for bucket, floor in sorted(floors.items()):
        failed_paths = {f[0] for f in failures}
        got = sum(1 for p in files
                  if bucket_of(str(p.relative_to(CORPUS))) == bucket
                  and str(p.relative_to(CORPUS)) not in failed_paths
                  and str(p.relative_to(CORPUS)) not in skipped_paths)
        if got < floor:
            print(f"  REGRESSION {bucket}: {got} agree, floor is {floor}")
            status = 1
        elif got > floor:
            print(f"  IMPROVED {bucket}: {got} agree, floor is {floor} -- "
                  "raise it in test/oracle-policy.json")
            status = 1
    if status == 0:
        print(f"{oracle}: at the floor in every bucket")
    return status


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    for name, fn, help_text in (
        ("tokens", cmd_tokens, "compare token streams"),
        ("parse", cmd_parse, "compare parse trees, and the errors for files that are rejected"),
        ("source", cmd_source, "compare the source rebuilt from the tree against the reference's"),
        ("print", cmd_print, "compare re-formatted output in all eleven layout modes"),
    ):
        sp = sub.add_parser(name, help=help_text)
        sp.add_argument("--filter", help="only paths containing this substring")
        sp.add_argument("--show", type=int, default=1, help="print this many diffs")
        sp.add_argument("--verbose", action="store_true", help="list every failing file")
        sp.set_defaults(func=fn)
    args = ap.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
