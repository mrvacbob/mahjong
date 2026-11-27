"""Scoring a win: interpretations, fu, han, payment, and the best choice (spec/rules.md section 3)."""

from collections.abc import Iterator
from dataclasses import dataclass

from hand import Group, Shape, is_chiitoi, is_kokushi, standard_forms
from tiles import DRAGONS, EAST, NUM_KINDS, Counts, Kind, Meld, MeldType, Tile, counts_of, digit, dora_of, is_yaochu
from yaku import YAKU, YAKUMAN, FormType, Wait, Win


class ScoreError(Exception):
    """`not_agari` or `no_yaku`."""


@dataclass(frozen=True, slots=True)
class Context:
    seat: Kind
    round: Kind
    flags: frozenset[str] = frozenset()
    dora: tuple[Kind, ...] = ()  # indicators
    ura: tuple[Kind, ...] = ()
    honba: int = 0

    @property
    def dealer(self) -> bool:
        return self.seat == EAST


@dataclass(frozen=True, slots=True)
class Result:
    yaku: tuple[tuple[str, int], ...]  # sorted by name; dora included
    han: int
    fu: int
    yakuman: int  # sum of multiples; 0 for an ordinary hand
    pay: str
    total: int

    @property
    def yaku_str(self) -> str:
        return ",".join(f"{n}:{v}" for n, v in self.yaku)

    def rank(self) -> tuple[int, bool, int, int]:
        """Tie-break order (higher is better), before the yaku string."""
        return (self.total, self.yakuman > 0, self.han, self.fu)

    def __str__(self) -> str:
        if self.yakuman:
            return f"yaku={self.yaku_str} yakuman={self.yakuman} pay={self.pay} total={self.total}"
        return f"yaku={self.yaku_str} han={self.han} fu={self.fu} pay={self.pay} total={self.total}"


# ---------------------------------------------------------------- interpretations


def _meld_group(m: Meld) -> Group:
    if m.is_kan:
        return Group(m.kind, Shape.KAN, m.is_open)
    return Group(m.kind, Shape.SEQ if m.type is MeldType.CHI else Shape.TRIPLET, True)


def _wait_of(g: Group, win: Kind) -> Wait:
    match g.shape:
        case Shape.PAIR:
            return Wait.TANKI
        case Shape.TRIPLET:
            return Wait.SHANPON
        case _:
            if win == g.kind + 1:
                return Wait.KANCHAN
            if (win == g.kind + 2 and digit(g.kind) == 1) or (win == g.kind and digit(g.kind) == 7):
                return Wait.PENCHAN
            return Wait.RYANMEN


def interpretations(concealed: Counts, melds: list[Meld], win: Kind, tsumo: bool,
                    ctx: Context) -> Iterator[Win]:
    """Every reading of the hand `concealed` (win tile included) completed by `win`."""
    meld_groups = tuple(_meld_group(m) for m in melds)
    all_counts = list(concealed)
    for g in meld_groups:
        for k in g.kinds:
            all_counts[k] += 1
    closed = not any(m.is_open for m in melds)
    common = dict(win=win, tsumo=tsumo, closed=closed, has_melds=bool(melds), flags=ctx.flags,
                  seat=ctx.seat, round=ctx.round, counts=all_counts)
    for form in standard_forms(concealed):
        seen: set[Group] = set()
        for i, g in enumerate(form):
            if win not in g.kinds or g in seen:
                continue
            seen.add(g)
            wait = _wait_of(g, win)
            groups = list(form)
            if wait is Wait.SHANPON and not tsumo:
                groups[i] = Group(g.kind, g.shape, open=True)  # ron completes an open triplet
            yield Win(FormType.STANDARD, tuple(groups) + meld_groups, wait, **common)
    if not melds and is_chiitoi(concealed):
        pairs = tuple(Group(k, Shape.PAIR) for k in range(NUM_KINDS) if concealed[k])
        yield Win(FormType.CHIITOI, pairs, Wait.TANKI, **common)
    if not melds and is_kokushi(concealed):
        wait = Wait.KOKUSHI_13 if concealed[win] == 2 else Wait.TANKI
        yield Win(FormType.KOKUSHI, (), wait, **common)


# ---------------------------------------------------------------- fu (section 3.1)


def _set_fu(g: Group) -> int:
    base = {Shape.TRIPLET: 2, Shape.KAN: 8}.get(g.shape, 0)
    if not g.open:
        base *= 2
    if is_yaochu(g.kind):
        base *= 2
    return base


def fu(w: Win, is_pinfu: bool) -> int:
    if w.form is FormType.CHIITOI:
        return 25
    if is_pinfu and w.tsumo:
        return 20
    total = 20
    if w.closed and not w.tsumo:
        total += 10  # menzen ron
    if w.tsumo:
        total += 2
    total += sum(_set_fu(g) for g in w.groups)
    if w.pair is not None:
        total += 2 * (w.pair in DRAGONS) + 2 * (w.pair == w.seat) + 2 * (w.pair == w.round)
    if w.wait in (Wait.KANCHAN, Wait.PENCHAN, Wait.TANKI):
        total += 2
    total = -(-total // 10) * 10
    if total == 20 and not w.closed:
        total = 30  # open pinfu-shape ron
    return total


# ---------------------------------------------------------------- payment (section 3.2)


def _ceil100(x: int) -> int:
    return -(-x // 100) * 100


def basic_points(han: int, fu_: int, yakuman: int) -> int:
    if yakuman:
        return 8000 * yakuman
    if han >= 13:
        return 8000  # kazoe yakuman, never more than 1x
    if han >= 11:
        return 6000
    if han >= 8:
        return 4000
    if han >= 6:
        return 3000
    return min(2000, fu_ * 2 ** (2 + han))


def payment(basic: int, tsumo: bool, ctx: Context) -> tuple[str, int]:
    h = ctx.honba
    if not tsumo:
        n = _ceil100(basic * (6 if ctx.dealer else 4)) + 300 * h
        return f"ron:{n}", n
    if ctx.dealer:
        n = _ceil100(2 * basic) + 100 * h
        return f"all:{n}", 3 * n
    nd, d = _ceil100(basic) + 100 * h, _ceil100(2 * basic) + 100 * h
    return f"tsumo:{nd}/{d}", 2 * nd + d


# ---------------------------------------------------------------- evaluation


@dataclass(frozen=True, slots=True)
class Dora:
    dora: int
    aka: int
    ura: int


def count_dora(tiles: list[Tile], ctx: Context) -> Dora:
    counts = counts_of(tiles)
    dora = sum(counts[dora_of(i)] for i in ctx.dora)
    with_riichi = bool({"riichi", "double_riichi"} & ctx.flags)
    ura = sum(counts[dora_of(i)] for i in ctx.ura) if with_riichi else 0
    return Dora(dora, sum(t.red for t in tiles), ura)


def evaluate(w: Win, d: Dora, ctx: Context) -> Result | None:
    """Score one interpretation; None if it has no yaku."""
    yakuman = [(y.name, y.han(w)) for y in YAKUMAN]
    yakuman = [(n, v) for n, v in yakuman if v]
    if yakuman:
        total_mult = sum(v for _, v in yakuman)
        pay, total = payment(basic_points(0, 0, total_mult), w.tsumo, ctx)
        return Result(tuple(sorted(yakuman)), 0, 0, total_mult, pay, total)
    yaku = [(y.name, y.han(w)) for y in YAKU]
    yaku = [(n, v) for n, v in yaku if v]
    if not yaku:
        return None
    is_pinfu = any(n == "pinfu" for n, _ in yaku)
    yaku += [(n, v) for n, v in (("dora", d.dora), ("aka", d.aka), ("ura", d.ura)) if v]
    han = sum(v for _, v in yaku)
    fu_ = fu(w, is_pinfu)
    pay, total = payment(basic_points(han, fu_, 0), w.tsumo, ctx)
    return Result(tuple(sorted(yaku)), han, fu_, 0, pay, total)


def best(hand: list[Tile], melds: list[Meld], win: Tile, tsumo: bool, ctx: Context) -> Result:
    """The best-paying interpretation (spec tie-break). Raises ScoreError."""
    all_tiles = hand + [win] + [t for m in melds for t in m.tiles]
    d = count_dora(all_tiles, ctx)
    concealed = counts_of(hand + [win])
    # Tenhou: any of the 14 tiles may be the winning tile.
    candidates = ([k for k in range(NUM_KINDS) if concealed[k]] if "tenhou" in ctx.flags
                  else [win.kind])
    results: list[Result] = []
    complete = False
    for w_kind in candidates:
        for w in interpretations(concealed, melds, w_kind, tsumo, ctx):
            complete = True
            r = evaluate(w, d, ctx)
            if r is not None:
                results.append(r)
    if not complete:
        raise ScoreError("not_agari")
    if not results:
        raise ScoreError("no_yaku")
    top = max(r.rank() for r in results)
    return min((r for r in results if r.rank() == top), key=lambda r: r.yaku_str)
