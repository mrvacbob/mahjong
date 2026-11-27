# P2 shootout review: opus

Reviewer: opus. Reviewed the eight non-opus entries: `shootout/{swift,python,haskell,mercury}/{codex,agy}`.

## What I did and did not do

- I read all source files of the eight entries except as noted below, plus every DESIGN.md and NOTES.md, `spec/formats.md` in full, the parts of `spec/rules.md` I needed, and `docs/reviews/p2/measurements.md`.
- I only skimmed these: the request parsers (`swift/agy/Sources/mj/Main.swift`, `python/agy/mjlib/cli.py`, `haskell/agy/src/Main.hs`, `mercury/agy/mj.m`), `haskell/agy/src/Shanten.hs` and `Tile.hs`, `mercury/agy/tiles.m`, the suit-combining code in `mercury/agy/shanten.m`, and the call helpers in `mercury/agy/legal.m` (`pon_actions`, `chi_actions`).
- I did not read `shootout/*/opus` or the other reviewers' files.
- **Mercury.** At first the Mercury entries were missing from this checkout. I reviewed them from the coordinator's worktrees (`../wt/{codex,agy}/shootout/mercury/*`). When they appeared under `shootout/mercury/`, I diffed them against those copies: the source is identical. I rebuilt both in place with `build.sh`, and both pass the corpus (12,434/12,434). Everything said about Mercury below applies to the in-repo copies.
- **Builds.** All eight build from clean with their `build.sh`. The only warning was the macOS linker's SDK search-path warning on the two Haskell builds.
- **Differential testing.** I wrote a random request generator (in my scratchpad, not in the repo). It deals hands from a real 136-tile wall with one red five per suit. It biases toward one-suit, half-flush, honors-only, terminal and all-green hands, random melds of every type, and consistent flags. I ran it against all eight entries:
  - For agari, shanten, waits and score I compared each entry with `tools/oracle_mj.py`: 25,000 cases per op, plus 4,000 per op on a second seed.
  - For legal there is no oracle, so I compared the entries against their majority answer: 35,000 cases. The generator produced riichi hands only when tenpai, and post-call states only when a legal discard remains.
- **Fuzz result.** No entry disagrees with the oracle, or with the legal majority, on any valid input. Every difference traced back to input that cannot occur, and to my own generator mistakes:
  - ippatsu together with rinshan (both stated in the 6 score "failures");
  - riichi while `first=1`;
  - riichi on a non-tenpai hand;
  - duplicate keys.

  So for the latent-bug sections below I relied on reading the code and on hand-written inputs.

## Part A: per language

### Swift: codex (770 lines) vs agy (1983 lines)

**Rule fidelity, side by side.**

Kuikae:

```swift
// codex Legal.swift
private func kuikae(took: Int, sequenceStart: Int?) -> Set<Int> {
    var forbidden: Set<Int> = [took]
    if let start = sequenceStart {
        if took == start, start % 9 <= 5 { forbidden.insert(start + 3) }
        if took == start + 2, start % 9 >= 1 { forbidden.insert(start - 1) }
    }
    return forbidden
}
```
```swift
// agy Legal.swift
var forbidden: Set<TileKind> = [took]
if took == baseKind {
    if let other = baseKind.offset(3) { forbidden.insert(other) }
} else if took.rank == baseKind.rank + 2 {
    if let other = baseKind.offset(-1) { forbidden.insert(other) }
}
```

The two are equivalent. agy's `TileKind.offset` returns nil at the suit edge, so the edge check lives in the type rather than in `% 9` arithmetic. Both entries apply the same predicate to filter `called` discards and to prune dead-end `chi:`.

Riichi ankan:

```swift
// codex
guard structuralWaits(hand) == structuralWaits(afterKan) else { continue }
// agy
let waitsBefore = Shanten.structuralTenpaiWaits(handBeforeDraw, meldCount: melds.count)
afterCounts.remove(drawnKind, count: 3)
let waitsAfter = Shanten.structuralTenpaiWaits(afterCounts, meldCount: melds.count + 1)
return waitsBefore == waitsAfter
```

Both are stated once and match the spec.

Sanankou and ron on a shanpon:

```swift
// codex Score.swift: the ron triplet is opened in the interpretation, yaku read a count
if !tsumo && wait == .shanpon { interpreted[index].open = true }
...
if standard.concealedTriplets == 3 { yaku["sanankou"] = 2 }
```
```swift
// agy Score.swift: a declarative table entry
YakuRule(name: "sanankou", closedHan: 2, openHan: 2) { _, h in
    h.isStandard && h.concealedTripletCount == 3
}
```

agy has the better rule fidelity. Every yaku is one table entry with its name, closed han, open han and predicate. codex is one 100-line `evaluate` closure that writes into `[String: Int]` (`yaku["chinitsu"] = closed ? 6 : 5`). It is still readable, but it is ordered by code convenience, not by the rule list. agy uses a sentinel for closed-only yaku (`openHan: 0 // 0 means closed-only`), which a `Han?` or an enum would express better.

**Structure.**
- codex: kinds are bare `Int` (`seat == 27` means dealer). `Tile` is `{kind, red}`. `Form` is an enum. `Group.open` is a mutable `var` that scoring flips on a copy. A meld becomes a `Group` through `meld.group`.
- agy: `TileKind` is a validated `RawRepresentable` wrapper, with `Suit` and `Wind` enums and a `ScoreFlags` OptionSet.
  - Agari `Group` is kept apart from scoring's `ResolvedSet(kind:base:isConcealed:)`.
  - `HandInterpretation.Shape` separates standard, chiitoi and kokushi.
  - This is the more type-driven design: the decomposition/interpretation split exists in the types.

**Idiom.** Both are idiomatic Swift. agy uses `InlineArray`, `Comparable` conformances that encode the canonical order, and key paths. It is also very verbose: `Tiles.swift` alone is 397 lines. codex is the Swift a pragmatic engineer would write: nested functions with explicit backtracking.

**Latent bugs.**
- **agy: decomposition ignores leftover tiles.** `extractSets` stops as soon as `setsLeft == 0`, without checking that the counts are empty, and nothing upstream validates hand size. A 15-tile hand is therefore "complete":
  ```
  a agari hand=222333444555667s melds=-
  -> win=1 forms=222s,333s,444s,555s,66s;...          (the 7s is silently dropped)
  b score hand=22233344455566s melds=- win=6s by=ron seat=S
  -> yaku=suuankou_tanki:2 yakuman=2 pay=ron:64000 total=64000
  ```
  The spec does not test malformed input. Still, in a full engine an off-by-one in the state machine (for example, a draw that was never removed) would be scored as a yakuman instead of failing loudly. The fix is one line: require all counts to be zero at `setsLeft == 0`.
- agy: `Meld.parse` accepts any tiles (`c111m` parses as a chi).
- codex validates sizes and copy counts and rejects bad melds. It does not count the `win` tile against the four-copy limit: a 5th copy of a kind is accepted in `score`.
- I found nothing in either entry that the corpus misses on valid input.

**Shortcuts.** None in either: no corpus reads, no tables.

**NOTES.**
- codex reports zero failed build/test cycles. That is plausible given the code, and the log is thin.
- agy logs one real corpus-caught bug: kokushi accepted 13 orphans plus a simple tile. That is the same bug codex hit in Python and agy hit in Swift, Haskell and probably Python. Swift itself cost neither model anything.

**Pick: codex**, narrowly.
- For: it is less than half the size, it validates input, and it was faster on `legal` (67k vs 31k req/s).
- Against: agy's types are the better base for a full engine.

Before judging, clean up codex:
1. Introduce a `TileKind`/`Wind` type in place of `Int` and `27`.
2. Make yaku a `String`-raw-value enum, so that spellings are checked.
3. Replace the mutated `Group.open` with an explicit interpretation struct.
4. Count `win` in the copy check.

If agy were kept instead, it would need the leftover-tile fix, meld validation and size checks.

### Python: codex (631 lines) vs agy (1364 lines)

**Rule fidelity.**

Pinfu:

```python
# codex scoring.py: pinfu as "no fu at all"
("pinfu", 1, f.closed and f.pair is not None and f.extra_fu == 0),
```
```python
# agy yaku.py: pinfu as the rule states it
def _is_pinfu(v):
    if not v.is_closed: return False
    if v.wait is not WaitType.RYANMEN: return False
    if v.pair in DRAGONS or v.pair == v.seat or v.pair == v.round_wind: return False
    return all(s.is_seq for s in v.sets)
```

codex's version is correct: with a closed hand, zero extra fu forces all sequences, a valueless pair and a ryanmen wait. But it derives the yaku from the fu calculation, so a reader has to prove the equivalence.

Kuikae:

```python
# codex actions.py
if called_kind == first and first % 9 < 6: forbidden.add(first + 3)
if called_kind == first + 2 and first % 9 > 0: forbidden.add(first - 1)
```
```python
# agy legal.py
if took_kind == meld_base and ((meld_base + 2) % 9) < 8:
    forbidden.add(meld_base + 3)
```

agy's edge test is correct but obscure.

Riichi ankan:
- codex: `set(winning_kinds(hand, structural=True)) != set(winning_kinds(after, structural=True))`. This matches the spec.
- agy: `if b_sh == 0 and a_sh == 0 and b_waits == a_waits`. It adds a tenpai precondition the spec does not have. It only matters for an impossible input (riichi on a non-tenpai hand), but it is an unrequested rule.

**Structure.**
- codex: red fives are ints 34–36 and kinds are ints 0–33, both typed `tuple[int, ...]` and kept apart only by calling `kind()`. That is convention, not types.
- agy: has a real `Tile(kind, is_red)` dataclass and a `HandSet`/`HandView`, so it is better typed.
- agy duplicates rules. The chiitoi path re-lists riichi, double_riichi, ippatsu, tsumo, haitei, houtei, chankan, tanyao, honroutou and the flushes by hand (`if "riichi" in flags: yk.append(("riichi", 1))`). Kokushi re-lists tenhou and chiihou. Each such rule now lives in two places.

**Idiom.** codex is idiomatic modern Python:
- `@lru_cache` suit profiles;
- generators of `(name, value, applies)` triples;
- a `Score.order()` tuple key.

agy is more Java-like: 13-parameter functions with keyword arguments.

**Latent bugs.** None found on valid input. Neither entry catches anything except `ValueError`/`KeyError`/`IndexError` around a request, so any other exception would kill the process. Python agy and Mercury agy answer `shanten hand=1z melds=-` with `std=8 ...` instead of an error; that is harmless.

**NOTES.**
- codex is candid. It logs the kokushi bug, which failed 9 cases across three ops, and its own early `git status`.
- agy claims 12,434/12,434 on the first run. Its DESIGN.md describes kokushi as "all 13 yaochu kinds have `counts[k] >= 1` and total tiles is 14", which is exactly the buggy rule its other entries hit. The code is correct, so the design text is stale.

**Pick: codex.** Smaller, memoized, validates input, rules in one place each.

Cleanup before judging:
1. Give tiles and kinds distinct types, for example `NewType` or a `Tile` dataclass.
2. State pinfu by its rule and keep the fu identity as an assertion.
3. Broaden the exception guard in `main`.

### Haskell: codex (626 lines) vs agy (1363 lines)

**Rule fidelity.**

Sanankou and suuankou:

```haskell
-- codex Score.hs: rule rows, with positional Bool patterns
, ("sanankou", 2, length [() | Set _ ty True <- sets, ty /= Run] >= 3)
...
, ("suuankou", 1, fourConcealed && wait == DoublePair)
, ("suuankou_tanki", 2, fourConcealed && wait == Single)
```
```haskell
-- agy Score.hs: one function per rule
ymSuuankou _ (StandardShape _ ms wt)
  | length (filter isClosedTriOrKan ms) == 4 =
      if wt == Tanki then [("suuankou_tanki", 2)] else [("suuankou", 1)]
ykSanankou _ (StandardShape _ ms _)
  | length (filter isClosedTriOrKan ms) == 3 = [("sanankou", 2)]
```

Kuikae:

```haskell
-- codex Legal.hs
allowedAfter c run took tile = k /= took && k `notElem` otherEnd
  where otherEnd = case (c, delete took run) of
          (Chi, [a,b]) | b == a+1 -> filter ((==suit took) . suit) [if took < a then b+1 else a-1]
          _ -> []
```
```haskell
-- agy Legal.hs
kuikaeForbidden (Meld Chi ts) took = case sort (map tileKind ts) of
  [a, b, c] | took == b -> [b]
            | took == a -> a : [TileKind (unKind c + 1) | kindRank c < 9]
            | took == c -> c : [TileKind (unKind a - 1) | kindRank a > 1]
```

codex's version reads directly as the spec's "if the two tiles used from hand are adjacent ... the tile at their other end".

Riichi ankan:
- codex: `not active || (k == kind tile && waitsBefore == structuralWaits (meldCount+1) (filter (/=k) drawnKinds))`
- agy: `beforeWaits == afterWaits` over `structuralWaits`

Both match the spec.

**Structure.**
- codex: `data Pattern = Normal Kind [Set] Wait | Pairs | Kokushi` and a `Set { setType :: SetType, concealed :: Bool }`. Decomposition (`Shape`/`Group`) is kept apart from interpretation (`Pattern`/`Set`). `Kind` is a type alias for `Int`. Flags are `[String]`.
- agy:
  - It has a `newtype TileKind`, a `Flag` ADT, a `Wind` type and `ScoreResult` as a sum type. That is better typing.
  - It reuses `GroupKind = Pair | Seq | Triplet | Kan` both for concealed groups and for interpreted `Mentsu`, so `Mentsu Pair` is representable and `mentsuFu` needs a dead case for it.
  - Errors are `ScoreError String`.

**Idiom.**
- codex is idiomatic: comprehensions, `maximumBy (comparing priority)` with `Down (names r)`.
- agy is idiomatic too, and uses `ST`/`STUArray` for the suit DFS.

**Latent bugs and performance.**
- **agy: the same leftover-tile bug as Swift agy.** `decomposeSets _ 0 _ _ = [[]]` ignores the remaining tiles. The two failing lines quoted under Swift give the same wrong answers here (`suuankou_tanki` for a 15-tile hand).
- **codex: standard shanten is an unmemoized exponential search.** `suitProfiles` enumerates every partition of a suit as `(sets, partials, head)` triples and then deduplicates them with `unique`. On one-suit hands it collapses:
  - 2,000 random 13-tile one-suit `waits` requests take **22.6 s (88 req/s)** with haskell/codex;
  - the same requests take 1.9 s with haskell/agy and 0.07 s with swift/codex;
  - the measured corpus rate, 4,043 shanten req/s, is the best case.

  A bot doing millions of shanten calls on chinitsu-leaning hands would stall. Memoizing the profiles by packed suit counts would fix it. This is a model's choice, not a language limit: agy got 47k req/s.

**NOTES.**
- codex: honest and short. It logs only warnings, and GHC's `-Wx-partial` warnings led it to remove `head`.
- agy: logs a real compile failure (constructor arity), a type-defaulting warning and the kokushi corpus bug.

**Pick: codex**, for its idiom and the separation between shapes and interpretations.

Cleanup before judging:
1. Memoize `suitProfiles`. This is a must; as it stands, its shanten throughput is the worst of all eight.
2. Replace `flags :: [String]` with a `Flag` ADT, as agy has.
3. Make `Kind` a `newtype`.

### Mercury: codex (832 lines) vs agy (1996 lines)

This is the language the owner cares most about, so I go into more detail here.

**Rule fidelity.** The two entries differ most here, and codex is the best of all eight entries on this criterion.

In codex, yaku are clauses of one nondet relation, and the head of each clause carries the protocol name and value:

```mercury
% codex scoring.m
:- pred ordinary(facts::in, method::in, context::in, string::out, int::out) is nondet.
ordinary(F, tsumo, _, "tsumo", 1) :- F ^ hand_exposure = concealed.
ordinary(F, _, _, "sanankou", 2) :- F ^ concealed_pungs = 3.
ordinary(F, _, _, "shousangen", 2) :- F ^ dragons = 2, is_dragon(F ^ head).
ordinary(_, tsumo, C, "haitei", 1) :- has_flag(C, "haitei").
ordinary(_, ron, C, "chankan", 1) :- has_flag(C, "chankan").
natural(F, _, _, _, "daisangen", 1) :- F ^ dragons = 3.
natural(F, _, _, _, Name, Mult) :-
    F ^ concealed_pungs = 4,
    ( if F ^ wait = single then Name = "suuankou_tanki", Mult = 2
      else Name = "suuankou", Mult = 1 ).
```

`solutions` collects them. A rule's situational precondition (haitei only on tsumo, chankan only on ron) is in the clause head, where a riichi player would look for it.

agy chains if-then-else list fragments, which its own NOTES calls out as the thing it would change:

```mercury
% agy score.m
Sanankou = ( if count_closed_triplets_or_kans(Groups) >= 3
             then [yaku_entry("sanankou", 2)] else [] ),
...
FormYaku = Pinfu ++ Tanyao ++ Peikou ++ Yakuhai ++ Toitoi ++ Sanankou ++ ...
```

Kuikae:

```mercury
% codex actions.m
allowed_discard(Call, Took, Start, T) :-
    K = kind_of(T), K \= Took,
    not ( Call = chi, suit(K) = suit(Took),
          ( Took = Start, K = Start + 3 ; Took = Start + 2, K = Start - 1 ) ).
```
```mercury
% agy legal.m
( if TookKind = num(S, R1), R1 + 3 =< 9 then
    Forbid = set.list_to_set([TookKind, num(S, R1 + 3)])
  else if TookKind = num(S, R3), R3 - 3 >= 1 then
    Forbid = set.list_to_set([TookKind, num(S, R3 - 3)])
  ...
```

Riichi ankan:
- codex: `structural_waits(kinds(Hand), N) = structural_waits(kinds(Rest), N + 1)`
- agy: `WaitsBefore = WaitsAfter` over `set(tile_kind)`

Both are set equality, which is exactly the rule.

**Structure.**
- codex:
  - `kind == int`;
  - `tile ---> tile(kind, bool_red)` with `bool_red ---> plain ; red`;
  - `group ---> group(kind, role, exposure)` with `exposure ---> concealed ; exposed`.

  The `facts` record distinguishes the hand's exposure (`hand_exposure`) from a group's exposure, so a ron shanpon cannot open the hand for closed yaku. Flags are `set(string)`, and the tables use their own boolean types (`in_riichi ; free`, `furiten ; clear`).
- agy: has the best tile typing of all eight entries:
  ```mercury
  :- type tile_kind ---> num(num_suit, int) ; wind(wind) ; dragon(dragon).
  :- type tile ---> tile(kind :: tile_kind, is_red :: is_red).
  :- type flag ---> flag_riichi ; flag_double_riichi ; ...
  ```
  - The constructor order gives the canonical mpsz order through standard term ordering.
  - Concealed groups (`pair(K) ; seq(S, N) ; triplet(K)`) are separate from `scored_group` (`sg_seq/sg_triplet/sg_kan` with `is_open`).
  - It has a defect: `concealed_to_closed_sg(pair(K)) = sg_triplet(K, closed)` turns a pair into a "triplet" if it is ever called on one. It is only called on non-pair groups, which is enforced by convention, not by type.
  - Several det functions invent dummy values instead of failing or throwing, which would hide engine bugs:
    - `remove_one_of_kind(_, [], tile(wind(east), plain), [])`;
    - `meld_to_scored_group` maps an honor chi to `sg_triplet`;
    - an empty meld becomes `sg_triplet(wind(east), open)`.

**Idiom: nondeterminism, modes and determinism.**
- codex carries the logic in nondeterminism:
  - `standard_groups` and `take_set` are `nondet` relations;
  - `interpret` is `nondet`: it picks the winning group with `list.delete(Groups, Winner, Rest)`;
  - `natural` and `ordinary` are `nondet`;
  - `action/6` is a single `nondet` predicate whose disjuncts are the action kinds;
  - `legal/5` is `det` via `solutions`;
  - `complete/2` and `remove_kind` are `semidet`.

  The one smell is `can_win/5`, which uses `promise_equivalent_solutions []` to commit to the first witness of a nondet goal. It is correct here, but it is a promise the compiler cannot check. A `semidet` existential (`some [...]`), as agy uses in `is_agari`, would be cleaner.
- agy uses nondeterminism for decomposition (`decompose_std`, `decompose_groups`), interpretation (`enumerate_interp`, `assign_wait`, `select_group`) and the tenhou win choice (`choose_win_split is multi`), which is good. Everything else is det functional code:
  - the yaku come from `++` chains;
  - shanten is a `det` DFS threading `!Best` state variables, which is an imperative search in Mercury syntax;
  - legal is a sequence of `filter_map` calls.

  agy's DESIGN.md gives determinism declarations for the main predicates, as the brief asked; codex's states them in prose.

**Bag versus set.**
- codex uses a **sorted `list(kind)`** as the multiset during search, not `bag`. The pivot is the list head, so `standard_groups([K | Ks], ...)` with `Ks = [K | Rest]` is a pair, and `take_set(K, [K, K | Rest], triplet, Rest)` is a triplet: pattern matching does the bag operations. It uses `bag(kind)` only where multiplicity is counted, for copies outside the hand (`owned/2`, `bag.count_value(Bag, K) < 4`) and for dora indicators. It uses `set` for flags and for the structural-wait sets compared in riichi ankan. Each choice is correct for its use, and the sorted list helps the search read like the rule. The weakness is that flags are `set(string)`, so a misspelt flag fails silently.
- agy uses **`bag(tile_kind)` for the hand throughout decomposition** (`bag.remove_smallest`, `bag.remove`). The resulting `decompose_groups` is the clearest statement of "take the smallest tile as a triplet or a run" in any of the eight entries. It uses `set(tile_kind)` for wait sets, kuikae-forbidden kinds and kyuushu kinds, and `set(flag)` for flags. All of these uses match the mathematics.
  - Where bag hurts: shanten wants per-suit count vectors, so agy converts the bag to `list(int)` per suit anyway (`num_suit_counts`).
  - `bag.to_assoc_list` and the bag removals are not free, but agari throughput is about the same either way: 163k req/s for agy, 174k for codex.

  So in Mercury, `bag` helps readability for decomposition, is neutral to slightly negative for performance, and is the wrong representation for shanten. Neither entry uses `set` where a multiset is needed. Dora indicators are a multiset, and both handle them correctly: codex folds over the indicator list into a bag count, and agy uses a bag.

**Latent bugs and performance.**
- No wrong answers on valid input from either entry. Both reject the 15-tile hands; both decompositions require all tiles to be consumed.
- codex rejects non-canonical tile lists (`Suit > Prev` in `parse_suits`); for example `hand=12345678m11z123s` gets `error=bad_input`. That is stricter than the spec requires, and fine.
- codex's `best_partition` shanten is an unmemoized search: 364 req/s on 2,000 random one-suit `waits`, against 1,451 for agy. It is acceptable for the slice and would need memoizing for bots.
- agy precomputes the four suit tables and recomputes only the changed suit per candidate draw. That took waits from 1,271 to 14,153 req/s, per its log, and makes it the fastest Mercury waits.

**NOTES.**
- codex logs two build failures: a missing `string` import for `++`, and `bag.count` being named `bag.count_value`. It also logs its own early `git status`. That is honest and specific.
- agy logs four failed builds:
  - a missing `char` import in the interface;
  - `list.filter_map` used in its function form with a pred argument;
  - an `int.-` versus `pair.-` ambiguity;
  - a mode error from rebinding a non-local variable in an if-then-else condition, which forced the renames `C1a`/`C1b`.

  It also logs the stdlib API it guessed wrong (`char.digit_to_int`). It says "zero runtime bugs ... every single error was caught at compile time". That is true of its corpus run, but it overstates what the compiler proved: the compiler proved modes and determinism, not mahjong.
- Mercury cost both models more compile cycles than any other language: 2 and 4, against 0 to 1 elsewhere. Both still finished quickly, and neither log shows a struggle with the determinism system itself.

**Pick: codex.**
- For: its `ordinary/5` and `natural/6` clauses and its `action/6` relation are the best rule expression in the shootout, in half agy's lines.
- Against: agy has the better types.

Before judging, port agy's types into codex:
1. Use the `tile_kind ---> num(num_suit, int) ; wind(wind) ; dragon(dragon)` type and a `flag` type in place of `int` and `string`.
2. Memoize or table the per-suit shanten (agy's per-suit precomputation is the model to copy).
3. Replace `promise_equivalent_solutions` in `can_win` with a semidet existential.

## Part B: the four languages for the full engine

Ranking: **1. Swift, 2. Mercury, 3. Haskell, 4. Python.** Swift versus Mercury is close, and the order depends on how much weight the browser front end and the owner's preference get.

### Expressiveness for rules

- Mercury, as codex wrote it, expresses rules best. Clause-per-yaku nondet relations, nondet decomposition and win-group choice, and a nondet action relation map one-to-one onto the rule text. What makes this work is the language's backtracking and `solutions/2`; agy's entry shows that a model can also ignore those features.
- Haskell comes close with rule tables of `(name, value, Bool)` rows and comprehensions.
- Swift needs either a closure table (agy, verbose) or an imperative evaluator (codex).
- Python's tuple tables are as terse as Haskell's but checked by nothing.

### Safety: what the compilers actually proved

- No compiler caught a mahjong logic bug in any of the eight entries.
  - The kokushi "13 orphans plus a simple tile" bug occurred in Python codex, Swift agy and Haskell agy, and is described in Python agy's design. The corpus caught it every time.
  - The leftover-tile decomposition bug compiles cleanly in both Swift and Haskell.
- What the compilers did catch:
  - Swift: exhaustive switches.
  - GHC: constructor arity errors, partial `head` calls and type defaulting.
  - Mercury: mode errors, determinism errors and ambiguous overloads. Mercury's determinism checking is the strongest guarantee here, because it proves that each predicate has the number of solutions its declaration claims.
  - Python: nothing at build time.
- For a long-lived engine, Swift, Haskell and Mercury can each make illegal states unrepresentable. Only the agy entries actually used newtypes or ADTs for tile kinds and flags. The codex entries in all four languages used `Int` kinds and string flags. That is the model's habit, not the language's limit.

### Performance and the work it took

Corpus measurements, plus my one-suit and fuzz timings:
- **Swift** was fast with no effort: 100–200k req/s on agari, shanten and score from both models, and the best waits and legal rates (40–68k). Neither model did any tuning.
- **Mercury `hlc.gc`** was as fast as Swift on agari and score (93–174k). Search-heavy ops depend on the algorithm: waits ran at 6k for codex and 15k for agy, after agy's 11x rewrite.
- **Haskell** needed care:
  - codex's unmemoized search ran waits at 2k req/s on the corpus and 88 req/s on one-suit hands;
  - agy needed `ST`/`STUArray` to reach 47k shanten, and its waits still copies `UArray`s (3.7k);
  - GHC can be fast, but neither model's natural first version was.
- **Python** was 3–40x slower than Swift on every op. Its `lru_cache` made the search tolerable without effort. A bot calling the engine millions of times would hit this first.

### How the agents coped (from the logs)

- Swift and Python: no build failures for either model.
- Haskell: warnings plus one compile error.
- Mercury: two and four failed builds, all on stdlib names, imports and overloading, which is the price of a small, rarely seen language. Nothing structural.

All eight reached 100%. The Mercury logs show the models handling modes and determinism well enough. They also show one model (agy) falling back to det functional style for most of the work. For the full engine, expect more of the agents' time to go to Mercury's library API and less to its semantics.

### Tooling, build, deployment and the browser

- Swift: `swiftc`/SwiftPM, a single binary, about 6 s release builds.
- Mercury: `mmc --make` worked from clean in both entries.
- Haskell: plain `ghc --make` worked.
- Python: no build step.
- Browser: I am **unsure**, and I tested none of this.
  - Swift has an official WebAssembly SDK.
  - GHC 9.14 has WebAssembly and JavaScript backends of uneven maturity.
  - Mercury can only reach the browser through its C grades and a C-to-WebAssembly toolchain such as Emscripten. The garbage-collected grade needs Boehm GC compiled for WebAssembly, and I know of no maintained path.
  - Python reaches the browser through Pyodide, which is heavy.

  If the front end must run the engine in the browser, this point favours Swift. If the engine runs server-side behind mjai/WebSocket, it largely disappears and Mercury moves up.
- Mercury's ecosystem is the thinnest: no JSON in its stdlib, which the spec itself calls out. Phase 3's mjai protocol means writing a JSON codec.

### Maintainability for a human who dislikes Python and likes Mercury

- Mercury codex is the entry such a person would most enjoy reading and extending. Its clauses are the rulebook, and the determinism declarations document each predicate's contract.
- Swift codex and agy are easy for anyone to maintain.
- Haskell codex is concise but leaves performance traps.
- Python is out on preference, and on lack of static checking: agy found no type checker installed.

### Inherent to the language versus the model's choice

**Inherent:**
- Mercury's relational style and determinism checking.
- Swift's performance without tuning.
- Python's interpreter cost and missing build-time checks.
- GHC's need for strictness and mutable-array work in hot loops.
- Mercury's small stdlib and difficult browser path.

**The model's choice:**
- `Int` kinds and string flags (all four codex entries).
- The unmemoized shanten searches (Haskell codex, Mercury codex).
- Det functional style in place of nondet clauses (Mercury agy).
- The missing leftover-tile check (Swift agy, Haskell agy).
- The duplicated chiitoi yaku list (Python agy).

### Where I am unsure

- The browser story for Mercury and GHC.
- Whether Mercury's performance holds once game state is large and allocation-heavy. Both entries are stateless per request.
- How much of the Swift advantage would remain after a careful Haskell or Mercury shanten (agy's Mercury waits at 15k suggests most of the gap is algorithmic).
