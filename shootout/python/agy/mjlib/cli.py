"""Line-oriented protocol parser and dispatcher for the shootout runner contract."""

from __future__ import annotations

import sys

from .decompose import agari_forms
from .legal import legal_called, legal_discard, legal_draw
from .shanten import compute_shanten, compute_waits
from .tiles import (
    WIND_MAP,
    format_kinds,
    parse_meld,
    parse_melds,
    parse_tile,
    parse_tiles,
    tiles_to_counts,
)
from .yaku import ScoreResult, score_hand


def _parse_flags(val: str) -> frozenset[str]:
    if not val or val == "-":
        return frozenset()
    return frozenset(f for f in val.split(",") if f)


def _handle_agari(kv: dict[str, str]) -> str:
    hand = parse_tiles(kv["hand"])
    melds = parse_melds(kv.get("melds", "-"))
    forms = agari_forms(tiles_to_counts(hand), len(melds))
    if not forms:
        return "win=0"
    return f"win=1 forms={';'.join(forms)}"


def _handle_shanten(kv: dict[str, str]) -> str:
    hand = parse_tiles(kv["hand"])
    melds = parse_melds(kv.get("melds", "-"))
    res = compute_shanten(tiles_to_counts(hand), len(melds))
    ch = "x" if res.chiitoi is None else str(res.chiitoi)
    ko = "x" if res.kokushi is None else str(res.kokushi)
    return f"std={res.std} chiitoi={ch} kokushi={ko} min={res.min_val}"


def _handle_waits(kv: dict[str, str]) -> str:
    hand = parse_tiles(kv["hand"])
    melds = parse_melds(kv.get("melds", "-"))
    hand_c = tiles_to_counts(hand)
    meld_c = [0] * 34
    for m in melds:
        for t in m.tiles:
            meld_c[t.kind] += 1
    res = compute_waits(hand_c, meld_c, len(melds))
    return f"shanten={res.shanten} tiles={format_kinds(res.tiles)} count={res.count}"


def _handle_score(kv: dict[str, str]) -> str:
    hand = parse_tiles(kv["hand"])
    melds = parse_melds(kv.get("melds", "-"))
    win_tile = parse_tile(kv["win"])
    by = kv["by"]
    seat = WIND_MAP[kv.get("seat", "E")]
    round_wind = WIND_MAP[kv.get("round", "E")]
    dora_inds = parse_tiles(kv.get("dora", "-"))
    ura_inds = parse_tiles(kv.get("ura", "-"))
    honba = int(kv.get("honba", "0"))
    flags = _parse_flags(kv.get("flags", "-"))

    res = score_hand(
        hand=hand,
        melds=melds,
        win_tile=win_tile,
        by=by,
        seat=seat,
        round_wind=round_wind,
        dora_inds=dora_inds,
        ura_inds=ura_inds,
        honba=honba,
        flags=flags,
    )
    if not isinstance(res, ScoreResult):
        return f"error={res}"
    if res.is_yakuman:
        return f"yaku={res.yaku_str} yakuman={res.yakuman} pay={res.pay} total={res.total}"
    return (
        f"yaku={res.yaku_str} han={res.han} fu={res.fu} "
        f"pay={res.pay} total={res.total}"
    )


def _handle_legal(kv: dict[str, str]) -> str:
    hand = parse_tiles(kv["hand"])
    melds = parse_melds(kv.get("melds", "-"))
    seat = WIND_MAP[kv.get("seat", "E")]
    round_wind = WIND_MAP[kv.get("round", "E")]
    dora_inds = parse_tiles(kv.get("dora", "-"))
    ura_inds = parse_tiles(kv.get("ura", "-"))
    honba = int(kv.get("honba", "0"))
    flags = _parse_flags(kv.get("flags", "-"))
    riichi = kv.get("riichi", "0") == "1"
    furiten = kv.get("furiten", "0") == "1"
    wall = int(kv.get("wall", "70"))
    first = kv.get("first", "0") == "1"
    kans = int(kv.get("kans", "0"))

    if "called" in kv:
        actions = legal_called(hand, parse_meld(kv["called"]), parse_tile(kv["took"]))
    elif "draw" in kv:
        actions = legal_draw(
            hand=hand,
            melds=melds,
            draw=parse_tile(kv["draw"]),
            seat=seat,
            round_wind=round_wind,
            dora_inds=dora_inds,
            ura_inds=ura_inds,
            honba=honba,
            flags=flags,
            riichi=riichi,
            wall=wall,
            first=first,
            kans=kans,
        )
    elif "discard" in kv:
        actions = legal_discard(
            hand=hand,
            melds=melds,
            discard=parse_tile(kv["discard"]),
            from_seat=kv["from"],
            seat=seat,
            round_wind=round_wind,
            dora_inds=dora_inds,
            ura_inds=ura_inds,
            honba=honba,
            flags=flags,
            riichi=riichi,
            furiten=furiten,
            wall=wall,
            kans=kans,
        )
    else:
        return "error=bad_input"

    return f"actions={','.join(actions)}"


_DISPATCH = {
    "agari": _handle_agari,
    "shanten": _handle_shanten,
    "waits": _handle_waits,
    "score": _handle_score,
    "legal": _handle_legal,
}


def process_line(line: str) -> str:
    tokens = line.split(" ")
    if len(tokens) < 2:
        rid = tokens[0] if tokens else "?"
        return f"{rid} error=bad_input"
    rid = tokens[0]
    op = tokens[1]
    handler = _DISPATCH.get(op)
    if handler is None:
        return f"{rid} error=unknown_op"
    kv: dict[str, str] = {}
    for tok in tokens[2:]:
        if "=" not in tok:
            return f"{rid} error=bad_input"
        k, v = tok.split("=", 1)
        kv[k] = v
    try:
        body = handler(kv)
        return f"{rid} {body}"
    except Exception:
        return f"{rid} error=bad_input"


def main() -> int:
    write = sys.stdout.write
    for raw in sys.stdin:
        line = raw.rstrip("\r\n")
        if not line:
            continue
        write(process_line(line) + "\n")
    return 0
