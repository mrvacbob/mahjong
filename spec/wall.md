# The wall and the seeded shuffle

Status: written for Phase 3 package A. The engine (`Sources/Riichi/Wall.swift`)
implements exactly this; the three vectors at the end are checked by its unit tests
and were produced by a second, independent implementation written from this text.

A wall is the 136 tiles of one hand in a fixed order. Seeded play derives every
hand's wall from a 64-bit game seed and the number of hands dealt so far, so a
whole game is reproducible from the seed and the decisions made.

All arithmetic below is on unsigned 64-bit integers, wrapping modulo 2^64. `^` is
exclusive or, `<<` and `>>` are logical shifts, `rotl(x, k)` is
`(x << k) | (x >> (64 - k))`.

## 1. Tiles and the starting order

Tiles are written in mpsz (`spec/formats.md`): `0m`, `0p`, `0s` are the red fives.
The tile set is four copies of each of the 34 kinds, where for each suit's five one
copy is red and three are plain.

The **starting order** `S[0..135]` is the canonical order: kinds `1m`…`9m`,
`1p`…`9p`, `1s`…`9s`, `1z`…`7z`, four tiles per kind, and within a five the red copy
first. So `S[0..3]` = `1m 1m 1m 1m`, `S[16..19]` = `0m 5m 5m 5m`, `S[132..135]` =
`7z 7z 7z 7z`. In general `S[4k + c]` is kind `k` (0-based, in the order just
given), red exactly when `k` is a five of a suit and `c = 0`.

## 2. Seeding

Inputs: `seed`, any 64-bit unsigned value, and `hand`, the number of hands already
dealt in this game (0 for the first hand of the game; a repeated dealership or a
draw counts as a new hand, so every hand gets a new wall).

```
G   = 0x9E3779B97F4A7C15
key = seed + hand * G            (mod 2^64)
```

SplitMix64 produces the four words of the generator state from `key`:

```
x = key
repeat 4 times:
    x = x + G
    z = x
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB
    output z ^ (z >> 31)
s0, s1, s2, s3 = the four outputs, in order
```

(The four outputs are distinct, so the state is never all zero.)

## 3. The generator: xoshiro256**

```
next():
    result = rotl(s1 * 5, 7) * 9
    t  = s1 << 17
    s2 = s2 ^ s0
    s3 = s3 ^ s1
    s1 = s1 ^ s2
    s0 = s0 ^ s3
    s2 = s2 ^ t
    s3 = rotl(s3, 45)
    return result
```

**Bounded sampling.** `below(n)`, for `1 <= n <= 136`, returns an integer uniform on
`0 .. n-1`:

```
below(n):
    threshold = 2^64 mod n        (equivalently (0 - n) mod n in 64-bit arithmetic)
    loop:
        r = next()
        if r >= threshold: return r mod n
```

Outputs below `threshold` are rejected and the loop draws again. Each call consumes
one or more outputs of `next()`; for these small `n` a rejection is very rare
(probability below 2^-56), but an implementation must still loop.

## 4. The shuffle

Fisher–Yates from the end, over a copy `W` of `S`:

```
W = S
for i = 135 down to 1:
    j = below(i + 1)
    swap W[i] and W[j]
```

`W` is the wall.

Check values for `key = 0`: SplitMix64 outputs `0xe220a8397b1dcdaf`,
`0x6e789e6aa1b965f4`, `0x06c45d188009454f`, `0xf88bb8a8724c81ec`; the first three
outputs of `next()` are `0x99ec5f36cb75f2b4`, `0xbf6e1f784956452a`,
`0x1a5f849d4933e6e0`; the first three `j` of the shuffle are 124, 107, 24.

## 5. Layout

Index into `W` (as in `docs/design/engine.md` §3):

| Indices | Use |
|---|---|
| `0..51` | The deal. For `i` in `0..11`, tiles `4i..4i+3` go to the seat `i mod 4` places after the dealer (three rounds of four). Then tile `48 + j` goes to the seat `j` places after the dealer. The dealer's 13 are indices 0–3, 16–19, 32–35 and 48. |
| `52..121` | The 70 live draws, in order; index 52 is the dealer's first draw. |
| `122..125` | The four replacement tiles, in the order drawn. |
| `126..130` | The dora indicators, in the order revealed (126 is shown at the start). |
| `131..135` | The ura indicators: `131 + k` lies under `126 + k`. |

Live tiles left = 70 − live draws made − completed kans. Each completed kan
shortens the live wall by one from its far end, so with `k` kans the last live draw
is index `121 − k`; the replacement and indicator indices never move.

## 6. Notes for other languages

- JavaScript: carry seeds as decimal strings and use `BigInt` with `& 0xFFFFFFFFFFFFFFFFn`
  after every multiplication and addition. A `Number` cannot hold a 64-bit seed.
- The seed never appears in anything a seat is shown.
- `(seed, hand)` and `(seed + G, hand − 1)` give the same key, and so the same wall.
  Seeds chosen independently collide this way with probability about 2^-64 per pair;
  consecutive seeds never do.

## 7. Test vectors

Each wall is 136 tiles in index order, 17 per line.

### Vector 1: seed `0`, hand `0` (key `0x0000000000000000`)

```
4m 2p 3s 8s 5p 0s 3p 4m 6p 8m 3z 2p 6p 7p 2m 6z 1p
6m 5p 6m 3z 9p 5s 6p 2p 3m 1s 8p 1m 4z 6z 3p 3m 2m
2z 4m 6s 4m 4p 8s 6m 5s 2s 1s 2m 1z 3m 7m 5s 1s 7p
9m 7z 2p 8p 7s 8m 1z 1s 5z 8p 9s 4s 4s 2m 7s 7p 2s
1z 2z 7z 6p 9s 3z 9m 7z 3s 8m 2s 1m 2s 5m 6z 9p 7m
1p 3s 3p 4z 4p 6s 5z 1m 4s 1m 2z 7s 9s 7m 5z 9m 4p
1p 5m 3p 8s 6s 1p 7z 4z 5p 6z 8m 3m 1z 8s 9p 9m 8p
0p 5m 4s 3z 0m 9p 6m 7s 4p 4z 6s 7p 3s 2z 7m 9s 5z
```

### Vector 2: seed `20261127`, hand `3` (key `0xdaa66d2c7f149d46`)

```
0p 2p 1z 8s 8m 3p 1s 7s 4p 7s 2p 4s 9s 9s 7s 8p 3m
3z 3s 1p 9s 5p 2z 3s 8m 5m 4p 2m 5z 9p 1s 6z 2s 2s
1m 9m 3m 2z 7m 4z 9s 3s 1m 7m 5m 5s 3z 6z 5z 8p 1z
3m 6m 8p 2z 2p 4m 9m 9m 5s 9m 2p 8s 4z 6z 4s 7p 1p
6p 7z 4m 4p 5p 6p 2s 1z 9p 6z 8s 3z 5p 0s 2m 2s 1p
4s 3z 7z 5s 7m 8s 5z 6m 9p 3p 3p 6s 8m 2m 3p 4s 6m
0m 7z 2z 1z 7z 1m 1s 5z 4z 6s 3m 6p 7p 7m 6m 2m 7s
5m 4m 8m 4p 8p 4z 9p 4m 1s 6s 3s 7p 1m 6s 6p 1p 7p
```

### Vector 3: seed `18446744073709551615`, hand `7` (key `0x538454127b096492`)

```
2z 5s 2m 8p 9p 8m 4p 3z 9s 6z 1m 3p 9m 8p 6m 7s 2m
4s 2z 4p 9p 5z 1m 6s 7s 6s 1z 1z 6s 2z 8p 6p 1s 8m
1p 8s 3p 5p 9m 3m 1s 3p 4p 4s 7z 7z 2m 3m 3z 6p 6m
4p 2s 6z 7z 9s 2p 6s 3p 1z 4s 5m 4m 7m 3m 5s 3m 5z
5z 6m 3s 0p 7p 2p 9s 0m 4z 7m 8m 4s 1s 8s 2s 7p 9s
7s 7p 4z 7z 8p 6p 2s 3s 9m 3s 1z 3z 4m 9p 2m 1s 0s
2z 5z 1m 9p 3s 2s 6p 1p 8s 5s 5p 5p 6z 7s 5m 1p 6m
6z 4m 4z 2p 7m 2p 9m 4m 7p 1p 3z 5m 7m 1m 8s 4z 8m
```
