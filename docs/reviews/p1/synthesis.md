# Phase 1 gate — synthesis

Reviews: `opus.md`, `codex.md`, `agy.md`. Verdict: **gate held**; fixes below, then re-run.
The three reviewers worked independently and agree on every major point, which is
the main reason to trust the rulings: none was verified in a Mahjong Soul client.

## Accepted

| # | Finding | Raised by | Action |
|---|---|---|---|
| 1 | Riichi ankan: Mahjong Soul needs only the wait kinds unchanged; decomposition may change. legal0073–0078 wrong. | all three | formats.md fixed; fix mj-rs, regenerate |
| 2 | Tenhou scores the best choice of winning tile. sc910, sc918, sc3695, sc5136 underpay by one yakuman. Chiihou keeps the supplied tile. | codex, opus | formats.md fixed; fix both references, regenerate |
| 3 | Chankan combines with ippatsu. rules.md item 26 and Decision 10 wrong; no case covers it. | all three | formats.md fixed; fix rules.md, add cases |
| 4 | Riichi needs a live wait: a fifth-copy-only wait is structurally tenpai but can't riichi. Corpus right, spec silent. | agy, opus, codex | formats.md fixed |
| 5 | Robbing a kan allows only ron/pass; and robbing a closed kan (kokushi only) couldn't be expressed. | all three | formats.md: `chankan` = added kan, new `ankan_rob` flag; add cases |
| 6 | Last-tile yaku must come from flags, not `wall=0`; `wall` timing undefined. | all three | formats.md fixed; mj-rs must stop inferring; corpus must send the flags |
| 7 | Tie-break undefined between real and kazoe yakuman; "highest han first" in rules.md misleading. | all three | formats.md: total, real yakuman, han, fu, string |
| 8 | Rules living only in the Decisions log (kazoe output, ura without riichi, shanpon ron, chiitoi kinds, structural shanten). | opus, codex | moved into formats.md body |
| 9 | Kuikae rule not written in formats.md. Corpus cases correct. | codex, agy | formats.md fixed |
| 10 | legal.txt answers come from the adapter that is then checked against them; mostly six replays plus suit permutations; rare actions barely covered. | codex, opus | cut replay-derived cases to ~600; add a hand-authored file with complete action sets, written by a different model than the adapter's author |
| 11 | Pao: rules.md gives honba to the wrong payer; `score` can't represent pao. | codex | fix rules.md; pao declared out of scope for `score` |
| 12 | rules.md: item 6 garbled, §4.16 describes an impossible 13-wait ankan robbery, 6x cap unsourced. | all three | fix rules.md |
| 13 | Coverage: riichi seat winning, okurikan, kan on last draw, 9-kind kyuushu boundary, penchan chi kuikae, ura without riichi, rinshan fu rounding boundary, kazoe tie, hand `called` with kans. | all three | add directed cases |
| 14 | Harness: one crash fails every later case. | opus | restart and resync by id |
| 15 | Input grammar and error strings undefined. | codex, agy | formats.md: corpus inputs are always valid; only two error answers tested |

## Not doing

- **Trim the agari forms output** (opus: over-tests sort order). Kept: enumerating
  every decomposition is the part of the slice where languages should differ most,
  and the ordering rule is now stated precisely.
- **Malformed-input test set** (codex). Out: it tests parsing, which we agreed not to judge.
- **Furiten reset timing** (codex). `furiten` is an input flag in this slice, so the
  generator's own bookkeeping can't make an expected answer wrong. Matters in Phase 3.
- **Separate throughput corpus** (opus). The existing files with `--time` are enough
  for the shootout; revisit if the languages end up close.

## Still unverified against a real client

Chankan + ippatsu, dead-end chi being refused, tenhou upgrade, multi-ron honba.
All rest on Mahjong Soul's published rules and FAQ, riichi.wiki, and three-way agreement.
