# Shootout Cross-Review — Mercury Addendum (`agy`)

## Scope and What Was Not Read

I read all source files, `DESIGN.md`, `NOTES.md`, and `build.sh` for:
- `shootout/mercury/opus` (`tile.m`, `hand.m`, `score.m`, `legal.m`, `mj.m`)
- `shootout/mercury/codex` (`tiles.m`, `shape.m`, `scoring.m`, `actions.m`, `mj.m`)

Both entries were built from clean/current state with their `build.sh` (`mmc 22.01.9`) and tested directly via `./mj`.

**Not read:**
- `shootout/mercury/agy` (my own entry, excluded by the brief).
- Other reviewers' files in `docs/reviews/p2/` (only `docs/reviews/p2/measurements.md` and my own earlier `docs/reviews/p2/agy.md` were read).

---

## Part A: Mercury (`opus` vs `codex`)

### 1. Rule fidelity (side-by-side)

**Yaku (`pinfu`, `ittsu`, `chanta` / `junchan`):**

`mercury/opus` (`score.m:265-270,321-325,330-333,344-347`):
```mercury
pinfu(C, standard(P, Ms, ryanmen)) :-
    C ^ closed = yes,
    list.all_true((pred(M::in) is semidet :- M ^ shape = run), Ms),
    not is_yakuhai_pair(C, P).

yaku(C, I, "ittsu", closed_open(C, 2, 1)) :-
    Runs = runs(I),
    list.member(kind(S, 1), Runs),
    list.member(kind(S, 4), Runs),
    list.member(kind(S, 7), Runs).

yaku(C, I, "chanta", closed_open(C, 2, 1)) :-
    all_groups_outside(I),
    runs(I) \= [],
    list.member(K, C ^ kinds), is_honor(K).

yaku(C, I, "junchan", closed_open(C, 3, 2)) :-
    all_groups_outside(I),
    runs(I) \= [],
    not (list.member(K, C ^ kinds), is_honor(K)).
```

`mercury/codex` (`scoring.m:219-230,253-256`):
```mercury
pinfu(F, C) :-
    F ^ wait = two_sided, list.length(F ^ runs) = 4,
    F ^ hand_exposure = concealed, pair_fu(F ^ head, C) = 0.

ordinary(F, _, _, "ittsu", Han) :-
    list.find_first_match((pred(K::in) is semidet :-
        rank(K) = 1, list.member(K + 3, F ^ runs), list.member(K + 6, F ^ runs)),
        F ^ runs, _),
    Han = open_reduction(F, 2).

ordinary(F, _, _, Name, Han) :-
    F ^ runs = [_ | _],
    list.all_true((pred(G::in) is semidet :-
        list.find_first_match(outside, group_kinds(G), _)), F ^ groups),
    ( if has_honors(F) then Name = "chanta", Han = open_reduction(F, 2)
      else Name = "junchan", Han = open_reduction(F, 3)
    ).
```

Both entries state each yaku once as a clause of a `nondet` predicate (`yaku/4` vs `ordinary/5`), matching `spec/rules.md` §2. `opus`'s clauses read closer to the rule text: `ittsu` uses logic-variable unification (`kind(S, 1)`, `kind(S, 4)`, `kind(S, 7)`) instead of integer offsets (`K + 3`, `K + 6`), and `yakuhai` / `ryuuiisou` avoid raw magic numbers (`31`, `32`, `33`, `[19, 20, 21, 23, 25, 32]` in `codex/scoring.m:166,204-206`).

**Fu calculation:**

`mercury/opus` (`score.m:414-445`):
```mercury
fu(C, I) = Fu :-
    (
        I = chiitoi,
        Fu = 25
    ;
        I = kokushi(_),
        Fu = 30         % never printed: kokushi is a yakuman
    ;
        I = standard(P, Ms, Wait),
        Tsumo = ( if C ^ req ^ by = tsumo then yes else no ),
        ( if pinfu(C, I), Tsumo = yes then
            Fu = 20
        else
            MenzenRon = ( if C ^ closed = yes, Tsumo = no then 10 else 0 ),
            TsumoFu = ( if Tsumo = yes then 2 else 0 ),
            Raw = 20 + MenzenRon + TsumoFu
                + list.foldl((func(M, A) = A + mentsu_fu(M)), Ms, 0)
                + pair_fu(C, P) + wait_fu(Wait),
            Rounded = (Raw + 9) // 10 * 10,
            ( if C ^ closed = no, Rounded = 20 then
                Fu = 30
            else
                Fu = Rounded
            )
        )
    ).
```

`mercury/codex` (`scoring.m:263-283`):
```mercury
fu(F, By, C) = Fu :-
    ( if F ^ form = chiitoi then Fu = 25
      else if By = tsumo, pinfu(F, C) then Fu = 20
      else
        Base = (if By = tsumo then 22 else if F ^ hand_exposure = concealed then 30 else 20),
        Wait = F ^ wait,
        WaitFu = (if (Wait = single ; Wait = inside ; Wait = edge) then 2 else 0),
        Raw = list.foldl((func(G, Sum) = Sum + group_fu(G)), F ^ groups,
            Base + pair_fu(F ^ head, C) + WaitFu),
        Fu = int.max(30, round_up(Raw, 10))
    ).
```

Both match §3.1 cleanly. `opus` switches exhaustively on `interp` (compiler-checked) and names `mentsu_fu`/`wait_fu` by constructor; `codex` is slightly more compact by folding `20 + 2` / `20 + 10` into `Base` and `int.max(30, ...)` for open no-fu ron.

**Kuikae and riichi-ankan:**

`mercury/opus` (`legal.m:163-170,257-273`):
```mercury
riichi_kan_keeps_waits(R, AllBag, Drawn, K) :-
    K = Drawn,
    N = num_melds(R),
    Before = wait_kinds(kind_bag(R ^ hand), N),
    bag.remove_all(K, AllBag, After),
    Before = wait_kinds(After, N + 1).

kuikae(MK, Took, Used) = [Took | Suji] :-
    ( if
        MK = chi,
        list.sort(Used, [X, Y]),
        offset(X, 1, Y)
    then
        ( if compare((<), Took, X), offset(Y, 1, Z) then
            Suji = [Z]
        else if compare((>), Took, Y), offset(X, -1, Z) then
            Suji = [Z]
        else
            Suji = []
        )
    else
        Suji = []
    ).
```

`mercury/codex` (`actions.m:46-52,104-112`):
```mercury
        ( if Table ^ riichi = in_riichi then
            K = kind_of(Draw),
            Rest = list.filter((pred(U::in) is semidet :- kind_of(U) \= K), Full),
            N = list.length(Melds),
            structural_waits(kinds(Hand), N) = structural_waits(kinds(Rest), N + 1)
          else true
        ),

allowed_discard(Call, Took, Start, T) :-
    K = kind_of(T),
    K \= Took,
    not ( Call = chi, suit(K) = suit(Took),
        ( Took = Start, K = Start + 3
        ; Took = Start + 2, K = Start - 1
        )
    ).
```

Both state kuikae and riichi-ankan once and reuse kuikae across `called`, `chi`, and `pon`. `opus` uses `offset/3` to stay within suit bounds; `codex` guards `Start + 3` / `Start - 1` with `suit(K) = suit(Took)` (safe because `K >= 0`, even though `(-1) // 9 = 0` in Mercury).

---

### 2. Structure

- **`mercury/opus`** separates every domain boundary with algebraic types:
  - `suit` (`man ; pin ; sou ; honor`), `kind(suit, int)`, `colour` (`red ; plain`), and `tile(kind, colour)` — with constructor order chosen so Mercury's built-in `compare` *is* canonical mpsz order (red five before plain five).
  - Concealed decomposition (`group` = `run(kind) ; triplet(kind)`) is distinct from scored interpretation (`mentsu(shape, kind, concealment)` inside `interp` = `standard(pair, mentsu, wait) ; chiitoi ; kokushi(pair)`).
  - Flags (`flag`), win method (`win_by`), score value (`ordinary(han, fu) ; yakuman(multiple)`), and outcome (`not_agari ; no_yaku ; scored(result)`) are all typed ADTs.
- **`mercury/codex`** keeps physical `tile(kind, bool_red)` distinct from `kind`, and uses typed `call`, `meld`, `role`, `exposure`, `method`, `source`, `turn`, and bespoke bools (`bool_riichi`, `bool_furiten`, `bool_first`). However:
  - `kind == int` (`0..33`), so suits, ranks, winds, and dragons are convention/arithmetic (`K // 9`, `K = 27`, `K >= 31`).
  - `flags` is `set(string)` (raw strings).
  - `group(kind, role, exposure)` is reused for both concealed decomposition (`standard_groups` tags everything `concealed`) and scored interpretation.
  - `reading` uses `-1` as a sentinel `kind` for `chiitoi`/`kokushi` pairs (`scoring.m:22,93-94`), and `score_result`'s `scored(string, int, int, int, string, int)` uses `Mult = 0` vs `Mult > 0` to distinguish ordinary hands from yakuman.

---

### 3. Idiom: Nondeterminism, Modes, Determinism, and `bag` vs `set`

Both entries are genuinely idiomatic Mercury — neither is a transliteration of imperative code — and they make interesting contrasting choices:

**Nondeterminism, modes, and determinism declarations:**
- **Decomposition & interpretation:** Both use `nondet` predicates collected by `solutions/2` (`opus`: `sets/2`, `standard_form/3`, `interpretation/2`; `codex`: `form_for/3`, `standard_groups/3`, `take_set/4`, `interpret/5`). Both use `list.delete/3` in its `nondet` mode to pick which concealed group absorbed the winning tile, and `opus` uses `step/4` declared `multi` for per-suit shanten DP.
- **Yaku & legal actions:** Both express yaku and yakuman as `nondet` predicates with one clause per rule, letting `solutions/2` collect and sort the winning yaku list in one step. `codex` goes one step further and makes `action/6` in `actions.m` itself a single `nondet` predicate (using `take_kind/4` in `nondet` mode for `pon:` and `chi:` material) collected by `solutions/2`, which reads more idiomatically than `opus`'s `list.filter_map` + `++` assembly in `legal.m`.
- **Existential checks & `main` determinism:** `codex`'s `can_win/5` (`scoring.m:55`) uses `promise_equivalent_solutions []` to commit to the first winning interpretation without enumerating all of them, and keeps `main` strictly `det` (zero `det_*` partial calls anywhere in the program). `opus` makes `main` `cc_multi` because it wraps dispatch in `exception.try` to guarantee the no-crash contract (and uses two `det_*` calls: `bag.det_remove` in `chuuren` and `list.det_head` in `mentsu_of_meld`).
- **Multi-mode predicates:** Both give `suit_char/2` two modes; because `opus`'s `suit` is an ADT rather than `int`, its reverse mode `suit_char(out, in)` is `det`, whereas `codex`'s `suit_char(out, in)` is `semidet` (forcing a dummy `else ""` branch in `tiles.m:149`).
- **Memoization:** `opus` uses `:- pragma memo(block_best/1)` (`hand.m:182`) on a `list(int)` function to turn its exponential per-suit search into a persistent DP in one line.

**`bag` vs `set`:**
- **`opus`** uses `bag(kind)` as the primary concealed-hand representation (`hand.m`). In `sets/2` and `standard_form/3`, `bag.remove_smallest/3` and `bag.remove/3` express the multiset moves cleanly. However, `bag` **hurts** in two places: (1) `shanten` immediately converts the `bag` back into `list(int)` suit counts (`suit_counts`) and an assoc list (`bag.to_assoc_list`), so the `bag` adds conversion overhead on the hot path (`waits` 3.7k vs `codex` 6.0k); (2) `score.m:509-513` doesn't even use `bag` for dora counting, instead filtering `C ^ kinds` once per indicator. `set` is used appropriately for `wait_kinds` (`set(kind)`), `distinct` (`set(tile)`), and `actions` (`set(string)`).
- **`codex`** uses a sorted `list(kind)` for shape search (`standard_groups`, `best_partition`) and reserves `bag(kind)` strictly for multiset counting: `owned` tile availability in `shape.m:184-185` and `bonuses` dora counting in `scoring.m:288-293` (`bag.count_value(Bag, successor(I))`). `set` is used for `flags` and `structural_waits`. That split is cleaner and faster: `codex` beats `opus` on `agari` (174k vs 143k), `waits` (6.0k vs 3.7k), `score` (115k vs 93k), and `legal` (15.2k vs 4.8k).

---

### 4. Latent bugs

- **`mercury/opus` — Confirmed bug in `honor_best` (`hand.m:209-217`) causing illegal riichi-ankan acceptance:**
  ```mercury
  honor_best(KCs) = Options :-
      Honors = list.filter((pred(K - _::in) is semidet :- is_honor(K)), KCs),
      Sets = list.length(list.filter((pred(_ - C::in) is semidet :- C >= 3),
          Honors)),
      Pairs = list.length(list.filter((pred(_ - C::in) is semidet :- C = 2),
          Honors)),
      Options = [partial(Sets, Pairs, 0) |
          ( if Pairs >= 1 then [partial(Sets, Pairs - 1, 1)] else [] )].
  ```
  On a 13- or 14-tile hand with at most 4 copies of each honor, `C = 3` and `C = 4` happen to give the same optimal shanten as `partial(1, 0, 0)`. However, `wait_kinds` (`hand.m:267-269`, used by `riichi_kan_keeps_waits` in `legal.m:165-170`) checks structural waits by calling `min_shanten(bag.insert(B, K), NumMelds) = -1` for all 34 kinds — including a **5th copy** (`C = 5`) of an honor the hand already holds 4 of. When `C = 5` (e.g., `11111z`, which is 1 triplet + 1 head pair), `C >= 3` counts `Sets = 1`, but `C = 2` misses the leftover pair, so `honor_best` returns `[partial(1, 0, 0)]` instead of `[partial(1, 0, 1)]`. `wait_kinds` therefore **misses every 5th-copy honor wait**.

  Failing request (physically valid 13-tile hand + draw, <= 4 copies of every kind):
  ```
  t1 legal hand=122233344m1111z melds=- draw=2m riichi=1 wall=10 kans=0
  ```
  Before the draw, `122233344m1111z` has structural wait `{1z}` (`123m 234m 234m 111z 11z`). After `ankan:2m`, the remaining `133344m1111z` has structural waits `{}` (the `1m` is isolated), so `ankan:2m` changes the wait set and is illegal.

  Built with `./build.sh` and piped to `./mj`:
  - `mercury/opus`: `t1 actions=ankan:2m,discard:2m` (**wrong** — `opus` computes `wait_kinds = {}` both before and after `ankan:2m`).
  - `mercury/codex`: `t1 actions=discard:2m` (**correct** — `codex`'s `structural_waits` tests `complete` directly rather than `shanten`).

  Minor edge note on `mercury/opus`: `agari_forms` (`hand.m:113-128`) does not check that `bag.count(B) = 14 - 3 * NumMelds`, so malformed short hands like `hand=11m123456789p melds=-` answer `win=1` instead of `win=0`/`error=bad_input` (outside the corpus contract).

- **`mercury/codex`**: No failing request found on valid inputs. Minor non-corpus edge notes:
  - `parse_suits` (`tiles.m:64`) enforces `Suit > Prev`, so a non-canonical `dora=1p1m` returns `error=bad_input` (the corpus is always canonical).
  - `mj.m:93-95,82-84` accepts unknown flags and non-`0`/`1` boolean values silently, and emits `? error=bad_input` on blank lines rather than skipping them.
  - `interpret` (`scoring.m:97`) calls `list.member(Win, group_kinds(Winner))`, which succeeds 2–3 times on pairs/triplets before `solutions` deduplicates.

---

### 5. Cheating or shortcuts

None in either entry. Both compute all answers from first principles, read only stdin, and contain no corpus-derived tables or case-ID special casing.

---

### 6. `NOTES.md`

- **`mercury/opus`** has a thorough, honest working log: it documents using `lib/mercury/ints` `.int` files as API docs, all 8 compile-time errors before the first link (reflexive `[f(N) || ...]` list comprehensions, reserved operator `event`, missing `pair` import turning `_ - C` into integer subtraction, `semidet` lambda calling `list.member` with output, field/function name clash, non-canonical `where comparison is` poisoning determinism, `all_same` overload, singleton warning), 12,434/12,434 pass on the first corpus run, and two timed shanten optimization attempts (including the `//`/`mod` precedence error and the 9x `waits` speedup from `pragma memo(block_best/1)`).
- **`mercury/codex`** also has an honest, concise log: it notes an accidental `git status --short` on the initial command before reading the ban, 2 build failures (missing `string` import for `++`, `bag.count` vs `bag.count_value`), 12,434/12,434 pass on Build 3, and a self-review cleanup pass before Build 4/5.

Together, the two logs tell a consistent story: **AI agents coped much better with Mercury than expected.** Neither agent had a single corpus logic failure; `mmc` caught every mistake at compile time, and the friction was mostly surface syntax and `.int`-file API discovery rather than fighting the mode/determinism system.

---

### 7. Representative pick and cleanup

**Pick: `mercury/opus`.**

`codex` is leaner, faster on 4 of 5 ops, bug-free, and writes `actions.m` (`action/6` + `solutions`) and `can_win/5` (`promise_equivalent_solutions []`) more idiomatically. However, `opus` has the domain architecture needed for a full engine: proper ADTs (`suit`, `kind`, `colour`, `tile`, `flag`, `value`, `outcome`), free canonical ordering via constructor order, clean separation of `group` (decomposition) from `mentsu` (interpretation), no magic tile indices or `-1`/`0` sentinels, and `:- pragma memo` DP for `shanten`. Its one confirmed bug is trivial to fix.

**Cleanup before cross-language judging:**
1. Fix `wait_kinds` (`hand.m:267-269`) to test completion directly (`standard_form` / `is_chiitoi` / `is_kokushi`, as `codex` does) instead of `min_shanten(...) = -1`, and fix `honor_best` (`hand.m:214`) to handle `C >= 5` (e.g. `Sets = C // 3`, `Rem = C mod 3`, `Pairs` from `Rem = 2`).
2. Adopt `codex`'s optimizations in `waits` (check completion when `S = 0`) and `legal` (`live_tenpai` via completion instead of full `waits` for `riichi:`, and `nondet` `action/6` + `solutions`).
3. Add a tile-count check (`bag.count(B) = 14 - 3 * NumMelds`) in `agari_forms` and use `bag.count_value` in `score.m:count_dora`.

---

## Part B (Revised): Cross-Language Ranking for the Full Engine

Target workload: full riichi engine (round state machine, game flow, mjai JSON protocol, bots calling into it millions of times, eventually a web front end), maintained by a human who dislikes Python and likes Mercury.

### Revised Ranking

1. **Swift** *(unchanged)*
2. **Mercury** *(moved up from provisional #3 — swapped with Haskell)*
3. **Haskell** *(moved from #2 to #3)*
4. **Python** *(unchanged)*

### What Changed After Reading Real Mercury Code and Logs

In my earlier review (`docs/reviews/p2/agy.md`), I ranked Haskell #2 and Mercury provisional #3 based on two assumptions I could not verify: that AI agents would suffer heavy compile-cycle friction with Mercury's mode/determinism checker, and that Mercury's ergonomics and `waits` throughput might lag Haskell's. Reading `mercury/opus`, `mercury/codex`, and their logs overturned both assumptions:

1. **Expressiveness for rules (Mercury rises to #1 on the rules core):**
   Seeing `sets/2`, `interpretation/2`, `yaku/4`, `action/6`, constructor-order canonical `compare`, and one-line `:- pragma memo(block_best/1)` confirms that Mercury is the most natural of the four languages for expressing riichi's combinatorics and rule tables. The trade-off is real declaration verbosity (~1/5 of `opus`'s lines are `:- pred`/`:- mode`/`:- type`/`:- import_module`, plus higher-order inst annotations like `pred(kind)::in(pred(in) is semidet)`), which will be felt more in the imperative/protocol layers than in the rules core.

2. **Safety (Mercury confirmed #1):**
   Both Mercury entries passed all 12,434 corpus cases on their first runnable build. `mmc` caught a determinism error inside a `semidet` lambda (`opus`) and let `codex` keep `main` strictly `det` with zero partial calls. Mercury proves strictly more statically than Swift or Haskell.

3. **Performance and effort (Mercury clearly beats Haskell, still trails Swift):**
   From `measurements.md` + the logs:
   - **Swift** remains #1 by a wide margin (`agari` 174k–205k, `shanten` 124k–206k, `waits` 38k–50k, `score` 78k–155k, `legal` 19k–67k) with zero optimization work in `swift/opus`.
   - **Mercury** (`hlc.gc`, `-O4`, ~1.1s clean build) is **faster and more predictable than Haskell** across the board: `agari` 143k–174k vs 60k–119k, `score` 93k–115k vs 53k–90k, `waits` 3.7k–15k vs 2.3k–3.9k, and `shanten` 28k–44k with no laziness cliff (`codex` hit 28k unmemoized vs `haskell/codex`'s 4.0k). `opus`'s one optimization pass (`pragma memo`) was a single pragma rather than refactoring into strict `State` monads.
   - **Haskell** remains #3 on performance-to-effort due to laziness and list allocation.
   - **Python** remains #4 (4–12x slower than Swift).

4. **How well AI agents coped (much better for Mercury than expected):**
   `mercury/codex` linked on Build 3 and passed 12,434/12,434 immediately; `mercury/opus` fixed 8 small compiler errors and passed 12,434/12,434 immediately. That is on par with Swift 6 and Haskell `-Wall`. The main Mercury-specific friction was surface syntax (`event` operator, `//`/`mod` precedence, missing `pair`/`string` imports) and discovering stdlib signatures from `.int` files.

5. **Tooling, build, deployment, and browser (unchanged — Mercury's main liability):**
   Mercury still has the weakest ecosystem for the *non-rules* parts of the full engine: no JSON in stdlib, a tiny package ecosystem, no installed HTML library docs, and no first-class WebAssembly/browser backend. **Swift** keeps #1 because it combines the best bot-simulation throughput with Foundation `JSONDecoder`/`Codable`, SwiftPM, value semantics for a stateful round machine, and SwiftWasm as a browser option.

6. **Maintainability (decisive for Mercury over Haskell at #2):**
   For a human who **dislikes Python and likes Mercury**, Mercury overtakes Haskell for #2: it matches or beats Haskell on rule expressiveness, static safety, clean build speed (~1.1s), and strict performance, without Haskell's laziness surprises. Writing or vendoring a focused mjai JSON codec in Mercury (mjai has a small, fixed message schema) is a bounded one-time cost, whereas Haskell's performance tuning for millions of bot calls is an ongoing cost.

### Remaining Uncertainty

- **Browser architecture:** If the teaching web front end talks to a server-side engine (HTTP/WebSocket), Mercury's lack of a WASM backend does not matter and the **Swift > Mercury > Haskell > Python** ranking holds firmly. If running the full engine *inside the browser via WASM* is a hard requirement, Haskell (GHC's official WASM backend) moves back ahead of Mercury (which would require a custom `hlc.gc` + Boehm GC Emscripten build), while SwiftWasm still warrants a small prototype.
