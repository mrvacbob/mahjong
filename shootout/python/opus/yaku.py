"""The yaku and yakuman of spec/rules.md section 2, one predicate per table row.

Each predicate takes one interpretation of a win (`Win`) and says whether the yaku
applies. The decorator carries the han from the rule table; `open=0` means
closed only, and the registry checks that, so a predicate never repeats it.
"""

from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass
from enum import Enum, auto
from functools import cached_property

from hand import Group, Shape
from tiles import (
    CHUN, DRAGONS, HATSU, HAKU, WINDS, Counts, Kind,
    is_honor, is_simple, is_terminal, is_yaochu, kinds_in, parse_tiles, suit, suit_counts,
)


class FormType(Enum):
    STANDARD = auto()
    CHIITOI = auto()
    KOKUSHI = auto()


class Wait(Enum):
    RYANMEN = auto()
    KANCHAN = auto()
    PENCHAN = auto()
    TANKI = auto()
    SHANPON = auto()
    KOKUSHI_13 = auto()  # thirteen-sided kokushi


@dataclass(frozen=True)
class Win:
    """One reading of a winning hand: all groups (melds included), the wait, the context."""

    form: FormType
    groups: tuple[Group, ...]  # empty for kokushi; seven pairs for chiitoi
    wait: Wait
    win: Kind
    tsumo: bool
    closed: bool  # no open melds (an ankan keeps the hand closed)
    has_melds: bool
    flags: frozenset[str]
    seat: Kind
    round: Kind
    counts: Counts  # every tile of the hand, melds included

    @cached_property
    def kinds(self) -> list[Kind]:
        return kinds_in(self.counts)

    @cached_property
    def suits(self) -> set[int]:
        """Suits present; 3 is honors."""
        return {suit(k) for k in self.kinds}

    @cached_property
    def seqs(self) -> list[Group]:
        return [g for g in self.groups if g.shape is Shape.SEQ]

    @cached_property
    def pons(self) -> list[Group]:
        """Triplets and kans."""
        return [g for g in self.groups if g.is_set_of_one_kind]

    @cached_property
    def pair(self) -> Kind | None:
        pairs = [g.kind for g in self.groups if g.shape is Shape.PAIR]
        return pairs[0] if len(pairs) == 1 else None

    def has_pon(self, k: Kind) -> bool:
        return any(g.kind == k for g in self.pons)

    @cached_property
    def concealed_pons(self) -> int:
        return sum(1 for g in self.pons if not g.open)

    @cached_property
    def kans(self) -> int:
        return sum(1 for g in self.groups if g.shape is Shape.KAN)


type Predicate = Callable[[Win], bool]


@dataclass(frozen=True, slots=True)
class YakuDef:
    name: str
    closed: int  # han when closed, or the yakuman multiple
    open: int  # han when open; 0 = closed only
    test: Predicate

    def han(self, w: Win) -> int:
        """Han this yaku gives `w` (0 if it does not apply)."""
        value = self.closed if w.closed else self.open
        return value if value and self.test(w) else 0


YAKU: list[YakuDef] = []
YAKUMAN: list[YakuDef] = []


def _register(table: list[YakuDef], name: str, closed: int, open: int) -> Callable[[Predicate], Predicate]:
    def register(f: Predicate) -> Predicate:
        table.append(YakuDef(name, closed, open, f))
        return f
    return register


def yaku(name: str, *, closed: int, open: int = 0) -> Callable[[Predicate], Predicate]:
    return _register(YAKU, name, closed, open)


def yakuman(name: str, *, mult: int = 1, closed_only: bool = False) -> Callable[[Predicate], Predicate]:
    return _register(YAKUMAN, name, mult, 0 if closed_only else mult)


def is_yakuhai_kind(w: Win, k: Kind) -> bool:
    return k in DRAGONS or k == w.seat or k == w.round


def _in_all_three_suits(kinds: set[Kind]) -> bool:
    """The same number appears in m, p and s."""
    return any({d, d + 9, d + 18} <= kinds for d in range(9))


def _flag(name: str) -> Predicate:
    return lambda w: name in w.flags


# ---------------------------------------------------------------- 2.1 standard yaku
# Situational yaku come only from flags (spec/formats.md, `score`).

for _name, _closed, _open in (("riichi", 1, 0), ("double_riichi", 2, 0), ("ippatsu", 1, 0),
                              ("rinshan", 1, 1), ("chankan", 1, 1), ("haitei", 1, 1), ("houtei", 1, 1)):
    yaku(_name, closed=_closed, open=_open)(_flag(_name))


@yaku("tsumo", closed=1)
def menzen_tsumo(w: Win) -> bool:
    """Self-draw win with a closed hand."""
    return w.tsumo


@yaku("pinfu", closed=1)
def pinfu(w: Win) -> bool:
    """Closed; 4 sequences, non-yakuhai pair, ryanmen wait."""
    return (len(w.seqs) == 4 and w.pair is not None and not is_yakuhai_kind(w, w.pair)
            and w.wait is Wait.RYANMEN)


@yaku("tanyao", closed=1, open=1)
def tanyao(w: Win) -> bool:
    """Only 2-8 numbered tiles."""
    return all(is_simple(k) for k in w.kinds)


def _peikou(w: Win) -> int:
    """Number of pairs of identical sequences."""
    return sum(n // 2 for n in Counter(g.kind for g in w.seqs).values())


@yaku("iipeikou", closed=1)
def iipeikou(w: Win) -> bool:
    """2 identical sequences in the same suit. Does not stack with ryanpeikou."""
    return _peikou(w) == 1


for _name, _kind in (("haku", HAKU), ("hatsu", HATSU), ("chun", CHUN)):
    yaku(f"yakuhai_{_name}", closed=1, open=1)(lambda w, k=_kind: w.has_pon(k))


@yaku("yakuhai_seat", closed=1, open=1)
def yakuhai_seat(w: Win) -> bool:
    return w.has_pon(w.seat)


@yaku("yakuhai_round", closed=1, open=1)
def yakuhai_round(w: Win) -> bool:
    return w.has_pon(w.round)


@yaku("sanshoku", closed=2, open=1)
def sanshoku(w: Win) -> bool:
    """Same numerical sequence in all 3 suits."""
    return _in_all_three_suits({g.kind for g in w.seqs})


@yaku("sanshoku_doukou", closed=2, open=2)
def sanshoku_doukou(w: Win) -> bool:
    """Same numerical triplet/kan in all 3 suits."""
    return _in_all_three_suits({g.kind for g in w.pons})


@yaku("sanankou", closed=2, open=2)
def sanankou(w: Win) -> bool:
    """3 concealed triplets/ankans (a ron-completed triplet is open)."""
    return w.concealed_pons == 3


@yaku("ittsu", closed=2, open=1)
def ittsu(w: Win) -> bool:
    """123, 456, 789 in one suit."""
    starts = {g.kind for g in w.seqs}
    return any({9 * s, 9 * s + 3, 9 * s + 6} <= starts for s in range(3))


@yaku("chiitoi", closed=2)
def chiitoi(w: Win) -> bool:
    return w.form is FormType.CHIITOI


@yaku("toitoi", closed=2, open=2)
def toitoi(w: Win) -> bool:
    """4 triplets/kans + pair."""
    return len(w.pons) == 4


@yaku("chanta", closed=2, open=1)
def chanta(w: Win) -> bool:
    """Every set and the pair contain a terminal or honor; at least 1 sequence and 1 honor."""
    return (bool(w.seqs) and all(any(is_yaochu(k) for k in g.kinds) for g in w.groups)
            and any(is_honor(k) for k in w.kinds))


@yaku("sankantsu", closed=2, open=2)
def sankantsu(w: Win) -> bool:
    return w.kans == 3


@yaku("honroutou", closed=2, open=2)
def honroutou(w: Win) -> bool:
    """Only 1s, 9s and honors."""
    return all(is_yaochu(k) for k in w.kinds)


@yaku("shousangen", closed=2, open=2)
def shousangen(w: Win) -> bool:
    """2 dragon triplets/kans + a dragon pair."""
    return w.pair in DRAGONS and sum(1 for k in DRAGONS if w.has_pon(k)) == 2


@yaku("honitsu", closed=3, open=2)
def honitsu(w: Win) -> bool:
    """One numbered suit + honors (with no honors it is chinitsu instead)."""
    return 3 in w.suits and len(w.suits) == 2


@yaku("junchan", closed=3, open=2)
def junchan(w: Win) -> bool:
    """Every set and the pair contain a terminal; at least 1 sequence; no honors."""
    return bool(w.seqs) and all(any(is_terminal(k) for k in g.kinds) for g in w.groups)


@yaku("ryanpeikou", closed=3)
def ryanpeikou(w: Win) -> bool:
    """2 pairs of identical sequences."""
    return _peikou(w) == 2


@yaku("chinitsu", closed=6, open=5)
def chinitsu(w: Win) -> bool:
    """One numbered suit only."""
    return len(w.suits) == 1 and 3 not in w.suits


# ---------------------------------------------------------------- 2.2 yakuman


for _name in ("tenhou", "chiihou"):
    yakuman(_name, closed_only=True)(_flag(_name))


@yakuman("kokushi", closed_only=True)
def kokushi(w: Win) -> bool:
    """1 of each terminal/honor + 1 duplicate, single wait."""
    return w.form is FormType.KOKUSHI and w.wait is not Wait.KOKUSHI_13


@yakuman("kokushi_13", mult=2, closed_only=True)
def kokushi_13(w: Win) -> bool:
    """All 13 terminals/honors held, winning on any of them."""
    return w.form is FormType.KOKUSHI and w.wait is Wait.KOKUSHI_13


@yakuman("suuankou", closed_only=True)
def suuankou(w: Win) -> bool:
    """4 concealed triplets/ankans; a shanpon wait must be won by tsumo."""
    return w.concealed_pons == 4 and w.wait is not Wait.TANKI


@yakuman("suuankou_tanki", mult=2, closed_only=True)
def suuankou_tanki(w: Win) -> bool:
    """4 concealed triplets/ankans, waiting on the pair."""
    return w.concealed_pons == 4 and w.wait is Wait.TANKI


@yakuman("daisangen")
def daisangen(w: Win) -> bool:
    return all(w.has_pon(k) for k in DRAGONS)


@yakuman("shousuushii")
def shousuushii(w: Win) -> bool:
    """3 wind triplets/kans + a wind pair."""
    return w.pair in WINDS and sum(1 for k in WINDS if w.has_pon(k)) == 3


@yakuman("daisuushii", mult=2)
def daisuushii(w: Win) -> bool:
    return all(w.has_pon(k) for k in WINDS)


@yakuman("tsuuiisou")
def tsuuiisou(w: Win) -> bool:
    """All winds and dragons."""
    return all(is_honor(k) for k in w.kinds)


@yakuman("chinroutou")
def chinroutou(w: Win) -> bool:
    """All 1s and 9s."""
    return all(is_terminal(k) for k in w.kinds)


GREEN = frozenset(t.kind for t in parse_tiles("23468s6z"))


@yakuman("ryuuiisou")
def ryuuiisou(w: Win) -> bool:
    return all(k in GREEN for k in w.kinds)


def _chuuren_counts(w: Win) -> Counts | None:
    """The suit's counts of a 1112345678999+X hand with no melds at all (not even ankan)."""
    if w.has_melds or not chinitsu(w):
        return None
    c = suit_counts(w.counts, w.suits.copy().pop())
    return c if c[0] >= 3 and c[8] >= 3 and all(c[1:8]) else None


def _junsei(w: Win) -> bool:
    """Exactly 1112345678999 before the win: the nine-sided wait."""
    c = _chuuren_counts(w)
    if c is None:
        return False
    c[w.win % 9] -= 1
    return c == [3, 1, 1, 1, 1, 1, 1, 1, 3]


@yakuman("chuuren", closed_only=True)
def chuuren(w: Win) -> bool:
    """1112345678999 + 1 extra tile in one suit, not the nine-sided wait."""
    return _chuuren_counts(w) is not None and not _junsei(w)


@yakuman("junsei_chuuren", mult=2, closed_only=True)
def junsei_chuuren(w: Win) -> bool:
    return _junsei(w)


@yakuman("suukantsu")
def suukantsu(w: Win) -> bool:
    return w.kans == 4
