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
