#!/usr/bin/env python3
"""A minimal mjai bot for the chained-kan arena test (Tests/mjTests): it discards
every tile it draws and answers `none` to everything else, except, in the first
hand only, the added kan of 1p by another seat. With `kakan` it answers that
event `hora` (as Mortal does: the robbing decision follows the `kakan`); with
`dora` it answers `none` there and `hora` to the indicator right after it."""
import json, sys

mode = sys.argv[1]
seat = None; hands = 0; last = None
for line in sys.stdin:
    e = json.loads(line)
    t = e["type"]
    out = {"type": "none"}
    if t == "start_game": seat = e["id"]
    elif t == "start_kyoku": hands += 1
    elif t == "tsumo" and e["actor"] == seat:
        out = {"type": "dahai", "actor": seat, "pai": e["pai"], "tsumogiri": True}
    elif hands == 1 and t == "kakan" and e["actor"] != seat and e["pai"] == "1p" and mode == "kakan":
        out = {"type": "hora", "actor": seat, "target": e["actor"], "pai": "1p"}
    elif (hands == 1 and t == "dora" and mode == "dora" and last is not None and last["type"] == "kakan"
          and last["pai"] == "1p"):
        out = {"type": "hora", "actor": seat, "target": last["actor"], "pai": "1p"}
    last = e
    print(json.dumps(out), flush=True)
    if t == "end_game": break
