# Design: Swift entry

A SwiftPM package with one executable target, `mj`. `build.sh` runs
`swift build -c release` and copies the binary to `./mj`. Foundation is not needed;
the program uses the standard library only (`readLine`, `print`).

## Tiles, hands, melds

- `Kind` is a value type wrapping an index 0..<34 (m 0–8, p 9–17, s 18–26,
  z 27–33). Computed properties say what the rules talk about: `suit`, `number`,
  `isHonor`, `isTerminal`, `isYaochu` (terminal or honor), `isSimple`, `isDragon`,
  `isWind`, `next(in:)` for sequences, `doraSuccessor` for indicators.
- `Tile` is `Kind` + `isRed`. Red fives only matter for aka counting and for the
  identity of `legal` actions, so almost every algorithm works on kinds.
- `Counts` is a 34-slot histogram of kinds (`[Int]`), the working representation for
  decomposition and shanten. A hand is kept both as `[Tile]` (for red identity and
  output) and as `Counts`.
- `Meld` is `enum MeldKind { chi, pon, daiminkan, shouminkan, ankan }` + tiles.
  `isOpen` is false only for ankan; `isKan` for the three kan forms.
- Parsing is a small tile-list parser (`"123m406p"` → `[Tile]`) and a formatter that
  emits canonical order (0 sorts just before 5).

## Decomposition

`Group` is `enum { pair(Kind), run(Kind), triplet(Kind) }` (run = the first tile of a
sequence). `decompositions(of: Counts) -> [[Group]]` chooses a pair, then peels the
lowest remaining kind as a triplet or as a run, recursively. That recursion is the
whole of "is this a standard hand". Chiitoi and kokushi are separate predicates on
`Counts`. `agari` formats each list of groups with the spec's ordering
(suit, number, pair < run < triplet), sorts and dedups the strings.

## Shanten

Per-suit search: for one suit's 9 counts (honors: 7 counts, no runs), a DFS returns
every reachable `(sets, partials, hasPair)` triple (capped at 4) as a bitmask. The
four suit results are combined by a fold over the same state space, starting from
`sets = meld count`; `std = 8 − 2s − t − p` with `t` capped at `4 − s`. Chiitoi and
kokushi are closed-form. `waits` adds each kind with a live copy and asks whether
`min` shanten drops.

## Yaku declarations

A winning hand is turned into one or more `Reading`s: for a standard hand, one per
(decomposition × which concealed group the winning tile completed); plus a chiitoi
and a kokushi reading if those shapes apply. A reading carries the four sets (with
`open`/`concealed` already resolved: a triplet completed by ron on a shanpon is
open), the pair, the wait shape (ryanmen, kanchan, penchan, shanpon, tanki),
menzen, tsumo/ron and the context (winds, flags).

Yaku are a table of declarations, one line per row of the rules table:

```swift
Yaku(.sanshoku, closed: 2, open: 1) { $0.hasSanshokuRuns }
Yaku(.tanyao, closed: 1, open: 1) { $0.allKinds.allSatisfy(\.isSimple) }
Yaku(.chanta, closed: 2, open: 1) { r in
    r.hasHonor && r.allGroupsContain(\.hasYaochu, pair: \.isYaochu)
},
```

`open: nil` means closed-only. Yakuman are a second table with the multiple they
contribute (`kokushi_13: 2`). Exclusions the rules state in words ("does not stack
with", "replaces") are written as explicit filters after evaluation
(ryanpeikou removes iipeikou, double_riichi replaces riichi, chinitsu vs honitsu is
expressed in the predicates). Yaku names are a `String`-backed enum whose raw values
are the spec's spellings, so the compiler catches misspellings in the table.

## Fu and interpretation choice

`fu(of: Reading)` follows table 3.1 directly: 20 base, menzen ron +10, tsumo +2
unless pinfu, per-set fu from (triplet|kan) × (open|closed) × (simple|yaochu), pair fu
per value (double wind = 4), wait fu; then the fixed exceptions (pinfu tsumo 20,
chiitoi 25, open 20 → 30). Each reading is scored to a `ScoreResult` (yaku list, han,
fu or yakuman multiple, payments, total). Readings are compared by
`(total, realYakuman, han, fu, -yakuString)` and the best wins. Tenhou loops over each
distinct tile of the 14 as the winning tile and takes the best of those.

## `legal`

`legal` is a client of the other ops, not a second rules engine:

- `tsumo`/`ron`: build the score request (with riichi and situational flags) and
  ask whether `score` returns a result rather than an error.
- `riichi:<t>`: remove `t`, require `shanten == 0` and `waits.count > 0`.
- riichi `ankan`: compare `structuralWaits(before)` with `structuralWaits(after)`,
  where structural waits are the kinds whose addition makes shanten −1.
- chi/pon/kan: enumerate the tile choices from hand (red variants separately),
  then drop a call if kuikae leaves no discard. Kuikae is one function shared with
  the `called` case.

## After implementation

The design held. Files: `Tile.swift` (kinds, tiles, melds, parsing),
`Decompose.swift` (agari), `Shanten.swift`, `Reading.swift` (readings of a winning
hand), `Yaku.swift` (the two declaration tables), `Score.swift` (fu, payments,
choice), `Legal.swift`, `main.swift` (protocol). Two small changes: the shanten memo
lives in a `final class ShantenCalculator` passed explicitly (Swift 6 strict
concurrency rejects a global mutable cache), and the yaku closures are `@Sendable`
for the same reason. The only explicit exclusion filter left is ryanpeikou removing
iipeikou; the other exclusions fell out of the predicates (chanta needs an honor,
junchan none; honitsu needs an honor, chinitsu none; honroutou has no runs so chanta's
"at least one run" excludes it).
