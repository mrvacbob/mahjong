# Phase 3 final fixes — notes

Brief: `docs/briefs/p3-final-fixes.md`. Reviews: `docs/reviews/p3/final-codex.md` and
`docs/reviews/p3/final-agy.md`. Nothing is staged or committed. Run outputs are
outside the repository (`/Volumes/Psyche/mahjong/work/finalfix/`); no game data, game
ids or player names are in the repository. No Foundation in `Riichi` or
`RiichiMjai`; `agpl/` and the `.scn` files are untouched.

Every fix has a test that fails without it. Besides writing the tests, each fix was
undone one at a time (a scratch script that reverts the fix, rebuilds and runs the
named test) and the test was seen to fail: 18 of 18 reversions caught, after one
reversion that undid the fix in the wrong direction was corrected.

## 1. Findings and outcomes

### Codex

| # | Finding | Outcome | Test |
|---|---|---|---|
| 1 | Blocker: the mjai adapter turns a legal ron during a chained kan into a pass | **Fixed at the cause.** A decision is bound to the event that asks for it. `PlayerView.prompt(in:)` (Riichi) names that event among a step's events: the seat's draw, chi, pon or riichi declaration on its turn; the discard; the `ankan`/`kakan` of a robbing window. Only indicators may follow it. The `Player` protocol now gets events one at a time, with the view attached to the prompt event (`receive(_:prompt:)`), and is then asked for the decision (`decision(_:)`). The driver throws if a decision has no prompt, which would be an engine bug. `MjaiBot` takes the reply to the prompt as the decision and checks it against the whole decision (`Mjai.action(_:for:)`, finding 5). A reply other than `none` to a later notification is counted as illegal and substituted. A reply other than `none` to an event that asks nothing is counted as the new `unbound`. A decision with no reply bound to it is substituted and counted, never taken as a pass. The exchange is specified in design §6: the decision is the reply to the prompt, and notifications must be answered `none`. | `mjTests.ArenaTests`: a whole game through `playGame` with an mjai child process (`Tests/Fixtures/robbot.py`) on the review's wall, under both presets and both reply orders. Checks the actual win (`hora` 3←0 on 1p), the event order (`kakan, dora, hora` / `kakan, hora`) and the tally (0; 1 illegal; 1 unbound). |
| 2 | Advancing from the largest admitted honba traps | **Fixed.** Admission bounds (honba and sticks 0–1,000, scores ±100M) now apply only to positions given from outside (`RoundState.init`, `GameState.init`), and these throw `InputError` instead of trapping. The engine's own path to the next hand checks only structure. A running game's honba may rise to `RoundState.maxRunningHonba` = 1,000,000, where the game ends (`GameEnd.counterLimit`) instead of overflowing `300 × honba` on 32-bit. Sticks and scores need no running bound because points are conserved. `GamePosition` is checked on construction (fields `internal(set)`). | `InputCheckTests.gameAdvancesFromTheLargestAdmittedHonba` (the probe: kyuushu at honba 1,000 now continues at 1,001; `counter_limit` at the running bound); `positionsAndRulesOutOfRangeAreErrors`. |
| 3 | The public scorer traps on `honba: Int.max` | **Fixed.** `score` checks its request first: rules, hand size 13 − 3 × melds (at most four melds), a possible tile set (hand, win, melds and indicators: at most four of a kind, one red per suit), and honba 0–1,000,000. New `ScoreError` cases cover these. The engine uses an internal path that skips the checks. `LegalRequest.actions` now throws `InputError` for the same kinds of input. The indicator count is not limited: the corpus has a request with eight. | `InputCheckTests.scoreRequestsAreChecked`, `legalRequestsAreChecked`. |
| 4 | The folded table keeps pre-award scores and sticks at the end of the game | **Fixed.** `ViewFolder` folds `end_game`: final scores, no sticks. `GameState.view(of:)` (new) shows the same terminal state, and the fold checks now include the ended state (mj `--check`, `GameTests`, every scenario). | `EastGameTests.terminalViewHasTheFinalScores` (the probe's East game with two sticks carried in). |
| 5 | Contradictory mjai win replies counted as successful | **Fixed.** `Mjai.action(_:for: Mjai.Decision)` replaces the old mapping for bot replies. The message type must fit the trigger, `actor` must be the seat, and a `hora`'s `target` and `pai` must be the discarder or kan seat and its tile (on a tsumo, the seat and its drawn tile). A kan's `consumed` must be the very tiles it uses, and the action must be legal. Fields mjai allows a bot to omit may still be omitted. The lenient mapping stays for reading logs, renamed `loggedAction`: check-log compares every win with the engine's own. | `MjaiTests.winRepliesMatchTheOffer` (the probe), `replies`, `HardeningTests.kanTilesAreTheHand`. |
| 6 | A long `--timeout` traps converting to `Int32` | **Fixed.** `mj selfplay` accepts 1 ms to one hour and refuses anything else before starting a bot. The reader caps each `poll` at 60 s and polls again until the deadline, and its arithmetic cannot overflow for any `Int`. | `mjTests.ChildProcessTests.longTimeoutsDoNotTrap` (the probe), `CommandTests.timeoutIsChecked`. |
| 7 | Suggestion: a typed kan commitment for event consumers | **Deferred to Phase 5**, with reasons. Consumers fold with `ViewFolder`, which is tested at every step under both kan orders, and the brief rules out new protocol beyond the blocker. Listed in design §10 with the JSON/wasm work. |  |
| 8 | Suggestion: scoring interpretation, contingent honba, settlement | **Partly fixed, rest deferred.** `winRequest(for:answers:)` now takes the window's answers: honba go to the nearest actual winner (all winners under `honbaToEveryRonWinner`), and without answers the seat is assumed to be the only winner. It is documented as a host-side tool whose request holds the ura indicators. Settlement is already explicit: `Win.deltas` are the transfers actually made, with `liable`. Exposing the reading a heavenly hand chose is for Phase 5 (design §10). | `WinRequestTests.honbaFollowTheAnswers`. |

Codex's test-strength section:

- **Fold skips the ended state; tautological legal-actions check.** Fixed: the ended state is folded, and the check that compared two calls of the same function now applies every offered action to a copy (mj `--check`). `GameTests` asserts that each decision's prompt is found.
- **Adapter tests do not tie replies to decisions; no tests for contradictory win metadata or out-of-range timeouts.** Covered by `ArenaTests`, `winRepliesMatchTheOffer` and `timeoutIsChecked`.
- **`mixedRules` does not vary `owedDoraAtChainedAddedKan`, the game-flow switches or the length.** All are varied now, and four whole games per combination are played through `GameState`.
- **Exact payments under controlled flags.** Composite pao by `paoCoversWholeHand`, on a third-party ron and on a tsumo, is checked to the point (`PaoTransactionTests`, the review's values; hand check: component ron 24,000 + 600 honba from the liable seat and 24,000 + 48,000 from the discarder). Nearest versus every winner's honba with a third-party discarder is `RulesFieldScenarioTests.honbaToEveryRonWinner` (exact deltas).
- **A whole East game in the suite.** `EastGameTests.wholeEastGames` (both presets, both bots, 40 games each), and `mj selfplay --length east` (new) with replay and check-log (`CommandTests.eastOnlySelfplay`). The trace records the length on a new optional `length east` line.
- **Boundary transitions.** Covered in `InputCheckTests`.
- **mjai round trip.** It now requires `daiminkan`, a riichi win with ura and a draw with tenpai and noten hands. It compares the winning hand, yaku (`yakus` is now decoded), fu and han, plus `tenpais` and `tehais`, and each seat's masking. `replyRoundTripsEveryOffer` writes every legal action of 40 games as a bot reply (over 10,000) and reads it back as that action.
- **Scenario runner.** The runner now checks, for every scenario, both sides of the ledger, the final award of leftover sticks and each seat's fold against its view where the game rests. The known-issue list is empty, and its mechanism is narrowed: each disputed entry names the one problem it excuses, and any other problem fails the run.

Documentation and preset audit: every row fixed (section 4).

### Gemini

| # | Finding | Outcome | Test |
|---|---|---|---|
| 1 | Traps from `parseTiles` (`⑽m`) and `Counts` (16 copies) through the line protocol | **Fixed.** Only ASCII digits are digits. The line protocol counts tiles (`isPossibleTileSet`, new) before any `Counts` is built and refuses more than four melds. A fuzz run of 50,000 hostile requests (non-ASCII digits, 16 of a kind, too many melds, honba beyond `Int`, wrong sizes) produced no crash; the old binary crashed at once. | `InputCheckTests.tileTextIsAscii`; `LineProtocolTests.hostileRequestsAreAnswered` (both reproductions and 3,000 generated requests, every one answered). |
| 2 | `winRequest(for:)` honba wrong on multi-ron | **Fixed** (Codex 8 above). The Mercury dump now makes each ron's request in `resolving`, with the real answers. | `WinRequestTests` (the reproduction: seat 2 alone is paid 2 honba, and the request scores the 2,600 settled). |
| 3 | `Mjai.action` accepts bogus `hora` fields and impossible red fives | **Fixed** (Codex 5 above). The robbing windows are covered too, since the decision comes from the view, not only from a discard. | `winRepliesMatchTheOffer`, `kanTilesAreTheHand` (four or three red fives refused; `kakan` `consumed` must be the pon). |
| 4 | Grandchild bot processes survive; no `deinit` | **Fixed.** `ChildProcess` spawns with `posix_spawn` into a process group of its own, with default SIGPIPE and no blocked signals. `stop()` closes the pipes, sends SIGTERM to the group, waits half a second for the shell without reaping it, sends SIGKILL to the group and then reaps. `deinit` stops the child. | `ChildProcessTests.stopKillsTheProcessGroup` (the reproduction's shape: a grandchild ignoring SIGTERM behind a shell that does not exec it), `droppingTheProcessStopsIt`. |
| 5 | `Mjai.reply` omits `target`/`pai` | **Fixed.** It writes every field mjai has for each action. | `replyRoundTripsEveryOffer` (exact strings for the two reproductions, then every offer of 40 games). |
| 6 | Stale known issue; no-op `openKanDoraBeforeRon` test | **Fixed.** `disputedScenarios` is empty. The no-op test is replaced by `openKanDoraAfterTheWindow`: the field off under both presets gives 2 han 2,000 and no `dora` before the `hora`, and the unpatched expectation is checked to fail with the field off. | `RulesFieldScenarioTests.openKanDoraAfterTheWindow`. |
| 7 | Documentation drift | **Fixed** (section 4). `Rules.init` now takes `owedDoraAtChainedAddedKan` as a required argument, so copying the presets' arguments yields the presets. | `InputCheckTests` (the memberwise copy equals `.mahjongSoul`), `RulesSpecTests.specTableMatchesPresets`. |
| 8 | Silent pass for unlisted seats; `mixedRules`; `replayIsExact`; East games; `allLastTestAfterNagashi == false` | **Fixed.** A seat asked in a window but not listed in the scenario fails it (section 3). `replayIsExact` replays the recorded decisions with no bot. `allLastTestBeforeNagashi`: the field off makes tenpai-yame end the South 4 game the scenario continues. | `ScenarioTests.unlistedAskedSeatFails`, `SelfPlayTests.replayIsExact`, `mixedRules`, `EastGameTests`, `RulesFieldScenarioTests.allLastTestBeforeNagashi`. |
| 9 | `canRon`/`canTsumo` run the full scorer; copy-on-write on `events` in `GameState` | **CoW fixed**: the caller's buffer is released to the emitter, as in `RoundState`. Behaviour is unchanged; `bench-round` stays at about 14,300 rounds/s. **Full scorer rebutted**: only a seat whose cached waits hold the tile is scored. The scorer is what decides yaku (readings, situational flags), so a cheaper test would be a second yaku engine to keep in step. Profiling has not called for one. Design §4.4 now says what is built. | (performance only; no behaviour to test) |

Gemini's API recommendations are handled in section 2. JSON codecs, the wasm boundary and `Rules` JSON are deferred to Phase 5 as the brief directs. The point about traps at public boundaries is covered by brief item 1 and design §2.1.

### Other entry points checked under the brief's trap item

- `Rules`: assigning a three-entry `uma` no longer traps. The `didSet` and initializer preconditions are removed. `Rules.validate()` reports each bad field, and every entry point that takes a `Rules` calls it.
- `GameFlow.result` and `GameFlow.ranking` throw for bad input. `GameFlow.next` throws for test scores of the wrong length.
- `Meld.kuikaeForbidden(took:)` no longer traps on a kind outside the meld; it returns an empty set.
- check-log builds positions through the checked initializers.
- Failable `Seat(checked:)` and `Kind(checked:)` exist for callers outside the library.

Left as preconditions, on purpose: typed index accessors (`Seat(_:)`, `Kind(_:)`, `Wall`'s accessors, `Counts` subscripts), which every decoder in the library reaches only with checked values, like `Array`'s subscript. Also `ViewFolder.apply`, which folds the engine's own masked events; no decoder produces `MaskedEvent`. Both are stated in design §2.1. A Phase 5 wasm boundary that takes indices or events from JavaScript must check them there.

## 2. API added for Phase 4

All of it is pure and Foundation-free, needs no `RoundState`, and is tested in `AnalysisTests` against the engine's own state at every decision of 12 games, plus built tables:

- `GameState.view(of:)`, which shows the final scores at the end of a game.
- On `PlayerView.Table`: `seatWind`, `wind(of:)`, `isClosed`, `isClosed(_:)`, `isRiichi(_:)`, `riichiStatus`, `concealed` (hand with the drawn tile), `visibleCounts` (own concealed tiles, every meld, ponds without called discards, indicators) and `unseen(_:)`. The test checks that visible and unseen copies add up to four for every kind against the engine's hidden tiles.
- On `PlayerView`: `waits` (structural, equal to `RoundState.waits(of:)`), `furitenParts` (`FuritenParts`, also returned by `RoundState.furitenParts(of:)`), and `prompt(in:)`.
- `PondTile.order`: each discard's place in the round. Needed for "after the riichi" and "since its last discard".
- Per-discard analysis: `PlayerView.discardOptions()`, and the pure `discardAnalysis(concealed:meldCount:visible:candidates:)`. For each legal discard it returns the shanten left, each improving kind with the copies this seat cannot see, and the total (ukeire). It throws `InputError` for impossible input.
- `ScoreRequest(hand:tableMelds:win:context:dora:ura:honba:)`.
- Defence:
  - `genbutsu(against:)`: certain. Covers own discards, discards after the seat's riichi, and discards since its own last one (not during its own kan's window), excluding an open window's discard. The engine check confirms the seat cannot ron each kind returned. Leaving the open discard out was a bug the test found.
  - `suji(against:)`: a heuristic. A kind qualifies when every two-sided wait on it is furiten.
  - `allCopiesSeen`: documented as ruling out tanki and shanpon waits only.
- Also: `InputError`, `isPossibleTileSet`, `Rules.validate()`, `GameEnd.counterLimit`, `RoundState.maxRunningHonba`, `GamePosition.maxSticks` and `GamePosition.maxScore`, `Mjai.Decision`, `Mjai.action(_:for:)`, `Mjai.loggedAction`, `YakuText` and `MjaiMessage.yakus`.

Not built, as the brief says: JSON codecs for views, the versioned wasm boundary, and a new decision envelope beyond the prompt binding.

## 3. Scenarios under the stricter runner

All **138 scenarios pass** under both of their rulesets with the stricter runner. A seat asked in a window must be listed, unless the step is `auto_tsumogiri`, whose definition in `scenarios/FORMAT.md` passes for every asked seat. The runner also checks the ledger and the folds of section 1. None fails, so there is nothing to report against a `.scn`.

To show the strict rule actually bites, `unlistedAskedSeatFails` drops seat 1's chi from `call_priority_daiminkan_over_chi` and gets exactly one problem, "seat 1 is asked but not listed". Undoing the rule (back to the silent pass) makes that test fail. The suite has no known issue: the close-out's dispute was settled by the scenario writers' correction of `declined_tsumo_outside_riichi`.

## 4. Documentation

**`docs/design/engine.md`** now describes what was built. Stale passages were rewritten, not appended to:

- the status line;
- goals 1 and 5;
- §2: the line protocol's own legality and its weaker request; a new §2.1 on input checking and the running bounds;
- §3: `Rules` fields, `spec/rules.md` §1.1;
- §4: throwing signatures;
- §4.1: triple ron on a robbing window, `tripleRonAborts`, temporary furiten ending on the seat's own call, the owed indicator before rows 2–9;
- §4.2: four-winds stick paid; owed indicator before the discard on both clients; the chained added kan per ruleset; the kan-announcement invariant with its exception; fifth-copy riichi and draw tenpai on both;
- §4.3: what `Win` carries;
- §4.4: cached waits and when shanten and the full scorer run, with measured speed;
- §5: `GamePosition`, the target from `Rules`, `dealerRepeatBeforeTarget` and `allLastTestAfterNagashi` settled, `counterLimit`, leftover sticks;
- §6: `start_game` and `end_kyoku` fields; `PlayerView` as a table plus engine-decided parts; the window shown only to a seat asked in it; what the folder rebuilds; a new §6.1 on the analysis API; the adapter's prompt binding, process group, timeout range and substitution categories (transport failure, malformed or illegal reply, unbound);
- §7: every flag of `selfplay`, `check-log` and `bench-round`; trace version 1 records a preset and its length; the checker validates provided and inferable fields under named conventions, the reduced format and the East fallback;
- §8: the actual scope of each oracle (libriichi: Tenhou round flow, legality and payments; Mercury: hand analysis and line-protocol legality only; invariants are self-consistency, not external evidence; real logs are the external evidence for Mahjong Soul) and the adapter tests;
- §9 recast as how it was built;
- §10: what is open (rules no record decides; Phase 5 items).

Draft 1's change table (§11) is kept as history.

**`spec/rules.md` and `Rules.swift`, field by field.** A new **§1.1** lists every `Rules` field with the §1 row it implements and both presets' values. `RulesSpecTests.specTableMatchesPresets` parses that table and compares it with the presets by reflection. It requires every field to be listed exactly once and every named row to exist. All 22 fields agree.

Rows changed in `spec/rules.md`:

- §1, edited: `target_points` (the dealer-repeat exception), `extension_max_round` ("ends unconditionally" now reads as the deal passing beyond, or an earlier end condition), `sudden_death_target` (repeat priority), `honba_value_ron` (pao split exception), `abort_suufon_renda` (the stick), `kan_dora_ankan_timing` (on commit; the Mahjong Soul robbery exception), `kan_dora_daiminkan_timing` and `kan_dora_shouminkan_timing` (dropped "Mahjong Soul behaviour on that ron stays unverified"), `chankan_ankan_kokushi` (Mahjong Soul qualifier), `pao_composite_yakuman` (component-only labelled Mahjong Soul, not decided by records), `furiten_temporary` (rewritten without the contradictory older text).
- §1, added: `tenhou_any_winning_tile`, `kan_dora_chained_kakan`, `suufon_renda_riichi_stick`, `tenpai_fifth_copy_at_draw`, `furiten_declined_tsumo`, `dealer_repeat_before_target`, `all_last_test_after_nagashi`.
- §1.1: new.
- §4: item 16 (Mahjong Soul only), item 17 (indicator just before the discard, both clients), item 28 (ends on own draw or own call), item 31 (Mahjong Soul; Tenhou whole hand).
- §5: item 8 ("is unverified" now reads "was unverified", since it is settled).

`Rules.swift`: the header; doc comments of `uma`, `dealerRepeatBeforeTarget`, `allLastTestAfterNagashi` and `honbaToEveryRonWinner`, no longer called unverified; `owedDoraAtChainedAddedKan` in the initializer; `validate()`. README mentions `--length east`.

## 5. Re-verification

With the final binary (copied to the work directory before the runs):

| Check | Result |
|---|---|
| Corpus | **12,439 of 12,439** (`./mj`); Mercury `mj` 12,439 of 12,439 |
| `swift test` | **green, no known issues**: RiichiTests 93 tests in 25 suites, RiichiMjaiTests 14, mjTests 5; no compiler warnings |
| libriichi, 1,000 eager Tenhou games (seeds 1,000,000–) | 13,594 hands; board replay **0 failed, 0 differences**; 7,180,788 legality rows, **0 unexplained** (all in the known categories); 0 selfplay FAIL |
| libriichi, 1,000 random Tenhou games (seeds 2,000,000–) | 11,933 hands; board replay **0 failed, 0 differences**; 7,447,708 rows, **0 unexplained**; 0 FAIL |
| Directed scenarios, Tenhou (libriichi, `--check`) | 7,400 games, 40,725 hands, the close-out's seeds and counts (eight scenarios); every invariant ok (0 FAIL); board replay: 3,272 hands differ, **all named and the same as the close-out** (2,551 `triple_ron_abort`, 720 four-winds riichi stick, 1 libriichi `chiihou_after_own_daiminkan`); 17,378,244 legality rows, **0 unexplained** |
| Directed scenarios, Mahjong Soul (Mercury, `--check`) | 7,400 games, 31,226 hands; every invariant ok; 1,973,980 requests (17,251 `score`): Mercury and `./mj` **identical**; `./mj` against the round engine only the two known differences (887 riichi under 1,000 points, 5 fifth-copy riichi) |
| `tools/mercury_diff.sh`, 1,000 Mahjong Soul eager games (`--check`) | 13,608 hands; invariants ok; 1,070,707 requests (7,622 `score`): Mercury and `./mj` **identical**; against the round engine only the known 4 low-points and 2 fifth-copy riichi |
| Real-log slice | Tenhou 2024 (`--rules tenhou`): 184,424 games, 1,952,493 hands, **0 differences**; Throne 2024: 288,341 games, 3,038,033 hands, only the 11 known `log_defect:unbalanced_deltas` (the converter's pao defect); Jade 2024: 933,050 games, 9,780,910 hands (reduced format), **0**. The same as the close-out: nothing regressed |

`mj bench-round`: 14,610 rounds/s without events and 14,331 with (Mahjong Soul), as before.

## 6. Restructuring `Round.swift`

The reviewers' suggestions and my assessment. Nothing was restructured, as the brief says.

- **Both: keep the single value `RoundState` with its `Phase` enum, the cached waits and bitmasks, the batched answers and the eventless path; no generic reducer, phase structs or protocol hierarchy.** Agreed. Copying a `RoundState` is what the invariant checks, bots' look-ahead and replay rely on, and the fast path is measured.
- **Extract settlement as a pure function returning per-winner transfers, liability and stick allocation (Codex; Gemini: move `settle`/`winRequest` to their own file).** Worth doing, but when Phase 5 needs to show a settlement, not now. `settle` mixes the pao split, the honba rule, the sticks and event emission in one loop. A pure `settlement(...) -> [Transfer]` would let pao and multi-ron payments be tested as a table instead of through whole rounds. Risk is low: the composite-pao and multi-ron tests are exact, and there is the gate and the real logs. Cost is about a hundred lines.
- **Centralise the pending-kan lifecycle and the owed indicator in one transition with explicit announce, commit and rob outcomes (Codex).** The owed indicator is turned in six places: before a discard, at a window's close, at an open kan, before a closed kan, at a chained added kan, and at an added kan's commit. Two `ViewFolder` bugs came from that ordering, though in the folder, not the round. A single kan transaction type is the right shape, but the order differs by ruleset and was fixed from real logs. I would do it together with the typed kan-commit event (Codex 7) in Phase 5, with the libriichi run, the directed `robkan`/`fourkans` games and the real-log slice as the safety net, not as a standalone refactor.
- **Move `PlayerState`, `PondTile`, `RiichiStatus`, `Pao` and `waitMask` to their own file (Gemini).** Cosmetic and safe whenever someone next edits the file. `Round.swift` is about 860 lines in clear sections and is not hard to work in.
- **Share kuikae, waits and hypothetical-legality primitives where the contracts match (Codex).** Mostly done already: kuikae and completion are shared. The two legality paths should stay separate where the requests differ (affordability, fifth copy), and the Mercury dump keeps them in step.
