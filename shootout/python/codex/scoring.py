from __future__ import annotations


from collections import Counter
from collections.abc import Iterable, Iterator
from dataclasses import dataclass

from shapes import (
    DRAGONS, HONORS, ORPHANS, TERMINALS, WINDS, Counts, Form, Group, Hand,
    changed, counts, forms, kind, kokushi, parse_tiles, seven_pairs,
)

type Yaku = tuple[str, int]
GREEN = frozenset((19, 20, 21, 23, 25, 32))
GATES = (3, 1, 1, 1, 1, 1, 1, 1, 3)
RIICHI_FLAGS = frozenset(("riichi", "double_riichi"))


@dataclass(frozen=True, slots=True)
class Context:
    seat: int
    round_wind: int
    flags: frozenset[str]
    dora: Counts
    ura: Counts
    honba: int
    tsumo: bool

    @classmethod
    def parse(cls, args: dict[str, str], *, tsumo: bool, riichi: bool = False) -> Context:
        flags = frozenset(args.get("flags", "-").split(",")) - {"-"}
        if riichi:
            flags |= {"riichi"}
        return cls(
            27 + "ESWN".index(args.get("seat", "E")),
            27 + "ESWN".index(args.get("round", "E")),
            flags,
            counts(dora_kind(kind(t)) for t in parse_tiles(args.get("dora", "-"))),
            counts(dora_kind(kind(t)) for t in parse_tiles(args.get("ura", "-"))),
            int(args.get("honba", "0")),
            tsumo,
        )


def dora_kind(indicator: int) -> int:
    if indicator in WINDS:
        return 27 + (indicator - 27 + 1) % 4
    if indicator in DRAGONS:
        return 31 + (indicator - 31 + 1) % 3
    return indicator // 9 * 9 + (indicator + 1) % 9


@dataclass(frozen=True, slots=True)
class Interpretation:
    concealed: Form
    winning_group: Group | None
    win: int
    special: str = ""

    @property
    def wait(self) -> str:
        group = self.winning_group
        if group is None:
            return self.special
        if group.shape == "pair":
            return "tanki"
        if group.shape == "triplet":
            return "shanpon"
        offset = self.win - group.first
        if offset == 1:
            return "kanchan"
        if (group.first % 9, offset) in ((0, 2), (6, 0)):
            return "penchan"
        return "ryanmen"


def interpretations(state: Counts, melds: int, wins: Iterable[int]) -> Iterator[Interpretation]:
    standard = forms(state, 4 - melds)
    pairs = not melds and seven_pairs(state)
    orphans = not melds and kokushi(state)
    for win in wins:
        if pairs:
            yield Interpretation((), None, win, "chiitoi")
        if orphans:
            name = "kokushi_13" if state[win] == 2 else "kokushi"
            yield Interpretation((), None, win, name)
        for form in standard:
            for group in dict.fromkeys(form):
                if win in group.tiles():
                    yield Interpretation(form, group, win)


@dataclass(frozen=True, slots=True)
class Features:
    closed: bool
    pair: int | None
    sequences: Counter[int]
    triplets: frozenset[int]
    concealed_triplets: int
    kans: int
    extra_fu: int
    outside: bool

    @classmethod
    def collect(cls, hand: Hand, reading: Interpretation, ctx: Context) -> Features:
        groups = [
            (g, not ctx.tsumo and g == reading.winning_group and g.shape == "triplet")
            for g in reading.concealed
        ]
        groups.extend((meld.group, meld.call != "a") for meld in hand.melds)
        pair = next((g.first for g, _ in groups if g.shape == "pair"), None)
        extra_fu = 2 * sum(pair == value for value in (*DRAGONS, ctx.seat, ctx.round_wind))
        if reading.wait in {"tanki", "kanchan", "penchan"}:
            extra_fu += 2
        sequences: Counter[int] = Counter()
        triplets: set[int] = set()
        concealed_triplets = kans = 0
        for group, opened in groups:
            tile = group.first
            if group.shape == "sequence":
                sequences[tile] += 1
            elif group.shape in {"triplet", "kan"}:
                triplets.add(tile)
                concealed_triplets += not opened
                kan = group.shape == "kan"
                kans += kan
                extra_fu += 2 * (2 if tile in ORPHANS else 1) * (1 if opened else 2) * (4 if kan else 1)
        outside = all(any(t in ORPHANS for t in g.tiles()) for g, _ in groups)
        return cls(hand.closed, pair, sequences, frozenset(triplets),
                   concealed_triplets, kans, extra_fu, outside)


def natural_yakuman(
    reading: Interpretation, features: Features, state: Counts, present: frozenset[int],
    ctx: Context,
) -> Iterator[Yaku]:
    f = features
    if reading.special in {"kokushi", "kokushi_13"}:
        yield reading.special, 2 if reading.special == "kokushi_13" else 1
    if f.concealed_triplets == 4:
        yield ("suuankou_tanki", 2) if reading.wait == "tanki" else ("suuankou", 1)
    wind_sets = len(f.triplets & WINDS)
    rules = (
        ("tenhou", 1, "tenhou" in ctx.flags),
        ("chiihou", 1, "chiihou" in ctx.flags),
        ("daisangen", 1, DRAGONS <= f.triplets),
        ("daisuushii", 2, wind_sets == 4),
        ("shousuushii", 1, wind_sets == 3 and f.pair in WINDS),
        ("tsuuiisou", 1, present <= HONORS),
        ("chinroutou", 1, present <= TERMINALS),
        ("ryuuiisou", 1, present <= GREEN),
        ("suukantsu", 1, f.kans == 4),
    )
    yield from ((name, value) for name, value, applies in rules if applies)
    if f.closed and not f.kans:
        suit_start = reading.win // 9 * 9
        suit = state[suit_start:suit_start + 9]
        if len(suit) == 9 and all(n >= need for n, need in zip(suit, GATES)):
            before = changed(suit, reading.win % 9, -1)
            yield ("junsei_chuuren", 2) if before == GATES else ("chuuren", 1)


def three_suits(kinds: Iterable[int]) -> bool:
    available = set(kinds)
    return any({rank, rank + 9, rank + 18} <= available for rank in range(9))


def ordinary_yaku(
    reading: Interpretation, features: Features, present: frozenset[int], ctx: Context,
) -> Iterator[Yaku]:
    f = features
    for name in ("ippatsu", "haitei", "houtei", "rinshan", "chankan"):
        if name in ctx.flags:
            yield name, 1
    if ctx.flags & RIICHI_FLAGS:
        yield ("double_riichi", 2) if "double_riichi" in ctx.flags else ("riichi", 1)

    seq = f.sequences
    repeated = sum(n // 2 for n in seq.values())
    single_suit = len({k // 9 for k in present - HONORS}) == 1
    has_honors = bool(present & HONORS)
    open_reduction = int(not f.closed)
    rules = (
        ("tsumo", 1, ctx.tsumo and f.closed),
        ("pinfu", 1, f.closed and f.pair is not None and f.extra_fu == 0),
        ("tanyao", 1, present.isdisjoint(ORPHANS)),
        ("iipeikou", 1, f.closed and repeated == 1),
        ("ryanpeikou", 3, f.closed and repeated == 2),
        ("chiitoi", 2, reading.special == "chiitoi"),
        ("toitoi", 2, len(f.triplets) == 4),
        ("sanankou", 2, f.concealed_triplets == 3),
        ("sanshoku", 2 - open_reduction, three_suits(seq)),
        ("sanshoku_doukou", 2, three_suits(f.triplets)),
        ("ittsu", 2 - open_reduction, any({i, i + 3, i + 6} <= seq.keys() for i in (0, 9, 18))),
        ("chanta", 2 - open_reduction, bool(seq) and f.outside and has_honors),
        ("junchan", 3 - open_reduction, bool(seq) and f.outside and not has_honors),
        ("honroutou", 2, present <= ORPHANS),
        ("shousangen", 2, len(f.triplets & DRAGONS) == 2 and f.pair in DRAGONS),
        ("sankantsu", 2, f.kans == 3),
        ("honitsu", 3 - open_reduction, single_suit and has_honors),
        ("chinitsu", 6 - open_reduction, single_suit and not has_honors),
    )
    yield from ((name, value) for name, value, applies in rules if applies)
    for name, tile in (
        ("haku", 31), ("hatsu", 32), ("chun", 33), ("seat", ctx.seat), ("round", ctx.round_wind),
    ):
        if tile in f.triplets:
            yield "yakuhai_" + name, 1


def round_up(value: int, unit: int) -> int:
    return (value + unit - 1) // unit * unit


def fu_for(reading: Interpretation, f: Features, yaku: dict[str, int], ctx: Context) -> int:
    if reading.special == "chiitoi":
        return 25
    if ctx.tsumo and "pinfu" in yaku:
        return 20
    method_fu = 2 if ctx.tsumo else 10 if f.closed else 0
    return max(30, round_up(20 + f.extra_fu + method_fu, 10))


def ordinary_base(han: int, fu: int) -> int:
    for threshold, base in ((13, 8000), (11, 6000), (8, 4000), (6, 3000)):
        if han >= threshold:
            return base
    return min(2000, fu * 2 ** (han + 2))


def payment(base: int, ctx: Context) -> tuple[str, int]:
    dealer = ctx.seat == 27
    if not ctx.tsumo:
        payer = round_up(base * (6 if dealer else 4), 100) + 300 * ctx.honba
        return f"ron:{payer}", payer
    high = round_up(base * 2, 100) + 100 * ctx.honba
    if dealer:
        return f"all:{high}", 3 * high
    low = round_up(base, 100) + 100 * ctx.honba
    return f"tsumo:{low}/{high}", 2 * low + high


@dataclass(frozen=True, slots=True)
class Score:
    yaku: str
    yakuman: int
    han: int
    fu: int
    pay: str
    total: int

    def order(self) -> tuple[int, bool, int, int, str]:
        return (-self.total, self.yakuman == 0, -self.han, -self.fu, self.yaku)

    def render(self) -> str:
        value = f"yakuman={self.yakuman}" if self.yakuman else f"han={self.han} fu={self.fu}"
        return f"yaku={self.yaku} {value} pay={self.pay} total={self.total}"


def score(hand: Hand, win: int, ctx: Context) -> Score | str:
    tiles = (*hand.tiles, win)
    state = counts(tiles)
    all_tiles = (*hand.all_tiles(), win)
    all_counts = counts(all_tiles)
    present = frozenset(i for i, n in enumerate(all_counts) if n)
    wins = sorted(present) if "tenhou" in ctx.flags else (kind(win),)
    bonuses = {
        "aka": sum(tile >= 34 for tile in all_tiles),
        "dora": sum(n * d for n, d in zip(all_counts, ctx.dora)),
        "ura": sum(n * d for n, d in zip(all_counts, ctx.ura)) if ctx.flags & RIICHI_FLAGS else 0,
    }
    saw_shape = False
    best: Score | None = None
    for reading in interpretations(state, len(hand.melds), wins):
        saw_shape = True
        f = Features.collect(hand, reading, ctx)
        yaku = dict(natural_yakuman(reading, f, state, present, ctx))
        yakuman = sum(yaku.values())
        han = fu = 0
        if yakuman:
            base = 8000 * yakuman
        else:
            yaku = dict(ordinary_yaku(reading, f, present, ctx))
            if not yaku:
                continue
            yaku.update((name, n) for name, n in bonuses.items() if n)
            han = sum(yaku.values())
            fu = fu_for(reading, f, yaku, ctx)
            base = ordinary_base(han, fu)
        pay, total = payment(base, ctx)
        names = ",".join(f"{name}:{yaku[name]}" for name in sorted(yaku))
        candidate = Score(names, yakuman, han, fu, pay, total)
        if best is None or candidate.order() < best.order():
            best = candidate
    if best is None:
        return "error=no_yaku" if saw_shape else "error=not_agari"
    return best
