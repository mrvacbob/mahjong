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
