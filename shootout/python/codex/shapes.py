from __future__ import annotations


from collections.abc import Iterable, Iterator
from dataclasses import dataclass
from functools import lru_cache
from typing import NamedTuple

type Tiles = tuple[int, ...]
type Counts = tuple[int, ...]

SUITS = "mpsz"
KINDS = range(34)
TERMINALS = frozenset((0, 8, 9, 17, 18, 26))
HONORS = frozenset(range(27, 34))
ORPHANS = TERMINALS | HONORS
DRAGONS = frozenset(range(31, 34))
WINDS = frozenset(range(27, 31))
WIDTHS = (9, 9, 9, 7)


def kind(tile: int) -> int:
    return tile if tile < 34 else 4 + 9 * (tile - 34)


def parse_tiles(value: str) -> Tiles:
    if value == "-":
        return ()
    tiles: list[int] = []
    digits = ""
    for char in value:
        if char in "0123456789":
            digits += char
            continue
        suit = SUITS.index(char)
        if not digits:
            raise ValueError(value)
        for digit in map(int, digits):
            if suit == 3 and not 1 <= digit <= 7:
                raise ValueError(value)
            tiles.append(suit * 9 + digit - 1 if digit else 34 + suit)
        digits = ""
    if digits:
        raise ValueError(value)
    return tuple(tiles)


def parse_tile(value: str) -> int:
    tile, = parse_tiles(value)
    return tile


def tile_text(tiles: Iterable[int]) -> str:
    ordered = sorted(tiles, key=lambda tile: (kind(tile), tile < 34))
    digits = [""] * 4
    for tile in ordered:
        base = kind(tile)
        digits[base // 9] += str(base % 9 + 1) if tile < 34 else "0"
    return "".join(part + suit for part, suit in zip(digits, SUITS) if part) or "-"


def counts(tiles: Iterable[int]) -> Counts:
    result = [0] * 34
    for tile in tiles:
        result[kind(tile)] += 1
    return tuple(result)


def changed(state: Counts, tile: int, delta: int) -> Counts:
    return state[:tile] + (state[tile] + delta,) + state[tile + 1:]


def run_start(tile: int) -> bool:
    return tile < 27 and tile % 9 <= 6


class Group(NamedTuple):
    first: int
    shape: str

    def tiles(self) -> Tiles:
        match self.shape:
            case "sequence":
                return (self.first, self.first + 1, self.first + 2)
            case "pair":
                return (self.first,) * 2
            case "triplet":
                return (self.first,) * 3
            case "kan":
                return (self.first,) * 4
            case _:
                raise ValueError(self.shape)


type Form = tuple[Group, ...]


@dataclass(frozen=True, slots=True)
class Meld:
    call: str
    tiles: Tiles

    @property
    def group(self) -> Group:
        shape = {"c": "sequence", "p": "triplet", "k": "kan", "s": "kan", "a": "kan"}
        return Group(min(map(kind, self.tiles)), shape[self.call])

    @classmethod
    def parse(cls, value: str) -> Meld:
        meld = cls(value[0], parse_tiles(value[1:]))
        if meld.call == "c" and not run_start(meld.group.first):
            raise ValueError(value)
        if counts(meld.tiles) != counts(meld.group.tiles()):
            raise ValueError(value)
        return meld


@dataclass(frozen=True, slots=True)
class Hand:
    tiles: Tiles
    melds: tuple[Meld, ...]

    @property
    def closed(self) -> bool:
        return all(meld.call == "a" for meld in self.melds)

    def all_tiles(self) -> Tiles:
        return self.tiles + tuple(tile for meld in self.melds for tile in meld.tiles)


@lru_cache(maxsize=65536)
def forms(state: Counts, sets: int, head: bool = True) -> tuple[Form, ...]:
    first = next((i for i, n in enumerate(state) if n), -1)
    if first == -1:
        return ((),) if sets == 0 and not head else ()
    if sets < 0:
        return ()
    result: list[Form] = []
    if head and state[first] >= 2:
        rest = changed(state, first, -2)
        result.extend((Group(first, "pair"), *tail) for tail in forms(rest, sets, False))
    if sets and run_start(first) and state[first + 1] and state[first + 2]:
        rest = tuple(n - 1 if first <= i <= first + 2 else n for i, n in enumerate(state))
        result.extend((Group(first, "sequence"), *tail) for tail in forms(rest, sets - 1, head))
    if sets and state[first] >= 3:
        rest = changed(state, first, -3)
        result.extend((Group(first, "triplet"), *tail) for tail in forms(rest, sets - 1, head))
    return tuple(result)


def seven_pairs(state: Counts) -> bool:
    return sum(state) == 14 and state.count(2) == 7


def kokushi(state: Counts) -> bool:
    return all(state[i] for i in ORPHANS) and sum(state[i] for i in ORPHANS) == sum(state) == 14


def complete(state: Counts, melds: int) -> bool:
    return bool(forms(state, 4 - melds)) or (
        melds == 0 and (seven_pairs(state) or kokushi(state))
    )


def agari(hand: Hand) -> str:
    state = counts(hand.tiles)
    standard = forms(state, 4 - len(hand.melds))
    names = {",".join(tile_text(group.tiles()) for group in sorted(form)) for form in standard}
    if not hand.melds:
        if seven_pairs(state):
            names.add("chiitoi")
        if kokushi(state):
            names.add("kokushi")
    return "win=1 forms=" + ";".join(sorted(names)) if names else "win=0"


class Partition(NamedTuple):
    sets: int
    head: int
    partials: int


def merge_profiles(left: tuple[Partition, ...], right: tuple[Partition, ...]) -> tuple[Partition, ...]:
    best: dict[tuple[int, int], int] = {}
    for a in left:
        for b in right:
            sets, head = a.sets + b.sets, a.head + b.head
            if sets <= 4 and head <= 1:
                key = (sets, head)
                best[key] = max(best.get(key, 0), min(4 - sets, a.partials + b.partials))
    return tuple(Partition(sets, head, partials) for (sets, head), partials in best.items())


@lru_cache(maxsize=65536)
def profile(state: Counts, numbered: bool) -> tuple[Partition, ...]:
    first = next((i for i, n in enumerate(state) if n), -1)
    if first == -1:
        return (Partition(0, 0, 0),)
    alone = changed(state, first, -1)
    best = {(p.sets, p.head): p.partials for p in profile(alone, numbered)}

    def consider(rest: Counts, sets: int, head: int, partials: int) -> None:
        for p in profile(rest, numbered):
            group_count = p.sets + sets
            head_count = p.head + head
            if group_count <= 4 and head_count <= 1:
                key = (group_count, head_count)
                best[key] = max(best.get(key, 0), min(4 - group_count, p.partials + partials))

    if state[first] >= 2:
        pair = changed(alone, first, -1)
        consider(pair, 0, 1, 0)
        consider(pair, 0, 0, 1)
        if state[first] >= 3:
            consider(changed(pair, first, -1), 1, 0, 0)
    if numbered:
        neighbors = [
            tile for tile in range(first + 1, min(first + 3, 9)) if state[tile]
        ]
        for tile in neighbors:
            consider(changed(alone, tile, -1), 0, 0, 1)
        if len(neighbors) == 2:
            consider(changed(changed(alone, first + 1, -1), first + 2, -1), 1, 0, 0)
    return tuple(Partition(sets, head, partials) for (sets, head), partials in best.items())


class Shanten(NamedTuple):
    standard: int
    chiitoi: int | None
    kokushi: int | None

    @property
    def best(self) -> int:
        return min(n for n in self if n is not None)

    def render(self) -> str:
        chiitoi = "x" if self.chiitoi is None else str(self.chiitoi)
        kokushi = "x" if self.kokushi is None else str(self.kokushi)
        return f"std={self.standard} chiitoi={chiitoi} kokushi={kokushi} min={self.best}"


@lru_cache(maxsize=32768)
def shanten(state: Counts, melds: int) -> Shanten:
    combined = (Partition(melds, 0, 0),)
    start = 0
    for width in WIDTHS:
        combined = merge_profiles(combined, profile(state[start:start + width], width == 9))
        start += width
    standard = min(8 - 2 * p.sets - p.partials - p.head for p in combined)
    if melds:
        return Shanten(standard, None, None)
    distinct = 34 - state.count(0)
    pairs = sum(n >= 2 for n in state)
    chiitoi = 6 - pairs + max(0, 7 - distinct)
    kokushi_distance = 13 - sum(state[i] > 0 for i in ORPHANS) - any(
        state[i] >= 2 for i in ORPHANS
    )
    return Shanten(standard, chiitoi, kokushi_distance)


def winning_kinds(hand: Hand, *, structural: bool = False) -> Iterator[int]:
    state = counts(hand.tiles)
    held = counts(hand.all_tiles())
    for tile in KINDS:
        if (structural or held[tile] < 4) and complete(changed(state, tile, 1), len(hand.melds)):
            yield tile


def waits(hand: Hand) -> str:
    state = counts(hand.tiles)
    held = counts(hand.all_tiles())
    melds = len(hand.melds)
    distance = shanten(state, melds).best
    if distance == 0:
        improvements = tuple(winning_kinds(hand))
    else:
        improvements = tuple(
            k for k in KINDS
            if held[k] < 4 and shanten(changed(state, k, 1), melds).best < distance
        )
    live = sum(4 - held[k] for k in improvements)
    return f"shanten={distance} tiles={tile_text(improvements)} count={live}"
