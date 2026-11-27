# Notes: Python 3.14 Entry (`shootout/python/agy`)

## Result

All 12,434 corpus cases pass (100%, 0 failures) via `python3.14 tools/harness.py shootout/python/agy/mj corpus/*.txt --time`:

| Op | Pass | Fail | Seconds | req/s | req/s excl. start-up |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `agari` | 2,190 | 0 | 0.046 | 47,607.3 | 374,703.3 |
| `shanten` | 2,199 | 0 | 0.067 | 32,661.7 | 80,935.6 |
| `waits` | 1,996 | 0 | 0.367 | 5,437.8 | 6,105.8 |
| `score` | 5,291 | 0 | 0.181 | 29,300.6 | 37,679.9 |
| `legal` | 758 | 0 | 0.174 | 4,357.9 | 5,666.0 |
| **total** | **12,434** | **0** | — | — | — |

Start-up (empty input): **40.2 ms**.

## Size

Lines of code excluding blank lines, comments, and module docstrings (measured via `tokenize` on Python files and non-blank/non-comment lines on `build.sh`):

| File | LOC (code) | Raw lines |
| :--- | ---: | ---: |
| `mj` | 5 | 11 |
| `mjlib/__init__.py` | 0 | 1 |
| `mjlib/tiles.py` | 168 | 220 |
| `mjlib/decompose.py` | 103 | 126 |
| `mjlib/shanten.py` | 189 | 237 |
| `mjlib/yaku.py` | 534 | 638 |
| `mjlib/legal.py` | 201 | 243 |
| `mjlib/cli.py` | 162 | 187 |
| `build.sh` | 7 | 10 |
| **total** | **1,369** | **1,673** |

## Log

- **Design phase**: Read `spec/formats.md`, `spec/rules.md`, `corpus/disputed.txt`, `corpus/handwritten.txt`, `corpus/legal_handwritten.txt`, and `tools/harness.py`. Wrote `DESIGN.md` before writing code. Chose 0..33 integer tile kinds + frozen slotted `Tile(kind, is_red)` + per-suit memoized `(sets, max_taatsu)` DP for shanten.
- **Implementation**: Wrote `mjlib/{__init__,tiles,decompose,shanten,yaku,legal,cli}.py`, `mj`, and `build.sh` in two batched passes.
- **Cycle 1 (build + full corpus)**:
  - `shootout/python/agy/build.sh` succeeded on the first attempt.
  - `python3.14 tools/harness.py shootout/python/agy/mj corpus/*.txt` passed **12,434 / 12,434** on the first run with 0 failures and 0 errors.
  - No static type-checker (`mypy` / `pyright`) is installed in this environment, so type annotations were verified by inspection and Python 3.14 compilation (`compileall`).
- **Cycle 2 (timing + LOC)**:
  - Ran `tools/harness.py ... --time`. Total runtime across all 5 ops was ~0.84s; `agari` exceeded 370k req/s excl. startup and `shanten` exceeded 80k req/s excl. startup thanks to `@lru_cache` on per-suit profiles.

## Language verdict

### What Python 3.14 made easy

1. **Declarative yaku tables read like the rulebook**: Tuples of `(name, predicate)` over a precomputed `HandView` dataclass map almost 1-to-1 to `spec/rules.md` without boilerplate classes or switch statements:
   ```python
   STANDARD_YAKU_RULES: tuple[YakuRule, ...] = (
       ("pinfu", lambda v: 1 if _is_pinfu(v) else 0),
       ("tanyao", lambda v: 1 if all(is_simple(k) for k in v.all_kinds) else 0),
       ("ryanpeikou", lambda v: 3 if v.is_closed and v.seq_pair_count == 2 else 0),
       ("iipeikou", lambda v: 1 if v.is_closed and v.seq_pair_count == 1 else 0),
       ("sanshoku", lambda v: (2 if v.is_closed else 1) if _has_sanshoku(v) else 0),
       ...
   )
   ```
2. **Memoized suit-factored shanten in 25 lines**: `@functools.lru_cache(maxsize=None)` on leading-zero-stripped `tuple[int, ...]` suit slices turned structural shanten into a tiny DP that runs at >80k req/s in pure Python without writing any manual hash table or cache-table generator:
   ```python
   @lru_cache(maxsize=None)
   def _suit_mt(s: tuple[int, ...]) -> Profile:
       ...
   ```
3. **Tuple-based ordering & deduplication**: Using `GroupKind(IntEnum)` (`PAIR = 0, SEQ = 1, TRIPLET = 2`) with `Group = tuple[TileKind, GroupKind]` meant Python's built-in `sorted()` and `set` directly implemented `agari`'s canonical group ordering and deduplication, and tuple comparison `(total, is_yakuman, han, fu)` handled score tie-breaking cleanly.
4. **Compact, readable parsing and formatting**: String slicing, comprehensions, and `f`-strings made mpsz parsing, meld parsing, and `legal` action formatting (`chi:07m`, `pon:05m`, `kakan:0m`) trivial.

### What Python 3.14 made hard

1. **No compile-time safety without an external checker**: Neither `mypy` nor `pyright` is in the stdlib (or installed here). Python's runtime ignores type annotations, so typos in attribute names, mismatched `Tile` vs `TileKind` arguments, or missing `Enum` cases are only caught when that code path executes.
2. **Value vs. index discipline**: Representing `TileKind` as a `int` type alias (`TileKind = int`) is fast, but Python's runtime cannot distinguish a `TileKind` (`0..33`) from a rank (`0..8`) or a suit (`0..3`) or a count. Using `NewType` helps static checkers but still has zero runtime enforcement.
3. **Per-call interpreter overhead in tight inner loops**: `waits` (which calls `min_shanten` 34 times per request) and `legal` (which tests `compute_waits` per distinct discard for riichi) still run at 4k–6k req/s — fast enough for the corpus in <0.4s, but an order of magnitude slower than compiled languages for `waits` where 34 small Python function calls add up.

### What I would do differently

- For even faster `waits` and `legal`, we could inline the 4-group combine step inside `structural_waits` so that when testing candidate draw `k` in suit `s`, the other 3 suits' combined `(no_head, with_head)` profiles are precomputed once instead of recomputed 34 times. That would likely push `waits` from ~6k req/s to >25k req/s with ~20 extra lines of code, though the current 0.37s for 1,996 cases is already very comfortable.

## Spec or corpus problems

None observed. Every rule in `spec/formats.md` and `spec/rules.md` agreed with all 12,434 corpus cases.

## Unfinished

None.
