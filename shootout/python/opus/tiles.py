"""Tiles, tile lists and melds in mpsz notation (spec/formats.md, "Tiles" and "Melds")."""

from collections.abc import Iterable
from dataclasses import dataclass
from enum import Enum
from itertools import groupby
from typing import NamedTuple

# A tile *kind* is an int 0..33: 9*suit + digit-1 for m/p/s, 27..33 for 1z..7z.
type Kind = int
type Counts = list[int]

NUM_KINDS = 34
SUITS = "mpsz"
EAST, SOUTH, WEST, NORTH, HAKU, HATSU, CHUN = range(27, 34)
WINDS = range(EAST, NORTH + 1)
DRAGONS = range(HAKU, CHUN + 1)
WIND_LETTERS = {"E": EAST, "S": SOUTH, "W": WEST, "N": NORTH}


def suit(k: Kind) -> int:
    return k // 9


def digit(k: Kind) -> int:
    """1..9 for suited kinds, 1..7 for honors."""
    return k % 9 + 1


def suit_counts(counts: Counts, s: int) -> Counts:
    """The nine (or seven, for honors) counts of suit `s`."""
    return counts[9 * s : 9 * s + 9]


def is_honor(k: Kind) -> bool:
    return k >= 27


def is_terminal(k: Kind) -> bool:
    return k < 27 and k % 9 in (0, 8)


def is_yaochu(k: Kind) -> bool:
    return is_honor(k) or is_terminal(k)


def is_simple(k: Kind) -> bool:
    return not is_yaochu(k)


YAOCHU: tuple[Kind, ...] = tuple(k for k in range(NUM_KINDS) if is_yaochu(k))


class Tile(NamedTuple):
    """A physical tile: its kind and whether it is a red five."""

    kind: Kind
    red: bool = False

    def __str__(self) -> str:
        return format_tiles([self])


def dora_of(indicator: Kind) -> Kind:
    """The dora indicated: the next kind in its cycle (1-9 per suit, ESWN, white-green-red)."""
    if indicator < EAST:
        first, size = indicator - indicator % 9, 9
    elif indicator <= NORTH:
        first, size = EAST, 4
    else:
        first, size = HAKU, 3
    return first + (indicator - first + 1) % size


def parse_tiles(text: str) -> list[Tile]:
    """`123m406p77z` -> tiles in the order written. `-` is the empty list."""
    if text == "-":
        return []
    tiles: list[Tile] = []
    pending: list[str] = []
    for ch in text:
        if ch.isdigit():
            pending.append(ch)
            continue
        s = SUITS.index(ch)
        for d in pending:
            n = int(d)
            if s == 3 and not 1 <= n <= 7:
                raise ValueError(f"bad honor {d}z")
            tiles.append(Tile(9 * s + (4 if n == 0 else n - 1), n == 0))
        pending = []
    if pending:
        raise ValueError(f"tile list without suit: {text}")
    return tiles


def parse_tile(text: str) -> Tile:
    tiles = parse_tiles(text)
    if len(tiles) != 1:
        raise ValueError(f"expected one tile: {text}")
    return tiles[0]


def _sort_key(t: Tile) -> tuple[int, bool]:
    return (t.kind, not t.red)


def format_tiles(tiles: Iterable[Tile]) -> str:
    """Canonical tile list: sorted, one suit letter per run, reds as 0 just before 5."""
    by_suit = groupby(sorted(tiles, key=_sort_key), key=lambda t: suit(t.kind))
    text = "".join("".join("0" if t.red else str(digit(t.kind)) for t in run) + SUITS[s]
                   for s, run in by_suit)
    return text or "-"


def format_kinds(kinds: Iterable[Kind]) -> str:
    return format_tiles(Tile(k) for k in kinds)


def counts_of(tiles: Iterable[Tile]) -> Counts:
    c = [0] * NUM_KINDS
    for t in tiles:
        c[t.kind] += 1
    return c


def kinds_in(counts: Counts) -> list[Kind]:
    """The distinct kinds present, in order."""
    return [k for k in range(NUM_KINDS) if counts[k]]


class MeldType(Enum):
    CHI = "c"
    PON = "p"
    DAIMINKAN = "k"
    SHOUMINKAN = "s"
    ANKAN = "a"


@dataclass(frozen=True, slots=True)
class Meld:
    type: MeldType
    tiles: tuple[Tile, ...]

    @property
    def kind(self) -> Kind:
        return min(t.kind for t in self.tiles)

    @property
    def is_open(self) -> bool:
        return self.type is not MeldType.ANKAN

    @property
    def is_kan(self) -> bool:
        return self.type not in (MeldType.CHI, MeldType.PON)

    def __str__(self) -> str:
        return self.type.value + format_tiles(self.tiles)


def starts_sequence(k: Kind) -> bool:
    """`k`, `k+1`, `k+2` is a sequence: numbered, digit 1..7."""
    return not is_honor(k) and digit(k) <= 7


def parse_meld(text: str) -> Meld:
    m = Meld(MeldType(text[0]), tuple(parse_tiles(text[1:])))
    kinds = sorted(t.kind for t in m.tiles)
    if len(kinds) != (4 if m.is_kan else 3):
        raise ValueError(f"bad meld size: {text}")
    if m.type is MeldType.CHI:
        if not starts_sequence(kinds[0]) or kinds != [kinds[0], kinds[0] + 1, kinds[0] + 2]:
            raise ValueError(f"bad chi: {text}")
    elif len(set(kinds)) != 1:
        raise ValueError(f"bad meld: {text}")
    return m


def parse_melds(text: str) -> list[Meld]:
    return [] if text == "-" else [parse_meld(m) for m in text.split(",")]


def meld_tiles(melds: Iterable[Meld]) -> list[Tile]:
    return [t for m in melds for t in m.tiles]


def is_closed(melds: Iterable[Meld]) -> bool:
    """No open meld (an ankan keeps the hand closed)."""
    return not any(m.is_open for m in melds)
