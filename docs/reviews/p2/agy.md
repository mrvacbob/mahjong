# Shootout Cross-Review (`agy`)

## Scope and What Was Not Read

I read all source files, `DESIGN.md`, `NOTES.md`, and `build.sh` for six entries:
- `shootout/swift/opus` and `shootout/swift/codex`
- `shootout/python/opus` and `shootout/python/codex`
- `shootout/haskell/opus` and `shootout/haskell/codex`

**Not read:**
- `shootout/mercury/opus` and `shootout/mercury/codex`: `shootout/mercury/` does not exist in this repository checkout (only `haskell/`, `python/`, and `swift/` are present under `shootout/`). I did not read any Mercury source, `DESIGN.md`, or `NOTES.md`. My Part B discussion of Mercury relies on `docs/reviews/p2/measurements.md` and inherent properties of the language/toolchain, and marks where I am unsure.
- `shootout/*/agy` (my own entries, excluded by the brief).
- Other reviewers' files in `docs/reviews/p2/` (excluded by the brief; only `measurements.md` was read).

---

## Part A: Per-Language Comparison

### 1. Swift (`opus` vs `codex`)

#### 1.1 Rule fidelity (side-by-side)

**Yaku (`chanta`, `junchan`, `sanankou`):**

`swift/opus` (`Sources/mj/Yaku.swift:61,67-69,76-78`):
```swift
Yaku(.sanankou, closed: 2, open: 2) { $0.concealedTriplets == 3 },
Yaku(.chanta, closed: 2, open: 1) { r in
    r.hasHonor && r.allGroupsContain(\.hasYaochu, pair: \.isYaochu)
},
Yaku(.junchan, closed: 3, open: 2) { r in
    !r.hasHonor && r.allGroupsContain(\.hasTerminal, pair: \.isTerminal)
},
```

`swift/codex` (`Score.swift:240,252-255`):
```swift
if standard.concealedTriplets == 3 { yaku["sanankou"] = 2 }
...
if !sequences.isEmpty, standard.groups.allSatisfy({ $0.kinds.contains(where: isOutside) }) {
    if hasHonors { yaku["chanta"] = closed ? 2 : 1 }
    else { yaku["junchan"] = closed ? 3 : 2 }
}
```

`opus` states each yaku once in a declarative table matching `spec/rules.md` §2, with closed/open han and a `YakuName` enum checked at compile time. `codex` scatters yaku across an imperative `evaluate()` function with raw string dictionary keys and numeric constants (`>= 31`, `27...30`, `[19, 20, 21, 23, 25, 32]`).

**Fu calculation:**

`swift/opus` (`Sources/mj/Score.swift:72-89`):
```swift
func fu(_ r: Reading) -> Int {
    guard case .standard(let sets, let pair, let wait) = r.shape else { return 25 }
    if r.isPinfuShape { return r.context.tsumo ? 20 : 30 }
    var fu = 20
    if r.menzen && !r.context.tsumo { fu += 10 }
    if r.context.tsumo { fu += 2 }
    for s in sets where s.shape != .run {
        var f = s.shape == .kan ? 8 : 2
        if s.concealed { f *= 2 }
        if s.base.isYaochu { f *= 2 }
        fu += f
    }
    if pair.isDragon { fu += 2 }
    if pair == r.context.seat.kind { fu += 2 }
    if pair == r.context.round.kind { fu += 2 }
    if [.kanchan, .penchan, .tanki].contains(wait) { fu += 2 }
    return max(30, (fu + 9) / 10 * 10)  // open no-fu ron counts 30
}
```

`swift/codex` (`Score.swift:52-61`):
```swift
func fu(_ context: ScoreContext, closed: Bool, tsumo: Bool, pinfu: Bool) -> Int {
    if pinfu && tsumo { return 20 }
    var raw = 20 + pairFu(context) + wait.fu
    raw += tsumo ? 2 : (closed ? 10 : 0)
    for group in triplets {
        let base = group.type == .kan ? 8 : 2
        raw += base * (group.open ? 1 : 2) * (isOutside(group.kind) ? 2 : 1)
    }
    return max(30, (raw + 9) / 10 * 10)
}
```

Both are close to §3.1; `opus` keeps the entire fu table (including chiitoi 25 fu and pinfu) in one function, whereas `codex` defaults `var fu = 25` outside `StandardWin.fu` and delegates pair/wait fu to separate methods.

**Kuikae and riichi-ankan:**

`swift/opus` (`Sources/mj/Legal.swift:34-43,95-102`):
```swift
func kuikaeForbidden(took: Kind, fromHand: [Kind]) -> Set<Kind> {
    var out: Set<Kind> = [took]
    let pair = fromHand.sorted()
    if pair.count == 2, pair[0] != pair[1], pair[0].shifted(1) == pair[1] {
        if took < pair[0], let far = pair[1].shifted(1) { out.insert(far) }
        if took > pair[1], let far = pair[0].shifted(-1) { out.insert(far) }
    }
    return out
}
// riichi-ankan:
if q.inRiichi {
    guard k == drawn.kind else { continue }
    var after = counts
    after[k] = 0
    let before = shanten.structuralWaits(Counts(q.hand), meldCount: q.melds.count)
    let now = shanten.structuralWaits(after, meldCount: q.melds.count + 1)
    guard before == now else { continue }
}
```

`swift/codex` (`Legal.swift:18-25,70-75`):
```swift
private func kuikae(took: Int, sequenceStart: Int?) -> Set<Int> {
    var forbidden: Set<Int> = [took]
    if let start = sequenceStart {
        if took == start, start % 9 <= 5 { forbidden.insert(start + 3) }
        if took == start + 2, start % 9 >= 1 { forbidden.insert(start - 1) }
    }
    return forbidden
}
// riichi-ankan:
if context.riichi {
    guard kind == draw.kind else { continue }
    let meld = Meld(type: .closedKan, tiles: tiles.filter { $0.kind == kind })
    let afterKan = Hand(tiles: tiles.filter { $0.kind != kind }, melds: hand.melds + [meld])
    guard structuralWaits(hand) == structuralWaits(afterKan) else { continue }
}
```

Both state kuikae once and reuse it for `called` and `chi`. `opus`'s `shifted(1)` / `shifted(-1)` avoids raw `% 9` boundary arithmetic (`start % 9 <= 5`).

#### 1.2 Structure

- `opus` enforces domain boundaries with types: `Suit`, `Kind`, `Wind`, `Tile`, `Counts`, `MeldKind`/`Meld`, `Group` (concealed decomposition) vs `HandSet`/`Shape`/`Reading` (interpretation with resolved openness), `Flag`, `YakuName`, `Payment`, `Scored.Value`, and `ScoreError` (with Swift 6 typed throws `throws(ScoreError)`).
- `codex` keeps physical `Tile` distinct from `Int` kinds, and uses enums for `Form`, `Turn`, `Wait`, `ScoreResult`, and `MeldType`. However, kinds, suits, and winds are all bare `Int`, flags are `Set<Substring>`, yaku names are `String`, and `Group` (with mutable `var open = false`) is reused for both decomposition and scored interpretation.

#### 1.3 Idiom

- `opus` is idiomatic Swift 6: value types, key-path predicates (`\.isSimple`, `\.isYaochu`), `CaseIterable`, typed throws, `Package.swift` SwiftPM layout.
- `codex` is concise and fast (67k vs 19k req/s on `legal`, 114k vs 78k on `score`), using bit-packed suit keys (`9 * unit`, `65 * unit`, `73 * unit` in `Shape.swift:114-116`) and direct `swiftc` compilation. It reads more like compact algorithmic code than a long-lived Swift codebase.

#### 1.4 Latent bugs

- **`swift/opus` — Confirmed cache-poisoning bug in `Sources/mj/Shanten.swift:50`:**
  ```swift
  let key = a.reduce(runs ? 1 : 2) { $0 * 5 + $1 }
  ```
  The memo key encodes per-tile counts in **base 5** (assuming counts `0..4`). However, `ShantenCalculator.structuralWaits` (`Shanten.swift:117-120`) calls `shanten(counts.adding($0), ...)` for every kind, including a **5th copy** when the hand already holds 4 copies of a kind. When `a[i] == 5`, base-5 carries into `a[i-1]`, colliding with a completely different hand (e.g. `[0, 5, 2, 2, 3, 1, 1, 0, 0]` collides with `[1, 0, 2, 2, 3, 1, 1, 0, 0]`). Because `ShantenCalculator.memo` lives for the entire process, this corrupts answers in both directions:

  1. **Illegal riichi-ankan accepted** (prior `shanten` primes `[1,0,2,2,3,1,1,0,0]`, causing `structuralWaits` to miss the 5th-copy wait `2m` on `2222334455567m`):
     ```
     t0 shanten hand=1334455567m123p melds=-
     t1 legal hand=2222334455567m melds=- draw=5m riichi=1 wall=10 kans=0
     ```
     Built with `./build.sh` and piped to `./mj`:
     - `swift/opus`: `t1 actions=ankan:5m,discard:5m,tsumo` (**wrong** — `2m` is a structural wait before `ankan:5m` via `222m 234m 234m 55m 567m`, and disappears after `ankan:5m`).
     - `swift/codex`: `t1 actions=discard:5m,tsumo` (**correct**).

  2. **13-tile hand reported as complete (`std=-1`)** (reversing the order poisons `memo` for a subsequent `shanten` request):
     ```
     t1 legal hand=2222334455567m melds=- draw=5m riichi=1 wall=10 kans=0
     t2 shanten hand=1334455567m123p melds=-
     ```
     - `swift/opus`: `t2 std=-1 chiitoi=3 kokushi=11 min=-1` (**wrong**; `std` should be `0`).

- **`swift/codex`**: No failing case found. `Shape.swift` packs 3 bits per tile (safe up to count 7), and `structuralWaits` uses `winningForms` directly instead of `shanten`.

#### 1.5 Cheating or shortcuts

None in either entry. Both compute all answers from scratch, read only stdin, and have no corpus-derived tables or ID special cases.

#### 1.6 `NOTES.md`

- `swift/opus`'s log reads as an honest working record: it records two actual compiler failures (nested `$0` closure shadowing in `Yaku.swift`, Swift 6 strict concurrency `Sendable`/main-actor errors), removing `-Ounchecked` before compiling, and a manual malformed-input test that caught duplicate `kakan:` entries. It shows Swift 6's concurrency checking adds friction to a single-threaded CLI, while the type system otherwise got out of the way.
- `swift/codex`'s log is brief and reports zero failed builds and zero corpus failures; plausible given its compact size and avoidance of global closure tables, though it gives less visibility into the development process.

#### 1.7 Representative pick and cleanup

**Pick: `swift/opus`.** Its domain typing (`Kind` vs `Tile`, `Group` vs `HandSet`/`Reading`, `YakuName`, `Flag`, typed throws) and declarative yaku tables are much stronger for maintaining a full engine, and its one serious bug is a one-line fix.

**Cleanup before cross-language judging:**
1. Fix `Shanten.swift:50` to use base 6 or 3-bit packing (`(acc << 3) | count`), and have `structuralWaits` check completion (`standardDecompositions` / `isChiitoi` / `isKokushi`) directly when `shanten == 0`.
2. In `Legal.swift:86-90`, check tenpai for `riichi:` via completion rather than full `waits` (matching `codex`'s 67k vs 19k `legal` throughput).

---

### 2. Python (`opus` vs `codex`)

#### 2.1 Rule fidelity (side-by-side)

**Yaku (`pinfu`, `sanshoku`, `chanta`):**

`python/opus` (`yaku.py:147-151,216-220,254-258`):
```python
@yaku("pinfu", closed=1)
def pinfu(w: Win) -> bool:
    """Closed; 4 sequences, non-yakuhai pair, ryanmen wait."""
    return (len(w.seqs) == 4 and w.pair is not None and not is_yakuhai_kind(w, w.pair)
            and w.wait is Wait.RYANMEN)

@yaku("sanshoku", closed=2, open=1)
def sanshoku(w: Win) -> bool:
    """Same numerical sequence in all 3 suits."""
    starts = {(suit(g.kind), digit(g.kind)) for g in w.seqs}
    return any({(s, d) for s in range(3)} <= starts for d in range(1, 8))

@yaku("chanta", closed=2, open=1)
def chanta(w: Win) -> bool:
    """Every set and the pair contain a terminal or honor; at least 1 sequence and 1 honor."""
    return (_groups_all(w, lambda g: any(is_yaochu(k) for k in g.kinds))
            and bool(w.seqs) and any(is_honor(k) for k in w.kinds))
```

`python/codex` (`scoring.py:185,192,195`):
```python
("pinfu", 1, f.closed and f.pair is not None and f.extra_fu == 0),
("sanshoku", 2 - open_reduction, three_suits(seq)),
("chanta", 2 - open_reduction, bool(seq) and f.outside and has_honors),
```

`opus` mirrors `spec/rules.md` §2 one-to-one with decorated predicates and docstrings. `codex` is concise; its `pinfu` predicate (`f.closed and f.pair is not None and f.extra_fu == 0`) is mathematically equivalent (0 extra fu rules out triplets/kans, yakuhai pair, and non-ryanmen waits) but encodes the rule indirectly through fu rather than stating the rule.

**Fu calculation:**

`python/opus` (`scoring.py:117-135`):
```python
def fu(w: Win, is_pinfu: bool) -> int:
    if w.form is FormType.CHIITOI:
        return 25
    if is_pinfu and w.tsumo:
        return 20
    total = 20
    if w.closed and not w.tsumo:
        total += 10  # menzen ron
    if w.tsumo:
        total += 2
    total += sum(_set_fu(g) for g in w.groups)
    if w.pair is not None:
        total += 2 * (w.pair in DRAGONS) + 2 * (w.pair == w.seat) + 2 * (w.pair == w.round)
    if w.wait in (Wait.KANCHAN, Wait.PENCHAN, Wait.TANKI):
        total += 2
    total = -(-total // 10) * 10
    if total == 20 and not w.closed:
        total = 30  # open pinfu-shape ron
    return total
```

`python/codex` (`scoring.py:215-221`, with `extra_fu` accumulated in `Features.collect` lines 112-127):
```python
def fu_for(reading: Interpretation, f: Features, yaku: dict[str, int], ctx: Context) -> int:
    if reading.special == "chiitoi":
        return 25
    if ctx.tsumo and "pinfu" in yaku:
        return 20
    method_fu = 2 if ctx.tsumo else 10 if f.closed else 0
    return max(30, round_up(20 + f.extra_fu + method_fu, 10))
```

`opus` keeps all fu components in one place; `codex` splits fu between `Features.collect` and `fu_for`.

**Kuikae and riichi-ankan:**

`python/opus` (`legal.py:34-44,89-96`):
```python
def kuikae(took: Kind, used: tuple[Kind, Kind] | None) -> set[Kind]:
    banned = {took}
    if used is not None:
        a, b = sorted(used)
        if b - a == 1:
            if took == a - 1 and digit(b) < 9:
                banned.add(b + 1)
            elif took == b + 1 and digit(a) > 1:
                banned.add(a - 1)
    return banned

def _riichi_ankan_ok(s: Situation, draw: Tile, k: Kind) -> bool:
    if draw.kind != k:
        return False
    before = H.structural_waits(counts_of(s.hand), len(s.melds))
    after_counts = counts_of(s.hand + [draw])
    after_counts[k] = 0
    return before == H.structural_waits(after_counts, len(s.melds) + 1)
```

`python/codex` (`actions.py:10-19,49-56`):
```python
def discardable(tiles: Tiles, meld: Meld, took: int) -> set[int]:
    called_kind = kind(took)
    forbidden = {called_kind}
    if meld.call == "c":
        first = meld.group.first
        if called_kind == first and first % 9 < 6:
            forbidden.add(first + 3)
        if called_kind == first + 2 and first % 9 > 0:
            forbidden.add(first - 1)
    return {tile for tile in tiles if kind(tile) not in forbidden}
# riichi-ankan:
if riichi:
    if tile != kind(drawn):
        continue
    quad = tuple(t for t in full if kind(t) == tile)
    after = Hand(without(full, *quad), (*hand.melds, Meld("a", quad)))
    if set(winning_kinds(hand, structural=True)) != set(winning_kinds(after, structural=True)):
        continue
```

Both state kuikae and riichi-ankan once and cleanly.

#### 2.2 Structure

- `opus` separates `Tile(NamedTuple(kind, red))` from `Kind` (`type Kind = int`), uses `MeldType(Enum)`, `Shape(IntEnum)` (with explicit print-order values), `FormType(Enum)`, `Wait(Enum)`, and `Win` with `cached_property`. `Group` is shared between decomposition and interpretation (`open: bool = False`). `Counts` is a mutable `list[int]`.
- `codex` packs physical tiles and kinds into the same `int` space (`0..33` for kinds, `34..36` for red fives), and uses raw strings for `Group.shape`, `Meld.call`, `Interpretation.wait`, and `Interpretation.special`. Notably, `shapes.py:168` (`sorted(form)`) relies on the alphabetical accident `"pair" < "sequence" < "triplet"` to produce the spec's `agari` group order. `codex` does use immutable `tuple[int, ...]` for `Counts`, which avoids in-place mutation hazards and allows direct `@lru_cache`.

#### 2.3 Idiom

- `opus` is idiomatic Python 3.14 (decorators, enums, frozen dataclasses, `cached_property`, `match`).
- `codex` uses tuples, `@lru_cache`, and `frozenset` subset operators (`DRAGONS <= f.triplets`) idiomatically, but the `34..36` integer encoding and stringly-typed shapes are fragile.

#### 2.4 Latent bugs

No corpus-escaping failing requests were found in either entry on valid inputs. Structural/edge risks:
- `python/codex/shapes.py:168`: `sorted(form)` depends on `"pair" < "sequence" < "triplet"` string ordering.
- `python/opus/hand.py:206-220`: `waits()` and `structural_waits()` mutate the caller's `counts` list in place (`counts[k] += 1 ... counts[k] -= 1`) without `try/finally`.
- `python/opus/main.py:104-105`: catches bare `Exception` and emits `error=<ExceptionClassName>`, which masks internal bugs as protocol errors (though required not to crash).

#### 2.5 Cheating or shortcuts

None in either entry.

#### 2.6 `NOTES.md`

- `python/codex`'s log is honest and informative: it notes an accidental initial git status check before seeing the prohibition, and a real first-run bug (9 failures because `kokushi` accepted 13 orphans + a simple tile). That failure directly illustrates Python's lack of static invariant checks.
- `python/opus`'s log is also honest: passed on first run, includes a 20k random-hand cross-check (`is_complete <=> shanten == -1`), and explicitly points out that no type checker was installed so the type annotations were never mechanically verified.

#### 2.7 Representative pick and cleanup

**Pick: `python/opus`.** Proper `Tile` and enum types instead of `34..36` ints and raw strings, plus the decorator-based yaku table, make it far easier to read and extend.

**Cleanup before cross-language judging:**
1. Use `NewType("Kind", int)` and verify annotations with a type checker when third-party tools are allowed.
2. Avoid mutating the caller's `counts` list in `waits()` / `structural_waits()`.
3. Optimize `_tenpai_for_riichi` in `legal.py` to test completion directly instead of full `waits` (closing the 3.1k vs 5.4k `legal` gap).

---

### 3. Haskell (`opus` vs `codex`)

#### 3.1 Rule fidelity (side-by-side)

**Yaku (`pinfu`, `chanta`, `sanshoku`):**

`haskell/opus` (`src/Score.hs:197-198,213-214,219-220`):
```haskell
  , closedOnly "pinfu" 1 $ stdW $ \w gs ->
      length (runs gs) == 4 && not (any (isValuePair w) (pairKind gs)) && waitOf w == Just Ryanmen
  , yaku "sanshoku" 2 1 $ std $ \gs ->
      any (\n -> all (\s -> any ((== Kind s n) . gbase) (runs gs)) numberSuits) [1 .. 7]
  , yaku "chanta" 2 1 $ std $ \gs ->
      all hasYaochu gs && not (null (runs gs)) && any (isHonor . gbase) gs
```

`haskell/codex` (`Score.hs:68-72,134,137,146-148`):
```haskell
pinfu w = closed w && case patternOf w of
    Normal p sets wait -> wait == TwoSided && all ((== Run) . setType) sets
                          && pairFu (context w) p == 0
    _ -> False
-- in standardYaku:
        , ("sanshoku", openReduced 2, acrossSuits runs)
        , ("chanta", openReduced 2, mixedOutside && any honor ks)
-- where:
        acrossSuits starts = any (\k -> all (`elem` starts) [k,k+9,k+18]) [0..8]
        mixedOutside = outside p && all outside pungs && not (null runs)
                       && all (\k -> terminal k || terminal (k+2)) runs
```

Both are very readable. `opus` expresses `sanshoku` over `numberSuits` and `Kind s n` without index arithmetic (`k+9`, `k+18`), and `std` prevents standard-form predicates from firing on chiitoi/kokushi.

**Fu calculation:**

`haskell/opus` (`src/Score.hs:269-290`):
```haskell
fu :: Win -> [(String, Int)] -> Int
fu w yakus = case reading w of
  SevenPairs -> 25
  Thirteen _ -> 0
  Standard gs wt
    | pinfu && tsumo -> 20
    | otherwise -> let r = roundUp (20 + menzenRon + tsumoFu + sum (map groupFu gs) + waitFu wt)
                   in if r == 20 then 30 else r          -- open hand, no fu, ron
  where
    ...
    groupFu (Group f k open) = case f of
      Pair -> (if isDragon k then 2 else 0) + (if k == seatWind s then 2 else 0) + (if k == roundWind s then 2 else 0)
      Run -> 0
      Triplet -> setFu 1
      Quad -> setFu 4
      where setFu m = m * (if isYaochu k then 4 else 2) * (if open then 1 else 2)
```

`haskell/codex` (`Score.hs:74-92`):
```haskell
fu :: Win -> Int
fu w = case patternOf w of
    Pairs -> 25
    Kokushi -> 0
    Normal p sets wait
        | selfDraw && pinfu w -> 20
        | otherwise -> max 30 (roundUp 10 (20 + methodFu + pairFu (context w) p
                                          + sum (map setFu sets) + waitFu wait))
  where
    ...
    setFu (Set _ Run _) = 0
    setFu (Set k ty hidden) =
        product [2, if outside k then 2 else 1, if hidden then 2 else 1,
                 if ty == Quad then 4 else 1]
```

Both read directly like §3.1.

**Kuikae and riichi-ankan:**

`haskell/opus` (`src/Legal.hs:70-75,118-122`):
```haskell
    riichiKanOk q
      | not (inRiichi t) = True
      | otherwise =
          q == kind d
            && improving k (map kind (hand s))
                 == improving (k + 1) (filter (/= q) (map kind full))

suji :: Kind -> [Kind] -> [Kind]
suji called [a, b]
  | num b == num a + 1, num called < num a, num b + 1 <= 9 = [b { num = num b + 1 }]
  | num b == num a + 1, num called > num b, num a - 1 >= 1 = [a { num = num a - 1 }]
suji _ _ = []
```

`haskell/codex` (`Legal.hs:38-40,75-81`):
```haskell
        ++ [ action "ankan" (plain k) | canKan, k <- unique drawnKinds, copies cs k == 4
            , not active || (k == kind tile && waitsBefore == structuralWaits (meldCount+1)
                                                          (filter (/=k) drawnKinds)) ]

allowedAfter :: Call -> [Kind] -> Kind -> Tile -> Bool
allowedAfter c run took tile = k /= took && k `notElem` otherEnd
  where
    k = kind tile
    otherEnd = case (c, delete took run) of
        (Chi, [a,b]) | b == a+1 -> filter ((==suit took) . suit) [if took < a then b+1 else a-1]
        _ -> []
```

Both are concise and clear.

#### 3.2 Structure

- `opus` gives nearly every concept its own algebraic type: `Suit`, `Kind`, `Tile`, `MeldType`, `Meld`, `Form`, `Group`, `Flag`, `Wait`, `Reading`, `Value`, `Payment`, `ScoreError`, `From`, `Prompt`. Scoring returns `Either ScoreError Score`, separated from `showScore`.
- `codex` separates decomposition (`Shape` / `Group`) from interpretation (`Pattern` / `Set`) at the type level — cleaner on that one boundary than `opus`, which reuses `Group` with `gopen = False` during decomposition. Elsewhere `codex` is less typed: `type Kind = Int`, `flags :: [String]`, `Discard Tile Bool` instead of a seat-direction enum, and `score` returns a formatted `String`.

#### 3.3 Idiom

Both are genuinely idiomatic Haskell (ADTs, list comprehensions, `maximumBy (comparing ...)` with `Down`, pure cores). `opus` uses list pattern matching (`c - 1 : b - 1 : d - 1 : ys`) in `Hand.hs` and `Control.Monad.State.Strict` for per-suit memoization (26k vs 4.0k req/s on `shanten`), plus `Control.Exception.try` in `Main.hs` to guarantee the no-crash contract. `codex` omits memoization in `suitProfiles`, making `shanten` (4.0k req/s) the slowest of all 12 entries, though its `legal` is 2x faster (22k vs 11k) because `structuralWaits` and `liveTenpai` check completion directly with a `nearby` filter instead of full `shanten`.

#### 3.4 Latent bugs

No failing requests on valid inputs were found in either entry. Minor issues:
- `haskell/codex/Score.hs:48`: `Set p (if ty == Sequence then Run else Pung) (how == Tsumo || i /= j)` marks a ron-completed sequence as `concealed = False`. Currently harmless because nothing inspects `concealed` on `Run`, but semantically wrong if future code reads it.
- `haskell/codex/Legal.hs:52`: does not check kuikae dead-end on `pon` (cannot trigger on physically valid <=4-copy hands, only on impossible inputs).
- `haskell/opus/src/Legal.hs:124-126`: defines a partial `head'` helper (safe only because `parseMeld` guarantees non-empty `mtiles`, but unnecessary).

#### 3.5 Cheating or shortcuts

None in either entry.

#### 3.6 `NOTES.md`

- `haskell/opus`'s log is the most informative of all six logs read: it records Build 1's `IO`/`String` type mismatch, `-Wx-partial`, `-Wname-shadowing` (catching a risky shadowed `k` in `Legal.ownTurn`), and a three-stage optimization of `waits` (60 -> 150 -> 2,000 -> 3,500 req/s) with exact causes. It shows clearly how Haskell's compiler catches structural errors early while laziness hides performance costs until measured.
- `haskell/codex`'s log is also honest: it reports GHC `-Wall` partiality warnings (`head`, incomplete pattern, redundant `foldl'` import), the macOS SDK linker warning, and accurately identifies unmemoized `suitProfiles` as its performance bottleneck.

#### 3.7 Representative pick and cleanup

**Pick: `haskell/opus`.** Stronger domain types (`Suit`, `Kind`, `Flag`, `From`, `Value`, `Payment`, `ScoreError`), clean separation of scoring from formatting, and 6.5x faster `shanten`.

**Cleanup before cross-language judging:**
1. Remove `head'` in `Legal.hs` (use `gbase (meldGroup m)` or store `mbase :: Kind` on `Meld`).
2. Deduplicate `splitOn` (currently duplicated in `Meld.hs` and `Main.hs`) and replace yaku name `String`s with a sum type.
3. Use `Int`-packed suit keys for `suitPartials` memoization and check `riichi:` / `ankan:` waits via `decompose` + `nearby` (as `codex` does) to speed up `waits` and `legal`.

---

### 4. Mercury (`opus` vs `codex`)

**Not reviewed:** `shootout/mercury/` is absent from this repository checkout, so neither entry could be read or compared.

---

## Part B: Cross-Language Ranking for the Full Engine

Target workload: full riichi engine (round state machine, game flow, mjai JSON protocol, bots calling into it millions of times, eventually a web front end), maintained by a human who dislikes Python and likes Mercury.

### Ranking

1. **Swift**
2. **Haskell**
3. **Mercury** *(provisional — source and logs were not in the repo)*
4. **Python**

### Comparison Across Dimensions

#### 1. Expressiveness for rules and game state
- **Haskell** and **Swift** both express mahjong rules and state transitions directly: algebraic data types / enums with associated values (`Shape`, `Turn`/`Prompt`, `Payment`, `ScoreError`) and exhaustive pattern matching map cleanly onto both scoring readings and a round state machine (waiting for discard, call window, kan-rob window, draw/rinshan).
- **Haskell** has a slight edge for pure rule tables and combinators (`std`, list comprehensions, `moves` pattern-matching on count lists). **Swift** is close behind with key paths (`\.isSimple`), `String`-backed enums, and typed throws, and handles stateful game-loop updates without monad plumbing.
- **Mercury** is inherently strong for rules (determinism declarations, modes, exhaustive switches, pure nondeterministic search for decomposition). *Unsure* how ergonomic its `bag`/`set` and state-variable syntax proved in practice here since the Mercury entries were not present.
- **Python** can express yaku cleanly (`opus`'s `@yaku` decorators), but lacks algebraic sum types with exhaustiveness checking.

#### 2. Safety (what the compiler proved)
- **Haskell** (`-Wall`) proved the most before runtime: both logs show GHC catching partial functions (`head`), non-exhaustive patterns, type mismatches, and variable shadowing (`opus`'s shadowed `k` in `Legal.ownTurn`). Neither Haskell entry had a corpus failure.
- **Swift** proved exhaustive switches, `Kind` vs `Tile` separation (`opus`), valid yaku spellings (`YakuName`), and exact error cases (`throws(ScoreError)`). Neither Swift entry had a corpus failure. Swift 6 strict concurrency (`Sendable`, main-actor isolation) added ceremony for a single-threaded CLI, though it becomes an asset once bots call the engine concurrently.
- **Mercury** inherently provides the strongest static guarantees on determinism (`det`/`semidet`/`nondet`) and modes, on top of strong types and exhaustiveness. *Unsure* what compiler vs corpus bugs occurred in the shootout without reading the Mercury logs.
- **Python** proved nothing beyond syntax at build time (`opus` notes no type checker was installed; `codex`'s kokushi bug escaped to the corpus). For a full engine with furiten, pao, multi-ron, and abortive-draw state transitions, unchecked types are a real liability.

#### 3. Performance and how much work it took
From `docs/reviews/p2/measurements.md` (req/s across all entries):
- **Swift** is fastest across every op: `agari` 174k–205k, `shanten` 124k–206k, `waits` 38k–50k, `score` 78k–155k, `legal` 19k–67k. Crucially, `swift/opus` reached these numbers on its first build with plain `[Int]` histograms and no optimization passes ("Performance needed no work"). For bots calling the engine millions of times, Swift has the best performance-to-effort ratio.
- **Mercury** (from `measurements.md` only): `agari` 143k–174k and `score` 93k–115k rival Swift, while `shanten` (28k–44k) and `waits` (3.7k–15k) trail Swift by 4–10x. *Unsure* how much optimization work went into those numbers without reading the Mercury entries.
- **Haskell**: `agari` (60k–119k) and `score` (53k–90k) are solid, but `shanten` (4k–47k) and `waits` (2.3k–3.9k) expose Haskell's inherent cost-model difficulty: `haskell/opus` started at 60 waits/s and needed three optimization rounds (including threading `State` for memoization) to reach 3.9k, and `haskell/codex` stayed at 4k shanten. Getting Swift-class throughput in Haskell for bot simulations requires unboxed vectors, strictness annotations, and `ByteString`/`Text` rather than `String`.
- **Python**: 4–12x slower than Swift (`score` 21k–30k, `waits` 4.1k–5.7k, `legal` 3.1k–5.4k) even with `@lru_cache` memoization. Millions of bot calls would force a rewrite or C extension.

#### 4. How well AI agents coped (from the logs)
- **Swift**: Both models passed all 12,434 cases on the first harness run. `opus` had 2 brief compile-error cycles (`$0` closure shadowing, Swift 6 `@Sendable`/actor diagnostics); `codex` had 0.
- **Haskell**: Both models passed all 12,434 cases on the first harness run. GHC `-Wall` caught real issues (`IO`/`String` mismatch, `head` partiality, name shadowing) before running tests. The main difficulty was diagnosing lazy/list performance in `shanten`/`waits`.
- **Python**: Easy to write (`opus` passed first run; `codex` had 1 logic bug caught by the corpus), but agents got zero static feedback from the toolchain.
- **Mercury**: *Unsure* — logs were not present. Based on line counts in `measurements.md` (832–1996 lines, the largest of the four languages on average) and general LLM experience with Mercury's mode/determinism system, I expect more compile-cycle friction than Swift or Haskell, but cannot verify this from the logs.

#### 5. Tooling, build, deployment, and reaching a browser
- **Swift**: Built-in `Codable` / Foundation `JSONDecoder` for mjai JSON; SwiftPM for builds and tests; fast native arm64 binaries (~4s clean release build). **Browser**: SwiftWasm can target WebAssembly, though I am *unsure* how painless its current toolchain and bundle sizes are for a teaching site compared to compiling a thin backend or using a native JS/TS frontend talking to the engine.
- **Haskell**: `cabal` + `aeson` is mature for mjai JSON (boot packages alone were only a shootout constraint). **Browser**: GHC 9.14 ships a WebAssembly backend (`ghc-wasm-meta`), which is viable, though with larger WASM binaries and a less mainstream JS interop story than JS/Rust.
- **Mercury**: Weakest ecosystem for a full engine. No JSON library in stdlib (`spec/formats.md` explicitly notes this), small package ecosystem, and no first-class WebAssembly/browser target (reaching a browser requires either running the engine server-side or compiling Mercury's C grade through Emscripten, which adds build complexity).
- **Python**: Strong stdlib (`json`), trivial scripting, Pyodide for browser (heavy runtime download), but poor fit for high-throughput bot simulations.

#### 6. Maintainability (for a human who dislikes Python and likes Mercury)
- **Swift** and **Haskell** are both strong choices here. **Haskell** is closest in spirit to Mercury (pure functions, ADTs, exhaustive pattern matching, declarative rule tables) and will feel natural to someone who likes Mercury. **Swift** is less purely functional, but its value semantics, exhaustive enums, and straightforward performance model make a large stateful engine (round machine + protocol + bot harness) easier to profile and maintain without monad-stack or laziness surprises.
- **Mercury** wins on personal preference for the core rules, but maintaining a JSON protocol, bot FFI/IPC, and web deployment around it will carry ongoing ecosystem tax.
- **Python** is ruled out by both performance/safety and the maintainer's stated dislike.

### Summary of Uncertainties
1. **Mercury's actual code and agent logs**: Because `shootout/mercury/` was missing from the repo, I could not verify how well `bag`/`set` and nondeterminism worked, how much AI agents struggled with Mercury's mode checker, or why Mercury's `waits` throughput lagged its `score` throughput.
2. **Browser deployment path**: Whether the teaching site runs the engine in-browser (WASM) or server-side (HTTP/WebSocket) significantly affects the Swift vs Haskell vs Mercury comparison. If server-side, Mercury's lack of a WASM target matters less (though lack of stdlib JSON still hurts); if in-browser WASM, SwiftWasm and GHC's WASM backend both warrant a small prototype before committing.
