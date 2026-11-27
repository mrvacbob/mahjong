# Phase 3 real-log campaign — notes

Brief: `docs/briefs/p3-reallogs.md`. Nothing is staged or committed. The game records
and everything derived from single games (per-game result lines, examples, tar
indexes, helper scripts) are in `/Volumes/Psyche/mahjong/work/reallogs/`, outside the
repository. Cases are named C1, C2, …; their game ids are listed in
`/Volumes/Psyche/mahjong/work/reallogs/cases.md`, outside the repository. No player
names, ids or excerpts of the records are in the repository.

## Result

- **Every game of every shard was checked** (all years, both sites, run 2 below):
  Tenhou houou 2009–2026, **2,512,433 games, 26,822,615
  hands**; Mahjong Soul Throne and Jade 2019–2026, **4,113,772 games, 43,212,223
  hands** (Throne 2025 excluded: it is Tenhou data). Per shard below.
- **Tenhou 2023–2025** (`--rules tenhou`): 532,098 games, 5,637,560 hands,
  **0 differences** with the final binary (one converter omission, a missing
  `reach_accepted` before a four-kan abort, is now a named convention).
- **Mahjong Soul Throne 2023–2024 and Jade 2023–2025**: 3,127,377 games, 32,829,794
  hands: **1 unexplained difference** (case C3, a reduced-format Jade hand) and 17
  log defects (unbalanced Throne pao deltas), the rest named conventions; the 69
  Throne pao rons the converter leaves without a `hora` are inferred and check.
- **Throughput**: 1,450–1,650 games/s (15,000–17,500 hands/s) on the 12-core machine
  for full-format shards when the run had the machine to itself (run 1 Tenhou 2023:
  1,650 games/s; Throne 2024: 1,621), about 1,300–1,400 games/s for reduced-format
  Jade (one hand in eight needs the hidden-indicator search; run 1 Jade 2023: 1,399
  games/s, 14,683 hands/s). Run 2's figures in the
  table below are lower where two campaigns shared the machine.
- Defaults changed from evidence: Mahjong Soul `openKanDoraBeforeRon`,
  `fifthCopyTenpaiAtDraw`, `riichiOnFifthCopyWait`, `temporaryFuritenEndsOnCall`, and
  a new field `owedDoraAtChainedAddedKan`; Tenhou `riichiOnFifthCopyWait` and
  `temporaryFuritenEndsOnCall`; both `fourWindsRiichiStickPaid`. The other rulings
  confirmed the existing defaults with counts; four could not be decided.
- Corpus **12,439 of 12,439**; `swift test` **83 tests in 21 suites pass**, with 30 known issues from the 12 scenarios
  whose expectations the changed defaults make wrong (list below).
  No Foundation in `Riichi` or `RiichiMjai`.
- Both C/D reviews (Gemini: 14 items; Codex: 7) are fixed or rebutted, each with a
  test where one can be written (section at the end).

## The tool

- `mj check-log [--rules tenhou] [--set field=value]... [--json] [--stdin] FILE...`.
  `--set` overrides any `Rules` field by name (Booleans `true`/`false`, the point
  fields and `doubleWindPairFu` as numbers, `length` as `east`/`south`); invalid
  rules (`Rules.isValid`) are refused. `--stdin` reads games framed as
  `NAME LENGTH\n` + bytes; `--json` prints one line per game: differences
  `[hand, event, category, message]`, named conventions, unchecked counts, and
  situation tags `[hand, tag]` (for the rulings and the frequency table).
- A difference ends the hand's check (the next hand is checked from its own
  header; only the header check of the next hand is skipped), not the game's.
- `tools/reallogs.py --mj MJ --rules R --out DIR [-j N] [--set ...] [--only NAMES]
  [--all-games] TAR...` streams each tar (stdlib `tarfile` and `compression.zstd`),
  feeds parallel workers, and writes `DIR/<shard>.summary.json` (games, hands,
  throughput, differences by category with five examples each, conventions,
  unchecked counts, hands per tag) and `DIR/<shard>.games.jsonl`. With `--only` it
  seeks to the named members instead of reading the whole tar. `--report DIR`
  merges summaries. Output directories must stay outside the repository.
- Games are tried as East–South; a game whose flow fails that way is re-tried as an
  East-only game (rooms mix both and the logs do not say which; tagged `east_game`).

### Named conventions (counted, not errors)

| Name | What the log does | Where |
|---|---|---|
| `ura_on_multi_ron` | every winner of a multi-ron carries the riichi winner's `ura_markers` | both sites |
| `suucha_riichi_no_reach_accepted` | no `reach_accepted` for the fourth riichi before the four-riichi abort (the stick is paid: the next header shows it) | both |
| `suukaikan_no_reach_accepted` (generalised from the above after run 2) | the same before a four-kan abort on the fourth kan's riichi discard | Tenhou 2024, 1 |
| `dora_before_dahai` | owed kan `dora` before the kan seat's `dahai`, where the rules reveal it after the window | Mahjong Soul under the old default only; 0 now that the default is settled (below) |
| `chankan_owed_dora_unlogged` | the owed indicator shown at a chained added kan is missing when that kan is robbed (the payment counts it) | Mahjong Soul |
| `hidden_indicators` | a kan or ura indicator the log never shows: every assignment of the unseen tiles is tried, and one reproduces the payment | both |
| `missing_hora_inferred` | the Throne converter drops the `hora` of a ron under pao: the hand stops after the winning discard; the seats that may ron are taken to have won, and the next header (or the game's end) checks it | Mahjong Soul Throne |
| `lite_*` | the reduced format (below) | Mahjong Soul Jade |

### The reduced ("lite") format

All Jade games from 2021 (and 23 of every 300 in 2020) were converted by a tool
that writes much less: no `deltas` or `scores` on `hora`/`ryukyoku`, no `dora`
events, no `ura_markers`, the dealer's first draw dealt as a 14th tile, and several
fields wrong. check-log handles it as follows, each counted:

- `lite_no_dora`: the engine's `dora` events have no counterpart; kan and ura
  indicators are unknown, so the point changes are checked against the next
  `start_kyoku` by searching the unseen tiles for indicators that reproduce it
  (`lite_hidden_indicators`; grouped by effect on the winners, at most 20,000 tries).
  The last hand of a game has no next header: only "the game ends here" is checked
  (`lite_last_hand_points` unchecked).
- `lite_call_target`: `chi`/`pon`/`daiminkan` `target` is the caller itself, not the
  discarder; `lite_chankan_target`: a robbed kan's `hora.target` is garbage.
- `lite_ankan_as_kakan`, `lite_kakan_as_ankan`: closed and added kans swap labels.
- `lite_reach_accepted_before_ron`: `reach_accepted` written for a riichi whose
  discard was ronned (no stick is paid: the next header shows it).
- `lite_abort_names_swapped`: `reach4` is written for four winds and `kaze4` for four
  riichi.

## Runs

- **Run 1**: old defaults, Tenhou 2023–25, Mahjong Soul Throne 2023–25 and Jade
  2023–25. The baseline for the changed defaults.
- **Run 2**: new defaults, every shard 2009–2026, a result line for every game.
- **Run 3**: the final binary (pao-ron inference, the generalised abort convention,
  the chained-kan tag) over every Throne shard and Tenhou 2024, which replace run 2's
  summaries for those shards.
- **Run 4**: the final binary over Jade 2019–20 (full-format games in them).
- **Flip runs**: games carrying a ruling's tag, re-run with one field flipped.

Final results per shard (run 2, with run 3 for Throne and Tenhou 2024 and a re-run of
Jade 2019–20 with the final binary). The four-winds riichi stick was settled after
these runs: the Tenhou `header` differences of 2014, 2016, 2017, 2018 and 2022 and
the Jade 2023 `sequence:reach_accepted/ryukyoku` are those hands, and all pass with the
new default (re-run: 0 differences). "Differences" are categories; every one is
explained in the next sections.

| Shard | Games | Hands | Reduced format | Games with a difference | Differences |
|---|---:|---:|---:|---:|---|
| tenhou-houou-2009 | 6,897 | 74,228 | 0 | 35 | header 56 |
| tenhou-houou-2010 | 70,228 | 755,507 | 0 | 119 | header 123, illegal:ron 1, sequence:hora/tsumo 1 |
| tenhou-houou-2011 | 100,814 | 1,090,233 | 0 | 0 | – |
| tenhou-houou-2012 | 116,985 | 1,262,637 | 0 | 2 | illegal:dahai 1, illegal:ron 1 |
| tenhou-houou-2013 | 131,838 | 1,422,580 | 0 | 1 | illegal:dahai 1 |
| tenhou-houou-2014 | 141,132 | 1,519,986 | 0 | 1 | header 1 |
| tenhou-houou-2015 | 152,278 | 1,635,472 | 0 | 0 | – |
| tenhou-houou-2016 | 159,663 | 1,709,149 | 0 | 1 | header 1 |
| tenhou-houou-2017 | 169,382 | 1,807,796 | 0 | 2 | illegal:ron 1, header 1 |
| tenhou-houou-2018 | 173,546 | 1,848,988 | 0 | 2 | illegal:ron 1, header 1 |
| tenhou-houou-2019 | 171,628 | 1,825,404 | 0 | 1 | ryukyoku.deltas 1 |
| tenhou-houou-2020 | 218,816 | 2,328,094 | 0 | 1 | sequence:ryukyoku/reach_accepted 1 |
| tenhou-houou-2021 | 187,313 | 1,993,456 | 0 | 1 | ryukyoku.deltas 1 |
| tenhou-houou-2022 | 167,627 | 1,782,346 | 0 | 2 | illegal:kakan 1, header 1 |
| tenhou-houou-2023 | 168,777 | 1,791,077 | 0 | 0 | – |
| tenhou-houou-2024 | 184,424 | 1,952,493 | 0 | 0 | – |
| tenhou-houou-2025 | 178,897 | 1,893,990 | 0 | 0 | – |
| tenhou-houou-2026 | 12,188 | 129,179 | 0 | 0 | – |
| majsoul-jade-2019 | 13,581 | 142,106 | 1,117 | 68 | illegal:dahai 57, sequence:pon/tsumo 12, illegal:reach 2 |
| majsoul-jade-2020 | 55,749 | 586,556 | 26,616 | 31 | illegal:dahai 26, illegal:hora 2, illegal:reach 2, log_defect:unbalanced_deltas 2, sequence:pon/tsumo 2 |
| majsoul-jade-2021 | 152,801 | 1,609,650 | 152,801 | 0 | – |
| majsoul-jade-2022 | 426,892 | 4,480,446 | 426,892 | 0 | – |
| majsoul-jade-2023 | 728,090 | 7,641,470 | 728,090 | 2 | lite_header 1, sequence:reach_accepted/ryukyoku 1 |
| majsoul-jade-2024 | 933,050 | 9,780,910 | 933,050 | 0 | – |
| majsoul-jade-2025 | 934,144 | 9,792,420 | 934,144 | 0 | – |
| majsoul-jade-2026 | 86,222 | 903,986 | 86,222 | 0 | – |
| majsoul-throne-2019 | 7,603 | 80,963 | 0 | 23 | illegal:dahai 20, sequence:pon/tsumo 2, illegal:reach 1 |
| majsoul-throne-2020 | 20,916 | 221,659 | 0 | 49 | illegal:dahai 47, sequence:pon/tsumo 4, ryukyoku.deltas 1, illegal:reach 1, illegal:hora 1 |
| majsoul-throne-2021 | 40,805 | 432,924 | 0 | 0 | – |
| majsoul-throne-2022 | 158,644 | 1,679,886 | 0 | 7 | log_defect:unbalanced_deltas 7 |
| majsoul-throne-2023 | 243,752 | 2,576,961 | 0 | 6 | log_defect:unbalanced_deltas 6 |
| majsoul-throne-2024 | 288,341 | 3,038,033 | 0 | 11 | log_defect:unbalanced_deltas 11 |
| majsoul-throne-2025 | 184,424 | 407,797 | 0 | 145,924 | parse 145894, hora.deltas 22, sequence:ryukyoku/tsumo 7, sequence:ryukyoku/reach_accepted 1 |
| majsoul-throne-2026 | 23,182 | 244,253 | 0 | 1 | header 1 |

### Data defects found

- **`majsoul-throne-2025.tar` is not Mahjong Soul.** Its 184,424 members are named
  like Tenhou records (`…gm-00a9-…`), the count equals Tenhou 2024's
  exactly, 145,894 members are gzip inside zstd (`.mjson.gz.tmp`, not mjai), and the
  rest score as Tenhou games (single yakuman where Mahjong Soul doubles). Excluded
  from every Mahjong Soul figure; the driver counts such names as
  `tenhou_named_games`.
- **Throne pao rons have no `hora`** (69 hands, 2023–24): the hand stops after the
  winning discard (then `end_kyoku`, usually `end_game`). Now inferred
  (`missing_hora_inferred`); the 14 with a following hand match its header, the 55
  that end the game end it as the engine's pao payment predicts.
- **Throne pao tsumo with a dealer liable**: the liable dealer's delta is 8,000 too
  large and the deltas sum to −8,000 (17 hands, all game-ending, e.g. case C1:
  `[34000, 0, -40000, 0]`). Points cannot vanish, so this is the converter; the
  category `log_defect:unbalanced_deltas` names any delta list whose sum differs from
  the engine's. In the 51 game-ending pao tsumos with a non-dealer liable, and all 6
  that do not end the game, the log agrees with the engine (liable pays the whole
  yakuman and the honba).
- **Jade reduced format** (all of 2021–26, part of 2020): the field errors listed
  above, all handled as conventions.
- **Tenhou 2010** (case C2):
  a `hora` on a discard that completes no seat's hand; the discard just before is
  logged `8p` from-hand where a tsumogiri `9p` would be the winning tile. A converter
  slip.
- **The one unexplained Mahjong Soul difference** (case C3, Jade 2023; reduced
  format, so only the next header checks it): the winner holds `789s FFF P` with
  `pon CCC`, `chi 789p` and rons the `P`: shousangen, hatsu and chun, 4 han 40 fu,
  8,000; the next header shows 5,200 paid (3 han). No assignment of the hidden
  indicators lowers a payment, so either the reduced log's hand or its scores is
  wrong; it cannot be told which from this format.

### Older Tenhou years

- **2009 to May 2010: no automatic agari-yame or tenpai-yame.** 34 games in 2009 and
  117 in January–May 2010 go on after an all-last hand in which the dealer repeats
  and is first on 30,000 or more, where the engine and the current manual end the
  game (`header`: "should have ended (dealer_first)"); none from June 2010. One 2009
  game (case C5) plays into the North round past the West-4 cap. Old rules, not
  engine bugs; checking those years exactly would need a field for optional
  agari-yame.
- **Rons after declining a tsumo by declaring a kan, 2010, 2012, 2017, 2018** (cases
  C6, C17; one hand each): the seat draws a winning tile, declares a closed or added
  kan instead, and wins by ron before its next live draw (in 2012 on the very tile
  it declined). Tenhou's `temporaryFuritenOnDeclinedTsumo` (on, from the manual's
  「和了放棄…同巡フリテン」) makes the seat furiten until its next live draw, through
  the kan (design §4.2, from the package B review), so the engine refuses these
  rons. None in 2023–26. See "could not be decided".
- **Kuikae, 2012 and 2013** (case C7, one hand each): a `5s` discarded right after
  `chi 2s` with `34s`, and right after `chi 5sr` with `46s`. Both forbidden by the
  current rules; two hands in fourteen years. Unexplained.
- **Nagashi not paid, 2019 and 2021** (case C8): both times the dealer (seat 1)
  discards only terminals and honours, none called, and the record pays
  tenpai/noten instead. The other 4,514 nagashi hands of 2009–26 are paid as the
  engine pays them. Unexplained.
- **2022: an added kan of a red five the seat does not hold** (case C9). A converter
  slip between red and plain.
- **Mahjong Soul 2019–20** (Throne, and the full-format part of Jade): dragons the
  seat was never dealt are discarded, called, ronned on and riichi'd on (case C10),
  216 hands over the four shards: an early converter's dragon mapping.
- **Throne 2026**: one double ron in which the pao winner's `hora` is dropped and the
  other winner's kept (case C11), the pao defect above.

## Engine changes and bugs found

None of the differences was a scoring or legality bug in the hand engine: every
difference that was not a log defect was a ruling (below) on which the engine had a
`Rules` field with the wrong default, or a ruling that needed a new field. What
changed in the engine:

1. **`Rules.owedDoraAtChainedAddedKan` (new; Mahjong Soul on, Tenhou off).** Mahjong
   Soul shows an indicator still owed by the seat's earlier open kan right after it
   announces a further added kan (`kakan`, `dora`), before that kan's robbing window,
   so a chankan on the chained kan counts it. The engine revealed it only at the
   commit, and a chankan was paid one han short (e.g. 7,700 for 8,000; case C4).
   `Round.announceAddedKan` reveals it after the `kakan` event when the field is on.
2. **`Rules.riichiOnFifthCopyWait` narrowed.** When on it used to allow any
   fifth-copy wait; both clients' records show riichi only on waits whose four copies
   include the seat's own closed kan, and the Tenhou formal-tenpai rule excludes four
   concealed copies, so the field now uses the same test as `fifthCopyTenpaiAtDraw`
   (not all four concealed). The line protocol's `legal` keeps `spec/formats.md`'s
   rule (no fifth-copy riichi at all), which the corpus fixes.
3. Preset defaults changed from evidence (rulings below): Mahjong Soul
   `openKanDoraBeforeRon`, `fifthCopyTenpaiAtDraw`, `riichiOnFifthCopyWait`,
   `temporaryFuritenEndsOnCall` and the new field on; `fourWindsRiichiStickPaid` on
   for both; Tenhou `riichiOnFifthCopyWait` and `temporaryFuritenEndsOnCall` on.
4. From the reviews (section at the end): bounds on `Rules`, honba, sticks and
   scores; North 4 never wraps; an all-last abortive draw always repeats.

check-log itself had three bugs found by the campaign: `fread` on a pipe blocked
until 1 MiB arrived (deadlock with the driver; now `read`); a hidden-indicator search
that ran out of a representative tile instead of using another of the same effect;
and the lite-format chankan target test missing the second winner of a double ron.

## Rulings settled from the logs

How the counts are made. "For" counts hands that the logs check (payments, ura
counts, the next header, the event sequence) and that only the chosen value
reproduces; "against" counts hands that only the other value reproduces. Changed
defaults were counted by comparing run 1 (old defaults) with run 2 (new defaults)
hand by hand: a hand failing in run 1 and passing in run 2 is "for", the reverse
"against" (there were none: 0 hands broken by the change on either site). Unchanged
defaults were counted by re-running every game whose hands carry the situation's tag
with the field flipped (`--set`): a tagged hand that then fails is "for"; "against"
would be a hand failing in run 2 in that situation, and there are none unless stated.
Hands where both values give the same result (an indicator that adds no han, say) do
not count either way. Years 2023–2025; Mahjong Soul is Throne 2023–24 and Jade
2023–25. Example cases: C12 (row 1), C4 (row 2), C16 (row 7), C13 (row 12), C15
(row 13), C14 (row 14).

| # | Ruling | Tenhou | Mahjong Soul | Default now |
|---|---|---|---|---|
| 1 | Kan dora on a ron of the kan seat's discard after an open or added kan (the indicator and its ura) | **counted**: 1,501 for (flipped: 1,160 payments and 341 ura counts fail), 0 against | **counted**: 4,610 for (1,862 Throne payments or ura counts, 2,748 Jade next headers), 0 against | on for both (Mahjong Soul changed) |
| 1b | … on a rinshan win after an open kan | not counted: no `dora` precedes a rinshan `hora` and payments agree | same | unchanged |
| 2 | Owed indicator at a chained added kan, before its robbing window | **not shown**: 1 for (a chankan's ura count), 0 against; 4 more show no indicator there | **shown**: 15 for, 0 against | Mahjong Soul on (new field), Tenhou off |
| 3 | Multi-ron honba only to the winner nearest the discarder | 11,629 for, 0 against | 65,091 for, 0 against | unchanged |
| 3b | Multi-ron sticks to the nearest winner (no field) | consistent in 19,928 hands | consistent in 136,404 | unchanged |
| 4 | Triple ron: Mahjong Soul pays three winners, Tenhou aborts | abort: 170 for, 0 against (177 aborts) | three winners: 1,393 for, 0 against | unchanged |
| 5 | Pao: liable pays a tsumo in full with the honba; a ron from a third seat is split with the discarder, honba to the liable seat (no field) | consistent in 118 pao wins (50 tsumo, 44 from the liable seat, 24 from a third seat, 38 with honba) | consistent in 1,034 (430, 314, 290; 331 with honba), less the Throne converter defects | unchanged |
| 5b | Pao on a composite yakuman | no hand | 8 hands, none discriminates | **undecided** |
| 6 | No stick for a riichi whose discard is ronned (no field) | consistent in 145,577 hands | 871,105 | unchanged |
| 7 | Riichi on the fourth-wind discard pays its stick | **paid**: 5 for (2014, 2016, 2017, 2018, 2022), 0 against | **paid**: 1 for (Jade 2023), 0 against among 19,054 four-wind aborts | on for both (changed after the runs) |
| 8 | Four-riichi abort when the fourth riichi's discard passes, stick paid | consistent, 717 aborts | 5,413 | unchanged |
| 9 | Four-kan abort when the fourth kan's discard passes | consistent, 69 aborts (1 with a riichi on that discard, stick paid) | 726 | unchanged |
| 10 | Nagashi mangan paid as a mangan tsumo, honba not paid, sticks stay, dealer repeat by tenpai | consistent in 876 hands (338 with honba, 640 with sticks, 154 by the dealer) | 5,663 (2,013; 4,131; 1,137) | unchanged |
| 10b | All-last end test after the nagashi payments | 6 for, 0 against | 33 for, 0 against | unchanged |
| 11 | All last: a dealer repeat continues though another seat has 30,000 | 90,659 for, 0 against | 562,928 for, 0 against | unchanged |
| 11b | Extension, end beyond it | consistent: 30,999 extension hands, 584 ends | 153,264; 2,254 | unchanged |
| 12 | Formal tenpai on a fifth-copy wait (copies not all concealed) at a draw | 120 for, 0 against | 433 for (116 Throne, 317 Jade), 0 against | on for both (Mahjong Soul changed) |
| 13 | Riichi on a fifth-copy wait whose copies are the seat's closed kan | 1 for | 14 for | on for both (changed and narrowed) |
| 14 | Temporary furiten ends on the seat's own call (chi, pon or open kan, from any seat) | 226 for, 0 against | 779 for (209 Throne, 570 Jade), 0 against | on for both (changed) |
| 15 | Double yakuman (Mahjong Soul's four) | single: 269 for, 0 against | double: 702 for, 0 against | unchanged |
| 16 | Kokushi robbing a closed kan | no case | 25 for, 0 against | unchanged |
| 17 | Double-wind pair 4 fu | 2,342 for, 0 against | 12,423 for, 0 against | unchanged |
| 18 | Heavenly hand: any of the 14 tiles as the winning tile | 17 hands, none discriminates | 101, none | **undecided** |
| 19 | Temporary furiten after a declined tsumo | 4 against, each a tsumo declined by a kan (2010–18), none 2019–26; "for" cannot show in a log | 25 rons after a declined tsumo, all after a call; none discriminates | **undecided** |

`spec/rules.md` §1 rows and §5 items 2, 4, 6, 7, 8, 9 and 10 now carry these counts;
new §5 items 11 (temporary furiten and calls) and 12 (what the logs could not decide).

### Rulings that could not be decided

- **Pao on a composite yakuman** (row 5b): 8 Mahjong Soul hands, none Tenhou, none
  where the two readings pay differently.
- **The winning-tile choice on a heavenly hand** (row 18): no hand where it changes
  the payment.
- **Temporary furiten after a declined tsumo** (row 19): a log can only contradict
  the stricter rule (with a ron it refuses), never show a refused ron. Tenhou has four
  contradicting hands (2010–18), all a tsumo declined by declaring a kan, which
  suggests the kan (or its replacement draw) ends that furiten, or that declining by
  a kan does not cause it; nothing contradicts it after a tsumo declined by a
  discard. Mahjong Soul has none that the call rule does not already explain.
  Defaults unchanged (Tenhou on, Mahjong Soul off); the engine's "survives the kan"
  detail is the likely wrong part.
- **Kan dora on a rinshan win after an open kan** (row 1b): consistent with not
  counting it on both sites, but no hand found where counting it would change the
  payment.
- **Leftover sticks at the end of the game**: `end_game` carries no scores.
- **The last hand of each reduced-format Jade game**: no next header; only that the
  game ends there is checked (`lite_last_hand_points`, one per game).
- **Unexplained hands**: Mahjong Soul case C3 (one); Tenhou cases C7 (two kuikae
  discards, 2012–13) and C8 (two unpaid nagashi, 2019 and 2021).

## Scenarios whose expectations are now wrong

Listed as known issues in `Tests/RiichiTests/ScenarioTests.swift` (`disputedScenarios`)
so the suite stays green; the `.scn` files are not edited.

| Scenario (run) | Why |
|---|---|
| `formal_tenpai_fifth_copy` (mahjongsoul) | expects noten for a fifth-copy wait with copies in melds; Mahjong Soul counts it tenpai |
| `furiten_surviving_call` (both runs) | expects temporary furiten to survive the seat's call; both clients end it there |
| `open_kan_discard_ron_dora` (mahjongsoul) | expects the ron on the post-kan discard without the kan's indicator (2,000; now 7,700) |
| `open_kan_discard_riichi_ron_ura` (mahjongsoul) | same, with its ura (11,600; now 18,000) |
| `open_kan_chained_kan_discard_ron` (mahjongsoul) | same after a chained kan (3,900; now 8,000) |
| `open_kan_discard_all_pass_dora`, `open_kan_discard_called_dora`, `ippatsu_cancelled_by_kakan`, `kakan_robbing_pass_furiten`, `riichi_discard_daiminkan_cancels_ippatsu`, `suukaikan_open_kan_owed_dora` (mahjongsoul) | event order only: the owed `dora` now comes before the kan seat's `dahai` |
| `abort_suufon_renda_riichi_stick` (mahjongsoul) | expects no stick for the riichi on the fourth-wind discard; both clients pay it |

## Frequency table

Hands with each situation, from check-log's tags (engine events of every hand that
checked). Per million hands. A double ron is one hand; "pao" counts winners with a
liable seat; the Throne pao rons with no `hora` are counted once inferred (Throne
2019–24); kyuushu is the abort. "Ron on the discard after an open/added kan" is the
situation of ruling 1.

| Situation | Tenhou 2023–25 | per M hands | Tenhou 2009–26 | per M | Mahjong Soul 2023–25 | per M hands | Mahjong Soul 2019–26 | per M |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Abort: nine terminals (kyuushu) | 60,390 | 10712.1 | 278,620 | 10387.5 | 299,409 | 9120.0 | 394,114 | 9120.4 |
| Abort: four winds | 3,928 | 696.8 | 17,076 | 636.6 | 19,054 | 580.4 | 24,749 | 572.7 |
| Abort: four riichi | 717 | 127.2 | 2,688 | 100.2 | 5,413 | 164.9 | 7,061 | 163.4 |
| Abort: four kans | 69 | 12.2 | 331 | 12.3 | 726 | 22.1 | 1,012 | 23.4 |
| Abort: three rons (Tenhou) | 177 | 31.4 | 821 | 30.6 | 0 | 0.0 | 0 | 0.0 |
| Chankan (robbing an added kan) | 851 | 151.0 | 4,435 | 165.3 | 7,292 | 222.1 | 9,745 | 225.5 |
| Kokushi robbing a closed kan | 0 | 0.0 | 0 | 0.0 | 25 | 0.8 | 33 | 0.8 |
| Rinshan win | 11,549 | 2048.6 | 55,729 | 2077.7 | 72,087 | 2195.8 | 95,430 | 2208.4 |
|   after a closed kan | 5,853 | 1038.2 | 27,955 | 1042.2 | 34,893 | 1062.8 | 46,066 | 1066.0 |
|   after an open kan | 957 | 169.8 | 5,104 | 190.3 | 8,163 | 248.6 | 10,884 | 251.9 |
|   after an added kan | 4,799 | 851.3 | 22,919 | 854.5 | 29,449 | 897.0 | 39,025 | 903.1 |
| Closed kan in riichi | 56,808 | 10076.7 | 263,826 | 9836.0 | 320,886 | 9774.2 | 421,262 | 9748.7 |
| Double ron | 31,721 | 5626.7 | 148,585 | 5539.5 | 213,641 | 6507.5 | 280,358 | 6487.9 |
| Triple ron (Mahjong Soul) | 0 | 0.0 | 0 | 0.0 | 1,393 | 42.4 | 1,812 | 41.9 |
| Pao (any win) | 118 | 20.9 | 553 | 20.6 | 1,034 | 31.5 | 1,339 | 31.0 |
|   pao, tsumo | 50 | 8.9 | 267 | 10.0 | 430 | 13.1 | 557 | 12.9 |
|   pao, ron from the liable seat | 44 | 7.8 | 185 | 6.9 | 314 | 9.6 | 412 | 9.5 |
|   pao, ron from a third seat | 24 | 4.3 | 101 | 3.8 | 290 | 8.8 | 370 | 8.6 |
|   pao with a composite yakuman | 0 | 0.0 | 3 | 0.1 | 9 | 0.3 | 12 | 0.3 |
| Nagashi mangan | 876 | 155.4 | 4,516 | 168.4 | 5,663 | 172.5 | 7,603 | 175.9 |
| Four kans by one seat | 4 | 0.7 | 9 | 0.3 | 14 | 0.4 | 16 | 0.4 |
| Ron on the discard after an open/added kan | 3,877 | 687.7 | 18,698 | 697.1 | 29,159 | 888.2 | 38,784 | 897.5 |
| Fifth-copy wait at an exhaustive draw | 120 | 21.3 | 573 | 21.4 | 638 | 19.4 | 848 | 19.6 |
| (Throne pao ron with no hora, inferred) | 0 | 0.0 | 0 | 0.0 | 69 | 2.1 | 116 | 2.7 |
| Kazoe yakuman | 229 | 40.6 | 1,075 | 40.1 | 2,572 | 78.3 | 3,438 | 79.6 |
| Yakuman: chiihou | 41 | 7.3 | 215 | 8.0 | 277 | 8.4 | 387 | 9.0 |
| Yakuman: chinroutou | 32 | 5.7 | 160 | 6.0 | 233 | 7.1 | 303 | 7.0 |
| Yakuman: chuuren | 24 | 4.3 | 102 | 3.8 | 219 | 6.7 | 282 | 6.5 |
| Yakuman: daisangen | 796 | 141.2 | 3,998 | 149.1 | 6,754 | 205.7 | 8,832 | 204.4 |
| Yakuman: daisuushii | 8 | 1.4 | 35 | 1.3 | 92 | 2.8 | 126 | 2.9 |
| Yakuman: junsei chuuren | 1 | 0.2 | 7 | 0.3 | 7 | 0.2 | 10 | 0.2 |
| Yakuman: kokushi | 870 | 154.3 | 4,586 | 171.0 | 8,133 | 247.7 | 10,833 | 250.7 |
| Yakuman: kokushi 13 | 16 | 2.8 | 76 | 2.8 | 197 | 6.0 | 252 | 5.8 |
| Yakuman worth more than one (double or composite) | 15 | 2.7 | 83 | 3.1 | 1,989 | 60.6 | 2,621 | 60.7 |
| Yakuman: ryuuiisou | 30 | 5.3 | 136 | 5.1 | 276 | 8.4 | 373 | 8.6 |
| Yakuman: shousuushii | 279 | 49.5 | 1,430 | 53.3 | 2,483 | 75.6 | 3,303 | 76.4 |
| Yakuman: suuankou | 1,582 | 280.6 | 7,637 | 284.7 | 11,484 | 349.8 | 15,225 | 352.3 |
| Yakuman: suuankou tanki | 244 | 43.3 | 1,114 | 41.5 | 1,475 | 44.9 | 1,937 | 44.8 |
| Yakuman: suukantsu | 3 | 0.5 | 3 | 0.1 | 3 | 0.1 | 3 | 0.1 |
| Yakuman: tenhou | 17 | 3.0 | 85 | 3.2 | 101 | 3.1 | 135 | 3.1 |
| Yakuman: tsuuiisou | 54 | 9.6 | 281 | 10.5 | 829 | 25.3 | 1,103 | 25.5 |

## Review findings (packages C and D)

### Gemini (`docs/reviews/p3/CD-agy.md`)

All reproductions in `docs/reviews/p3/CD-agy-repro/` were re-run against the new
build: none crashes or hangs; each now reports a named error.

| # | Finding | Outcome | Test |
|---|---|---|---|
| 1 | `\uD800\u0000` traps (surrogate underflow) | Fixed: a high surrogate pairs only with `\uDC00`–`\uDFFF`; otherwise U+FFFD and the next escape is read on its own | `HardeningTests.unpairedSurrogates` |
| 2 | Deep nesting overflows the stack | Fixed: nesting deeper than 64 is a `JSONError` (skip and value) | `HardeningTests.deepNesting` |
| 3 | Bot ignoring SIGTERM hangs `stop()`; unbounded, quadratic line buffer | Fixed: `stop()` closes the pipe through its `FileHandle` (no double close), sends SIGTERM, waits 0.5 s, then SIGKILL; a reply over 1 MiB is refused (bot counted as crashed); the newline scan covers new bytes only; EINTR on read/write is retried (suggestion 14). Grandchildren of `/bin/sh -c` are not killed (no process group with Foundation's `Process`); noted, not fixed | `CommandTests.mjaiAdapterHostileBots` (fake bot modes `stubborn=N`, `flood=N`) |
| 4 | Empty log, events outside hands accepted | Fixed: `no_hands` and `outside_hand` errors (only `start_game` first and `end_game` last are allowed outside a hand) | `CommandTests.checkLogRefusesBadLogs` |
| 5 | Negative honba/kyotaku trap | Fixed in check-log (`format` error for honba or sticks outside 0…1,000 or a score beyond ±10⁸) and bounded in `RoundState.init` (`RoundState.maxCount`, `maxScore`) | same |
| 6 | `uradora_markers` ignored; omitted ura filled arbitrarily | Fixed: `uradora_markers` is read when `ura_markers` is absent; a win whose payment depends on indicators the log does not show is re-run over every assignment of the unseen tiles (`hidden_indicators`), as for the reduced format | repro no longer fails; `CommandTests.checkLogReducedFormat` |
| 7 | `ryukyoku.reason`/`tenpais`, hora fields unchecked | Fixed: `reason` (with tenhou.net names `yao9`, `kaze4`, `reach4`, `kan4`, `ron3`), `tenpais`, `hora_tehais`, and `fan`/`fu` of an ordinary hand are compared when present. `yakus` and yakuman `fan` are not (writers name and count them differently) | `checkLogRefusesBadLogs` (bogus reason) |
| 8 | Escapes not validated in skip; `try?` hides errors; loose numbers; control characters | Fixed: skipped strings are read by `string()`; control characters refused; RFC 8259 number grammar. Since parsing validates every value, the subscript's `try?` can no longer hide one | `HardeningTests.strictGrammar` |
| 9 | Duplicate keys first-wins | Fixed: last wins | `HardeningTests.duplicateKeysLastWins` |
| 10 | Wrong-typed fields ignored | Fixed: a present, non-null field of the wrong type is an `MjaiError` (malformed) | `HardeningTests.wrongTypes` |
| 11 | `ankan` with a short or mixed `consumed`; calls not checked | Fixed: `ankan` needs four of one kind; `Mjai.action` takes the offered discard and checks a call's `pai`, `target` and a `daiminkan`'s `consumed` (the adapter passes it) | `HardeningTests.callFieldsValidated` |
| 12 | `dealerRepeatBeforeTarget = false` ends the game on an all-last abort | Fixed (an abortive draw always repeats) | `GameTests.transitions` |
| 13 | Encode field order vs. design table | Not changed: the order is fixed and deterministic; the design table lists fields, not an order. Rebuttal | – |
| 14 | EINTR; `--seed -1`, `--games -1` trap; seeds above `Int.max` | Fixed: EINTR retried; `--seed` parsed as `UInt64`; `--games` must be ≥ 0 | `checkLogRefusesBadLogs` |

### Codex (`docs/reviews/p3/CD-codex.md`)

| # | Finding | Outcome | Test |
|---|---|---|---|
| 2 (blocker) | Default seeds make walls predictable to an external bot | Fixed: with any `mjai:` seat and no `--seed`, each game's wall seed and the built-in bots' seed are fresh `SystemRandomNumberGenerator` values, recorded only in the trace; `--seed` with an external bot prints a warning. Built-in bot seeds are no longer an affine function of the wall seed (`botSeed`: the sum of two unrelated SplitMix64 mixes). This changes which games a given `--seed` produces for the built-in bots | `CommandTests.externalBotSeeds` |
| 1 | Callback batching and `table.reacting` reveal another seat's offer | Fixed: the driver delivers one event per `receive` call (the view only with the last); `RoundState.view(of:)` shows `reacting` only to a seat with an action; the fold invariant compares `ViewFolder.table(asked:)` | `GameTests.viewsFoldFromMaskedEvents` (asserts `reacting == nil` for a seat not asked); driver change has no unit test (the driver is in the `mj` target) |
| 5 | Score arithmetic can trap on wasm32 | Fixed: `Rules.isValid` bounds every point setting to ±1,000,000 and the double-wind fu to 2 or 4; `RoundState.init` requires it and bounds honba, sticks (≤ 1,000) and scores (±10⁸); `check-log --set` refuses invalid rules | `GameTests.rulesBounds` (extremes fit `Int32`) |
| 4 | North 4 wraps to East 1 | Fixed: the deal passing beyond North 4 ends the game (`extension_over`) | `GameTests.transitions` |
| 6 | Custom rules recorded as `mahjongsoul` in the trace | Fixed by refusal: `playGame` throws for rules other than the two presets (trace version 1 names a preset only) | – |
| 7 (their 7) | Replay compares Strings, not bytes | Fixed: `mj replay` and `selfplay --check` compare UTF-8 bytes (the file read as raw bytes) | `CommandTests.externalBotSeeds` (a combining accent inserted into the log is a difference) |
| 3 | Referee-only files not labelled | Documented in the usage text and README | – |

## Open

- The libriichi differential run (`tools/libriichi_diff.sh`) and the Mercury
  cross-check were not re-run. Expected changes: Tenhou's `temporaryFuritenEndsOnCall`
  now matches libriichi's clearing (part of `temporary_furiten_reset`), and
  `riichi_fifth_copy_wait` (1 row) now agrees. The `--requests` dump compares the
  round engine with the line protocol, which keeps the strict fifth-copy riichi; a
  fifth-copy kan riichi would now show as a known difference there, like the
  1,000-point riichi rows.
- The built-in bots' RNG seeding changed (Codex finding 2), so `mj selfplay --seed N`
  plays different games than before; earlier recorded numbers (coverage counts,
  speeds) are not comparable seed for seed.
- The Throne converter's pao defects and the reduced Jade format limit what those
  records can say about pao rons and about the last hand of each Jade game.
