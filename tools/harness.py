#!/usr/bin/env python3.14
"""Shootout test harness (stdlib only).

    harness.py <path-to-mj> corpus/*.txt [--show N] [--time] [--op OP] [--timeout S]

Corpus format (spec/formats.md): a request line followed by its expected response
prefixed with "= ". Lines starting with '#' and blank lines are ignored.

All requests from all files are fed to one `mj` process (mixed ops, in file order),
unless --time is given: then each op gets its own process and the harness reports
requests/second per op, plus the start-up time of an empty run.

Responses are compared as key=value sets (key order insensitive, values compared as
strings). The first response token must equal the request id. Exit status is 0 only
if every case passes.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from collections import OrderedDict, defaultdict


class Case:
    __slots__ = ("file", "line", "request", "expected", "rid", "op")

    def __init__(self, file, line, request, expected):
        self.file = file
        self.line = line
        self.request = request
        self.expected = expected
        toks = request.split(" ")
        self.rid = toks[0]
        self.op = toks[1] if len(toks) > 1 else "?"


def load(path: str) -> list[Case]:
    cases = []
    pending = None
    with open(path, encoding="utf-8") as f:
        for n, raw in enumerate(f, 1):
            line = raw.rstrip("\r\n")
            if not line.strip() or line.startswith("#"):
                continue
            if line.startswith("= "):
                if pending is None:
                    sys.exit(f"{path}:{n}: expected line without a request")
                cases.append(Case(path, pending[0], pending[1], line[2:]))
                pending = None
            else:
                if pending is not None:
                    sys.exit(f"{path}:{pending[0]}: request without an expected line")
                pending = (n, line)
    if pending is not None:
        sys.exit(f"{path}:{pending[0]}: request without an expected line")
    return cases


def parse_resp(line: str):
    """-> (id, dict) or raises ValueError."""
    toks = line.split(" ")
    d = {}
    for t in toks[1:]:
        if "=" not in t:
            raise ValueError(f"token without '=': {t!r}")
        k, v = t.split("=", 1)
        if k in d:
            raise ValueError(f"duplicate key {k!r}")
        d[k] = v
    return toks[0], d


def run_mj(mj: str, cases: list[Case], timeout: float):
    data = "".join(c.request + "\n" for c in cases)
    t0 = time.perf_counter()
    try:
        p = subprocess.run([mj], input=data, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, f"timed out after {timeout}s", time.perf_counter() - t0
    except OSError as e:
        return None, f"could not run {mj}: {e}", 0.0
    dt = time.perf_counter() - t0
    problem = None
    if p.returncode != 0:
        problem = f"exit status {p.returncode}"
        tail = p.stderr.strip().splitlines()[-5:]
        if tail:
            problem += "; stderr tail:\n    " + "\n    ".join(tail)
    lines = p.stdout.splitlines()
    return lines, problem, dt


def diff_text(exp: dict, got: dict) -> str:
    parts = []
    for k in sorted(set(exp) | set(got)):
        e, g = exp.get(k), got.get(k)
        if e != g:
            parts.append(f"{k}: expected {e if e is not None else '(absent)'}, got {g if g is not None else '(absent)'}")
    return "; ".join(parts)


def check(cases: list[Case], lines: list[str] | None):
    """-> list of (case, reason or None)."""
    results = []
    for i, c in enumerate(cases):
        if lines is None or i >= len(lines):
            results.append((c, "no response"))
            continue
        got_line = lines[i]
        try:
            gid, got = parse_resp(got_line)
        except ValueError as e:
            results.append((c, f"unparseable response {got_line!r}: {e}"))
            continue
        eid, exp = parse_resp(c.expected)
        if gid != c.rid:
            results.append((c, f"response id {gid!r} != request id {c.rid!r} (responses out of step?)"))
            continue
        if got != exp:
            results.append((c, diff_text(exp, got) + f"\n      got line: {got_line}"))
            continue
        results.append((c, None))
    return results


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mj")
    ap.add_argument("files", nargs="+")
    ap.add_argument("--show", type=int, default=10, help="print the first N failures (default 10)")
    ap.add_argument("--time", action="store_true", help="one process per op; report requests/second")
    ap.add_argument("--op", action="append", help="only run cases for this op (repeatable)")
    ap.add_argument("--timeout", type=float, default=600.0, help="seconds per mj process (default 600)")
    args = ap.parse_args()

    mj = os.path.abspath(args.mj) if os.path.exists(args.mj) else args.mj  # else PATH lookup

    cases: list[Case] = []
    for f in args.files:
        cases.extend(load(f))
    if args.op:
        cases = [c for c in cases if c.op in set(args.op)]
    if not cases:
        print("no cases")
        return 1

    problems = []
    timing = OrderedDict()
    results = []
    if args.time:
        by_op = OrderedDict()
        for c in cases:
            by_op.setdefault(c.op, []).append(c)
        _, prob, startup = run_mj(mj, [], args.timeout)
        if prob:
            problems.append(f"empty run: {prob}")
        for op, cs in by_op.items():
            lines, prob, dt = run_mj(mj, cs, args.timeout)
            if prob:
                problems.append(f"op {op}: {prob}")
            if lines is not None and len(lines) != len(cs):
                problems.append(f"op {op}: {len(lines)} response lines for {len(cs)} requests")
            timing[op] = (len(cs), dt)
            results.extend(check(cs, lines))
    else:
        lines, prob, dt = run_mj(mj, cases, args.timeout)
        if prob:
            problems.append(prob)
        if lines is not None and len(lines) != len(cases):
            problems.append(f"{len(lines)} response lines for {len(cases)} requests")
        results = check(cases, lines)

    counts = defaultdict(lambda: [0, 0])
    fails = []
    for c, reason in results:
        counts[c.op][0 if reason is None else 1] += 1
        if reason is not None:
            fails.append((c, reason))

    for c, reason in fails[: args.show]:
        print(f"FAIL {c.file}:{c.line}")
        print(f"   request:  {c.request}")
        print(f"   expected: {c.expected}")
        print(f"   diff:     {reason}")
    if len(fails) > args.show:
        print(f"... {len(fails) - args.show} more failures not shown (--show N)")
    for p in problems:
        print(f"PROBLEM: {p}")

    print()
    print(f"{'op':<10}{'pass':>8}{'fail':>8}")
    tp = tf = 0
    for op in sorted(counts):
        p, f = counts[op]
        tp += p
        tf += f
        print(f"{op:<10}{p:>8}{f:>8}")
    print(f"{'total':<10}{tp:>8}{tf:>8}")

    if args.time:
        print()
        print(f"start-up (empty input): {startup * 1000:.1f} ms")
        print(f"{'op':<10}{'requests':>10}{'seconds':>10}{'req/s':>12}{'req/s excl. start-up':>24}")
        for op, (n, dt) in timing.items():
            rps = n / dt if dt > 0 else float("inf")
            net = dt - startup
            rps2 = n / net if net > 0 else float("inf")
            print(f"{op:<10}{n:>10}{dt:>10.3f}{rps:>12.1f}{rps2:>24.1f}")

    return 0 if tf == 0 and not problems else 1


if __name__ == "__main__":
    sys.exit(main())
