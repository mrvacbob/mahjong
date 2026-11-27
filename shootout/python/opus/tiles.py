"""Tiles, tile lists and melds in mpsz notation (spec/formats.md, "Tiles" and "Melds")."""

from dataclasses import dataclass
from enum import Enum
from collections.abc import Iterable
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
    """The dora indicated: next kind, wrapping 9->1, N->E, red->white."""
    if indicator < 27:
        return indicator - 8 if indicator % 9 == 8 else indicator + 1
    if indicator <= NORTH:
        return EAST if indicator == NORTH else indicator + 1
    return HAKU if indicator == CHUN else indicator + 1


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


def format_tiles(tiles: Iterable[Tile], *, plain: bool = False) -> str:
    """Canonical tile list; `plain` writes reds as 5 (as in agari forms)."""
    out: list[str] = []
    last_suit = -1
    for t in sorted(tiles, key=_sort_key):
        s = suit(t.kind)
        if out and s != last_suit:
            out.append(SUITS[last_suit])
        last_suit = s
        out.append("0" if t.red and not plain else str(digit(t.kind)))
    if not out:
        return "-"
    out.append(SUITS[last_suit])
    return "".join(out)


def format_kinds(kinds: Iterable[Kind]) -> str:
    return format_tiles(Tile(k) for k in kinds)


def counts_of(tiles: Iterable[Tile]) -> Counts:
    c = [0] * NUM_KINDS
    for t in tiles:
        c[t.kind] += 1
    return c


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
        return self.type in (MeldType.DAIMINKAN, MeldType.SHOUMINKAN, MeldType.ANKAN)

    def __str__(self) -> str:
        return self.type.value + format_tiles(self.tiles)


_MELD_SIZE = {MeldType.CHI: 3, MeldType.PON: 3}


def parse_meld(text: str) -> Meld:
    mtype = MeldType(text[0])
    tiles = tuple(parse_tiles(text[1:]))
    kinds = sorted(t.kind for t in tiles)
    if len(tiles) != _MELD_SIZE.get(mtype, 4):
        raise ValueError(f"bad meld size: {text}")
    if mtype is MeldType.CHI:
        if is_honor(kinds[0]) or kinds != [kinds[0], kinds[0] + 1, kinds[0] + 2] or digit(kinds[0]) > 7:
            raise ValueError(f"bad chi: {text}")
    elif len(set(kinds)) != 1:
        raise ValueError(f"bad meld: {text}")
    return Meld(mtype, tiles)


def parse_melds(text: str) -> list[Meld]:
    return [] if text == "-" else [parse_meld(m) for m in text.split(",")]
