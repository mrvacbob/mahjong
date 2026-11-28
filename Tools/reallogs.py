#!/usr/bin/env python3.14
"""Bulk `mj check-log` over tar shards of `.mjai.json.zst` games.

Reads each tar as a stream, decompresses every member (stdlib `compression.zstd`),
and feeds the games to parallel `mj check-log --stdin --json` workers. Writes, per
shard, `OUT/<shard>.summary.json` (games, hands, throughput, differences by
category, named conventions, unchecked counts, hands per situation tag) and
`OUT/<shard>.games.jsonl` (one line per game that has a difference, a convention or
a rare tag). Keep OUT outside the repository: these are third-party records.

  python3.14 Tools/reallogs.py --mj ./mj --rules tenhou --out DIR [-j N]
      [--set field=value]... [--limit N] [--only NAMES] [--tag-suffix S] [--all-games] TAR...
  python3.14 Tools/reallogs.py --report DIR...     # merge summaries into one table

`--only NAMES` checks just the games listed (one name per line, as in games.jsonl),
for re-running candidate games under another `--set`. `--all-games` writes a line for
every game. Games named like Tenhou records (`...gm-...`) in a Mahjong Soul shard are
counted as `tenhou_named_games` (the 2025 Throne shard holds Tenhou 2024 games).
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import subprocess
import sys
import tarfile
import threading
import time
from compression import zstd

# Tags too common to keep a per-game line for.
COMMON = {"ron", "tsumo", "exhaustive", "declined_tsumo", "declined_tsumo_discard", "declined_tsumo_riichi", "all_last_repeat", "all_last_advance",
          "end_target", "end_below_zero", "end_dealer_first", "end_extension_over", "end_sticks_left",
          "riichi_discard_ronned", "rinshan", "rinshan_after_ankan", "rinshan_after_daiminkan",
          "rinshan_after_kakan", "riichi_ankan", "ron_x2", "multi_ron_sticks", "multi_ron_honba",
          "extension_hand", "chankan", "ron_after_open_kan", "ron_after_open_kan_riichi"}


class Pool:
    def __init__(self, cmd: list[str], n: int, sink):
        self.cond = threading.Condition()
        self.outstanding = [0] * n
        self.procs = []
        self.threads = []
        self.sink = sink
        for i in range(n):
            p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=1 << 20)
            t = threading.Thread(target=self.read, args=(i, p), daemon=True)
            t.start()
            self.procs.append(p)
            self.threads.append(t)

    def read(self, i, p):
        for line in p.stdout:
            self.sink(json.loads(line))
            with self.cond:
                self.outstanding[i] -= 1
                self.cond.notify_all()

    def send(self, name: str, data: bytes):
        with self.cond:
            while min(self.outstanding) >= 32:
                self.cond.wait()
            i = self.outstanding.index(min(self.outstanding))
            self.outstanding[i] += 1
        p = self.procs[i]
        p.stdin.write(f"{name} {len(data)}\n".encode() + data)
        p.stdin.flush()

    def drain(self):
        for p in self.procs:
            p.stdin.flush()
        with self.cond:
            while any(self.outstanding):
                self.cond.wait(timeout=1)
                for p in self.procs:
                    p.stdin.flush()

    def close(self):
        for p in self.procs:
            p.stdin.close()
        for p in self.procs:
            p.wait()
        for t in self.threads:
            t.join()


class Shard:
    def __init__(self, name: str, out: str):
        self.name = name
        self.lock = threading.Lock()
        self.games = 0
        self.hands = 0
        self.lite = 0
        self.diff_games = 0
        self.tenhou_named = 0
        self.all_games = False
        self.diffs = collections.Counter()
        self.conventions = collections.Counter()
        self.unchecked = collections.Counter()
        self.tags = collections.Counter()
        self.examples: dict[str, list] = {}
        self.file = open(os.path.join(out, f"{name}.games.jsonl"), "w")

    def take(self, r: dict):
        with self.lock:
            self.games += 1
            self.hands += r["h"]
            self.lite += r["lite"]
            if r["d"]:
                self.diff_games += 1
            for h, e, cat, msg in r["d"]:
                self.diffs[cat] += 1
                ex = self.examples.setdefault(cat, [])
                if len(ex) < 5:
                    ex.append([r["g"], h, e, msg])
            self.conventions.update(r["c"])
            self.unchecked.update(r["u"])
            seen = set()
            for h, t in r["t"]:
                if (h, t) not in seen:  # hands with the tag
                    seen.add((h, t))
                    self.tags[t] += 1
            if self.name.startswith("majsoul") and "gm-" in r["g"]:
                self.tenhou_named += 1
            if self.all_games or r["d"] or r["c"] or any(t not in COMMON for _, t in r["t"]):
                self.file.write(json.dumps(r, ensure_ascii=False) + "\n")

    def summary(self, secs: float, args) -> dict:
        return {"shard": self.name, "rules": args.rules, "set": args.set, "games": self.games,
                "hands": self.hands, "lite_games": self.lite, "games_with_differences": self.diff_games,
                "tenhou_named_games": self.tenhou_named,
                "seconds": round(secs, 1), "games_per_s": round(self.games / secs, 1) if secs else None,
                "hands_per_s": round(self.hands / secs, 1) if secs else None,
                "differences": dict(self.diffs.most_common()), "examples": self.examples,
                "conventions": dict(self.conventions), "unchecked": dict(self.unchecked),
                "tags": dict(sorted(self.tags.items()))}


def run(args):
    os.makedirs(args.out, exist_ok=True)
    cmd = [args.mj, "check-log", "--stdin", "--json", "--rules", args.rules]
    for s in args.set:
        cmd += ["--set", s]
    only = None
    if args.only:
        with open(args.only) as f:
            only = {l.strip() for l in f if l.strip()}
    current: list[Shard] = []
    pool = Pool(cmd, args.jobs, lambda r: current[0].take(r))
    for tar in args.tars:
        stem = os.path.basename(tar).removesuffix(".tar") + args.tag_suffix
        shard = Shard(stem, args.out)
        shard.all_games = args.all_games
        current[:] = [shard]
        start = time.monotonic()
        n = 0
        # With --only, scan the headers (seeking past the data) and read just the
        # members wanted; otherwise stream the whole tar.
        def members():
            if only is None:
                with tarfile.open(tar, "r|") as tf:
                    for m in tf:
                        if m.isfile():
                            yield m.name, tf.extractfile(m).read()
                return
            with tarfile.open(tar, "r:") as tf, open(tar, "rb") as raw:
                for m in tf:
                    if m.isfile() and m.name.removesuffix(".mjai.json.zst") in only:
                        raw.seek(m.offset_data)
                        yield m.name, raw.read(m.size)
        if True:
            for mname, blob in members():
                if not mname.endswith(".mjai.json.zst"):
                    continue
                name = mname.removesuffix(".mjai.json.zst")
                if only is not None and name not in only:
                    continue
                data = zstd.decompress(blob)
                pool.send(name, data)
                n += 1
                if args.limit and n >= args.limit:
                    break
                if n % 20000 == 0:
                    el = time.monotonic() - start
                    print(f"  {stem}: {n} games sent, {shard.games} checked, {el:.0f}s, "
                          f"{shard.games / el:.0f} games/s", file=sys.stderr, flush=True)
        pool.drain()
        secs = time.monotonic() - start
        shard.file.close()
        s = shard.summary(secs, args)
        with open(os.path.join(args.out, f"{stem}.summary.json"), "w") as f:
            json.dump(s, f, indent=1, ensure_ascii=False)
        print(f"{stem}: games={s['games']} hands={s['hands']} lite={s['lite_games']} "
              f"diff_games={s['games_with_differences']} {s['games_per_s']} games/s "
              f"diffs={dict(shard.diffs.most_common(8))} conventions={dict(shard.conventions)}", flush=True)
    pool.close()


def report(dirs):
    rows = []
    for d in dirs:
        for f in sorted(os.listdir(d)):
            if f.endswith(".summary.json"):
                with open(os.path.join(d, f)) as fh:
                    rows.append(json.load(fh))
    tot = collections.Counter()
    tags = collections.Counter()
    diffs = collections.Counter()
    conv = collections.Counter()
    print(f"{'shard':32} {'games':>9} {'hands':>10} {'lite':>8} {'diffgames':>9} {'g/s':>7}")
    for r in rows:
        print(f"{r['shard']:32} {r['games']:9} {r['hands']:10} {r['lite_games']:8} "
              f"{r['games_with_differences']:9} {r['games_per_s'] or 0:7}")
        tot.update(games=r["games"], hands=r["hands"], secs=r["seconds"])
        tags.update(r["tags"])
        diffs.update(r["differences"])
        conv.update(r["conventions"])
    print("total", dict(tot))
    print("differences", dict(diffs.most_common()))
    print("conventions", dict(conv))
    print("tags (hands; per million hands)")
    for t, v in sorted(tags.items()):
        print(f"  {t:32} {v:9} {1e6 * v / max(tot['hands'], 1):10.1f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mj", default="./mj")
    ap.add_argument("--rules", default="mahjongsoul")
    ap.add_argument("--set", action="append", default=[])
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count())
    ap.add_argument("--out")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--only")
    ap.add_argument("--tag-suffix", default="")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--all-games", action="store_true")
    ap.add_argument("tars", nargs="*")
    args = ap.parse_args()
    if args.report:
        report(args.tars)
    else:
        if not args.out:
            ap.error("--out is required")
        run(args)


if __name__ == "__main__":
    main()
