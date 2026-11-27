# NOTES: Python entry (opus)

## Result

`python3.14 tools/harness.py shootout/python/opus/mj corpus/*.txt` (all 8 files):

| op | pass | fail |
|---|---|---|
| agari | 2190 | 0 |
| legal | 758 | 0 |
| score | 5291 | 0 |
| shanten | 2199 | 0 |
| waits | 1996 | 0 |
| total | 12434 | 0 |

`--time` (Apple Silicon laptop, python3.14.10, start-up of an empty run 39 ms):

| op | requests | seconds | req/s | req/s excl. start-up |
|---|---|---|---|---|
| agari | 2190 | 0.062 | 35237 | 94801 |
| shanten | 2199 | 0.076 | 28967 | 59650 |
| waits | 1996 | 0.479 | 4166 | 4536 |
| score | 5291 | 0.250 | 21202 | 25136 |
| legal | 758 | 0.248 | 3060 | 3633 |

## Size

Lines excluding blanks, `#` comments and docstrings (counted with `tokenize`):

| file | lines |
|---|---|
| tiles.py | 118 |
| hand.py | 162 |
| yaku.py | 242 |
| scoring.py | 175 |
| legal.py | 113 |
| main.py | 94 |
| build.sh | 5 |
| mj (wrapper) | 1 |
| total | 910 |

yaku.py also carries 36 docstring lines (the rule text quoted next to each predicate).

## Log

- Read brief, spec/formats.md, spec/rules.md, corpus samples, disputed.txt and
  legal_handwritten.txt. Wrote DESIGN.md before any code.
- Wrote tiles.py, hand.py, yaku.py, scoring.py, legal.py, main.py in one pass
  (~1h of writing, no runs in between). Two small self-review fixes before the first
  run: `_meld_group` had a convoluted test for chi vs pon (replaced with
  `m.type is MeldType.CHI`); magic numbers 27 / range(31, 34) replaced with
  EAST / DRAGONS.
- First build + harness run: build.sh OK (compileall + import). Harness:
  12434 pass, 0 fail on all eight corpus files. No failing cycle to report: nothing
  in the corpus caught a bug, and there was no compiler to catch one (Python
  only byte-compiles; syntax errors would have been the only build failures).
- Extra check not in the corpus (scratch script, not kept): 20000 random hands,
  asserting `is_complete <=> shanten.min == -1` and, after removing a tile,
  `shanten == 0 <=> structural_waits nonempty`. 0 mismatches. This cross-checks the
  shanten search (per-suit dominance table) against the independent decomposition
  generator.
- Cleanup pass: removed `from __future__ import annotations` (redundant in 3.14,
  annotations are deferred by PEP 649), unused imports (`Iterator`, `field`,
  `is_yakuhai_kind` in scoring.py), and a redundant honor-digit test in
  `parse_tiles`. Rebuilt, harness still 12434/0.
- Looked for a type checker to check the annotations: none installed (no mypy,
  pyright, pyre, ruff) and none in the stdlib, so the annotations were never
  checked by a tool. Every bug-catching in this entry was by reading the code.
- `--time` run: waits (34 shanten evaluations per request) and legal (a full score
  per riichi/tsumo/ron candidate, waits per riichi discard) are the slow ops at
  ~4000 req/s; nothing needed optimising. The per-suit `functools.cache` on the
  shanten search is what keeps waits fast.

## Language verdict

Easy:

- **Yaku as decorated predicates.** The rule table maps one-to-one onto code; the
  decorator holds the han, the docstring holds the rule text, the body is usually
  one expression over the interpretation:

  ```python
  @yaku("honitsu", closed=3, open=2)
  def honitsu(w: Win) -> bool:
      """One numbered suit + honors (with no honors it is chinitsu instead)."""
      suits = {suit(k) for k in w.kinds}
      return 3 in suits and len(suits) == 2
  ```

  Set literals and comprehensions make sanshoku/ittsu read like the definition:
  `any({9*s, 9*s+3, 9*s+6} <= starts for s in range(3))`.
- **Interpretation choice** is `max`/`min` over a key tuple; the spec's tie-break
  is one line: `(self.total, self.yakuman > 0, self.han, self.fu)` then the
  smallest yaku string.
- **Search with memoisation**: `@functools.cache` on a per-suit shanten function
  keyed by the suit's count tuple turned an exponential search into a table built
  lazily, with no data-structure code.
- `match` on an `IntEnum` shape for waits, `NamedTuple` tiles that sort and hash
  for free (so `sorted(set(tiles))` gives the distinct physical tiles for `legal`,
  red and plain separate), `dataclasses.replace` to add the riichi flag to a
  frozen context.

Hard / weak:

- **Nothing checks the types.** Annotations are thorough but, with stdlib only, no
  checker ran. A misspelt attribute or a `Kind` passed where a `Tile` is expected
  would surface only when the corpus hit that path. The corpus happened to pass on
  the first run, so I can't point at a bug the language caught or missed; but the
  assurance comes entirely from the 12k cases, not from the build (`build.sh` can
  only catch syntax errors and import-time failures).
- **Frozen dataclass + `cached_property`** only works without `slots=True`
  (cached_property needs an instance `__dict__`), so `Win` is the one dataclass
  without slots. A small inconsistency forced by the library.
- **Counts as mutable `list[int]`**: the search functions mutate and restore the
  vector for speed (`counts[k] += 1 ... counts[k] -= 1`); an exception between the
  two would leave it corrupted. Fine here, but it is the kind of aliasing a
  language with value arrays wouldn't let you write by accident.
- Performance is adequate (thousands to tens of thousands of requests/s) only
  because the hot path is memoised; a naive recursive shanten in CPython would be
  the bottleneck.

What I'd do differently: make `Kind` a `NewType` so a checker (if one were
allowed) could separate kinds from counts and digits; and push the open/closed
status of a ron-completed triplet into `Win` construction more visibly (it is
currently one line in `interpretations()` that sanankou, suuankou and fu all depend
on).

## Spec or corpus problems

None found that changed an answer. Choices the spec leaves open, where I picked
the reading the corpus is consistent with:

- Dead-end calls: the spec states "left out if every remaining discard would be
  kuikae" only for `chi`. rules.md (`kuikae_allowed`) says any call is illegal if
  no legal discard remains, so I apply the same test to `pon` too. With 13-3k
  tiles it can only bite in odd cases (e.g. `5555m` + three melds, a fifth 5m,
  which is not physical); no corpus case distinguishes.
- Riichi-ankan "structural waits": I compare the sets of kinds whose addition
  completes the hand, counting even a fifth copy, before the draw and after the
  kan (the spec says "structural, as in `shanten`").

## Unfinished

Nothing failing or skipped. Malformed input answers `error=<Python exception
name>` (e.g. `error=KeyError` for an unknown op, `error=ValueError` for `9z`),
which the spec does not test.

## Finalization

Brief: docs/briefs/p2-finalize.md. Reviews read: the Python sections of
docs/reviews/p2/codex.md and docs/reviews/p2/agy.md (agy-mercury.md has no Python
entry section).

### Bugs

No failing request was known for this entry, and none turned up. All five cases in
`corpus/legal_review.txt` passed before any change (12439/12439 from a clean build).
I checked the reasoning they target:

- **Fifth copy in the riichi-ankan wait set (r1, r4).** `_riichi_ankan_ok` already
  compared completion sets, not shanten: for each kind it adds one copy with no
  availability limit and asks `is_complete`. A fifth 6m (r1) or a fifth 1z (r4) is
  therefore in the "before" set, and the comparison after the kan comes out right.
  The function is now called `hand.winning_kinds`, and the docstring says it includes
  a fifth copy.
- **Cache keyed on counts (r2/r3/r5).** The shanten memo is keyed on one suit's
  9-tuple, so a count of 5 is just a 5 in that tuple and can't carry into the next
  kind.

Reviewer items applied:

- `waits` and the completion scan no longer change the caller's count list. `_plus`
  returns a new list, which also removes the mutate-and-restore that agy flagged.
- Riichi tenpai now tests completion directly, as agy asked: some kind in
  `winning_kinds` still has a copy outside the hand and melds. A cheap gate goes in
  front of the scan: a 14-tile hand above shanten 0 has no tenpai discard, so the
  14 × 34 completion scan only runs on hands that can riichi. Adding a tile never
  raises shanten under the spec's formula, so the gate never rejects a valid riichi.
  This took `legal` from about 3,000 to about 9,400 requests/s.
- `main.py`'s catch-all is narrower. `KeyError`, `ValueError` and `IndexError` are
  malformed input and still answer `error=<name>`. Anything else is a bug: it answers
  `error=internal` and prints the traceback to stderr, so it no longer looks like a
  protocol error.

Reviewer items declined:

- **`Kind` as `NewType` (agy).** No type checker is allowed, so a `NewType` does
  nothing at runtime. Under a checker, every `k + 1`, `9 * s + d` and `k % 9` would
  come back as `int` and need `Kind(...)` wrapped around it. The result is noisier
  code with no check behind it. With a checker allowed, I would do it.
- **Completeness as `shanten(...).min == -1` (simplify/altitude agent).** That
  states the rule once, but the brief and agy ask for completion to be checked
  directly. `standard_forms` also gives up quickly on incomplete hands, and the
  efficiency agent measured the shanten route as slower (209 vs 187 µs per scan).
  `is_complete` stays, and the NOTES cross-check of `is_complete` against `shanten`
  (20000 hands, 0 mismatches) still covers the two definitions.
- **Codex's `Group` with an `open=False` default** serving both decomposition and
  interpretation. Splitting it into two types is a design change the brief rules out.

### Simplify pass

I ran the skill with four review angles (reuse, simplification, efficiency,
altitude) over the whole entry. Applied:

- **tiles.py**
  - `dora_of` is the one rule "next kind in its cycle" (9 per suit, 4 winds,
    3 dragons) instead of three branches.
  - `format_tiles` uses `itertools.groupby` by suit, and its unused `plain`
    parameter is gone.
  - New helpers `suit_counts`, `kinds_in`, `meld_tiles`, `is_closed` and
    `starts_sequence` replace four, three, three, two and three copies of their
    expressions respectively.
  - `Meld.is_kan` is "not chi or pon", and the meld-size table is gone.
- **hand.py**
  - `standard_forms` builds the list of groups that can start at the lowest tile
    and runs one take/recurse/restore body, instead of three pasted ones.
  - The chiitoi/kokushi "no melds" guards are gone everywhere (hand, main,
    scoring, legal). Both need 14 concealed tiles, which a hand with melds can't
    have. One comment states this, and `is_complete`/`winning_kinds` lost their
    `n_melds` parameter.
  - `Group.__str__` uses `format_kinds`.
- **yaku.py**
  - `yaku`/`yakuman` share one `_register`, and the unread `YakuDef.yakuman` field
    is gone.
  - The nine flag-only yaku and yakuman (riichi, double_riichi, ippatsu, rinshan,
    chankan, haitei, houtei, tenhou, chiihou) are registered from a table with
    their han, and the three dragon yakuhai from a loop. Seat and round wind stay
    as functions.
  - `sanshoku`/`sanshoku_doukou` share `_in_all_three_suits` over raw kinds.
  - `Win.suits` is a cached property used by honitsu, chinitsu and chuuren.
    Chuuren calls `chinitsu` instead of restating it, and `_chuuren_counts`
    returns the suit slice.
  - `GREEN` is `parse_tiles("23468s6z")` instead of magic numbers.
  - The redundant form check in chanta/junchan is gone, since both need a sequence.
- **scoring.py**
  - `best` returns `Result | NoWin` (a `StrEnum`) instead of raising `ScoreError`.
  - The tie-break is one `min` over `Result.preference`, instead of a max over the
    rank followed by a min over the yaku string.
  - `count_dora` returns yaku entries directly, so the `Dora` class is gone.
  - `basic_points` lost its yakuman argument.
  - The walrus filter replaces build-then-filter for yaku lists.
- **legal.py**
  - `kuikae(called: Meld, took)` branches on the meld type instead of taking
    `None` for pon.
  - Pon and chi go through one `call()` that offers the call only if `after_call`
    on the rest of the hand is non-empty. The dead-end-call rule is now stated
    once, and `_has_allowed_discard` is gone.
  - `on_draw` computes the distinct tiles once and passes its counts to the
    ankan check.
- **main.py, mj, build.sh**
  - `op_agari` uses a small name/test table.
  - The `noqa` lambda is now a function.
  - `print(..., flush=True)` replaces the manual stdout handling.
  - `mj` dropped `-X frozen_modules=on`, which is the default.
  - Trailing whitespace is gone from build.sh.

Left alone:

- **`Shanten.min`.** The name shadows the builtin, but it matches the spec's `min=`
  field.
- **`case _:` in `_wait_of`.** Writing `case Shape.SEQ:` would leave an implicit
  `None` return for KAN, which can't reach it.
- **`Context` inside `Win`.** This would drop the copied seat/round/flags, but it
  touches every predicate.
- **The tenhou loop re-decomposing for each candidate tile.** It only runs with the
  `tenhou` flag, and the loop reads as the rule.
- **The closure cycle in `standard_forms`.**
- **The `not s.riichi` before kakan.** It is the spec's wording, even though a
  riichi hand can't have a pon.
- **Adding the riichi flag once in `main`.** It stays in `legal`, which owns that
  semantics.

Checks:

- 12439/12439 from a clean build after each step.
- A differential run against the pre-finalization copy found 0 differences. It used
  about 71k random requests over all ops: legal draw with and without riichi, chi
  and pon on discards, and score.
- A random check of the new riichi-tenpai test against the old
  `waits(...).shanten == 0 and count > 0` found 0 mismatches in 20000 hands
  (3692 tenpai).

### Size

Non-blank, non-comment lines. The second column also leaves out docstrings, as in
"Size" above.

| file | before | after | before (no docstrings) | after (no docstrings) |
|---|---|---|---|---|
| tiles.py | 124 | 131 | 118 | 121 |
| hand.py | 169 | 152 | 162 | 143 |
| yaku.py | 277 | 245 | 242 | 208 |
| scoring.py | 181 | 167 | 175 | 160 |
| legal.py | 116 | 102 | 113 | 96 |
| main.py | 95 | 90 | 94 | 88 |
| build.sh + mj | 6 | 6 | 6 | 6 |
| total | 968 | 893 | 910 | 822 |

### `--time` (same machine, req/s excluding start-up)

| op | before | after |
|---|---|---|
| agari | 137275 | 94725 / 91276 |
| shanten | 51766 | 56298 / 54857 |
| waits | 4712 | 4332 / 4530 |
| score | 26790 | 25643 / 25779 |
| legal | 3780 | 19191 / 19552 |
| start-up | 48.7 ms | 41.4 ms |

Raw req/s for legal went from 3044 to 9386. The agari "excl. start-up" figure is
dominated by the start-up subtraction: raw agari is 33877 before and 33932 after,
and the other differences are noise.

### What got in the way

- **No type checker.** The new `Result | NoWin` return, the `Predicate` alias and
  `Counts | None` from `_chuuren_counts` are documentation only. Nothing proves that
  every caller of `best` handles `NoWin`. The corpus and the differential run do
  that work.
- **Closures in a registration loop bind late.** The dragon-yakuhai loop needs the
  `lambda w, k=_kind:` default-argument trick, and the flag yaku need a `_flag(name)`
  factory. Written naively, every predicate would test the last name.
- **Module-level loop variables** (`_name`, `_closed`, ...) leak into the module
  namespace. Python has no block scope, so the leading underscore is the only marker.
