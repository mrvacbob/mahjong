"""Hand structure: decomposition into groups, shanten, waits."""

from dataclasses import dataclass
from enum import IntEnum
from functools import cache

from tiles import NUM_KINDS, YAOCHU, Counts, Kind, Tile, format_tiles, is_honor


class Shape(IntEnum):
    # Value order is the agari print order for groups starting on the same tile.
    PAIR = 0
    SEQ = 1
    TRIPLET = 2
    KAN = 3


@dataclass(frozen=True, slots=True, order=True)
class Group:
    kind: Kind  # lowest kind in the group
    shape: Shape
    open: bool = False

    @property
    def kinds(self) -> tuple[Kind, ...]:
        match self.shape:
            case Shape.SEQ:
                return (self.kind, self.kind + 1, self.kind + 2)
            case Shape.PAIR:
                return (self.kind,) * 2
            case Shape.TRIPLET:
                return (self.kind,) * 3
            case Shape.KAN:
                return (self.kind,) * 4

    @property
    def is_set_of_one_kind(self) -> bool:
        """Triplet or kan: what toitoi, yakuhai, sanankou count."""
        return self.shape in (Shape.TRIPLET, Shape.KAN)

    def __str__(self) -> str:
        return format_tiles(Tile(k) for k in self.kinds)


type Form = tuple[Group, ...]


# ---------------------------------------------------------------- decomposition


def standard_forms(counts: Counts) -> list[Form]:
    """Every way to split `counts` into sets plus exactly one pair (sorted groups, no duplicates)."""
    if sum(counts) % 3 != 2:
        return []
    c = list(counts)
    found: set[Form] = set()
    groups: list[Group] = []

    def go(start: int, have_pair: bool) -> None:
        i = start
        while i < NUM_KINDS and c[i] == 0:
            i += 1
        if i == NUM_KINDS:
            if have_pair:
                found.add(tuple(sorted(groups)))
            return
        if not have_pair and c[i] >= 2:
            c[i] -= 2
            groups.append(Group(i, Shape.PAIR))
            go(i, True)
            groups.pop()
            c[i] += 2
        if c[i] >= 3:
            c[i] -= 3
            groups.append(Group(i, Shape.TRIPLET))
            go(i, have_pair)
            groups.pop()
            c[i] += 3
        if not is_honor(i) and i % 9 <= 6 and c[i + 1] and c[i + 2]:
            for k in (i, i + 1, i + 2):
                c[k] -= 1
            groups.append(Group(i, Shape.SEQ))
            go(i, have_pair)
            groups.pop()
            for k in (i, i + 1, i + 2):
                c[k] += 1

    go(0, False)
    return sorted(found)


def is_chiitoi(counts: Counts) -> bool:
    """Seven distinct pairs (a four-of-a-kind is not two pairs)."""
    return sum(counts) == 14 and sum(1 for n in counts if n == 2) == 7


def is_kokushi(counts: Counts) -> bool:
    return sum(counts) == 14 and all(counts[k] >= 1 for k in YAOCHU) and sum(counts[k] for k in YAOCHU) == 14


def is_complete(counts: Counts, n_melds: int) -> bool:
    if n_melds == 0 and (is_chiitoi(counts) or is_kokushi(counts)):
        return True
    return bool(standard_forms(counts))


# ---------------------------------------------------------------- shanten

type Options = dict[tuple[int, int], int]  # (sets, pair) -> best partial count


def _merge(into: Options, sets: int, pair: int, partials: int) -> None:
    key = (sets, pair)
    if into.get(key, -1) < partials:
        into[key] = partials


@cache
def _suit_options(c: tuple[int, ...], honors: bool) -> Options:
    """Achievable (sets, pair) -> max partials for one suit's counts."""
    i = next((j for j, n in enumerate(c) if n), None)
    if i is None:
        return {(0, 0): 0}
    out: Options = {}

    def sub(delta: dict[int, int], ds: int, dp: int, dt: int) -> None:
        nc = list(c)
        for j, d in delta.items():
            nc[j] -= d
        for (s, p), t in _suit_options(tuple(nc), honors).items():
            if p + dp <= 1:
                _merge(out, s + ds, p + dp, t + dt)

    sub({i: 1}, 0, 0, 0)  # leave the tile isolated
    if c[i] >= 3:
        sub({i: 3}, 1, 0, 0)
    if c[i] >= 2:
        sub({i: 2}, 0, 1, 0)  # the pair
        sub({i: 2}, 0, 0, 1)  # a pair as a partial set
    if not honors:
        if i + 2 < 9 and c[i + 1] and c[i + 2]:
            sub({i: 1, i + 1: 1, i + 2: 1}, 1, 0, 0)
        if i + 1 < 9 and c[i + 1]:
            sub({i: 1, i + 1: 1}, 0, 0, 1)
        if i + 2 < 9 and c[i + 2]:
            sub({i: 1, i + 2: 1}, 0, 0, 1)
    return out


def standard_shanten(counts: Counts, n_melds: int) -> int:
    combined: Options = {(n_melds, 0): 0}
    for s in range(4):
        part = _suit_options(tuple(counts[9 * s : 9 * s + 9]), s == 3)
        nxt: Options = {}
        for (s1, p1), t1 in combined.items():
            for (s2, p2), t2 in part.items():
                if p1 + p2 <= 1:
                    _merge(nxt, s1 + s2, p1 + p2, t1 + t2)
        combined = nxt
    return min(8 - 2 * s - min(t, 4 - s) - p for (s, p), t in combined.items())


def chiitoi_shanten(counts: Counts) -> int:
    pairs = sum(1 for n in counts if n >= 2)
    kinds = sum(1 for n in counts if n)
    return 6 - pairs + max(0, 7 - kinds)


def kokushi_shanten(counts: Counts) -> int:
    kinds = sum(1 for k in YAOCHU if counts[k])
    pair = any(counts[k] >= 2 for k in YAOCHU)
    return 13 - kinds - pair


@dataclass(frozen=True, slots=True)
class Shanten:
    std: int
    chiitoi: int | None  # None when the hand has melds
    kokushi: int | None

    @property
    def min(self) -> int:
        return min(x for x in (self.std, self.chiitoi, self.kokushi) if x is not None)


def shanten(counts: Counts, n_melds: int) -> Shanten:
    if n_melds:
        return Shanten(standard_shanten(counts, n_melds), None, None)
    return Shanten(standard_shanten(counts, 0), chiitoi_shanten(counts), kokushi_shanten(counts))


@dataclass(frozen=True, slots=True)
class Waits:
    shanten: int
    kinds: list[Kind]
    count: int


def waits(counts: Counts, n_melds: int, visible: Counts) -> Waits:
    """Kinds with a live copy (4 - visible) whose draw lowers min shanten."""
    base = shanten(counts, n_melds).min
    kinds: list[Kind] = []
    for k in range(NUM_KINDS):
        if visible[k] >= 4:
            continue
        counts[k] += 1
        if shanten(counts, n_melds).min < base:
            kinds.append(k)
        counts[k] -= 1
    return Waits(base, kinds, sum(4 - visible[k] for k in kinds))


def structural_waits(counts: Counts, n_melds: int) -> set[Kind]:
    """Kinds that complete the hand, ignoring how many copies exist."""
    out: set[Kind] = set()
    for k in range(NUM_KINDS):
        counts[k] += 1
        if is_complete(counts, n_melds):
            out.add(k)
        counts[k] -= 1
    return out
