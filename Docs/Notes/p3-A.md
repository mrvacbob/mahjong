# Phase 3 package A: foundation — notes

Brief: `Docs/Briefs/p3-A-foundation.md`. Nothing is committed.

## Result

- Corpus: `python3.14 Tools/harness.py ./mj Corpus/*.txt` → **12,439 of 12,439**.
- Unit tests: `swift test` → 29 tests in 8 suites, all pass.
- Clean release build (`rm -rf .build && swift build -c release`): no warnings, no
  errors, Swift 6 language mode (tools version 6.0).
- `sh Sources/Mercury/build.sh` builds as before (nothing to do; not edited), and
  the Mercury `mj` still passes 12,439 of 12,439.
- `grep '^import' Sources/Riichi` is empty: the library imports nothing.

## What I did

1. **Library split.** `Sources/Riichi/` (library, no imports), `Sources/mj/main.swift`
   (line protocol only: request parsing, `Scored`/`Payment` text, the read loop),
   `Tests/RiichiTests/` (swift-testing). `Package.swift` declares a `Riichi` library
   product and the `mj` executable; `./build.sh` is unchanged and still produces
   `./mj`. The seven analysis files moved with `mv`, not `git mv`, since I may not
   stage anything: git will show them as deleted plus untracked until someone adds
   them.
2. **`Rules`** (`Rules.swift`) with `.mahjongSoul` and `.tenhou`. It reaches
   `score(_:rules:)` (a required argument, no default), the yaku tables (yakuman
   multiples, kuitan), fu (double-wind pair), and `LegalRequest.rules` (robbing a
   closed kan, riichi on a fifth-copy wait, and everything `score` decides).
   `isTenpaiAtDraw(_:melds:rules:)` implements the formal-tenpai difference now,
   since it is hand analysis; the round will call it in package B. The line protocol
   gains `rules=mahjongsoul|tenhou` on `score` and `legal` (default Mahjong Soul;
   anything else is `error=bad_rules`), documented in `Spec/formats.md`.
3. **`Seat`, `TableMeld`** (`Seat.swift`). `TableMeld` has kind, tiles, `taken`,
   `from`, and `added` (added kan only), validated constructors `chi`, `pon`,
   `daiminkan`, `ankan` and `adding(_:)` (pon → added kan, keeping the pon's taken
   tile and source), and derives `meld` (the analysis `Meld`), `consumed` (mjai's
   field) and `kuikaeForbidden`. Kuikae moved onto `Meld.kuikaeForbidden(took:)` so
   the line protocol (which has no source seats) and `TableMeld` share it.
4. **`Wall`** (`Wall.swift`): `init?(tiles:)` validated against the exact 136-tile
   set, `init(seed:hand:)`, and accessors for the layout of design §3. The algorithm
   is written out in the new `Spec/wall.md` with three vectors (full walls) plus
   intermediate check values. The vectors were produced by a separate Python
   implementation I wrote from the spec text (kept out of the repository); the
   Swift tests check Swift against them, and they agree.
5. **Thread safety.** `ShantenCalculator` (a class with a mutable memo) is gone.
   Per-suit search results are now two immutable global tables, built on first use;
   Swift runs a global's initialiser exactly once even under concurrent first
   access, so `shanten`, `standardShanten` and `waits` are free functions safe from
   any thread. A test runs 8 concurrent tasks over 400 hands and compares with the
   serial answers. All public value types are `Sendable`.
6. **`Counts` in fixed inline storage**: done, it was contained. `Counts` is a
   `SIMD4<UInt64>`, one word per suit, four bits per kind. The per-suit word is
   also what the shanten table is indexed from. Counts up to 15 fit, so a
   structural fifth copy still works.
7. **Tests**: wall vectors, layout, validation, SplitMix64's published first
   output, bounded sampling; `Counts`; mpsz; `Meld` validation; kuikae; `Seat`;
   `TableMeld`; shanten values and concurrency; Tenhou scoring: the four Mahjong
   Soul double yakuman as single, stacked yakuman (daisuushii + tsuuiisou 3x vs 2x),
   tenhou not upgraded (kokushi and suuankou), kuitan off, double-wind pair fu,
   preset differences; legality: robbing a closed kan per ruleset, riichi on a
   fifth-copy wait, kuitan reaching `ron`, formal tenpai at a draw.

## Decisions the design left open

1. **Fields of `Rules`.** Included: every row of rules.md §1 where the columns
   differ (`returnPoints`/`oka`, `uma`, `doubleYakuman`, `tripleRonAborts`,
   `paoCoversWholeHand`, `openKanDoraBeforeRon`, `kokushiRobsClosedKan`,
   `fifthCopyTenpaiAtDraw`); unverified rows (`honbaToEveryRonWinner`,
   `riichiOnFifthCopyWait`, `fourWindsRiichiStickPaid`, `dealerRepeatBeforeTarget`,
   `allLastTestAfterNagashi`); fields design §3/§4.2/§5 name (`kuitan`,
   `doubleWindPairFu`, `tenhouAnyWinningTile`, `startingPoints`, `targetPoints`,
   `length`, `temporaryFuritenEndsOnCall`). Not fields: rows identical on both and
   not in doubt (kiriage, kazoe cap, riichi minimums, tobi, ...).
2. **One field for open-kan dora timing**, not one per kan type: rules.md gives
   daiminkan and shouminkan the same timing on both clients. **No field for chained
   kans** (rules.md §5 item 10): the design states one order and there is no
   documented alternative to switch to; add it in B if a client log shows one.
3. **`oka` is derived**, `4 × (returnPoints − startingPoints)`, so the two cannot
   disagree. `uma` is in points (`[15_000, 5_000, −5_000, −15_000]`), integers only.
4. **`length`** is a `Rules` field (both presets: hanchan), since the extension
   rule depends on it; a tonpuusen is `var r = Rules.tenhou; r.length = .east`.
5. **`riichiOnFifthCopyWait = true` means structural tenpai** (any wait, fifth copy
   included), not Tenhou's "unless all four concealed" test, which is only defined
   for the draw payment.
6. **Under `tenhouAnyWinningTile = false`, the drawn tile is the winning tile.** So
   on Tenhou rules a tenhou with kokushi drawn on a non-duplicate scores `kokushi`,
   not `kokushi_13` (both 1x there; only the name differs).
7. **Yakuman names under Tenhou rules** stay `kokushi_13`, `suuankou_tanki` etc.,
   printed `:1`, as `formats.md` already implied.
8. **Shuffle details** (all in `Spec/wall.md`): the starting order is canonical
   order with the red copy first within each five; SplitMix64's state starts at the
   key and is advanced before each output (the standard form); bounded sampling is
   "reject below `2^64 mod n`, then `r mod n`" (simpler to reproduce than Lemire's
   multiply-shift, and JavaScript needs `BigInt` either way); Fisher–Yates runs
   `i = 135 … 1` with `j = below(i + 1)`.
9. **Live wall end with kans**: with `k` completed kans the last live draw is index
   `121 − k`; replacement and indicator indices never move. This is what the
   design's "70 − live draws − completed kans" implies, written down.
10. **Wall accessors** take a dealer offset (`dealt(toDealerOffset:)`) or a seat and
    dealer (`dealt(to:dealer:)`); hands come back in dealt order, unsorted.
11. **`Seat`** gained `Comparable`, `next`, `advanced(by:)`, `distance(from:)` and
    `wind(dealer:)`. Its `init` traps outside 0...3 (a programming error, not
    input).
12. **`TableMeld.consumed` for an added kan** is the three pon tiles, matching
    mjai's `kakan` `consumed`; the added tile is `added`.
13. **`Meld(kind:tiles:)` sorts its tiles and rejects two red fives**; it was
    previously only reachable through the text parser.
14. **Shanten tables over a lock**: an immutable table needs no synchronisation
    primitive, and the `Synchronization` module would break "imports nothing".
    Cost: 15.6 MB for the suit table (dense base-5 index, `5^9` entries, only those
    with at most 14 tiles filled) and about 8 ms to build on first use. Inputs
    outside the table (a count of 5, or more than 14 tiles in a suit) fall back to a
    search that bottoms out in the table.
15. **Public surface**: tile and meld types and parsing (`parseTiles`, `parseMelds`,
    `mpsz`), `Counts`, decomposition (`standardDecompositions`, `isComplete`,
    `completingKinds`, `agariForms`, `isChiitoi`, `isKokushi`), shanten and waits,
    `score` with `ScoreRequest`/`WinContext`/`Flag`/`Scored`/`Payment`/`ScoreError`,
    `LegalRequest`/`Situation`, `isTenpaiAtDraw`, `Rules`, `Seat`, `TableMeld`,
    `Wall`. Internal: `Reading`, the yaku tables, fu, `ShapeStates`, the RNGs.
    `format(_:)` was renamed `mpsz(_:)` so the library does not export a name as
    generic as `format`. The `score` text format moved to `mj`.
16. **`[Tile].distinct` is now sorted**, so no code path depends on `Set` order
    even transiently (design goal 2).

## What I think is wrong or inconsistent in the design

1. **Temporary furiten and calls, Mahjong Soul.** Design §4.1 says a call does not
   end temporary furiten on either client and cites Mahjong Soul's published rules
   for "next own draw". But rules.md §1 `furiten_temporary`, Mahjong Soul column,
   still says "until own next draw/call", and the design says rules.md wins. I
   followed the design (`temporaryFuritenEndsOnCall = false` on both, a field so it
   is one line to change) because its text is the later, sourced correction. One of
   the two documents needs fixing; package F should know.
2. **The wall key collides along a line**: `(seed, hand)` and `(seed + G, hand − 1)`
   give the same wall, because the key is linear in both. Harmless for consecutive
   or random seeds, so I kept the design's formula and documented it; if it
   matters, mixing the seed through SplitMix64 once before adding `hand` removes it.
3. **`Wall.init?(tiles:)` hard-codes three red fives.** Both rulesets have three,
   so this is right for Phase 3, but a no-red or three-player variant would need
   the tile set to come from `Rules`. Noted, not designed in.
4. **"One per arena worker" is not a good option for B.** Design §2 offers it for
   `ShantenCalculator`, but `RoundState` is a `Sendable` value that caches waits; a
   per-worker mutable calculator would have to be threaded into every `apply`. The
   immutable table avoids the question; I recommend the design drop that option.
5. Not wrong, but worth stating in §3: the analysis `Meld` cannot always be
   promoted to a `TableMeld` (the line protocol has no source seats), so kuikae has
   to stay computable from `Meld` plus the taken tile. It is.

## Throughput

`python3.14 Tools/harness.py ./mj Corpus/*.txt --time`, before (HEAD, rebuilt in
the scratchpad) and after, run back to back three times on the same machine. req/s
excluding start-up, median of three:

| op | before | after |
|---|---:|---:|
| agari | 281k | 346k |
| shanten | 236k | 165k |
| waits | 43k | 60k |
| score | 78k | 86k |
| legal | 39k | 47k |

These per-op runs are one short process each (0.01–0.07 s), so start-up dominates
and the spread between runs is ±30%. `shanten` per process is lower because the
first call pays the ~8 ms table build (a one-request `shanten` run takes 11.8 ms
against 3.6 ms before; `agari` is unchanged at 3.6 ms). In one process, with each
op's corpus repeated 20 times (so the build is amortised):

| op | before | after |
|---|---:|---:|
| waits | 55,000 req/s | 82,700 req/s |
| shanten | 277,000 req/s | 287,000 req/s |
| score | 89,600 req/s | 89,000 req/s |
| legal | 43,200 req/s | 46,100 req/s |

`waits` gains most (it calls shanten 35 times per request: table lookups replace
dictionary lookups, and `Counts` no longer allocates). Scoring is unchanged: its
time is in decomposition and readings, not in `Counts`.
