"""Shared helpers for the line-protocol text format (Spec/formats.md). Stdlib only.

Tile codes used internally:
  0..8   = 1m..9m, 9..17 = 1p..9p, 18..26 = 1s..9s, 27..33 = 1z..7z (34-format kinds)
  34, 35, 36 = red 5m, red 5p, red 5s
"""

from __future__ import annotations

SUITS = "mpsz"
RED_CODES = (34, 35, 36)
RED_KIND = {34: 4, 35: 13, 36: 22}
KIND_RED = {4: 34, 13: 35, 22: 36}
WINDS = "ESWN"  # seat / round letters -> 1z..4z


class FormatError(ValueError):
    pass


def kind(t: int) -> int:
    return RED_KIND.get(t, t)


def is_red(t: int) -> bool:
    return t >= 34


def suit_of(t: int) -> int:
    return kind(t) // 9


def digit_of(t: int) -> int:
    """Digit as written (0 for red five)."""
    if t >= 34:
        return 0
    return t % 9 + 1 if t < 27 else t - 27 + 1


def _sort_key(t: int) -> tuple[int, float]:
    k = kind(t)
    s = k // 9
    v = k - 9 * s + 1
    if t >= 34:
        v = 4.5  # red five sorts immediately before 5
    return (s, v)


def parse_tiles(s: str) -> list[int]:
    if s == "-":
        return []
    out: list[int] = []
    pending: list[str] = []
    for ch in s:
        if ch.isdigit():
            pending.append(ch)
        elif ch in SUITS:
            if not pending:
                raise FormatError(f"suit letter without digits in {s!r}")
            si = SUITS.index(ch)
            for d in pending:
                n = int(d)
                if si == 3:
                    if not 1 <= n <= 7:
                        raise FormatError(f"bad honor {d}z")
                    out.append(27 + n - 1)
                elif n == 0:
                    out.append(34 + si)
                else:
                    out.append(si * 9 + n - 1)
            pending = []
        else:
            raise FormatError(f"bad character {ch!r} in tile list {s!r}")
    if pending or not out:
        raise FormatError(f"bad tile list {s!r}")
    return out


def parse_tile(s: str) -> int:
    ts = parse_tiles(s)
    if len(ts) != 1:
        raise FormatError(f"expected one tile, got {s!r}")
    return ts[0]


def fmt_tiles(tiles, red_as_five: bool = False) -> str:
    """Canonical tile list. `tiles` is an iterable of tile codes."""
    ts = [kind(t) if red_as_five else t for t in tiles]
    if not ts:
        return "-"
    ts.sort(key=_sort_key)
    out = []
    cur = None
    for t in ts:
        s = suit_of(t)
        if cur is not None and s != cur:
            out.append(SUITS[cur])
        cur = s
        out.append(str(digit_of(t)))
    out.append(SUITS[cur])
    return "".join(out)


def fmt_tile(t: int) -> str:
    return fmt_tiles([t])


MELD_LETTERS = "cpksa"  # chi pon open-kan added-kan closed-kan


def parse_melds(s: str) -> list[tuple[str, list[int]]]:
    if s == "-":
        return []
    out = []
    for part in s.split(","):
        if len(part) < 3 or part[0] not in MELD_LETTERS:
            raise FormatError(f"bad meld {part!r}")
        letter = part[0]
        tiles = parse_tiles(part[1:])
        ks = sorted(kind(t) for t in tiles)
        if letter == "c":
            ok = len(ks) == 3 and ks[0] < 27 and ks[0] // 9 == ks[2] // 9 and ks[1] == ks[0] + 1 and ks[2] == ks[0] + 2
        elif letter == "p":
            ok = len(ks) == 3 and ks[0] == ks[2]
        else:
            ok = len(ks) == 4 and ks[0] == ks[3]
        if not ok:
            raise FormatError(f"bad meld shape {part!r}")
        out.append((letter, tiles))
    return out


def fmt_meld(letter: str, tiles) -> str:
    return letter + fmt_tiles(tiles)


def fmt_melds(melds) -> str:
    if not melds:
        return "-"
    return ",".join(fmt_meld(l, t) for l, t in melds)


def parse_kv(tokens) -> dict[str, str]:
    d: dict[str, str] = {}
    for tok in tokens:
        if "=" not in tok:
            raise FormatError(f"token without '=': {tok!r}")
        k, v = tok.split("=", 1)
        if k in d:
            raise FormatError(f"duplicate key {k!r}")
        d[k] = v
    return d


def parse_request(line: str) -> tuple[str, str, dict[str, str]]:
    toks = line.split(" ")
    if len(toks) < 2:
        raise FormatError("request needs id and op")
    return toks[0], toks[1], parse_kv(toks[2:])


def fmt_request(rid: str, op: str, kv) -> str:
    """kv: list of (key, value) pairs in the order to print."""
    return " ".join([rid, op] + [f"{k}={v}" for k, v in kv])


def fmt_response(rid: str, kv) -> str:
    return " ".join([rid] + [f"{k}={v}" for k, v in kv])


def parse_response(line: str) -> tuple[str, dict[str, str]]:
    toks = line.split(" ")
    return toks[0], parse_kv(toks[1:])


def counts34(tiles) -> list[int]:
    c = [0] * 34
    for t in tiles:
        c[kind(t)] += 1
    return c


def validate_tiles(all_tiles) -> None:
    """All physical tiles in one player's view: at most 4 per kind, 1 red per suit."""
    c = counts34(all_tiles)
    for k, n in enumerate(c):
        if n > 4:
            raise FormatError(f"more than 4 copies of {fmt_tile(k)}")
    for r in RED_CODES:
        if sum(1 for t in all_tiles if t == r) > 1:
            raise FormatError(f"more than one {fmt_tile(r)}")
        k = RED_KIND[r]
        if sum(1 for t in all_tiles if t == k) > 3:
            raise FormatError(f"more than three non-red {fmt_tile(k)} (one copy is red)")


def meld_tiles(melds) -> list[int]:
    out = []
    for _, ts in melds:
        out.extend(ts)
    return out
