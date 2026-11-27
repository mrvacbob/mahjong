"""The `legal` op: what may this seat do right now (spec/formats.md, `legal`)."""

from dataclasses import dataclass, replace
from itertools import combinations

import hand as H
import scoring
from tiles import YAOCHU, Kind, Meld, MeldType, Tile, counts_of, digit, format_tiles, is_closed, is_honor, meld_tiles


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


def kuikae(called: Meld, took: Kind) -> set[Kind]:
    """Kinds that may not be discarded right after the call: the called kind, and for a chi
    completed at one end, the kind at the other end of the ryanmen shape (suji kuikae)."""
    banned = {took}
    if called.type is MeldType.CHI:
        low = called.kind
        if took == low and digit(low) <= 6:
            banned.add(low + 3)
        elif took == low + 2 and digit(low) >= 2:
            banned.add(low - 1)
    return banned


def after_call(s: Situation, called: Meld, took: Tile) -> list[str]:
    banned = kuikae(called, took.kind)
    return [f"discard:{t}" for t in _distinct(s.hand) if t.kind not in banned]


def _can_win(s: Situation, win: Tile, tsumo: bool) -> bool:
    ctx = replace(s.ctx, flags=s.ctx.flags | {"riichi"}) if s.riichi else s.ctx
    return isinstance(scoring.best(s.hand, s.melds, win, tsumo, ctx), scoring.Result)


def _tenpai_for_riichi(rest: list[Tile], melds: list[Meld]) -> bool:
    """Some kind with a copy outside this hand and melds would complete it (not just a fifth copy)."""
    visible = counts_of(rest + meld_tiles(melds))
    return any(visible[k] < 4 for k in H.winning_kinds(counts_of(rest)))


def _riichi_ankan_ok(s: Situation, counts: list[int], draw: Tile, k: Kind) -> bool:
    """In riichi: the kan must use the drawn tile and keep the same (structural) wait kinds."""
    if draw.kind != k:
        return False
    after_kan = list(counts)
    after_kan[k] = 0
    return H.winning_kinds(counts_of(s.hand)) == H.winning_kinds(after_kan)


def on_draw(s: Situation, draw: Tile) -> list[str]:
    full = s.hand + [draw]
    counts = counts_of(full)
    choices = _distinct(full)
    acts = [f"discard:{t}" for t in ([draw] if s.riichi else choices)]
    if _can_win(s, draw, tsumo=True):
        acts.append("tsumo")
    # A 14-tile hand above shanten 0 has no tenpai discard, so skip the per-discard scan.
    if is_closed(s.melds) and not s.riichi and s.wall >= 4 and H.shanten(counts, len(s.melds)).min <= 0:
        acts += [f"riichi:{t}" for t in choices if _tenpai_for_riichi(_remove(full, t), s.melds)]
    if s.wall >= 1 and s.kans < 4:
        acts += [f"ankan:{Tile(k)}" for k, n in enumerate(counts)
                 if n == 4 and (not s.riichi or _riichi_ankan_ok(s, counts, draw, k))]
        if not s.riichi:
            for m in s.melds:
                if m.type is MeldType.PON:
                    acts += [f"kakan:{t}" for t in choices if t.kind == m.kind]
    if s.first and sum(1 for k in YAOCHU if counts[k]) >= 9:
        acts.append("kyuushu")
    return acts


def on_discard(s: Situation, tile: Tile, source: str) -> list[str]:
    acts = ["pass"]
    robbing_added_kan = "chankan" in s.ctx.flags
    robbing_closed_kan = "ankan_rob" in s.ctx.flags
    if not s.furiten:
        if robbing_closed_kan:
            if H.is_kokushi(counts_of(s.hand + [tile])):
                acts.append("ron")
        elif _can_win(s, tile, tsumo=False):
            acts.append("ron")
    if s.riichi or s.wall < 1 or robbing_added_kan or robbing_closed_kan:
        return acts

    def call(mtype: MeldType, used: tuple[Tile, ...]) -> list[str]:
        """`chi:`/`pon:` with `used`, unless every discard left afterwards would be kuikae."""
        rest = replace(s, hand=_remove(s.hand, *used))
        if not after_call(rest, Meld(mtype, (*used, tile)), tile):
            return []
        return [f"{mtype.name.lower()}:{format_tiles(used)}"]

    k = tile.kind
    same = sorted(t for t in s.hand if t.kind == k)
    for pair in sorted(set(combinations(same, 2))):
        acts += call(MeldType.PON, pair)
    if len(same) >= 3 and s.kans < 4:
        acts.append(f"kan:{Tile(k)}")
    if source == "kamicha" and not is_honor(k):
        for da, db in ((-2, -1), (-1, 1), (1, 2)):
            if not (1 <= digit(k) + da and digit(k) + db <= 9):
                continue
            for ta in _distinct([t for t in s.hand if t.kind == k + da]):
                for tb in _distinct([t for t in s.hand if t.kind == k + db]):
                    acts += call(MeldType.CHI, (ta, tb))
    return acts
