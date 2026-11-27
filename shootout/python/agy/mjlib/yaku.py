"""Yaku, yakuman, fu, payment calculation, and best-interpretation selection."""

from __future__ import annotations

from collections import Counter
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from enum import Enum

from .decompose import Group, GroupKind, decompose_standard, is_chiitoi, is_kokushi
from .tiles import (
    DRAGONS,
    GREENS,
    TERMINALS,
    WINDS,
    YAOCHU,
    Meld,
    MeldKind,
    Tile,
    TileKind,
    dora_next,
    is_honor,
    is_simple,
    tiles_to_counts,
)

CHUUREN_BASE: tuple[int, ...] = (3, 1, 1, 1, 1, 1, 1, 1, 3)


class WaitType(Enum):
    RYANMEN = "ryanmen"
    SHANPON = "shanpon"
    KANCHAN = "kanchan"
    PENCHAN = "penchan"
    TANKI = "tanki"


@dataclass(frozen=True, slots=True)
class HandSet:
    """Unified view of a meld or concealed set for yaku and fu evaluation."""

    start: TileKind
    is_seq: bool
    is_kan: bool
    is_open: bool

    @property
    def is_triplet(self) -> bool:
        return not self.is_seq

    @property
    def is_concealed_triplet(self) -> bool:
        return (not self.is_seq) and (not self.is_open)

    @property
    def has_terminal(self) -> bool:
        if self.is_seq:
            return (self.start % 9) in (0, 6)
        return self.start in TERMINALS

    @property
    def has_yaochu(self) -> bool:
        if self.is_seq:
            return (self.start % 9) in (0, 6)
        return self.start in YAOCHU


@dataclass(frozen=True, slots=True)
class HandView:
    """Precomputed facts about one (decomposition, wait) interpretation."""

    is_closed: bool
    by: str  # "tsumo" or "ron"
    seat: TileKind
    round_wind: TileKind
    flags: frozenset[str]
    pair: TileKind
    sets: tuple[HandSet, ...]
    wait: WaitType
    win_kind: TileKind
    num_melds: int
    total_counts: tuple[int, ...]
    all_kinds: frozenset[TileKind]

    @property
    def concealed_triplets(self) -> int:
        return sum(1 for s in self.sets if s.is_concealed_triplet)

    @property
    def num_kans(self) -> int:
        return sum(1 for s in self.sets if s.is_kan)

    def has_triplet(self, k: TileKind) -> bool:
        return any(s.is_triplet and s.start == k for s in self.sets)

    @property
    def seq_pair_count(self) -> int:
        c = Counter(s.start for s in self.sets if s.is_seq)
        return sum(v // 2 for v in c.values())


@dataclass(frozen=True, slots=True)
class ScoreResult:
    """One valid scored interpretation."""

    yaku: tuple[tuple[str, int], ...]  # sorted by name
    is_yakuman: bool
    yakuman: int  # 0 for ordinary hands
    han: int  # 0 for real yakuman
    fu: int  # 0 for real yakuman
    pay: str
    total: int

    @property
    def yaku_str(self) -> str:
        return ",".join(f"{name}:{val}" for name, val in self.yaku)


def _ceil100(x: int) -> int:
    return ((x + 99) // 100) * 100


def _compute_payment(
    basic: int, by: str, seat: TileKind, honba: int
) -> tuple[str, int]:
    is_dealer = seat == 27  # East
    if by == "ron":
        mult = 6 if is_dealer else 4
        amt = _ceil100(mult * basic) + 300 * honba
        return f"ron:{amt}", amt
    if is_dealer:
        each = _ceil100(2 * basic) + 100 * honba
        return f"all:{each}", 3 * each
    non_d = _ceil100(basic) + 100 * honba
    dealer = _ceil100(2 * basic) + 100 * honba
    return f"tsumo:{non_d}/{dealer}", 2 * non_d + dealer


def _ordinary_basic(han: int, fu: int) -> int:
    if han >= 13:
        return 8000
    if han >= 11:
        return 6000
    if han >= 8:
        return 4000
    if han >= 6:
        return 3000
    if han == 5:
        return 2000
    return min(2000, fu * (1 << (2 + han)))


# ---------------------------------------------------------------------------
# Declarative Yakuman Rules (standard 4-set + pair form)
# ---------------------------------------------------------------------------

def _is_chuuren(v: HandView) -> int:
    """Return 2 for junsei_chuuren, 1 for chuuren, 0 otherwise."""
    if v.num_melds != 0:
        return 0
    suits = {k // 9 for k in v.all_kinds}
    if len(suits) != 1:
        return 0
    s = next(iter(suits))
    if s == 3:
        return 0
    base = s * 9
    c14 = v.total_counts[base : base + 9]
    if not all(a >= b for a, b in zip(c14, CHUUREN_BASE)):
        return 0
    c13 = list(c14)
    c13[v.win_kind - base] -= 1
    return 2 if tuple(c13) == CHUUREN_BASE else 1


YakumanRule = tuple[str, Callable[[HandView], int]]

STANDARD_YAKUMAN_RULES: tuple[YakumanRule, ...] = (
    ("tenhou", lambda v: 1 if "tenhou" in v.flags else 0),
    ("chiihou", lambda v: 1 if "chiihou" in v.flags else 0),
    (
        "suuankou_tanki",
        lambda v: 2 if v.concealed_triplets == 4 and v.wait is WaitType.TANKI else 0,
    ),
    (
        "suuankou",
        lambda v: 1 if v.concealed_triplets == 4 and v.wait is not WaitType.TANKI else 0,
    ),
    (
        "daisangen",
        lambda v: 1 if all(v.has_triplet(d) for d in DRAGONS) else 0,
    ),
    (
        "daisuushii",
        lambda v: 2 if all(v.has_triplet(w) for w in WINDS) else 0,
    ),
    (
        "shousuushii",
        lambda v: 1
        if v.pair in WINDS and sum(1 for w in WINDS if v.has_triplet(w)) == 3
        else 0,
    ),
    ("tsuuiisou", lambda v: 1 if all(is_honor(k) for k in v.all_kinds) else 0),
    ("chinroutou", lambda v: 1 if all(k in TERMINALS for k in v.all_kinds) else 0),
    ("ryuuiisou", lambda v: 1 if all(k in GREENS for k in v.all_kinds) else 0),
    ("junsei_chuuren", lambda v: 2 if _is_chuuren(v) == 2 else 0),
    ("chuuren", lambda v: 1 if _is_chuuren(v) == 1 else 0),
    ("suukantsu", lambda v: 1 if v.num_kans == 4 else 0),
)


# ---------------------------------------------------------------------------
# Declarative Standard Yaku Rules (4-set + pair form)
# ---------------------------------------------------------------------------

def _is_pinfu(v: HandView) -> bool:
    if not v.is_closed:
        return False
    if v.wait is not WaitType.RYANMEN:
        return False
    if v.pair in DRAGONS or v.pair == v.seat or v.pair == v.round_wind:
        return False
    return all(s.is_seq for s in v.sets)


def _has_sanshoku(v: HandView) -> bool:
    seqs = {(s.start // 9, s.start % 9) for s in v.sets if s.is_seq}
    return any((0, r) in seqs and (1, r) in seqs and (2, r) in seqs for r in range(7))


def _has_sanshoku_doukou(v: HandView) -> bool:
    trips = {(s.start // 9, s.start % 9) for s in v.sets if s.is_triplet and s.start < 27}
    return any((0, r) in trips and (1, r) in trips and (2, r) in trips for r in range(9))


def _has_ittsu(v: HandView) -> bool:
    seqs = {(s.start // 9, s.start % 9) for s in v.sets if s.is_seq}
    return any((s, 0) in seqs and (s, 3) in seqs and (s, 6) in seqs for s in range(3))


def _is_junchan(v: HandView) -> bool:
    if any(is_honor(k) for k in v.all_kinds):
        return False
    if not any(s.is_seq for s in v.sets):
        return False
    return v.pair in TERMINALS and all(s.has_terminal for s in v.sets)


def _is_chanta(v: HandView) -> bool:
    if not any(is_honor(k) for k in v.all_kinds):
        return False
    if not any(s.is_seq for s in v.sets):
        return False
    return v.pair in YAOCHU and all(s.has_yaochu for s in v.sets)


def _is_chinitsu(v: HandView) -> bool:
    suits = {k // 9 for k in v.all_kinds}
    return len(suits) == 1 and next(iter(suits)) < 3


def _is_honitsu(v: HandView) -> bool:
    num_suits = {k // 9 for k in v.all_kinds if k < 27}
    has_honor = any(is_honor(k) for k in v.all_kinds)
    return len(num_suits) == 1 and has_honor


YakuRule = tuple[str, Callable[[HandView], int]]

STANDARD_YAKU_RULES: tuple[YakuRule, ...] = (
    ("riichi", lambda v: 1 if "riichi" in v.flags else 0),
    ("double_riichi", lambda v: 2 if "double_riichi" in v.flags else 0),
    ("ippatsu", lambda v: 1 if "ippatsu" in v.flags else 0),
    ("tsumo", lambda v: 1 if v.is_closed and v.by == "tsumo" else 0),
    ("pinfu", lambda v: 1 if _is_pinfu(v) else 0),
    ("tanyao", lambda v: 1 if all(is_simple(k) for k in v.all_kinds) else 0),
    ("ryanpeikou", lambda v: 3 if v.is_closed and v.seq_pair_count == 2 else 0),
    ("iipeikou", lambda v: 1 if v.is_closed and v.seq_pair_count == 1 else 0),
    ("yakuhai_haku", lambda v: 1 if v.has_triplet(31) else 0),
    ("yakuhai_hatsu", lambda v: 1 if v.has_triplet(32) else 0),
    ("yakuhai_chun", lambda v: 1 if v.has_triplet(33) else 0),
    ("yakuhai_seat", lambda v: 1 if v.has_triplet(v.seat) else 0),
    ("yakuhai_round", lambda v: 1 if v.has_triplet(v.round_wind) else 0),
    ("haitei", lambda v: 1 if "haitei" in v.flags else 0),
    ("houtei", lambda v: 1 if "houtei" in v.flags else 0),
    ("rinshan", lambda v: 1 if "rinshan" in v.flags else 0),
    ("chankan", lambda v: 1 if "chankan" in v.flags else 0),
    ("toitoi", lambda v: 2 if all(s.is_triplet for s in v.sets) else 0),
    ("sanankou", lambda v: 2 if v.concealed_triplets == 3 else 0),
    ("sanshoku", lambda v: (2 if v.is_closed else 1) if _has_sanshoku(v) else 0),
    ("sanshoku_doukou", lambda v: 2 if _has_sanshoku_doukou(v) else 0),
    ("ittsu", lambda v: (2 if v.is_closed else 1) if _has_ittsu(v) else 0),
    ("junchan", lambda v: (3 if v.is_closed else 2) if _is_junchan(v) else 0),
    ("chanta", lambda v: (2 if v.is_closed else 1) if _is_chanta(v) else 0),
    ("honroutou", lambda v: 2 if all(k in YAOCHU for k in v.all_kinds) else 0),
    (
        "shousangen",
        lambda v: 2
        if v.pair in DRAGONS and sum(1 for d in DRAGONS if v.has_triplet(d)) == 2
        else 0,
    ),
    ("sankantsu", lambda v: 2 if v.num_kans == 3 else 0),
    ("chinitsu", lambda v: (6 if v.is_closed else 5) if _is_chinitsu(v) else 0),
    ("honitsu", lambda v: (3 if v.is_closed else 2) if _is_honitsu(v) else 0),
)


# ---------------------------------------------------------------------------
# Fu Calculation
# ---------------------------------------------------------------------------

def _calc_fu(v: HandView, has_pinfu: bool) -> int:
    if has_pinfu and v.by == "tsumo":
        return 20
    fu = 20
    if v.is_closed and v.by == "ron":
        fu += 10
    if v.by == "tsumo":
        fu += 2
    for s in v.sets:
        if s.is_seq:
            continue
        if s.is_kan:
            base = 8 if s.is_open else 16
        else:
            base = 2 if s.is_open else 4
        if s.start in YAOCHU:
            base *= 2
        fu += base
    if v.pair in DRAGONS:
        fu += 2
    else:
        if v.pair == v.seat:
            fu += 2
        if v.pair == v.round_wind:
            fu += 2
    if v.wait in (WaitType.KANCHAN, WaitType.PENCHAN, WaitType.TANKI):
        fu += 2
    if not v.is_closed and v.by == "ron" and fu == 20:
        return 30
    return ((fu + 9) // 10) * 10


# ---------------------------------------------------------------------------
# Interpretation Generation & Comparison
# ---------------------------------------------------------------------------

def _is_better(cand: ScoreResult, best: ScoreResult | None) -> bool:
    if best is None:
        return True
    c_key = (cand.total, 1 if cand.is_yakuman else 0, cand.han, cand.fu)
    b_key = (best.total, 1 if best.is_yakuman else 0, best.han, best.fu)
    if c_key != b_key:
        return c_key > b_key
    return cand.yaku_str < best.yaku_str


def _dora_items(
    total_counts: Sequence[int],
    aka_count: int,
    dora_inds: Sequence[Tile],
    ura_inds: Sequence[Tile],
    flags: frozenset[str],
) -> list[tuple[str, int]]:
    items: list[tuple[str, int]] = []
    dora_n = sum(total_counts[dora_next(t.kind)] for t in dora_inds)
    if dora_n > 0:
        items.append(("dora", dora_n))
    if aka_count > 0:
        items.append(("aka", aka_count))
    if "riichi" in flags or "double_riichi" in flags:
        ura_n = sum(total_counts[dora_next(t.kind)] for t in ura_inds)
        if ura_n > 0:
            items.append(("ura", ura_n))
    return items


def _meld_to_handset(m: Meld) -> HandSet:
    return HandSet(
        start=m.base_kind,
        is_seq=(m.kind is MeldKind.CHI),
        is_kan=m.is_kan,
        is_open=m.is_open,
    )


def _wait_for_seq(start: TileKind, win_kind: TileKind) -> WaitType:
    if win_kind == start + 1:
        return WaitType.KANCHAN
    rank = start % 9
    if (win_kind == start + 2 and rank == 0) or (win_kind == start and rank == 6):
        return WaitType.PENCHAN
    return WaitType.RYANMEN


def _score_for_win_kind(
    full_counts: tuple[int, ...],
    total_counts: tuple[int, ...],
    all_kinds: frozenset[TileKind],
    melds: tuple[Meld, ...],
    meld_sets: tuple[HandSet, ...],
    is_closed: bool,
    win_kind: TileKind,
    by: str,
    seat: TileKind,
    round_wind: TileKind,
    flags: frozenset[str],
    dora_items: list[tuple[str, int]],
    honba: int,
) -> tuple[bool, ScoreResult | None]:
    """Evaluate all decompositions for a fixed win_kind. Returns (is_complete, best_score)."""
    num_melds = len(melds)
    complete = False
    best: ScoreResult | None = None

    # 1. Kokushi
    if is_kokushi(full_counts, num_melds):
        complete = True
        ym: list[tuple[str, int]] = []
        if full_counts[win_kind] == 2:
            ym.append(("kokushi_13", 2))
        else:
            ym.append(("kokushi", 1))
        if "tenhou" in flags:
            ym.append(("tenhou", 1))
        if "chiihou" in flags:
            ym.append(("chiihou", 1))
        ym.sort()
        mult = sum(v for _, v in ym)
        pay, total = _compute_payment(8000 * mult, by, seat, honba)
        cand = ScoreResult(tuple(ym), True, mult, 0, 0, pay, total)
        if _is_better(cand, best):
            best = cand

    # 2. Chiitoitsu
    if is_chiitoi(full_counts, num_melds):
        complete = True
        ym_c: list[tuple[str, int]] = []
        if "tenhou" in flags:
            ym_c.append(("tenhou", 1))
        if "chiihou" in flags:
            ym_c.append(("chiihou", 1))
        if all(is_honor(k) for k in all_kinds):
            ym_c.append(("tsuuiisou", 1))
        if ym_c:
            ym_c.sort()
            mult = sum(v for _, v in ym_c)
            pay, total = _compute_payment(8000 * mult, by, seat, honba)
            cand = ScoreResult(tuple(ym_c), True, mult, 0, 0, pay, total)
        else:
            yk: list[tuple[str, int]] = [("chiitoi", 2)]
            if "riichi" in flags:
                yk.append(("riichi", 1))
            if "double_riichi" in flags:
                yk.append(("double_riichi", 2))
            if "ippatsu" in flags:
                yk.append(("ippatsu", 1))
            if by == "tsumo":
                yk.append(("tsumo", 1))
            if "haitei" in flags:
                yk.append(("haitei", 1))
            if "houtei" in flags:
                yk.append(("houtei", 1))
            if "chankan" in flags:
                yk.append(("chankan", 1))
            if all(is_simple(k) for k in all_kinds):
                yk.append(("tanyao", 1))
            if all(k in YAOCHU for k in all_kinds):
                yk.append(("honroutou", 2))
            num_suits = {k // 9 for k in all_kinds if k < 27}
            has_h = any(is_honor(k) for k in all_kinds)
            if len(num_suits) == 1 and not has_h:
                yk.append(("chinitsu", 6))
            elif len(num_suits) == 1 and has_h:
                yk.append(("honitsu", 3))
            yk.extend(dora_items)
            yk.sort()
            han = sum(v for _, v in yk)
            fu = 25
            pay, total = _compute_payment(_ordinary_basic(han, fu), by, seat, honba)
            cand = ScoreResult(tuple(yk), False, 0, han, fu, pay, total)
        if _is_better(cand, best):
            best = cand

    # 3. Standard decompositions
    for pair_kind, c_sets in decompose_standard(full_counts, num_melds):
        complete = True
        # Build candidate (wait_type, open_idx) for each distinct concealed group containing win_kind
        wait_choices: list[tuple[WaitType, int]] = []
        if pair_kind == win_kind:
            wait_choices.append((WaitType.TANKI, -1))
        seen_groups: set[Group] = set()
        for idx, g in enumerate(c_sets):
            if g in seen_groups:
                continue
            start, gkind = g
            if gkind is GroupKind.TRIPLET and start == win_kind:
                seen_groups.add(g)
                wait_choices.append((WaitType.SHANPON, idx))
            elif gkind is GroupKind.SEQ and start <= win_kind <= start + 2:
                seen_groups.add(g)
                wait_choices.append((_wait_for_seq(start, win_kind), idx))

        for wait_type, shanpon_idx in wait_choices:
            hand_sets_list: list[HandSet] = list(meld_sets)
            for idx, (start, gkind) in enumerate(c_sets):
                opened_by_ron = (
                    wait_type is WaitType.SHANPON
                    and idx == shanpon_idx
                    and by == "ron"
                )
                hand_sets_list.append(
                    HandSet(
                        start=start,
                        is_seq=(gkind is GroupKind.SEQ),
                        is_kan=False,
                        is_open=opened_by_ron,
                    )
                )
            view = HandView(
                is_closed=is_closed,
                by=by,
                seat=seat,
                round_wind=round_wind,
                flags=flags,
                pair=pair_kind,
                sets=tuple(hand_sets_list),
                wait=wait_type,
                win_kind=win_kind,
                num_melds=num_melds,
                total_counts=total_counts,
                all_kinds=all_kinds,
            )

            # Check yakuman first
            ym_list: list[tuple[str, int]] = []
            for name, fn in STANDARD_YAKUMAN_RULES:
                m = fn(view)
                if m > 0:
                    ym_list.append((name, m))
            if ym_list:
                ym_list.sort()
                mult = sum(val for _, val in ym_list)
                pay, total = _compute_payment(8000 * mult, by, seat, honba)
                cand = ScoreResult(tuple(ym_list), True, mult, 0, 0, pay, total)
                if _is_better(cand, best):
                    best = cand
                continue

            # Check standard yaku
            yk_list: list[tuple[str, int]] = []
            has_pinfu = False
            for name, fn in STANDARD_YAKU_RULES:
                h = fn(view)
                if h > 0:
                    yk_list.append((name, h))
                    if name == "pinfu":
                        has_pinfu = True
            if not yk_list:
                continue  # no yaku for this interpretation

            yk_list.extend(dora_items)
            yk_list.sort()
            han = sum(val for _, val in yk_list)
            fu = _calc_fu(view, has_pinfu)
            pay, total = _compute_payment(_ordinary_basic(han, fu), by, seat, honba)
            cand = ScoreResult(tuple(yk_list), False, 0, han, fu, pay, total)
            if _is_better(cand, best):
                best = cand

    return complete, best


def score_hand(
    hand: tuple[Tile, ...],
    melds: tuple[Meld, ...],
    win_tile: Tile,
    by: str,
    seat: TileKind = 27,
    round_wind: TileKind = 27,
    dora_inds: tuple[Tile, ...] = (),
    ura_inds: tuple[Tile, ...] = (),
    honba: int = 0,
    flags: frozenset[str] = frozenset(),
) -> ScoreResult | str:
    """Score a winning hand. Returns ScoreResult, or 'not_agari' / 'no_yaku'."""
    full_hand_counts = tiles_to_counts((*hand, win_tile))
    full_counts = tuple(full_hand_counts)

    total_c = list(full_hand_counts)
    for m in melds:
        for t in m.tiles:
            total_c[t.kind] += 1
    total_counts = tuple(total_c)
    all_kinds = frozenset(k for k, c in enumerate(total_counts) if c > 0)

    aka_count = (
        sum(1 for t in hand if t.is_red)
        + (1 if win_tile.is_red else 0)
        + sum(m.aka_count for m in melds)
    )
    dora_items = _dora_items(total_counts, aka_count, dora_inds, ura_inds, flags)
    is_closed = all(not m.is_open for m in melds)
    meld_sets = tuple(_meld_to_handset(m) for m in melds)

    if "tenhou" in flags:
        win_candidates = [k for k in range(34) if full_counts[k] > 0]
    else:
        win_candidates = [win_tile.kind]

    any_complete = False
    best: ScoreResult | None = None
    for wk in win_candidates:
        comp, res = _score_for_win_kind(
            full_counts=full_counts,
            total_counts=total_counts,
            all_kinds=all_kinds,
            melds=melds,
            meld_sets=meld_sets,
            is_closed=is_closed,
            win_kind=wk,
            by=by,
            seat=seat,
            round_wind=round_wind,
            flags=flags,
            dora_items=dora_items,
            honba=honba,
        )
        if comp:
            any_complete = True
        if res is not None and _is_better(res, best):
            best = res

    if not any_complete:
        return "not_agari"
    if best is None:
        return "no_yaku"
    return best
