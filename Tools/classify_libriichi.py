#!/usr/bin/env python3
"""Classify every differing legality row (engine vs libriichi) into a known
NOTES.md difference, a new difference, or unexplained. Streams both files
(same row order). Prints JSON counts; with --show CAT prints examples."""
import json, sys, collections
REACT = ("can_chi_low","can_chi_mid","can_chi_high","can_pon","can_daiminkan","can_ron_agari")
eng_path, lib_path = sys.argv[1], sys.argv[2]
show = sys.argv[sys.argv.index("--show")+1] if "--show" in sys.argv else None
counts = collections.Counter(); hands_with = collections.defaultdict(set); examples = {}
rows = 0
class SeatCtx:
    def __init__(s):
        s.lib_temp = False      # libriichi may still hold a window furiten
        s.eng_had_t = False     # engine had temporary furiten during that span
        s.declined = False      # engine temporary furiten came from a declined tsumo
        s.last_tsumo_could_win = False
ctx = {}
logs = {}
def log_event(f, h, i):
    if f not in logs:
        logs.clear()
        hs = []; cur = None
        for l in open(f):
            e = json.loads(l)
            if e["type"] == "start_kyoku": cur = []; hs.append(cur)
            if cur is not None: cur.append(e)
        logs[f] = hs
    return logs[f][h - 1][i]
def base(t): return t[:2] if t[0].isdigit() else t
def cat(c, a, b, field):
    counts[c] += 1
    hands_with[c].add((a["file"], a["hand"]))
    if c not in examples: examples[c] = (field, a, b)
def merged(eng, lib):
    """Row pairs with the same key. libriichi writes no rows for a hand that failed
    its board replay (a known board difference, e.g. a triple-ron abort): the
    engine's rows of such hands are skipped and counted."""
    global skipped_hands
    lb = next(lib, None)
    skipped = set()
    for la in eng:
        a = json.loads(la)
        key = (a["file"], a["hand"], a["event_index"], a["seat"])
        b = json.loads(lb) if lb is not None else None
        if b is None or (b["file"], b["hand"]) != (a["file"], a["hand"]):
            # (Both files are in the same (file, hand) order.)
            skipped.add((a["file"], a["hand"]))
            continue
        assert key == (b["file"], b["hand"], b["event_index"], b["seat"]), (key, b)
        yield a, b
        lb = next(lib, None)
    assert lb is None, "libriichi rows left over"
    skipped_hands = len(skipped)
skipped_hands = 0
eng = open(eng_path); lib = open(lib_path)
for a, b in merged(eng, lib):
    rows += 1
    key = (a["file"], a["hand"], a["event_index"], a["seat"])
    hk = (a["file"], a["hand"]); seat = a["seat"]; et = a["event_type"]
    if et == "start_kyoku":
        ctx[(hk, seat)] = SeatCtx()
    c = ctx[(hk, seat)]
    ev = None  # the event itself is not in the rows; infer from flags of others
    # --- update context BEFORE comparing (state as of this event) ---
    # A window event on a kind in our waits starts a libriichi furiten span.
    mine = a["flags"]["target_actor"] == seat
    if et in ("dahai", "kakan") and not mine:
        pass  # handled below with the waits information of the previous row
    diffs = []
    for f in ("event_type","flags","discard","ankan","kakan","waits","shanten","furiten"):
        x, y = a[f], b[f]
        if f in ("discard","ankan","kakan","waits"):
            if sorted(x) == sorted(y): continue
        elif x == y: continue
        diffs.append(f)
    parts = a.get("x_furiten", "")
    # A seat that could have declared tsumo and acted otherwise (Tenhou: temporary
    # furiten until its next draw, design §4.2); decided before comparing the row.
    if mine and et in ("dahai", "ankan", "kakan", "reach") and c.last_tsumo_could_win:
        c.last_tsumo_could_win = False
        if "t" in parts:
            c.declined = True; c.lib_temp = False
    # track engine temporary furiten history
    if "t" in parts: c.eng_had_t = True
    def four_concealed():
        # a kind held four times in the concealed tiles (mpsz, e.g. 234m7777z)
        h = a.get("x_hand", ""); digits = []
        counts = collections.Counter()
        for ch in h:
            if ch.isdigit(): digits.append("5" if ch == "0" else ch)
            else:
                for d in digits: counts[d + ch] += 1
                digits = []
        return any(v == 4 for v in counts.values())
    def four_concealed_or_kan(a):
        # 13 - 3k concealed tiles plus a drawn one: fewer than 14 means a kan meld,
        # whose kind may be the only wait of a riichi discard (a fifth copy).
        n = sum(1 for ch in a.get("x_hand", "") if ch.isdigit())
        return four_concealed() or n < 14
    def riichi_kan_of_waited_tile():
        # In riichi (the drawn tile the only discard), the engine offers the closed
        # kan of the drawn tile, a kind the hand waits on, and libriichi does not: its
        # check_ankan_after_riichi refuses to kan a waited tile; Spec/formats.md
        # compares the structural wait kinds, which keep the kan kind as a fifth-copy
        # wait (rule choice; a seat that kans its winning tile in riichi gives it up,
        # so no record can show which Tenhou does).
        return (et == "tsumo" and mine and a["ankan"] and not b["ankan"] and len(a["discard"]) == 1
                and a["ankan"][0] in a["waits"] and a["discard"][0][:2] == a["ankan"][0])
    for f in diffs:
        x, y = a[f], b[f]
        if f in ("flags", "ankan") and riichi_kan_of_waited_tile() and (f == "ankan" or all(
                x[k] == y[k] for k in x if k != "can_ankan")):
            cat("NEW riichi_ankan_waited_tile", a, b, f); continue
        if et == "ankan" and mine and f in ("waits", "shanten", "furiten"):
            cat("NEW ankan_eager_commit", a, b, f); continue
        if f == "flags":
            for k in x:
                if x[k] == y[k]: continue
                if k == "target_actor" and not any(x[r] or y[r] for r in REACT):
                    cat("idle_target_actor", a, b, f); continue
                if k == "can_ron_agari" and not x[k] and y[k] and a.get("x_furiten") == "t" and c.eng_had_t:
                    # Our temporary furiten survives a call (design §4.1, Tenhou
                    # 「逆巡副露では解消しない」); libriichi cleared it at the discard.
                    cat("temporary_furiten_reset", a, b, f); continue
                cat("UNEXPLAINED flags." + k, a, b, f)
            continue
        if f == "waits":
            sx, sy = set(x), set(y)
            if sy < sx and sx - sy <= set(b.get("visible_exhausted", [])):
                cat("visible_exhausted_waits", a, b, f); continue
            if et in ("chi", "pon") and mine:
                cat("cached_waits", a, b, f); continue
            if et == "kakan" and mine: cat("kakan_eager_commit", a, b, f); continue
            if et == "ankan" and mine: cat("NEW ankan_eager_commit", a, b, f); continue
            cat("UNEXPLAINED waits " + et, a, b, f); continue
        if f == "shanten":
            if et == "kakan" and mine: cat("kakan_eager_commit", a, b, f); continue
            if et == "ankan" and mine: cat("NEW ankan_eager_commit", a, b, f); continue
            if x == y - 1 and four_concealed():
                cat("NEW four_concealed_shanten", a, b, f); continue
            if et in ("hora", "end_kyoku", "ryukyoku", "dora") and x == y - 1:
                cat("NEW announcement_shanten", a, b, f); continue
            cat("UNEXPLAINED shanten " + et, a, b, f); continue
        if f == "furiten":
            if et in ("chi", "pon") and mine and not x and y:
                cat("cached_waits", a, b, f); continue
            if et == "kakan" and mine: cat("kakan_eager_commit", a, b, f); continue
            if not x and y:
                if c.lib_temp or (et in ("dahai","kakan") and not mine):
                    cat("temporary_furiten_reset" if c.eng_had_t and not (et in ("dahai","kakan") and not mine) else "furiten_on_window_event", a, b, f)
                    continue
                cat("UNEXPLAINED furiten eng=F lib=T " + et, a, b, f); continue
            if x and not y:
                if parts == "t" and c.declined: cat("NEW declined_tsumo_furiten", a, b, f); continue
                if parts == "t" and c.eng_had_t: cat("temporary_furiten_reset", a, b, f); continue
                if "o" in parts and not set(a["waits"]) <= set(b["waits"]):
                    cat("visible_exhausted_waits" if set(a["waits"]) - set(b["waits"]) <= set(b.get("visible_exhausted", [])) else "cached_waits", a, b, f); continue
                cat("UNEXPLAINED furiten eng=T lib=F " + et + " parts=" + parts, a, b, f); continue
        if f == "discard" and et == "reach" and set(a["discard"]) < set(b["discard"]) and four_concealed_or_kan(a):
            cat("NEW riichi_fifth_copy_wait", a, b, f); continue
        cat("UNEXPLAINED " + f, a, b, f)
    # --- context updates after the row ---
    if et in ("dahai", "kakan") and not mine:
        pai = base(log_event(a["file"], a["hand"], a["event_index"])["pai"])
        if b["furiten"] or pai in a["waits"] or pai in b["waits"]:
            c.lib_temp = True
    if et == "dahai" and mine:
        # libriichi recomputes at the seat's own discard (non-riichi)
        c.lib_temp = False; c.eng_had_t = "t" in parts and not c.declined
    if et == "tsumo" and mine:
        c.last_tsumo_could_win = a["flags"]["can_tsumo_agari"]
        if "t" not in parts: c.declined = False
out = {"rows": rows, "hands_without_libriichi_rows": skipped_hands, "rows_with_difference_by_category": dict(counts.most_common()),
       "hands_by_category": {k: len(v) for k, v in sorted(hands_with.items(), key=lambda kv: -len(kv[1]))}}
print(json.dumps(out, indent=1))
if show:
    for k, (f, a, b) in examples.items():
        if show in k:
            print("==", k, f); print(" eng", {g: a[g] for g in a if g != "flags"}); print(" lib", {g: b[g] for g in b if g != "flags"})
