"""Random hand construction for the corpus generators. Deterministic given an rng."""

from __future__ import annotations

import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from mjfmt import KIND_RED, RED_KIND, kind  # noqa: E402

FIVES = (4, 13, 22)
TERMINALS = {0, 8, 9, 17, 18, 26}
HONORS = set(range(27, 34))
YAOCHU = TERMINALS | HONORS
WINDS_K = (27, 28, 29, 30)
DRAGONS = (31, 32, 33)
GREEN = {19, 20, 21, 23, 25, 32}


def is_simple(k: int) -> bool:
    return k < 27 and k not in TERMINALS


class Pool:
    """The 136 physical tiles; tracks what one player's view has used."""

    def __init__(self, rng: random.Random, red_bias: float = 1.0):
        self.rng = rng
        self.counts = [0] * 34
        self.red_used = set()
        self.red_bias = red_bias

    def copy(self) -> "Pool":
        p = Pool(self.rng, self.red_bias)
        p.counts = self.counts.copy()
        p.red_used = set(self.red_used)
        return p

    def can(self, k: int, n: int = 1) -> bool:
        return self.counts[k] + n <= 4

    def take(self, k: int, red: bool | None = None) -> int:
        """Take one physical tile of kind k; returns its code (red fives as 34..36)."""
        if not self.can(k):
            raise ValueError("no copies left")
        if k in FIVES:
            red_left = KIND_RED[k] not in self.red_used
            plain_used = self.counts[k] - (0 if red_left else 1)
            plain_left = 3 - plain_used
            if red is None:
                if not red_left:
                    red = False
                elif plain_left == 0:
                    red = True
                else:
                    red = self.rng.random() < min(1.0, self.red_bias / (1 + plain_left))
            if red and not red_left:
                raise ValueError("red already used")
            if not red and plain_left == 0:
                raise ValueError("no plain copies left")
            self.counts[k] += 1
            if red:
                self.red_used.add(KIND_RED[k])
                return KIND_RED[k]
            return k
        self.counts[k] += 1
        return k

    def add_existing(self, tiles):
        for t in tiles:
            k = kind(t)
            self.counts[k] += 1
            if t in RED_KIND:
                self.red_used.add(t)
        if any(c > 4 for c in self.counts):
            raise ValueError("over 4")

    def random_tile(self, kinds=None) -> int:
        kinds = list(range(34)) if kinds is None else list(kinds)
        weights = [4 - self.counts[k] for k in kinds]
        if sum(weights) == 0:
            raise ValueError("pool empty")
        k = self.rng.choices(kinds, weights)[0]
        return self.take(k)


# ---------------------------------------------------------------- groups


def group_kinds(gtype: str, k: int) -> list[int]:
    if gtype == "seq":
        return [k, k + 1, k + 2]
    if gtype == "trip":
        return [k, k, k]
    if gtype == "pair":
        return [k, k]
    raise ValueError(gtype)


def seq_starts(suits=(0, 1, 2)):
    return [s * 9 + d for s in suits for d in range(7)]


def take_group(pool: Pool, gtype: str, k: int):
    ks = group_kinds(gtype, k)
    need = {}
    for x in ks:
        need[x] = need.get(x, 0) + 1
    if not all(pool.can(x, n) for x, n in need.items()):
        return None
    return [pool.take(x) for x in ks]


class Built:
    """A complete hand: concealed groups plus melds."""

    def __init__(self, pool, groups, pair):
        self.pool = pool
        self.groups = groups  # list of [gtype, kind, codes]
        self.pair = pair  # [kind, codes]
        self.melds = []  # (letter, codes)
        self.concealed_groups = []
        self.special = None  # 'chiitoi' / 'kokushi' / 'chuuren' / None
        self.fixed_tiles = None  # concealed tiles for special shapes

    def concealed(self) -> list[int]:
        if self.fixed_tiles is not None:
            return list(self.fixed_tiles)
        out = []
        for g in self.concealed_groups:
            out.extend(g[2])
        if self.pair:
            out.extend(self.pair[1])
        return out

    def is_closed(self) -> bool:
        return all(l == "a" for l, _ in self.melds)

    def n_kans(self) -> int:
        return sum(1 for l, _ in self.melds if l in "ksa")


def build(
    rng: random.Random,
    *,
    req=(),
    group_ok=None,
    pair_ok=None,
    seq_prob: float = 0.55,
    red_bias: float = 1.0,
    pair_kind: int | None = None,
    tries: int = 60,
):
    """Build 4 groups + pair. req: list of (gtype, kind) forced groups."""
    for _ in range(tries):
        pool = Pool(rng, red_bias)
        groups = []
        ok = True
        for gt, k in req:
            codes = take_group(pool, gt, k)
            if codes is None:
                ok = False
                break
            groups.append([gt, k, codes])
        if not ok:
            continue
        # pair before random groups so forced pair kinds stay available
        if pair_kind is not None:
            pk = pair_kind
            if not pool.can(pk, 2):
                continue
        else:
            cands = [k for k in range(34) if pool.can(k, 2) and (pair_ok is None or pair_ok(k))]
            if not cands:
                continue
            pk = rng.choice(cands)
        pair_codes = [pool.take(pk), pool.take(pk)]
        attempts = 0
        while len(groups) < 4 and attempts < 200:
            attempts += 1
            if rng.random() < seq_prob:
                gt, k = "seq", rng.choice(seq_starts())
            else:
                gt, k = "trip", rng.randrange(34)
            if group_ok is not None and not group_ok(gt, k):
                continue
            codes = take_group(pool, gt, k)
            if codes is None:
                continue
            groups.append([gt, k, codes])
        if len(groups) < 4:
            continue
        b = Built(pool, groups, [pk, pair_codes])
        b.concealed_groups = list(groups)
        return b
    return None


def assign_melds(
    rng: random.Random,
    b: Built,
    n_open: int = 0,
    n_ankan: int = 0,
    kan_prob: float = 0.25,
    keep: set[int] = frozenset(),
    force_kans: int = 0,
):
    """Turn some groups into melds. keep: indices of groups that must stay concealed
    (and un-kanned). force_kans: at least this many of the called/ankan groups are kans."""
    idx = [i for i in range(len(b.groups)) if i not in keep]
    rng.shuffle(idx)
    melds = []
    used = set()
    kans_made = 0
    # ankan first (triplets only)
    for i in idx:
        if n_ankan <= 0:
            break
        gt, k, codes = b.groups[i]
        if gt == "trip" and b.pool.can(k):
            codes = codes + [b.pool.take(k)]
            melds.append(("a", codes))
            used.add(i)
            n_ankan -= 1
            kans_made += 1
    for i in idx:
        if n_open <= 0:
            break
        if i in used:
            continue
        gt, k, codes = b.groups[i]
        if gt == "seq":
            melds.append(("c", codes))
        else:
            want_kan = kans_made < force_kans or rng.random() < kan_prob
            if want_kan and b.pool.can(k):
                letter = rng.choice("ks")
                melds.append((letter, codes + [b.pool.take(k)]))
                kans_made += 1
            else:
                melds.append(("p", codes))
        used.add(i)
        n_open -= 1
    b.melds = melds
    b.concealed_groups = [g for i, g in enumerate(b.groups) if i not in used]
    return b


def random_meld_counts(rng, closed_only=False):
    """-> (n_open, n_ankan)"""
    n_ankan = rng.choices([0, 1, 2], [88, 10, 2])[0]
    if closed_only:
        return 0, n_ankan
    n_open = rng.choices([0, 1, 2, 3, 4], [45, 22, 15, 10, 8])[0]
    return n_open, n_ankan


# ---------------------------------------------------------------- special shapes


def build_chiitoi(rng, kinds_ok=None, red_bias=1.0, dup_seq=False):
    pool = Pool(rng, red_bias)
    if dup_seq:
        # ryanpeikou-shaped: 2x seq a, 2x seq b, + pair
        s1 = rng.choice(seq_starts())
        s2 = rng.choice([s for s in seq_starts() if s not in (s1 - 2, s1 - 1, s1, s1 + 1, s1 + 2)])
        ks = [s1, s1 + 1, s1 + 2, s2, s2 + 1, s2 + 2]
        rest = [k for k in range(34) if k not in ks]
        ks.append(rng.choice(rest))
    else:
        cands = [k for k in range(34) if kinds_ok is None or kinds_ok(k)]
        if len(cands) < 7:
            return None
        ks = rng.sample(cands, 7)
    codes = []
    for k in ks:
        codes += [pool.take(k), pool.take(k)]
    b = Built(pool, [], None)
    b.special = "chiitoi"
    b.fixed_tiles = codes
    return b


def build_kokushi(rng):
    pool = Pool(rng)
    ks = sorted(YAOCHU)
    codes = [pool.take(k) for k in ks]
    codes.append(pool.take(rng.choice(ks)))
    b = Built(pool, [], None)
    b.special = "kokushi"
    b.fixed_tiles = codes
    return b


def build_chuuren(rng, suit=None):
    suit = rng.randrange(3) if suit is None else suit
    pool = Pool(rng)
    base = [0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 8, 8]
    codes = [pool.take(suit * 9 + d) for d in base]
    codes.append(pool.take(suit * 9 + rng.randrange(9)))
    b = Built(pool, [], None)
    b.special = "chuuren"
    b.fixed_tiles = codes
    return b


def perturb(rng, tiles: list[int], pool: Pool, n: int = 1, kinds=None) -> list[int]:
    """Replace n random tiles with random other tiles from the pool."""
    tiles = list(tiles)
    for _ in range(n):
        i = rng.randrange(len(tiles))
        old = tiles[i]
        try:
            new = pool.random_tile(kinds)
        except ValueError:
            continue
        tiles[i] = new
        # return old tile to the pool
        k = kind(old)
        pool.counts[k] -= 1
        if old in RED_KIND:
            pool.red_used.discard(old)
    return tiles


def random_tiles(rng, n: int, kinds=None, pool=None) -> tuple[list[int], Pool]:
    pool = pool or Pool(rng)
    out = []
    for _ in range(n):
        out.append(pool.random_tile(kinds))
    return out, pool


# ---------------------------------------------------------------- output


class Writer:
    def __init__(self, path: str, prefix: str, header: list[str]):
        self.path = path
        self.prefix = prefix
        self.lines = [f"# {h}" if h else "#" for h in header]
        self.n = 0
        self.seen = set()

    def section(self, title: str):
        self.lines.append("")
        self.lines.append(f"# == {title}")

    def comment(self, text: str):
        for t in text.splitlines():
            self.lines.append(f"# {t}")

    def next_id(self) -> str:
        self.n += 1
        return f"{self.prefix}{self.n}"

    def dedupe_key(self, op, kv):
        return (op, tuple(kv))

    def add(self, rid, request: str, response: str, comments=()):
        for c in comments:
            self.comment(c)
        self.lines.append(request)
        self.lines.append("= " + response)

    def write(self):
        with open(self.path, "w", encoding="utf-8") as f:
            f.write("\n".join(self.lines) + "\n")
