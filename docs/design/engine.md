# Phase 3 design: the full engine

Status: **draft 2.** Draft 1 was reviewed by Opus, Codex and Gemini
(`docs/reviews/p3/design-*.md`); section 11 lists what changed and why. Nothing here
is implemented yet.

The engine today answers questions about one hand (`agari`, `shanten`, `waits`,
`score`, `legal` in `spec/formats.md`). Phase 3 adds everything needed to play a whole
game: the wall, turns, calls, riichi, furiten, draws, payments, dealer rotation and
game end. Rules are `spec/rules.md`; where this document and `rules.md` disagree,
`rules.md` wins and this document has a bug.

## 1. Goals and non-goals

Goals:

1. One function, `legalActions`, is the only place that decides what a seat may do.
   Bots, LLM tools, the website and replay validation all use it.
2. Deterministic: the same wall and the same actions give the same game and the same
   bytes of log, on every platform including WebAssembly. No output may depend on
   `Dictionary` or `Set` iteration order, which Swift randomises per process.
3. Hidden information cannot leak by accident. Code that plays a seat is handed a
   type that does not contain other hands or the wall.
4. Speaks mjai, so Mortal, akochan and any other mjai bot can sit at the table.
5. Fast enough for bot arenas. Draft 1 said 500 random-bot hanchan per second per
   core; the reviewers estimate the current code would manage about 20. The number
   is now set after package B is measured in-process, and section 4.4 lists the
   design choices made now so that the target stays reachable.
6. Two rulesets from day one, Mahjong Soul ranked (default) and Tenhou ranked, chosen
   by a `Rules` value that reaches scoring and legality as well as game flow.
   Three-player is out of scope but should not be designed out.

Non-goals for Phase 3: bots beyond random ones, any UI, networking, three-player,
local yaku.

## 2. Package layout

```
Package.swift
Sources/Riichi/        library: tiles, hand analysis (existing code), rules, round, game
Sources/RiichiMjai/    library: mjai event encoding/decoding, depends on Riichi
Sources/mj/            executable: line protocol, `selfplay`, `replay`, bot adapters
Tests/RiichiTests/     swift-testing unit and scenario tests
```

- `Riichi` imports nothing, not even Foundation, and uses no floating point (uma and
  oka stay in integer points). `Int` is 32 bits on wasm32, which is enough for points.
- `RiichiMjai` carries a hand-written JSON reader and writer, also without
  Foundation. The reader must skip any value it does not need, including nested
  objects and arrays of floats: Mortal's replies carry a `meta` object with both.
- The five line-protocol operations keep working unchanged, with Mahjong Soul rules
  as their default, and the corpus runs against `mj` on every change. The `legal`
  operation keeps its own one-seat entry point (it has no round state) and shares
  the underlying checks with `legalActions`; self-play dumps keep the two in step
  (section 8, layer 3).
- `ShantenCalculator` is currently a class with a mutable cache. It becomes safe to
  use from several threads: an immutable table built once (done in package A).

## 3. Core types

Kept: `Kind`, `Tile` (kind + red flag), `Counts`, `Wind`, the scoring types.

```swift
public struct Seat: Hashable, Sendable { public let index: Int }  // 0...3, fixed for the game;
                                                                  // seat 0 is the first dealer
public struct Rules: Sendable { ... }       // one field per row of rules.md §1 that differs or may differ
extension Rules { static let mahjongSoul, tenhou: Rules }

public struct Wall: Sendable {              // 136 tiles in a fixed order
    init?(tiles: [Tile])                    // validated: the exact 136-tile set
    init(seed: UInt64, hand: Int)           // hand = count of hands dealt so far in this game
}
```

**`Rules` reaches hand analysis.** `score`, the yaku tables and `legalActions` take a
`Rules`. Today's code hard-codes Mahjong Soul's four double yakuman and the tenhou
upgrade; those become fields, as do kuitan, the double-wind pair, robbing a closed
kan, the composite pao rule, kan dora timing, formal tenpai on a fifth copy, and the
others listed in 4.2 and 5.

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
different (seed, hand) pairs do not collide by simple arithmetic. `spec/wall.md` is
the authority. The spec will include three known
walls as test vectors. Keying on the count of hands dealt, not the round number,
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
func legalActions(for seat: Seat) -> [Action]            // empty if the seat has nothing to decide;
                                                         // in a canonical, documented order
mutating func apply(_ action: Action, by seat: Seat, events: inout [Event]) throws      // .turn
mutating func resolve(_ answers: Answers, events: inout [Event]) throws                  // .reactions, .robbing
```

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
| 1 | Any `ron` answered | Every ron wins. Under `Rules.tenhou`, three rons are an abortive draw (sanchahou) instead. A riichi declared on this discard is not accepted and pays no stick. |
| 2 | The discard is the fourth identical wind of an uninterrupted first go-around | Abortive draw (four winds). See 4.2 for the stick. |
| 3 | Otherwise a riichi declared on this discard is accepted now | 1,000 points move to the table (`reach_accepted`), before anything below. |
| 4 | This was the discard after a fourth kan and the kans belong to two or more seats | Abortive draw (four kans). Calls answered on this discard are not made. |
| 5 | That acceptance was the fourth riichi | Abortive draw (four riichi). The fourth stick stays on the table. Calls are not made. |
| 6 | A `pon` or `daiminkan` answered | It is made. (At most one seat can hold such a call on one tile.) |
| 7 | A `chi` answered | It is made. |
| 8 | No live tiles left | Exhaustive draw. |
| 9 | Otherwise | Next seat draws. |

For a `robbing` window: any ron wins (the kan is not completed); otherwise the kan
completes.

**Furiten is decided from waits, not from who was asked.** When a window closes
without ending the round, every seat other than the discarder whose current waits
include the tile's kind becomes temporarily furiten (permanently, if in riichi). It
makes no difference whether the seat had a yaku, whether it was asked, or whether it
answered `pass` or a call. The same applies to the tile of an added kan (and of a
closed kan, for a seat that could have robbed it). Separately:

- *Own-discard furiten*: any of the seat's waits is in its own pond, including
  discards that were called away. Recomputed when the hand's waits change.
- *Temporary furiten* ends when the seat next draws from the wall. A call does not
  end it. (Tenhou's manual: until 「次の自分のツモ番」, and 「逆巡副露では解消しない」.
  Mahjong Soul's published rules also name the next own draw.)
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
  not possible in practice (all four copies are in ponds). If the fourth discard was
  a riichi declaration, whether the stick is paid is unverified for both clients;
  `Rules` field, default not paid, which is what libriichi does.
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
  - *An owed indicator* is revealed at the kan seat's next discard, or just before
    its next replacement draw if it kans again first. So for open kan → added kan,
    the order is `kakan`, robbing window, `dora`, `tsumo`; for open kan → closed kan
    it is `dora` (owed), `ankan`, `dora` (new), `tsumo`. A rinshan win right after an
    open or added kan does not see that kan's indicator.
  - *A kan announcement changes nothing* (hand, melds, counts, cached waits) until
    its robbing window has closed.
  - *Ron on the discard after an open or added kan*: under `Rules.tenhou` the owed
    indicator is revealed immediately before the discard (`dora`, then `dahai`), so the ron counts it
    and its ura (manual: 「後めくり（打牌または続く嶺上の直前）」). For Mahjong Soul this
    is unverified (`rules.md` §5 item 4); `Rules` field, default revealed only after
    the window passes.
- **Four kans.** By two or more seats: the fourth kan's replacement draw may win,
  its discard may be ronned, and otherwise the round aborts ahead of any call (row 4)
  [22]. By one seat: play continues, and no fifth kan is legal for anyone [23].
- **Four riichi** [24]: row 5.
- **Last tile.** No kan of any sort with zero live tiles. The discard made with zero
  live tiles can be ronned (houtei) but not called. Haitei applies to a win on a
  normal draw that leaves zero live tiles; a replacement draw is rinshan only, never
  haitei [18], though the discard after it is houtei if no live tiles remain.
- **Kuikae and dead-end calls** [12, 13]: existing `legal` code, now fed from
  `TableMeld`.
- **Pao** [31, 32]: set when the pon or open kan that completes the third dragon set
  or fourth wind set is made, against the seat that fed it. Mahjong Soul: the liable
  seat pays for the liable yakuman only; Tenhou: for the whole composite hand. In
  both, the liable seat pays the honba. Tests cover tsumo, ron from a third party, ron from
  the liable seat itself, and pao inside a double ron. The `score` operation still
  answers the ordinary payment; the round redistributes.
- **Exhaustive draw.** Tenpai for payment: Mahjong Soul as in `formats.md` (a wait
  that exists only as a fifth copy does not count); Tenhou counts a fifth-copy wait
  unless all four are in the concealed hand (`rules.md` §5 item 7). Nagashi mangan:
  all of the seat's discards are terminals or honors and none was called away; it
  replaces tenpai payments, pays every qualifying seat, moves no sticks or honba,
  and does not affect dealer repeat [30].
- **Multi-ron**: each winner's payment is computed separately; sticks and honba go
  only to the winner nearest the discarder in turn order; the dealer repeats if any
  winner is the dealer [21].
- **Event reason for nagashi mangan**: the `ryukyoku` event's reason is `exhaustive`;
  the nagashi seats are listed in the result, and the point changes show the payment.
- **A robbed kan never counts** toward four kans.
- **Declining a self-drawn win outside riichi** and then keeping the wait: whether
  the clients treat that seat as temporarily furiten is unverified (Tenhou's manual:
  「和了放棄…後は同巡フリテン」). `Rules` field; default yes for Tenhou, no for Mahjong
  Soul until checked. A replacement draw does not clear temporary furiten; only a
  live-wall draw does.
- **Nine terminals** is an action on the seat's own first draw and ends the round at
  once.

### 4.3 Result

`RoundResult`: wins (in turn order from the discarder: winner, from, value, yaku,
fu, ura indicators shown), exhaustive draw (tenpai seats, nagashi seats), or
abortive draw (kind). Each carries the four point changes, the sticks left on the
table, and whether the dealer repeats.

### 4.4 Speed

Decided now, so the hot path does not need redesign later:

- Transitions mutate in place; no state snapshots are kept by the engine.
- Each seat's shanten and waits are cached and recomputed only when its concealed
  hand changes.
- "Can this seat ron this tile" is a wait lookup plus a cheap has-a-yaku test. Full
  scoring runs only when someone actually wins.
- The riichi-discard search runs only at shanten ≤ 1.
- `Counts` moves to fixed inline storage.
- Events are appended to a caller-owned buffer; a caller that passes none pays
  nothing for them.

Measured after package B, in process, with and without event and view building.

## 5. Game flow

`GameState` owns: `Rules`, seed, hands dealt so far, round wind and number, honba,
sticks on the table, scores, and the current `RoundState`.

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
     draw) and is first with ≥ 30,000, the game ends. "First" uses the seat-order
     tie-break, so a last dealer level with another seat is not first.
   - If the dealer repeats otherwise, play continues.
   - If the dealer does not repeat: the game ends if anyone has ≥ 30,000, or if the
     next hand would start a wind beyond the extension (South for an East game, West
     for a South game). Otherwise play continues into, or within, the extension.
   - The 30,000 tests use scores after the hand's payments and before leftover
     sticks are awarded (Tenhou: 「供託未収」).
   - One `Rules` field covers the case where a non-dealer passes 30,000 while the
     dealer also repeats without being first: Tenhou continues (dealer repeat takes
     priority); Mahjong Soul is unverified and defaults to the same.
5. At the end: leftover sticks go to first place; ranks break ties by starting seat;
   then return points, oka and uma from `Rules` give the final result (`GameResult`:
   ranks, raw scores, adjusted scores). Adjusted scores are integer points, so
   +27.0 is written 27000.

A nagashi mangan that pushes a tenpai last dealer out of first is handled by the
ordering above (scores are tested after payments); unverified for both clients.

## 6. Events, mjai, and the player's view

`Event` cases correspond to mjai messages. Order and fields follow Mortal's dialect,
and we emit a superset of fields so that akochan, which speaks the original
protocol, also works (Mortal ignores fields it does not know).

| Event | Fields | Notes |
|---|---|---|
| `start_game` | `names`, `id` (per recipient) | No seed. |
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
| `end_kyoku`, `end_game` | (`scores` on `end_game`) | |

Tile names convert at the `RiichiMjai` boundary (`5mr`, `E`, `P`, ...).

**Player view.** `PlayerView` is built from a `RoundState` (plus game-level facts)
and a seat. It contains: the seat's hand, drawn tile and own furiten state;
everyone's melds, ponds and riichi status; scores; round wind, round number, honba,
sticks, dealer; dora indicators; live tiles left; what the seat is reacting to (the
discard or kan, and whose); and the seat's legal actions. It has no wall and no
other hands, and nothing leads from it back to the `RoundState`. Events shown to a
seat are a distinct masked type, so an unmasked event cannot be passed by mistake.

**The API is the step API**: `legalActions`, `apply`, `resolve`, `PlayerView`, masked
events. JavaScript cannot block inside a callback, so nothing in `Riichi` calls out
to a player.

**Drivers and bot adapters** live in the `mj` executable target. A driver asks each
seat that must act, then steps the state. The mjai adapter (child process, JSON
lines):

- sends every event to every bot and reads one reply per event (`none` when it has
  nothing to do), as mjai bots expect;
- performs riichi as mjai does: the bot answers `reach`, is shown the `reach` event,
  and answers its `dahai`;
- treats a bot's `ryukyoku` reply as nine terminals;
- has a timeout from day one, since a hung bot would otherwise hang an arena;
- on a bad reply substitutes the first legal action of: `pass`, tsumogiri, the
  first legal discard; and records which of *malformed*, *illegal*, *timeout* or
  *crashed* it was. Those counts are the benchmark's illegal-move rate.

**From JavaScript**, later: exported functions taking and returning UTF-8 buffers of
JSON, covering mjai events and also `PlayerView` and legal actions (mjai alone
cannot drive a UI).

## 7. Command line

Added to `mj` (the line protocol on stdin stays the default):

- `mj selfplay --seed N --games K [--rules tenhou] [--bots random|eager] [--out DIR]`.
  Writes, per game, the mjai log and an **engine trace**: rules, seed, and every
  decision submitted (including passes and calls that lost), which is what exact
  reproduction needs and an mjai log does not contain. `eager` bots always win when
  they can, declare riichi when legal, call and kan with high probability, and
  sometimes pass a ron; uniform random play rarely reaches tenpai, let alone four
  kans or pao.
  In the unmasked log each `start_kyoku` also carries `wall`: the 136 tiles in the
  layout of section 3, so a checker can rebuild the hand without the trace.
- `mj replay TRACE...`: re-runs traces and requires byte-identical logs.
- `mj check-log [--rules tenhou] FILE...`: for mjai logs from elsewhere. Rebuilds a
  wall per hand from what the log reveals (dealt hands, draws, indicators; unseen
  slots filled with the unused tiles), then requires every logged action to be
  legal and every point change and next-hand header to match. It reports what it
  could not check (passes, losing calls, unseen ura).

## 8. How we will know it is right

1. **Scenario tests.** One per bullet in 4.2, per row in 4.1, per branch in 5, and
   per game-flow case in `rules.md` §4: a fixed wall, a list of actions, expected
   events and point changes. Run under both rulesets where they differ. Written by a
   different model from the engine's author, from this document and `rules.md`.
2. **Differential against libriichi** (Tenhou rules), in a new AGPL crate
   `agpl/libriichi-check` that depends on Mortal's `libriichi` itself, vendored once
   so it builds offline. `agpl/mj-rs` is not grown: it deliberately has no event
   processing.
   - *Board replay*: load our wall, hands and indicators into libriichi's own board,
     drive it with the decisions from our trace, and compare its event log with ours
     event by event, then the result: point changes, sticks, dealer repeat. This
     covers draws, nagashi, pao, multi-ron splits, abort timing and dora order.
   - *Legality*: feed each seat's masked events to libriichi's player state and
     compare its action flags, discard and kan candidates, waits and furiten flag
     with ours for **all four seats after every event**, which also catches a
     decision we failed to offer.
   - *Known differences*, kept as a written list in the crate and filtered by name,
     never silently: libriichi has no triple-ron abort; does not stack tenhou or
     chiihou; its four-riichi abort is logged one draw late; riichi discards and
     red-five call variants are not distinguished in its flags; yaku names and fu
     are not exposed. Game end is not covered, because its `Game` deals its own
     walls.
3. **Mercury cross-check.** The Mercury core stays at hand analysis. Self-play dumps
   every win as a `score` request and every decision as a `legal` request, and the
   Mercury `mj` must agree. Default (Mahjong Soul) rules only.
4. **Invariants and cheap properties**, checked in self-play:
   - tiles conserved by kind and by red flag; `sum(scores) + 1,000 × sticks` constant;
   - every round ends; the seat to act always has a legal action; every action in
     `legalActions` applies without error, and nothing outside it does;
   - after every window that did not end the round, every seat waiting on that tile
     is furiten;
   - folding a seat's masked events rebuilds exactly its `PlayerView`;
   - a trace replays to a byte-identical log; `check-log` accepts our own logs;
   - results do not change when answers are supplied in a different seat order;
   - swapping the three suits throughout a wall, reds included, gives the same game
     with suits swapped.
5. **Coverage report.** Self-play counts how often each rare branch was reached
   (each abort, chankan, rinshan, each pao case, double and triple ron, nagashi,
   riichi kan, four kans by one seat, each end-of-game branch). The gate is on
   branches reached, not only on games played.
6. **Real logs**, when a source is settled (section 10).

Notes from the first full run (`docs/notes/p3-CD.md`): the libriichi legality
comparison is judged on action flags; furiten and waits are compared as evidence
only, because libriichi updates them at different moments from ours. Random and
eager bots never reach four winds, four riichi, triple ron, a robbed closed kan,
pao, nagashi or four kans by one seat, so the coverage gate needs directed play
(seeded walls or scripted bots) for those; until then the scenarios are their only
test. A first pass of `check-log` over 300 real Tenhou and 300 real Mahjong Soul
games (2024) agreed on every point change; the only differences were log
conventions (ura shown for a non-riichi winner in a double ron, and the position of
the `dora` event after an open kan).

Mahjong Soul-only behaviour (double yakuman, triple ron, robbing a closed kan,
component pao) is covered by layers 1, 3 and 4 only. That remains the weakest spot.

## 9. Work packages

| # | Package | Writer | Reviewers |
|---|---|---|---|
| A | Library split, public API, `Rules` threaded through scoring and legality, `TableMeld`, `Wall`, shuffle with test vectors | Opus | Codex, Gemini |
| B | `RoundState`, `legalActions`, windows, events, results; in-process benchmark | Opus | Codex, Gemini |
| C | `GameState`, end conditions, `GameResult` | Opus | Codex, Gemini |
| D | `RiichiMjai`, `PlayerView`, masked events, `selfplay`, `replay`, `check-log`, mjai bot adapter | Opus | Codex, Gemini |
| E | `agpl/libriichi-check` | Codex | Opus |
| F | Scenario tests | Gemini | Codex |

A comes first because it fixes the shared types. B–D follow in order. E and F start
alongside A, from this document, without reading the engine's source.

Gate for leaving Phase 3: every scenario test passes; 50,000 `eager` and 50,000
random self-play games under Tenhou rules with no unexplained difference from
libriichi; the coverage report shows every listed branch reached; the corpus still
at 12,439 of 12,439; council review of the code.

## 10. Still open

1. **Real logs.** Done in the real-log campaign (`docs/notes/p3-reallogs.md`):
   Tenhou houou and Mahjong Soul Throne and Jade records in mjai form, checked
   with `tools/reallogs.py`. Earlier text: Not needed to start. Options, none chosen: Mortal-against-Mortal
   games generated locally once a checkpoint is running (no terms issue; realistic
   play); mjai conversions of Tenhou records that others have published on Hugging
   Face (Tenhou restricts reuse of its records); the owner's own games.
2. **Settled from real logs** (`docs/notes/p3-reallogs.md`, rules.md §5): kan
   dora on a ron of the post-kan discard (counted, both clients), the owed
   indicator at a chained added kan (Mahjong Soul shows it before the robbing
   window), riichi and formal tenpai on a fifth-copy wait whose copies are in a kan
   (allowed, both), temporary furiten ending on the seat's own call (both). What is
   still open is listed in those notes. Earlier text: **Unverified in a Mahjong
   Soul client**, each a `Rules` field with the default stated above: kan dora on a ron of the post-kan discard, and in chained kans;
   the stick on a four-winds riichi discard; dealer repeat against the 30,000 finish
   in the extension; nagashi against a tenpai last dealer; component pao; riichi on
   a fifth-copy wait. Until checked, the claim is "Mahjong Soul rules as published",
   not "matches the client".

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
