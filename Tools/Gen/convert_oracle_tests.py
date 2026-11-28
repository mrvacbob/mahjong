"""Harvest hands from the oracle library's own tests and write them as requests.

    uv run --project ../3p/mahjong --no-sync \
        python -B Tools/Gen/convert_oracle_tests.py

Runs the library's pytest suite in-process with recording wrappers around
HandCalculator.estimate_hand_value, Shanten.*, Agari.is_agari and
HandDivider.divide_hand. Every recorded input that fits the shootout format becomes a
request in Tools/Gen/oracle_test_requests.txt (tab-separated: test id, request without
an id). generate.py adds them to the corpus and computes the expected answers under the
shootout rules, so the tests' own assertions (which use assorted rule options) are
deliberately not copied.

Nothing is written into the library checkout (no bytecode, no pytest cache, no coverage).
"""

from __future__ import annotations

import inspect
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ORACLE = os.environ.get("MJ_ORACLE_PATH", os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../3p/mahjong"))
OUT = os.path.join(HERE, "oracle_test_requests.txt")

import pytest  # noqa: E402

from mahjong.agari import Agari  # noqa: E402
from mahjong.constants import AKA_DORAS  # noqa: E402
from mahjong.hand_calculating.divider import HandDivider  # noqa: E402
from mahjong.hand_calculating.hand import HandCalculator  # noqa: E402
from mahjong.meld import Meld  # noqa: E402
from mahjong.shanten import Shanten  # noqa: E402

records: list[tuple[str, str, dict]] = []
recording = True


def _tag():
    t = os.environ.get("PYTEST_CURRENT_TEST", "?")
    return t.rsplit(" ", 1)[0]


def _wrap_static(cls, name, kind_):
    orig = getattr(cls, name)
    sig = inspect.signature(orig)

    def wrapper(*args, **kwargs):
        if recording:
            try:
                b = sig.bind(*args, **kwargs)
                b.apply_defaults()
                records.append((_tag(), kind_, dict(b.arguments)))
            except TypeError:
                pass
        return orig(*args, **kwargs)

    setattr(cls, name, staticmethod(wrapper))


_wrap_static(HandCalculator, "estimate_hand_value", "score")
for n in ("calculate_shanten", "calculate_shanten_for_regular_hand", "calculate_shanten_for_chiitoitsu_hand",
          "calculate_shanten_for_kokushi_hand"):
    _wrap_static(Shanten, n, "shanten")
_wrap_static(Agari, "is_agari", "agari")
_wrap_static(HandDivider, "divide_hand", "divide")


def main() -> int:
    global recording
    rc = pytest.main([
        os.path.join(ORACLE, "tests"),
        "-q", "-p", "no:cacheprovider", "-o", "addopts=", "--rootdir", ORACLE, "--no-header",
    ])
    recording = False
    print(f"pytest exit code {rc}; {len(records)} recorded calls", file=sys.stderr)

    sys.path.insert(0, TOOLS)
    import oracle_mj as O  # noqa: PLC0415  (import only after the tests ran)
    from mjfmt import fmt_melds, fmt_tile, fmt_tiles, parse_request  # noqa: PLC0415

    WIND = "ESWN"
    out: list[tuple[str, str]] = []
    seen = set()
    skipped: dict[str, int] = {}

    def skip(why):
        skipped[why] = skipped.get(why, 0) + 1

    def add(tag, op, pairs):
        body = op + " " + " ".join(f"{k}={v}" for k, v in pairs)
        if body in seen:
            return
        resp = O.handle("t " + body)
        _, _, kv = parse_request("t x " + resp.split(" ", 1)[1]) if " " in resp else (None, None, {})
        err = kv.get("error")
        if err and not (op == "score" and err in ("not_agari", "no_yaku")):
            skip(f"{op}: oracle_mj says error={err}")
            return
        seen.add(body)
        out.append((tag, body))

    def code(tid, aka):
        k = tid // 4
        if aka and tid in AKA_DORAS:
            return {16: 34, 52: 35, 88: 36}[tid]
        return k

    def counts_to_tiles(c):
        return [k for k in range(34) for _ in range(c[k])]

    def fab_melds(c, k):
        """k fake pons on kinds absent from the hand (honors first)."""
        melds = []
        for kk in list(range(33, -1, -1)):
            if len(melds) == k:
                break
            if c[kk] == 0:
                melds.append(("p", [kk, kk, kk]))
        return melds if len(melds) == k else None

    for tag, kind_, a in records:
        if kind_ == "score":
            cfg = a.get("config")
            tiles = list(a["tiles"])
            win = a["win_tile"]
            melds = list(a.get("melds") or [])
            if a.get("scores_calculator_factory") is not None and a["scores_calculator_factory"].__name__ != "ScoresCalculator":
                pass  # aotenjou in the test; re-scored under standard rules below
            if cfg is not None:
                if (cfg.is_nagashi_mangan or cfg.is_renhou or cfg.is_open_riichi or cfg.paarenchan
                        or cfg.num_nuki_dora or cfg.options.is_three_player):
                    skip("score: rule outside the shootout (nagashi/renhou/open riichi/paarenchan/3p)")
                    continue
            aka = bool(cfg and cfg.options.has_aka_dora)
            if win not in tiles or len(set(tiles)) != len(tiles):
                skip("score: malformed tiles")
                continue
            rest = list(tiles)
            ok = True
            lm = []
            for m in melds:
                if m.type == Meld.NUKI:
                    ok = False
                    break
                letter = {Meld.CHI: "c", Meld.PON: "p", Meld.SHOUMINKAN: "s"}.get(m.type)
                if m.type == Meld.KAN:
                    letter = "k" if m.opened else "a"
                if letter is None:
                    ok = False
                    break
                mt = []
                for t in m.tiles:
                    if t not in rest:
                        # tests often build melds without aka ids; match by kind instead
                        same = [x for x in rest if x // 4 == t // 4 and x != win]
                        if not same:
                            ok = False
                            break
                        t = same[-1]
                    rest.remove(t)
                    mt.append(t)
                lm.append((letter, [code(t, aka) for t in mt]))
            if not ok or win not in rest:
                skip("score: meld tiles not in hand")
                continue
            rest.remove(win)
            if len(rest) != 13 - 3 * len(lm):
                skip("score: wrong tile count")
                continue
            seat = "S"
            rnd = "E"
            flags = []
            by = "ron"
            honba = 0
            if cfg is not None:
                if cfg.player_wind is not None:
                    seat = WIND[cfg.player_wind - 27]
                elif cfg.is_tenhou:
                    seat = "E"
                if cfg.round_wind is not None:
                    rnd = WIND[cfg.round_wind - 27]
                by = "tsumo" if cfg.is_tsumo else "ron"
                if cfg.is_daburu_riichi:
                    flags.append("double_riichi")
                elif cfg.is_riichi:
                    flags.append("riichi")
                for attr, f in (("is_ippatsu", "ippatsu"), ("is_haitei", "haitei"), ("is_houtei", "houtei"),
                                ("is_rinshan", "rinshan"), ("is_chankan", "chankan"), ("is_tenhou", "tenhou"),
                                ("is_chiihou", "chiihou")):
                    if getattr(cfg, attr):
                        flags.append(f)
                honba = cfg.tsumi_number
            dora = [code(t, aka) for t in (a.get("dora_indicators") or [])]
            ura = [code(t, aka) for t in (a.get("ura_dora_indicators") or [])]
            pairs = [("hand", fmt_tiles([code(t, aka) for t in rest])), ("melds", fmt_melds(lm)),
                     ("win", fmt_tile(code(win, aka))), ("by", by), ("seat", seat), ("round", rnd)]
            if dora:
                pairs.append(("dora", fmt_tiles(dora)))
            if ura and flags and flags[0] in ("riichi", "double_riichi"):
                pairs.append(("ura", fmt_tiles(ura)))
            if honba > 0:
                pairs.append(("honba", str(honba)))
            if flags:
                pairs.append(("flags", ",".join(flags)))
            add(tag, "score", pairs)
        elif kind_ == "shanten":
            c = list(a["tiles_34"])
            n = sum(c)
            if len(c) != 34 or any(x < 0 or x > 4 for x in c) or n > 14 or n % 3 == 0 or n == 0:
                skip("shanten: invalid tile array")
                continue
            k = (14 - n) // 3 if n % 3 == 2 else (13 - n) // 3
            melds = fab_melds(c, k) if k else []
            if melds is None:
                skip("shanten: could not fabricate melds")
                continue
            hand = counts_to_tiles(c)
            add(tag, "shanten", [("hand", fmt_tiles(hand)), ("melds", fmt_melds(melds))])
            if n % 3 == 1:
                add(tag, "waits", [("hand", fmt_tiles(hand)), ("melds", fmt_melds(melds))])
        elif kind_ in ("agari", "divide"):
            c = list(a["tiles_34"])
            if len(c) != 34 or any(x < 0 or x > 4 for x in c):
                skip(f"{kind_}: invalid tile array")
                continue
            lm = []
            sets = a.get("open_sets_34") if kind_ == "agari" else a.get("melds")
            ok = True
            for s in sets or []:
                ks = sorted(s.tiles_34 if isinstance(s, Meld) else s)
                for x in ks:
                    c[x] -= 1
                if isinstance(s, Meld):
                    letter = {Meld.CHI: "c", Meld.PON: "p", Meld.SHOUMINKAN: "s"}.get(s.type)
                    if s.type == Meld.KAN:
                        letter = "k" if s.opened else "a"
                else:
                    letter = "c" if len(ks) == 3 and ks[0] != ks[1] else ("p" if len(ks) == 3 else "k")
                if letter is None:
                    ok = False
                lm.append((letter, ks))
            if not ok or any(x < 0 for x in c):
                skip(f"{kind_}: bad melds")
                continue
            n = sum(c)
            if n % 3 != 2 or n + 3 * len(lm) > 14:
                skip(f"{kind_}: wrong tile count")
                continue
            k = (14 - n) // 3 - len(lm)
            extra = fab_melds([x + sum(1 for _, ks in lm for y in ks if y == i) for i, x in enumerate(c)], k) if k else []
            if extra is None:
                skip(f"{kind_}: could not fabricate melds")
                continue
            add(tag, "agari", [("hand", fmt_tiles(counts_to_tiles(c))), ("melds", fmt_melds(lm + extra))])

    with open(OUT, "w") as f:
        f.write("# Requests harvested from the oracle library's tests by convert_oracle_tests.py.\n")
        f.write("# Format: <pytest id> TAB <op> <key=value ...>\n")
        for tag, body in out:
            f.write(f"{tag}\t{body}\n")
    by_op: dict[str, int] = {}
    for _, body in out:
        op = body.split(" ", 1)[0]
        by_op[op] = by_op.get(op, 0) + 1
    print(f"wrote {len(out)} requests to {OUT}: {by_op}", file=sys.stderr)
    for why, n in sorted(skipped.items(), key=lambda x: -x[1]):
        print(f"  skipped {n}: {why}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
