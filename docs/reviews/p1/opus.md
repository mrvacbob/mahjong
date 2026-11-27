# P1 gate review: opus

Scope: spec/rules.md, spec/formats.md (with its Decisions log), corpus/*.txt, tools/harness.py.
I ran the harness. mj-rs passes 14583/14583. tools/oracle_mj.py passes every non-legal file.
Sources: riichi.wiki was reachable for this review. I fetched riichi.wiki/Mahjong_Soul,
/Kan, /Chankan and /Ippatsu. Everything else comes from my own derivation.

Findings are ordered by severity.

---

## S1: corpus answers that are wrong under Mahjong Soul rules

### S1.1 Tenhou does not upgrade to the double-yakuman forms (score: sc910, sc918, sc3695, sc5136)

riichi.wiki/Mahjong_Soul says the dealer's 14 dealt tiles let "any tile be treated as the tsumo
tile", and that "combining tenhou with suuankou, kokushi musou, or chuuren poutou will always
score their double yakuman variations". Decision 12 instead lets the `win=` tile decide, and
says itself that this was not checked. Four cases are wrong as a result:

| case | expected now | under Mahjong Soul |
|---|---|---|
| sc910 `199m19p19s123467z +5z tenhou, honba=1` | kokushi:1,tenhou:1 yakuman=2 all:32100 total=96300 | kokushi_13:2,tenhou:1 yakuman=3 pay=all:48100 total=144300 |
| sc918 `44477m333p66s333z +6s tenhou` | suuankou:1,tenhou:1 yakuman=2 all:32000 | suuankou_tanki:2,tenhou:1 yakuman=3 pay=all:48000 total=144000 (treat 7m as the winning tile, a tanki) |
| sc3695 `11p33377888s111z +1p tenhou, honba=1` | suuankou:1,tenhou:1 yakuman=2 all:32100 | suuankou_tanki:2,tenhou:1 yakuman=3 pay=all:48100 total=144300 (7s tanki) |
| sc5136 `19m19p19s2345677z +1z tenhou` | kokushi:1,tenhou:1 yakuman=2 all:32000 | kokushi_13:2,tenhou:1 yakuman=3 pay=all:48000 total=144000 |

Chiihou cases (sc926, sc928, sc932, sc934, sc5137) are not affected. The page gives the
upgrade only for tenhou, and on chiihou the 14th tile really is a draw.

**Fix:** with `tenhou`, evaluate every one of the 14 tiles as the winning tile and keep the
best result (or, equivalently, always use the 2x form for these three families). Rewrite
Decision 12 to say this, and add a case for tenhou with chuuren, which should score
junsei_chuuren:2 plus tenhou:1 = 3. The oracle and libriichi both use the `win` tile, so this
has to be patched in both.

### S1.2 Riichi ankan: formats.md is stricter than Mahjong Soul (legal0073 to legal0078)

formats.md requires that the kan "changes neither waits nor hand interpretation".
riichi.wiki/Kan says the alternative rule, used "such as in Tenhou.net and Mahjong Soul",
allows the kan whenever the possible winning tiles do not change, even if the interpretation
changes. Okurikan is still banned on both. rules.md row 69 also says waits-only. So the
stricter rule comes only from formats.md, and mj-rs NOTES.md admits that it tightened
libriichi's waits-only check to match formats.md.

Derivation for legal0073, `23m999p33345666s draw=6s riichi=1`:
- Before the kan: 33345666s reads as 333+456+66 or as 33+345+666. In both, 23m waits on 1m or 4m.
- After ankan 6666s: 23m 999p 33+345 plus the kan. The waits are still 1m and 4m.
- Under Mahjong Soul the answer is `actions=ankan:6s,discard:6s`. legal0074 to legal0078 are
  the same hand with the suits permuted.

The other riichi-ankan cases agree under both rules:
- legal0061 to legal0063: no fourth copy, so no ankan.
- legal0064 to legal0066: ankan allowed.
- legal0067 to legal0072: the waits change from {3s,5s,6s} to {5s}, so no ankan.

**Fix:** adopt waits-only in formats.md: "In riichi only with the drawn tile, and only if the
set of winning kinds is unchanged." Change the six expected lines. Keep legal0067 to legal0072
as the cases that must be refused.

### S1.3 Chankan does combine with ippatsu (rules.md item 26, Decision 10, Unverified 5)

riichi.wiki/Ippatsu says: "Note that chankan is compatible with ippatsu. When winning off
chankan, the kan call is interrupted, so ippatsu is retained." It also says calls end ippatsu
"except for a robbed kan". riichi.wiki/Chankan says the same. I found nothing saying Mahjong
Soul differs, and this is standard behaviour in Tenhou. No corpus case is wrong, because the
combination was never generated. But rules.md item 26 and Decision 10 state the opposite, so
an implementer who follows them will build a rule that rejects ippatsu on chankan.

**Fix:** correct item 26 to say "any completed call; a shouminkan robbed by chankan is not
completed and does not cancel ippatsu". Delete the ippatsu+chankan exclusion from Decision 10
and add 2 or 3 score cases with `flags=riichi,ippatsu,chankan`. Unverified item 5 can be
closed.

---

## S2: ambiguities that will fail a careful implementer (Q6)

1. **Riichi on a wait that needs a fifth copy (legal0157, legal0158, legal0159).** Take
   `111789m123p123s1z draw=1m kans=4`. Discarding 1z leaves 1111789m 123p 123s, which waits
   only on a fifth 1m. Decision 4 and disputed.txt say such a hand is tenpai (std=0). The
   legal answer still leaves out `riichi:1z`. An implementer who reuses their shanten for the
   "leaves tenpai" test will output riichi:1z and fail. Mahjong Soul and Tenhou do treat this
   hand as noten, so the expected line is probably right. **Fix:** write it down: "tenpai for
   riichi = at least one winning kind of which the hand plus melds hold fewer than 4 copies.
   Karaten through other players' discards still counts as tenpai."
2. **The chankan flag in the discard case.** legal0133 to legal0138 come `from=kamicha` with a
   chi shape, yet expect only `pass,ron`. formats.md never says that a robbed kan tile cannot
   be chi'd, pon'd or kanned. **Fix:** add "with `chankan`, only `ron` and `pass`."
3. **Hand size in the `called` case is not stated.** The corpus uses 14−3k concealed tiles,
   with the meld already removed (legal0025 has 11 tiles plus one meld). **Fix:** state it in
   the `called` row.
4. **When `wall` is counted, and whether wall=0 implies haitei or houtei.** mj-rs counts
   after the draw and infers haitei or houtei from wall=0. formats.md only says "live wall
   tiles remaining" and passes haitei/houtei through `flags`. No current case depends on the
   difference, because every replay case with wall=0 carries the flag. **Fix:** say "count
   after the incoming draw; haitei/houtei are given only by flags" (or say they are inferred)
   and pick one.
5. **Rules that live only in the Decisions log.** Kazoe prints `han=14 fu=..` and never
   `yakuman=` (Decision 6). `ura` is ignored without riichi (8). A shanpon ron makes the
   triplet open (11). An equal-payment tie between a real yakuman and kazoe is unresolved
   (7a). **Fix:** move these into the `score` section. For 7a, say the real yakuman wins,
   which matches what both engines already do.
6. **`first=1` and tenhou/chiihou in `legal`.** It is not defined whether first=1 on a
   complete draw supplies the tenhou or chiihou yaku for `tsumo`. **Fix:** say yes (dealer
   first draw gives tenhou, non-dealer gives chiihou), or say first=1 affects only kyuushu.
7. **Robbing an ankan for kokushi cannot be expressed.** The `chankan` flag means a
   shouminkan. Either say that, or add `flags=chankan_ankan`. mj-rs NOTES flags the same gap.

## S3: rules.md text errors (no corpus impact)

- **Item 6** is incoherent: a half-written example with "?" and "no," in the middle.
  Replace it with one clean example, such as 23444m-type ambiguity where ron on 2m reads as
  ryanmen (pinfu) or as a tanki and the higher total wins.
- **Item 14's example is malformed.** "111234m (waiting 1m/4m)" is not a 13-tile hand, and
  the reasoning is garbled. Use legal0067 instead: `123456m4445s111z`, where drawing 4s and
  kanning changes the waits from {3s,5s,6s} to {5s}.
- **Item 26** has the chankan error described in S1.3.
- **Section 1 has no tenhou-upgrade row**; see S1.1.
- **Row 69 and formats.md disagree** on the riichi ankan rule; see S1.2.

## Q4: fu and scoring rulings checked (rules.md)

- Double-wind pair = 4 fu: correct. riichi.wiki/Mahjong_Soul says "Double-wind pair: 4 fu".
  sc938, sc945, sc948, sc950, sc954 and sc962 check it.
- Rinshan tsumo +2 fu: correct for Tenhou and Mahjong Soul. Checked in sc193, sc205, sc244
  and sc309.
- Kazoe yakuman at 13 han or more, capped at 1x: correct. sc937, sc968 and sc50 print the
  real han, as Decision 6 says.
- The four double yakuman (kokushi_13, suuankou_tanki, junsei_chuuren, daisuushii): correct,
  and riichi.wiki lists the same four.
- Yakuman stacking: correct. sc5133 is 2+2+1+1 = 6, paid all:96000, which is right. The 6x
  cap can never be reached.
- Pao on daisangen and daisuushii only, 50/50 on ron, liability limited to the liable yakuman
  in composites: correct ("Separated responsibility for each yakuman"). Pao cannot be
  expressed in `score`, which is fine.
- Everything else I checked was correct: no kiriage, 25 fu chiitoi, 30 fu on open ron, 20 fu
  pinfu tsumo, the honba rules, and both score lookup tables, every cell of which I
  recomputed.

## Q3: kuikae

The rule as written in rules.md row 38 is correct for both Tenhou and Mahjong Soul:
- After a pon, the same kind is banned, red or not.
- After a chi, the called kind is banned, plus the tile at the far end of the sequence when
  the called tile sits at an end of a two-sided shape. A kanchan call bans only the called
  kind. A penchan call bans only the called kind.

All the legal.txt cases match:
- legal0025 to legal0030 (c406 took 4 bans 4 and 7).
- legal0031 to legal0036 (c567 took 7 bans 7 and 4, and 0m stays legal).
- legal0037 to legal0042 (a pon on 5 bans 0).
- legal1024 (c789 took 9 bans 9 and 6), legal1185 (c456p took 6p bans 3p, which is correctly
  missing), legal1373 and legal1453 (kanchan).

"Chi left out if every remaining discard would be kuikae" is correct. legal0043 to legal0045
keep both chi options. legal0046 to legal0048 drop chi:56. The same rule exists in principle
for pon, but it can never fire: it would need five copies of a kind. Say so in formats.md, so
nobody writes dead code looking for the pon case. **Coverage gap:** no case calls a penchan
chi (c123 took 3, or c789 took 7) and then checks the discards.

## Q5: hand-checked cases

I derived each answer before reading the expected line.

**Wrong:**
- legal0073 to legal0078 (S1.2).
- sc910, sc918, sc3695, sc5136 (S1.1).

**Correct (score):**
- sc1, sc2, sc42, sc131, sc193, sc205, sc244, sc309
- sc937, sc938, sc939, sc941, sc943, sc944, sc945, sc948, sc949, sc950
- sc952, sc953, sc954, sc955, sc956, sc957, sc958, sc962, sc964, sc968
- sc969, sc970, sc971, sc972, sc976, sc977, sc982, sc983, sc985, sc987
- sc988, sc989
- 40 cases in total: fu with kans, double-wind pairs, shanpon-ron triplets, kazoe, rinshan,
  chankan, honba.

**Correct (legal):**
- Fixtures: legal0001, legal0007, legal0013, legal0019, legal0025, legal0031, legal0037,
  legal0043, legal0046, legal0049 to legal0060, legal0061 to legal0072, legal0079, legal0085,
  legal0088, legal0091, legal0097, legal0103, legal0109, legal0115, legal0121, legal0127,
  legal0133, legal0139, legal0145, legal0151, legal0157 (subject to S2.1), legal0160.
- Replay cases: legal0236, legal0326, legal0342, legal0399, legal0527, legal0623, legal0839,
  legal1000, legal1016, legal1024, legal1104, legal1185, legal1197, legal1289, legal1302,
  legal1373, legal1441, legal1461, legal1477, legal1487.

## Q7: coverage gaps inside the five ops

- `legal` with `riichi=1` and a winning tile: **0 cases** of ron or tsumo while in riichi
  (89 discard cases and 0 ron). As a result, riichi as the only yaku, furiten while in
  riichi, and tsumo during riichi are never tested.
- Okurikan: no case where a riichi hand already holds four copies and draws a different tile.
- Kan on the haitei draw: no wall=0 draw case in which ankan or kakan would otherwise be
  legal. The three haitei draws have no quad.
- The kyuushu boundary: no case with exactly 9 kinds. Expected-yes cases all have 12 kinds,
  and expected-no cases have at most 8.
- Penchan chi kuikae (see Q3). Only 6 legal cases have k, s or a melds in `melds=`, so
  parsing kan melds in legal is barely exercised.
- Tsumo or ron on chiitoi or kokushi shapes in `legal`. Tsumo where the yaku depends on the
  decomposition chosen.
- The `first=1` tenhou/chiihou tsumo (S2.6).
- `score`: chankan+ippatsu (S1.3), tenhou with chuuren (S1.1).
- No invalid-input or `error=` cases for the "never crash" contract. Add a handful, and let
  the harness accept `error=*` as a wildcard.

## Q8: slice shape

- `legal` is low in diversity. 1323 of its snapshots come from 6 replay hands, and another
  1512 are suit permutations of those. Most of it tests discard enumeration and sorting, which
  is bookkeeping. Cut it to around 600 (dedupe the permutations) and spend the effort on about
  100 more directed cases from the Q7 list.
- `agari` forms: the exact group and form sort order is mostly a canonical-printing exercise.
  Keep it, but 2190 cases is more than the decomposition logic needs. Around 500 would do.
- What would separate the languages better: a throughput set (say 100k random shanten and
  waits requests, run with `--time`). It rewards table-driven or memoised search and
  exposes runtime cost. At present the whole corpus finishes too quickly to say anything about
  performance.
- Harness: all cases go through one process. A crash on case N fails every case after it as
  "no response", and one missing line throws off every later id. Consider restarting the
  process after a crash and resyncing on the id. This affects fairness between languages with
  different panic behaviour.

## Not checked

- I did not read tools/gen or the mj-rs source beyond NOTES.md and DISAGREEMENTS.md.
- I did not audit agari.txt, shanten.txt or waits.txt beyond the disputed cases. They come
  from two agreeing engines.
- I did not verify any of this in a Mahjong Soul client. The tenhou upgrade, waits-only
  riichi ankan and chankan+ippatsu all rest on riichi.wiki text.
- I did not check the multi-ron honba question or the rules.md table rows outside the five
  ops (uma, nagashi, abortive draws).
- I did not check the 140 rule-sensitive comment lines individually.
