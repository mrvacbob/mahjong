# Haskell Implementation Notes

## Result

Full corpus run via `python3.14 tools/harness.py shootout/haskell/agy/mj corpus/*.txt --time`:

| Op | Pass | Fail | Requests | Seconds | Req/s |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `agari` | 2190 | 0 | 2190 | 0.019 | 116,590.4 |
| `shanten` | 2199 | 0 | 2199 | 0.041 | 53,079.9 |
| `waits` | 1996 | 0 | 1996 | 0.538 | 3,710.2 |
| `score` | 5291 | 0 | 5291 | 0.049 | 107,340.3 |
| `legal` | 758 | 0 | 758 | 0.076 | 9,981.1 |
| **Total** | **12434** | **0** | **12434** | **0.723** | — |

(Start-up measured by harness on empty input: 73.4 ms.)

## Size

Non-blank, non-comment lines of code per file:

| File | LOC |
| :--- | ---: |
| `src/Tile.hs` | 234 |
| `src/Agari.hs` | 101 |
| `src/Shanten.hs` | 222 |
| `src/Score.hs` | 488 |
| `src/Legal.hs` | 177 |
| `src/Main.hs` | 141 |
| **Total** | **1363** |

(Plus `build.sh`: 6 lines.)

## Log

- Initialized design in `DESIGN.md` before writing code. Using GHC 9.14.1 with boot packages only (`base`, `array`, `containers`, `bytestring`) and plain `ghc --make -O2 -Wall`.
- While writing `Shanten.hs`, caught a potential runtime bug before the first compile: `minimum [...]` in `stdShantenFromProfile` would fail on empty list if a hand had no pair at all (`spWithHead` all `-1`). Guarded with `minimum (99 : [...])`.
- **Build 1 (compile failed)**:
  - `Score.hs:433`: `StandardShape` takes 3 arguments (`StandardShape p ms _`), gave 2 in a pattern guard. Compiler caught it immediately.
  - `Agari.hs:32`: `-Wtype-defaults` warning — local helper `go` defaulted `pairs`/`total` to `Integer` instead of `Int`. Added explicit `go :: Int -> Int -> Int -> Bool` signature.
  - Removed unused `Data.Set` import in `Main.hs`.
- **Build 2 (built with 5 `-Wall` warnings; 12429/12434 passed, 5 failed)**:
  - `score` (5291/5291), `shanten` (2199/2199), `waits` (1996/1996), and `legal` (758/758) all passed 100% on the first run.
  - `agari` failed 5 cases (`ag1247`, `ag1257`, `ag1263`, `ag1266`, `ag1313`), all of the form 13 distinct yaochu tiles + 1 simple tile (e.g., `19m179p19s1234567z`). Cause: `isKokushi` checked `countsTotal c == 14 && all (>= 1) yaochuCounts`, which allowed the 14th tile to be a non-yaochu simple instead of a yaochu pair. This was a pure logic bug only the corpus caught; fixed by also checking `sum ys == 14`.
  - Fixed all 5 `-Wall` warnings: unused `scFullCounts` record field in `ScoreCtx`, and 4 GHC 9.14 `-Wx-partial` warnings on `head` (replaced with total pattern matches).
- **Build 3 (clean build, 0 warnings; 12434/12434 passed, 0 failed)**.

## Language verdict

### What Haskell made easy

1. **ADTs + derived `Ord` directly encoding domain ordering and shapes.**
   `CGroup` and `Tile` express canonical ordering with almost no boilerplate:
   ```haskell
   data GroupKind = Pair | Seq | Triplet | Kan
     deriving (Eq, Ord, Show)

   data CGroup = CGroup !TileKind !GroupKind
     deriving (Eq, Ord, Show)
   ```
   Deriving `Ord` on `CGroup` automatically implements the `agari` spec's group sort order (suit, then first digit, then pair < sequence < triplet). Likewise, `Ord Tile` (`compare k1 k2 <> compare (not r1) (not r2)`) handles red-five placement (`0m` before `5m`, `40m`, `07m`) uniformly across formatting, `chi:`, `pon:`, and `discard:`.

2. **Declarative yaku and yakuman rules with pattern guards and list comprehensions.**
   Every yaku rule is a 2–8 line pure function `ScoreCtx -> HandShape -> [(String, Int)]` that reads almost verbatim like `spec/rules.md`:
   ```haskell
   ymSuuankou _ (StandardShape _ ms wt)
     | length (filter isClosedTriOrKan ms) == 4 =
         if wt == Tanki then [("suuankou_tanki", 2)] else [("suuankou", 1)]
   ymSuuankou _ _ = []
   ```
   And tie-breaking is a single tuple key:
   ```haskell
   resultKey (ScoreYakuman ys _ _ tot)     = (tot, True,  0,   0,  Down (formatYakuList ys))
   resultKey (ScoreOrdinary ys han fu _ tot) = (tot, False, han, fu, Down (formatYakuList ys))
   ```

3. **Pure backtracking and `ST` local mutation where needed.**
   List comprehensions made `decompose`, `expandDecomp`, and `tenhou`'s best-winning-tile search trivial and bug-free (all 5291 `score` and 758 `legal` cases passed on the very first run). Meanwhile, `Control.Monad.ST` with `STUArray` gave zero-allocation in-place DFS for per-suit `shanten` while keeping a pure API.

4. **GHC 9.14's `-Wall` (including `-Wx-partial`)** caught constructor arity mistakes, unused fields, type defaulting to `Integer`, and every partial `head` call.

### What Haskell made harder

1. **No mutable fixed-size stack arrays without `ST` ceremony.**
   Writing the per-suit shanten DFS with `STUArray` in `ST` required explicit `readArray`/`writeArray` save/restore pairs, which is noisier than a small stack array in Swift or C. Even `Vec5` was written as a 5-tuple `(Int, Int, Int, Int, Int)` with manual unrolling in `combineVec5` to avoid heap-allocating tiny arrays in the inner loop.
2. **Updating immutable `UArray`s in `waits` copies all 34 entries.**
   `countsAdd` uses `(//)`, which copies the 34-element `UArray` on each of the 34 candidate draws in `waits` (plus `runST` allocates a fresh 9-element `STUArray` per candidate). That made `waits` ~10x slower per request than `shanten` (still 0.54 s for 1996 cases, so not worth complicating).
3. **Standard-library string splitting and `ByteString` interop.**
   `base` has no `splitOn` for comma-separated lists, so `splitComma` had to be written twice (in `Tile.hs` and `Score.hs`), and `Main.hs` converts `ByteString` lines to `String` via `BS.unpack`/`BS.pack` for simplicity.

### What I would do differently

- Extract a small `splitComma` helper into `Tile.hs` (or a `Parse.hs`) instead of duplicating it.
- In `Shanten.hs`, pass the modified `(rank, delta)` directly into `numberedSuitProfile` so `waits` does not copy the 34-element `Counts` array 34 times.
- Represent `Meld` with a `NonEmpty Tile` (or explicit `Meld` constructors carrying their tile kind) so `meldToMentsu` and `kuikaeForbidden` never even have an unreachable empty-list branch.

## Spec or corpus problems

None encountered. Every corpus case matched the spec cleanly.

## Unfinished

None. All 12,434 corpus cases pass with 0 failures and 0 compiler warnings.
