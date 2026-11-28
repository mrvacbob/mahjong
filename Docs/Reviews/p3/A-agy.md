# Review: Phase 3 package A (foundation)

Reviewed `Sources/Riichi/`, `Sources/mj/main.swift`, `Tests/RiichiTests/`, `Spec/wall.md`, and the `rules=` addition in `Spec/formats.md` against `Docs/Design/engine.md` §2–§3, `Spec/rules.md`, `Docs/Briefs/p3-A-foundation.md`, and `Docs/Notes/p3-A.md`.

## Summary

- **Blockers:** 0
- **Should-fix:** 5
- **Suggestions:** 3

### Verification checks

- **Rules audit:** Every field of `Rules` in `Sources/Riichi/Rules.swift` matches `Spec/rules.md` §1 and `Docs/Design/engine.md` §3–§5 for both `.mahjongSoul` and `.tenhou`. All package A fields (`doubleYakuman`, `tenhouAnyWinningTile`, `kuitan`, `doubleWindPairFu`, `kokushiRobsClosedKan`, `riichiOnFifthCopyWait`, `fifthCopyTenpaiAtDraw`) are threaded through scoring, yaku, fu, legality, and `isTenpaiAtDraw`; nothing in hand analysis remains hard-coded to Mahjong Soul.
- **Wall & independent Python reimplementation:** `Spec/wall.md`, `Sources/Riichi/Wall.swift`, `Tests/RiichiTests/WallTests.swift`, and `Docs/Design/engine.md` §3 are mutually consistent on the `mix(seed) ^ mix(~hand)` key derivation. An independent Python implementation written directly from `Spec/wall.md` matched all §4 intermediate check values (`mix(0)`, `mix(~0)`, key, SplitMix64 state, first three xoshiro256** outputs, first three shuffle indices) and all three 136-tile test vectors byte-for-byte. Bounded sampling (`threshold = 2^64 mod n`, reject `r < threshold`, return `r mod n`) is unbiased, and all layout accessors (`dealt`, `liveDraw`, `replacement`, `doraIndicator`, `uraIndicator`) are right for every dealer.
- **Safety & constraints:** `Sources/Riichi/` has no `import` statements (no Foundation); no output depends on `Set` or `Dictionary` iteration order; `Shanten.swift`'s immutable global tables are thread-safe under Swift 6 (`swift test`: 30 tests in 8 suites pass); all `Int` arithmetic is 32-bit-safe for WebAssembly (`Counts` and RNG use explicit `UInt64`).

---

## Findings

### 1. [should-fix] `Kind.init(_ suit: _ number:)` silently wraps out-of-range numbers into other suits

- **File:** `Sources/Riichi/Tile.swift:31`
- **What is wrong:** `public init(_ suit: Suit, _ number: Int)` delegates directly to `self.init(suit.rawValue * 9 + number - 1)` without validating `number` against `1...suit.size`. While `Kind.init(_ index:)` traps outside `0..<34`, passing an out-of-range `number` to `Kind(_:_:)` silently produces a tile in another suit: e.g., `Kind(.man, 10)` constructs `1p` (`Kind(9)`), `Kind(.pin, 0)` constructs `9m` (`Kind(8)`), and `Kind(.honor, 0)` constructs `9s` (`Kind(26)`).
- **Proposed fix:** Add `precondition((1...suit.size).contains(number), "kind number out of range")` before calling `self.init(...)`.

### 2. [should-fix] `Meld.kuikaeForbidden(took:)` returns a forbidden kind for kans and force-unwraps on invalid `took`

- **File:** `Sources/Riichi/Tile.swift:250-261`
- **What is wrong:** `Meld.kuikaeForbidden(took:)` is a `public` method, but:
  1. For kans (`.daiminkan`, `.shouminkan`, `.ankan`), it returns `[took]` instead of `[]` (unlike `TableMeld.kuikaeForbidden`, which guards `kind == .chi || kind == .pon`).
  2. For a `.chi`, if `took` is not in `tiles`, `fromHand.firstIndex(of: took)!` at line 254 crashes with an uninformative force-unwrap trap; for a `.pon`, it silently returns `[took]` even when `took != base`.
- **Proposed fix:** Return `[]` when `kind != .chi && kind != .pon`, and guard/precondition that `took` is actually present in `tiles` (e.g., `precondition(tiles.contains { $0.kind == took }, "took tile not in meld")`).

### 3. [should-fix] Line protocol does not validate `by=`, `from=`, or `called=` meld kind

- **File:** `Sources/mj/main.swift:75, 77-79, 129`
- **What is wrong:**
  - Line 129 (`score`): `tsumo: try q.string("by") == "tsumo"` treats any invalid value (e.g., `by=bogus`) as `ron` instead of returning `error=bad_by`.
  - Line 75 (`legal` `discard`): `fromKamicha: try string("from") == "kamicha"` treats any invalid value (e.g., `from=bogus`) as `fromKamicha: false` instead of returning `error=bad_from`.
  - Lines 77–79 (`legal` `called`): accepts a kan meld (e.g., `called=k1111p took=1p`) even though `Spec/formats.md` defines `called` as chi or pon only, and then passes it to `Meld.kuikaeForbidden(took:)` (finding 2).
- **Repro (`./mj`):**
  ```
  8 score hand=123m456p789s1122z melds=- win=1z by=bogus seat=E
  -> 8 yaku=yakuhai_round:1,yakuhai_seat:1 han=2 fu=40 pay=ron:3900 total=3900
  9 legal hand=123m456p789s1122z melds=- discard=1z from=bogus seat=E
  -> 9 actions=pass,pon:11z,ron
  11 legal hand=123m456p789s1z melds=k1111p called=k1111p took=1p
  -> 11 actions=discard:1m,discard:1z,discard:2m,discard:3m,discard:4p,discard:5p,discard:6p,discard:7s,discard:8s,discard:9s
  ```
- **Proposed fix:** Validate `by` against `"tsumo"` / `"ron"`, `from` against `"kamicha"` / `"toimen"` / `"shimocha"`, and `called` against `.chi` / `.pon` using `value(...)` so invalid inputs return `error=bad_by`, `error=bad_from`, and `error=bad_called`.

### 4. [should-fix] `Scored` is not `Equatable`/`Hashable` and exposes stringly-typed `yaku`

- **File:** `Sources/Riichi/Score.swift:41-53`
- **What is wrong:** `Scored.yaku` is `[(name: String, value: Int)]`. Because tuples cannot conform to `Hashable`, `Scored` does not conform to `Equatable` or `Hashable` (unlike `Scored.Value` and `Payment`), which will make `RoundResult` in package B harder to compare in tests. In addition, package B's composite-pao calculation (`Rules.paoCoversWholeHand == false`) must inspect whether `daisangen` or `daisuushii` is present and its multiplier, and `RiichiMjai` must serialize yaku — both will have to match raw strings even though `YakuName` is already a `public enum`.
- **Proposed fix:** Define a `public struct YakuEntry: Hashable, Sendable` (e.g., `public let name: String; public let value: Int`, or a typed enum over `YakuName` + dora/aka/ura) and conform `Scored` to `Hashable`.

### 5. [should-fix] Missing unit tests for red-five `TableMeld` cases, `tenhou` chuuren, `ankan` draw-tenpai, and `mj` `rules=` CLI

- **Files:** `Tests/RiichiTests/CoreTypesTests.swift`, `Tests/RiichiTests/RulesTests.swift`, `Tests/RiichiTests/WallTests.swift`
- **What is wrong:** Several edge cases introduced in package A are untested:
  1. `TableMeld`: `pon` with a red five from hand (`taken: 5p, using: [0p, 5p]`) and subsequent `adding(5p)`; `pon` of plain fives with `adding(0p)`; rejecting `adding(0p)` onto a pon that already contains `0p` (two reds); `daiminkan` and `ankan` with red fives / rejecting two reds; `chi` suji kuikae via `TableMeld.kuikaeForbidden` (only kanchan is tested on `TableMeld`).
  2. `RulesScoringTests`: `tenhou` + `chuuren` (`1123456789999m` + `win=1m`) under `.mahjongSoul` (`junsei_chuuren:2,tenhou:1`) vs `.tenhou` (`chuuren:1,tenhou:1`).
  3. `RulesLegalTests`: `isTenpaiAtDraw` when all four copies of the only wait are in a closed kan (`a5555m` + `46m123p456s99s` -> `true` on `.tenhou`, `false` on `.mahjongSoul`); `LegalRequest` with `.called` situation (chi suji and pon kuikae with red fives).
  4. `WallTests`: `dealt(to:dealer:)` checked for all four dealers (`Seat(0)...Seat(3)`), confirming each dealer receives indices `0..3, 16..19, 32..35, 48` and all four seats partition `0..<52`.
  5. Line protocol `rules=tenhou` and `rules=invalid` (`error=bad_rules`) on `score` and `legal` are not covered by the corpus or a test script.
- **Proposed fix:** Add focused test cases in `CoreTypesTests.swift`, `RulesTests.swift`, and `WallTests.swift` covering the items above.

### 6. [suggestion] `Rules.uma` length precondition can be bypassed after `init`

- **File:** `Sources/Riichi/Rules.swift:22, 102`
- **What is wrong:** `Rules.init` enforces `precondition(uma.count == 4)`, but `uma` is a `public var uma: [Int]` with no `didSet` check, so mutating `rules.uma` after construction can violate the invariant and trap later in `GameState`.
- **Proposed fix:** Add `didSet { precondition(uma.count == 4, "uma has one entry per rank") }` or represent `uma` as a fixed 4-element `Sendable, Hashable` struct.

### 7. [suggestion] `Shanten.swift` `expand` computes `one(i + 1)` past `size - 1`

- **File:** `Sources/Riichi/Shanten.swift:89`
- **What is wrong:** `let (a, b, c) = (one(i), one(i + 1), i + 2 < size ? one(i + 2) : (0, 0))` unconditionally evaluates `one(i + 1)` when `i == size - 1` (`i == 8` for suited tiles). It avoids an out-of-bounds crash only because `pow5` happens to have 10 elements (`0..<10`) for `buildTable`.
- **Proposed fix:** Guard `i + 1 < size ? one(i + 1) : (0, 0)` symmetrically with `i + 2 < size`.

### 8. [suggestion] 16.25 MB static shanten table footprint on WebAssembly

- **File:** `Sources/Riichi/Shanten.swift:133-134`
- **What is wrong:** `suitTable` (`5^9 * 8` ≈ 15.6 MB) plus `honorTable` (`5^7 * 8` ≈ 0.625 MB) allocates ~16.25 MB of linear memory on first shanten call. This is fast and clean natively (and works on wasm32), but is worth noting if browser memory budgets or wasm cold-start latency become a constraint later.
- **Proposed fix:** No change needed now; if wasm memory becomes tight, packing only reachable `sum <= 14` entries or using a smaller state encoding would cut the footprint substantially.
