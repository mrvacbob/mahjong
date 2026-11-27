# Swift Riichi Mahjong Implementation Notes

## Result

All 12,434 corpus test cases pass (`0` failures):

```text
op            pass    fail
agari         2190       0
legal          758       0
score         5291       0
shanten       2199       0
waits         1996       0
total        12434       0
```

Timing (`python3.14 tools/harness.py --time shootout/swift/agy/mj corpus/*.txt`, release build on arm64 macOS):

```text
start-up (empty input): 11.4 ms
op          requests   seconds       req/s    req/s excl. start-up
agari           2190     0.019    116690.0                297328.8
shanten         2199     0.020    112744.9                271410.3
waits           1996     0.061     32523.1                 39944.3
score           5291     0.041    127598.4                175991.5
legal            758     0.027     28556.5                 50060.1
```

## Size

Lines of code excluding blank lines and comments (`Sources/mj/*.swift`):

| File | LOC |
| :--- | ---: |
| `Tiles.swift` | 397 |
| `Agari.swift` | 154 |
| `Shanten.swift` | 283 |
| `Score.swift` | 734 |
| `Legal.swift` | 254 |
| `Main.swift` | 161 |
| **Total (Swift sources)** | **1983** |

(Build files: `Package.swift` 12 LOC, `build.sh` 5 LOC.)

## Log

- **Setup**: Verified Swift 6.4.4 (`arm64-apple-macosx27.3.0`). Read `spec/formats.md`, `spec/rules.md`, `corpus/disputed.txt`, `corpus/handwritten.txt`, `corpus/legal_handwritten.txt`. Wrote `DESIGN.md`.
- **Cycle 1 (first build & corpus run)**:
  - Build: succeeded on the first attempt with 0 errors and 0 warnings (`6.72 sec` release build).
  - Corpus: `12429 / 12434` passed (`legal` 758/758, `score` 5291/5291, `shanten` 2199/2199, `waits` 1996/1996, `agari` 2185/2190).
  - Failures (5 cases in `corpus/agari.txt`: `ag1247`, `ag1257`, `ag1263`, `ag1266`, `ag1313`): all hands with 13 unique yaochu plus 1 simple tile (e.g., `19m179p19s1234567z`).
  - Cause: `Agari.isKokushi` checked `counts.total == 14` and `counts[k] >= 1` for all 13 yaochu kinds, without verifying that the 14th tile was also a yaochu rather than a simple tile. Logic bug caught only by the corpus.
  - Fix: sum counts over `TileKind.yaochuKinds` and require `yaochuTotal == 14 && counts.total == 14`.
- **Cycle 2 (rebuild & timed corpus run)**:
  - Build: clean (`5.08 sec` release build).
  - Corpus: `12434 / 12434` passed (`0` failures).

## Language verdict

### What Swift 6.4 made easy

1. **Zero-allocation fixed-size value types with `InlineArray` (Swift 6.2+/6.4)**:
   `TileCounts` is a 34-byte stack-allocated value type (`InlineArray<34, UInt8>`), and the per-suit shanten DP uses `InlineArray<9, UInt8>` and `InlineArray<5, Int8>`. This gave C-like throughput (270k–297k req/s for `shanten`/`agari`, 176k req/s for `score`) while keeping ordinary value semantics and bounds safety:
   ```swift
   struct TileCounts: Equatable, Hashable, Sendable {
       var data: InlineArray<34, UInt8>
       init() { self.data = InlineArray(repeating: 0) }
       subscript(kind: TileKind) -> UInt8 {
           get { data[kind.index] }
           set { data[kind.index] = newValue }
       }
   }
   ```
2. **Algebraic enums with associated values + exhaustive `switch`**:
   Modeling `HandInterpretation.Shape` (`.standard(pair:sets:wait:)`, `.chiitoi(pairs:)`, `.kokushi(is13Wait:)`), `LegalTrigger` (`.draw`, `.discard`, `.called`), and `ScoreOutcome` (`.notAgari`, `.noYaku`, `.scored`) made illegal states unrepresentable and ensured every op handled all variants exhaustively at compile time.
3. **Declarative yaku rules with key-path and closure syntax**:
   Yaku predicates read closely to the rules text:
   ```swift
   YakuRule(name: "chanta", closedHan: 2, openHan: 1) { _, h in
       guard case .standard(let pair, let sets, _) = h.shape else { return false }
       guard pair.isYaochu && sets.allSatisfy(\.hasYaochu) else { return false }
       guard sets.contains(where: \.isSequence) else { return false }
       return pair.isHonor || sets.contains(where: \.hasHonor)
   }
   ```
4. **Encoding canonical sort orders directly in `Comparable`**:
   `Tile` orders `isRed` (`0`) before plain `5`, `Group` orders by `(base, GroupKind)` with `pair < sequence < triplet`, and `ScoredHand`'s `<` encodes the exact multi-key tie-break order (`total`, real yakuman > kazoe, `han`, `fu`, lexicographic `yaku`).

### What Swift made harder

1. **Strict integer type conversions**:
   Mixing `UInt8` (tile indices, ranks, counts) with `Int` (array indices, arithmetic) requires explicit `Int(...)` / `UInt8(...)` conversions in index math and loops. It prevents silent narrowing bugs, at the cost of some visual noise.
2. **Manual `Equatable` / `Hashable` on `InlineArray` wrappers**:
   `InlineArray` does not synthesize `Equatable`/`Hashable` automatically for enclosing structs, so `TileCounts` needed a 10-line manual `==` and `hash(into:)`.
3. **Build / toolchain startup overhead**:
   Release builds via SwiftPM take ~5–7 seconds from clean (reasonable for a compiled language, though slower than scripting languages for tight edit-run loops), and macOS binary launch overhead is ~11 ms.
4. **Verbosity compared to pattern-matching functional languages**:
   At 1,983 LOC, Swift's explicit struct definitions, `OptionSet` boilerplate, and imperative parsing take more lines than a terse functional implementation, though the resulting code is very readable and self-documenting.

### What I would do differently

- `Score.swift` (734 LOC) could be split into `Yaku.swift` (the declarative yaku/yakuman tables) and `Score.swift` (interpretation expansion, fu, and payment) for cleaner file organization.
- In `Scorer.buildInterpretations`, `sets` allocates small 4-element `[ResolvedSet]` arrays per candidate interpretation; using `InlineArray<4, ResolvedSet>` would eliminate even those small heap allocations and push `score` throughput higher.

## Spec or corpus problems

None observed. The spec and corpus were consistent and unambiguous throughout.

## Unfinished

None.
