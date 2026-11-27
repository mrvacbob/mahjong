# Phase 3 close-out — notes

Brief: `docs/briefs/p3-closeout.md`. Nothing is staged or committed. The game records,
everything derived from single games, and the original Tenhou records used here are
outside the repository (`/Volumes/Psyche/mahjong/work/closeout/`, raw Tenhou XML in
`/Volumes/Psyche/mahjong/work/rawdb/`); case ids are in
`/Volumes/Psyche/mahjong/work/reallogs/cases.md`. No game ids, player names or
excerpts of records are in the repository.

## Result

- **The unexplained real-log cases, settled** (section 1): the Jade shousangen is a
  defective record; the two Tenhou kuikae discards and the two unpaid nagashi are
  not rules of play but the server acting for a seat that had lost its connection
  (shown by the original Tenhou XML, which keeps the `BYE` messages the mjai
  conversion drops: 0 kuikae among 51.76 million discards after a call by a
  connected seat, and 4,442 of 4,442 connected nagashi seats paid, 2009–2025); the
  four rons after declining a tsumo by a kan are a **rule we had wrong**.
- **Declined tsumo: `temporaryFuritenOnDeclinedTsumo` is off for Tenhou too.** After
  a declined tsumo the 13 tiles left wait on the tile let go, so a decline by a
  discard or riichi is always own-discard furiten and the field can only show after a
  kan; there Tenhou's records have 4 rons in 6 chances (2010–21) and Mahjong Soul's 12
  in 14, and no record anywhere of a ron refused by the field. Nothing ties a change
  to a date.
- **Directed coverage** (section 2): `mj selfplay --scenario` with eight scenarios;
  every listed branch reached hundreds to thousands of times under both rulesets
  (the robbed closed kan under Mahjong Soul only: Tenhou does not allow it), with
  every invariant on, through libriichi (Tenhou) and Mercury (Mahjong Soul).
- **The gate** (section 3): 109,400 Tenhou games (50,000 eager, 50,000 random, 9,400
  directed), 1,325,364 hands; 3,274 board-replay differences, every one a named
  difference (2,553 triple-ron aborts, 720 four-winds riichi sticks, 1 libriichi
  chiihou); 752,829,936 legality rows, **0 unexplained** (one hand's 2 rows named as
  a new rule-choice difference, `riichi_ankan_waited_tile`).
- **Engine bug fixed:** `ViewFolder` took Mahjong Soul's owed indicator at a chained
  added kan for the kan's commit (folding only; found by the directed invariants).
  No game, log or payment changed.
- **Real-log slice** with the final binary: Tenhou 2024 0 differences (184,424
  games), Throne 2024 only the 11 known converter defects (288,341), Jade 2024 0
  (933,050); nothing regressed.
  The all-years re-runs for the declined-tsumo count (every Tenhou and Mahjong Soul
  game) reproduce the campaign's results with the four declined-tsumo rons now
  passing.
- Corpus **12,439 of 12,439** (Mercury `mj` too); `swift test` **86 tests in 21
  suites pass** with 1 known issue: the Tenhou run of `declined_tsumo_outside_riichi`,
  which expects the old furiten (all 134 scenarios run; the other 133, and that
  scenario's Mahjong Soul run, pass). No Foundation in `Riichi` or `RiichiMjai`;
  `agpl/` and the `.scn` files untouched.

## 1. The unexplained real-log cases

A new source settled three of the four: the upstream dataset's SQLite databases of
the **original Tenhou XML records** (`logs/tenhou-raw-db/`, 2009–2025, 2,461,224
houou games), which keep what the mjai conversion drops: `BYE` (a seat's
connection lost) and `UN` (reconnected), and the order of every server message. A
small decoder and a scanner over all of it are in the work directory
(`closeout/scripts/raw.py`, `rawscan.py`).

| Case | Verdict |
|---|---|
| C3, Jade 2023: shousangen paid 5,200 where the engine pays 8,000 | **defective record** |
| C7, Tenhou 2012 and 2013: a kuikae discard right after a chi | **not a rule of play**: the server's discard for a seat that is losing its connection |
| C8, Tenhou 2019 and 2021: a nagashi seat paid as noten | **not a rule of play**: a disconnected seat is not paid nagashi |
| C6 and C17, Tenhou 2010, 2012, 2017, 2018: a ron after declining a tsumo by a kan | **rule we had wrong**: fixed (`temporaryFuritenOnDeclinedTsumo` off for Tenhou) |

No case is an engine bug, and none is a rule that changed on a known date.

### C3: the Jade shousangen (defective record)

Worked by hand from the reduced log (following every draw, discard and call of the
hand): the winner calls `pon C` and `chi 789p`, and holds `789s FFF P` when it rons
the `P` another seat discards. No tile kind appears more than four times in the
hand's deal and draws. That is shousangen (2 han) with hatsu and chun (1 each):
4 han; fu 20 + 8 (concealed `FFF`) + 4 (open `CCC`) + 2 (dragon pair) + 2 (tanki) = 36
→ 40: a non-dealer mangan, 8,000. The next header has the winner up 7,200 and the
discarder down 6,200 with two riichi sticks on the table: 5,200 paid (3 han 40 fu, or
2 han 80 fu). No reading of the logged tiles gives 3 han (two dragon triplets always
bring their two yakuhai with the shousangen), no indicator the reduced format hides
can lower a payment, and there is no kan. So the logged hand and the logged result
cannot both be true. The reduced Jade format records neither payments nor yaku, so
the record cannot show which is wrong. Every one of the 2.6 million full-format Throne
hands of 2023–24, shousangen hands included, is paid as the engine pays it, and this is
the only payment difference in 28 million reduced-format Jade hands. Verdict:
defective record. Nothing to change.

### C7: the kuikae discards (the server's discard for a dropping seat)

In both original records the seat that discards the forbidden tile loses its
connection right after: the next message for that seat is `BYE`, before its next
draw (2012: chi `2s` with `34s`, discard `5s`, then `BYE`, reconnected 12 messages
later; 2013: chi `5sr` with `46s`, discard `5s`, then `BYE`, reconnected 20 messages
later). In both, the discarded tile is the last tile of the seat's hand in Tenhou's tile order (the highest tile id),
which is what Tenhou's client and server discard for a player who does not answer.
The scan of every original record of 2009–2025 settles it:

- 51,763,663 discards right after a chi or pon. Of the 51,761,076 by a seat that
  stayed connected, **none** is a kuikae tile.
- 2,587 were made by a seat that disconnected before its next draw (or was already
  disconnected); 2 of them are kuikae, these two, both the rightmost tile.

So the server's substitute discard for a dropping seat does not apply the kuikae
restriction; a player cannot make that discard. It is not a rule the engine should
follow (an mjai bot that times out gets the adapter's own substitute, which is
always legal). Verdict: not a rule of play; the mjai conversion drops the `BYE`, so
check-log cannot tell these from an illegal discard. The engine is unchanged.

### C8: the unpaid nagashi (a disconnected seat)

Both nagashi seats (seat 1, the dealer, both times) had lost their connection before
the exhaustive draw: the original records have that seat's `BYE` 10 and 8 messages
before `RYUUKYOKU`, and its `UN` (reconnection) only in the next hand. The server
paid the hand as an ordinary exhaustive draw with that seat noten. Over all original
records of 2009–2025: **4,442** seats that qualified for nagashi at an exhaustive draw
while connected, **all paid**; **2** that qualified while disconnected, **both
unpaid** (these two). Verdict: not a rule of play but the server's handling of a
disconnected seat (noten, no nagashi), which the mjai records cannot show. The engine
is unchanged.

(While reading the originals, C2, the 2010 `hora` on a discard that completes no
hand, turned out to be in the original too: the seat discards `8p` and then `9p`
with no draw between, and the `9p` is ronned; the conversion keeps only the first
discard. A defective original record.)

### C6 and C17: ron after declining a tsumo by a kan (rule we had wrong)

The four hands, worked from the logs and the originals: a seat not in riichi draws a
tile that completes its hand with a yaku, declares a closed kan (2010, 2018) or an
added kan of another tile (2012, 2017) instead, draws its replacement tile, discards,
and wins by ron on a later discard before its next live draw (in 2012 on the very
tile it declined). The originals match the conversion: these rons were allowed by the
server. The engine refused them because `Rules.temporaryFuritenOnDeclinedTsumo` (on
for Tenhou, from the manual's 「和了放棄…後は同巡フリテン」) made the seat furiten until
its next live draw, "surviving the kan".

**Settling the field.** check-log now tags every declined tsumo by how it was
declined and, run with the field off, every chance to ron that the field would
refuse before the seat's next live draw (`dt_<how>_offered`, `_ron`, `_passed`). Every
Tenhou game of 2009–2026 (2,512,433 games, 26,822,615 hands) and every Mahjong Soul
game of 2019–2026 (4,113,772 games, 43,212,223 hands; Throne 2025 excluded, as
before) was re-run that way:

| | Tenhou 2009–26 | Mahjong Soul 2019–26 |
|---|---:|---:|
| tsumo declined by a discard | 21,431 | 28,065 |
| … by declaring riichi | 9,579 | 22,215 |
| … by a closed or added kan | 188 | 458 |
| a chance to ron before the next live draw, after a discard or riichi | **0** | **0** |
| … after a kan | 6 (2010 ×2, 2012, 2017, 2018, 2021) | 14 (Jade 2021–25, Throne 2023–24) |
| … taken | 4 | 12 |
| … passed | 2 | 2 |

Why the first rows have no chances at all: the 14 tiles held when a tsumo is legal
are a winning hand, so after discarding any tile `T` of them the 13 left wait on `T`
(with `T` back they win). The seat is then own-discard furiten on `T` until its hand
changes, which before its next live draw only a call can do, and a call ends
temporary furiten too (`temporaryFuritenEndsOnCall`, on for both). So a tsumo
declined by a discard or a riichi can never be followed by a ron the field would
refuse: the manual's sentence is true of Tenhou and needs no rule of its own. The
field can show only after a kan, where the seat's 13 tiles change, and there the
Tenhou records have the seat ron 4 times out of 6. The 2 passes (2010 and 2021) are
both in South 4, by a seat that had declined the tsumo itself in the same
situation, and the 2021 chance follows the 2010–18 rons, so nothing suggests a rule
change at a known date. Mahjong Soul (field already off) shows the same: 12 of its 14
chances after a kan were taken. The "survives the kan" detail and the field are both
wrong for Tenhou as far as any record can show.

Decision: `temporaryFuritenOnDeclinedTsumo` is **off for both presets** (Tenhou
changed). The field is kept as the strict reading of the manual (furiten through the
kan's replacement draw until the next live draw) for anyone who wants it. A
replacement draw still does not end temporary furiten in general (with
`temporaryFuritenEndsOnCall` on, nothing in the presets can show the difference
either way). With the default changed, the re-run's four "against" hands pass and
nothing else changes (Tenhou differences other than the documented old-rule and
defective-record ones: 0).

Tests: `ReviewBTests.declinedTsumoThenAnkan` (both presets ron after the kan; the
strict field still makes the seat furiten through the replacement draw) and
`declinedTsumoByDiscardIsOwnDiscardFuriten` (the structural fact above, under both
presets and the strict field). The scenario `declined_tsumo_outside_riichi` expects
the old Tenhou behaviour; it is now a known issue (`disputedScenarios`), and its
correction is described below.

## 2. Directed coverage

### How

`mj selfplay --scenario NAME` (`Sources/mj/Directed.swift`). In a directed game some
hands are **arranged**: a `WallBuilder` places chosen tiles in chosen wall slots (a
seat's 13, particular live draws, replacement tiles) and shuffles the rest of the 136
in, every choice drawn from an RNG keyed on (game seed, hand number), so the kinds,
seats, shapes and the rest of the wall differ in every hand. In an arranged hand each
seat is a scripted `DirectedBot` with a goal ("discard these kinds first", "never
win", "call everything", "kan everything", "discard only terminals and honours",
"keep these kinds"); it sees only its masked events and its `PlayerView`, and
re-derives its goal from the scenario, the seed and the hand number at each
`start_kyoku`. Hands that are not arranged are ordinary seeded walls played eager, so
games move on and end normally. The trace names the scenario (`scenario NAME`, a new
optional header line of trace version 1), and `GameState` takes the wall source
(`GameState(rules:seed:position:walls:)`), so `mj replay` rebuilds every arranged wall
and starting position: `CommandTests.directedScenarios` plays every scenario under
both rulesets with the invariants on, requires its branches, and replays the traces
byte for byte.

| Scenario | Arranged hands | The arrangement (random parts in italics) | Goals |
|---|---:|---|---|
| `fourwinds` | 50% | each seat dealt one copy of *a wind*; in 30%, the fourth seat dealt *a closed tenpai hand* less one tile plus the wind, its first draw the missing tile | everyone discards the wind first; the fourth seat declares riichi when it can |
| `fourriichi` | 50% | every seat dealt *a closed tenpai hand* (in 30% of hands *one seat* a random hand instead) | riichi when legal, never win, never call |
| `tripleron` | 50% | *a simple 4–6 in a suit*: the three seats after the dealer dealt tanyao tenpai on it with the three shapes `k−2 k−1`, `k+1 k+2`, `k−1 k+1` (*shuffled*), the dealer holds one | dealer discards it first and never wins; the others always ron |
| `robkan` | 70% | *a terminal or honour* `x`: *one seat* dealt all four, *another* a kokushi tenpai of the 12 other kinds with *a pair* (waiting only on `x`) | kan every time; the kokushi seat always wins (Mahjong Soul robs the closed kan; Tenhou may not) |
| `pao` | 70% | *one seat* dealt two of each dragon; the two copies left of each dragon dealt to the other three seats, two kinds each (*shuffled*) | the collector calls everything, keeps dragons, always wins; the others discard their dragons first, never call or win |
| `nagashi` | 70% | *one seat* (in 15% *two*) dealt 13 terminals and honours, and *45% of its live draws* replaced by terminals or honours | it discards only terminals and honours; nobody calls or wins; the others riichi in *half the hands* |
| `fourkans` | 70% | *one seat* dealt *three quads and a single*, the three replacement tiles the single's other copies; in 40%, one quad short, its fourth copy dealt to *another seat* | kan everything, keep those kinds, always win; the feeder discards that tile first; nobody else kans |
| `endgame` | – | every game starts at *an all-last position* (South 4 or *a West hand*) with *scores* of seven shapes (dealer first past 30,000; another seat past it; nobody near it, twice as likely; a seat near zero; dealer just below; a tie for first), or (5 in 12) *before all last* with *a seat on 1,000 or 2,000*; *honba 0–3, sticks 0–2* | eager |

Runs (seeds from 7,000,000, a different 100,000 block per scenario): every scenario
under Tenhou rules through `tools/libriichi_diff.sh` (now taking `scenario:NAME` and
extra selfplay arguments; `--check` added) and under Mahjong Soul rules through the
new `tools/mercury_diff.sh` (selfplay `--requests` with `--check`, `./mj` and
Mercury answering, both compared). Games: fourwinds, fourriichi, tripleron and
nagashi 200 each, robkan 600, pao 1,500, fourkans 500, endgame 6,000, per ruleset.

Everything passed its invariants (`--check`: view folds, answer order, points and
tiles, replay of every trace to the same bytes, check-log of every log): 0 FAIL lines
in 18,800 directed games, after the `ViewFolder` fix below (one Mahjong Soul `endgame`
game failed the fold before it; that run was repeated with the fixed binary).

### Coverage

Times each branch was reached (hands; "end" branches are games). Directed: 9,400
games and 46,505 hands under Tenhou rules, 9,400 games and 37,006 hands under Mahjong
Soul's (fewer hands: its yakuman end games sooner). The gate's eager and random games
(section 3, Tenhou) are shown for comparison: they reach almost none of the first
block.

| Branch | Directed, Tenhou | Directed, Mahjong Soul | Gate eager (50,000) | Gate random (50,000) | How (scenario) |
|---|---:|---:|---:|---:|---|
| four winds (`abort_suufon_renda`) | 2,480 | 2,480 | 4 | 0 | fourwinds |
| … with riichi on the fourth wind (stick paid) | 720 | 720 | 0 | 0 | fourwinds (30% of arranged hands) |
| four riichi (`abort_suucha_riichi`) | 1,756 | 1,752 | 0 | 0 | fourriichi |
| triple ron: Tenhou aborts (`abort_sanchahou`) | 2,551 | – | 3 | 0 | tripleron |
| triple ron: Mahjong Soul pays three (`ron_x3`) | – | 937 | – | – | tripleron |
| robbed closed kan (kokushi) | 0: **not possible** under Tenhou rules | 597 | 0 | 0 | robkan (under Tenhou the same 600 games exercise the refusal: an `ankan` of the kokushi seat's only wait, never offered as a ron) |
| pao, tsumo | 608 | 608 | 3 | 0 | pao |
| pao, ron from a third seat | 1,042 | 1,043 | 10 | 0 | pao |
| pao, ron from the liable seat | 502 | 502 | 7 | 0 | pao |
| nagashi | 1,683 | 1,683 | 0 | 0 | nagashi (also 123 in all last, and two nagashi seats in some) |
| four kans by one seat | 513 | 490 | 2 | 0 | fourkans (suukantsu wins 438 / 419) |
| end: below zero | 4,291 | 4,627 | 5,553 | 1 | pao, robkan, endgame |
| … in all last | 363 | 330 | 1,007 | 0 | endgame |
| end: dealer first (agari- or tenpai-yame) | 1,353 | 1,272 | 8,284 | 102 | endgame |
| end: target reached | 3,534 | 3,279 | 35,890 | 484 | endgame |
| … in the extension | 1,032 | 1,025 | 2,260 | 217 | endgame |
| end: extension over | 222 | 222 | 273 | 5,563 | endgame (West starts) |
| end with sticks left (to first place) | 1,182 | 1,119 | 1,647 | 69 | endgame |
| end with tied scores (seat order) | 1,014 | 1,458 | 686 | 6,030 | pao, robkan |
| all last: dealer repeat continues | 3,415 | 2,926 | 25,849 | 456 | endgame |
| … after an abortive draw | 727 | 459 | 489 | 21 | fourwinds, fourriichi |
| … dealer not first | 2,240 | 2,032 | 23,440 | 113 | endgame |
| … dealer first below the target | 448 | 435 | 1,920 | 322 | endgame |
| … another seat at the target (repeat has priority) | 1,595 | 1,403 | 19,443 | 2 | endgame |
| all last: deal passes into the extension | 532 | 513 | 3,759 | 5,868 | endgame |
| … within the extension | 684 | 677 | 3,349 | 17,163 | endgame |
| zero points, game continues | 295 | 286 | 219 | 0 | endgame (seat on 1,000/2,000) |

Not reachable this way, and why: the robbed closed kan under Tenhou (its rules do not
allow it; the refusal is what the 600 Tenhou robkan games test), and the end at North 4
(`extension_over` from North): with either preset's extension only the West round can
be played, so a hanchan ends before North (East-only games, which reach the South
extension, are not a preset). Also reached in passing: chankan 113 / 86, rinshan 119 /
95, haitei, houtei, double ron, riichi kan, double riichi, kyuushu, four-kan abort (by
two seats) 40 / 22.

### Differences found

Mahjong Soul, Mercury: every directed request (2,410,111 `legal` and 20,398 `score`
lines over the eight scenarios) answered identically by Mercury and `./mj`. `./mj`
against the round engine: 967 riichi offered under 1,000 points (`lowpoints`) and 5
fifth-copy riichi on a wait whose copies are the seat's own closed kan (e.g.
`133338888m5z` + `5z` with `a2222m`: riichi on `8m` waits only on `2m`); the line
protocol keeps `spec/formats.md`'s strict rule, the round engine follows the real-log
ruling. Both known; nothing else.

Tenhou, libriichi: board replay of 46,505 directed hands, 3,272 hands differ, all
named:

| Board difference | Hands | Explained |
|---|---:|---|
| `triple_ron_abort` | 2,551 | known (NOTES): libriichi has no three-ron abort |
| four-winds riichi stick | 720 | known (`four_winds_before_reactions`): libriichi aborts before accepting the riichi; the engine pays the stick, as both clients' records do (real-log ruling 7). One of these is a `fourriichi` hand whose four riichi discards were all `N`: four winds comes first |
| `chiihou_after_own_daiminkan` | 1 | **new, libriichi-side**: a seat's first-turn open kan, then a winning replacement draw. libriichi's `state/update.rs` `daiminkan` clears `can_w_riichi` only for the other seats, so the caller's rinshan tsumo before its first discard is scored chiihou (32,000); any call voids chiihou, and the engine pays rinshan + 4 dora, 8,000 |

Legality rows (20,445,364): every differing row in a known category (the NOTES ones and
the earlier new ones, `announcement_shanten`, `ankan_eager_commit`,
`four_concealed_shanten`); **0 unexplained**. The classifier now skips, and counts,
the rows of the 3,272 hands libriichi did not replay (it writes none for them).

`declined_tsumo_furiten`, the new category of the first differential run, is gone with
the default change (none in any run here).

## 3. The gate

`tools/libriichi_diff.sh` in ten parallel pipelines per bot kind, 50-game batches,
Tenhou rules (seeds 1,000,000–1,049,999 eager, 2,000,000–2,049,999 random), board
replay and the classified legality rows; plus the directed games of section 2.

| | Games | Hands | Board-replay hands that differ | Legality rows | Unexplained rows |
|---|---:|---:|---:|---:|---:|
| eager | 50,000 | 680,718 | 2 (`triple_ron_abort`) | 359,166,872 | 0 (2 rows, 1 hand, named below) |
| random | 50,000 | 598,141 | 0 | 373,217,700 | 0 |
| directed | 9,400 | 46,505 | 3,272 (table above) | 20,445,364 | 0 |
| **total** | **109,400** | **1,325,364** | **3,274, all named** | **752,829,936** | **0** |

The eager games had three triple-ron aborts; the third agrees with libriichi because it
fell on the last discard with all four seats tenpai, where libriichi's exhaustive draw
pays nothing and repeats the dealer too.

**The one new legality difference** (eager, seed 1,048,009, hand 4, seat 2, a `tsumo`
row): in riichi with `1235r5567888s 66z` (waits `5s`, `8s`, `6z`), the seat draws the
fourth `8s`, a winning tile. The engine offers `ankan:8s` with the tsumo; libriichi
does not. libriichi's `check_ankan_after_riichi` (`algo/agari.rs`, "Using Tenhou rule
here") refuses to kan any tile the hand waits on; `spec/formats.md` compares the
structural wait kinds before the draw and after the kan, and after this kan the hand
`1235r5567s 66z` still waits on `5s`, `8s` (a fifth copy, as in the fifth-copy rulings)
and `6z`. A rule choice that no record can decide (a seat that kans its winning tile
in riichi gives up the win and is furiten for the rest of the hand, so nobody does it);
the engine keeps the spec, the classifier names it `riichi_ankan_waited_tile`
(re-classifying the regenerated batch gives 0 unexplained), and scenario 4 below
pins the engine's choice.

Rows by category, eager / random (hands in brackets): `visible_exhausted_waits`
15,543,020 (383,127) / 448,003 (34,206); `furiten_on_window_event` 1,133,401
(487,524) / 16,412 (10,704); `cached_waits` 1,118,320 (415,947) / 9,747 (6,254);
`temporary_furiten_reset` 281,674 (198,306) / 6,371 (5,973); `announcement_shanten`
248,900 (134,385) / 40,995 (38,854); `kakan_eager_commit` 39,588 (30,632) / 16,435
(15,937); `ankan_eager_commit` 14,096 (12,462) / 5,274 (5,192);
`four_concealed_shanten` 8,441 (1,236) / 688 (152); `riichi_ankan_waited_tile` 2 (1) / 0.
All as described in `docs/notes/p3-CD.md` and `agpl/libriichi-check/NOTES.md`. No
selfplay invariant was on in the gate (as in the design: board replay and rows); the
invariants ran in the directed games and in `swift test`.

The other gate items: every scenario passes except the one disputed by the evidence
(below); corpus 12,439 of 12,439; council review not part of this brief.

## Real-log regression slice

With the final binary (`tools/reallogs.py --mj <final mj>`, default rules per site):

| Shard | Games | Hands | Differences |
|---|---:|---:|---|
| tenhou-houou-2024 (`--rules tenhou`) | 184,424 | 1,952,493 | **0** |
| majsoul-throne-2024 | 288,341 | 3,038,033 | 11 `log_defect:unbalanced_deltas` (the Throne pao converter defect, as before) |
| majsoul-jade-2024 | 933,050 | 9,780,910 (all reduced format) | **0** |

Nothing regressed: the same results as the campaign's final runs.

The all-years runs of section 1 double as a wider check (check-log at the final
engine semantics; the binary for them predates only the `ViewFolder` fix and the
directed code, neither of which check-log uses):

- Tenhou 2009–2026 (`--set temporaryFuritenOnDeclinedTsumo=false`, now the default):
  2,512,433 games, 26,822,615 hands. Differences: 179 `header` (2009–10 games with
  no automatic agari-yame, old rules, as before), C2 (defective original), C7 (2),
  C8 (2), C9 (the 2022 red-five slip). The four declined-tsumo rons of 2010–18 pass.
- Mahjong Soul 2019–2026: 4,113,772 games, 43,212,223 hands, shard for shard the same
  differences as the campaign's final table (`docs/notes/p3-reallogs.md`), all
  explained there: the 2019–20 dragon mapping (180 in the four 2019–20 shards), the
  pao deltas that do not add up (24 in Throne 2022–24, 2 in Jade 2020), the Throne 2026
  dropped pao `hora`, and C3; the Jade 2023 four-winds riichi hand passes, as it did
  once that ruling was settled.

## Changes

Engine (`Riichi`, no Foundation):

- `Rules.tenhou.temporaryFuritenOnDeclinedTsumo` → **false** (section 1); its doc
  comment and design §4.2 say why; `spec/rules.md` §5 item 13 is new.
- `GameState` takes an optional wall source, `walls: (seed, hand) -> Wall`, used for
  every hand (`GameState(rules:seed:position:walls:events:observe:)`, and a `walls:`
  argument on the position initializer). Unset, nothing changes.

- **Bug fixed: `ViewFolder` under Mahjong Soul's chained added kan.** With
  `owedDoraAtChainedAddedKan` (added by the real-log campaign) the owed indicator of
  the seat's earlier added kan is shown right after a further `kakan`, before that
  kan's robbing window. The folder committed a pending kan on any event that followed
  it, so it took that `dora` for the commit: while the window was open every seat's
  folded table showed the kan made, the drawn tile gone, one live tile fewer and no
  open window, and a robbed kan was then folded as made. Found by the view-fold
  invariant in one directed `endgame` game under Mahjong Soul (`--seed 7701379`; an
  eager seat added a kan, drew the fourth of another pon and added that too, and it
  was robbed). A pending kan now commits on the first event after it that is not a
  `dora`; a committing kan's own indicator is followed by its replacement draw, which
  commits it, so nothing else changes. Only the fold uses `ViewFolder` (players get
  `PlayerView` from the engine), so no game, log or payment was affected. Test:
  `GameTests.foldChainedAddedKanOwedDoraBeforeRob` (robbed and not robbed, every seat,
  every step; it fails on the old folder).

No scoring, legality or flow difference in any directed game, in the gate, or in the
real-log re-runs was the engine's.

`mj` and tools:

- `selfplay --scenario NAME` and `Sources/mj/Directed.swift` (section 2); the trace's
  optional `scenario` line; `replay` honours it.
- Coverage report: the game-flow branches are split
  (`all_last_repeat_abort`/`_not_first`/`_below_target`/`_other_at_target`,
  `all_last_advance_into_extension`/`_in_extension`, `end_target_in_extension`,
  `end_below_zero_all_last`, `end_sticks_left`, `end_rank_tie`, `zero_points_continue`,
  `nagashi_all_last`) and `abort_suufon_renda_riichi` is counted. The flow branches are
  read from the position of the hand that ended (the step that ends a hand also deals
  the next).
- check-log: `declined_tsumo_{discard,riichi,kan}` and `dt_*` tags (section 1); a
  declined tsumo is now forgotten only at the seat's next live draw (or its call), not
  at a replacement draw.
- `tools/libriichi_diff.sh`: `scenario:NAME`, extra selfplay arguments, `MJ=`; the
  selfplay output (coverage, invariants) is kept. `tools/classify_libriichi.py` skips
  the engine rows of a hand libriichi failed to replay (it writes none for it) instead
  of stopping on the misaligned rows, and counts them. `tools/libriichi_diff_summary.py`
  takes any batch name, sums coverage and FAIL lines, and names the board differences
  (`triple_ron_abort`, the four-winds riichi stick, the libriichi chiihou of section 2);
  anything else is printed as unexplained.
- `tools/mercury_diff.sh` (new): the Mercury cross-check of any self-play, with the
  two known line-protocol differences named.

Docs: `spec/rules.md` §3 and §4 had nine "Settled from real logs" sentences pasted
onto the wrong items by the real-log campaign (onto §3 and §4 items that share a
number with the §5 items they belong to); removed there (they are in §5). README
mentions `--scenario`.

Tests: `ReviewBTests.declinedTsumoThenAnkan` (rewritten),
`ReviewBTests.declinedTsumoByDiscardIsOwnDiscardFuriten` (new),
`CommandTests.directedScenarios` (new; both rulesets),
`GameTests.foldChainedAddedKanOwedDoraBeforeRob` (new); `ScenarioTests` lists
`declined_tsumo_outside_riichi` (Tenhou run) as disputed.

## Scenario descriptions for the scenario writers

Prose only; no `.scn` file was written or edited.

1. **Correct `declined_tsumo_outside_riichi`, Tenhou run.** Same wall and steps up to
   seat 1's `4s`. Under Tenhou too seat 0 is not furiten after its ankan and
   replacement draw (`assert_furiten 0: false`, `assert_legal 0: ron`), rons the
   `4s`, and the expectation is the Mahjong Soul run's: haku 1 han, 80 fu (the pair
   reading), dealer ron 3,900 from seat 1, honba 1, dealer repeats. The title and the
   INDEX line should say that declining a tsumo by a kan leaves no temporary furiten
   on either client (real logs: Tenhou 4 rons in 6 chances).
2. **`declined_tsumo_kakan_ron_same_tile`, both.** Seat 0 has an open pon of `2s` and
   holds `2345s 345m 678p` (waiting `5s`: the nobetan's other end, `2s`, would be a
   fifth copy). It draws `5s`: tsumo is legal (tanyao, kuitan on). It declares the
   added kan of `2s` instead (nobody can rob it), draws an unrelated replacement
   tile and discards it, keeping `3455s 345m 678p`, still waiting on `5s`. Another
   seat discards `5s` before seat 0's next draw: seat 0 is not furiten and may ron on
   both rulesets (tanyao), and the kan's owed indicator, shown just before seat 0's
   discard, counts for the ron on both. (The 2012 Tenhou record is this shape: a ron
   on the very tile declined.)
3. **`declined_tsumo_by_discard_own_furiten`, both.** Seat 0 (not in riichi) holds
   `23456m 456p 789s 55z`, waiting `1m`/`4m`/`7m`, and draws `7m` (menzen tsumo
   legal). It declines by discarding `2m`, leaving `34567m`: waits `2m`/`5m`/`8m`, one
   of them the tile it just discarded. The next seat discards `5m`: seat 0 is furiten
   (own discard) and is not asked; at its next draw it may still tsumo a `5m` or `8m`.
   This holds whatever `temporaryFuritenOnDeclinedTsumo` says; the scenario documents
   why the field never shows after a discard.
4. **`riichi_ankan_of_winning_tile`, both (pins a rule choice).** Seat 0 in riichi
   holds `1235r5567888s 66z`, waiting `5s`, `8s` and `6z` (readings `555s 678s 88s
   66z` and `55s 567s 888s 66z` give shanpons). It draws the fourth `8s`, a winning
   tile (tsumo legal). By `spec/formats.md` (the structural wait kinds before the
   draw and after the kan) the closed kan of `8s` is legal too: after it,
   `1235r5567s 66z` still waits on `5s`, `8s` (now a fifth copy) and `6z`. Expect
   `ankan:8s` among the legal actions on both rulesets, and riichi furiten after it
   (a winning draw declined in riichi). libriichi forbids this kan ("cannot kan a
   waited tile"); no record can show either client's choice (a seat that does it
   gives up its win), so the scenario should be marked unverified.

5. **`no_chiihou_after_own_daiminkan`, both.** A non-dealer seat, before its first
   discard and with no call made yet, makes an open kan of the dealer's first discard
   and wins on the replacement tile: rinshan kaihou (plus whatever else the hand
   has), **not** chiihou, because a call (its own included) ends the first go-around.
   libriichi scores this chiihou (section 2); the engine does not.

Every other difference found in the directed runs and the gate is a known one.

## Open

- Still undecided by any record (unchanged): pao on a composite yakuman, the winning
  tile of a heavenly hand, kan dora on a rinshan win after an open kan, leftover sticks
  at the end of a game; now also the riichi kan of a waited tile (section 3).
- C3: which half of the record (hand or result) is wrong cannot be told from the
  reduced format.
- Disconnection is not modelled (by design): Tenhou's substitute discard ignores
  kuikae and its exhaustive draw pays a dropped seat nothing. check-log cannot see a
  `BYE` in mjai; a converter that kept it would let check-log name these cases.
- The scenario writers' items above, and `scenarios/INDEX.md`'s line for
  `declined_tsumo_outside_riichi` (still "unverified", Tenhou furiten).
- The gate's council review of the code is outside this brief.
