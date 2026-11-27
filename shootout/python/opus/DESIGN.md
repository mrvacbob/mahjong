# Design: Python entry (opus)

Written before the code; see "What moved" at the end.

## Modules

| File | Contents |
|---|---|
| `tiles.py` | `Tile` (kind + red flag), kind arithmetic, mpsz parsing/printing, `Meld`, dora successor |
| `hand.py` | decomposition into groups (`agari`), shanten (std / chiitoi / kokushi), waits |
| `yaku.py` | the yaku and yakuman registry: one decorated predicate per rule-table row |
| `scoring.py` | interpretations of a win, fu, han, payment, choice of best interpretation |
| `legal.py` | the `legal` op, built from `hand` and `scoring` |
| `main.py` | the line protocol: parse `key=value`, dispatch on op, format, catch errors |

## Tiles, hands, melds

A tile *kind* is an `int` 0..33: `9*suit + (digit-1)` for m/p/s (suit 0..2), and
27..33 for the honors 1z..7z. Ordering kinds as ints is exactly the canonical
order, so sorting needs nothing special. A physical `Tile` is a frozen
`NamedTuple(kind, red)`; red only matters for aka counting and for `legal`
(where `0m` and `5m` are distinct actions), so everything structural works on a
*count vector* `list[int]` of length 34 (`Counts`). Printing a tile list sorts by
`(kind, not red)` so that `0` comes immediately before `5`.

A `Meld` is a frozen dataclass: `MeldType` enum (CHI, PON, DAIMINKAN, SHOUMINKAN,
ANKAN) + the tuple of tiles. It exposes `kind` (lowest kind), `is_open`
(everything but ANKAN) and `is_kan`.

## Decomposition

A completed group is `Group(shape, kind, open)` with `Shape` = PAIR, SEQ,
TRIPLET, KAN. Standard decomposition is a recursive generator over the count
vector: take the lowest remaining kind and either make it the pair (once), a
triplet, or the start of a sequence. Because it always consumes the lowest kind
it never produces the same decomposition twice by reordering. Chiitoi and kokushi
are recognised by count checks, not by search. `agari` prints the concealed
groups; scoring adds the melds as already-fixed groups.

Shanten uses the textbook formula `8 - 2*sets - partials - pair` with
`sets + partials <= 4`, ignoring availability. Each suit is searched
independently (memoised on the suit's count tuple with `functools.cache`) for the
achievable `(sets, partials, pair)` triples, keeping only the best `partials` for
each `(sets, pair)`; suits are then combined by the same dominance. Waits = kinds
with a live copy whose addition lowers `min` shanten.

## Yaku

Each yaku is a function decorated with its name and han, mirroring a row of the
table in `spec/rules.md` §2:

```python
@yaku("tanyao", closed=1, open=1)
def tanyao(w: Win) -> bool:
    """Only 2-8 numbered tiles."""
    return all(is_simple(k) for k in w.all_kinds)
```

`closed=` / `open=` are the han in each state, `open=0` meaning "closed only"
(the registry enforces that, so predicates don't repeat the menzen test).
Yakuman use `@yakuman("daisuushii", mult=2)`. Predicates take a `Win`: one
interpretation (all five groups including melds with open/closed status *after*
the ron-on-shanpon rule, the wait, the win tile, flags, seat/round winds, and the
full tile count vector). Variants that are distinct names in the spec (suuankou vs
suuankou_tanki, kokushi vs kokushi_13, chuuren vs junsei_chuuren) are separate
predicates. Exclusions that aren't implied by definitions (ryanpeikou over
iipeikou) are expressed in the predicate. Situational yaku read flags only.

## Fu and interpretation choice

`scoring.interpretations()` yields one `Win` per (decomposition, which concealed
group the winning tile completed): this choice decides the wait (tanki, shanpon,
kanchan, penchan, ryanmen) and whether a ron-completed triplet is open. Chiitoi
and kokushi add their own. For `tenhou` the outer loop also ranges over every
distinct tile as the winning tile. Each `Win` is evaluated to a `Result` (yaku
list, han, fu, payments, total); fu follows the §3.1 table line by line in
`fu()`. The best result is `max` over a key implementing the tie-break:
`(total, real yakuman, han, fu)` then the smallest yaku string. No yaku in any
interpretation is `no_yaku`; no interpretation at all is `not_agari`. (Since
finalization these come back as a `NoWin` `StrEnum` value, `best() -> Result | NoWin`,
not as an exception.)

## legal

`legal.py` composes the other modules: `tsumo`/`ron` = `scoring.best()` returns a
`Result` with the situational flags (plus `riichi` if `riichi=1`); `riichi:` = for
each distinct discard, some kind in `hand.winning_kinds()` (kinds whose addition
completes the hand, a fifth copy included) still has a copy outside the hand and
melds, scanned only when the 14-tile hand is at shanten <= 0; riichi-`ankan`
compares `hand.winning_kinds()` before the draw and after the kan; kuikae is a
function of the called `Meld` and the taken kind, and `after_call` (the `called`
case) is also how a dead-end chi or pon is detected: a call is offered only if
`after_call` on the remaining hand is non-empty. Calls are enumerated over physical
tiles so red/plain variants come out as separate actions.

## What moved

Little. `Win`, `Wait` and `FormType` live in `yaku.py` (the predicates' input type
sits next to the predicates) rather than in `scoring.py`, which avoids an import
cycle. `Win` is the one dataclass without `slots=True`, because its derived views
(`seqs`, `pons`, `pair`, ...) are `functools.cached_property`, which needs an
instance `__dict__`. The dead-end-call test is applied to `pon` as well as `chi`.

Finalization (see NOTES.md): riichi tenpai and riichi-ankan both test completion
directly through `winning_kinds` instead of going through `waits`/shanten; the
`not_agari`/`no_yaku` outcomes are a `NoWin` enum instead of an exception; the
"chiitoi/kokushi only without melds" rule is carried by their 14-tile count alone;
flag-only yaku and the three dragon yakuhai are registered from small tables rather
than one function each.
