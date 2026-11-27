#!/usr/bin/env python3
"""Totals over a tools/libriichi_diff.sh work directory: board replay (check),
compare.py, and the row classification, per bot kind."""
import json, sys, glob, collections, os
work = sys.argv[1]
for bots in ("eager", "random"):
    files = sorted(glob.glob(os.path.join(work, bots + "[0-9][0-9][0-9].classify.json")))
    if not files: continue
    board = collections.Counter(); cmp = collections.Counter(); filt = collections.Counter()
    rows = collections.Counter(); hands = collections.Counter(); games = 0
    for f in files:
        d = f[: -len(".classify.json")]
        games += sum(1 for _ in open(d + ".files"))
        for line in open(d + ".check.txt"):
            if line.startswith("{") and '"hands"' in line:
                j = json.loads(line)
                board["hands"] += j["hands"]; board["failed"] += j["failed"]
                for k, v in j.get("filtered", {}).items(): board["filtered " + k] += v
            elif line.startswith("{"):
                board["difference lines"] += 1
        last = open(d + ".compare.txt").read().strip().split("\n")[-1]
        j = json.loads(last)
        cmp["hands"] += j["hands"]; cmp["failed"] += j["failed"]; cmp["rows"] += j["rows"]
        for k, v in j["filtered"].items(): filt[k] += v
        c = json.load(open(f))
        rows["(all rows)"] += c["rows"]
        for k, v in c["rows_with_difference_by_category"].items(): rows[k] += v
        for k, v in c["hands_by_category"].items(): hands[k] += v
    print(f"== {bots}: {len(files)} batches, {games} games")
    print("board replay (libriichi-check check):", dict(board))
    print("compare.py:", dict(cmp), "filtered:", dict(filt))
    print("rows by category (hands):")
    for k, v in rows.most_common(): print(f"  {k}: {v} ({hands.get(k, '-')})")
