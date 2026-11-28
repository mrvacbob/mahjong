# Package F2 scenario review

Reviewed the 69 scenarios added in `332e9ca` against `Spec/rules.md` and the round, game, and event transitions in `Docs/Design/engine.md` §§4–6. Traced draw and call order, concealed hands, reaction answers, and furiten. Cross-checked the expanded walls with a supplemental replay and the repository's Python scoring oracle. Recomputed payments, including honba, sticks, pao, draw settlements, and final ranks and adjusted scores. The fixture checker validates structure, tile flow, and point conservation. Engine execution and client replay remain unverified by this review.

## Changes

14 of the 69 scenarios changed. The suite still contains 123 scenarios.

| Scenario | Before → after | Reason |
| --- | --- | --- |
| `chiitoitsu_25_fu_no_four_of_a_kind` | Seat 2's `11s` → `22s`. | The original all-terminal/honor hand added Honroutou and scored 5 han 25 fu for 8,000. The new hand scores the asserted 3 han 25 fu, paid 1,600/800/800. Rounding to 30 fu would now change the payment, and seat 1's four-of-a-kind probe still works. |
| `endgame_extension_w4_dealer_repeat` | Engine-only reference → direct reference to clarified `extension_max_round`. | The spec now explicitly allows the repeat. The dealer finishes West 4 at 28,000 after receiving 3,000 and repeats at honba 1. |
| `four_kans_one_seat_no_fifth_kakan_daiminkan` | Comment counted three rinshan 9p draws → two live and two rinshan 9p draws. | The four copies assemble legally before the fourth kan. The replacement 6z tests daiminkan and the next live 5z tests kakan. |
| `ippatsu_cancelled_by_kakan` | Untagged → unverified under rules §5.4. | The ron's exact event list assumes Mahjong Soul suppresses the owed indicator. The ippatsu test still distinguishes 11,600 from 12,000. |
| `kazoe_yakuman_26_han_cap` | Commented opening discards `1z` and `9p` → `4z` and `9s`. | Matches the opening sequence and avoids an incomplete wait list. The 30 han still pays one 32,000-point counted yakuman. |
| `kyuushu_illegal_eight_and_second_turn` | Commented first discard `2m` → `8s`. | The fixture keeps all eight distinct terminals/honors through the first discard and adds a ninth on the second draw. |
| `last_tile_houtei_pass_exhaustive` | Inconsistent accounts of the wait copies → all four 4s and three 7s in starting hands. | The expanded wall has no earlier live 4s or 7s. The last 7s therefore reaches seat 2 without an earlier passed or own-discard wait. |
| `last_tile_no_kakan_or_daiminkan` | Superseded turn-count notes → draw indices 0–1, 2–68, and 69 in actual play order. | Seat 2 draws the fourth 5z at zero live tiles and discards 6z to seat 3, which holds the other three copies. |
| `nagashi_mangan_lost_when_called` | Commented first tile `2m` → `0m`. Clarified that the called 5z is itself an honor. | Seat 1 otherwise meets Nagashi Mangan conditions. The pon alone disqualifies it, leaving ordinary tenpai payments. |
| `natural_yakuman_ignores_dora` | Draft comments about possible indicators → actual two-ankan setup. | The three indicators make nine dragon dora and the red 5m adds one more. Daisangen alone pays 32,000. |
| `open_kan_discard_all_pass_dora` | Empty reaction window → seat 3 holds `11z` in place of `34z`, can pon, and explicitly passes. | Both runs now test revealing the owed indicator after a nonempty window closes without a call or ron. It still adds two dora to seat 2's 8,000-point tsumo. |
| `riichi_discard_daiminkan_cancels_ippatsu` | Untagged → unverified under rules §5.4. | No dora event on the replacement discard is an assumption of the Mahjong Soul branch. The exact log also checks reach acceptance before the kan. |
| `riichi_furiten_and_karaten` | Commented ura indicator `1z` → `5z`. | Matches the wall. Neither the actual ura nor the ordinary indicator adds han. |
| `suuankou_shanpon_tsumo` | Draft first-draw explanation → explicit first-turn 9m discard and second-turn 2m draw. | The second draw excludes Chiihou and isolates single Suuankou. |

Updated `INDEX.md` and `QUESTIONS.md` with the two unverified timing tags and the resolved West 4 rule. A concurrent edit to `FORMAT.md` was already present during the review and is outside this change list.

## Left unchanged

No remaining expectation was found to contradict the stated ruleset or its documented default. The Mahjong Soul owed-indicator expectations, the chained-kan order, and the earlier client-dependent assumptions in `QUESTIONS.md` remain dependent on client verification.

`ambiguous_wait_max_payment` reaches both intended hands and pays 3,900 and 3,200. In each case the interpretation with the greater payment also has more han. The fixture therefore cannot distinguish sorting by payment from sorting by han first.

## Prior coverage gaps

**Engine §4.1.** Row 1 now has both the fourth-riichi and fourth-kan ron overrides, and ron against daiminkan. Row 2 gains a four-winds interruption fixture. Row 3 now accepts riichi before each type of open call. Rows 4–5 cover the ron overrides, and row 4 already had an abort beating a submitted pon. Rows 6–7 now cover the direct daiminkan/chi matchup alongside the existing pon/chi case. Row 8 now has a genuine final ron window answered with pass. Row 9 remains covered by ordinary play and gains a post-kan pass with an exact indicator-before-draw check.

The writer's two impossibility claims hold. Before a pon, a caller with at most three melds holds at least four concealed tiles. Consuming two leaves at least two. With two consumed copies and one discarded copy already accounted for, at most one remaining tile is of the forbidden kind, including red fives. The caller therefore has an allowed discard. For fourth riichi, all three opponents have already accepted riichi, so none can submit chi, pon, or daiminkan. Ron remains possible and is tested. Ron on the fourth identical wind is also impossible because all four copies are in the ponds.

**Engine §4.2.** The batch covers the prior missing riichi legality and discard-choice assertions, ippatsu expiry and cancellation variants, first-go-around wins and interruptions, both four-riichi outcomes, the fourth-kan ron, fifth kakan and daiminkan denial, zero-live kakan and daiminkan denial, and the red-five and kanchan kuikae paths. Robbing now includes an explicit legal kakan pass with furiten clearing at the next draw. Kan timing now includes the all-pass reveal, reveal before a call, immediate kakan rinshan, open-to-closed chaining, and the Tenhou/Mahjong Soul ura split on a post-open-kan riichi ron. The batch also adds the missing own-discard furiten reset and permanent furiten across an own draw, three/four-tenpai draws, dealer and multiple-winner Nagashi Mangan, loss of Nagashi qualification through a called discard, Tenhou double ron, and the remaining nine-terminals options and bounds.

Pao gains Daisuushii, formation by daiminkan, composite third-party ron, and Tenhou counterparts for liable-seat ron, double ron and no Suukantsu liability. The composite Tenhou ron pays 32,300 from the liable seat and 32,000 from the discarder. Mahjong Soul pays 16,300 and 48,000 respectively. The separate ordinary Tenhou third-party ron with honba and ordinary Daisangen tsumo from a pon remain absent. Shared composite and daiminkan fixtures exercise those settlement paths indirectly.

**Engine §5.** The batch closes the listed game-flow gaps: draw-payment tobi takes precedence over repeat, scheduled All Last ends at exactly 30,000 or on a qualifying non-dealer win, a first-place dealer below target repeats, extension advances below target, E4/S4 exercise the East-game endpoints, and the Tenhou repeat-priority and West 4 dealer-repeat cases are explicit. Honba, dealer rotation, and integer final settlement already had direct coverage. An East-game S4 repeat would provide the direct counterpart to the West 4 repeat. Most game-end fixtures still check ranks and raw scores without checking adjusted scores.

**Rules §4.** The new scoring fixtures close the listed gaps in items 1–2, 4–6, 8, 10–11, and 33–36 at the case level. Items 12–19, 21–32 and 37 gain the rule branches described above. Item 20 now covers both no-kiriage ron boundaries and dealer/non-dealer 4 han 30 fu tsumo under both rulesets. The 3 han 60 fu tsumo boundary and the full value matrix across dealer status and win method still lack direct cases.

Other remaining gaps within these sections are a lower-han decomposition that actually pays more, separate Pinfu exclusions for single-wind pairs and penchan/kanchan when full subcase coverage is desired, a robbable closed kan after an open kan to distinguish owed-indicator ordering, and direct observation of the preserved pon and unchanged kan count after a robbed kakan. The last two state facts cannot be asserted in the current format after the hand ends. Existing exact events check for no replacement draw or new indicator on the robbed kakan.

## Validation

```text
OK: 123 scenarios passed (16 unverified).
```
