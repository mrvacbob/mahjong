#!/usr/bin/env python3
"""A tiny scripted mjai bot for the adapter test: reads one event per line and
writes one reply per line. It discards its drawn tile (tsumogiri), declares riichi
whenever its closed 14 tiles have a discard leaving tenpai (two steps: `reach`,
then the `dahai` after the reach event), wins whenever it can by its own reckoning
(complete hand; it ignores yaku, so some wins are illegal), and passes calls.

Misbehaviour on the Nth decision (1-based), from the arguments:
  malformed=N  reply with text that is not JSON
  illegal=N    discard a tile it does not hold
  sleep=N      never reply (the adapter times out)
  exit=N       exit
"""
import json, sys

args = dict(a.split("=") for a in sys.argv[1:])
plan = {int(v): k for k, v in args.items()}
seat = None; hand = []; drawn = None; melded = False; decisions = 0; riichi_tile = None

def kind(t): return t[:2] if t[0].isdigit() else t
def complete(ks):
    if not ks: return True
    k = ks[0]
    if ks.count(k) >= 3:
        r = list(ks); [r.remove(k) for _ in range(3)]
        if complete(r): return True
    if k[0].isdigit():
        n, s = int(k[0]), k[1]
        a, b = f"{n+1}{s}", f"{n+2}{s}"
        if a in ks and b in ks:
            r = list(ks); r.remove(k); r.remove(a); r.remove(b)
            if complete(r): return True
    return False
def agari(tiles):
    ks = sorted(kind(t) for t in tiles)
    for p in set(ks):
        if ks.count(p) >= 2:
            r = list(ks); r.remove(p); r.remove(p)
            if complete(r): return True
    return False
ALL = [f"{n}{s}" for s in "mps" for n in range(1, 10)] + list("ESWNPFC")
def tenpai(tiles): return any(agari(tiles + [k]) for k in ALL)

def reply(obj):
    global decisions
    decisions += 1
    what = plan.get(decisions)
    if what == "malformed": print("{not json", flush=True); return
    if what == "illegal": obj = {"type": "dahai", "actor": seat, "pai": "C" if "C" not in hand else "E", "tsumogiri": False}
    if what == "sleep":
        sys.stdin.readline()  # wait for the adapter to give up and close
        sys.exit(0)
    if what == "exit": sys.exit(0)
    print(json.dumps(obj), flush=True)

for line in sys.stdin:
    e = json.loads(line)
    t = e["type"]
    if t == "start_game": seat = e["id"]; print('{"type":"none"}', flush=True); continue
    if t == "start_kyoku": hand = list(e["tehais"][seat]); melded = False; riichi_tile = None
    if t == "tsumo" and e["actor"] == seat:
        drawn = e["pai"]
        tiles = hand + [drawn]
        if agari(tiles): reply({"type": "hora", "actor": seat, "target": seat}); hand.append(drawn); continue
        if not melded and riichi_tile is None and "reach" in args.get("mode", "reach"):
            for i, x in enumerate(tiles):
                rest = tiles[:i] + tiles[i + 1:]
                if tenpai(rest):
                    riichi_tile = x
                    reply({"type": "reach", "actor": seat}); break
            else:
                reply({"type": "dahai", "actor": seat, "pai": drawn, "tsumogiri": True})
            hand.append(drawn); continue
        hand.append(drawn)
        reply({"type": "dahai", "actor": seat, "pai": drawn, "tsumogiri": True}); continue
    if t == "reach" and e["actor"] == seat:
        x = riichi_tile if riichi_tile in hand else drawn
        reply({"type": "dahai", "actor": seat, "pai": x, "tsumogiri": x == drawn and hand.count(x) == 1}); continue
    if t == "dahai" and e["actor"] == seat:
        if e["pai"] in hand: hand.remove(e["pai"])
    if t in ("chi", "pon", "daiminkan") and e["actor"] == seat:
        melded = True
        for x in e["consumed"]: hand.remove(x)
    if t in ("ankan",) and e["actor"] == seat:
        melded = True
    if t == "dahai" and e["actor"] != seat and riichi_tile is not None and agari(hand + [e["pai"]]):
        reply({"type": "hora", "actor": seat, "target": e["actor"]}); continue
    if t in ("chi", "pon") and e["actor"] == seat:
        reply({"type": "dahai", "actor": seat, "pai": hand[-1], "tsumogiri": False}); continue
    if t == "end_game": print('{"type":"none"}', flush=True); break
    print('{"type":"none"}', flush=True)
