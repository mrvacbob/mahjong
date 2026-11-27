#!/usr/bin/env python3.14
"""`mj` built on the Python `mahjong` library (the oracle). Implements agari, shanten,
waits and score from spec/formats.md; `legal` answers error=unsupported.

Run directly as an executable (stdin -> stdout), or import and call `handle(line)`.

Rule settings live in RULES. The library is adjusted (by wrapping, never by editing it)
where the shootout's assumed rules differ from the library's defaults; every such
adjustment is listed in the Decisions log of spec/formats.md.
"""

from __future__ import annotations

import os
import sys
from functools import lru_cache

ORACLE_PATH = os.environ.get("MJ_ORACLE_PATH", os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../3p/mahjong"))
sys.dont_write_bytecode = True  # never write into the oracle checkout
sys.path.insert(0, ORACLE_PATH)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import mahjong.hand_calculating.hand as _hand_mod  # noqa: E402
from mahjong.constants import EAST  # noqa: E402
from mahjong.hand_calculating.divider import HandDivider  # noqa: E402
from mahjong.hand_calculating.fu import FuCalculator  # noqa: E402
from mahjong.hand_calculating.hand import HandCalculator  # noqa: E402
from mahjong.hand_calculating.hand_config import HandConfig, HandConstants, OptionalRules  # noqa: E402
from mahjong.hand_calculating.yaku_list.yakuman import KokushiMusou  # noqa: E402
from mahjong.meld import Meld  # noqa: E402
from mahjong.shanten import Shanten  # noqa: E402

from mjfmt import (  # noqa: E402
    WINDS,
    FormatError,
    counts34,
    fmt_response,
    fmt_tiles,
    kind,
    meld_tiles,
    parse_melds,
    parse_request,
    parse_tile,
    parse_tiles,
    validate_tiles,
)

# ---------------------------------------------------------------- rules

RULES = {
    # Fu for a pair that is both seat and round wind. spec/rules.md (Mahjong Soul
    # ranked): 4, which is also the library's own behaviour. 2 is the brief's
    # provisional assumption, kept as a switch for the rule-sensitive notes.
    "double_wind_fu": 4,
    # kokushi_13 / suuankou_tanki / junsei_chuuren / daisuushii count 2x
    # (spec/rules.md: natural double yakuman enabled). Kazoe stays 1x.
    "double_yakuman": True,
    # Standard-form shanten ignores tile availability (a hand waiting only on a fifth
    # copy still counts as tenpai). False = the library's own regular shanten, which
    # adds Tenhou-style penalties for hands holding all four copies of a kind.
    "pure_shanten": True,
}

# --------------------------------------------------------- library adjustments

_orig_calculate_fu = FuCalculator.calculate_fu


def _calculate_fu(hand, win_tile, win_group, config, valued_tiles=None, melds=None):
    if RULES["double_wind_fu"] == 2 and valued_tiles:
        # dedupe: a seat+round wind pair then counts once (2 fu)
        valued_tiles = list(dict.fromkeys(valued_tiles))
    return _orig_calculate_fu(hand, win_tile, win_group, config, valued_tiles, melds)


FuCalculator.calculate_fu = staticmethod(_calculate_fu)

# Record every interpretation the calculator ranks, so callers can detect ties the
# spec's tie-break rule does not resolve.
_orig_hand_priority = _hand_mod._hand_priority
_seen_hands: dict[int, dict] = {}


def _hand_priority(h):
    _seen_hands[id(h)] = h
    return _orig_hand_priority(h)


_hand_mod._hand_priority = _hand_priority

# ---------------------------------------------------------------- names

YAKU_NAMES = {
    "Riichi": "riichi",
    "DaburuRiichi": "double_riichi",
    "Ippatsu": "ippatsu",
    "Tsumo": "tsumo",
    "Pinfu": "pinfu",
    "Tanyao": "tanyao",
    "Iipeiko": "iipeikou",
    "Haku": "yakuhai_haku",
    "Hatsu": "yakuhai_hatsu",
    "Chun": "yakuhai_chun",
    "SeatWindEast": "yakuhai_seat",
    "SeatWindSouth": "yakuhai_seat",
    "SeatWindWest": "yakuhai_seat",
    "SeatWindNorth": "yakuhai_seat",
    "RoundWindEast": "yakuhai_round",
    "RoundWindSouth": "yakuhai_round",
    "RoundWindWest": "yakuhai_round",
    "RoundWindNorth": "yakuhai_round",
    "Haitei": "haitei",
    "Houtei": "houtei",
    "Rinshan": "rinshan",
    "Chankan": "chankan",
    "Chiitoitsu": "chiitoi",
    "Toitoi": "toitoi",
    "Sanankou": "sanankou",
    "Sanshoku": "sanshoku",
    "SanshokuDoukou": "sanshoku_doukou",
    "Ittsu": "ittsu",
    "Chantai": "chanta",
    "Honroto": "honroutou",
    "Shosangen": "shousangen",
    "SanKantsu": "sankantsu",
    "Honitsu": "honitsu",
    "Junchan": "junchan",
    "Ryanpeikou": "ryanpeikou",
    "Chinitsu": "chinitsu",
    "Dora": "dora",
    "AkaDora": "aka",
    "UraDora": "ura",
    "KokushiMusou": "kokushi",
    "DaburuKokushiMusou": "kokushi_13",
    "Suuankou": "suuankou",
    "SuuankouTanki": "suuankou_tanki",
    "Daisangen": "daisangen",
    "Shousuushii": "shousuushii",
    "DaiSuushii": "daisuushii",
    "Tsuuiisou": "tsuuiisou",
    "Chinroutou": "chinroutou",
    "Ryuuiisou": "ryuuiisou",
    "ChuurenPoutou": "chuuren",
    "DaburuChuurenPoutou": "junsei_chuuren",
    "Suukantsu": "suukantsu",
    "Tenhou": "tenhou",
    "Chiihou": "chiihou",
}

FLAGS = {"riichi", "double_riichi", "ippatsu", "haitei", "houtei", "rinshan", "chankan", "tenhou", "chiihou"}


class Unsupported(Exception):
    pass


# ---------------------------------------------------------------- input helpers


def _hand_and_melds(kv: dict[str, str], extra: int):
    """Parse hand+melds; hand must have 13-3k+extra tiles. Returns (hand, melds)."""
    if "hand" not in kv:
        raise FormatError("missing hand")
    hand = parse_tiles(kv["hand"])
    melds = parse_melds(kv.get("melds", "-"))
    if len(melds) > 4:
        raise FormatError("more than 4 melds")
    want = 13 - 3 * len(melds) + extra
    if len(hand) != want:
        raise FormatError(f"hand has {len(hand)} tiles, expected {want}")
    validate_tiles(hand + meld_tiles(melds))
    return hand, melds


def _hand_either(kv: dict[str, str]):
    hand = parse_tiles(kv["hand"]) if "hand" in kv else None
    if hand is None:
        raise FormatError("missing hand")
    melds = parse_melds(kv.get("melds", "-"))
    if len(melds) > 4:
        raise FormatError("more than 4 melds")
    if len(hand) not in (13 - 3 * len(melds), 14 - 3 * len(melds)):
        raise FormatError(f"hand has {len(hand)} tiles with {len(melds)} melds")
    validate_tiles(hand + meld_tiles(melds))
    return hand, melds


class _Ids:
    """Allocate distinct 136-format ids. Red fives get copy 0 (the library's aka ids)."""

    def __init__(self):
        self.used: dict[int, int] = {}

    def get(self, t: int) -> int:
        k = kind(t)
        if t >= 34:
            return k * 4
        start = 1 if k in (4, 13, 22) else 0
        n = self.used.get(k, start)
        if n > 3:
            raise FormatError("too many copies")
        self.used[k] = n + 1
        return k * 4 + n


def _lib_melds(melds, ids: _Ids):
    out = []
    for letter, ts in melds:
        tids = [ids.get(t) for t in ts]
        mtype = {"c": Meld.CHI, "p": Meld.PON, "k": Meld.KAN, "s": Meld.SHOUMINKAN, "a": Meld.KAN}[letter]
        out.append(Meld(meld_type=mtype, tiles=tids, opened=letter != "a"))
    return out


# ---------------------------------------------------------------- agari


_TYPE_ORDER = {"pair": 0, "seq": 1, "trip": 2}


def _group_str(block: list[int]) -> tuple[tuple, str]:
    k = block[0]
    if len(block) == 2:
        ty = "pair"
    elif block[0] == block[1]:
        ty = "trip"
    else:
        ty = "seq"
    return (k // 9, k % 9 if k < 27 else k - 27, _TYPE_ORDER[ty]), fmt_tiles(block)


def agari_forms(hand: list[int], melds) -> list[str]:
    ids = _Ids()
    lib_melds = _lib_melds(melds, ids)
    full = counts34(hand + meld_tiles(melds))
    forms: set[str] = set()
    for decomp in HandDivider.divide_hand(full, lib_melds):
        blocks = [list(b) for b in decomp]
        if len(blocks) == 7 and all(len(b) == 2 for b in blocks):
            forms.add("chiitoi")
            continue
        for m in lib_melds:
            mb = sorted(m.tiles_34)
            for i, b in enumerate(blocks):
                if sorted(b) == mb:
                    del blocks[i]
                    break
            else:
                raise RuntimeError("meld block missing from decomposition")
        groups = sorted(_group_str(b) for b in blocks)
        forms.add(",".join(g for _, g in groups))
    if not melds and KokushiMusou().is_condition_met(None, counts34(hand)):
        forms.add("kokushi")
    return sorted(forms)


def op_agari(kv):
    hand, melds = _hand_and_melds(kv, 1)
    forms = agari_forms(hand, melds)
    if not forms:
        return [("win", "0")]
    return [("win", "1"), ("forms", ";".join(forms))]


# ---------------------------------------------------------------- shanten


def _prune(opts):
    """Keep only Pareto-maximal (m, t, p) triples, capped to what can matter."""
    capped = {(min(m, 4), min(t, 4), min(p, 5)) for m, t, p in opts}
    keep = []
    for a in capped:
        if not any(b != a and b[0] >= a[0] and b[1] >= a[1] and b[2] >= a[2] for b in capped):
            keep.append(a)
    return frozenset(keep)


def _combine(a, b):
    return _prune({(x[0] + y[0], x[1] + y[1], x[2] + y[2]) for x in a for y in b})


@lru_cache(maxsize=None)
def _suit_opts(c: tuple[int, ...], honors: bool):
    """All (sets, taatsu, pairs) extractable from one suit's count vector."""
    i = 0
    while i < len(c) and c[i] == 0:
        i += 1
    if i == len(c):
        return frozenset({(0, 0, 0)})
    res = set()
    lst = list(c)

    def sub(*idx):
        x = lst.copy()
        for j in idx:
            x[j] -= 1
        return tuple(x)

    def add(base, opts):
        for m, t, p in opts:
            res.add((m + base[0], t + base[1], p + base[2]))

    add((0, 0, 0), _suit_opts(sub(i), honors))  # leave tile i isolated
    if c[i] >= 2:
        add((0, 0, 1), _suit_opts(sub(i, i), honors))
    if c[i] >= 3:
        add((1, 0, 0), _suit_opts(sub(i, i, i), honors))
    if not honors:
        if i + 1 < 9 and c[i + 1]:
            add((0, 1, 0), _suit_opts(sub(i, i + 1), honors))
            if i + 2 < 9 and c[i + 2]:
                add((1, 0, 0), _suit_opts(sub(i, i + 1, i + 2), honors))
        if i + 2 < 9 and c[i + 2]:
            add((0, 1, 0), _suit_opts(sub(i, i + 2), honors))
    return _prune(res)


def std_shanten(c34: list[int], nmelds: int) -> int:
    """Standard-form shanten ignoring tile availability (see Decisions log)."""
    opts = frozenset({(0, 0, 0)})
    for s in range(3):
        opts = _combine(opts, _suit_opts(tuple(c34[9 * s : 9 * s + 9]), False))
    for h in range(27, 34):
        if c34[h]:
            opts = _combine(opts, _suit_opts((c34[h],), True))
    best = 8
    for m, t, p in opts:
        mm = m + nmelds
        head = 1 if p else 0
        tt = t + p - head
        best = min(best, 8 - 2 * mm - min(tt, 4 - mm) - head)
    return best


def lib_std_shanten(c34: list[int]) -> int:
    return Shanten.calculate_shanten_for_regular_hand(c34)


def shanten_all(hand, melds):
    c = counts34(hand)
    if not RULES["pure_shanten"]:
        std = lib_std_shanten(c)
    else:
        std = std_shanten(c, len(melds))
    if RULES["pure_shanten"] and not any(n >= 4 for n in c):
        lib = lib_std_shanten(c)
        if lib != std:
            raise RuntimeError(f"internal: std shanten {std} != library {lib} for {fmt_tiles(hand)}")
    if melds:
        return std, None, None, std
    chi = Shanten.calculate_shanten_for_chiitoitsu_hand(c)
    ko = Shanten.calculate_shanten_for_kokushi_hand(c)
    return std, chi, ko, min(std, chi, ko)


def op_shanten(kv):
    hand, melds = _hand_either(kv)
    std, chi, ko, mn = shanten_all(hand, melds)
    x = lambda v: "x" if v is None else str(v)  # noqa: E731
    return [("std", str(std)), ("chiitoi", x(chi)), ("kokushi", x(ko)), ("min", str(mn))]


def waits(hand, melds):
    base = shanten_all(hand, melds)[3]
    visible = counts34(hand + meld_tiles(melds))
    tiles = []
    count = 0
    for k in range(34):
        if visible[k] >= 4:
            continue
        if shanten_all(hand + [k], melds)[3] < base:
            tiles.append(k)
            count += 4 - visible[k]
    return base, tiles, count


def op_waits(kv):
    hand, melds = _hand_and_melds(kv, 0)
    base, tiles, count = waits(hand, melds)
    return [("shanten", str(base)), ("tiles", fmt_tiles(tiles)), ("count", str(count))]


# ---------------------------------------------------------------- score


def _yaku_value(y, is_open: bool) -> int:
    return y.han_open if (is_open and y.han_open) else y.han_closed


def _render(hand_yaku, han, fu, cost, is_open, is_dealer, is_tsumo):
    yakuman = any(y.is_yakuman for y in hand_yaku)
    items = []
    total_mult = 0
    for y in hand_yaku:
        name = YAKU_NAMES.get(type(y).__name__)
        if name is None:
            raise Unsupported(f"unmapped yaku {type(y).__name__}")
        v = _yaku_value(y, is_open)
        if yakuman:
            v //= 13
            total_mult += v
        items.append((name, v))
    items.sort()
    ystr = ",".join(f"{n}:{v}" for n, v in items)
    if is_tsumo:
        if is_dealer:
            pay = f"all:{cost['main'] + cost['main_bonus']}"
        else:
            pay = f"tsumo:{cost['additional'] + cost['additional_bonus']}/{cost['main'] + cost['main_bonus']}"
    else:
        pay = f"ron:{cost['main'] + cost['main_bonus']}"
    if yakuman:
        return [("yaku", ystr), ("yakuman", str(total_mult)), ("pay", pay), ("total", str(cost["total"]))]
    return [
        ("yaku", ystr),
        ("han", str(han)),
        ("fu", str(fu)),
        ("pay", pay),
        ("total", str(cost["total"])),
    ]


def _priority(c):
    """Spec tie-break (formats.md, score): highest total, then a real yakuman over a
    kazoe one, then higher han, then higher fu, then the yaku list that sorts first
    (applied by the caller). A yakuman answer prints no han or fu, so between two
    yakuman interpretations only total and the yaku list count."""
    if c["yakuman"]:
        return (c["total"], True, 0, 0)
    return (c["total"], False, c["han"], c["fu"])


def _interpretations(hand, win, melds, dora, ura, flags, seat, rnd, honba, by):
    """Score one (hand, winning tile) assignment. -> (candidates, library error or None).
    Each candidate is one interpretation the library ranked, already rendered."""
    ids = _Ids()
    concealed_ids = [ids.get(t) for t in hand]
    win_id = ids.get(win)
    lib_melds = _lib_melds(melds, ids)
    all_ids = concealed_ids + [win_id] + [i for m in lib_melds for i in m.tiles]
    ind = _Ids()
    dora_ids = [ind.get(t) for t in dora]
    ind = _Ids()
    ura_ids = [ind.get(t) for t in ura]

    options = OptionalRules(
        has_open_tanyao=True,
        has_aka_dora=True,
        has_double_yakuman=RULES["double_yakuman"],
        kazoe_limit=HandConstants.KAZOE_LIMITED,
        kiriage=False,
        fu_for_open_pinfu=True,
        fu_for_pinfu_tsumo=False,
        # No yakuman cap (spec/rules.md). The largest sum the ranked yakuman list can
        # reach is 6x, so the library's 6x cap would never bind either way.
        limit_to_sextuple_yakuman=False,
    )
    config = HandConfig(
        is_tsumo=by == "tsumo",
        is_riichi="riichi" in flags or "double_riichi" in flags,
        is_daburu_riichi="double_riichi" in flags,
        is_ippatsu="ippatsu" in flags,
        is_rinshan="rinshan" in flags,
        is_chankan="chankan" in flags,
        is_haitei="haitei" in flags,
        is_houtei="houtei" in flags,
        is_tenhou="tenhou" in flags,
        is_chiihou="chiihou" in flags,
        player_wind=EAST + WINDS.index(seat),
        round_wind=EAST + WINDS.index(rnd),
        tsumi_number=honba,
        options=options,
    )
    _seen_hands.clear()
    res = HandCalculator.estimate_hand_value(
        all_ids, win_id, melds=lib_melds, dora_indicators=dora_ids, config=config, ura_dora_indicators=ura_ids
    )
    seen = list(_seen_hands.values())
    _seen_hands.clear()
    is_open = any(m.opened for m in lib_melds)
    is_dealer = seat == "E"
    cands = []
    for h in seen:
        if h["error"] is not None or not h["cost"]:
            continue
        out = _render(h["hand_yaku"], h["han"], h["fu"], h["cost"], is_open, is_dealer, by == "tsumo")
        cands.append({
            "out": out,
            "total": h["cost"]["total"],
            "yakuman": any(y.is_yakuman for y in h["hand_yaku"]),
            "han": h["han"],
            "fu": h["fu"],
            "yaku": dict(out)["yaku"],
        })
    if not cands and not res.error:
        # the library found a hand without recording it through _hand_priority
        out = _render(res.yaku, res.han, res.fu, res.cost, is_open, is_dealer, by == "tsumo")
        cands.append({"out": out, "total": res.cost["total"], "yakuman": any(y.is_yakuman for y in res.yaku),
                      "han": res.han, "fu": res.fu, "yaku": dict(out)["yaku"]})
    return cands, res.error


def score(kv):
    """Returns (response pairs, info dict).

    The answer is chosen by the spec's full tie-break (see _priority), not by the
    library's own choice. info['tiebreak'] names the rule that decided between
    interpretations with the same total (None when the total alone decided);
    info['alternatives'] lists the losing interpretations at that total.
    With `tenhou`, every distinct tile of hand+win is tried as the winning tile
    (formats.md: score the best choice); `chiihou` keeps the supplied tile."""
    hand, melds = _hand_and_melds(kv, 0)
    if "win" not in kv:
        raise FormatError("missing win")
    win = parse_tile(kv["win"])
    by = kv.get("by")
    if by not in ("tsumo", "ron"):
        raise FormatError("by must be tsumo or ron")
    seat = kv.get("seat", "E")
    rnd = kv.get("round", "E")
    if seat not in WINDS or rnd not in WINDS or len(seat) != 1 or len(rnd) != 1:
        raise FormatError("bad seat/round")
    dora = parse_tiles(kv.get("dora", "-"))
    ura = parse_tiles(kv.get("ura", "-"))
    honba = int(kv.get("honba", "0"))
    if honba < 0:
        raise FormatError("negative honba")
    flags = set() if kv.get("flags", "-") == "-" else set(kv["flags"].split(","))
    if flags - FLAGS:
        raise FormatError(f"unknown flags {sorted(flags - FLAGS)}")
    unknown = set(kv) - {"hand", "melds", "win", "by", "seat", "round", "dora", "ura", "honba", "flags"}
    if unknown:
        raise FormatError(f"unknown keys {sorted(unknown)}")
    validate_tiles(hand + [win] + meld_tiles(melds))

    if "tenhou" in flags:
        tiles14 = hand + [win]
        choices = []
        for t in sorted(set(tiles14)):
            rest = list(tiles14)
            rest.remove(t)
            choices.append((rest, t))
    else:
        choices = [(hand, win)]

    cands = []
    first_error = None
    for h, w in choices:
        cs, err = _interpretations(h, w, melds, dora, ura, flags, seat, rnd, honba, by)
        cands.extend(cs)
        if err and first_error is None:
            first_error = err
    info = {"tiebreak": None, "alternatives": [], "tenhou_upgrade": False}
    if not cands:
        if first_error == HandCalculator.ERR_HAND_NOT_WINNING:
            return [("error", "not_agari")], info
        if first_error == HandCalculator.ERR_NO_YAKU:
            return [("error", "no_yaku")], info
        return [("error", first_error or "internal")], info

    best = max(_priority(c) for c in cands)
    tops = [c for c in cands if _priority(c) == best]
    tops.sort(key=lambda c: c["yaku"])
    chosen = tops[0]
    out = chosen["out"]

    same_total = [c for c in cands if c["total"] == chosen["total"]]
    others = {fmt_response("", c["out"]).strip() for c in same_total} - {fmt_response("", out).strip()}
    if others:
        info["alternatives"] = sorted(others)
        levels = [("real yakuman over kazoe", 1), ("higher han", 2), ("higher fu", 3)]
        for label, i in levels:
            if len({_priority(c)[i] for c in same_total}) > 1:
                info["tiebreak"] = label
                break
        else:
            info["tiebreak"] = "yaku list sorting first"
    if "tenhou" in flags:
        base, _ = _interpretations(hand, win, melds, dora, ura, flags, seat, rnd, honba, by)
        if base and max(c["total"] for c in base) < chosen["total"]:
            info["tenhou_upgrade"] = True
    return out, info


def op_score(kv):
    return score(kv)[0]


# ---------------------------------------------------------------- dispatch

OPS = {"agari": op_agari, "shanten": op_shanten, "waits": op_waits, "score": op_score}


def handle(line: str) -> str:
    line = line.rstrip("\r\n")
    rid = line.split(" ", 1)[0] if line else "?"
    try:
        rid, op, kv = parse_request(line)
        fn = OPS.get(op)
        if fn is None:
            return fmt_response(rid, [("error", "unsupported")])
        return fmt_response(rid, fn(kv))
    except FormatError as e:
        print(f"{rid}: bad_input: {e}", file=sys.stderr)
        return fmt_response(rid, [("error", "bad_input")])
    except Exception as e:  # never crash
        if os.environ.get("MJ_DEBUG"):
            raise
        print(f"{rid}: internal: {type(e).__name__}: {e}", file=sys.stderr)
        return fmt_response(rid, [("error", "internal")])


def main() -> int:
    out = sys.stdout
    for line in sys.stdin:
        if not line.strip():
            continue
        out.write(handle(line) + "\n")
    out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
