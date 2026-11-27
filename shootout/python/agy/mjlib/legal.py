"""Legal action generation for draw, discard, and post-call turns."""

from __future__ import annotations

from .decompose import is_kokushi
from .shanten import compute_waits, structural_waits
from .tiles import (
    SUITS,
    YAOCHU,
    Meld,
    MeldKind,
    Tile,
    TileKind,
    kind_str,
    tiles_to_counts,
)
from .yaku import ScoreResult, score_hand


def kuikae_forbidden(
    meld_kind: MeldKind, took_kind: TileKind, meld_base: TileKind
) -> frozenset[TileKind]:
    """Tile kinds forbidden to discard immediately after making a chi or pon."""
    if meld_kind is MeldKind.PON:
        return frozenset({took_kind})
    if meld_kind is MeldKind.CHI:
        forbidden = {took_kind}
        if took_kind == meld_base and ((meld_base + 2) % 9) < 8:
            forbidden.add(meld_base + 3)
        elif took_kind == meld_base + 2 and (meld_base % 9) > 0:
            forbidden.add(meld_base - 1)
        return frozenset(forbidden)
    return frozenset()


def _meld_counts(melds: tuple[Meld, ...]) -> list[int]:
    c = [0] * 34
    for m in melds:
        for t in m.tiles:
            c[t.kind] += 1
    return c


def _distinct_tiles_of_kind(hand: tuple[Tile, ...], kind: TileKind) -> list[Tile]:
    found: set[Tile] = {t for t in hand if t.kind == kind}
    return sorted(found, key=lambda t: t.sort_key)


def legal_called(hand: tuple[Tile, ...], called: Meld, took: Tile) -> list[str]:
    forbidden = kuikae_forbidden(called.kind, took.kind, called.base_kind)
    distinct = sorted(set(hand), key=lambda t: t.sort_key)
    actions = [f"discard:{t}" for t in distinct if t.kind not in forbidden]
    return sorted(actions)


def legal_draw(
    hand: tuple[Tile, ...],
    melds: tuple[Meld, ...],
    draw: Tile,
    seat: TileKind = 27,
    round_wind: TileKind = 27,
    dora_inds: tuple[Tile, ...] = (),
    ura_inds: tuple[Tile, ...] = (),
    honba: int = 0,
    flags: frozenset[str] = frozenset(),
    riichi: bool = False,
    wall: int = 70,
    first: bool = False,
    kans: int = 0,
) -> list[str]:
    actions: list[str] = []
    full_tiles = (*hand, draw)
    full_counts = tiles_to_counts(full_tiles)
    meld_c = _meld_counts(melds)
    num_melds = len(melds)
    is_closed = all(not m.is_open for m in melds)

    # Discards
    if riichi:
        actions.append(f"discard:{draw}")
    else:
        for t in set(full_tiles):
            actions.append(f"discard:{t}")

    # Tsumo
    score_flags = flags | (frozenset({"riichi"}) if riichi else frozenset())
    res = score_hand(
        hand=hand,
        melds=melds,
        win_tile=draw,
        by="tsumo",
        seat=seat,
        round_wind=round_wind,
        dora_inds=dora_inds,
        ura_inds=ura_inds,
        honba=honba,
        flags=score_flags,
    )
    if isinstance(res, ScoreResult):
        actions.append("tsumo")

    # Kyuushu kyuuhai
    if first:
        yaochu_kinds = sum(1 for k in YAOCHU if full_counts[k] > 0)
        if yaochu_kinds >= 9:
            actions.append("kyuushu")

    # Riichi
    if not riichi and is_closed and wall >= 4:
        # Cache tenpai check per tile kind (red 5 and plain 5 leave identical counts)
        kind_tenpai: dict[TileKind, bool] = {}
        for t in set(full_tiles):
            k = t.kind
            ok = kind_tenpai.get(k)
            if ok is None:
                full_counts[k] -= 1
                w = compute_waits(full_counts, meld_c, num_melds)
                full_counts[k] += 1
                ok = w.shanten == 0 and w.count > 0
                kind_tenpai[k] = ok
            if ok:
                actions.append(f"riichi:{t}")

    # Ankan
    if wall >= 1 and kans < 4:
        if not riichi:
            for k in range(34):
                if full_counts[k] == 4:
                    actions.append(f"ankan:{kind_str(k)}")
        else:
            dk = draw.kind
            if full_counts[dk] == 4:
                before_c = tiles_to_counts(hand)
                b_sh, b_waits = structural_waits(before_c, num_melds)
                after_c = list(full_counts)
                after_c[dk] -= 4
                a_sh, a_waits = structural_waits(after_c, num_melds + 1)
                if b_sh == 0 and a_sh == 0 and b_waits == a_waits:
                    actions.append(f"ankan:{kind_str(dk)}")

    # Kakan
    if not riichi and wall >= 1 and kans < 4:
        pon_kinds = {m.base_kind for m in melds if m.kind is MeldKind.PON}
        for t in set(full_tiles):
            if t.kind in pon_kinds:
                actions.append(f"kakan:{t}")

    return sorted(actions)


def legal_discard(
    hand: tuple[Tile, ...],
    melds: tuple[Meld, ...],
    discard: Tile,
    from_seat: str,
    seat: TileKind = 27,
    round_wind: TileKind = 27,
    dora_inds: tuple[Tile, ...] = (),
    ura_inds: tuple[Tile, ...] = (),
    honba: int = 0,
    flags: frozenset[str] = frozenset(),
    riichi: bool = False,
    furiten: bool = False,
    wall: int = 70,
    kans: int = 0,
) -> list[str]:
    actions: list[str] = ["pass"]
    hand_counts = tiles_to_counts(hand)
    d = discard.kind

    # Ron
    if not furiten:
        if "ankan_rob" in flags:
            test_c = list(hand_counts)
            test_c[d] += 1
            if is_kokushi(test_c, len(melds)):
                actions.append("ron")
        else:
            score_flags = flags | (frozenset({"riichi"}) if riichi else frozenset())
            res = score_hand(
                hand=hand,
                melds=melds,
                win_tile=discard,
                by="ron",
                seat=seat,
                round_wind=round_wind,
                dora_inds=dora_inds,
                ura_inds=ura_inds,
                honba=honba,
                flags=score_flags,
            )
            if isinstance(res, ScoreResult):
                actions.append("ron")

    # Robbing a kan allows only ron or pass
    if "chankan" in flags or "ankan_rob" in flags:
        return sorted(actions)

    # Open calls (chi, pon, daiminkan)
    if not riichi and wall >= 1:
        suit_ch = SUITS[d // 9]
        rank_d = d % 9 + 1

        # Pon
        if hand_counts[d] >= 2:
            has_red = any(t.kind == d and t.is_red for t in hand)
            plain_n = sum(1 for t in hand if t.kind == d and not t.is_red)
            if has_red and plain_n >= 1:
                actions.append(f"pon:05{suit_ch}")
            if plain_n >= 2:
                actions.append(f"pon:{rank_d}{rank_d}{suit_ch}")

        # Open kan (daiminkan)
        if kans < 4 and hand_counts[d] == 3:
            actions.append(f"kan:{kind_str(d)}")

        # Chi (from kamicha only, suited tiles only)
        if from_seat == "kamicha" and d < 27:
            r = d % 9
            patterns: list[tuple[TileKind, TileKind, TileKind]] = []
            if r >= 2:
                patterns.append((d - 2, d - 1, d - 2))
            if 1 <= r <= 7:
                patterns.append((d - 1, d + 1, d - 1))
            if r <= 6:
                patterns.append((d + 1, d + 2, d))
            for a, b, meld_base in patterns:
                if hand_counts[a] >= 1 and hand_counts[b] >= 1:
                    forbidden = kuikae_forbidden(MeldKind.CHI, d, meld_base)
                    hand_counts[a] -= 1
                    hand_counts[b] -= 1
                    has_legal_discard = any(
                        c > 0 and k not in forbidden for k, c in enumerate(hand_counts)
                    )
                    hand_counts[a] += 1
                    hand_counts[b] += 1
                    if not has_legal_discard:
                        continue
                    for ta in _distinct_tiles_of_kind(hand, a):
                        for tb in _distinct_tiles_of_kind(hand, b):
                            actions.append(f"chi:{ta.digit}{tb.digit}{suit_ch}")

    return sorted(actions)
