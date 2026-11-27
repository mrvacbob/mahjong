# Phase 3 package B: the round state machine — notes

Brief: `docs/briefs/p3-B-round.md`. Nothing is staged or committed.

## Result

- Corpus: `python3.14 tools/harness.py ./mj corpus/*.txt` → **12,439 of 12,439**.
- Clean release build: no warnings. `grep '^import' Sources/Riichi` is empty.
- `swift test`: every test passes. The scenario test has one case per scenario, and
  disputed scenarios are recorded as known issues (a disputed scenario that starts
  passing fails the run, so the list cannot go stale).
- Scenarios (123 files when last run, 69 of them the unreviewed second batch):
  102 single-round scenarios run, **95 pass, 7 disputed** (below); the 21
  `endgame_*` scenarios are listed as disabled ("game end is package C").
- Benchmark: **≈13,800 rounds/s** of uniform random play, the same with and
  without events (details at the end).

## Package A follow-ups

- **Wall key** is now `mix(seed) ^ mix(~hand)`. `Wall.swift` (`Wall.key`),
  `spec/wall.md` (§2 algorithm, §4 check values for seed 0 hand 0, §6 note, §7
  vectors) and the test vectors are updated. The vectors and check values come from
  a fresh independent Python implementation written from the spec text (kept in the
  scratchpad, not the repository); a test also checks the key's check values and
  that the old collision `(seed + G, hand − 1)` no longer collides. The reviewer's
  separate Python implementation matched too.
- **Temporary furiten**: nothing to change; `Rules.temporaryFuritenEndsOnCall`
  stays (default false on both), and rules.md now agrees with the design.

## Package A review (docs/reviews/p3/A-agy.md)

1. `Kind(suit, number)` now traps on a number outside the suit. Fixed.
2. `Meld.kuikaeForbidden(took:)` returns `[]` for kans, and traps with a message
   (not a bare force-unwrap) if `took` is not in the meld. Fixed.
3. Line protocol: `by=` must be `tsumo|ron` (`error=bad_by`), `from=` must be
   `kamicha|toimen|shimocha` (`error=bad_from`), and `called=` must be a chi or pon
   (`error=bad_called`). Fixed; the corpus uses only valid values and still passes
   12,439 of 12,439, so no case relied on the lax behaviour.
4. `Scored.yaku` is now `[YakuEntry]` (`name: YakuEntry.Name`, which is
   `.yaku(YakuName)`, `.dora`, `.aka` or `.ura`, and `value`), and `Scored` is
   `Hashable`. `Scored.value(of: YakuName)` is what pao uses. The text form and the
   tie-break order are unchanged.
5. Tests added (`ReviewFollowupTests.swift`): red-five `TableMeld` cases (pon with
   a red from hand then a plain added, plain pon with the red added, two reds
   rejected for added kan, daiminkan and ankan, chi suji kuikae with reds), tenhou
   with chuuren under both rulesets, `isTenpaiAtDraw` with the waits' four copies in
   a closed kan, `LegalRequest` `.called` with red fives, `dealt(to:dealer:)` for all
   four dealers, and the `mj` line protocol run as a child process (`rules=tenhou`,
   `rules=bogus`, and the three new errors).
6. (suggestion) `Rules.uma` re-checks its length in `didSet`. Done.
7. (suggestion) `expand` no longer computes `one(i + 1)` past the suit. Done.
8. (suggestion) the 16 MB table: no change, as the reviewer said.

## What I built

- `Action.swift`: `Action` (`discard(tile, tsumogiri:)`, `riichi`, `tsumo`,
  `ankan(kind)`, `kakan(tile)`, `kyuushu`, `ron`, `pon(a, b)`, `daiminkan`,
  `chi(a, b)`, `pass`; pon and chi carry the two hand tiles, so red variants are
  distinct), `TurnStart`, `Discard`, `PendingKan`, `Phase`, `Answers` (four fixed
  slots), `RoundError`.
- `Round.swift`: `RoundState` (value type; `init` deals and makes the dealer's
  draw; `apply`, `resolve`, each with and without an event buffer; non-mutating
  `applying`/`resolving`; queries for hands, drawn tile, melds, ponds, riichi
  status, pao, waits, furiten, live tiles left, dora indicators, seats to answer),
  the resolution table, kans as transactions, settlement.
- `RoundLegal.swift`: `legalActions(for:)` and the window offers. Canonical order:
  own turn `tsumo`, `riichi`, `ankan` by kind, `kakan` by tile, `kyuushu`, then
  discards by tile (a from-hand discard before the tsumogiri of an equal tile); a
  window `ron`, `daiminkan`, `pon` by tiles, `chi` by tiles, `pass`.
- `RoundResult.swift`: `RoundResult` (outcome, round deltas, scores, sticks left,
  dealer, dealer repeat, `nextHonba(after:)`) and `Win` (winner, from, tile,
  `Scored`, dora and ura indicators shown, this win's deltas, liable seat, robbed
  kan).
- `Event.swift`: `Event`, one case per mjai message of design §6 that a round
  emits (`start_game`/`end_game` are game level), with `type`, `actor` and the
  stable text form `text` (`pon(1)`, `dora(9p)`, `ryukyoku(exhaustive)`,
  `ryukyoku(suufon_renda)`, `start_kyoku`).
- `tools/scenario.py --json-dir DIR`: writes every scenario's JSON (or
  `{name, error}`) into `DIR`; documented in `scenarios/FORMAT.md`. Scenario
  semantics are untouched.
- Tests: `ScenarioTests.swift` (runner; disputes; corrected variants of the
  disputed scenarios), `SelfPlayTests.swift` (invariants, replay, suit rotation),
  `RoundTests.swift` (hand-built walls; `Rules` fields with no preset, checked by
  flipping one field on an existing scenario), `ReviewFollowupTests.swift`.
- `mj bench-round [ROUNDS] [tenhou]`: the in-process benchmark (not part of the
  line protocol; `mj` with no argument behaves as before).

### Self-play invariants checked (design §8 layer 4, one round)

Over 6,000 rounds per run (1,000 random and 2,000 eager, under each ruleset), with
the expensive checks on one round in eight:

- tiles conserved by kind and red flag (hands, drawn tiles, melds, uncalled pond
  tiles, a pending added-kan tile and a chankan winning tile against the dealt and
  drawn wall slots); `sum(scores) + 1000 × sticks` constant; round deltas sum with
  the stick change to zero;
- every round ends; the seat to act always has a legal action and nobody else does;
  every window has someone to answer;
- every action in `legalActions` applies to a copy without error, and probes
  outside it (every tile not offered as a discard, `ron`, `pass`, `riichi`,
  `tsumo`, `kyuushu`, a kan, a pon) throw and leave the state unchanged; an answer
  outside the window's offers throws; another seat cannot act;
- after every window that did not end the round, every seat that was waiting on the
  tile is furiten (unless it just called it and its waits changed);
- the exhaustive-draw payment matches the tenpai count, and the cached-waits tenpai
  test agrees with `isTenpaiAtDraw`;
- answers keyed by seat are order-independent by construction (`Answers` is four
  slots; the test checks that building them in reverse gives the same value);
- a round replays to identical events and result from wall and decisions;
- rotating the three suits throughout a wall, reds included, with the decisions
  rotated, gives the same deltas, sticks, dealer repeat and yaku.

The eager bot wins whenever it can (but passes a ron one time in ten), declares
riichi when legal, calls or kans with probability 60%, and otherwise discards to
the lowest shanten. Coverage over one run (Mahjong Soul, 3,000 eager rounds, before
the run was shortened): 1,199 rons, 421 tsumo, 1 double ron, 10 chankan, 12 rinshan,
29 haitei, 53 houtei, 60 ippatsu, 644 riichi, 7 riichi kans, 3 four-kan aborts, 18
nine-terminal aborts, 1 yakuman. Pao, nagashi, triple ron, four riichi and four winds
do not arise in self-play; the scenarios cover them, and the coverage report belongs
with `selfplay` in package D.

## Decisions the design left open

1. **Round deltas include riichi sticks.** `RoundResult.deltas` is scores after the
   round minus scores at its start: riichi deposits, payments and sticks collected
   (the scenarios' meaning). Each `Win.deltas` and each `hora` event's `deltas` is
   that win only, the first winner's including the sticks.
2. **Answers from seats not asked**: `nil` or `.pass` is accepted, anything else is
   `illegal`. A seat that is asked must answer (`missingAnswer`).
3. **Validation before mutation.** `apply` checks legality with a direct test per
   action (`isLegalTurnAction`, equivalent to `legalActions(...).contains`) before
   touching the state; `resolve` checks every answer first. Self-play checks both
   paths agree.
4. **Waits** are structural (a fifth copy counts), cached per seat as a 34-bit mask
   and recomputed only when the concealed hand changes (not on tsumogiri). They are
   computed from the shanten tables: the kinds `k` with `shanten(hand + k) = −1`.
   While a seat holds 14 − 3k tiles after a chi or pon it has no waits; no window can
   open before its discard.
5. **Ron is offered** when the tile is in the waits, the seat is not furiten, and
   `score` finds a yaku. Robbing a closed kan (Mahjong Soul) is offered to a closed
   hand that is kokushi with the kan's kind and not furiten.
6. **Kan bookkeeping.** A closed or added kan's tiles leave the hand at the
   announcement (the `ankan`/`kakan` event); the count, ippatsu, `anyCallMade` and
   indicators wait for the commit after the robbing window. An open kan reveals any
   owed indicator after its `daiminkan` event and before its replacement `tsumo`.
   A closed kan reveals an owed indicator before its `ankan` event (design §4.2), so
   it is shown even if the closed kan is then robbed (see QUESTIONS.md #3).
7. **Mahjong Soul's owed indicator after a discard** is revealed after rows 1–5 of
   the table and before the call or draw. It is not revealed if the round ends at
   the window (ron or abort). A riichi and an owed indicator cannot fall on the same
   discard (riichi needs a closed hand), so their mutual order never arises.
8. **Furiten for a closed kan's window** applies to seats that could have robbed it
   (kokushi on that kind under `kokushiRobsClosedKan`), whether or not they were
   furiten already; under Tenhou rules nobody.
9. **Temporary furiten ends only on a live-wall draw**, not on a replacement draw
   after the seat's own open kan (the design says "draws from the wall"; a
   replacement draw is part of the call).
10. **Riichi furiten from a skipped draw** is set when a seat in accepted riichi
    has a drawn tile in its waits and discards or kans instead of `tsumo`.
11. **Pao**: set on the pon or daiminkan that makes the caller's third dragon set or
    fourth wind set (closed kans of that suit count toward the three or four);
    applies when the win's yakuman list contains that yakuman. Tsumo: the liable
    seat pays the ron value of the liable part plus all honba, and any remaining
    yakuman are paid as an ordinary tsumo without honba. Ron by a third party: the
    liable part's ron value split in half between liable seat and discarder, the
    liable seat also paying the honba, the discarder the rest. Ron from the liable
    seat: an ordinary ron. `Win.liable` records the liable seat in all three.
12. **Nagashi**: a seat whose every discard is a terminal or honor and none was
    called away; each qualifying seat is paid as a mangan tsumo (dealer 4,000 all,
    otherwise 4,000/2,000), no honba, sticks stay. Tenpai is still computed for the
    dealer repeat. The event is `ryukyoku` with reason `exhaustive`.
13. **hora fields**: `horaTehais` is the concealed hand without the winning tile;
    the event carries the full `Scored` (yaku, han/fu or yakuman multiple,
    payment). Field names in JSON are package D's.
14. **Tenhou and chiihou** need `TurnStart.draw` (not a replacement draw), no call
    at the table, and no discard by the seat yet. Kyuushu the same.
15. **Errors** are typed throws (`throws(RoundError)`): `wrongPhase`,
    `notYourTurn`, `illegal(seat, action)`, `missingAnswer(seat)`.
16. **Events** are collected through an internal emitter that builds nothing when
    the caller passes no buffer; the public overloads with and without `events:`.

## Scenario disputes

Run against the scenario files as of the end of this package (the first batch as
reviewed and committed in `9594ba8`, the second batch as committed in `332e9ca`
plus whatever its writer changed afterwards). Each is a known issue in
`ScenarioTests.swift`; `correctedDisputedScenarios` runs my correction of the first
and fifth so that what they test is still tested.

Reviewed (first batch):

1. **`closed_kan_rinshan_tsumo`** — the draws make all four first discards 3z
   (West): seat 0's riichi tsumogiri and seats 1–3's tsumogiri, with no call. That
   is four winds (rules.md §1 `abort_suufon_renda`, design §4.1 row 2), so the hand
   aborts at seat 3's discard (sticks: seat 0's riichi is not accepted, row 2 before
   row 3) and the closed kan never happens. With seat 3's draw swapped for a later
   honor tile that is not 3z, the scenario passes as written (8 han 60 fu baiman,
   `ankan(0), dora(8m), tsumo(0)`).
2. **`riichi_furiten_skipped_tsumo_ankan`** — the same four 3z first discards abort
   the hand. Also, the comment says seat 0's waits are 1s and 4s, but
   `678m 234p 23444s 88p` also reads `234s 44s 88p`, a shanpon on 4s/8p, so the waits
   are 1s, 4s, 8p; `ankan 4s` leaves `23s 88p` (1s, 4s) and changes them, so the kan
   is illegal in riichi (rules.md §4.14). The scenario needs a different hand; the
   behaviour it wants (riichi furiten after skipping a winning draw) is covered by
   `RoundTests.riichiFuritenAfterSkippedTsumo` (via a tsumogiri).
3. **`kan_one_live_tile_rinshan_not_haitei`** — the dealer wins, so `honba` should
   be 1, not 0 (design §5 step 2: "+1 … after a dealer win"; the file itself says
   `dealer_repeats: true`). Everything else passes.
4. **`last_tile_houtei_no_calls`** — same: the dealer (seat 0) rons, so `honba` 1.
5. **`riichi_ankan_waits`** — after seat 1's `ankan 6666s`, the concealed tiles are
   `23m 999p 33345s`; with the rinshan 1m the only reading is
   `123m 999p 33s 345s`: one concealed triplet plus the closed kan, so no sanankou
   (the comment's `333s` triplet would leave `45s`). The hand is double riichi 2 +
   tsumo 1 + rinshan 1 = 4 han; fu 20 + 2 + 8 (999p) + 16 (6666s closed kan) = 46 →
   50: mangan 2,000/4,000. Deltas `−5000 9000 −2000 −2000` (seat 0 −1,000 riichi
   −4,000; seat 1 −1,000 + 8,000 + 2,000 sticks). The corrected version passes.

Unreviewed (second batch; for the reviewer):

6. **`nagashi_mangan_dealer`** and 7. **`nagashi_mangan_multiple_winners`** — both
   expect the event `ryukyoku(nagashi_mangan)`, while the reviewed
   `nagashi_mangan_tenpai_dealer` expects `ryukyoku(exhaustive)` for the same kind of
   ending. The design (§4.3) makes nagashi part of an exhaustive draw and §6 gives
   no separate reason; I followed the reviewed scenario. Everything else in both
   passes. One of the two conventions should be chosen in the design (mjai/Mortal
   has no reason field at all, so this is only about our own rendering).

Disputes raised during the work and since fixed by the scenario writers (they now
pass): `kakan_robbing_pass_furiten` (seat 2 was asked for a chi it was assumed not
to have), `call_priority_ron_over_daiminkan` (a 14-tile hand),
`chiitoitsu_25_fu_no_four_of_a_kind` (the winning hand was all terminals and
honors, so honroutou), `nagashi_mangan_lost_when_called` (missing window answer).

## What I now think is wrong or open in the design or rules

1. **Skipping a tsumo outside riichi.** The design makes temporary furiten come
   only from windows. Both clients, as I understand them, also make a seat
   temporarily furiten when it declines its own winning draw (見逃し of a tsumo),
   until its next draw; rules.md §4 item 28 talks only of passing a ron. Not
   implemented; it changes ron legality within one go-around. It should be checked
   and added as a rule (and a `Rules` field if the clients differ).
2. **Temporary furiten and replacement draws** (decision 9) are not stated.
3. **A closed kan after an open kan** shows the owed indicator before the `ankan`
   event, so a kokushi robbing that closed kan sees one more indicator than it
   would if the order were `ankan`, robbing window, `dora` (owed), `dora` (new).
   Harmless for scoring (kokushi is a yakuman), visible in the log. QUESTIONS.md #3
   already asks.
4. **Nagashi's event reason** (dispute 6–7): the design should say.
5. **The `legal` line operation** is still the package A `LegalRequest` code, not a
   wrapper over `legalActions` (design §2). It cannot be: the line protocol has no
   round (no ponds, no wall, no source seats). The two share the scoring and kuikae
   code but not the enumeration; the Mercury cross-check (design §8 layer 3) is what
   keeps them in step. The design should say this instead.
6. **Four kans and the robbed fourth kan**: if the fourth kan is an added kan that
   is robbed, it never counts, so no four-kan abort; I believe that is right, but
   the design's row 4 ("the discard after a fourth kan") does not say so.
7. **Pao with the liable seat dealing in under Tenhou's whole-hand rule** is the
   ordinary ron and needs no special case, but rules.md does not say what the liable
   seat pays when the composite remainder is ronned from it (it pays all, as the
   discarder). Stated here for package C/D readers.
8. **The "eager" bot of design §7** needs a discard policy; uniformly random
   discards almost never reach tenpai (96% exhaustive draws in a first try). Mine
   discards to the lowest shanten. The selfplay bot in package D should do the same.

## Benchmark

`mj bench-round 50000` (release, Apple Silicon, one core): uniform random choice
among `legalActions` for every decision, seeds 0…49,999, Mahjong Soul rules.

| events | rounds/s | decisions/round | events/round |
|---|---:|---:|---:|
| off | 13,758 | 88 | 0 |
| on | 13,763 | 88 | 155 |

Tenhou rules: 14,001 and 13,740. Events cost nothing measurable: the time is in
legality and waits. With about 10 rounds a hanchan that is roughly 1,300 random
hanchan per second per core, before `PlayerView` building (package D). Two changes
during the package took it from 6,800 to 9,900 to 13,800 rounds/s: replacing
`[Tile].distinct` (a `Set` plus a sort) by an adjacent dedupe of the sorted hand in
the turn enumeration, and computing tenpai at the exhaustive draw from the cached
waits instead of `isTenpaiAtDraw`'s decompositions (self-play checks the two agree).
The remaining time is mostly the shanten table combines in `waitMask` (on every
discard that changes the hand) and the riichi search.
