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
