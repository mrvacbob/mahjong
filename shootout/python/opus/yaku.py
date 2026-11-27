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
    CHUN, DRAGONS, HATSU, HAKU, NUM_KINDS, WINDS, Counts, Kind,
    digit, is_honor, is_simple, is_terminal, is_yaochu, suit,
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
        return [k for k in range(NUM_KINDS) if self.counts[k]]

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


@dataclass(frozen=True, slots=True)
class YakuDef:
    name: str
    closed: int  # han when closed, or the yakuman multiple
    open: int  # han when open; 0 = closed only
    test: Callable[[Win], bool]
    yakuman: bool

    def han(self, w: Win) -> int:
        """Han this yaku gives `w` (0 if it does not apply)."""
        value = self.closed if w.closed else self.open
        return value if value and self.test(w) else 0


YAKU: list[YakuDef] = []
YAKUMAN: list[YakuDef] = []


def yaku(name: str, *, closed: int, open: int = 0) -> Callable[[Callable[[Win], bool]], Callable[[Win], bool]]:
    def register(f: Callable[[Win], bool]) -> Callable[[Win], bool]:
        YAKU.append(YakuDef(name, closed, open, f, False))
        return f
    return register


def yakuman(name: str, *, mult: int = 1, closed_only: bool = False) -> Callable[[Callable[[Win], bool]], Callable[[Win], bool]]:
    def register(f: Callable[[Win], bool]) -> Callable[[Win], bool]:
        YAKUMAN.append(YakuDef(name, mult, 0 if closed_only else mult, f, True))
        return f
    return register


def is_yakuhai_kind(w: Win, k: Kind) -> bool:
    return k in DRAGONS or k == w.seat or k == w.round


def _groups_all(w: Win, pred: Callable[[Group], bool]) -> bool:
    return w.form is FormType.STANDARD and all(pred(g) for g in w.groups)


# ---------------------------------------------------------------- 2.1 standard yaku
# Situational yaku come only from flags (spec/formats.md, `score`).


@yaku("riichi", closed=1)
def riichi(w: Win) -> bool:
    return "riichi" in w.flags


@yaku("double_riichi", closed=2)
def double_riichi(w: Win) -> bool:
    return "double_riichi" in w.flags


@yaku("ippatsu", closed=1)
def ippatsu(w: Win) -> bool:
    return "ippatsu" in w.flags


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


@yaku("yakuhai_haku", closed=1, open=1)
def yakuhai_haku(w: Win) -> bool:
    return w.has_pon(HAKU)


@yaku("yakuhai_hatsu", closed=1, open=1)
def yakuhai_hatsu(w: Win) -> bool:
    return w.has_pon(HATSU)


@yaku("yakuhai_chun", closed=1, open=1)
def yakuhai_chun(w: Win) -> bool:
    return w.has_pon(CHUN)


@yaku("yakuhai_seat", closed=1, open=1)
def yakuhai_seat(w: Win) -> bool:
    return w.has_pon(w.seat)


@yaku("yakuhai_round", closed=1, open=1)
def yakuhai_round(w: Win) -> bool:
    return w.has_pon(w.round)


@yaku("rinshan", closed=1, open=1)
def rinshan(w: Win) -> bool:
    return "rinshan" in w.flags


@yaku("chankan", closed=1, open=1)
def chankan(w: Win) -> bool:
    return "chankan" in w.flags


@yaku("haitei", closed=1, open=1)
def haitei(w: Win) -> bool:
    return "haitei" in w.flags


@yaku("houtei", closed=1, open=1)
def houtei(w: Win) -> bool:
    return "houtei" in w.flags


@yaku("sanshoku", closed=2, open=1)
def sanshoku(w: Win) -> bool:
    """Same numerical sequence in all 3 suits."""
    starts = {(suit(g.kind), digit(g.kind)) for g in w.seqs}
    return any({(s, d) for s in range(3)} <= starts for d in range(1, 8))


@yaku("sanshoku_doukou", closed=2, open=2)
def sanshoku_doukou(w: Win) -> bool:
    """Same numerical triplet/kan in all 3 suits."""
    pons = {(suit(g.kind), digit(g.kind)) for g in w.pons if not is_honor(g.kind)}
    return any({(s, d) for s in range(3)} <= pons for d in range(1, 10))


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
    return (_groups_all(w, lambda g: any(is_yaochu(k) for k in g.kinds))
            and bool(w.seqs) and any(is_honor(k) for k in w.kinds))


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
    suits = {suit(k) for k in w.kinds}
    return 3 in suits and len(suits) == 2


@yaku("junchan", closed=3, open=2)
def junchan(w: Win) -> bool:
    """Every set and the pair contain a terminal; at least 1 sequence; no honors."""
    return (_groups_all(w, lambda g: any(is_terminal(k) for k in g.kinds)) and bool(w.seqs))


@yaku("ryanpeikou", closed=3)
def ryanpeikou(w: Win) -> bool:
    """2 pairs of identical sequences."""
    return _peikou(w) == 2


@yaku("chinitsu", closed=6, open=5)
def chinitsu(w: Win) -> bool:
    """One numbered suit only."""
    suits = {suit(k) for k in w.kinds}
    return len(suits) == 1 and 3 not in suits


# ---------------------------------------------------------------- 2.2 yakuman


@yakuman("tenhou", closed_only=True)
def tenhou(w: Win) -> bool:
    return "tenhou" in w.flags


@yakuman("chiihou", closed_only=True)
def chiihou(w: Win) -> bool:
    return "chiihou" in w.flags


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


GREEN = frozenset({19, 20, 21, 23, 25, HATSU})  # 2s 3s 4s 6s 8s hatsu


@yakuman("ryuuiisou")
def ryuuiisou(w: Win) -> bool:
    return all(k in GREEN for k in w.kinds)


def _chuuren_suit(w: Win) -> int | None:
    """The suit of a 1112345678999+X hand with no melds at all (not even ankan)."""
    if w.has_melds or w.form is not FormType.STANDARD:
        return None
    suits = {suit(k) for k in w.kinds}
    if len(suits) != 1 or 3 in suits:
        return None
    s = suits.pop()
    c = w.counts[9 * s : 9 * s + 9]
    return s if c[0] >= 3 and c[8] >= 3 and all(c[1:8]) else None


@yakuman("chuuren", closed_only=True)
def chuuren(w: Win) -> bool:
    """1112345678999 + 1 extra tile in one suit, not the nine-sided wait."""
    return _chuuren_suit(w) is not None and not _junsei(w)


def _junsei(w: Win) -> bool:
    s = _chuuren_suit(w)
    if s is None:
        return False
    c = w.counts[9 * s : 9 * s + 9]
    c[w.win - 9 * s] -= 1
    return c == [3, 1, 1, 1, 1, 1, 1, 1, 3]


@yakuman("junsei_chuuren", mult=2, closed_only=True)
def junsei_chuuren(w: Win) -> bool:
    """Exactly 1112345678999 before the win: nine-sided wait."""
    return _junsei(w)


@yakuman("suukantsu")
def suukantsu(w: Win) -> bool:
    return w.kans == 4
