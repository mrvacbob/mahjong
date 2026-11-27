# Design: Mercury entry

Written before the code. A section at the end records where the design moved.

## Modules

| Module | Contents |
|---|---|
| `mj.m` | main loop: read a line, parse `key=value`, dispatch on op, print. Any failure becomes `error=...`. |
| `tile.m` | `suit`, `kind`, `tile`, parsing and printing of mpsz lists and melds, dora successor. |
| `hand.m` | decomposition (nondet), agari forms, shanten, waits. |
| `score.m` | interpretations, yaku and yakuman clauses, fu, payments, choice of the best. |
| `legal.m` | the `legal` op, built from `hand` and `score`. |

## Tiles, hands, melds

```mercury
:- type suit ---> man ; pin ; sou ; honor.
:- type kind ---> kind(suit, int).          % number 1..9, or 1..7 for honors
:- type colour ---> red ; plain.
:- type tile ---> tile(kind, colour).
```

The declaration order is chosen so that Mercury's built-in structural `compare`
is exactly the canonical tile order: suits m < p < s < z, then number, and a red
five (`tile(kind(S,5), red)`) sorts immediately before the plain five. Sorting a
`list(tile)` with `list.sort` therefore yields canonical order; no comparison
function is written.

Melds: `meld ---> meld(meld_kind, list(tile))` with
`meld_kind ---> chi ; pon ; daiminkan ; shouminkan ; ankan`. A predicate
`is_open(meld_kind)` fails only for `ankan`.

**bag versus set.** The concealed hand is a `bag(kind)`: multiplicity is the whole
point (a triplet is "three of this kind"), red is irrelevant to shape, and
`bag.remove`/`bag.remove_smallest` are exactly the moves a decomposition makes.
Where only membership matters I use `set`: the set of wait kinds (the riichi-ankan
rule compares two wait sets for equality), the set of distinct physical tiles a
seat may discard (`set(tile)`, so red and plain fives are distinct members), the
set of printed agari forms (dedup + sort in one step). Red fives are counted from
the original `list(tile)`; they never enter the bag.

The hot path, shanten, does not use the bag. Each suit's nine counts are packed
into one base-5 `int` and the suit's best partial decompositions are computed by
a function under `:- pragma memo`, so each distinct suit shape is solved once per
process.

## Decomposition

Decomposition is a nondeterministic predicate, one clause per way of taking a
group from the smallest remaining kind:

```mercury
:- pred sets(bag(kind)::in, list(group)::out) is nondet.
sets(B, []) :- bag.is_empty(B).
sets(B0, [G | Gs]) :-
    bag.remove_smallest(K, B0, B1),
    ( take_triplet(K, B1, B2), G = triplet(K)
    ; take_run(K, B1, B2),     G = run(K) ),
    sets(B2, Gs).
```

`standard_form(Bag, Pair, Sets)` picks a pair (nondet over kinds with count >= 2)
and calls `sets`. `solutions/2` collects all forms; chiitoi and kokushi are
separate semidet tests. `agari` just prints the solutions.

Shanten: per suit, a memoised search returns the Pareto-best
`{Sets, Partials, Head}` tuples; honors are counted directly; the suits are
combined with `Head` used at most once and `sets + partials <= 4`. Chiitoi and
kokushi are closed formulas. `waits` adds each of the 34 kinds in turn.

## Interpretations, yaku, fu

An interpretation is one way of reading the winning hand:

```mercury
:- type interp
    --->    standard(pair :: kind, groups :: list(mentsu), wait :: wait)
    ;       chiitoi(list(kind))
    ;       kokushi(pair :: kind).
:- type mentsu ---> mentsu(shape, kind, concealment).   % shape: run/triplet/kan
:- type wait ---> ryanmen ; kanchan ; penchan ; tanki ; shanpon.
```

For a standard form, each concealed group containing the winning kind yields an
interpretation (that is where the winning tile went), which fixes the wait. On a
ron, a shanpon triplet is marked open. Melds become `mentsu` with their own
concealment.

Each yaku is one clause of a nondet predicate, so the code for a yaku sits next to
its rule-text condition and nothing else:

```mercury
:- pred yaku(context::in, interp::in, string::out, int::out) is nondet.
yaku(C, I, "tanyao", 1)   :- all_tiles(C, I, is_simple).
yaku(C, I, "honitsu", H)  :- one_suit_with_honors(C, I), H = closed_open(C, 3, 2).
yaku(C, I, "iipeikou", 1) :- closed(C), peikou_count(I) = 1.
```

Exclusions are written into the clause condition (iipeikou needs exactly one
peikou; ryanpeikou needs two). `solutions(yaku(C, I))` gives the yaku list, already
sorted by name. Yakuman are a second nondet predicate `yakuman(C, I, Name, Mult)`;
if it has any solution the ordinary yaku are not consulted. Dora are added after,
and only if at least one real yaku exists.

Fu is a function over an interpretation: base 20, menzen ron 10, tsumo 2, each
mentsu by shape/concealment/terminal, pair (seat and round wind each 2, so a
double wind is 4), wait 2 for kanchan/penchan/tanki; then the fixed cases (pinfu
tsumo 20, chiitoi 25, open 20 -> 30) and rounding.

Choice: every interpretation is scored to a `result`; the best is the maximum
under a comparison `(total, real yakuman over kazoe, han, fu, then the yaku
string reversed)`. For tenhou the interpretations of every possible winning tile
are pooled.

## legal

`legal` composes the other ops:

- `tsumo`/`ron`: build the 14 tiles and call `score`'s evaluator with the flags of
  the request (+ `riichi` when `riichi=1`); legal if the result is not an error.
- `riichi:T`: remove `T`, `min_shanten = 0` and `waits` count > 0.
- riichi `ankan`: `wait_kinds` (complete-hand test over 34 kinds, set(kind)) before
  the draw and after the kan must be equal.
- kokushi robbing an ankan: the kokushi test from `hand`.
- chi/pon/kan: enumerate the physical tile pairs in hand as a `set` of sorted
  two-tile lists, filter by kuikae with a dead-end check.

## Determinism of the main predicates

| Predicate | Determinism |
|---|---|
| `tile.parse_tiles(string, list(tile))` | semidet |
| `tile.parse_meld(string, meld)` | semidet |
| `hand.sets(bag(kind), list(group))` | nondet |
| `hand.standard_form(bag(kind), kind, list(group))` | nondet |
| `hand.is_chiitoi(bag(kind))`, `hand.is_kokushi(bag(kind))` | semidet |
| `hand.agari_forms(bag(kind), int) = list(string)` | det |
| `hand.shanten(bag(kind), int melds) = shanten` | det |
| `hand.suit_best(int) = list(partial)` (memo) | det |
| `score.interpretation(ctx, interp)` | nondet |
| `score.yaku(ctx, interp, string, int)` | nondet |
| `score.yakuman(ctx, interp, string, int)` | nondet |
| `score.fu(ctx, interp) = int` | det |
| `score.evaluate(ctx) = maybe_error(result)` | det |
| `legal.actions(request) = list(string)` | det |
| `mj.handle(string) = string` | det (parse failures are values) |

## Where the design moved (written at the end)

- `interp` has `chiitoi` with no argument (the pair list was never needed: every
  chiitoi yaku is a property of all tiles).
- Shanten: the per-suit search became a memoised dynamic program,
  `block_best(list(int)) = list(partial)` with `:- pragma memo`, where one `step`
  (multi) uses the lowest kind and the recursion is on the remaining counts. The
  Pareto set is kept at every level. Honors are a closed form. The cross-suit
  combination is a direct `best_std` min, not `solutions`.
- `legal`'s input type is `trigger` (`draw` / `discard` / `called`), because
  `event` is a reserved operator in Mercury.
- The tie-break is an explicit `worse/2` predicate over `{total, real, han, fu}`
  and then the yaku string, not a type with user-defined comparison (that makes
  the type non-canonical and poisons determinism).
- Determinism as built: `step/4` is `multi`; `block_best/1` det (memo);
  `completed_by_win/4` semidet; `interpretation/2`, `yaku/4`, `yakuman/4` nondet;
  `evaluate/1` det; `wins/3` semidet; `main/2` is `cc_multi` because it calls
  `exception.try`.

## Finalization changes

- `hand.complete(Bag, NumMelds)` (semidet) is the one definition of a complete
  hand: `14 - 3k` tiles and an agari form. `agari_forms` is `solutions` over the
  same nondet `agari_form`. `wait_kinds` (riichi ankan), `live_tenpai` (riichi)
  and `waits` from tenpai all test completion directly instead of `shanten = -1`.
- `shanten` returns `with_melds(Std) ; no_melds(Std, Chiitoi, Kokushi)`, so the
  "no chiitoi or kokushi with melds" rule is a type; `min_of/1` is the only min.
- `legal.actions` is `solutions(action(R))`: `action/2` is nondet with one clause
  group per trigger (`on_draw/4`, `on_discard/4` multi, `call_on/5`), and each
  clause carries its own guard. The `set` round trip and list assembly are gone.
- `score.result` holds a `payment` (`ron_pay ; dealer_tsumo ; child_tsumo`); the
  total is derived from it and printing is `payment_to_string`.
- `evaluate` collects distinct `{ctx, interp}` readings before scoring them.
- Validation moved to the boundary (`mj.dispatch`): hand size per op, physically
  possible tiles (`tile.physically_possible`), no repeated keys, exactly one
  `legal` trigger (and `called` must be one of `melds`, with `took` in it), and
  `honba` 0..999, `wall` 0..70, `kans` 0..4. The core assumes well-formed input.
