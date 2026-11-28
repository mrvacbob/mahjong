#!/usr/bin/env python3.14
"""Scenario file validator and JSON expander for Riichi Mahjong engine tests.

Standard library only. See Scenarios/FORMAT.md for the file format and
Docs/Design/engine.md §3 for the 136-tile wall layout.

Usage:
  python3.14 Tools/scenario.py Scenarios/foo.scn        # expand to JSON on stdout
  python3.14 Tools/scenario.py --check [paths...]       # validate scenarios (default: Scenarios/)
  python3.14 Tools/scenario.py --list [paths...]        # list scenarios and unverified tags
  python3.14 Tools/scenario.py --json-dir DIR [paths...]  # expand every scenario to DIR/<name>.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SUITS = "mpsz"
RED_CODES = (34, 35, 36)
RED_KIND = {34: 4, 35: 13, 36: 22}
KIND_RED = {4: 34, 13: 35, 22: 36}
VALID_RULESETS = ("mahjongsoul", "tenhou")
VALID_WINDS = ("E", "S", "W", "N")
VALID_OUTCOMES = ("ron", "tsumo", "exhaustive_draw", "abortive_draw")
VALID_ABORTS = ("kyuushu", "suufon_renda", "suucha_riichi", "suukaikan", "sanchahou")
VALID_ASSERT_ACTION_KINDS = {
    "discard", "tsumogiri", "riichi", "tsumo", "ankan", "kakan",
    "kyuushu", "ron", "pon", "daiminkan", "chi", "pass",
}


class ScenarioError(ValueError):
    pass


def tile_kind(t: int) -> int:
    return RED_KIND.get(t, t)


def tile_suit(t: int) -> int:
    return tile_kind(t) // 9


def tile_digit(t: int) -> int:
    if t >= 34:
        return 0
    return (t % 9 + 1) if t < 27 else (t - 27 + 1)


def fmt_tile(t: int) -> str:
    return f"{tile_digit(t)}{SUITS[tile_suit(t)]}"


def parse_tiles(s: str) -> list[int]:
    """Parse compact or space-separated mpsz tile list (e.g. '123m 0p 7z')."""
    s = s.strip()
    if not s or s == "-":
        return []
    out: list[int] = []
    for tok in s.split():
        pending: list[str] = []
        for ch in tok:
            if ch.isdigit():
                pending.append(ch)
            elif ch in SUITS:
                if not pending:
                    raise ScenarioError(f"suit letter without digits in {tok!r}")
                si = SUITS.index(ch)
                for d in pending:
                    n = int(d)
                    if si == 3:
                        if not 1 <= n <= 7:
                            raise ScenarioError(f"invalid honor tile {d}z")
                        out.append(27 + n - 1)
                    elif n == 0:
                        out.append(34 + si)
                    else:
                        out.append(si * 9 + n - 1)
                pending = []
            else:
                raise ScenarioError(f"invalid character {ch!r} in tile list {tok!r}")
        if pending:
            raise ScenarioError(f"trailing digits without suit in {tok!r}")
    return out


def parse_tile(s: str) -> int:
    ts = parse_tiles(s)
    if len(ts) != 1:
        raise ScenarioError(f"expected single tile, got {s!r}")
    return ts[0]


def full_136_canonical() -> list[int]:
    """All 136 physical tiles in canonical order (0 before 5)."""
    tiles: list[int] = []
    for s in range(3):
        for n in range(1, 10):
            k = s * 9 + (n - 1)
            if n == 5:
                tiles.append(34 + s)  # 1 red five
                tiles.extend([k, k, k])  # 3 normal fives
            else:
                tiles.extend([k, k, k, k])
    for n in range(1, 8):
        k = 27 + (n - 1)
        tiles.extend([k, k, k, k])
    assert len(tiles) == 136
    return tiles


def build_wall(
    dealer: int,
    hands: list[list[int]],
    live_slots: dict[int, int],
    rinshan: list[int],
    dora: list[int],
    ura: list[int],
) -> list[int]:
    """Validate 136-tile accounting and build the full wall per Docs/Design/engine.md §3."""
    if len(hands) != 4:
        raise ScenarioError("must specify exactly 4 hands")
    for seat, h in enumerate(hands):
        if len(h) != 13:
            raise ScenarioError(f"hand {seat} has {len(h)} tiles, expected 13")
    if not (1 <= len(dora) <= 5):
        raise ScenarioError(f"dora must have 1..5 tiles, got {len(dora)}")
    if len(ura) > 5:
        raise ScenarioError(f"ura must have 0..5 tiles, got {len(ura)}")
    if len(rinshan) > 4:
        raise ScenarioError(f"rinshan must have 0..4 tiles, got {len(rinshan)}")

    # Track remaining counts of each physical tile code (0..36)
    avail: dict[int, int] = {}
    for t in full_136_canonical():
        avail[t] = avail.get(t, 0) + 1

    def take(t: int, where: str) -> None:
        if avail.get(t, 0) <= 0:
            raise ScenarioError(f"tile {fmt_tile(t)} over-allocated at {where}")
        avail[t] -= 1

    wall: list[int | None] = [None] * 136

    # 0..51: deal in dealer order: 3 rounds of 4, then 1 each
    seat_order = [(dealer + k) % 4 for k in range(4)]
    cursors = [0, 0, 0, 0]
    w_idx = 0
    for _ in range(3):
        for s in seat_order:
            for _ in range(4):
                t = hands[s][cursors[s]]
                cursors[s] += 1
                take(t, f"hand {s}")
                wall[w_idx] = t
                w_idx += 1
    for s in seat_order:
        t = hands[s][cursors[s]]
        cursors[s] += 1
        take(t, f"hand {s}")
        wall[w_idx] = t
        w_idx += 1
    assert w_idx == 52

    # 52..121: live draws
    for idx, t in sorted(live_slots.items()):
        if not (0 <= idx < 70):
            raise ScenarioError(f"live draw index {idx} out of range 0..69")
        take(t, f"live draw {idx}")
        wall[52 + idx] = t

    # 122..125: rinshan
    for i, t in enumerate(rinshan):
        take(t, f"rinshan[{i}]")
        wall[122 + i] = t

    # 126..130: dora indicators
    for i, t in enumerate(dora):
        take(t, f"dora[{i}]")
        wall[126 + i] = t

    # 131..135: ura indicators
    for i, t in enumerate(ura):
        take(t, f"ura[{i}]")
        wall[131 + i] = t

    # Fill all unspecified slots deterministically in canonical order
    remaining: list[int] = []
    for t in full_136_canonical():
        if avail[t] > 0:
            remaining.append(t)
            avail[t] -= 1

    rem_iter = iter(remaining)
    final_wall: list[int] = []
    for slot in wall:
        if slot is None:
            final_wall.append(next(rem_iter))
        else:
            final_wall.append(slot)

    # Final sanity check: exact 136-tile set
    if sorted(final_wall) != sorted(full_136_canonical()):
        raise ScenarioError("internal error: final wall does not match 136-tile set")
    return final_wall


def strip_comment(line: str) -> str:
    if "#" in line:
        line = line.split("#", 1)[0]
    return line.strip()


def parse_bool(val: str, field: str) -> bool:
    v = val.strip().lower()
    if v == "true":
        return True
    if v == "false":
        return False
    raise ScenarioError(f"{field}: expected true or false, got {val!r}")


def parse_int(val: str, field: str) -> int:
    try:
        return int(val.strip())
    except ValueError:
        raise ScenarioError(f"{field}: expected integer, got {val!r}") from None


def parse_int_list(val: str, count: int, field: str) -> list[int]:
    parts = val.replace(",", " ").split()
    if len(parts) != count:
        raise ScenarioError(f"{field}: expected {count} integers, got {len(parts)} ({val!r})")
    return [parse_int(p, field) for p in parts]


def parse_seat_list(val: str, field: str) -> list[int]:
    v = val.strip()
    if v == "-" or v == "":
        return []
    parts = [p.strip() for p in v.replace(",", " ").split() if p.strip()]
    seats = [parse_int(p, field) for p in parts]
    for s in seats:
        if not 0 <= s <= 3:
            raise ScenarioError(f"{field}: invalid seat {s}")
    return seats


def parse_window_action(raw: str) -> dict[str, Any]:
    s = raw.strip()
    if s in ("ron", "daiminkan", "pass"):
        return {"action": s}
    if s.startswith("pon:"):
        ts = parse_tiles(s[4:])
        if len(ts) != 2:
            raise ScenarioError(f"pon requires 2 tiles, got {s!r}")
        if tile_kind(ts[0]) != tile_kind(ts[1]):
            raise ScenarioError(f"pon tiles must be same kind: {s!r}")
        return {"action": "pon", "using": [fmt_tile(t) for t in ts], "_codes": ts}
    if s.startswith("chi:"):
        ts = parse_tiles(s[4:])
        if len(ts) != 2:
            raise ScenarioError(f"chi requires 2 tiles, got {s!r}")
        if tile_suit(ts[0]) != tile_suit(ts[1]) or tile_suit(ts[0]) == 3:
            raise ScenarioError(f"chi tiles must be same numbered suit: {s!r}")
        return {"action": "chi", "using": [fmt_tile(t) for t in ts], "_codes": ts}
    raise ScenarioError(f"invalid window action {raw!r}")


def parse_assert_action(raw: str) -> dict[str, Any]:
    s = raw.strip()
    if ":" in s:
        kind, arg = s.split(":", 1)
        if kind not in VALID_ASSERT_ACTION_KINDS:
            raise ScenarioError(f"invalid action kind in assertion: {s!r}")
        if kind in ("discard", "kakan", "ankan"):
            t = parse_tile(arg)
            return {"action": kind, "tile": fmt_tile(t)}
        if kind in ("pon", "chi"):
            ts = parse_tiles(arg)
            if len(ts) != 2:
                raise ScenarioError(f"assertion {s!r} needs 2 tiles")
            return {"action": kind, "using": [fmt_tile(t) for t in ts]}
        raise ScenarioError(f"unexpected argument in assertion {s!r}")
    if s not in VALID_ASSERT_ACTION_KINDS:
        raise ScenarioError(f"invalid action in assertion: {s!r}")
    return {"action": s}


def parse_step(line: str) -> dict[str, Any]:
    if line.startswith("window:"):
        body = line[len("window:"):].strip()
        if not body:
            raise ScenarioError("empty window:")
        answers: dict[str, Any] = {}
        for part in body.split(","):
            part = part.strip()
            if not part:
                continue
            if "=" not in part:
                raise ScenarioError(f"window entry missing '=': {part!r}")
            seat_s, act_s = part.split("=", 1)
            seat = parse_int(seat_s, "window seat")
            if not 0 <= seat <= 3:
                raise ScenarioError(f"invalid seat {seat} in window")
            if str(seat) in answers:
                raise ScenarioError(f"duplicate seat {seat} in window")
            answers[str(seat)] = parse_window_action(act_s)
        return {"type": "window", "answers": answers}

    if line.startswith("auto_tsumogiri "):
        n = parse_int(line.split(None, 1)[1], "auto_tsumogiri")
        if n <= 0:
            raise ScenarioError("auto_tsumogiri count must be > 0")
        return {"type": "auto_tsumogiri", "count": n}

    if line.startswith("assert_legal "):
        rest = line[len("assert_legal "):].strip()
        if ":" not in rest:
            raise ScenarioError(f"assert_legal missing ':': {line!r}")
        seat_s, act_s = rest.split(":", 1)
        seat = parse_int(seat_s, "assert_legal seat")
        if not 0 <= seat <= 3:
            raise ScenarioError(f"invalid seat {seat} in assert_legal")
        return {"type": "assert_legal", "seat": seat, "target": parse_assert_action(act_s)}

    if line.startswith("assert_illegal "):
        rest = line[len("assert_illegal "):].strip()
        if ":" not in rest:
            raise ScenarioError(f"assert_illegal missing ':': {line!r}")
        seat_s, act_s = rest.split(":", 1)
        seat = parse_int(seat_s, "assert_illegal seat")
        if not 0 <= seat <= 3:
            raise ScenarioError(f"invalid seat {seat} in assert_illegal")
        return {"type": "assert_illegal", "seat": seat, "target": parse_assert_action(act_s)}

    if line.startswith("assert_furiten "):
        rest = line[len("assert_furiten "):].strip()
        if ":" not in rest:
            raise ScenarioError(f"assert_furiten missing ':': {line!r}")
        seat_s, val_s = rest.split(":", 1)
        seat = parse_int(seat_s, "assert_furiten seat")
        if not 0 <= seat <= 3:
            raise ScenarioError(f"invalid seat {seat} in assert_furiten")
        return {"type": "assert_furiten", "seat": seat, "expected": parse_bool(val_s, "assert_furiten")}

    if line.startswith("assert_not_asked "):
        seat = parse_int(line[len("assert_not_asked "):].strip(), "assert_not_asked")
        if not 0 <= seat <= 3:
            raise ScenarioError(f"invalid seat {seat} in assert_not_asked")
        return {"type": "assert_not_asked", "seat": seat}

    # Turn actions: "<seat> <verb> [arg]"
    toks = line.split()
    if len(toks) < 2:
        raise ScenarioError(f"unrecognized step: {line!r}")
    seat = parse_int(toks[0], "step seat")
    if not 0 <= seat <= 3:
        raise ScenarioError(f"invalid seat {seat} in step {line!r}")
    verb = toks[1]
    if verb == "discard":
        if len(toks) != 3:
            raise ScenarioError(f"discard requires 1 tile: {line!r}")
        t = parse_tile(toks[2])
        return {"type": "turn", "seat": seat, "action": "discard", "tile": fmt_tile(t), "tsumogiri": False, "_code": t}
    if verb == "tsumogiri":
        if len(toks) == 2:
            return {"type": "turn", "seat": seat, "action": "discard", "tsumogiri": True}
        if len(toks) == 3:
            t = parse_tile(toks[2])
            return {"type": "turn", "seat": seat, "action": "discard", "tile": fmt_tile(t), "tsumogiri": True, "_code": t}
        raise ScenarioError(f"invalid tsumogiri step: {line!r}")
    if verb in ("riichi", "tsumo", "kyuushu"):
        if len(toks) != 2:
            raise ScenarioError(f"{verb} takes no arguments: {line!r}")
        return {"type": "turn", "seat": seat, "action": verb}
    if verb == "ankan":
        if len(toks) != 3:
            raise ScenarioError(f"ankan requires 1 tile kind: {line!r}")
        t = parse_tile(toks[2])
        if t >= 34:
            raise ScenarioError(f"ankan takes a kind (not red five): {line!r}")
        return {"type": "turn", "seat": seat, "action": "ankan", "kind": fmt_tile(t), "_code": t}
    if verb == "kakan":
        if len(toks) != 3:
            raise ScenarioError(f"kakan requires 1 tile: {line!r}")
        t = parse_tile(toks[2])
        return {"type": "turn", "seat": seat, "action": "kakan", "tile": fmt_tile(t), "_code": t}
    raise ScenarioError(f"unknown turn action {verb!r} in {line!r}")


def parse_expect_section(kv: list[tuple[str, str]], round_cfg: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    wins: dict[str, dict[str, Any]] = {}
    events_list: list[str] = []
    events_order_list: list[str] = []

    for k, v in kv:
        if k == "outcome":
            if v not in VALID_OUTCOMES:
                raise ScenarioError(f"invalid outcome {v!r}")
            out["outcome"] = v
        elif k == "abort_reason":
            if v not in VALID_ABORTS:
                raise ScenarioError(f"invalid abort_reason {v!r}")
            out["abort_reason"] = v
        elif k == "winners":
            out["winners"] = parse_seat_list(v, "winners")
        elif k.startswith("win "):
            seat = parse_int(k[4:], "win seat")
            if not 0 <= seat <= 3:
                raise ScenarioError(f"invalid seat {seat} in {k!r}")
            info: dict[str, Any] = {}
            for tok in v.split():
                if "=" not in tok:
                    raise ScenarioError(f"bad token {tok!r} in {k}")
                wk, wv = tok.split("=", 1)
                if wk in ("han", "fu", "yakuman"):
                    info[wk] = parse_int(wv, f"{k}.{wk}")
                elif wk == "yaku":
                    info["yaku"] = [y.strip() for y in wv.split(",") if y.strip()]
                else:
                    raise ScenarioError(f"unknown key {wk!r} in {k}")
            wins[str(seat)] = info
        elif k == "tenpai":
            out["tenpai"] = parse_seat_list(v, "tenpai")
        elif k == "nagashi":
            out["nagashi"] = parse_seat_list(v, "nagashi")
        elif k == "deltas":
            out["deltas"] = parse_int_list(v, 4, "deltas")
        elif k == "scores":
            out["scores"] = parse_int_list(v, 4, "scores")
        elif k == "sticks":
            out["sticks"] = parse_int(v, "sticks")
            if out["sticks"] < 0:
                raise ScenarioError("expect.sticks must be >= 0")
        elif k == "honba":
            out["honba"] = parse_int(v, "honba")
            if out["honba"] < 0:
                raise ScenarioError("expect.honba must be >= 0")
        elif k == "dealer_repeats":
            out["dealer_repeats"] = parse_bool(v, "dealer_repeats")
        elif k == "events":
            events_list.extend([e.strip() for e in v.split(",") if e.strip()])
        elif k == "events_order":
            events_order_list.extend([e.strip() for e in v.split(",") if e.strip()])
        elif k == "game_ended":
            out["game_ended"] = parse_bool(v, "game_ended")
        elif k == "next_wind":
            if v not in VALID_WINDS:
                raise ScenarioError(f"invalid next_wind {v!r}")
            out["next_wind"] = v
        elif k == "next_round":
            nr = parse_int(v, "next_round")
            if not 1 <= nr <= 4:
                raise ScenarioError(f"invalid next_round {nr}")
            out["next_round"] = nr
        elif k == "next_dealer":
            nd = parse_int(v, "next_dealer")
            if not 0 <= nd <= 3:
                raise ScenarioError(f"invalid next_dealer {nd}")
            out["next_dealer"] = nd
        elif k == "final_scores":
            out["final_scores"] = parse_int_list(v, 4, "final_scores")
        elif k == "final_ranks":
            ranks = parse_int_list(v, 4, "final_ranks")
            if sorted(ranks) != [0, 1, 2, 3]:
                raise ScenarioError(f"final_ranks must be a permutation of 0..3, got {ranks}")
            out["final_ranks"] = ranks
        elif k == "adjusted_scores":
            out["adjusted_scores"] = parse_int_list(v, 4, "adjusted_scores")
        else:
            raise ScenarioError(f"unknown expect key {k!r}")

    if wins:
        out["wins"] = wins
    if events_list:
        out["events"] = events_list
    if events_order_list:
        out["events_order"] = events_order_list

    for req in ("outcome", "deltas", "sticks", "honba", "dealer_repeats"):
        if req not in out:
            raise ScenarioError(f"missing required expect key {req!r}")

    if out["outcome"] == "abortive_draw" and "abort_reason" not in out:
        raise ScenarioError("abortive_draw requires abort_reason")
    if out["outcome"] in ("ron", "tsumo") and not out.get("winners"):
        raise ScenarioError(f"{out['outcome']} requires non-empty winners")
    if out["outcome"] == "exhaustive_draw" and "tenpai" not in out:
        raise ScenarioError("exhaustive_draw requires tenpai")

    # Point conservation: sum(deltas) + 1000 * (sticks_after - sticks_before) == 0
    sticks_diff = out["sticks"] - round_cfg["sticks"]
    if sum(out["deltas"]) + 1000 * sticks_diff != 0:
        raise ScenarioError(
            f"point conservation failed: sum(deltas)={sum(out['deltas'])}, "
            f"sticks {round_cfg['sticks']}->{out['sticks']} (delta {1000 * sticks_diff})"
        )

    if "scores" in out:
        expected_scores = [round_cfg["scores"][i] + out["deltas"][i] for i in range(4)]
        if out["scores"] != expected_scores:
            raise ScenarioError(
                f"expect.scores {out['scores']} != initial + deltas {expected_scores}"
            )

    if "final_scores" in out:
        total_before = sum(round_cfg["scores"]) + 1000 * round_cfg["sticks"]
        if sum(out["final_scores"]) != total_before:
            raise ScenarioError(
                f"final_scores sum {sum(out['final_scores'])} != total points on table {total_before}"
            )

    return out


def simulate_tile_flow(
    ruleset: str,
    dealer: int,
    hands_init: list[list[int]],
    wall: list[int],
    steps: list[dict[str, Any]],
) -> None:
    """Validate that every tile discarded, called, or kanned is actually held by that seat."""
    hands = [list(h) for h in hands_init]
    drawn: list[int | None] = [None, None, None, None]
    pons: list[list[int]] = [[], [], [], []]  # list of tile kinds ponned by each seat
    live_idx = 0
    rinshan_idx = 0
    kans_made = 0
    cur_seat = dealer
    awaiting_riichi_discard = False
    last_discard: tuple[int, int] | None = None  # (seat, tile)
    pending_kan: tuple[int, str, int] | None = None  # (seat, 'ankan'|'kakan', kind_or_tile)
    round_ended = False

    def live_remaining() -> int:
        return 70 - live_idx - kans_made

    def draw_live(seat: int) -> None:
        nonlocal live_idx
        if live_remaining() <= 0:
            raise ScenarioError(f"[{ruleset}] attempted live draw with 0 live tiles remaining")
        drawn[seat] = wall[52 + live_idx]
        live_idx += 1

    def draw_rinshan(seat: int) -> None:
        nonlocal rinshan_idx, kans_made
        if kans_made >= 4 or rinshan_idx >= 4:
            raise ScenarioError(f"[{ruleset}] attempted 5th kan / rinshan draw")
        kans_made += 1
        drawn[seat] = wall[122 + rinshan_idx]
        rinshan_idx += 1

    def remove_one(pool: list[int], code: int, ctx: str) -> None:
        try:
            pool.remove(code)
        except ValueError:
            raise ScenarioError(
                f"[{ruleset}] {ctx}: tile {fmt_tile(code)} not in hand "
                f"({[fmt_tile(x) for x in pool]})"
            ) from None

    # Initial dealer draw (live draw 0)
    draw_live(dealer)

    def next_non_assert_is_window(idx: int) -> bool:
        for j in range(idx + 1, len(steps)):
            t = steps[j]["type"]
            if t.startswith("assert_"):
                continue
            return t == "window"
        return False

    for i, step in enumerate(steps):
        stype = step["type"]
        if stype.startswith("assert_"):
            continue
        if round_ended:
            raise ScenarioError(f"[{ruleset}] step {i} occurs after round already ended")

        if stype == "auto_tsumogiri":
            if pending_kan is not None or awaiting_riichi_discard:
                raise ScenarioError(f"[{ruleset}] auto_tsumogiri during pending kan/riichi")
            for _ in range(step["count"]):
                if drawn[cur_seat] is None:
                    raise ScenarioError(f"[{ruleset}] auto_tsumogiri: seat {cur_seat} has no drawn tile")
                last_discard = (cur_seat, drawn[cur_seat])
                drawn[cur_seat] = None
                if live_remaining() == 0:
                    round_ended = True
                    break
                cur_seat = (cur_seat + 1) % 4
                draw_live(cur_seat)
            continue

        if stype == "window":
            ans = step["answers"]
            if pending_kan is not None:
                kseat, ktype, _ = pending_kan
                for s_str, act in ans.items():
                    if act["action"] not in ("ron", "pass"):
                        raise ScenarioError(
                            f"[{ruleset}] step {i}: robbing window only allows ron/pass, got {act['action']}"
                        )
                rons = [int(s) for s, a in ans.items() if a["action"] == "ron"]
                if rons:
                    round_ended = True
                    pending_kan = None
                else:
                    # Kan completes
                    pending_kan = None
                    draw_rinshan(kseat)
                    cur_seat = kseat
                continue

            if last_discard is None:
                raise ScenarioError(f"[{ruleset}] step {i}: window without preceding discard or kan")
            dseat, dtile = last_discard
            rons = [int(s) for s, a in ans.items() if a["action"] == "ron"]
            if rons:
                round_ended = True
                continue

            # Check pon / daiminkan / chi priority
            pon_or_kan = [(int(s), a) for s, a in ans.items() if a["action"] in ("pon", "daiminkan")]
            chis = [(int(s), a) for s, a in ans.items() if a["action"] == "chi"]
            if len(pon_or_kan) > 1:
                raise ScenarioError(f"[{ruleset}] step {i}: multiple pon/daiminkan in one window")
            if pon_or_kan:
                cseat, act = pon_or_kan[0]
                if cseat == dseat:
                    raise ScenarioError(f"[{ruleset}] step {i}: discarder cannot call own discard")
                if act["action"] == "pon":
                    for code in act["_codes"]:
                        if tile_kind(code) != tile_kind(dtile):
                            raise ScenarioError(
                                f"[{ruleset}] step {i}: pon tile {fmt_tile(code)} != {fmt_tile(dtile)}"
                            )
                        remove_one(hands[cseat], code, f"step {i} seat {cseat} pon")
                    pons[cseat].append(tile_kind(dtile))
                    cur_seat = cseat
                    drawn[cseat] = None
                else:
                    # daiminkan: remove 3 tiles of tile_kind(dtile) from hands[cseat]
                    matching = [t for t in hands[cseat] if tile_kind(t) == tile_kind(dtile)]
                    if len(matching) < 3:
                        raise ScenarioError(
                            f"[{ruleset}] step {i}: seat {cseat} lacks 3 copies of {fmt_tile(tile_kind(dtile))} for daiminkan"
                        )
                    for code in matching[:3]:
                        hands[cseat].remove(code)
                    cur_seat = cseat
                    draw_rinshan(cseat)
                last_discard = None
            elif chis:
                if len(chis) > 1:
                    raise ScenarioError(f"[{ruleset}] step {i}: multiple chi in one window")
                cseat, act = chis[0]
                if cseat != (dseat + 1) % 4:
                    raise ScenarioError(
                        f"[{ruleset}] step {i}: only shimocha ({(dseat + 1) % 4}) may chi, got seat {cseat}"
                    )
                ks = sorted([tile_kind(c) for c in act["_codes"]] + [tile_kind(dtile)])
                if not (ks[0] < 27 and ks[0] // 9 == ks[2] // 9 and ks[1] == ks[0] + 1 and ks[2] == ks[0] + 2):
                    raise ScenarioError(f"[{ruleset}] step {i}: invalid chi sequence with {fmt_tile(dtile)}")
                for code in act["_codes"]:
                    remove_one(hands[cseat], code, f"step {i} seat {cseat} chi")
                cur_seat = cseat
                drawn[cseat] = None
                last_discard = None
            else:
                # All pass
                last_discard = None
                if live_remaining() == 0:
                    round_ended = True
                else:
                    cur_seat = (dseat + 1) % 4
                    draw_live(cur_seat)
            continue

        # Turn action
        seat = step["seat"]
        act = step["action"]
        if seat != cur_seat:
            raise ScenarioError(
                f"[{ruleset}] step {i}: expected turn for seat {cur_seat}, got seat {seat} ({act})"
            )

        if awaiting_riichi_discard and act != "discard":
            raise ScenarioError(f"[{ruleset}] step {i}: expected discard after riichi, got {act}")

        if act == "riichi":
            if drawn[seat] is None:
                raise ScenarioError(f"[{ruleset}] step {i}: cannot riichi without drawn tile")
            awaiting_riichi_discard = True
            continue

        if act in ("tsumo", "kyuushu"):
            if drawn[seat] is None:
                raise ScenarioError(f"[{ruleset}] step {i}: cannot {act} without drawn tile")
            round_ended = True
            continue

        if act == "ankan":
            if live_remaining() <= 0:
                raise ScenarioError(f"[{ruleset}] step {i}: cannot ankan with 0 live tiles")
            k = step["_code"]
            pool = list(hands[seat]) + ([drawn[seat]] if drawn[seat] is not None else [])
            matching = [t for t in pool if tile_kind(t) == k]
            if len(matching) != 4:
                raise ScenarioError(
                    f"[{ruleset}] step {i}: seat {seat} has {len(matching)} copies of {fmt_tile(k)} for ankan (need 4)"
                )
            # Remove all 4 from hand + drawn
            if drawn[seat] is not None:
                hands[seat].append(drawn[seat])
                drawn[seat] = None
            for t in matching:
                hands[seat].remove(t)
            if next_non_assert_is_window(i):
                pending_kan = (seat, "ankan", k)
            else:
                draw_rinshan(seat)
            continue

        if act == "kakan":
            if live_remaining() <= 0:
                raise ScenarioError(f"[{ruleset}] step {i}: cannot kakan with 0 live tiles")
            code = step["_code"]
            if tile_kind(code) not in pons[seat]:
                raise ScenarioError(
                    f"[{ruleset}] step {i}: seat {seat} has no pon of {fmt_tile(tile_kind(code))} for kakan"
                )
            if drawn[seat] is not None:
                hands[seat].append(drawn[seat])
                drawn[seat] = None
            remove_one(hands[seat], code, f"step {i} seat {seat} kakan")
            pons[seat].remove(tile_kind(code))
            if next_non_assert_is_window(i):
                pending_kan = (seat, "kakan", code)
            else:
                draw_rinshan(seat)
            continue

        if act == "discard":
            awaiting_riichi_discard = False
            if step["tsumogiri"]:
                if drawn[seat] is None:
                    raise ScenarioError(f"[{ruleset}] step {i}: tsumogiri with no drawn tile (after call?)")
                dtile = drawn[seat]
                if "_code" in step and step["_code"] != dtile:
                    raise ScenarioError(
                        f"[{ruleset}] step {i}: tsumogiri expected {fmt_tile(step['_code'])}, "
                        f"but seat {seat} drew {fmt_tile(dtile)}"
                    )
                drawn[seat] = None
            else:
                code = step["_code"]
                remove_one(hands[seat], code, f"step {i} seat {seat} discard")
                if drawn[seat] is not None:
                    hands[seat].append(drawn[seat])
                    drawn[seat] = None
                dtile = code

            last_discard = (seat, dtile)
            # If the next non-assert step is NOT a window, advance to next seat's draw
            # (unless this was the last live tile or the last step of the scenario).
            if not next_non_assert_is_window(i):
                has_more_actions = any(
                    not steps[j]["type"].startswith("assert_")
                    for j in range(i + 1, len(steps))
                )
                if has_more_actions:
                    if live_remaining() == 0:
                        round_ended = True
                    else:
                        cur_seat = (seat + 1) % 4
                        draw_live(cur_seat)


def strip_internal(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: strip_internal(v) for k, v in obj.items() if not k.startswith("_")}
    if isinstance(obj, list):
        return [strip_internal(x) for x in obj]
    return obj


def parse_scenario(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    sections: dict[str, list[str]] = {}
    cur_sec: str | None = None

    for lineno, raw in enumerate(text.splitlines(), 1):
        line = strip_comment(raw)
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            cur_sec = line[1:-1].strip()
            if cur_sec in sections:
                raise ScenarioError(f"{path}:{lineno}: duplicate section [{cur_sec}]")
            sections[cur_sec] = []
        else:
            if cur_sec is None:
                raise ScenarioError(f"{path}:{lineno}: content before first section")
            sections[cur_sec].append(line)

    def kv_pairs(sec: str) -> list[tuple[str, str]]:
        pairs: list[tuple[str, str]] = []
        for line in sections.get(sec, []):
            if ":" not in line:
                raise ScenarioError(f"{path}: [{sec}] line missing ':': {line!r}")
            k, v = line.split(":", 1)
            pairs.append((k.strip(), v.strip()))
        return pairs

    # [meta]
    if "meta" not in sections:
        raise ScenarioError(f"{path}: missing [meta]")
    meta_map = dict(kv_pairs("meta"))
    for req in ("name", "title", "rules", "source"):
        if req not in meta_map or not meta_map[req]:
            raise ScenarioError(f"{path}: [meta] missing {req!r}")
    if meta_map["name"] != path.stem:
        raise ScenarioError(f"{path}: meta.name {meta_map['name']!r} != filename stem {path.stem!r}")
    rules_raw = meta_map["rules"]
    if rules_raw == "both":
        rulesets = ["mahjongsoul", "tenhou"]
    elif rules_raw in VALID_RULESETS:
        rulesets = [rules_raw]
    else:
        raise ScenarioError(f"{path}: invalid meta.rules {rules_raw!r}")
    meta = {
        "name": meta_map["name"],
        "title": meta_map["title"],
        "rules": rulesets,
        "source": meta_map["source"],
        "unverified": meta_map.get("unverified") or None,
    }

    # [round]
    round_map = dict(kv_pairs("round"))
    game_length = round_map.get("game_length", "south")
    if game_length not in ("east", "south"):
        raise ScenarioError(f"{path}: invalid game_length {game_length!r}")
    wind = round_map.get("wind", "E")
    if wind not in VALID_WINDS:
        raise ScenarioError(f"{path}: invalid wind {wind!r}")
    rnd = parse_int(round_map.get("round", "1"), "round")
    if not 1 <= rnd <= 4:
        raise ScenarioError(f"{path}: round must be 1..4, got {rnd}")
    honba = parse_int(round_map.get("honba", "0"), "honba")
    if honba < 0:
        raise ScenarioError(f"{path}: honba must be >= 0")
    sticks = parse_int(round_map.get("sticks", "0"), "sticks")
    if sticks < 0:
        raise ScenarioError(f"{path}: sticks must be >= 0")
    dealer = parse_int(round_map.get("dealer", str((rnd - 1) % 4)), "dealer")
    if not 0 <= dealer <= 3:
        raise ScenarioError(f"{path}: dealer must be 0..3, got {dealer}")
    scores = parse_int_list(round_map.get("scores", "25000 25000 25000 25000"), 4, "scores")
    round_cfg = {
        "game_length": game_length,
        "wind": wind,
        "round": rnd,
        "honba": honba,
        "sticks": sticks,
        "dealer": dealer,
        "scores": scores,
    }

    # [wall]
    if "wall" not in sections:
        raise ScenarioError(f"{path}: missing [wall]")
    hands: list[list[int] | None] = [None, None, None, None]
    dora: list[int] = []
    ura: list[int] = []
    rinshan: list[int] = []
    live_slots: dict[int, int] = {}
    next_draw_idx = 0

    for k, v in kv_pairs("wall"):
        if k.startswith("hand "):
            s = parse_int(k[5:], "hand seat")
            if not 0 <= s <= 3:
                raise ScenarioError(f"{path}: invalid hand seat {s}")
            if hands[s] is not None:
                raise ScenarioError(f"{path}: duplicate hand {s}")
            hands[s] = parse_tiles(v)
        elif k == "dora":
            dora.extend(parse_tiles(v))
        elif k == "ura":
            ura.extend(parse_tiles(v))
        elif k == "rinshan":
            rinshan.extend(parse_tiles(v))
        elif k == "draws":
            for t in parse_tiles(v):
                if next_draw_idx in live_slots:
                    raise ScenarioError(f"{path}: live draw {next_draw_idx} specified twice")
                live_slots[next_draw_idx] = t
                next_draw_idx += 1
        elif k.startswith("draw_at "):
            idx = parse_int(k[8:], "draw_at")
            for t in parse_tiles(v):
                if idx in live_slots:
                    raise ScenarioError(f"{path}: live draw {idx} specified twice")
                live_slots[idx] = t
                idx += 1
        else:
            raise ScenarioError(f"{path}: unknown [wall] key {k!r}")

    for s in range(4):
        if hands[s] is None:
            raise ScenarioError(f"{path}: missing hand {s}")
    hands_final = [h for h in hands if h is not None]
    wall_codes = build_wall(dealer, hands_final, live_slots, rinshan, dora, ura)

    # [steps*] and [expect*]
    shared_steps = [parse_step(line) for line in sections.get("steps", [])]
    runs: dict[str, Any] = {}

    for rs in rulesets:
        rs_steps = list(shared_steps)
        if f"steps.{rs}" in sections:
            rs_steps.extend(parse_step(line) for line in sections[f"steps.{rs}"])
        if not rs_steps:
            raise ScenarioError(f"{path}: no steps for ruleset {rs}")

        if len(rulesets) == 2:
            exp_sec = f"expect.{rs}"
            if exp_sec not in sections:
                raise ScenarioError(f"{path}: rules=both requires [{exp_sec}]")
        else:
            exp_sec = f"expect.{rs}" if f"expect.{rs}" in sections else "expect"
            if exp_sec not in sections:
                raise ScenarioError(f"{path}: missing [{exp_sec}]")

        expect = parse_expect_section(kv_pairs(exp_sec), round_cfg)
        simulate_tile_flow(rs, dealer, hands_final, wall_codes, rs_steps)
        runs[rs] = {
            "steps": strip_internal(rs_steps),
            "expect": expect,
        }

    # Reject unknown sections
    allowed_secs = {"meta", "round", "wall", "steps", "expect"}
    for rs in rulesets:
        allowed_secs.add(f"steps.{rs}")
        allowed_secs.add(f"expect.{rs}")
    for sec in sections:
        if sec not in allowed_secs:
            raise ScenarioError(f"{path}: unexpected section [{sec}]")

    return {
        "meta": meta,
        "round": round_cfg,
        "wall": [fmt_tile(t) for t in wall_codes],
        "runs": runs,
    }


def collect_files(paths: list[str]) -> list[Path]:
    if not paths:
        paths = ["Scenarios"]
    files: list[Path] = []
    for p_str in paths:
        p = Path(p_str)
        if p.is_dir():
            files.extend(sorted(p.rglob("*.scn")))
        elif p.is_file():
            files.append(p)
        else:
            raise ScenarioError(f"path not found: {p}")
    return files


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Validate and expand scenario files.")
    parser.add_argument("--check", action="store_true", help="Validate all scenario files")
    parser.add_argument("--list", action="store_true", help="List scenarios and unverified tags")
    parser.add_argument("--json-dir", metavar="DIR",
                        help="Expand every scenario to DIR/<name>.json (a scenario that fails "
                             "validation is written as {\"name\", \"error\"})")
    parser.add_argument("paths", nargs="*", help="Scenario file(s) or directory")
    args = parser.parse_args(argv)

    if args.json_dir:
        out_dir = Path(args.json_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        errors = 0
        for f in collect_files(args.paths):
            try:
                data = parse_scenario(f)
            except ScenarioError as e:
                data = {"name": f.stem, "error": str(e)}
                errors += 1
            (out_dir / f"{f.stem}.json").write_text(json.dumps(data, indent=1), encoding="utf-8")
        return 1 if errors else 0

    if args.check:
        files = collect_files(args.paths)
        if not files:
            print("No .scn files found.", file=sys.stderr)
            return 1
        errors = 0
        unverified = 0
        for f in files:
            try:
                data = parse_scenario(f)
                if data["meta"]["unverified"]:
                    unverified += 1
            except ScenarioError as e:
                print(f"FAIL {f}: {e}", file=sys.stderr)
                errors += 1
        if errors:
            print(f"FAILED: {errors}/{len(files)} scenarios failed.", file=sys.stderr)
            return 1
        print(f"OK: {len(files)} scenarios passed ({unverified} unverified).")
        return 0

    if args.list:
        files = collect_files(args.paths)
        for f in files:
            data = parse_scenario(f)
            m = data["meta"]
            uv = f" [UNVERIFIED: {m['unverified']}]" if m["unverified"] else ""
            print(f"{m['name']} ({','.join(m['rules'])}){uv} — {m['title']}")
        return 0

    if len(args.paths) != 1:
        parser.error("provide a single scenario file to expand to JSON, or use --check")
    data = parse_scenario(Path(args.paths[0]))
    print(json.dumps(data, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
