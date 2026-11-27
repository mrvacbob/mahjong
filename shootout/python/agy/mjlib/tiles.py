"""Tile, hand, and meld representations, parsing, and canonical formatting."""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from enum import Enum

TileKind = int  # 0..33: 0..8=1m..9m, 9..17=1p..9p, 18..26=1s..9s, 27..33=1z..7z

SUITS: tuple[str, ...] = ("m", "p", "s", "z")
SUIT_INDEX: dict[str, int] = {"m": 0, "p": 1, "s": 2, "z": 3}

WIND_MAP: dict[str, TileKind] = {"E": 27, "S": 28, "W": 29, "N": 30}
DRAGONS: frozenset[TileKind] = frozenset({31, 32, 33})
WINDS: frozenset[TileKind] = frozenset({27, 28, 29, 30})
TERMINALS: frozenset[TileKind] = frozenset({0, 8, 9, 17, 18, 26})
YAOCHU: frozenset[TileKind] = TERMINALS | WINDS | DRAGONS
GREENS: frozenset[TileKind] = frozenset({19, 20, 21, 23, 25, 32})  # 23468s, 6z
RED_KINDS: frozenset[TileKind] = frozenset({4, 13, 22})  # 5m, 5p, 5s


@dataclass(frozen=True, slots=True)
class Tile:
    """A concrete tile, distinguishing red fives from plain fives."""

    kind: TileKind
    is_red: bool = False

    @property
    def suit(self) -> int:
        return self.kind // 9

    @property
    def rank(self) -> int:
        """0-based rank within suit (0..8 for suited, 0..6 for honors)."""
        return self.kind % 9

    @property
    def digit(self) -> str:
        return "0" if self.is_red else str(self.kind % 9 + 1)

    @property
    def sort_key(self) -> tuple[int, int]:
        return (self.kind, 0 if self.is_red else 1)

    def __str__(self) -> str:
        return f"{self.digit}{SUITS[self.kind // 9]}"


class MeldKind(Enum):
    CHI = "c"
    PON = "p"
    KAN = "k"  # daiminkan (open kan)
    KAKAN = "s"  # shouminkan (added kan)
    ANKAN = "a"  # closed kan


MELD_PREFIX: dict[str, MeldKind] = {m.value: m for m in MeldKind}


@dataclass(frozen=True, slots=True)
class Meld:
    """A declared meld (chi, pon, open kan, added kan, or closed kan)."""

    kind: MeldKind
    tiles: tuple[Tile, ...]

    @property
    def is_open(self) -> bool:
        return self.kind is not MeldKind.ANKAN

    @property
    def is_kan(self) -> bool:
        return self.kind in (MeldKind.KAN, MeldKind.KAKAN, MeldKind.ANKAN)

    @property
    def is_triplet(self) -> bool:
        return self.kind is not MeldKind.CHI

    @property
    def base_kind(self) -> TileKind:
        return self.tiles[0].kind

    @property
    def aka_count(self) -> int:
        return sum(1 for t in self.tiles if t.is_red)


def is_honor(k: TileKind) -> bool:
    return k >= 27


def is_terminal(k: TileKind) -> bool:
    return k in TERMINALS


def is_yaochu(k: TileKind) -> bool:
    return k in YAOCHU


def is_simple(k: TileKind) -> bool:
    return k < 27 and 1 <= (k % 9) <= 7


def kind_str(k: TileKind) -> str:
    return f"{k % 9 + 1}{SUITS[k // 9]}"


def dora_next(indicator: TileKind) -> TileKind:
    """Map a dora indicator kind to the dora tile kind."""
    if indicator < 27:
        return (indicator // 9) * 9 + (indicator % 9 + 1) % 9
    if indicator < 31:
        return 27 + (indicator - 27 + 1) % 4
    return 31 + (indicator - 31 + 1) % 3


def parse_tiles(spec: str) -> tuple[Tile, ...]:
    """Parse an mpsz tile list (or '-') into a tuple of Tiles."""
    if not spec or spec == "-":
        return ()
    out: list[Tile] = []
    digits: list[str] = []
    for ch in spec:
        if ch in "0123456789":
            digits.append(ch)
        elif ch in SUIT_INDEX:
            suit = SUIT_INDEX[ch]
            base = suit * 9
            for d in digits:
                if d == "0":
                    if suit == 3:
                        raise ValueError(f"red honor tile in {spec!r}")
                    out.append(Tile(base + 4, is_red=True))
                else:
                    rank = int(d) - 1
                    if suit == 3 and rank >= 7:
                        raise ValueError(f"invalid honor digit {d} in {spec!r}")
                    out.append(Tile(base + rank, is_red=False))
            digits.clear()
        else:
            raise ValueError(f"unexpected character {ch!r} in tile list {spec!r}")
    if digits:
        raise ValueError(f"trailing digits in tile list {spec!r}")
    return tuple(out)


def parse_tile(spec: str) -> Tile:
    tiles = parse_tiles(spec)
    if len(tiles) != 1:
        raise ValueError(f"expected single tile, got {spec!r}")
    return tiles[0]


def parse_meld(spec: str) -> Meld:
    if not spec or spec[0] not in MELD_PREFIX:
        raise ValueError(f"invalid meld {spec!r}")
    mkind = MELD_PREFIX[spec[0]]
    tiles = tuple(sorted(parse_tiles(spec[1:]), key=lambda t: t.sort_key))
    return Meld(mkind, tiles)


def parse_melds(spec: str) -> tuple[Meld, ...]:
    if not spec or spec == "-":
        return ()
    return tuple(parse_meld(part) for part in spec.split(","))


def tiles_to_counts(tiles: Iterable[Tile]) -> list[int]:
    counts = [0] * 34
    for t in tiles:
        counts[t.kind] += 1
    return counts


def format_kinds(kinds: Iterable[TileKind]) -> str:
    """Format an iterable of TileKinds as a canonical mpsz list (reds as 5)."""
    sorted_k = sorted(kinds)
    if not sorted_k:
        return "-"
    parts: list[str] = []
    cur_suit = -1
    buf: list[str] = []
    for k in sorted_k:
        s = k // 9
        if s != cur_suit:
            if buf:
                buf.append(SUITS[cur_suit])
                parts.append("".join(buf))
                buf = []
            cur_suit = s
        buf.append(str(k % 9 + 1))
    if buf:
        buf.append(SUITS[cur_suit])
        parts.append("".join(buf))
    return "".join(parts)


def format_tiles(tiles: Sequence[Tile]) -> str:
    """Format concrete Tiles in canonical mpsz order (0 before 5)."""
    if not tiles:
        return "-"
    sorted_t = sorted(tiles, key=lambda t: t.sort_key)
    parts: list[str] = []
    cur_suit = -1
    buf: list[str] = []
    for t in sorted_t:
        s = t.suit
        if s != cur_suit:
            if buf:
                buf.append(SUITS[cur_suit])
                parts.append("".join(buf))
                buf = []
            cur_suit = s
        buf.append(t.digit)
    if buf:
        buf.append(SUITS[cur_suit])
        parts.append("".join(buf))
    return "".join(parts)
