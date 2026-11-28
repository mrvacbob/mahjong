#!/usr/bin/env python3.14
"""Shootout test harness (stdlib only).

    harness.py <path-to-mj> Corpus/*.txt [--show N] [--time] [--op OP] [--timeout S] [--stall S]

Corpus format (Spec/formats.md): a request line followed by its expected response
prefixed with "= ". Lines starting with '#' and blank lines are ignored.

All requests from all files are fed to one `mj` process (mixed ops, in file order),
unless --time is given: then each op gets its own process and the harness reports
requests/second per op, plus the start-up time of an empty run.

If `mj` exits early, or sends no line for --stall seconds, the first unanswered case
is retried alone in a fresh process; if it fails alone too it is recorded as failed
(the others are not). The run then restarts with the next case. Responses are matched
to requests by id, in order, so a missing line fails only its own case.

Responses are compared as key=value sets (key order insensitive, values compared as
strings). The first response token must equal the request id. Exit status is 0 only
if every case passes.
"""

from __future__ import annotations

import argparse
import os
import queue
import subprocess
import sys
import threading
import time
from collections import OrderedDict, defaultdict, deque


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


class NoAnswer:
    """Stands in for a response line when `mj` died or stalled on this case."""

    __slots__ = ("reason",)

    def __init__(self, reason: str):
        self.reason = reason


def run_batch(mj: str, cases: list[Case], timeout: float, stall: float):
    """Feed `cases` to one fresh `mj` process.

    -> (response lines received in order, problem or None, seconds). Stops early when
    the process exits before answering every request, or when no new line arrives for
    `stall` seconds (or the `timeout` for the whole batch runs out); the process is then
    killed. The lines received so far are kept."""
    t0 = time.perf_counter()
    try:
        p = subprocess.Popen([mj], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, encoding="utf-8", errors="replace", bufsize=1 << 16)
    except OSError as e:
        return [], f"could not run {mj}: {e}", 0.0
    data = "".join(c.request + "\n" for c in cases)
    q: queue.Queue = queue.Queue()
    err_tail: deque = deque(maxlen=5)

    def writer():
        try:
            p.stdin.write(data)
        except (BrokenPipeError, OSError, ValueError):
            pass
        finally:
            try:
                p.stdin.close()
            except (BrokenPipeError, OSError, ValueError):
                pass

    def reader():
        for line in p.stdout:
            q.put(line.rstrip("\r\n"))
        q.put(None)

    def err_reader():
        for line in p.stderr:
            err_tail.append(line.rstrip("\r\n"))

    threads = [threading.Thread(target=f, daemon=True) for f in (writer, reader, err_reader)]
    for t in threads:
        t.start()
    deadline = t0 + timeout
    lines: list[str] = []
    problem = None
    eof = False

    def kill():
        try:
            p.kill()
        except OSError:
            pass
        p.wait()

    while len(lines) < len(cases):
        left = deadline - time.perf_counter()
        if left <= 0:
            problem = f"timed out after {timeout}s"
            kill()
            break
        try:
            item = q.get(timeout=min(stall, left))
        except queue.Empty:
            problem = (f"no response for {stall}s" if left > stall else f"timed out after {timeout}s")
            kill()
            break
        if item is None:
            eof = True
            break
        lines.append(item)
    if problem is None:
        try:
            p.wait(timeout=max(0.1, min(stall, deadline - time.perf_counter())))
        except subprocess.TimeoutExpired:
            problem = "did not exit at end of input"
            kill()
    dt = time.perf_counter() - t0
    for t in threads[1:]:
        t.join(timeout=1.0)
    extra = 0
    if not eof:
        while True:
            try:
                item = q.get_nowait()
            except queue.Empty:
                break
            if item is None:
                break
            extra += 1
    if problem is None and len(lines) < len(cases):
        problem = f"exited after {len(lines)} of {len(cases)} responses"
    if problem is None and extra:
        problem = f"{extra} response lines more than requests"
    if p.returncode not in (0, None) and problem is None:
        problem = f"exit status {p.returncode}"
    elif p.returncode not in (0, None, -9):
        problem += f" (exit status {p.returncode})"
    if problem and err_tail:
        problem += "; stderr tail:\n    " + "\n    ".join(err_tail)
    return lines, problem, dt


def align(cases: list[Case], lines: list[str]):
    """Match response lines to cases by id, in order. -> ({case index: line}, number of
    cases covered). A line whose id belongs to a later case skips the cases between
    (they get no response); a line with an id matching no later case is taken as the
    answer to the next case, so the id mismatch shows up as a failure there."""
    where: dict[str, list[int]] = {}
    for j, c in enumerate(cases):
        where.setdefault(c.rid, []).append(j)
    got: dict[int, str] = {}
    j = 0
    for line in lines:
        if j >= len(cases):
            break
        lid = line.split(" ", 1)[0]
        later = [t for t in where.get(lid, ()) if t >= j]
        t = later[0] if later else j
        got[t] = line
        j = t + 1
    return got, j


def run_mj(mj: str, cases: list[Case], timeout: float, stall: float):
    """Run every case, restarting `mj` after a crash or stall.

    -> (one entry per case: a response line, NoAnswer, or None for a case the process
    skipped; problems; seconds). When the process stops early, the first unanswered
    case is run again on its own in a fresh process (so output lost in a buffer is not
    blamed on the wrong case); if it fails alone too it is recorded as failed. Either
    way the run then restarts with the case after it."""
    out: list = [None] * len(cases)
    problems: list[str] = []
    total = 0.0
    i = 0
    while i < len(cases):
        lines, prob, dt = run_batch(mj, cases[i:], timeout, stall)
        total += dt
        got, covered = align(cases[i:], lines)
        for j, line in got.items():
            out[i + j] = line
        k = i + covered
        if k >= len(cases) or prob is None:
            if prob:
                problems.append(prob)
            elif k < len(cases):
                problems.append(f"{len(lines)} response lines for {len(cases) - i} requests")
            break
        if not lines and prob.startswith("could not run"):
            problems.append(prob)
            for j in range(i, len(cases)):
                out[j] = NoAnswer(prob)
            break
        c = cases[k]
        alone, prob1, dt1 = run_batch(mj, [c], timeout, stall)
        total += dt1
        if alone:
            out[k] = alone[0]
            problems.append(f"{prob} (case {c.rid} answered when run alone; restarted after it)")
        else:
            out[k] = NoAnswer(prob1 or prob)
            problems.append(f"case {c.rid} ({c.file}:{c.line}): {prob1 or prob}; restarted after it")
        i = k + 1
    return out, problems, total


def diff_text(exp: dict, got: dict) -> str:
    parts = []
    for k in sorted(set(exp) | set(got)):
        e, g = exp.get(k), got.get(k)
        if e != g:
            parts.append(f"{k}: expected {e if e is not None else '(absent)'}, got {g if g is not None else '(absent)'}")
    return "; ".join(parts)


def check(cases: list[Case], lines: list):
    """-> list of (case, reason or None). `lines` has one entry per case (see run_mj)."""
    results = []
    for i, c in enumerate(cases):
        got_line = lines[i] if lines is not None and i < len(lines) else None
        if isinstance(got_line, NoAnswer):
            results.append((c, f"no response: {got_line.reason}"))
            continue
        if got_line is None:
            results.append((c, "no response"))
            continue
        try:
            gid, got = parse_resp(got_line)
        except ValueError as e:
            results.append((c, f"unparseable response {got_line!r}: {e}"))
            continue
        eid, exp = parse_resp(c.expected)
        if gid != c.rid:
            results.append((c, f"response id {gid!r} != request id {c.rid!r}"))
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
    ap.add_argument("--stall", type=float, default=60.0,
                    help="restart mj if no response line arrives for this many seconds (default 60)")
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
        _, prob, startup = run_batch(mj, [], args.timeout, args.stall)
        if prob:
            problems.append(f"empty run: {prob}")
        for op, cs in by_op.items():
            lines, probs, dt = run_mj(mj, cs, args.timeout, args.stall)
            problems.extend(f"op {op}: {p}" for p in probs)
            timing[op] = (len(cs), dt)
            results.extend(check(cs, lines))
    else:
        lines, probs, dt = run_mj(mj, cases, args.timeout, args.stall)
        problems.extend(probs)
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
