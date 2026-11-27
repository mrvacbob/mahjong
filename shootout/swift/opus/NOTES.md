# NOTES: Swift / opus

Swift 6.4.4 (swiftlang-6.4.4.3.6), SwiftPM, tools version 6.0 (Swift 6 language
mode, so strict concurrency checking is on). Standard library only: no Foundation import.

## Result

`python3.14 tools/harness.py shootout/swift/opus/mj corpus/*.txt`

| op | pass | fail |
|---|---|---|
| agari | 2190 | 0 |
| legal | 758 | 0 |
| score | 5291 | 0 |
| shanten | 2199 | 0 |
| waits | 1996 | 0 |
| total | 12434 | 0 |

`--time` (release build, `-O`, Apple Silicon):

```
start-up (empty input): 10.7 ms
op          requests   seconds       req/s    req/s excl. start-up
agari           2190     0.013    173831.4               1170940.8
shanten         2199     0.013    170252.3               1005027.4
waits           1996     0.053     37327.3                 46695.7
score           5291     0.069     77094.7                 91378.9
legal            758     0.039     19546.2                 27021.4
```

Clean build (`rm -rf .build mj && ./build.sh`): about 4 s.

## Size

Non-blank, non-comment lines (`grep -vE '^\s*(//|#|$)'`):

| file | lines |
|---|---|
| Sources/mj/Tile.swift | 163 |
| Sources/mj/Score.swift | 159 |
| Sources/mj/Legal.swift | 149 |
| Sources/mj/Reading.swift | 137 |
| Sources/mj/Yaku.swift | 121 |
| Sources/mj/main.swift | 112 |
| Sources/mj/Shanten.swift | 112 |
| Sources/mj/Decompose.swift | 67 |
| Package.swift | 10 |
| build.sh | 4 |
| **Swift total** | **1030** (1020 excluding Package.swift) |

## Log

- Read the brief, spec/formats.md, spec/rules.md, corpus/handwritten.txt,
  corpus/disputed.txt, corpus/legal_handwritten.txt, and the heads of the generated
  corpus files. Wrote DESIGN.md before any code.
- Wrote all eight source files in one pass before the first compile (Tile, Decompose,
  Shanten, Reading, Yaku, Score, Legal, main).
- Changed my mind before compiling: had put `-Ounchecked` in Package.swift via
  `unsafeFlags`; removed it so the timing is for the default checked `-O` build.
- Build 1 failed: `anonymous closure arguments cannot be used inside a closure that
  has explicit arguments` in Yaku.swift. I had written
  `Yakuman(.kokushi, 1) { isKokushiShape($0) && Kind.yaochu.allSatisfy { k in $0.waiting[k] == 1 } }`:
  the inner closure names its parameter `k`, and then `$0` is not allowed to refer to the
  outer closure's argument. Fixed by naming the outer parameter `r` and pulling the
  13-wait test into `isThirteenWait(_:)`. Caught by the compiler; a plain mistake
  of mine.
- Build 2 failed with Swift 6 strict-concurrency errors, two kinds:
  - `let 'yakuList' is not concurrency-safe because non-'Sendable' type '[Yaku]' may
    have shared mutable state`. A global `let` table of structs holding closures counts
    as non-Sendable. Fixed by making `Yaku`/`Yakuman` `Sendable` and the closure type
    `@Sendable (Reading) -> Bool`.
  - `main actor-isolated let 'shantenCalc' can not be referenced from a nonisolated
    context`. Top-level code in main.swift is main-actor isolated, so a global defined
    there cannot be used from an ordinary function. Fixed by passing the calculator
    as a parameter to `answer(_:shantenCalc:)`. The program has no concurrency at all;
    this was purely ceremony, but cheap. I had already planned the shanten memo as a
    class instance instead of a global `var` because I expected this.
- Build 3 succeeded. First harness run: 12434/12434 pass. No corpus-caught bugs.
- Fed malformed input by hand (missing keys, bad melds, `8z`, unknown op, empty line,
  20-tile hand, impossible triple pons) to confirm it answers `error=...` instead of
  crashing. One cosmetic issue found: duplicate `kakan:` entries for an impossible
  input with three identical pons. Made `legal` dedupe its action list. Re-ran: still
  12434/12434.
- One thing I worried about but did not need to change: I flagged `double_riichi` as
  implying `riichi` in the flag parser, then removed that before the first build,
  because it would have printed both `riichi:1` and `double_riichi:2`. The only place
  that cares is ura counting, which checks both flags.

Bugs caught by the compiler: 1 (closure `$0` shadowing). Plus 2 concurrency
diagnostics that were not bugs (single-threaded program). Bugs caught only by the
corpus: 0. APIs I expected that did not exist: none came up; I avoided Foundation, so
no `components(separatedBy:)`; `split(separator:)` on `Substring` was enough.

## Language verdict

Easy:

- Enums with associated values and exhaustive `switch` fit the domain. A reading's
  shape is
  ```swift
  enum Shape {
      case standard(sets: [HandSet], pair: Kind, wait: Wait)
      case chiitoi
      case kokushi
  }
  ```
  and fu is one `guard case .standard(...) = r.shape else { return 25 }` away from
  the rules table.
- Yaku as data. A `String`-backed enum gives the exact spec spellings and catches
  misspellings at compile time; the table reads like the rules table, with closed/open
  han in the declaration:
  ```swift
  Yaku(.sanshoku, closed: 2, open: 1) { $0.hasSanshokuRuns },
  Yaku(.junchan, closed: 3, open: 2) { r in
      !r.hasHonor && r.allGroupsContain(\.hasTerminal, pair: \.isTerminal)
  },
  ```
  Key paths as functions (`\.isSimple`, `\.isYaochu`) keep predicates short.
- Typed throws (`func score(_:) throws(ScoreError) -> Scored`) express the two allowed
  error answers precisely; `catch` gets a `ScoreError`, not `any Error`.
- Tuple comparison made the tie-break a one-liner:
  `(total, isRealYakuman, han, fu)` compared with `>`, then the yaku string.
- Performance needed no work: plain `[Int]` histograms and a memoised per-suit
  shanten search give 30-1000k requests/s; start-up is about 11 ms.

Hard or annoying:

- Swift 6 strict concurrency in a single-threaded CLI: global tables of closures need
  `Sendable`/`@Sendable`, and top-level `let`s in main.swift are main-actor isolated.
  The fixes are small but the diagnostics are about threads that don't exist.
- `$0` cannot appear in a closure nested inside one with named parameters, which
  bites in exactly the nested-`allSatisfy` predicates that yaku code is full of.
- `String`/`Substring`/`Character` friction for the mpsz format: digits come out as
  `Character`, need `wholeNumberValue`, and output needs `Character(String(n))`.
  Not hard, just noisy.
- Swift's `Array` is a heap-allocated CoW type, so `Counts` copies on every mutation
  in the recursive searches. Fast enough here; `InlineArray<34, Int8>` would avoid
  it, but I did not need it.

What I would do differently: make `Counts` a fixed-size value type
(`InlineArray`) if throughput mattered; and give `Reading` precomputed fields
instead of computed properties (each yaku predicate refilters `sets`), which would
matter only if score got hot.

## Spec or corpus problems

None that forced a workaround; the corpus passed as the spec reads. Two places where I
had to pick an interpretation the corpus may not test:

- Kuikae dead end for pon. formats.md says "Left out if every remaining discard would
  be kuikae" only in the `chi:` row. rules.md (`kuikae_allowed`) says the call is
  illegal whenever no legal discard remains, which also covers pon. I apply it to pon
  as well. It can only matter for a hand whose other tiles are all the called kind.
- Riichi ankan "set of wait kinds (structural, as in `shanten`)". I take this as kinds
  whose addition gives shanten -1, ignoring availability (so a fifth-copy wait counts
  as a wait on both sides of the comparison), using `min` over standard, chiitoi and
  kokushi.

## Unfinished

Nothing failing, skipped or hacked. Malformed input gets `error=<reason>` lines
(`bad_hand`, `missing_win`, `unknown_op`, ...); their wording is my own.

## Finalization

Brief: docs/briefs/p2-finalize.md. Reviews read: the Swift sections of
docs/reviews/p2/codex.md and docs/reviews/p2/agy.md (agy-mercury.md has no Swift
opus findings).

### Bugs fixed

Before the fix, the full corpus run (one process, all files) was 12373/12439: the two
`legal_review.txt` requests failed and, because the poisoned memo lives for the whole
process, 62 later `waits` and 2 `shanten` answers went wrong too. Per-op processes
(`--time`) showed only 1 failure.

- **Memo key aliasing.** `ShantenCalculator.states` keyed its memo by the suit's counts
  in base 5. `structuralWaits` asked for shanten of the hand plus every kind,
  including a fifth copy of a kind already held four times; a count of 5 carried into
  the previous kind and collided with a different hand. So riichi-ankan waits were
  wrong (`3456666999m789p` + 9m lost `ankan:9m`; the fifth-6m wait was missed), and a
  later `shanten` of the colliding hand could read a stale entry (`std=-1` for a
  13-tile hand). Fixed at both ends: the key packs 3 bits per count, and nothing asks
  shanten about five-copy hands any more.
- **Structural waits now come from completion.** `completingKinds(counts, meldCount:)`
  lists the kinds whose addition gives a complete hand (`isComplete`: a standard
  decomposition, or chiitoi/kokushi with no melds). The riichi-ankan check compares
  that set before the draw and after the kan. `structuralWaits` is gone.
- **Riichi tenpai** (reviewer cleanup): `riichi:<t>` asks whether some kind with a copy
  outside hand and melds completes the hand after discarding `t`, instead of running
  the full `waits` op. One check per kind rather than per tile, so a red and a plain
  five share it. `legal` went from about 21k to about 33k req/s.
- **Input boundaries** (out-of-corpus probes from codex.md): `honba=9223372036854775807`
  trapped on overflow; now `honba` must be 0...999 (`error=bad_honba`), and every
  integer key has a range (`riichi`/`furiten`/`first` 0...1, `kans` 0...4, `wall`
  0...136). A `legal` request with two triggers (`called=` and `draw=`) used whichever
  was checked first; now `error=bad_situation`. A malformed `called` fell through to
  `no_situation`; now `bad_called`, and a `took` not in the meld is `bad_took` (it
  used to remove index 0 by `?? 0`). Hands with five of a kind or two red fives of a
  suit (hand, melds and win/draw/discard together) are `error=impossible_tiles`; the
  memo then never sees a count above 4 from input.

### Simplify pass

Ran the `simplify` skill (four review angles: reuse, simplification, efficiency,
altitude) over the whole entry. Applied:

- `Decomposition { pair, sets }` with `Group` reduced to run/triplet. The pair is a
  field, not `groups[0]`, so the `guard case .pair` and `fatalError` in `readings` are
  gone. `Decomposition.text` does the agari ordering.
- Run membership is stated once (`Kind.run`); `Group.kinds`, `HandSet.kinds` and chi
  validation use it. `MeldKind.shape` is an exhaustive switch (meld to set shape),
  replacing a nested ternary and `Meld.isKan`/`isChi` (`isKan` tested `tiles.count`).
  `HandSet` has `init(_ meld:)` and `init(_ group:, concealed:)`.
- The wait-shape rule moved out of the placement loop into
  `wait(completing:with:)`.
- `Reading` stores `melds` and derives `menzen` and `waiting`; the three `if case`
  accessors go through one private `standard` tuple; `isStandard`, `noMelds` and
  `hasTriplet` are gone. `[Meld].isClosed` and `[Meld].tiles` replace repeated
  `allSatisfy { !$0.isOpen }` / `flatMap(\.tiles)`.
- `Shape: Equatable`, so yaku say `$0.shape == .chiitoi` / `.kokushi` (deleted
  `isKokushiShape` and an `if case ... return true else false`).
- Nine gates: the pattern is one constant; `nineGatesSuit` finds the suit once;
  `c.total == 13` (always true) is gone.
- The ryanpeikou-removes-iipeikou filter was dead (`identicalRunPairs == 1` vs `== 2`
  already exclude each other); deleted, and the comment on `ordinaryYaku` says where
  each exclusion lives. DESIGN.md said double_riichi had a filter too; it never did.
- Score: `ScoreError` is `String`-backed (raw values are the spec's error words);
  `Scored.init` sorts the yaku list once; best-of is `max(by:)` in one helper used by
  both the tenhou loop and the readings loop; labelled `(name:, value:)` tuples instead
  of `.0`/`.1`; `doraCount` uses `Counts`; fu loops `where s.isTriplet`; the tenhou
  loop uses `removingOne`.
- `LegalEngine` (a stateless struct) became `extension LegalRequest`; `wins` builds
  its own context. Redundant `!k.isHonor` (chi) and `pair[0] != pair[1]` (kuikae)
  guards removed.
- main.swift: one generic `value(_:default:_ parse:)` replaces six copies of
  "look up, parse, throw `bad_<key>`"; `parseFlags` sits beside `Flag` like
  `parseMelds`; everything is `throws(BadInput)`, so the `catch let e as BadInput` /
  `error=internal` branches are gone.
- `count(where:)` instead of `filter{}.count`; dead `Suit: Comparable` and
  `Flag: CaseIterable` removed; `ShantenResult.min` uses `compactMap` instead of `99`
  sentinels.

Left alone, and why:

- `isComplete` enumerates all decompositions to test non-emptiness. An early-exit
  twin of the recursion would state the decomposition rule twice; `legal` is already
  1.6x faster than before and the riichi check stops at the first live wait.
- Memo key as a hashed `[Int]` struct (altitude review): the 3-bit packing is one
  line with its bound stated, and input can no longer exceed 4 per kind.
- A `Hand { concealed, melds }` type with hand-size checks (13-3k / 14-3k), and
  moving `ankan_rob` out of `Flag` into the `Situation` type: both reasonable, but
  they reshape every op's signature or the input-flag model; out of scope for a
  finalization pass. `ankan_rob` stays an input flag because the format sends it as one.
- Folding the tenhou winning-tile choice into `readings`: smaller payoff now that both
  loops share `best`.
- Pon variants by counting plain/red copies (vs chi's enumeration): explicit and
  short; a shared helper would not be clearer.
- `ShapeStates.shifted` vs `combined(with:)` of a singleton: `shifted` reads better
  at the call site.
- Storing `runs`/`triplets`/`suits` in `Reading`: score is already ~90k req/s and the
  computed views keep `Reading` small.

### Size and time

Non-blank, non-comment lines (`grep -vE '^\s*(//|#|$)'`):

| file | before | after |
|---|---|---|
| Sources/mj/Tile.swift | 163 | 172 |
| Sources/mj/Score.swift | 159 | 146 |
| Sources/mj/Legal.swift | 149 | 136 |
| Sources/mj/Reading.swift | 137 | 136 |
| Sources/mj/Yaku.swift | 121 | 107 |
| Sources/mj/main.swift | 112 | 115 |
| Sources/mj/Shanten.swift | 112 | 108 |
| Sources/mj/Decompose.swift | 67 | 71 |
| **Swift sources** | **1020** | **991** |
| with Package.swift + build.sh | 1034 | 1005 |

(The earlier table's "1030" total was a sum slip; the files added to 1034.) main.swift
grew with the new validation (tile limits, trigger count, `took`); Tile.swift gained
`[Meld]`/`[Tile]` helpers moved from Legal.swift.

`--time`, same machine, before (original code) and after (final, clean build):

| op | before req/s | after req/s |
|---|---|---|
| agari | 170,487 | 159,261 |
| shanten | 166,735 | 172,501 |
| waits | 39,646 | 43,685 |
| score | 80,799 | 87,599 |
| legal | 20,974 | 32,691 |
| start-up | 6.3 ms | 6.2 ms |

Differences other than `legal` are within run-to-run noise. Corpus after a clean
`./build.sh`: 12439/12439.

### What got in the way

- Nothing serious. Typed throws made the generic `value` parser and the removal of
  the catch-all branch clean; a `do` around `score` inside a `throws(BadInput)`
  function correctly infers `ScoreError` for its `catch`.
- `Optional` has no `filter`, so the range check reads
  `Int($0).flatMap { range.contains($0) ? $0 : nil }`.
- The memo bug is the kind of thing a fixed-size `InlineArray` key or a dedicated
  `Hashable` struct would rule out; the type checker had no way to see that a packed
  `Int` assumed counts below 5.
