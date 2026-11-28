# Phase 3 packages C and D: game flow, mjai, command line — notes

Brief: `Docs/Briefs/p3-CD-game-mjai.md`. Nothing is staged or committed.

## Result

- Corpus: `python3.14 Tools/harness.py ./mj Corpus/*.txt` → **12,439 of 12,439**
  (Mercury `mj` also 12,439 of 12,439).
- Clean release build (`rm -rf .build && swift build -c release`): no warnings.
  `grep '^import' Sources/Riichi` is empty; `Sources/RiichiMjai` imports only `Riichi`.
- `swift test`: **72 tests in 20 suites** (67 in `RiichiTests`, 5 in the new
  `RiichiMjaiTests`), all pass, 7 known issues (scenario disputes below; a disputed
  scenario that starts passing still fails the run).
- Scenarios: **132 run, 125 pass, 7 disputed**; all 22 `endgame_*` scenarios now run
  and pass.
- Differential run (2,000 eager + 2,000 random Tenhou games, 51,086 hands): board
  replay **0 differences**; legality rows: **no action-flag difference** other than
  ones explained below, **0 unexplained**; every differing row is a NOTES.md known
  difference or one of five new, libriichi-side or rule-choice differences (below).
- Mercury cross-check: **1,367,938 requests** (7,387 `score`) from 1,300 Mahjong Soul
  self-play games: Mercury and `./mj` agree on all; the round engine agrees with the
  line protocol on all but 4, each a riichi refused for want of 1,000 points, which
  `legal` deliberately ignores.
- Self-play: about **160 eager or 290 random hanchan per second** on one core, with
  the mjai log built.

## Package B review findings

Codex (`Docs/Reviews/p3/B-codex.md`) and Gemini (`Docs/Reviews/p3/B-agy.md`); each
fix has a test in `Tests/RiichiTests/ReviewBTests.swift` (adapted from the
reviewers' reproductions) unless named otherwise.

1. **Codex blocker: ron after a declined tsumo (Tenhou).** New field
   `Rules.temporaryFuritenOnDeclinedTsumo` (design §4.2: Tenhou on, Mahjong Soul off,
   unverified). `apply` now calls `declineWinningDraw` before any turn action other
   than `tsumo`/`kyuushu`: in accepted riichi a drawn winning kind sets riichi furiten
   (as before, now also on the `riichi` path, which cannot arise); otherwise, under
   the field, a seat whose `tsumo` was legal becomes temporarily furiten. It is
   cleared only by a live-wall draw, so it survives the kan and its replacement draw.
   Test `declinedTsumoThenAnkan` (both presets); the new scenario
   `declined_tsumo_outside_riichi` passes on Mahjong Soul.
2. **Codex: a robbed closed kan stayed in the meld list**, and **Gemini 1: stale
   counts and waits during `.robbing(.closed)`.** Fixed together by making kans real
   transactions: announcing a closed or added kan changes nothing (hand, drawn tile,
   melds, cached waits, counts all as before); the `ankan`/`kakan` event and the
   robbing window happen; then either the commit (tiles leave the hand, the meld is
   made or upgraded, waits recomputed, count, ippatsu, indicator, replacement) or the
   robbery (the robbed tile, and only it, leaves the declarer's tiles as the winning
   tile) or a three-ron abort (nothing moves). Tests `robbedClosedKanIsNotAMeld`,
   `closedKanWindowLeavesHandAndWaitsAsBefore`. The reviewer's repro expected the
   post-kan waits (`4z`) during the window; with nothing committed the waits are the
   unchanged hand's, which is the consistent answer — rebuttal of that one detail.
3. **Gemini 2: sanchahou on a closed kan lost a tile** (kokushiRobsClosedKan with
   tripleRonAborts). With item 2 nothing moves before the three-ron check, so the
   tiles are conserved. Test `sanchahouOnClosedKanConservesTiles`; and a new
   self-play run `SelfPlayTests.mixedRules` plays 3,000 eager rounds over 12 random
   combinations of every Boolean `Rules` field (and the double-wind fu) with the
   invariants on.
4. **Codex: the fourth open kan's owed dora was skipped before the four-kan abort.**
   Mahjong Soul's owed indicator is now revealed as soon as no ron is made, before
   rows 2–9 (riichi acceptance and four winds cannot share a discard with an owed
   indicator, so only the four-kan abort moves). Under Tenhou it is shown before the
   discard (below). Test `fourthOpenKanDoraBeforeAbort` (both presets); the new
   scenario `suukaikan_open_kan_owed_dora` passes on Mahjong Soul.
5. Codex suggestion (eligibility without full scoring): not done; selfplay speed
   below is adequate for now.

## Engine changes found by this work

- **Tenhou owed kan indicator comes before the discard, not after.** The manual
  says 「後めくり（打牌または続く嶺上の直前）」 — flipped *immediately before* the
  discard or the next replacement draw. Package B emitted `dahai, dora`; it now emits
  `dora, dahai`, which is also libriichi's order and the order an mjai bot needs (it
  must know the indicator before it answers the discard). Six scenarios expect the
  old order on their Tenhou run and are known issues: `open_kan_chained_kan_discard_ron`,
  `open_kan_discard_all_pass_dora`, `open_kan_discard_called_dora`,
  `open_kan_discard_riichi_ron_ura`, `open_kan_discard_ron_dora`,
  `suukaikan_open_kan_owed_dora` (each `.tenhou`). Design §4.2's sentence "revealed at
  the discard, before the window" should say "before the discard".
- **State settled before call events.** `chi`/`pon`/`daiminkan` were emitted before
  the caller's counts and waits were updated, so an observer at that event saw stale
  waits (found by the legality dump). The state is now updated first.
- **check-log** had to skip `reach_accepted` and an owed `dora` between a discard
  and the call that answers it (Mahjong Soul), and an owed `dora` before a Tenhou
  discard; found by `--check` on our own logs.

## Scenarios

Re-run against the files as committed for F3 (132 scenarios; the seven package B
disputes are corrected and pass, and the known-issue list no longer holds them).
Known issues now (`ScenarioTests.disputedScenarios`):

1. Six Tenhou runs expect `dahai, dora` for an owed kan indicator; the engine now
   emits `dora, dahai` (see "Engine changes" above): `open_kan_chained_kan_discard_ron`,
   `open_kan_discard_all_pass_dora`, `open_kan_discard_called_dora`,
   `open_kan_discard_riichi_ron_ura`, `open_kan_discard_ron_dora`,
   `suukaikan_open_kan_owed_dora`. Only the event order differs; results agree.
   `RulesFieldScenarioTests.openKanDoraBeforeRonOnMahjongSoul` ignores the event
   list for the same reason.
2. `declined_tsumo_outside_riichi` (Tenhou run, new in F3): after seat 0 declines
   the tsumo and makes its ankan it holds `2344s`, so seat 1's `4s` offers it
   `pon:44s` (a furiten seat still appears for calls, design §4.1). The file's
   `assert_not_asked 0` fails and its window step is missing. The furiten itself is
   right (`assert_furiten 0: true` holds; ron is not offered). The Mahjong Soul run
   passes; its first version expected 70 fu, but the 4s can complete the pair
   (tanki, +2 fu → 80 fu, 3,900), and the reviewers corrected it while I worked.

The other eight new F3 scenarios pass as written.

## What I built

### Package C (`Sources/Riichi/Game.swift`)

- `GamePosition` (round wind, kyoku, honba, sticks, scores; `dealer` is seat
  kyoku − 1), `GameFlow.next(after:at:rules:testScores:)` — design §5 steps 1–4
  exactly, as a pure function so `check-log` can use it — `GameFlow.result` (step 5),
  `GameFlow.ranking`, `GameEnd` (`below_zero`, `dealer_first`, `target`,
  `extension_over`), `GameTransition` (`ordinary`, `allLastRepeat`,
  `allLastAdvance`, `ends`) and `GameResult` (ranks, final scores, sticks awarded,
  adjusted scores).
- `GameState`: rules, seed, hands dealt, position, the current `RoundState`,
  `lastRound` (result and transition) and `result`. `apply`/`resolve` forward to the
  round and, when it ends, run the transition at once and deal the next hand
  (`Wall(seed:hand: handsDealt)`) or emit `end_game`; so it rests only where a seat
  must decide. A second initializer starts from any position with a given wall
  (scenarios). `start_game` and `end_game` are new `Event` cases.
- Decisions: `allLastTestAfterNagashi` off reads the scores before the nagashi
  payments (the round's starting scores less accepted deposits); the
  `dealerRepeatBeforeTarget` field applies to any repeat that does not end the game
  (abortive draws included); the extension's end is "the next hand's wind is beyond
  the extension wind".
- The scenario runner now plays every scenario as the first hand of a `GameState`
  at the scenario's position (`game_length` sets `Rules.length`) and checks
  `game_ended`, `next_*`, `final_scores`, `final_ranks`, `adjusted_scores`.
  `end_game` is compared only where the scenario's event list names it (round
  scenarios with odd scores can end the game without saying so). Assertions after
  the hand is over (`assert_illegal`, `assert_not_asked`) hold vacuously.

### Package D

- `Sources/Riichi/View.swift`: `MaskedEvent` (a distinct type; other hands and draws
  are `nil`, noten hands at `ryukyoku` too), `Event.masked(for:)`, `PlayerView`
  (`Table`: position, scores, indicators, live tiles left, own hand and drawn tile,
  everyone's melds, ponds and riichi status, the open window; plus `furiten` and
  `legalActions`, which only the engine can know) built by `RoundState.view(of:)`,
  and `ViewFolder`, which rebuilds `PlayerView.Table` from one seat's masked events.
- `Sources/RiichiMjai/`: `JSON.swift` (reader that records each top-level value's
  bytes and parses only what is asked for, skipping the rest without building it;
  writer with fixed key order) and `Mjai.swift` (tile names, `encode` of `Event`
  and `MaskedEvent` with the §6 superset of fields, `decode` of any mjai message,
  `action(_:seat:legal:)` for bot replies). No Foundation.
- `Sources/mj/`: `Bots.swift` (random and eager bots that see only a `PlayerView`),
  `Driver.swift` (game loop, log, trace, observers), `Legality.swift` (the rows for
  compare.py), `CrossCheck.swift` (the Mercury dump), `Checks.swift` (invariants and
  the coverage report), `MjaiBot.swift` (adapter), `CheckLog.swift`,
  `Commands.swift`. Package platform raised to macOS 13 (`ContinuousClock`).

Commands:

- `mj selfplay --seed N --games K [--rules tenhou] [--bots random|eager|mjai:CMD]
  [--seat S=BOT] [--out DIR] [--legal] [--requests FILE] [--check] [--timeout MS]
  [--quiet]`. Game g uses seed N+g. Writes `DIR/%06d.jsonl` (unmasked mjai log:
  `start_game.names`, `wall` on each `start_kyoku`, and on `end_kyoku` the
  libriichi-check fields `scores`, `deltas`, `kyotaku_left`, `dealer_repeats`) and
  `DIR/%06d.trace` (`mj-trace 1`, rules, seed, bots, then `seat action` per
  decision, passes and losing calls included). Prints games/s, substitution counts
  and the coverage report. `--check` adds the invariants below.
- `--legal` writes `DIR/%06d.legality`: the rows compare.py expects, for every event
  from `start_kyoku` to `end_kyoku` and all four seats, `file` being the log's path
  as written (so give the checker the same path strings). Extra fields `x_furiten`
  (which furiten: own discard, temporary, riichi) and `x_hand` are diagnostics that
  compare.py ignores.
- `--requests FILE` (Mahjong Soul): every decision as a `legal` request and every
  win as a `score` request, with `FILE.expected` (the round engine's answer) and
  `FILE.lowpoints` (requests where the seat has under 1,000 points).
- `mj replay TRACE...`: replays and requires the `.jsonl` beside each trace to be
  byte-identical.
- `mj check-log [--rules tenhou] FILE...`: see design §7. Reports `not checked`
  counts (`passes`, `unseen_ura`).

### Invariants (design §8 layer 4) and how they are checked

- Folding each seat's masked events rebuilds its `PlayerView.Table` at every rest
  point: `selfplay --check` (every step, all seats) and `GameTests.viewsFoldFromMaskedEvents`.
- Byte-identical replay and `check-log` accepting our own logs: `selfplay --check`
  replays every game's trace in process and runs check-log on its log;
  `CommandTests.selfplayReplayCheckLog` also runs `mj replay` and `mj check-log` on
  the files and shows a tampered log is refused.
- Answer-order independence: `selfplay --check` resolves a copy of every window with
  the answers set in descending seat order and requires the same events and state
  (`Answers` is four fixed slots, so this holds by construction).
- Points conserved at every step; tiles conserved (B's round checks, now including
  pending kans and the mixed-Rules run).

### The mjai adapter

Child process via `/bin/sh -c CMD`, JSON lines, one reply per event (`none`
expected when there is nothing to do; other replies to such events are ignored).
Two-step riichi as in mjai. `hora` is tsumo or ron by phase, `ryukyoku` is nine
terminals. A reply naming an equal tile with the wrong tsumogiri flag is taken as
the legal one. Bad reply → first legal of `pass`, tsumogiri, first discard; counted
as malformed (not JSON / no type), illegal (not in `legalActions`), timeout (no line
within `--timeout`, default 10 s) or crashed (pipe closed / exited). A bot that times
out is killed and every later decision of that game is substituted under the same
reason. Test: `CommandTests.mjaiAdapter` with `Tests/Fixtures/fakebot.py`, scripted
to misbehave once each way on four seats, and, at four well-behaved seats, to make a
riichi in two steps.

## Mercury cross-check (design §8 layer 3)

`mj selfplay --seed 1000 --games 1000 --bots eager --requests rq1.txt` and
`--seed 5000 --games 300 --bots random`, then `./mj < rq.txt` and
`Sources/Mercury/mj < rq.txt`: 1,367,938 lines (1,360,551 `legal`, 7,387
`score`). **Mercury and `./mj`: identical on every line.** `./mj` against the round
engine's own answer (`rq.txt.expected`): 4 lines differ, all `riichi:` entries
offered by `legal` to a seat on under 1,000 points (all four ids are in
`rq1.txt.lowpoints`). The riichi discard turn is not asked (the line protocol folds
it into `riichi:<tile>`, which the dump fills by applying `riichi` to a copy).

## Differential run against libriichi (step 5)

Commands: `Tools/libriichi_diff.sh WORK eager 1000000 40 50`, then
`... random 2000000 40 50`, then `python3.14 Tools/libriichi_diff_summary.py WORK`.
Each 50-game batch runs `mj selfplay --rules tenhou --legal`, the checker's `check`
(already built), `compare.py`, and `Tools/classify_libriichi.py`, which puts every
differing row (not only the first per hand, which is all compare.py reports) in a
category; the rows (≈3 MB per game per side) are then deleted. The checker was not
modified.

**Board replay** (`libriichi-check check`): 27,124 eager and 23,962 random hands,
**0 differences** (only `deal_tile_order` filtered, 51,086). No three-ron, four-riichi
or four-winds hand arose, so those known board differences were not exercised.

**compare.py** (its own filters): eager 25,748 of 27,124 hands report a difference,
random 2,639 of 23,962; rows 14,315,016 and 14,959,872; filtered
`candidate_tile_order` 362,418 / 379,132 and `visible_exhausted_waits` 612,754 /
17,701. Every reported difference is one of the rows below.

**All differing rows by category**, rows (hands), eager / random:

| Category | Eager | Random | Kind |
|---|---:|---:|---|
| `visible_exhausted_waits` | 612,669 (15,220) | 17,701 (1,340) | NOTES |
| `furiten_on_window_event` | 44,819 (19,288) | 640 (421) | NOTES |
| `cached_waits` | 36,238 (16,372) | 290 (236) | NOTES |
| `temporary_furiten_reset` | 23,772 (8,712) | 322 (257) | NOTES |
| `kakan_eager_commit` | 1,628 (1,252) | 636 (623) | NOTES |
| `idle_target_actor` | 0 | 0 | NOTES |
| new: `announcement_shanten` | 9,862 (5,320) | 1,593 (1,521) | libriichi |
| new: `ankan_eager_commit` | 563 (508) | 183 (182) | libriichi |
| new: `four_concealed_shanten` | 381 (59) | 39 (8) | definition |
| new: `riichi_fifth_copy_wait` | 1 (1) | 0 | rule choice |
| new: `declined_tsumo_furiten` | 0 | 7 (1) | rule choice |
| unexplained | **0** | **0** | |

Action flags agree on every row except: `can_ron_agari` where our temporary furiten
survives a call and libriichi's is cleared at the following discard (counted under
`temporary_furiten_reset`; Tenhou's manual 「逆巡副露では解消しない」 is with us), and
the one riichi discard list below. How the classifier decides (all from the two rows,
the log, and the engine's `x_furiten`/`x_hand`): a furiten row libriichi sets on a
window event, or on the event after one, where our furiten is decided at the close
→ `furiten_on_window_event`; ours cleared by our own draw but libriichi's kept to
the next discard, or ours kept through a call and libriichi's cleared at the
discard → `temporary_furiten_reset`; waits and furiten of the caller at its own
`chi`/`pon` (we hold 14 − 3k tiles and have no waits; libriichi keeps the old ones)
→ `cached_waits`; the declarer's row at its own `kakan` → `kakan_eager_commit`.

Engine bugs fixed during the run: the stale caller waits at call events (above). The
checker found nothing in the engine's legality; the earlier B-review fixes and the
Tenhou dora order were made before the run.

New differences (not in NOTES.md; checker not patched), each with a minimal log:

1. **`announcement_shanten`**: a seat holding a drawn tile at a `hora`, `ryukyoku`,
   `end_kyoku` or (Tenhou, before a discard) `dora` event: libriichi's shanten is one
   more than at the `tsumo` row just before, with the same tiles. Ours stays the
   shanten of the 14 − 3k tiles held. Minimal log: any tsumo win, e.g. eager seed
   100 game 0 hand 3 (`mj selfplay --seed 100 --games 1 --rules tenhou --legal`):
   event 160 `tsumo` seat 1 draws `P` (both: shanten −1, `can_tsumo_agari`), event
   161 `hora` seat 1 (libriichi 0, engine −1). Libriichi-side snapshot artefact.
2. **`ankan_eager_commit`**: as NOTES' `kakan_eager_commit`, for a closed kan:
   libriichi applies the kan at the `ankan` event; our declarer row at `ankan` is the
   state before the commit (nothing changes until the robbing window closes; under
   Tenhou no window opens and the commit follows in the same step). E.g. random seed
   2000000 batch: every own-`ankan` row where the kan changes the shanten or waits.
3. **`four_concealed_shanten`**: a hand holding four of a kind concealed, e.g.
   `234m CCCC` with two melds (eager seed 1000000, game 30, hand 7, seat 2, events
   90–97). Our shanten is 0, waiting on `C` (structural, a fifth copy:
   Spec/formats.md, "`234567789m1111z` is tenpai, std=0"); libriichi says 1. A
   definitional difference; furiten and riichi do not depend on it here.
4. **`riichi_fifth_copy_wait`**: eager seed 1000150, game 22, hand 3, seat 3, event
   49 `reach`: seat 3 holds an ankan of `5mr 5m 5m 5m` and `468m 678p 234s 88s`;
   libriichi lists `4m` and `8m` as riichi discards, we list `4m` only, because
   discarding `8m` leaves a kanchan on `5m`, a fifth copy, which
   `Rules.riichiOnFifthCopyWait` (rules.md §5 item 7, unverified, default off)
   refuses. Rule choice; Tenhou's actual behaviour is still to be checked.
5. **`declined_tsumo_furiten`**: a random-bot seat that could tsumo and discarded
   instead; we make it temporarily furiten until its next draw
   (`Rules.temporaryFuritenOnDeclinedTsumo`, Tenhou manual 「和了放棄…後は同巡フリテン」);
   libriichi does not. 7 rows in one hand: `mj selfplay --seed 2001553 --games 1
   --rules tenhou --bots random --legal`, hand 4: seat 1 declines a tsumo and
   discards out of tenpai (`1233m6689p44s` after, shanten 1); from event 132 to its
   next draw we say furiten (temporary), libriichi says not.

## The legality row format: what it cannot express

- Our two riichi steps: after `reach` the rows show only `can_discard` and the
  candidates; fine. But tsumogiri and from-hand discards of equal tiles, and the red
  and plain variants of a call, are projected to one entry (README says so).
- A row is a per-event snapshot, but the engine only rests after the last event of
  a step; earlier events of a step have no decisions (correct) and their status
  fields are the engine's state as the event is emitted (via a new `observe` hook on
  `apply`/`resolve`). Furiten in our design is decided when a window closes, which
  is between events, so the `dahai` row before a window closes cannot show it: that
  is exactly `furiten_on_window_event`, by construction.
- The engine's furiten is three parts; the row has one Boolean. `x_furiten` carries
  the parts for classification.
- During a robbing window our declarer's state is the pre-kan state (nothing
  committed); libriichi's is post-kan. The format has no way to say "pending".

## Coverage (design §8 layer 5)

`mj selfplay` prints the report; `Coverage.required` is the list design §8 layer 5
names. 5,000 eager Tenhou games (67,246 hands): abort_kyuushu 372, abort_suukaikan
61, chankan 270, rinshan 273, haitei 673, houtei 1,126, ron_x2 119, riichi_ankan
200, pao_third_party_ron 1, yakuman 82, end_below_zero 557, end_dealer_first 850,
end_target 3,568, end_extension_over 25, all_last_repeat 2,493, all_last_advance 689.
**Not reached** by any bot (also not in 5,000 Mahjong Soul eager games or 2,000
random): four winds, four riichi, sanchahou / triple ron, robbing a closed kan, pao
on tsumo and on a ron from the liable seat, nagashi, four kans by one seat. The
gate on branches cannot be met by these two bots: it needs directed bots (a nagashi
seat, a wind-first discarder, a kokushi chaser) or seeded walls. Scenarios cover
every one of them.

## Speed

`./mj selfplay --seed 0 --games 2000 [--rules R] [--bots B] --quiet` (release, one
core, Apple Silicon, log and trace built in memory, no `--out`):

| Bots | Mahjong Soul | Tenhou |
|---|---:|---:|
| eager | 164 games/s | 163 games/s |
| random | 288 games/s | 296 games/s |

`--legal` (per-event snapshots of all four seats) drops eager to about 20 games/s;
`--check` (every legal action applied, view folds, replay, check-log) to about 2.
`mj bench-round` is unchanged at ≈14,300 rounds/s.

## What I now think is wrong or open in the design

1. **§4.2, Tenhou owed indicator**: "revealed at the discard, before the window"
   should be "immediately before the discard" (the manual's 直前). Six scenarios
   follow the old reading.
2. **§4.2, kans as transactions** should say that the announcement changes nothing
   — no tile leaves the hand, no meld, no cache — until the window closes; package B
   took the tiles out at the announcement, which both reviewers tripped over.
3. **§8 layer 2, legality "after every event"**: an event-level snapshot cannot
   match libriichi's furiten timing, because our furiten is decided when a window
   closes, between events. The checker treats that as a known difference, which is
   right, but most compare.py "failed hands" are this. The design should say the
   legality comparison is of action flags, with status fields compared only as
   evidence.
4. **§8 layer 5, coverage gate**: unreachable with random and eager bots (list above).
   Directed bots or seeded walls are needed before the Phase 3 exit gate.
5. **§7 eager bots** never decline a tsumo, so `temporaryFuritenOnDeclinedTsumo` is
   exercised against libriichi only by random bots (one hand in 2,000 games).
6. **§6 `PlayerView` fold**: furiten and legal actions are not in the masked events,
   so the fold rebuilds `PlayerView.Table`, not the whole view; the design's
   invariant should say so (a full fold would need a second rules engine).
7. **§6 `hora` fields**: the design names `fu` and `fan` but not their values for a
   yakuman; I wrote `fan = 13 × multiple`, `fu = 0`. Akochan's expectation is
   unverified.
8. **§7 trace**: the design says the trace has "every decision submitted"; the
   adapter's substituted decisions are what is recorded (the bot's bad reply is
   not), which is what replay needs; the bot's raw replies would need a separate log.
9. **Mahjong Soul `dora` and `reach_accepted` between a discard and the call that
   answers it**: correct by §4.1, but a log reader must look past them to find the
   call (check-log does); worth a sentence in §6.
