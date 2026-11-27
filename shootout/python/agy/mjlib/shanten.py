"""Structural shanten (standard, chiitoi, kokushi) and waits calculation."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from functools import lru_cache

from .tiles import YAOCHU, TileKind

# Profile: tuple of (sets, max_taatsu) pairs for a single suit or honors block.
Profile = tuple[tuple[int, int], ...]


@lru_cache(maxsize=None)
def _suit_mt(s: tuple[int, ...]) -> Profile:
    """Return optimal (sets, max_taatsu) profile for a single suited tile slice."""
    # Strip leading zeros so equivalent subproblems share cache entries.
    i = 0
    n = len(s)
    while i < n and s[i] == 0:
        i += 1
    if i == n:
        return ((0, 0),)
    if i > 0:
        return _suit_mt(s[i:])

    best: dict[int, int] = {}

    def merge(sub: Profile, dm: int, dt: int) -> None:
        for m, t in sub:
            nm = m + dm
            nt = t + dt
            prev = best.get(nm, -1)
            if nt > prev:
                best[nm] = nt

    c0 = s[0]
    # 1. Triplet at 0
    if c0 >= 3:
        merge(_suit_mt((c0 - 3, *s[1:])), 1, 0)
    # 2. Sequence (0, 1, 2)
    if n >= 3 and s[1] > 0 and s[2] > 0:
        merge(_suit_mt((c0 - 1, s[1] - 1, s[2] - 1, *s[3:])), 1, 0)
    # 3. Pair taatsu at 0
    if c0 >= 2:
        merge(_suit_mt((c0 - 2, *s[1:])), 0, 1)
    # 4. Ryanmen / penchan taatsu (0, 1)
    if n >= 2 and s[1] > 0:
        merge(_suit_mt((c0 - 1, s[1] - 1, *s[2:])), 0, 1)
    # 5. Kanchan taatsu (0, 2)
    if n >= 3 and s[2] > 0:
        merge(_suit_mt((c0 - 1, s[1], s[2] - 1, *s[3:])), 0, 1)
    # 6. Drop remaining copies of index 0
    merge(_suit_mt(s[1:]), 0, 0)

    return tuple(best.items())


@lru_cache(maxsize=None)
def _suit_profiles(s: tuple[int, ...]) -> tuple[Profile, Profile]:
    """Return (no_head_profile, with_head_profile) for a 9-tile suit tuple."""
    no_head = _suit_mt(s)
    best_head: dict[int, int] = {}
    for i, c in enumerate(s):
        if c >= 2:
            sub = _suit_mt((*s[:i], c - 2, *s[i + 1 :]))
            for m, t in sub:
                prev = best_head.get(m, -1)
                if t > prev:
                    best_head[m] = t
    return no_head, tuple(best_head.items())


def _honors_profiles(h: Sequence[int]) -> tuple[Profile, Profile]:
    """Return (no_head_profile, with_head_profile) for the 7 honor counts."""
    m0 = 0
    t0 = 0
    has2 = False
    has3 = False
    has4 = False
    for c in h:
        if c >= 3:
            m0 += 1
            if c == 3:
                has3 = True
            else:
                has4 = True
        elif c == 2:
            t0 += 1
            has2 = True

    no_head: Profile = ((m0, t0),)
    best_head: dict[int, int] = {}
    if has2:
        # Removing 2 from a pair reduces taatsu by 1
        best_head[m0] = max(best_head.get(m0, -1), t0 - 1)
    if has3:
        # Removing 2 from a triplet reduces sets by 1
        best_head[m0 - 1] = max(best_head.get(m0 - 1, -1), t0)
    if has4:
        # Removing 2 from a quad turns 1 set into 1 taatsu
        best_head[m0 - 1] = max(best_head.get(m0 - 1, -1), t0 + 1)
    return no_head, tuple(best_head.items())


def _combine(acc: dict[int, int], prof: Profile, out: dict[int, int]) -> None:
    for m1, t1 in acc.items():
        for m2, t2 in prof:
            nm = m1 + m2
            nt = t1 + t2
            prev = out.get(nm, -1)
            if nt > prev:
                out[nm] = nt


def standard_shanten(counts: Sequence[int], num_melds: int) -> int:
    """Structural standard shanten: 8 - 2*sets - min(taatsu, 4-sets) - head."""
    groups = (
        _suit_profiles(tuple(counts[0:9])),
        _suit_profiles(tuple(counts[9:18])),
        _suit_profiles(tuple(counts[18:27])),
        _honors_profiles(counts[27:34]),
    )
    no_head: dict[int, int] = {num_melds: 0}
    with_head: dict[int, int] = {}
    for g_no, g_with in groups:
        next_with: dict[int, int] = {}
        if with_head:
            _combine(with_head, g_no, next_with)
        if g_with:
            _combine(no_head, g_with, next_with)
        next_no: dict[int, int] = {}
        _combine(no_head, g_no, next_no)
        no_head = next_no
        with_head = next_with

    best = 8
    for m, t in no_head.items():
        t_cap = t if m + t <= 4 else 4 - m
        val = 8 - 2 * m - t_cap
        if val < best:
            best = val
    for m, t in with_head.items():
        t_cap = t if m + t <= 4 else 4 - m
        val = 8 - 2 * m - t_cap - 1
        if val < best:
            best = val
    return best


def chiitoi_shanten(counts: Sequence[int]) -> int:
    """Chiitoitsu shanten: 6 - pairs + max(0, 7 - kinds)."""
    pairs = 0
    kinds = 0
    for c in counts:
        if c >= 1:
            kinds += 1
            if c >= 2:
                pairs += 1
    return 6 - pairs + (7 - kinds if kinds < 7 else 0)


def kokushi_shanten(counts: Sequence[int]) -> int:
    """Kokushi shanten: 13 - distinct_yaochu - (1 if pair else 0)."""
    distinct = 0
    has_pair = False
    for k in YAOCHU:
        c = counts[k]
        if c >= 1:
            distinct += 1
            if c >= 2:
                has_pair = True
    return 13 - distinct - (1 if has_pair else 0)


@dataclass(frozen=True, slots=True)
class ShantenResult:
    std: int
    chiitoi: int | None
    kokushi: int | None
    min_val: int


def compute_shanten(counts: Sequence[int], num_melds: int) -> ShantenResult:
    std = standard_shanten(counts, num_melds)
    if num_melds == 0:
        ch = chiitoi_shanten(counts)
        ko = kokushi_shanten(counts)
        return ShantenResult(std=std, chiitoi=ch, kokushi=ko, min_val=min(std, ch, ko))
    return ShantenResult(std=std, chiitoi=None, kokushi=None, min_val=std)


def min_shanten(counts: Sequence[int], num_melds: int) -> int:
    std = standard_shanten(counts, num_melds)
    if num_melds == 0:
        ch = chiitoi_shanten(counts)
        ko = kokushi_shanten(counts)
        return min(std, ch, ko)
    return std


def structural_waits(counts: Sequence[int], num_melds: int) -> tuple[int, list[TileKind]]:
    """Return (base_shanten, list of tile kinds that strictly lower min_shanten)."""
    base = min_shanten(counts, num_melds)
    c = list(counts)
    waits: list[TileKind] = []
    for k in range(34):
        c[k] += 1
        if min_shanten(c, num_melds) < base:
            waits.append(k)
        c[k] -= 1
    return base, waits


@dataclass(frozen=True, slots=True)
class WaitsResult:
    shanten: int
    tiles: tuple[TileKind, ...]
    count: int


def compute_waits(
    hand_counts: Sequence[int],
    meld_counts: Sequence[int],
    num_melds: int,
) -> WaitsResult:
    """Compute waits op result: kinds with >=1 live copy outside hand and melds."""
    base, raw_waits = structural_waits(hand_counts, num_melds)
    live_tiles: list[TileKind] = []
    total_count = 0
    for k in raw_waits:
        rem = 4 - (hand_counts[k] + meld_counts[k])
        if rem > 0:
            live_tiles.append(k)
            total_count += rem
    return WaitsResult(shanten=base, tiles=tuple(live_tiles), count=total_count)
