# Phase 3 design: the full engine

Status: **draft 1, for council review.** Nothing here is implemented yet.

The engine today answers questions about one hand (`agari`, `shanten`, `waits`,
`score`, `legal` in `spec/formats.md`). Phase 3 adds everything needed to play a whole
game: the wall, turns, calls, riichi, furiten, draws, payments, dealer rotation and
game end. Rules are `spec/rules.md`; where this document and `rules.md` disagree,
`rules.md` wins and this document has a bug.

## 1. Goals and non-goals

Goals:

1. One function, `legalActions`, is the only place that decides what a seat may do.
   Bots, LLM tools, the website and replay validation all use it.
2. Deterministic: the same wall and the same actions give the same game, on every
   platform including WebAssembly.
3. Hidden information cannot leak by accident. Code that plays a seat is handed a
   type that does not contain other hands or the wall.
4. Speaks mjai, so Mortal, akochan and any other mjai bot can sit at the table.
5. Fast enough for bot arenas: target 500 random-bot hanchan per second per core.
6. Two rulesets from day one, Mahjong Soul ranked (default) and Tenhou ranked, chosen
   by a `Rules` value. Three-player is out of scope but should not be designed out.

Non-goals for Phase 3: bots beyond a random one, any UI, networking, time limits,
three-player, local yaku.

## 2. Package layout

```
Package.swift
Sources/Riichi/        library: tiles, hand analysis (existing code), rules, round, game
Sources/RiichiMjai/    library: mjai event encoding/decoding, depends on Riichi
Sources/mj/            executable: line protocol + `replay` and `selfplay` subcommands
Tests/RiichiTests/     swift-testing unit and scenario tests
```

- `Riichi` imports nothing, not even Foundation. This keeps the WebAssembly build
  small (`docs/design/wasm-spike.md`) and the behaviour identical everywhere.
- `RiichiMjai` carries a small hand-written JSON reader and writer for the flat
  objects mjai uses. No Foundation there either.
- The existing five line-protocol operations keep working unchanged and the corpus
  keeps running against `mj` on every change. The existing `legal` operation becomes
  a thin wrapper over the same code `legalActions` uses, so the 758 `legal` corpus
  cases keep guarding the shared logic.
- Public API is declared deliberately (`public` on what the other targets need);
  everything else stays internal.

## 3. Core types

Existing and kept: `Kind` (34 tile kinds), `Tile` (kind + red flag), `Meld`, `Counts`,
`Wind`, the scoring types.

New:

```swift
public struct Seat: Hashable { public let index: Int }   // 0...3, fixed for the game;
                                                         // seat 0 is the first dealer
public struct Rules { ... }                              // one field per row of rules.md §1
extension Rules { static let mahjongSoul, tenhou: Rules }

public struct Wall {                                     // 136 tiles in a fixed order
    init(tiles: [Tile])                                  // explicit (replays, duplicate play)
    init(seed: UInt64, kyoku: Int)                       // shuffled
}
```

**Physical tiles.** `Tile` stays a value (kind + red), not one of 136 identities.
Tsumogiri is recorded on the discard itself, which is all that mjai and the rules
need. Reviewers: say so if you know a rule that needs physical identity.

**Wall layout.** Index 0–51 are the deal (13 each, in mjai's order: four tiles at a
time to East, South, West, North, three rounds, then one each). 52–121 are the live
draws in order. The last 14 are the dead wall: 4 replacement tiles, 5 dora
indicators, 5 ura indicators, in that order. Each kan moves the live wall's end in by
one, so the count of live tiles left is `70 − draws − kans`.

**Shuffle.** Fisher–Yates driven by a generator written out in full in the spec
(xoshiro256\*\* seeded through SplitMix64), so another implementation can reproduce a
wall from `(seed, kyoku index)`. No use of the system random source inside `Riichi`.

## 4. The round state machine

`RoundState` is a value type. It holds the wall, four hands, melds, discard ponds
(each discard marked tsumogiri / riichi / called-away), scores, riichi state per seat
(none, declared this turn, accepted, double), ippatsu flags, furiten flags (discard,
temporary, riichi), first-turn-uninterrupted flag, kan count per seat, dora
indicators revealed, pending kan-dora reveals, pao liability per seat, and a `phase`:

```swift
enum Phase {
    case turn(Seat, after: TurnStart)        // seat holds 14 tiles (or 11, 8, ...) and must act
    case reactions(to: Discard, ...)         // other seats may ron / pon / kan / chi / pass
    case robbing(kan: Meld, by: Seat, ...)   // other seats may ron an added kan (or, kokushi, a closed kan)
    case ended(RoundResult)
}
enum TurnStart { case draw(Tile), replacementDraw(Tile), call(Meld) }
```

Two operations, both pure:

```swift
func legalActions(for seat: Seat) -> [Action]          // empty if the seat has nothing to decide
func applying(_ decisions: [Seat: Action]) throws -> (RoundState, [Event])
```

`Action` is: `discard(tile, tsumogiri)`, `riichi(discard)`, `tsumo`, `ankan(kind)`,
`kakan(tile)`, `kyuushu`, `ron`, `pon(using:)`, `daiminkan`, `chi(using:)`, `pass`.
Red fives make calls distinct: pon of 5m using `0m 5m` and using `5m 5m` are two
actions.

### 4.1 Decision points

- **`turn`**: exactly one seat decides. `applying` takes one action.
- **`reactions`** and **`robbing`**: every seat with a non-empty `legalActions` must
  answer (possibly `pass`) before the state advances. `applying` takes all answers
  at once and resolves them:
  1. Any ron: all ron answers win (multi-ron; Tenhou rules turn three into an
     abortive draw). Other answers are discarded.
  2. Otherwise a pon or daiminkan, if answered.
  3. Otherwise a chi, if answered.
  4. Otherwise the next seat draws, or the round ends in a draw if the live wall is
     empty or an abortive condition is met.
- A seat whose only option would be `pass` is not asked at all. So being asked
  reveals that the seat could act, which is the same information a real client
  leaks through its pause. This is deliberate and is the simplest honest model;
  reviewers may argue for always asking.
- A seat that could ron and answers `pass`, or answers with a call that loses to
  someone else's ron — reviewers please check the second case — becomes furiten
  (temporary, or permanent if in riichi).

### 4.2 Things that are easy to get wrong

Each of these gets a scenario test (section 8). Row numbers refer to `rules.md` §4.

- **Riichi**: `riichi(discard)` puts the seat in "declared"; the 1,000 points and the
  stick move only if the discard is not ronned. A ronned riichi discard pays no
  stick. Legal only with ≥ 1,000 points, ≥ 4 live
  tiles, closed hand, and a tenpai-keeping discard.
- **Ippatsu** ends for everyone on any completed call, including the riichi seat's
  own closed kan, and for a seat after its own next discard. A robbed added kan is
  not a completed call (26).
- **Double riichi, tenhou, chiihou, kyuushu, four winds** all hang off one flag: "no
  call has happened and this seat has not yet discarded". A closed kan by anyone
  clears it for everyone (25).
- **Furiten** looks at every wait, including waits that have no yaku (27), and at
  discards that were called away.
- **Kan dora**: closed kan reveals at once. Open and added kans reveal after the
  following discard passes, or just before another kan by the same seat (17). A
  rinshan win after an open or added kan does not see the new indicator. Whether a
  ron on that discard sees it is unverified for Mahjong Soul (`rules.md` §5 item 4);
  the engine takes a `Rules` field for it and defaults to "not revealed".
- **Chankan**: an added kan opens a `robbing` phase before the replacement draw. A
  closed kan opens one only for seats with a kokushi wait on that kind (16).
- **Four kans**: by two or more seats, the round aborts after the fourth kan's
  discard passes (22). By one seat, play continues and no fifth kan is legal for
  anyone (23). Tenhou and Mahjong Soul agree here.
- **Four riichi**: aborts after the fourth riichi discard passes; that stick stays
  on the table (24).
- **Last tile**: with zero live tiles left, no kan of any sort is legal, and the
  last discard can be ronned but not called for chi, pon or kan. Haitei and houtei
  flags are set from the wall count.
- **Kuikae and dead-end calls** (12, 13): already in the `legal` code; reused.
- **Pao** (31, 32): set when the pon or open kan that completes the third dragon set
  or fourth wind set is made; recorded as (liable seat, which yakuman). Payment
  split per `rules.md`. The current `score` operation returns the ordinary payment;
  pao redistribution is done by the round when it builds point changes.
- **Exhaustive draw**: tenpai is "has at least one wait kind that is not entirely in
  its own hand and melds", matching the riichi rule in `formats.md`. Nagashi mangan
  replaces tenpai payments, leaves sticks on the table, and does not affect dealer
  repeat (30).
- **Multi-ron**: sticks and honba go to the winner nearest the discarder in turn
  order; dealer repeats if any winner is the dealer (21).

### 4.3 Result

`RoundResult` is one of: wins (one or more: winner, from, hand value, yaku list, fu,
ura indicators), exhaustive draw (tenpai seats, nagashi seats), abortive draw
(kind). All carry the four point changes and the riichi sticks left on the table.

## 5. Game flow

`GameState` wraps `RoundState` and owns: round wind and number, honba, sticks on the
table, scores, the seed, and the `Rules`.

After each round: dealer repeat or rotation; honba update; then end checks in this
order: someone below zero; all-last with dealer win or tenpai while first on
≥ 30,000; last scheduled round finished with someone ≥ 30,000; extension round
(sudden death once anyone reaches 30,000 after a hand; ends unconditionally after
the extension wind's fourth round). At game end, leftover sticks go to first place,
ties break by starting seat, then uma is applied.

`rules.md` §5 item 6 (nagashi mangan against a tenpai-yame dealer) is unverified;
the engine checks scores after all payments, and the choice is one `Rules` field.

## 6. Events, mjai, and the player's view

Every state change produces `Event`s, which map one-to-one onto mjai messages:
`start_game`, `start_kyoku`, `tsumo`, `dahai`, `chi`, `pon`, `daiminkan`, `ankan`,
`kakan`, `dora`, `reach`, `reach_accepted`, `hora`, `ryukyoku`, `end_kyoku`,
`end_game`. Event order follows Mortal's dialect of mjai so its bots and its replay
tools accept our logs unchanged. Tile names convert at the `RiichiMjai` boundary
(`5mr`, `E`, `P` and so on); inside the engine, tiles are `Tile`.

**Player view.** `PlayerView` is a separate struct built from a `RoundState` and a
seat. It contains that seat's hand, everyone's melds and ponds, scores, dora
indicators, counts of tiles left, and the seat's own legal actions. It has no wall
and no other hands, and there is no way to get from a `PlayerView` back to the
`RoundState`. Events have a matching `masked(for:)` that hides other seats' draws
and starting hands, as mjai does with `?`.

The seam for anything that plays:

```swift
public protocol Player {
    mutating func observe(_ event: Event)                        // already masked
    mutating func decide(_ view: PlayerView) -> Action           // must be one of view.legalActions
}
```

An mjai bot adapter (child process, JSON lines on stdin/stdout) implements `Player`
in the `mj` executable target, not in the library. An illegal or malformed answer
from a player is recorded and replaced by a default (tsumogiri, or pass), so one bad
bot cannot stall an arena; the count of such substitutions is part of the result,
which is exactly the "illegal move rate" the benchmark wants.

**From JavaScript.** Later, for the website: a handful of exported functions that
take and return mjai JSON strings. Not part of Phase 3, but the reason `RiichiMjai`
has no Foundation dependency.

## 7. Command line

Added to `mj` (the bare line protocol on stdin stays the default):

- `mj selfplay --seed N --games K [--rules tenhou] [--out DIR]`: random-legal bots,
  writes one mjai log per game. Also the throughput benchmark.
- `mj replay [--rules tenhou] FILE...`: reads mjai logs, replays them through the
  engine, and reports the first place where (a) a logged action is not in
  `legalActions`, (b) the engine's point changes differ from the log's, or (c) the
  log ends a round the engine thinks is still live, or the reverse.

## 8. How we will know it is right

In the shootout, differential testing against independent references found the bugs
that reading the code did not. Same approach here, in five layers:

1. **Scenario tests.** One hand-written test per item in section 4.2 and per
   numbered case in `rules.md` §4 that involves game flow, written as a fixed wall
   plus a list of actions plus expected events and point changes. Written by a
   different model from the one that writes the engine.
2. **Differential self-play against libriichi.** Extend `agpl/mj-rs` (AGPL, separate,
   test tooling only) with a checker that reads our `selfplay` logs, feeds each
   seat's masked events to libriichi's player state, and compares its legal-action
   flags with ours at every decision, and its scoring with ours at every win. Run
   under `--rules tenhou`, because libriichi implements Tenhou rules. Tens of
   thousands of random games. Random play reaches odd corners (strange kans, calls
   on everything) that human logs rarely do.
3. **Real logs.** `mj replay` over human game logs in mjai form. Source of logs is an
   open question (section 10).
4. **Invariants checked during self-play:** 136 tiles always accounted for; points
   sum to 100,000 minus sticks on the table; every round ends; `legalActions` is
   never empty for the seat whose turn it is.
5. **Mercury cross-check.** The Mercury core stays at hand analysis; the state
   machine is not ported. Self-play dumps every win as a `score` request and every
   decision as a `legal` request in the line protocol, and the Mercury `mj` must
   agree. This also gives `legal` the held-back cases it lacked in the shootout.

The Mahjong Soul-only rules (double yakuman, triple ron, pao details) are covered by
layers 1 and 5 only, since libriichi cannot check them. That is the weakest spot.

## 9. Work packages and who does them

Implementation is one writer (so the state machine has one mind behind it), with the
tests and the checker written by others:

| # | Package | Writer | Reviewers |
|---|---|---|---|
| A | Library split, public API, `Rules`, `Wall`, shuffle | Opus | Codex, Gemini |
| B | `RoundState`, `legalActions`, events, results | Opus | Codex, Gemini |
| C | `GameState`, end conditions, placement | Opus | Codex, Gemini |
| D | `RiichiMjai`, `PlayerView`, `selfplay`, `replay` | Opus | Codex, Gemini |
| E | libriichi differential checker in `agpl/mj-rs` | Codex | Opus |
| F | Scenario tests from `rules.md` | Gemini | Codex |

E and F start from this document as soon as it is agreed, in parallel with A–D, and
do not read the engine's source while writing their expectations.

Gate for leaving Phase 3: all scenario tests pass; 50,000 differential self-play
games with zero disagreements (or each disagreement explained and ruled on); the
existing corpus still at 12,439 of 12,439; council review of the final code.

## 10. Open questions

For reviewers and the owner:

1. **Real logs.** Tenhou's public archives can be converted to mjai; using them may
   run against Tenhou's terms. Mahjong Soul logs need an account and a third-party
   downloader. Is layer 2 (random self-play against libriichi) enough to start, with
   real logs added later?
2. **Asking only seats that can act** (4.1) versus asking every seat every time.
3. **Simultaneous answers.** The design collects all reactions and then resolves.
   Real clients resolve the same way, but a slow bot holds up the table. Fine for
   arenas; the website will need a timeout policy later.
4. **Mercury.** Is cross-checking only hand analysis enough, or is a second,
   independent state machine worth its cost? The proposal says no: libriichi already
   plays that role.
5. **Unverified Mahjong Soul rulings** carried from Phase 1: kan dora on a ronned
   post-kan discard, multi-ron honba, nagashi against tenpai-yame. Each is one
   `Rules` field with a stated default; none blocks the work.
