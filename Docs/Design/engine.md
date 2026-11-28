# Engine design

This document describes the full-game engine as built. Beyond single-hand
analysis (`agari`, `shanten`, `waits`, `score`, `legal` in `Spec/formats.md`),
it implements everything needed to play a complete game: the wall, turns, calls,
riichi, furiten, draws, payments, dealer rotation, and game end. Section 11
lists what changed after the first draft. Rules are defined
in `Spec/rules.md`; where this document and `rules.md` disagree, `rules.md` wins
and this document has a bug.

## 1. Goals and non-goals

Goals:

1. One function, `RoundState.legalActions(for:)`, is the only place that decides what
   a seat at a table may do. Bots, the drivers, the website and log checking all use
   it. The line protocol's `legal` operation is a separate, hypothetical one-hand
   question (section 2) that shares primitives and the scorer with it.
2. Deterministic: the same wall and the same actions give the same game and the same
   bytes of log, on every platform including WebAssembly. No output may depend on
   `Dictionary` or `Set` iteration order, which Swift randomises per process.
3. Hidden information cannot leak by accident. Code that plays a seat is handed a
   type that does not contain other hands or the wall.
4. Speaks mjai, so Mortal, akochan and any other mjai bot can sit at the table.
5. Fast enough for bot arenas: about 14,000 rounds of uniform random play per second
   on one core in process, with or without events (`mj bench-round`; section 4.4).
6. Two rulesets from day one, Mahjong Soul ranked (default) and Tenhou ranked, chosen
   by a `Rules` value that reaches scoring and legality as well as game flow.
   Three-player is out of scope but should not be designed out.

Non-goals: bots beyond random ones, any UI, networking, three-player, local yaku.

## 2. Package layout

```
Package.swift
Sources/Riichi/        library: tiles, hand analysis (existing code), rules, round, game
Sources/RiichiMjai/    library: mjai event encoding/decoding, depends on Riichi
Sources/mj/            executable: line protocol, `selfplay`, `replay`, `check-log`, drivers, bot adapters
Tests/RiichiTests/     swift-testing unit, scenario and command tests
Tests/RiichiMjaiTests/ the mjai codec
Tests/mjTests/         the driver and the mjai adapter in process (`@testable import mj`)
```

- `Riichi` imports nothing, not even Foundation, and uses no floating point (uma and
  oka stay in integer points). `Int` is 32 bits on wasm32, which is enough for points.
- `RiichiMjai` carries a hand-written JSON reader and writer, also without
  Foundation. The reader must skip any value it does not need, including nested
  objects and arrays of floats: Mortal's replies carry a `meta` object with both.
- The five line-protocol operations use Mahjong Soul rules by default, and the
  corpus runs against `mj` on every change. `legal` is its own
  entry point (`LegalRequest`, `Legal.swift`): a hypothetical hand with no round
  behind it. Its request is weaker than a table position (no score, so no riichi
  affordability test; the strict `Spec/formats.md` fifth-copy rule for riichi), so
  it answers what the line protocol defines, not always what the table offers. It
  shares hand completion, kuikae and the scorer with `RoundLegal.swift`, which has
  the table's own legality (scores, the two-step riichi, the tile's origin). The
  Mercury cross-check (section 8) compares the two on every self-play decision and
  names the two known differences.
- The shanten tables are immutable and built once, so analysis is safe from several
  threads.

### 2.1 Input from outside

Every public entry point that takes a value from outside the library checks it and
returns an error instead of trapping (on wasm a trap ends the whole instance):
`Rules.validate()` (point settings within ±1,000,000, four uma entries, double-wind
fu 2 or 4); `RoundState.init` and `GameState.init` (`InputError`: kyoku 1–4, honba and
sticks 0–1,000, four scores within ±100,000,000, a non-negative hand count);
`GamePosition.init`; `score` (`ScoreError`: valid rules, 13 − 3 × melds concealed
tiles, a possible tile set counting the indicators, honba 0–1,000,000);
`LegalRequest.actions`; `discardAnalysis`; `GameFlow.result` and `ranking`;
`parseTiles` (ASCII digits only). The mjai decoder and the line protocol return
errors for anything malformed. `precondition` is kept for the engine's own
invariants and for typed index accessors (`Seat(_:)`, `Kind(_:)`, `Wall`'s accessors,
`Counts` subscripts), which, like `Array`'s subscript, every decoder in the library
reaches only with checked values (`Seat(checked:)` and `Kind(checked:)` are the
failable forms). A running game needs no admission bounds: honba grow by one a hand
up to 1,000,000 (`RoundState.maxRunningHonba`), where the game ends
(`GameEnd.counterLimit`) rather than overflow; sticks and scores cannot grow, since
every point stays among the seats and the table.

## 3. Core types

From single-hand analysis: `Kind`, `Tile` (kind + red flag), `Counts`, `Wind`, and the scoring types.

```swift
public struct Seat: Hashable, Sendable { public let index: Int }  // 0...3, fixed for the game;
                                                                  // seat 0 is the first dealer
public struct Rules: Sendable { ... }       // one field per row of rules.md §1 that differs or has a variant
extension Rules { static let mahjongSoul, tenhou: Rules }

public struct Wall: Sendable {              // 136 tiles in a fixed order
    init?(tiles: [Tile])                    // validated: the exact 136-tile set
    init(seed: UInt64, hand: Int)           // hand = count of hands dealt so far in this game
}
```

**`Rules` reaches hand analysis.** `score`, the yaku tables and `legalActions` take a
`Rules`: Mahjong Soul's four double yakuman and the free winning tile of a heavenly
hand are fields, as are kuitan, the double-wind pair, robbing a closed kan, the
composite pao rule, kan dora timing, formal tenpai and riichi on a fifth copy, and
the others of 4.2 and 5. `Spec/rules.md` §1.1 lists every field with both presets'
values.

**Melds.** The analysis `Meld` (kind + tiles) is not enough for a game. The round
keeps `TableMeld`: kind, tiles, the tile taken, and the seat it came from (both nil
for a closed kan). Kuikae, pao, nagashi mangan, mjai's `target`/`pai`/`consumed` and
an added kan's history all read from it. The analysis `Meld` is derived from it.

**Physical tiles.** `Tile` stays a value, not one of 136 identities. A seat's hand
is its 13 (or fewer) concealed tiles plus a separate "drawn tile" slot, so a discard
can be recorded as tsumogiri or from the hand even when the two tiles are equal.

**Unknown tiles.** A masked event carries `Tile?`; `nil` is a tile the observer may
not see.

**Wall layout.** Our own, fixed here because mjai does not define one. Index 0–51
are the deal: tiles `4i ..< 4i+4` go to seats in dealer order for three rounds, then
one tile each (so the dealer's 13 are indices 0–3, 16–19, 32–35, 48). 52–121 are the
70 live draws in order. 122–125 are the four replacement tiles in the order drawn,
126–130 the dora indicators in the order revealed, 131–135 the matching ura
indicators. Live tiles left = `70 − live draws − completed kans`.

**Shuffle.** Fisher–Yates from the end, with unbiased bounded sampling by rejection,
driven by xoshiro256\*\* whose state is four SplitMix64 outputs from the key
`mix(seed) ^ mix(~UInt64(hand))`, where `mix` is one SplitMix64 output step, so that
different (seed, hand) pairs do not collide by simple arithmetic. `Spec/wall.md` is
the authority, with three known walls as test vectors. Keying on the count of hands dealt, not the round number,
means a repeated dealership gets a new wall. The seed never appears in anything a
seat is shown. Seeds cross into JavaScript as decimal strings.

## 4. The round state machine

`RoundState` is a value type holding: the wall and its cursors; for each seat the
concealed hand, drawn tile, melds, pond (each discard marked tsumogiri, riichi
declaration, called away) and cached waits; scores; riichi state per seat (none,
declared and awaiting discard, declared with discard out, accepted; plus whether it
was a double riichi); ippatsu flags; furiten flags (own discard, temporary, riichi);
`anyCallMade` (table-wide, set by any call including a closed kan); kan count per
seat; dora indicators revealed and kan dora owed; pao liability (liable seat and
which yakuman) per seat; and a `phase`:

```swift
enum Phase {
    case turn(Seat, TurnStart)           // this seat must act
    case reactions(Discard)              // one or more other seats may ron / pon / kan / chi / pass
    case robbing(PendingKan)             // one or more other seats may ron a kan / pass
    case ended(RoundResult)
}
enum TurnStart { case draw, replacementDraw, call, riichiDeclared }
```

The state is never left in a phase where nobody has a decision: applying an action
runs on, through draws and through windows nobody can use, until some seat must
decide or the round has ended. One step can therefore emit several events
(`dahai`, `reach_accepted`, `tsumo`).

```swift
init(rules:wall:roundWind:kyoku:honba:sticks:dealer:scores:events:) throws(InputError)
func legalActions(for seat: Seat) -> [Action]            // empty if the seat has nothing to decide;
                                                         // in a canonical, documented order
mutating func apply(_ action: Action, by seat: Seat, events: inout [Event]) throws(RoundError)  // .turn
mutating func resolve(_ answers: Answers, events: inout [Event]) throws(RoundError)              // .reactions, .robbing
```

Each also has a form without events, which builds none. The forms with events take
an optional observer, shown the state as of each event as it is emitted (tools such
as the legality dump). That state is part-way through a step, so it is marked as
advancing: it offers no actions (`legalActions` and `seatsToAnswer` are empty) and
`apply` and `resolve` on it throw `wrongPhase`.

`Answers` is a fixed four-slot value, one optional action per seat, not a dictionary.
Non-mutating wrappers that copy exist for tests and tools. An action that is not in
`legalActions` throws and leaves the state unchanged.

`Action`: `discard(tile, tsumogiri)`, `riichi`, `tsumo`, `ankan(kind)`,
`kakan(tile)`, `kyuushu`, `ron`, `pon(using:)`, `daiminkan`, `chi(using:)`, `pass`.
Red fives make calls distinct: pon of 5m using `0m 5m` and using `5m 5m` are two
actions.

**Riichi is two steps**, as in mjai: `riichi` moves to `turn(seat, .riichiDeclared)`,
where the only legal actions are the discards that leave the hand tenpai (each with
its own tsumogiri flag). After a call (`TurnStart.call`) only discards from the hand
are legal, minus the kuikae tiles; there is no drawn tile and so no tsumogiri.

### 4.1 Windows and their resolution

When a discard or a kan opens a window, every seat with a non-empty `legalActions`
must answer. A seat whose only option would be `pass` is not asked. All answers are
validated against the same state and resolved together, in this order:

| # | Condition | Result |
|---|---|---|
| 1 | Any `ron` answered | Every ron wins. With `Rules.tripleRonAborts` (Tenhou), three rons are an abortive draw (sanchahou) instead. A riichi declared on this discard is not accepted and pays no stick. |
| 2 | The discard is the fourth identical wind of an uninterrupted first go-around | Abortive draw (four winds). A riichi declared on it is accepted first (4.2). |
| 3 | Otherwise a riichi declared on this discard is accepted now | 1,000 points move to the table (`reach_accepted`), before anything below. |
| 4 | This was the discard after a fourth kan and the kans belong to two or more seats | Abortive draw (four kans). Calls answered on this discard are not made. |
| 5 | That acceptance was the fourth riichi | Abortive draw (four riichi). The fourth stick stays on the table. Calls are not made. |
| 6 | A `pon` or `daiminkan` answered | It is made. (At most one seat can hold such a call on one tile.) |
| 7 | A `chi` answered | It is made. |
| 8 | No live tiles left | Exhaustive draw. |
| 9 | Otherwise | Next seat draws. |

Before rows 2–9, an indicator still owed by an open or added kan is shown if Mahjong
Soul's timing left it owed (`openKanDoraBeforeRon` off; 4.2).

For a `robbing` window: any ron wins and the kan is not made; three rons abort the
hand with `tripleRonAborts` (Tenhou's added kan; a closed kan robbed by three kokushi
under mixed rules); otherwise the kan completes.

**Furiten is decided from waits, not from who was asked.** When a window closes
without ending the round, every seat other than the discarder whose current waits
include the tile's kind becomes temporarily furiten (permanently, if in riichi). It
makes no difference whether the seat had a yaku, whether it was asked, or whether it
answered `pass` or a call. The same applies to the tile of an added kan (and of a
closed kan, for a seat that could have robbed it). Separately:

- *Own-discard furiten*: any of the seat's waits is in its own pond, including
  discards that were called away. Recomputed when the hand's waits change.
- *Temporary furiten* ends when the seat next draws from the live wall, and, with
  `Rules.temporaryFuritenEndsOnCall` (on for both presets, from both clients'
  records), when the seat makes a chi, pon or open kan. A replacement draw after a
  kan leaves it as it is.
- *Riichi furiten* is permanent, and is also set when a riichi seat draws a winning
  tile and does anything other than `tsumo` with it, including a closed kan.

A seat that is furiten still appears in windows for calls, and is simply not offered
`ron`.

### 4.2 Rules that are easy to get wrong

Each gets a scenario test (section 8). Numbers in brackets are `rules.md` §4 items.

- **Riichi** needs ≥ 1,000 points, a closed hand, a tenpai-keeping discard, and at
  least 4 live tiles. Double riichi is fixed at declaration: `anyCallMade` false and
  the seat has no discards yet.
- **Ippatsu** starts when a riichi is accepted. It ends for every seat when any call
  is completed, including the riichi seat's own closed kan, and for a seat at its
  first discard after the riichi discard. A robbed added kan is not a completed call
  [26]. (Tenhou ends ippatsu for an added kan after the robbing window, just before
  the replacement draw.)
- **First go-around.** Tenhou, chiihou, nine terminals and double riichi each need
  `anyCallMade == false` and that seat to have no discard yet. Four winds needs
  `anyCallMade == false` and each seat's first discard to be the same wind. A closed
  kan by anyone sets `anyCallMade` [25].
- **Four winds.** Checked at the fourth discard (row 2 above). A ron on that tile is
  not possible in practice (all four copies are in ponds). A riichi declared on the
  fourth discard is accepted and its stick paid before the abort
  (`Rules.fourWindsRiichiStickPaid`, on for both from the records; libriichi aborts
  first and pays nothing).
- **Kans as transactions.**
  - *Closed kan*: announce; robbing window if the ruleset allows any (Mahjong Soul:
    kokushi only [16]; Tenhou: none); then commit: count the kan, clear ippatsu and
    set `anyCallMade`, reveal its indicator at once, draw the replacement. A rinshan
    win sees the new indicator [17].
  - *Added kan*: announce the added tile with the pon still intact; robbing window.
    If robbed: the pon stays a pon, no kan is counted, no replacement draw, no
    indicator, ippatsu survives, and the winner scores chankan [15]. Otherwise
    commit, then draw the replacement with the indicator owed.
  - *Open kan*: commit, draw the replacement with the indicator owed.
  - *An owed indicator* is revealed immediately before the kan seat's next discard
    (`dora`, then `dahai`), so a ron on that discard counts it and its ura
    (`Rules.openKanDoraBeforeRon`, on for both: Tenhou's 「後めくり（打牌または続く嶺上の
    直前）」 and Mahjong Soul's records; off, it is shown only once that discard's
    window passes), or just before the seat's next replacement draw if it kans again
    first. For open kan → closed kan the order is `dora` (owed), `ankan`, `dora`
    (new), `tsumo`. For open kan → added kan it depends on the ruleset: Tenhou gives
    `kakan`, robbing window, `dora`, `tsumo`; Mahjong Soul shows the owed indicator
    right after the `kakan`, before the window, so a chankan counts it
    (`Rules.owedDoraAtChainedAddedKan`). A rinshan win right after an open or added
    kan does not see that kan's indicator.
  - *A kan announcement changes nothing* of the declarer's (hand, drawn tile, melds,
    counts, cached waits) until its robbing window has closed; only an indicator
    owed by an earlier kan may already be shown.
- **Four kans.** By two or more seats: the fourth kan's replacement draw may win,
  its discard may be ronned, and otherwise the round aborts ahead of any call (row 4)
  [22]. By one seat: play continues, and no fifth kan is legal for anyone [23].
- **Four riichi** [24]: row 5.
- **Last tile.** No kan of any sort with zero live tiles. The discard made with zero
  live tiles can be ronned (houtei) but not called. Haitei applies to a win on a
  normal draw that leaves zero live tiles; a replacement draw is rinshan only, never
  haitei [18], though the discard after it is houtei if no live tiles remain.
- **Kuikae and dead-end calls** [12, 13]: handled by the `legal` code, fed from
  `TableMeld`.
- **Pao** [31, 32]: set when the pon or open kan that completes the third dragon set
  or fourth wind set is made, against the seat that fed it. Mahjong Soul: the liable
  seat pays for the liable yakuman only; Tenhou: for the whole composite hand. In
  both, the liable seat pays the honba. Tests cover tsumo, ron from a third party, ron from
  the liable seat itself, and pao inside a double ron. The `score` operation still
  answers the ordinary payment; the round redistributes.
- **Riichi on a fifth-copy wait**: allowed when the four copies are not all
  concealed (in the records, always the seat's own closed kan), on both clients
  (`Rules.riichiOnFifthCopyWait`); the line protocol keeps `formats.md`'s strict
  reading.
- **Exhaustive draw.** Tenpai for payment: a wait that exists only as a fifth copy
  counts unless all four copies are in the concealed hand, on both clients
  (`Rules.fifthCopyTenpaiAtDraw`; off, `formats.md`'s definition). Nagashi mangan:
  all of the seat's discards are terminals or honors and none was called away; it
  replaces tenpai payments, pays every qualifying seat, moves no sticks or honba,
  and does not affect dealer repeat [30].
- **Multi-ron**: each winner's payment is computed separately; sticks and honba go
  only to the winner nearest the discarder in turn order; the dealer repeats if any
  winner is the dealer [21].
- **Event reason for nagashi mangan**: the `ryukyoku` event's reason is `exhaustive`;
  the nagashi seats are listed in the result, and the point changes show the payment.
- **A robbed kan never counts** toward four kans.
- **Declining a self-drawn win outside riichi** and then keeping the wait: no
  temporary furiten on either client (see `Docs/Evidence/closeout.md`). Declining by a discard leaves the seat furiten on
  the discarded tile anyway (the 13 tiles left wait on it); declining by a closed or
  added kan, Tenhou's records show the seat winning by ron before its next live
  draw. `Rules.temporaryFuritenOnDeclinedTsumo` (off for both) keeps the strict
  reading of Tenhou's manual (「和了放棄…後は同巡フリテン」), lasting through the kan's
  replacement draw. A replacement draw does not clear temporary furiten; only a
  live-wall draw (or, with `temporaryFuritenEndsOnCall`, the seat's own call) does.
- **Nine terminals** is an action on the seat's own first draw and ends the round at
  once.

### 4.3 Result

`RoundResult`: wins, an exhaustive draw (tenpai seats, nagashi seats) or an abortive
draw (its reason), with the round's point changes and scores, the sticks left on the
table and whether the dealer repeats. Each `Win` (in turn order from the discarder)
has the winner, the seat it won from, the tile, the indicators and ura shown, the
`Scored` hand (the ordinary payment with this winner's honba, as `score` gives it),
its own point changes by seat (pao redistribution and the first winner's sticks
included: the settlement actually made), the liable seat if pao applied, and the kind
of kan robbed, if any.

### 4.4 Speed

- Transitions mutate in place; no state snapshots are kept by the engine.
- Each seat's counts and structural waits (a bit per kind) are cached and recomputed
  only when its concealed hand changes. Shanten is computed where needed: the riichi
  gate tests shanten ≤ 0 of the 14 tiles before searching for riichi discards.
- "Can this seat win on this tile" is first a lookup in the cached waits (and the
  furiten flags); only a seat that waits on the tile is scored, by the full scorer,
  which also decides the yaku. Profiling has not called for a cheaper yaku-only test.
- `Counts` has fixed inline storage (four bits per kind).
- Events are appended to a caller-owned buffer, which the emitter takes over without
  copying; a caller that passes none pays nothing for them.

Measured in process (`mj bench-round`): about 14,000 rounds of uniform random play
per second on one core, the same with events on.

## 5. Game flow

`GameState` owns: `Rules`, seed, hands dealt so far, the current hand's starting
position (`GamePosition`: round wind and number, honba, sticks, scores), the current
`RoundState`, and, at the end, the `GameResult`. A game may start from any position
(scenarios, directed play) and take its walls from a function of (seed, hand
number) instead of the seeded shuffle. `GameFlow.next` and `GameFlow.result` are the
transition and the final step as pure functions.

After each round, in this order:

1. Apply the point changes. If any score is below zero, the game ends (zero
   continues).
2. Honba: +1 after any draw and after a dealer win; reset to 0 after a win by a
   non-dealer only.
3. Dealer repeats on a dealer win (any winner being the dealer, in a multi-ron), on
   dealer tenpai at an exhaustive draw, and on every abortive draw.
4. *All last* is the last hand of the scheduled wind (East 4 or South 4) and every
   hand after it.
   - In all last, if the dealer repeats by winning or by tenpai (not by an abortive
     draw) and is first with at least `Rules.targetPoints` (30,000 in both presets),
     the game ends (agari-yame, tenpai-yame). "First" uses the seat-order tie-break,
     so a last dealer level with another seat is not first.
   - If the dealer repeats otherwise, play continues, even when another seat has the
     target (`Rules.dealerRepeatBeforeTarget`, on for both from the records; off,
     that seat's target ends the game, except after an abortive draw).
   - If the dealer does not repeat: the game ends if anyone has the target, or if the
     next hand would start a wind beyond the extension (South for an East game, West
     for a South game). Otherwise play continues into, or within, the extension.
   - The target tests use scores after the hand's payments, nagashi mangan payments
     included (`Rules.allLastTestAfterNagashi`, on for both from the records; off,
     the scores before them), and before leftover sticks are awarded (Tenhou:
     「供託未収」).
   - The next hand would have more than 1,000,000 honba: the game ends
     (`GameEnd.counterLimit`; section 2.1).
5. At the end: leftover sticks go to first place; ranks break ties by starting seat;
   then return points, oka and uma from `Rules` give the final result (`GameResult`:
   ranks, raw scores, adjusted scores). Adjusted scores are integer points, so
   +27.0 is written 27000.

Leftover sticks at the end go to first place; no record shows the final award
(rules.md §5 item 12), so this is the published rule. `GameState.view(of:)` shows the
final scores once the game is over.

## 6. Events, mjai, and the player's view

`Event` cases correspond to mjai messages. Order and fields follow Mortal's dialect,
and we emit a superset of fields so that akochan, which speaks the original
protocol, also works (Mortal ignores fields it does not know).

| Event | Fields | Notes |
|---|---|---|
| `start_game` | `names`, `id` (per recipient) | No seed. `Event.startGame` has no fields; `RiichiMjai` adds the names and, in a seat's copy, its id. |
| `start_kyoku` | `bakaze`, `kyoku` (1–4), `honba`, `kyotaku` (count of sticks), `oya` (0–3), `dora_marker`, `scores`, `tehais` | Other seats' hands are `?` when masked. Followed by the dealer's `tsumo`. |
| `tsumo` | `actor`, `pai` | `?` to other seats. Replacement draws are also `tsumo`. |
| `dahai` | `actor`, `pai`, `tsumogiri` | |
| `chi`, `pon`, `daiminkan` | `actor`, `target`, `pai`, `consumed` | |
| `ankan` | `actor`, `consumed` (4) | |
| `kakan` | `actor`, `pai`, `consumed` (the 3 pon tiles) | |
| `dora` | `dora_marker` | Order as in 4.2. |
| `reach` | `actor` | Then that seat's `dahai`. |
| `reach_accepted` | `actor`, `scores` | Immediately before whatever follows the window: the next `tsumo`, a `chi`/`pon`/`daiminkan`, or `ryukyoku`. Absent if the discard was ronned. |
| `hora` | `actor`, `target` (= actor for tsumo), `pai`, `deltas`, `ura_markers` and `uradora_markers`, `hora_tehais`, `yakus`, `fu`, `fan`, `scores` | One per winner, in turn order from the discarder. The first carries the sticks and honba. `ura_markers` is `[]` for a winner not in riichi. |
| `ryukyoku` | `reason`, `deltas`, `tenpais`, `tehais` (noten hands masked), `scores` | Mortal reads only `deltas`. |
| `end_kyoku`, `end_game` | (`scores` on `end_game`: the final scores, sticks paid out) | In the unmasked log `end_kyoku` also carries `scores`, `deltas`, `kyotaku_left` and `dealer_repeats`, for checkers. |

Tile names convert at the `RiichiMjai` boundary (`5mr`, `E`, `P`, ...).

**Player view.** `PlayerView` (`RoundState.view(of:)`, `GameState.view(of:)`) is a
`Table`, which follows from the seat's masked events alone, plus what the engine
decides for the seat: its furiten (and the three sorts, `furitenParts`) and its
legal actions. The `Table` has the seat's hand and drawn tile; everyone's melds,
ponds (each discard with its place in the round's order) and riichi status; scores;
round wind, round number, honba, sticks, dealer; dora indicators; live tiles left;
and the open window (the discard or announced kan, and whose). The window is shown
only to a seat asked in it: that a window is open at all tells that some seat may
call, so a seat with no decision does not learn it. The view has no wall and no other
hands, and nothing leads from it back to the `RoundState`. Events shown to a seat
are a distinct masked type, so an unmasked event cannot be passed by mistake.
`ViewFolder` rebuilds the `Table` (not the furiten or the legal actions) from a seat's
masked events, at every step and at the end of the game, where both show the final
scores with the leftover sticks paid out.

### 6.1 What a seat's view gives a bot

Pure functions of a `PlayerView` (`Analysis.swift`), for bots and tools, none of
which needs the `RoundState`: the seat's wind (`seatWind`, `wind(of:)`), closed hand
and riichi (`isClosed`, `isRiichi`, `riichiStatus`), concealed tiles with the drawn
one, the seat's structural waits (`waits`) and furiten sorts; the tiles it can see
by kind (`visibleCounts`: its own concealed tiles, every meld, every discard still in
a pond, the indicators) and the copies it cannot see (`unseen`); a per-discard
analysis (`discardOptions()`, and the pure `discardAnalysis(concealed:meldCount:
visible:candidates:)`): for each legal discard, the shanten left, the kinds that lower
it, and how many copies of each the seat cannot see; and defensive facts against a
seat: `genbutsu` (kinds it cannot ron now: its own discards, discards after its
riichi, and discards since its own last one, an open window's discard excepted),
`suji` (kinds no two-sided wait can win on without furiten: a heuristic) and
`allCopiesSeen`. `ScoreRequest(hand:tableMelds:...)` takes the table's melds. JSON
codecs for views and actions, and a decision envelope for remote bots, are deferred
to the web and remote-bot work (section 10).

**The API is the step API**: `legalActions`, `apply`, `resolve`, `PlayerView`, masked
events. JavaScript cannot block inside a callback, so nothing in `Riichi` calls out
to a player.

**Drivers and bot adapters** live in the `mj` executable target. After each step the
driver gives every seat the step's events one at a time (so where the engine paused,
and so whether another seat was offered a call, does not show), with the seat's view
attached to the event that asks it to decide: its prompt (`PlayerView.prompt(in:)`:
its draw, its chi or pon, or its riichi declaration on its turn; the discard in a
discard window; the `ankan` or `kakan` in a robbing window). Only indicators can
follow a prompt in the same step (Mahjong Soul's owed indicator after a chained
added kan). Once the step's events are delivered the driver asks for the decision,
then steps the state. The mjai adapter (a child process in a process group of its
own, JSON lines):

- sends every event to the bot and reads one reply per event (`none` when it has
  nothing to do), as mjai bots expect;
- binds the decision to the prompt: the reply to the prompt event is the decision,
  checked against it (`Mjai.action(_:for:)`: the message type must fit the trigger,
  `actor` must be the seat, a `hora`'s `target` and `pai` must name what was offered,
  a kan's `consumed` must be the tiles it would use, and the action must be legal).
  A reply to a later notification of the same step must be `none`; a reply other
  than `none` to an event that asks nothing is counted as *unbound*;
- performs riichi as mjai does: the bot answers `reach`, is shown the `reach` event,
  and answers its `dahai`;
- treats a bot's `ryukyoku` reply as nine terminals;
- has a timeout (1 ms to an hour), one deadline covering both sending an event and
  reading its reply (a bot that stops reading its input times out), and stops a bot
  (SIGTERM, then SIGKILL, to its whole process group) when it times out, exits,
  floods its output (a reply over 1 MiB) or the game ends;
- substitutes the first legal action of `pass`, tsumogiri, the first legal discard
  for a decision it cannot take from the bot, and counts why: *malformed* (not a
  message), *illegal* (does not fit the decision, or a notification answered with
  something other than `none` after the answer), *timeout* and *crashed* (the
  transport failed; every later decision is then substituted under the same
  reason), *unbound* (no reply bound to the decision). Those counts are the
  benchmark's illegal-move rate; a reply is never taken as a pass because it could
  not be read.

**From JavaScript** (planned): exported functions taking and returning UTF-8 buffers
of JSON, covering mjai events and also `PlayerView` and legal actions (mjai alone
cannot drive a UI).

## 7. Command line

Subcommands of `mj` (with no subcommand, it runs the line protocol on stdin):

- `mj selfplay --seed N --games K [--rules tenhou] [--length east] [--bots
  random|eager|mjai:CMD] [--seat N=BOT] [--scenario NAME] [--out DIR] [--legal]
  [--requests FILE] [--check] [--timeout MS] [--quiet]`. Writes, per game, the mjai
  log and an **engine trace**: the ruleset (a preset name, and `length east` for an
  East-only game: version 1 records nothing else of `Rules`), seed, bots, the
  directed scenario if any, and every decision submitted (including passes and calls
  that lost), which is what exact reproduction needs and an mjai log does not
  contain. `eager` bots always win when they can (but pass a ron one time in ten),
  declare riichi when legal, call and kan with probability 60%, and otherwise
  discard to the lowest shanten; `--seat` puts another bot (or an mjai child
  process) at one seat. `--scenario NAME` plays directed bots on arranged walls that
  reach one rare branch in bulk (`Docs/Evidence/closeout.md`). `--legal` writes every
  seat's legality rows for the libriichi comparison, `--requests` the Mercury dump,
  `--check` runs the invariants of section 8 on every game. In the unmasked log each
  `start_kyoku` also carries `wall`: the 136 tiles in the layout of section 3, so a
  checker can rebuild the hand without the trace. With an external bot at the table
  each game draws a fresh seed from the system unless `--seed` is given.
- `mj replay TRACE...`: re-runs traces and requires byte-identical logs.
- `mj check-log [--rules tenhou] [--set FIELD=VALUE]... [--json] [--stdin] FILE...`:
  for mjai logs from elsewhere. It validates the fields a log provides, and those it
  lets one infer, under documented conventions: it rebuilds a wall per hand from
  what the log reveals (dealt hands, draws, indicators; unseen slots filled with the
  unused tiles, and searched when a hidden indicator decides a payment), then
  requires every logged action to be legal and every point change and next-hand
  header to match; it accepts the reduced format (no deltas or yaku: the next
  header checks the points) and, since the logs do not say which, tries a game
  whose flow fails as a hanchan as an East-only game. It reports what it could not
  check (passes, losing calls, unseen ura) and names each convention it relied on.
- `mj bench-round [ROUNDS] [tenhou]`: rounds per second of uniform random play in
  process, without and with events.

## 8. How we know it is right

1. **Scenario tests** (`Scenarios/*.scn`, 138): a fixed wall, a list of actions,
   expected events and point changes, under both rulesets where they differ; written
   by a different model from the engine's author, from this document and
   `rules.md`, and corrected only by their writers. The runner requires every seat
   asked in a window to be listed, checks both sides of the point ledger, the final
   award of leftover sticks and each seat's folded view in every scenario, and
   compares the fixture's own expectations (all of `events` where given, in order
   for `events_order`). `Rules` fields no preset turns on are checked by flipping one
   field on an existing scenario.
2. **Differential against libriichi** (Tenhou rules), in the AGPL crate
   `AGPL/libriichi-check`, which depends on Mortal's vendored `libriichi` so it
   builds offline. `AGPL/mj-rs` has no event processing.
   - *Board replay*: load our wall, hands and indicators into libriichi's own board,
     drive it with the decisions from our trace, and compare its event log with ours
     event by event, then the result: point changes, sticks, dealer repeat. This
     covers draws, nagashi, pao, multi-ron splits, abort timing and dora order.
   - *Legality*: feed each seat's masked events to libriichi's player state and
     compare its action flags, discard and kan candidates, waits and furiten flag
     with ours for all four seats after every event, which also catches a
     decision we failed to offer.
   - *Known differences*, kept as a written list in the crate
     (`AGPL/libriichi-check/NOTES.md`) and in `Tools/classify_libriichi.py`, and
     filtered by name, never silently: libriichi has no triple-ron abort; does not
     stack tenhou or chiihou; aborts four winds before accepting a riichi on it;
     scores a caller's rinshan win before its first discard as chiihou; riichi
     discards and red-five call variants are not distinguished in its flags; yaku
     names and fu are not exposed; and the legality categories of the notes. Game
     end is not covered, because its `Game` deals its own walls.
   - This is external evidence for Tenhou rules only, and for what libriichi
     models: round flow, legality and payments, not game end.
3. **Mercury cross-check** (`Tools/mercury_diff.sh`). The Mercury core stays at hand
   analysis. Mahjong Soul self-play dumps every win as a `score` request and every
   decision as a `legal` request; Mercury's `mj` must answer each as ours does, and
   ours is compared with the round engine's own answer (two known differences:
   riichi under 1,000 points and fifth-copy riichi, which the line protocol does not
   model). It checks hand analysis and the line protocol's legality, not round flow,
   pao or payments.
4. **Invariants and cheap properties**, checked in self-play (`--check`) and in the
   test suite. They show the engine agrees with itself, not that it agrees with a
   client:
   - tiles conserved by kind and by red flag; `sum(scores) + 1,000 × sticks` constant;
   - every round ends; the seat to act always has a legal action; every action in
     `legalActions` (and every window answer) is accepted, and nothing outside it is;
   - after every window that did not end the round, every seat waiting on that tile
     is furiten;
   - folding a seat's masked events rebuilds exactly its view's `Table`, at every
     step and at the end of the game;
   - a trace replays to a byte-identical log; `check-log` accepts our own logs;
   - results do not change when answers are supplied in a different seat order;
   - swapping the three suits throughout a wall, reds included, gives the same game
     with suits swapped.
5. **Coverage report.** Self-play counts how often each rare branch was reached
   (each abort, chankan, rinshan, each pao case, double and triple ron, nagashi,
   riichi kan, four kans by one seat, each end-of-game branch). The gate is on
   branches reached, not only on games played.
6. **Real logs** (`Tools/reallogs.py`, `Docs/Evidence/real-logs.md`): `check-log` over
   millions of Tenhou houou and Mahjong Soul Throne and Jade games. The external
   evidence for Mahjong Soul's payments and legality, as far as a log records them;
   it cannot show passes, losing calls or what a client would have offered.
7. **The bot adapter** is tested end to end (`Tests/mjTests`): a whole game with an
   mjai child process, asserting the win, the event order and the substitution tally
   when the reply comes before or after an indicator; the process group is stopped;
   hostile bots (silent, flooding, exiting, ignoring SIGTERM) are substituted and
   counted.

The libriichi legality comparison is judged on action flags; furiten and waits are
compared as evidence only, because libriichi updates them at different moments from
ours. What the runs found is in `Docs/Evidence/real-logs.md`
and `Docs/Evidence/closeout.md` (directed play: every rare branch reached hundreds to
thousands of times under both rulesets, through libriichi and Mercury). Mahjong
Soul-only behaviour (double yakuman, triple ron, robbing a closed kan, component
pao, the chained-kan indicator) has external evidence only from the real logs, where
it occurs; component pao on a composite yakuman has none.

## 9. How it was built

| # | Package | Writer | Reviewers |
|---|---|---|---|
| A | Library split, public API, `Rules` threaded through scoring and legality, `TableMeld`, `Wall`, shuffle with test vectors | Opus | Codex, Gemini |
| B | `RoundState`, `legalActions`, windows, events, results; in-process benchmark | Opus | Codex, Gemini |
| C | `GameState`, end conditions, `GameResult` | Opus | Codex, Gemini |
| D | `RiichiMjai`, `PlayerView`, masked events, `selfplay`, `replay`, `check-log`, mjai bot adapter | Opus | Codex, Gemini |
| E | `AGPL/libriichi-check` | Codex | Opus |
| F | Scenario tests | Gemini | Codex |

A came first because it fixed the shared types; B–D followed in order; E and F were
written alongside A, from this document, without reading the engine's source.
Real-log verification, directed play, and final review fixes followed.

Completion gate (passed, `Docs/Evidence/closeout.md`): every scenario test
passes; 50,000 `eager` and 50,000 random self-play games under Tenhou rules with no
unexplained difference from libriichi; the coverage report shows every listed branch
reached; the corpus stays at 12,439 of 12,439; code review completed.

## 10. Still open

1. **Rules no record decides** (`Docs/Evidence/real-logs.md`, `closeout.md`,
   rules.md §5 item 12): pao on a composite yakuman, the winning tile of a heavenly
   hand, kan dora on a rinshan win after an open kan, leftover sticks at the end of
   a game, the riichi kan of a waited tile. Each is the published rule or a `Rules`
   field.
2. **Website and remote bots**, each needing its own design: JSON
   codecs for views, actions and results; a versioned wasm boundary; a seat-scoped
   decision envelope (decision id, trigger, typed options) for bots that are not
   mjai child processes; the scoring interpretation behind a `Scored` (which tile and
   reading a heavenly hand chose); a typed kan-commit event for consumers that do not
   fold.

## 11. Changes from draft 1

All three reviews asked for revisions; the architecture stood.

| Change | Raised by |
|---|---|
| Furiten decided from waits at the close of every window, not from who was asked; riichi furiten after a skipped tsumo | all three |
| Wall keyed on hands dealt, not round number (a repeat would have re-dealt the same wall) | Gemini, Opus |
| `Rules` threaded into scoring and legality; double yakuman no longer hard-coded | Gemini, Codex |
| Tenhou differences corrected from the manual text, and in `rules.md`: no robbing a closed kan, pao covers the whole composite hand, kan dora shown at the discard, temporary furiten until the next own draw, formal tenpai on a fifth copy, dealer repeat ahead of the 30,000 finish | Codex, Opus, Gemini |
| Explicit resolution table; four kans and four riichi abort ahead of calls | all three |
| Kans written as transactions; owed-indicator order for chained kans | Codex, Opus |
| Haitei excludes replacement draws | Gemini, Opus |
| Riichi as two steps, matching mjai; no tsumogiri after a call | Gemini, Opus |
| `TableMeld` with taken tile and source seat; separate drawn-tile slot | all three |
| First go-around: table-wide flag plus per-seat first discard | Gemini, Codex |
| State never rests where nobody can act | Gemini, Opus |
| Game-end transition written out; extension's last hand repeats; tie-break; sticks excluded from the 30,000 test; oka | all three |
| mjai field table, superset for akochan, JSON reader skips nested values, adapter handshake and timeout | all three |
| Engine trace for exact replay; `check-log` for foreign logs with stated limits | Codex |
| libriichi check moved to a new crate on real libriichi, driving its board as well as its player state; written list of known differences; eager bots; coverage gate | all three |
| Speed target deferred to measurement; hot-path choices fixed now | Opus, Gemini, Codex |
| `Player` protocol removed from the library; step API is the API | Opus |
| Determinism: canonical ordering, thread-safe shanten tables | Opus, Codex |

Not taken: asking every seat on every discard (all three agreed with asking only
seats that can act); a second state machine in Mercury (all three agreed libriichi
fills that role).
