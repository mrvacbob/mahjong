"""Hand decomposition into standard (4 sets + pair), chiitoitsu, and kokushi forms."""

from __future__ import annotations

from collections.abc import Sequence
from enum import IntEnum

from .tiles import SUITS, YAOCHU, TileKind


class GroupKind(IntEnum):
    """Order matches the agari spec: pair < sequence < triplet."""

    PAIR = 0
    SEQ = 1
    TRIPLET = 2


Group = tuple[TileKind, GroupKind]  # (start_kind, group_kind)
StandardForm = tuple[TileKind, tuple[Group, ...]]  # (pair_kind, sorted concealed sets)


def format_group(g: Group) -> str:
    start, gkind = g
    suit = SUITS[start // 9]
    d = start % 9 + 1
    if gkind is GroupKind.PAIR:
        return f"{d}{d}{suit}"
    if gkind is GroupKind.SEQ:
        return f"{d}{d + 1}{d + 2}{suit}"
    return f"{d}{d}{d}{suit}"


def is_chiitoi(counts: Sequence[int], num_melds: int) -> bool:
    if num_melds != 0:
        return False
    pairs = 0
    for c in counts:
        if c == 2:
            pairs += 1
        elif c != 0:
            return False
    return pairs == 7


def is_kokushi(counts: Sequence[int], num_melds: int) -> bool:
    if num_melds != 0:
        return False
    total = 0
    for k, c in enumerate(counts):
        if k in YAOCHU:
            if c == 0:
                return False
            total += c
        elif c != 0:
            return False
    return total == 14


def _extract_sets(
    c: list[int],
    need: int,
    start_idx: int,
    allow_triplet: bool,
    acc: list[Group],
    out: set[tuple[Group, ...]],
) -> None:
    if need == 0:
        out.add(tuple(sorted(acc)))
        return
    i = start_idx
    while i < 34 and c[i] == 0:
        i += 1
    if i == 34:
        return
    if i > start_idx:
        allow_triplet = True

    if allow_triplet and c[i] >= 3:
        c[i] -= 3
        acc.append((i, GroupKind.TRIPLET))
        _extract_sets(c, need - 1, i, True, acc, out)
        acc.pop()
        c[i] += 3

    if i < 27 and (i % 9) <= 6 and c[i + 1] > 0 and c[i + 2] > 0:
        c[i] -= 1
        c[i + 1] -= 1
        c[i + 2] -= 1
        acc.append((i, GroupKind.SEQ))
        _extract_sets(c, need - 1, i, False, acc, out)
        acc.pop()
        c[i] += 1
        c[i + 1] += 1
        c[i + 2] += 1


def decompose_standard(counts: Sequence[int], num_melds: int) -> list[StandardForm]:
    """Return all distinct standard decompositions (pair_kind, concealed_sets)."""
    need = 4 - num_melds
    if need < 0 or sum(counts) != 2 + 3 * need:
        return []
    c = list(counts)
    results: list[StandardForm] = []
    for pair_kind in range(34):
        if c[pair_kind] >= 2:
            c[pair_kind] -= 2
            sets_found: set[tuple[Group, ...]] = set()
            _extract_sets(c, need, 0, True, [], sets_found)
            c[pair_kind] += 2
            for s in sets_found:
                results.append((pair_kind, s))
    return results


def agari_forms(counts: Sequence[int], num_melds: int) -> list[str]:
    """Return all canonical agari form strings, sorted and deduplicated."""
    forms: set[str] = set()
    for pair_kind, sets in decompose_standard(counts, num_melds):
        groups = sorted([(pair_kind, GroupKind.PAIR), *sets])
        forms.add(",".join(format_group(g) for g in groups))
    if is_chiitoi(counts, num_melds):
        forms.add("chiitoi")
    if is_kokushi(counts, num_melds):
        forms.add("kokushi")
    return sorted(forms)
