# Phase 3 final review — codex

Reviewed commit `dd0f46c7668777c6ec88c0b28ce0a3a4f161d6c1`.

## Findings

1. **Blocker — the mjai adapter silently passes a legal chained-kan ron.**
   `Sources/Riichi/Round.swift:570–581`, `Sources/mj/Driver.swift:93–107`,
   `Sources/mj/MjaiBot.swift:131–155`. Mahjong Soul emits `kakan, dora` for the
   second added kan while a robbing decision is live. The driver attaches the
   decision to `dora`. The adapter ignores the `hora` reply to `kakan` and accepts
   the natural `none` reply to `dora` as pass, with zero substitutions. The
   `chained` probe uses the real adapter and the driver's per-event delivery rule
   with the same wall under both settings. Keep event order, carry the triggering
   event's identity through the decision boundary, and retain its reply through
   subsequent notifications. If the bot protocol permits a decision after the
   indicator, specify and test that exchange separately. Add an end-to-end arena
   test for both orders and assert the actual win, event order and substitution tally.

2. **Should-fix — a legal action from an accepted game position traps while
   advancing.** `Sources/Riichi/Round.swift:100–102,158–164`,
   `Sources/Riichi/RoundResult.swift:50–54`, `Sources/Riichi/Game.swift:94–99,250–267`.
   The `honba` probe starts a game at the advertised maximum of 1,000 honba.
   The dealer's legal nine-terminals abort creates the next hand with 1,001 honba
   and trips the engine precondition. Sticks and scores also use admission limits
   at every new deal, so an upper-bound input needs a transition policy.
   Check initial positions at the public boundary, give the running game arithmetic
   headroom, and define a typed failure or end condition if that headroom runs out.
   Keep unrelated replay-input limits out of normal hand advancement.

3. **Should-fix — the throwing hypothetical scorer traps on an unchecked
   request.** `Sources/Riichi/Score.swift:13–23,147–153,166–194`. The `score`
   probe supplies a valid pinfu hand and `honba: Int.max`. Its ron payment
   overflows before Swift can return a `ScoreError`. Validate score requests and
   rules in the public entry point, including counters, physical tile inventory,
   and structural hand size. Keep a fast internal path for engine-owned requests
   if profiling justifies it. The CLI's input guards are a separate entry point.

4. **Should-fix — a seat's folded table retains the pre-award scores at end
   of game.** `Sources/Riichi/View.swift:203–205,266–272`,
   `Sources/Riichi/Game.swift:132–141,255–260`. The masked end event carries
   final scores after unclaimed riichi sticks go to first; the folder ignores
   them and retains the round's sticks. A website using `ViewFolder.Table` needs
   a defined terminal state. Fold these scores and clear the sticks, or export a
   distinct terminal projection with final scores and ranking. The current fold
   assertions skip the ended state.

5. **Should-fix — contradictory mjai win replies can be counted as successful.**
   `Sources/RiichiMjai/Mjai.swift:311–342`, `Sources/mj/MjaiBot.swift:151–155`.
   The `replyValidation` probe replies to seat 0's offered `1p` with `hora`
   naming a different seat and tile. It maps to a legal ron on the actual offer.
   The codec checks present `target` and `pai` for calls but ignores both for
   wins, and the adapter only extracts discard context. Pass a typed decision
   context covering wins on draws, discards and both robbery windows. Reconcile
   the fields the bot supplies with that context, keep supported omitted fields
   optional, and count mismatches as illegal. This matters for benchmark telemetry
   even though the engine still receives a legal action.

6. **Should-fix — an accepted mjai timeout can trap in `poll` conversion.**
   `Sources/mj/Commands.swift:108`, `Sources/mj/MjaiBot.swift:52–69`.
   The `timeout` probe passes 3,000,000,000 ms to the real reader with a child
   that produces no line. The unchecked conversion of remaining milliseconds
   to `Int32` traps. Validate the CLI interval before launching bots, and
   compute a bounded poll interval in the reader. If long deadlines are
   supported, repoll until the actual deadline after a capped poll expires.

7. **Suggestion — define a kan commitment for event consumers.**
   `Sources/Riichi/View.swift:169–200,251–258`, `Sources/Riichi/Round.swift:554–641`.
   The current reducer commits a pending kan on the first following event other
   than dora, robbery or abort. The chained-kan probe exercises a pending
   announcement with an intervening indicator. A typed engine-level commit
   or public delta would let a consumer apply the change directly, with the mjai
   projection retaining its wire sequence. Keep the value-semantic state machine,
   batched answers, distinct masked types and existing deterministic wall layout.

8. **Suggestion — distinguish physical win, scored interpretation and settlement.**
   `Sources/Riichi/Score.swift:69–80,166–181`, `Sources/Riichi/RoundResult.swift:4–25`,
   `Sources/Riichi/Round.swift:701–716,747–807`. The `heavenly` probe shows a
   physical `7z` draw and a score for thirteen-sided kokushi under Mahjong Soul.
   Those are both correct for the configured semantics. A UI cannot get the
   selected scoring tile or reading from `Scored`. `winRequest(for:)` also
   includes unrevealed ura and assumes the nearest eligible ron accepts for
   honba allocation. Publish scoring interpretations in the analysis result.
   Let a decision preview expose only visible information and label contingent
   honba or ura, and let settlement expose actual per-seat transfers and liability.

## Directed evidence

Run `sh Docs/Reviews/p3/final-codex-repro/run.sh` from the checkout. It builds the
current libraries and the adapter code without relying on a prebuilt executable,
uses physical 136-tile walls, and isolates the expected traps in subprocesses.

| Case | Observed |
| --- | --- |
| Chained added kan with post-kan-discard reveal disabled, toggling owed dora at announcement | With the chained flag on, events are `kakan,dora`; a manually submitted ron sees 2 dora from the owed indicator. With it off, `kakan` alone opens the window and the robbery has no bonus dora. The bot's identical reply loses only with the flag on. |
| Composite Daisangen + Tsuuiisou, two honba, dealer winner seat 0, liable seat 2 | Third-party ron from 1 gives `[96600,-72000,-24600,0]` for component pao and `[96600,-48000,-48600,0]` for whole-hand pao. Tsumo gives `[96600,-16000,-64600,-16000]` and `[96600,0,-96600,0]`, respectively. |
| Daisuushii + Suuankou Tanki + Tsuuiisou non-dealer ron | Mahjong Soul gives 5×, 160,000. Tenhou gives 3×, 96,000. |
| Kokushi on a closed kan | Mahjong Soul offers only the kokushi seat ron/pass. Its masked announcement shows the public quad, an uninvolved seat has no reacting window, and robbery leaves the completed-kan count at zero. Tenhou goes straight to kan commit, dora and replacement draw. |
| Daiminkan into rinshan tsumo | An owed indicator that would give bonus dora is still absent at tsumo. Both presets with their post-kan-discard reveal switches inverted give Haku + Rinshan and only the initial indicator. The switch affects ron on the discard, which this path bypasses. |
| Tenhou with physical `7z` finishing a single-wait kokushi | Mahjong Soul chooses a scoring interpretation worth 3×, Tenhou sticks to the supplied tile at 2×; the win event retains the physical draw. |
| Full East-only game, raised target, two sticks carried in | Eight hands across East and South, ending at `extensionOver`. Tied players rank by starting seat and the award goes to seat 0. The seat fold stays on the pre-award scores. |

The directed pao, heavenly tile, rinshan dora and leftover-stick checks establish
what HEAD does in cases the campaign could not distinguish. They do not establish
live client behavior. The composite case covers a third-party ron and tsumo with a
single liable component. It does not test possible combined pao and multi-ron
honba policies. The adapter reproduction invokes the actual child transport and
reply mapper with the driver's delivery rule, using a minimal bot that replies
to the kan announcement. It does not establish what every external bot would
return on the subsequent dora message.

## Documentation and preset audit

Pairs below are Mahjong Soul / Tenhou. `Rules.swift:119–195` and `Spec/rules.md`
§§1, 4–5 were the comparison. Shared fixed rules live in the engine rather than
as independently mutable `Rules` fields.

| Field | Preset values | Specification |
| --- | --- | --- |
| `startingPoints` | 25,000 / 25,000 | Matches `starting_points`. |
| `returnPoints`, derived `oka` | 25,000, 0 / 30,000, 20,000 | Matches `oka` in point units. |
| `uma` | [15k, 5k, −5k, −15k] / [20k, 10k, −10k, −20k] | Matches score uma; rank ladder adjustments are out of scope. |
| `targetPoints` | 30,000 / 30,000 | Matches both target rows. Their notes need the §5.8 repeat exception. |
| `length` | South / South | §1 allows East or South on both; presets choose South and support changing to East. |
| `dealerRepeatBeforeTarget` | true / true | Matches §5.8; §1 sudden-death prose says immediately after any qualifying hand. |
| `allLastTestAfterNagashi` | true / true | Matches §5.6. |
| `doubleYakuman` | true / false | Matches `natural_double_yakuman` and its four variants. |
| `tenhouAnyWinningTile` | true / false | §1 is missing this field and preset pair. §5.12 flags the choice as undetermined by logs; `Spec/formats.md:139–142,184–188` contains the operational default and Tenhou exception. |
| `kuitan` | true / true | Matches `kuitan_enabled`. |
| `doubleWindPairFu` | 4 / 4 | Matches `double_wind_pair_fu`. |
| `tripleRonAborts` | false / true | Matches `abort_sanchahou` and the inverse `triple_ron_enabled`. |
| `honbaToEveryRonWinner` | false / false | Matches `multi_ron_honba` and §5.2. The source comment calling Mahjong Soul unverified is stale. |
| `kokushiRobsClosedKan` | true / false | Matches §1. §4.16 needs a Mahjong Soul qualifier, and §1's wording “on declaration” for immediate ankan dora needs the robbery exception since ankan dora appears at commit. |
| `openKanDoraBeforeRon` | true / true | Matches §1 timing cells and §5.4. §1 timing notes still say Mahjong Soul ron is unverified; §4.17 says after discard, though the engine emits `dora` before `dahai`. |
| `owedDoraAtChainedAddedKan` | true / false | Matches §1 added-kan note and §5.10. Omitted from the public initializer, where it defaults false even if callers copy the other Mahjong Soul arguments. |
| `paoCoversWholeHand` | false / true | Matches `pao_composite_yakuman`; the note and §4.31 should label component-only as Mahjong Soul. §5.12 records the evidence limitation. |
| `riichiOnFifthCopyWait` | true / true | Matches §1 karaten note and §5.7. The line protocol deliberately forces false; this is documented in both specs. |
| `fifthCopyTenpaiAtDraw` | true / true | Matches §5.7. No separate §1 row. |
| `fourWindsRiichiStickPaid` | true / true | Matches §5.9. No separate §1 row; its four-winds row overlooks stick acceptance. |
| `temporaryFuritenEndsOnCall` | true / true | Matches §1 cells and §5.11 for chi, pon and open kan; §1 note and §4.28 retain contradictory older text. |
| `temporaryFuritenOnDeclinedTsumo` | false / false | Matches §5.13 for non-riichi. No separate §1 row. |

The ranked fixed rows describe the engine's below-zero rule, one extension wind,
auto yame with the repeat exception, renchan, base honba, red inventory, atozuke,
kuikae, multiple-ron priority, aborts, nagashi, limit values, pao triggers and
splits, riichi thresholds, kan limit, fu rules, furiten, tenpai pool and tie order.
Two prose details need correction. In §1, “honba value ron” needs to point to the
pao split exception. The extension maximum's “ends unconditionally” should read
as ending when the deal advances beyond the extension, or earlier when an end
condition is met. Both exceptions are already described nearby.

**Engine design drift.** The architecture still matches the implementation
around deterministic walls, in-place round/game transitions, typed actions and
masked state, and a separate Foundation-free mjai codec. `Spec/wall.md` matches
`Wall.swift:50–121` and the three exact wall vectors passed. These design sections
should be amended.

- §2 and §4.2 describe shared legality more strongly than the code supports.
  `Legal.swift` implements the standalone format and `RoundLegal.swift` has
  actual table legality, including score checks, the two-step riichi and distinct
  discard origins. They share some primitives and scoring. `Spec/formats.md:193–249` defines a weaker hypothetical request, including no affordability
  test and the strict fifth-copy rule.
- §4.1 omits triple-ron abort on an added kan under Tenhou and mixed-rules
  triple-ron abort on a closed kan. It also states temporary furiten survives an
  open call. In both presets an own chi, pon or daiminkan clears it, and the
  replacement draw itself leaves temporary furiten unchanged.
- §4.2 retains the old four-winds riichi stick decision and old Mahjong Soul
  defaults on post-kan discards and fifth-copy draw tenpai. Both presets pay the
  riichi stick, expose owed dora before the discard and count draw tenpai on a
  fifth copy if the four are partly in melds. The chained added-kan paragraph
  gives the Tenhou order only. The kan-announcement invariant applies to hand,
  melds and waits, while an owed indicator may already be revealed.
- §4.4 promises cached shanten and a cheap yaku-only offer test. The engine
  caches counts and waits; it computes shanten to gate riichi and calls the full
  scorer on win candidates (`RoundLegal.swift:94–117,186–191`). The riichi gate
  code tests shanten at most zero on the 14-tile state.
- §5's unverified repeat and post-nagashi wording predate the log decisions.
  Name the configurable target and pre-nagashi override explicitly. §6 should
  explain decision-only reaction context, which keeps window existence from
  seats with no offer, and clarify that the folder rebuilds the event-derived
  table rather than all of `PlayerView`. §6's timeout and substitution
  description needs to distinguish transport failures, per-event replies and
  absent decisions after findings 1, 5 and 6 are fixed.
- §7 should describe the current checker as validating provided and inferable
  fields under documented conventions, including reduced input and an East
  fallback, and version 1 trace as recording preset rules only. §8 should give
  the actual scope of the oracle comparisons and stop presenting test
  self-consistency as external evidence for payout or adapter behavior.

## Test strength and gaps

Swift 6.4.4 ran the Swift Testing suites with
`CLANG_MODULE_CACHE_PATH=/tmp/p3-final-clang SWIFTPM_MODULECACHE_OVERRIDE=/tmp/p3-final-pm swift test --disable-sandbox --disable-xctest`.
Riichi passed 75 tests with one recorded known issue for
`declined_tsumo_outside_riichi`; RiichiMjai passed 11. The initial bare
`swift test` hit the restricted user cache. The scenario suite reported 134
cases at run time. Source and test files matched HEAD, and the targeted probes
use embedded walls independent of the concurrently edited scenario directory.

- `GameTests.swift:129–154,162–197` checks the fold against engine snapshots and
  skips comparisons at terminal states. Applying the game's terminal stick
  award in the reducer is therefore untested. The “legal actions agree”
  assertion compares two paths that call the same round function. The chained
  test checks the correct offer and manually supplies its answer, so a lost
  external bot reply does not change its result.
- `CommandTests.swift:68–111` verifies two-step reach, positive substitution
  counters and a wall-clock bound for the named hostile cases. It does not
  associate each reply with the decision that consumed it, and checks
  neither contradictory win metadata nor an out-of-range timeout. A benchmark
  can accept a syntactically sound pass after discarding the earlier winning
  reply and still pass those tests.
- `SelfPlayTests.swift:299–318` samples invariants across 12 configurations. It
  varies neither `owedDoraAtChainedAddedKan` independently of preset nor the
  game flow switches and length. A wrong payer can preserve tile and point
  totals. Assert exact transactions under controlled flag changes, particularly
  composite pao and nearest/every-winner honba with a third-party discarder.
  The current East transition coverage in `GameTests.swift:115–125` is
  synthetic; keep an entire East-plus-South game in the automated suite.
- `GameTests.swift:200–221` checks arithmetic at large chosen values for final
  settlement. It never advances a game from the maximum valid counter. Add
  transitions from boundary positions and rejection tests for library score
  requests separate from line-protocol parsing.
- `MjaiTests.swift:46–115` exercises serialization and compares most ordinary
  fields. The required event set omits `daiminkan`, and the win comparison
  ignores the winning concealed tiles, yaku, fu and han; the draw comparison
  ignores the tenpai flags and per-seat hand masking. Those mutations could
  survive that round trip. Assert field values explicitly on a drawn hand with
  a known/hidden mix, a riichi win with ura, and a real open kan. Use both
  public perspectives for each mask assertion.
- `ScenarioTests.swift:277–344` compares fields present in the fixture.
  Default expectations and `events_order` allow unasserted payloads or
  additional events; a recorded known issue permits any failure in its
  scope. For decisive cases, compare full ordered events, both sides of the
  score/stick ledger and terminal views. Narrow the known-issue assertion to
  the exact disputed difference, so an unrelated regression remains visible.

## Phase 4 and 5 API recommendations

1. **Give bot and UI clients a seat-scoped decision envelope.** Include the
   safe rules configuration, trigger and stable decision ID, masked events
   since the prior step, canonical typed options, round/turn context and
   per-seat terminal data. Keep submitting actions and resolving simultaneous
   answers on the host. A bot should choose an offered option without
   reconstructing riichi eligibility, kan phase or the call's source from
   strings. This also gives the benchmark a decision ID for substitutions
   and reply latency. Keep the unmasked replay and observer capabilities in
   the host interface.

2. **Add a validated analysis surface for an LLM tool server.** Use typed
   hypothetical score and legality requests with explicit physical bounds,
   contextual flags and actionable errors. For the actual table use
   `PlayerView.legalActions`. For analysis, expose per-discard shanten,
   improving tile kinds and visible-copy-adjusted ukeire. The existing
   `Shanten.swift:188–201` count subtracts one's concealed tiles and melds;
   a visible-copy count also needs public ponds, called-away deduplication,
   melds and indicators. Give safe-tile analysis evidence per opponent, such
   as genbutsu from their discards and deductions from visible copies. Keep
   heuristic safety estimates distinct from guarantees, and derive both
   from the masked snapshot. Include the scoring interpretation and actual
   settlement separately as described in finding 8.

3. **Use a small, versioned JSON/Wasm interface.** Start with game creation,
   seat projection, a submit/resolve operation, and pure hand analysis. Put
   opaque game handles and deterministic data DTOs at this boundary, with
   tagged actions, string UInt64 seeds, typed invalid-input errors, explicit
   buffer ownership and a destroy operation. Keep JS across steps in charge
   of callbacks, rendering and bot scheduling. Pin ABI/schema versions and
   add a native-versus-Wasm transcript test with malformed input and
   terminal cases. `Package.swift:14–23` supports this split. The review
   exercised native Swift and left Wasm ABI and parity unverified.

4. **Keep the round model and extract the two parts with the best boundaries.**
   Move payout computation in `Round.swift:747–807` into a pure settlement
   function returning per-winner transfers, liabilities and stick allocation.
   Let the round apply the ledger and emit events in order. Centralize the
   pending-kan lifecycle and owed-indicator decision in one transition with
   explicit announcement, commit and robbery outcomes. Share targeted pure
   primitives for kuikae, waits and hypothetical legality when their
   contracts align. Keep the stage dispatch, draw order, cached
   representation, batched replies and eventless fast path. A generic reducer
   rewrite, hidden-state bot framework and new wall abstraction can wait.

## Verdict

**Not ready as the shared foundation for the bot arena, benchmark and website yet.**
The deterministic round core passed the directed rule cases and is suitable
for in-process bot and analysis prototyping. Fix decision/reply
binding before using mjai results in a benchmark. Close the accepted-state
transition trap before exposing resumable games, validate the analysis and
transport inputs, and settle the terminal view contract before shipping the
website. The rule and design edits should land alongside their corresponding
boundary changes.
