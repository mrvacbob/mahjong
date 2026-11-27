#!/usr/bin/env python3
"""Totals over a tools/libriichi_diff.sh work directory: board replay (check),
compare.py, and the row classification, per bot kind."""
import json, sys, glob, collections, os
work = sys.argv[1]
import re
names = sorted({re.sub(r"[0-9]{3}\.classify\.json$", "", os.path.basename(f))
                for f in glob.glob(os.path.join(work, "*[0-9][0-9][0-9].classify.json"))})
for bots in names:
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
                j = json.loads(line)
                lg, lb = j.get("log") or {}, j.get("libriichi") or {}
                # Known board differences (agpl/libriichi-check/NOTES.md), by shape.
                if lg.get("type") == "ryukyoku" and lg.get("reason") == "sanchahou":
                    kind = "triple_ron_abort"
                elif lg.get("type") == "reach_accepted" and lb.get("type") == "ryukyoku":
                    kind = "four_winds_riichi_stick (engine pays it: real-log ruling)"
                elif (lg.get("type") == lb.get("type") == "hora" and ["rinshan", 1] in (lg.get("yakus") or [])
                      and max(lb.get("deltas") or [0]) in (32000, 48000)):
                    # libriichi's state/update.rs daiminkan clears can_w_riichi for the
                    # other seats only, so the caller's rinshan tsumo before its first
                    # discard scores chiihou (Tenhou: any call voids it).
                    kind = "chiihou_after_own_daiminkan (libriichi)"
                else:
                    kind = f"UNEXPLAINED log {lg.get('type')} / libriichi {lb.get('type')}"
                    print("  unexplained board difference:", line.strip()[:300])
                board["by kind: " + kind] += 1
        last = open(d + ".compare.txt").read().strip().split("\n")[-1]
        j = json.loads(last)
        cmp["hands"] += j["hands"]; cmp["failed"] += j["failed"]; cmp["rows"] += j["rows"]
        for k, v in j["filtered"].items(): filt[k] += v
        c = json.load(open(f))
        rows["(all rows)"] += c["rows"]
        rows["(hands with no libriichi rows: board difference)"] += c.get("hands_without_libriichi_rows", 0)
        for k, v in c["rows_with_difference_by_category"].items(): rows[k] += v
        for k, v in c["hands_by_category"].items(): hands[k] += v
    cov = collections.Counter(); fails = 0
    for f in files:
        for line in open(f[: -len(".classify.json")] + ".selfplay.txt"):
            m = re.fullmatch(r"  ([a-z_0-9]+)=([0-9]+)\n", line)
            if m: cov[m[1]] += int(m[2])
            if line.startswith("FAIL") or line.startswith("failures="): fails += 1
    print(f"== {bots}: {len(files)} batches, {games} games")
    print("coverage:", dict(sorted(cov.items())))
    print("selfplay FAIL lines:", fails)
    print("board replay (libriichi-check check):", dict(board))
    print("compare.py:", dict(cmp), "filtered:", dict(filt))
    print("rows by category (hands):")
    for k, v in rows.most_common(): print(f"  {k}: {v} ({hands.get(k, '-')})")
