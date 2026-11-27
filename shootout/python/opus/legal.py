"""The `legal` op: what may this seat do right now (spec/formats.md, `legal`)."""

from dataclasses import dataclass, replace
from itertools import combinations

import hand as H
import scoring
from tiles import YAOCHU, Kind, Meld, MeldType, Tile, counts_of, digit, format_tiles, is_honor


@dataclass(frozen=True, slots=True)
class Situation:
    hand: list[Tile]
    melds: list[Meld]
    ctx: scoring.Context
    riichi: bool = False
    furiten: bool = False
    wall: int = 70
    first: bool = False
    kans: int = 0


def _remove(tiles: list[Tile], *gone: Tile) -> list[Tile]:
    rest = list(tiles)
    for t in gone:
        rest.remove(t)
    return rest


def _distinct(tiles: list[Tile]) -> list[Tile]:
    return sorted(set(tiles))


def kuikae(took: Kind, used: tuple[Kind, Kind] | None) -> set[Kind]:
    """Kinds that may not be discarded after calling `took` (with `used` from hand, for a chi)."""
    banned = {took}
    if used is not None:
        a, b = sorted(used)
        if b - a == 1:
            if took == a - 1 and digit(b) < 9:
                banned.add(b + 1)
            elif took == b + 1 and digit(a) > 1:
                banned.add(a - 1)
    return banned


def _can_win(s: Situation, win: Tile, tsumo: bool) -> bool:
    ctx = replace(s.ctx, flags=s.ctx.flags | {"riichi"}) if s.riichi else s.ctx
    try:
        scoring.best(s.hand, s.melds, win, tsumo, ctx)
    except scoring.ScoreError:
        return False
    return True


def _n_visible(tiles: list[Tile], melds: list[Meld]) -> list[int]:
    return counts_of(tiles + [t for m in melds for t in m.tiles])


def _tenpai_for_riichi(rest: list[Tile], melds: list[Meld]) -> bool:
    w = H.waits(counts_of(rest), len(melds), _n_visible(rest, melds))
    return w.shanten == 0 and w.count > 0


def on_draw(s: Situation, draw: Tile) -> list[str]:
    full = s.hand + [draw]
    counts = counts_of(full)
    acts: list[str] = []
    discards = [draw] if s.riichi else _distinct(full)
    acts += [f"discard:{t}" for t in discards]
    if _can_win(s, draw, tsumo=True):
        acts.append("tsumo")
    closed = not any(m.is_open for m in s.melds)
    if closed and not s.riichi and s.wall >= 4:
        acts += [f"riichi:{t}" for t in _distinct(full) if _tenpai_for_riichi(_remove(full, t), s.melds)]
    if s.wall >= 1 and s.kans < 4:
        for k in range(len(counts)):
            if counts[k] == 4 and (not s.riichi or _riichi_ankan_ok(s, draw, k)):
                acts.append(f"ankan:{Tile(k)}")
        if not s.riichi:
            for m in s.melds:
                if m.type is MeldType.PON:
                    acts += [f"kakan:{t}" for t in _distinct(full) if t.kind == m.kind]
    if s.first and sum(1 for k in YAOCHU if counts[k]) >= 9:
        acts.append("kyuushu")
    return acts


def _riichi_ankan_ok(s: Situation, draw: Tile, k: Kind) -> bool:
    """In riichi: the kan must use the drawn tile and keep the same wait kinds."""
    if draw.kind != k:
        return False
    before = H.structural_waits(counts_of(s.hand), len(s.melds))
    after_counts = counts_of(s.hand + [draw])
    after_counts[k] = 0
    return before == H.structural_waits(after_counts, len(s.melds) + 1)


def on_discard(s: Situation, tile: Tile, source: str) -> list[str]:
    acts = ["pass"]
    robbing_added_kan = "chankan" in s.ctx.flags
    robbing_closed_kan = "ankan_rob" in s.ctx.flags
    if not s.furiten:
        if robbing_closed_kan:
            if not s.melds and H.is_kokushi(counts_of(s.hand + [tile])):
                acts.append("ron")
        elif _can_win(s, tile, tsumo=False):
            acts.append("ron")
    if s.riichi or s.wall < 1 or robbing_added_kan or robbing_closed_kan:
        return acts
    k = tile.kind
    same = [t for t in s.hand if t.kind == k]
    if len(same) >= 2:
        for pair in sorted(set(combinations(sorted(same), 2))):
            if _has_allowed_discard(_remove(s.hand, *pair), kuikae(k, None)):
                acts.append(f"pon:{format_tiles(pair)}")
    if len(same) >= 3 and s.kans < 4:
        acts.append(f"kan:{Tile(k)}")
    if source == "kamicha" and not is_honor(k):
        for da, db in ((-2, -1), (-1, 1), (1, 2)):
            a, b = k + da, k + db
            if not (1 <= digit(k) + da and digit(k) + db <= 9):
                continue
            for ta in _distinct([t for t in s.hand if t.kind == a]):
                for tb in _distinct([t for t in s.hand if t.kind == b]):
                    if _has_allowed_discard(_remove(s.hand, ta, tb), kuikae(k, (a, b))):
                        acts.append(f"chi:{format_tiles([ta, tb])}")
    return acts


def _has_allowed_discard(rest: list[Tile], banned: set[Kind]) -> bool:
    return any(t.kind not in banned for t in rest)


def after_call(s: Situation, called: Meld, took: Tile) -> list[str]:
    if called.type is MeldType.CHI:
        used = [t.kind for t in called.tiles]
        used.remove(took.kind)
        banned = kuikae(took.kind, (used[0], used[1]))
    else:
        banned = kuikae(took.kind, None)
    return [f"discard:{t}" for t in _distinct(s.hand) if t.kind not in banned]
