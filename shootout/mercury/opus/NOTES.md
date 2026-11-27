# NOTES: Mercury entry (opus)

## Result

`python3.14 tools/harness.py shootout/mercury/opus/mj corpus/*.txt`:

| op | pass | fail |
|---|---|---|
| agari | 2190 | 0 |
| legal | 758 | 0 |
| score | 5291 | 0 |
| shanten | 2199 | 0 |
| waits | 1996 | 0 |
| total | 12434 | 0 |

`--time` (Apple Silicon, `mmc --make -O4`, final build):

| op | requests | seconds | req/s | req/s excl. start-up |
|---|---|---|---|---|
| agari | 2190 | 0.015 | 146,618 | 530,395 |
| shanten | 2199 | 0.072 | 30,638 | 36,069 |
| waits | 1996 | 0.551 | 3,625 | 3,697 |
| score | 5291 | 0.056 | 95,234 | 118,235 |
| legal | 758 | 0.147 | 5,145 | 5,552 |

Start-up (empty input): 10.8 ms. Clean build: about 1.1 s.

## Size

Lines excluding blank lines and comment-only lines (`%` / `#`):

| file | lines |
|---|---|
| tile.m | 184 |
| hand.m | 198 |
| score.m | 538 |
| legal.m | 232 |
| mj.m | 186 |
| build.sh | 4 |
| total | 1342 |

That includes the Mercury declarations (`:- pred`/`:- func`/`:- mode`/`:- type`,
`:- import_module`), roughly a fifth of the lines.

## Log

- Read the brief, spec/formats.md, spec/rules.md, corpus/handwritten.txt,
  corpus/legal_handwritten.txt, corpus/disputed.txt. Wrote DESIGN.md.
- Library check: no Mercury library sources installed, only `.int` interface
  files under `lib/mercury/ints`; used those as API documentation (bag, solutions,
  string, io). `bag.remove_smallest/3` exists, which is what the decomposition wants.
- Noted from grepping the corpus: `flags=rinshan,` (trailing comma) occurs once, so
  flag splitting must drop empty items.
- Wrote tile.m, hand.m, score.m, legal.m, mj.m in one go, then build cycles:
  1. Syntax errors at `||`: I had written list comprehensions
     (`[f(N) || N <- 1 .. 9]`). Mercury has none; rewrote as `list.map` over
     `1 .. 9` (that function does exist, in `list`).
  2. Syntax error in legal.m: `event` is an operator in Mercury (user events for
     the debugger), so `:- type event` and a field named `event` do not parse.
     Renamed to `trigger`.
  3. Type errors in hand.m: `_ - C` inside lambdas resolved to integer minus
     because the `pair` module was not imported. The error message talks about
     `list(pair(kind, int))` vs `list(int)`, which took a moment to decode.
     Same missing import in mj.m (`undefined type pair/2`).
  4. Determinism error (caught by the compiler): a lambda declared `semidet`
     called `list.member(meld(pon, Ts), Melds)` with output, which is nondet.
     Moved it to a named semidet predicate; the committed-choice is then implied
     because no outputs escape.
  5. Name clash: a function `meld_mentsu/1` and a field `meld_mentsu` of `ctx`
     (field names generate access functions). Renamed the function.
  6. I tried a user-defined comparison (`where comparison is`) on a wrapper type
     to reverse the yaku-string order in the tie-break. That makes the type
     non-canonical, and every head unification of it becomes `multi` / "requires
     all solutions". Replaced with an explicit `worse/2` predicate.
  7. Overloading ambiguity: my own `all_same/1` vs `list.all_same/1`. Deleted mine.
  8. Compiler warning for a singleton variable `K` (genuine leftover).
  Then it linked. First corpus run: 12434/12434 pass, all ops. No bug was found
  only by the corpus in this first pass; the bugs that existed were all type,
  mode or determinism errors the compiler reported.
- `--time` first numbers: agari 222k req/s, shanten 9.8k, waits 418, score 94k,
  legal 1.7k. Waits is 34 shanten calls per request; shanten is slow for what it
  does (100 us). Next: optimise shanten.
- Shanten optimisation, attempt 1: packed each suit's counts into a base-5 int
  as the memo key and replaced the `solutions`-based cross-suit combine with a
  direct min over readings; honors became a closed form. One build failure:
  `Key // int.pow(5, 9 - N) mod 5` is an operator precedence error in Mercury
  (`//` and `mod` are both 400 but non-associative), needed parentheses.
  Result: shanten 9.8k -> 12.8k req/s, waits 418 -> 514. Barely moved, so the
  memo lookup was not the cost.
- Attempt 2: the real cost was the first visit to each suit shape:
  `block_partial` enumerated every reading path of a suit (exponential for a
  chinitsu-like suit) and only then deduplicated. Rewrote it as a memoised DP:
  `block_best(Counts)` takes one `step` (multi: the seven ways to use the lowest
  kind) and recurses on the remaining counts, keeping a Pareto set at each
  level. `pragma memo` on a `list(int)` argument just works. Shanten 36k req/s,
  waits 3.8k req/s (9x). All 12434 still pass.
- Checked that Pareto pruning across the head flag is sound (a head pair can
  always be read as a taatsu instead, so dropping a head-less reading dominated
  by a headed one loses nothing); recorded here because it is not obvious.
- Built from clean (`rm -rf Mercury mj`): 1.1 s. Malformed lines answer
  `error=bad_input`; exceptions inside an op are caught and answer
  `error=internal`.

## Language verdict

**Easy.**

- *Decomposition as nondeterminism.* The decomposition of a hand is written as
  the rule says it: take the lowest tile, and either it starts a triplet or a
  run. `solutions/2` collects every answer, sorted and deduplicated. No
  explicit backtracking, no accumulator plumbing:

  ```mercury
  sets(B0, [G | Gs]) :-
      bag.remove_smallest(K, B0, B1),
      (   bag.remove(K, B1, B2a), bag.remove(K, B2a, B2), G = triplet(K)
      ;   offset(K, 1, K1), offset(K, 2, K2),
          bag.remove(K1, B1, B2a), bag.remove(K2, B2a, B2), G = run(K)
      ),
      sets(B2, Gs).
  ```

  The same carries through scoring: "where did the winning tile go" is
  `list.delete(Groups, G, Others)` in nondet mode, and the whole set of
  interpretations is one `solutions` call.

- *Yaku as clauses.* Each yaku is a clause of one nondet predicate. The clause
  is the rule text, and the list of yaku a hand scores is `solutions(yaku(C, I))`,
  already sorted by name, which is the output order the spec asks for:

  ```mercury
  yaku(C, _, "tanyao", 1)  :- all_kinds_are(C, is_simple).
  yaku(C, I, "iipeikou", 1) :- C ^ closed = yes, peikou(I) = 1.
  yaku(C, I, "ittsu", closed_open(C, 2, 1)) :-
      Runs = runs(I),
      list.member(kind(S, 1), Runs),
      list.member(kind(S, 4), Runs),
      list.member(kind(S, 7), Runs).
  ```

  The `ittsu` clause shows logic variables at work: `S` is chosen by the first
  `member` and checked by the next two.

- *Canonical order for free.* Constructor order decides the built-in `compare`,
  so `suit ---> man ; pin ; sou ; honor` and `colour ---> red ; plain` make
  `list.sort` produce mpsz canonical order, red five before plain five. No
  comparison function anywhere for tiles, kinds, groups or action strings.

- *Memoisation is one pragma.* `:- pragma memo(block_best/1).` on a function of
  `list(int)` turned an exponential per-suit search into a DP shared across
  requests (waits 9x faster). No hash table to write.

- *The compiler caught the bugs.* Every defect before the first passing run was
  a compile-time type, mode or determinism error. The corpus found nothing that
  the compiler had let through. The determinism checker caught a lambda
  declared semidet that could succeed more than once.

**Hard.**

- *Syntax traps.* No list comprehensions (I wrote some by reflex). `event` is a
  reserved operator, so a type named `event` gives a bare "syntax error at token
  'event'". `A // B mod C` is a precedence error. `_ - C` in a lambda head means
  integer minus unless `pair` is imported, and the resulting type error names
  neither `pair` nor the import.
- *Determinism in lambdas.* A lambda that calls `list.member` with an output is
  nondet even when the output is used only for a test inside it. The fix is to
  move the test into a named semidet predicate.
- *Non-canonical types.* I wanted a wrapper type with reversed comparison for
  the "yaku string that sorts first" tie-break. `where comparison is` makes the
  type non-canonical, and then every unification with it needs committed choice.
  An explicit comparison predicate was simpler.
- *Higher-order insts.* Passing a semidet predicate as an argument needs
  `pred(kind)::in(pred(in) is semidet)` in the declaration, and a function with
  such an argument needs a separate `:- mode` line. Verbose but mechanical.
- *Library docs.* Only `.int` interface files are installed, no sources or HTML,
  so API discovery is grepping signatures. It was enough: `bag`, `solutions`,
  `list.delete/3` (nondet) and `list.all_same` were all there.

**What I would do differently.** Write the shanten search as the memoised DP
from the start; the first version enumerated paths and then deduplicated, which
is the natural way to write it in a logic language and the wrong one for
speed. The `waits` op still costs 35 full shanten evaluations per request; an
incremental version that re-evaluates only the suit that changed would be the
next step.

## Spec or corpus problems

None found that needed coding around. Two small observations:

- `corpus/score.txt` contains one request with `flags=rinshan,` (trailing comma).
  The spec says flags is a comma list; I drop empty items.
- The `legal` spec says chi is "left out if every remaining discard would be
  kuikae" but is silent about pon. A pon can never dead-end with a legal hand
  (it would need a fifth copy), so I apply the same check to both, and it never
  fires for pon.

## Unfinished

Nothing failing or skipped. No case-specific hacks. Malformed input gets
`error=bad_input` (not tested by the corpus).

## Finalization

Brief: docs/briefs/p2-finalize.md. Review sources: docs/reviews/p2/agy-mercury.md
(Part A, the opus entry) and the Mercury section of docs/reviews/p2/codex.md;
docs/reviews/p2/agy.md has no review of this entry (the Mercury tree was absent
from its checkout).

### Bugs fixed

- **Riichi ankan with a fifth-copy honor wait** (`legal_review.txt` r4,
  `122233344m1111z` + draw 2m: answered `ankan:2m,discard:2m`, correct is
  `discard:2m`). Cause: `wait_kinds` asked whether `shanten(hand + K) = -1` for
  every K, including a fifth copy of a held kind, and `honor_best` counted honor
  sets with `C >= 3` and pairs with `C = 2`. For five copies (`11111z`) that gave
  one set and no pair, so the 1z wait was never seen and the wait sets before and
  after the kan both looked empty. Two fixes, both at the cause:
  1. `wait_kinds`, `live_tenpai` and the tenpai branch of `waits` now test
     completion directly with `hand.complete` (the same nondet `agari_form` that
     the `agari` op prints), as the reviewers suggested. A hypothetical fifth copy
     is just one more tile in the bag for `sets/2`.
  2. `honor_best` now reads `C // 3` sets and a leftover pair when `C mod 3 = 2`,
     so the shanten op is right for five copies too.
- r1 (fifth-copy 6m wait, number suit) and r2/r3/r5 (count-of-five cache key)
  already passed: the number-suit path goes through `block_best` over a
  `list(int)` memo key, which has no carry between kinds.
- **Malformed input reached the core** (reviewer notes, outside the corpus):
  `agari` on a short hand answered `win=1`; huge `honba` wrapped the payment
  (`ron:3600`); a `legal` request with both `called` and `draw` silently used one.
  All now answer `error=bad_input` (see the validation item below).

### Reviewer cleanup items

Applied: completion instead of shanten for waits/riichi/riichi-ankan; the
tile-count check (now in `agari_form`, so also in `complete`); `bag.count_value`
for dora; nondet `action/2` + `solutions` in `legal`; pinfu's "pair is not a
value tile" is now `pair_fu(C, P) = 0`, so the value-pair rule (dragon, seat,
round) is stated once, in `pair_fu`; validation at the request boundary.

Not applied:
- *Reuse unchanged suit profiles across draw candidates* (codex). `block_best`
  is memoised, so an unchanged suit is already a table lookup; doing it by hand
  would duplicate what the pragma gives. The completion test from tenpai took
  `waits` from 3.6k to 8.5k req/s; the rest of the cost is the cross-suit
  combination for non-tenpai hands.
- *Typed kinds for winds/dragons* (simplify finding): a redesign that touches
  every module. I only made `dora_of`'s honor cycle readable.

### What the simplify pass changed

Four review angles (reuse, simplification, efficiency, altitude) over the whole
entry. Applied:

- **legal.m** rewritten around `action/2` (nondet). Each action is one clause
  with its guard beside it. `solutions` does the sorting and dedup, so `distinct`,
  `two_of`, `solutions_two`, `chi_actions`, `allowed_discards` and the
  `set` round trip are gone. Chi and pon are both `take/4` (nondet `list.delete`)
  twice plus `leaves_discard`. Pon goes through `kuikae(pon, ...)` like chi and
  the after-call case, and the open kan uses `kan_allowed` like every other
  kan. `wins` no longer adds `riichi` twice when the flag is already present.
  232 -> 175 lines.
- **hand.m**: the `shanten` type (`with_melds ; no_melds`) replaces the
  "chiitoi and kokushi meaningful only without melds" comment, and the duplicate
  min logic in mj.m is gone. `group_kinds` is one clause per constructor (the
  "cannot happen" branch is gone). Form printing sorts by a `piece` type whose
  constructor order is pair < run < triplet, not by rank integers 0/1/2.
  `bag.remove_list` and `to_list_only_duplicates` replace paired removes. A
  `copies_left` helper and `lowers_shanten` state the waits rule once.
- **score.m**: a `payment` type, with the total derived from it rather than
  stored next to a preformatted string. Also `has_honor` (was 5 inline
  conjunctions), `triplet_kinds` (was four ways of filtering triplets),
  `meld_shape` with concealment from `is_open_meld`, `all_true_corresponding`,
  `sum_values`, `fu` testing `win_by` directly instead of a bool copy. In
  `evaluate`, distinct readings are collected before scoring and the outcome
  choice is flat.
- **tile.m**: `max_num(suit)` states the 1..9 / 1..7 range once (`make_tile`
  and `all_kinds`). `all_kinds` is memoised. `all_closed` and `meld_tiles` are
  shared by score, legal and mj. `parse_meld` matches list shapes instead of
  checking a length. `physically_possible` is new.
- **mj.m**: one if-then-else in `handle`. `parse_kv` is `split_at_char`. Repeated
  keys are rejected. The per-op hand size goes through `concealed_and_melds`,
  and so do physically possible tiles (at most 4 of a kind, one red and three
  plain fives per suit). `legal` takes exactly one trigger, and `called` must be
  in `melds` with `took` in it. `int_key` takes a range: honba 0..999, wall
  0..70, kans 0..4.

Left alone:
- `best_std` as a fold, not `solutions` + min. It states the rule once already,
  and it is the shanten inner loop.
- The `waits` tenpai branch (altitude suggested one rule only). Completing the
  hand is what lowering shanten from 0 means, so it is the same rule, and it is
  the 2.3x waits speedup.
- Chiitoi and kokushi as both a completeness test and a shanten formula. Each
  reads as its rule.
- The `group` (decomposition) vs `mentsu` (scoring) split. It is deliberate:
  mentsu adds kans and concealment.
- `flags` as a list, not a set. Lists are tiny, and the one duplicate risk
  (`riichi`) is guarded.
- No whitelist of keys per op: the spec does not call unknown keys invalid.
- Dora is still counted per reading. There are few readings per request.
- The kokushi fu of 30 (never printed) and the `"?"` id fallback in `respond`
  (it avoids a `det_head`).

### Size (non-blank, non-comment lines)

| file | before | after |
|---|---|---|
| tile.m | 184 | 198 |
| hand.m | 198 | 209 |
| score.m | 538 | 535 |
| legal.m | 232 | 175 |
| mj.m | 186 | 195 |
| build.sh | 4 | 4 |
| total | 1342 | 1316 |

tile.m and mj.m grew from the new input validation (about 25 lines). hand.m
grew from `complete`/`agari_form`, the `shanten` type and the waits helpers.

### `--time` (req/s excluding start-up, same machine, same session)

| op | before | after bug fix | final |
|---|---|---|---|
| agari | 229,518 | 258,502 | 184,754 |
| shanten | 35,239 | 35,533 | 31,052 |
| waits | 3,612 | 8,299 | 8,686 |
| score | 101,045 | 105,538 | 105,910 |
| legal | 4,857 | 10,168 | 13,594 |

Start-up is 6.1 ms. A clean build (`rm -rf Mercury mj *.mh`, then `./build.sh`)
takes about 1.2 s. Corpus: 12,439/12,439 pass, legal_review.txt included.

The bug fix sped up waits and legal: the tenpai completion test is cheaper than
34 shanten evaluations. The agari and shanten drop in the final column comes
from the new boundary validation. I measured it by building once with
`physically_possible` turned off: agari went to 770k req/s, shanten to 41k,
score to 150k. That is a few microseconds per request for two small bags. I
kept it because the spec calls such input invalid, and checking it once at the
boundary is what lets the core assume well-formed input.

### What got in the way

- Field names must be unique across all constructors of a type. Writing
  `with_melds(std :: int) ; no_melds(std :: int, ...)` fails with "duplicate
  occurrence of the field name". I wrote a `std/1` function instead.
- The compiler noticed that `on_discard` always succeeds (the `pass` clause) and
  warned that `nondet` could be `multi`. That is useful, and a tighter
  declaration documents it.
- Names to avoid for predicates and constructors: `call` (the builtin
  higher-order call) and `all` (a quantifier keyword). I renamed to `call_on` and
  `dealer_tsumo` before compiling, so the compiler never saw the clash.
- One editing slip of my own (a Python splice duplicated half of tile.m) was
  caught by the compiler as duplicate imports.
