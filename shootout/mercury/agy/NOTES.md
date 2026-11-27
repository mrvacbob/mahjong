# Notes: Mercury Implementation

## Result

All **12,434 / 12,434** corpus cases pass (0 failures) on `python3.14 tools/harness.py shootout/mercury/agy/mj corpus/*.txt --time`:

| Op | Pass | Fail | Requests | Seconds | req/s | req/s excl. start-up |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| `agari` | 2190 | 0 | 2190 | 0.015 | 149,182.6 | 587,998.4 |
| `shanten` | 2199 | 0 | 2199 | 0.051 | 43,077.5 | 54,848.8 |
| `waits` | 1996 | 0 | 1996 | 0.141 | 14,152.6 | 15,344.6 |
| `score` | 5291 | 0 | 5291 | 0.061 | 86,647.5 | 105,591.9 |
| `legal` | 758 | 0 | 758 | 0.070 | 10,838.0 | 12,851.0 |
| **total** | **12434** | **0** | **12434** | **0.338** | | |

Start-up (empty input): `11.0 ms`.

## Size

Lines of code excluding blank lines and `%` comment lines:

| File | LOC |
| :--- | ---: |
| `agari.m` | 131 |
| `legal.m` | 295 |
| `mj.m` | 194 |
| `score.m` | 722 |
| `shanten.m` | 371 |
| `tiles.m` | 283 |
| **total** | **1,996** |

## Log

- **Setup**: Verified `mmc 22.01.9` on `aarch64-apple-darwin27.0.0`, default grade `hlc.gc` available, stdlib `.int` files in `/opt/homebrew/lib/mercury/ints/`.
- **Design**: Wrote `DESIGN.md` before coding. Separated `tile_kind` (`num(num_suit, int) ; wind(wind) ; dragon(dragon)`) from `tile(kind, is_red)` so Mercury's built-in term ordering matches canonical `mpsz` order with `0` before `5`. Used `bag(tile_kind)` for multisets, `set(tile_kind)` for wait sets and kuikae, and `nondet` predicates + `solutions.solutions` for hand decomposition and wait assignment.
- **Build 1 (failed)**: `tiles.m:082-083`: `undefined type char/0` — forgot `:- import_module char.` in `tiles.m`'s interface (it was only imported in `:- implementation.`). Moved `import_module char` to interface.
- **Build 2 (failed)**: `legal.m` had three issues caught by the typechecker:
  1. `list.filter_map/2` as a function expects a `func`, not a `pred` (switched to the 3-arg predicate `list.filter_map/3`).
  2. Multi-goal conjunctions inside `X = (if ... then A, B else ...)` expressions (switched to goal-level `if-then-else`).
  3. `(D - 2) - (D - 1)` was ambiguous between `int.-/2` and `pair.-/2` (switched to tuple `{D - 2, D - 1}`).
  Also cleaned up redundant `import_module char` warning in `tiles.m` and singleton variable warning `_P, _Gs` in `agari.m`.
- **Build 3 (failed)**: `agari.m`, `legal.m`, `mj.m`, and `score.m` all compiled cleanly with zero warnings! `shanten.m:201` failed with a mode/scope error (`attempt to bind a non-local variable inside the condition of an if-then-else` for `C1` and `Rest`) because two sequential `if` conditions in `search_suit_taatsu` reused the same variable names `C1` and `Rest` (in Mercury, variables are clause-scoped unless existentially quantified). Renamed to `C1a/RestA` and `C1b/C2b/RestB`.
- **Build 4 (failed)**: `shanten.m` compiled cleanly! `tiles.m:135`: `undefined predicate char.digit_to_int/2` (API I expected that did not exist under that name; Mercury's `char` module uses `decimal_digit_to_int/2`). Replaced with an explicit `char_to_rank/2` switch `'1'..'9'`.
- **Build 5 & Test 1 (passed 100%!)**: Compiled cleanly with zero warnings (`mmc --make --grade hlc.gc -O4 mj`). Ran `tools/harness.py` on all 8 corpus files: **12,434 / 12,434 passed, 0 failures on the very first run!** Zero runtime bugs caught by the corpus — every single error was caught at compile time by `mmc`.
- **Optimization (`waits`)**: Initial `--time` run showed `waits` at 1.570s (1,271 req/s) because `compute_waits` recomputed all 4 suits' `suit_best` tables for each of the 34 candidate tiles. Refactored `shanten.m` to precompute the 4 suits once, recompute only the single suit modified by candidate `K` (and use `agari.is_agari` directly when `BaseSh = 0`). `waits` dropped from **1.570s to 0.141s** (11.1x speedup, 14,153 req/s) and `legal` dropped from **0.120s to 0.070s** (10,838 req/s), still 12,434 / 12,434 pass.

## Language verdict

### What Mercury made remarkably easy

1. **Nondeterministic hand decomposition & wait assignment**: `decompose_std`, `choose_win_split` (for `tenhou`), `enumerate_interp`, and `assign_wait` are written directly as `nondet` / `multi` relational predicates and collected with `solutions.solutions`. There is no manual backtracking stack or accumulator plumbing:

```mercury
decompose_groups(Bag, MaybeNoSeqKind, Acc, Groups) :-
    ( if bag.is_empty(Bag) then
        Groups = Acc
    else
        bag.remove_smallest(MinK, Bag, Bag1),
        (
            bag.remove(MinK, Bag1, Bag2),
            bag.remove(MinK, Bag2, Bag3),
            decompose_groups(Bag3, yes(MinK), [triplet(MinK) | Acc], Groups)
        ;
            MaybeNoSeqKind \= yes(MinK),
            MinK = num(S, N),
            N =< 7,
            bag.remove(num(S, N + 1), Bag1, Bag2),
            bag.remove(num(S, N + 2), Bag2, Bag3),
            decompose_groups(Bag3, MaybeNoSeqKind, [seq(S, N) | Acc], Groups)
        )
    ).
```

2. **Built-in `bag` and `set` + canonical term ordering**: Declaring `num_suit ---> m ; p ; s`, `wind ---> east ; south ; west ; north`, `dragon ---> haku ; hatsu ; chun`, `tile_kind ---> num(num_suit, int) ; wind(wind) ; dragon(dragon)`, and `is_red ---> red ; plain` meant Mercury's standard `compare/3` gave canonical `mpsz` order (with `0` before `5`) for free. `bag.remove_smallest/3` made canonical-order decomposition trivial, and riichi `ankan` wait preservation is literally `WaitsBefore = WaitsAfter` on `set(tile_kind)`.

3. **Exhaustive determinism & mode checking**: Once `mmc` accepted all 6 modules (zero warnings), **all 12,434 corpus tests passed on the very first run** with zero runtime bugs. Exhaustive switches on `meld_type`, `wind`, `dragon`, `wait_type`, `hand_interp`, and `turn_state` guaranteed no missing cases, and `hlc.gc -O4` produced C-like throughput (149k req/s `agari`, 87k req/s `score`, 43k req/s `shanten`).

### What Mercury made awkward or verbose

1. **Clause-scoped variables**: Reusing a local pattern variable name (`C1`, `Rest`) in two sequential `if` conditions inside the same clause causes a mode/scope error (`attempt to bind a non-local variable inside the condition of an if-then-else`), forcing ugly numbered names (`C1a/RestA`, `C1b/RestB`) or existential quantifiers.
2. **Predicate vs function duality and overloading**: Many stdlib operations exist in both predicate and function forms (`list.filter_map`, `set.list_to_set`, `bag.delete_all`), and `-` is overloaded between `int.-/2` and `pair.-/2`, which caused type-ambiguity errors in `legal.m`.
3. **Verbose conditional list assembly**: Without list comprehensions or monadic `do`/guard syntax, assembling optional yaku lists in `score.m` requires chains of `(if Cond then [yaku_entry(...)] else []) ++ ...`, which inflated `score.m` to 722 LOC.

### What I would do differently

- Use a `nondet` predicate `yaku_for_interp(Interp, Ctx, Entry)` + `solutions.solutions` for standard yaku and yakuman collection instead of chaining `++` over `(if ... then [...] else [])` expressions — it would cut `score.m` by ~100–150 lines and read even more declaratively.
- Use `array` or a 9-int struct instead of `list(int)` for per-suit counts in `shanten.m` to push `shanten` and `waits` throughput even higher.

## Spec or corpus problems

None encountered; all 12,434 corpus cases matched the spec cleanly.

## Unfinished

None.
