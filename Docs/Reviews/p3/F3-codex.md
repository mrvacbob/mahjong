# Package F3 scenario review

Corrected the seven disputed fixtures and added nine fixtures for the seven F2 coverage gaps. The index now lists 132 scenarios, including 19 with unverified client behavior.

## Disputed scenarios

| Scenario | Correction and recheck |
| --- | --- |
| `closed_kan_rinshan_tsumo` | North replaces the fourth opening West, so the first riichi deposit is accepted and the round continues to the ankan. Replaced filler hands to remove incidental waits. The closed kan reveals 8m before rinshan and cancels ippatsu. Four 9m dora give 8 han 60 fu and 8,000 from each opponent. Seat 0 recovers its own stick and repeats at honba 1. |
| `riichi_furiten_skipped_tsumo_ankan` | Broke the four-wind opening and used the reviewed `1112344s 123m 789p` hand. The fourth 1s completes a legal tsumo and permits ankan with the same structural 1s/4s waits. Seat 0 is furiten afterward. Seat 2 rons 4s for Pinfu, 1 han 30 fu, and collects the stick. Deltas remain `-1000 -1000 2000 0`. |
| `kan_one_live_tile_rinshan_not_haitei` | Dealer seat 0 repeats at honba 1. Removed incidental filler tenpai, pinned all earlier live 1m and 4m to other seats, and corrected the hand breakdown. The replacement 4m wins for 4 han 60 fu, with Rinshan, menzen tsumo and two East yakuhai. Mangan pays 4,000 each. |
| `last_tile_houtei_no_calls` | Dealer seat 0 repeats at honba 1. Replaced filler while retaining seat 1's quad, seat 2's chi shape and seat 3's pon pair. Earlier live waits occur outside seat 0's pond and before its final live draw. At zero live tiles only seat 0 answers, winning for 3 han 30 fu and 5,800. |
| `riichi_ankan_waits` | The first ankan would shrink 3m/5m/6m to 5m. The second preserves 1m/4m. The winning reading has 999p and the 6666s kan as its two concealed sets. Double riichi, menzen tsumo and Rinshan give 4 han 50 fu, with deltas `-5000 9000 -2000 -2000` after both deposits and their collection. Changed filler to preserve the opening call opportunities without incidental tenpai and supplied the remaining pon pass. |
| `nagashi_mangan_dealer` | Uses `ryukyoku(exhaustive)`. Seat 0 alone qualifies for 4,000 from each opponent. The dealer is noten and rotates. One stick remains and honba advances from 1 to 2. |
| `nagashi_mangan_multiple_winners` | Uses `ryukyoku(exhaustive)`. Seats 1 and 2 qualify and each nets 6,000 after paying into the other's mangan. Seats 0 and 3 pay 8,000 and 4,000. The dealer is noten and rotates, the stick remains, and honba advances to 2. |

## New coverage

| Scenario | Expected result |
| --- | --- |
| `ambiguous_wait_yakuman_beats_higher_han` | A double natural Suuankou Tanki pays 64,000 on Mahjong Soul, beating a 28-han sequence reading capped at 32,000. The natural reading is nominally equivalent to 26 han and is encoded as two yakuman. Tenhou pays 32,000 for either reading and picks the natural yakuman on the tie. This exercises a strict payment inversion on Mahjong Soul through the kazoe cap. The fixture does not assert a strict inversion between two ordinary han/fu readings. |
| `no_kiriage_3han60fu_dealer_tsumo` | Both rulesets use base 1,920 and round 3,840 up to 3,900 per opponent. |
| `no_kiriage_3han60fu_nondealer_tsumo` | Both rulesets round 3,840 and 1,920 up to 3,900 from the dealer and 2,000 from each other nondealer. |
| `pao_ron_third_party_tenhou` | A single Daisangen ron charges the liable seat 16,300 and the third-party discarder 16,000. |
| `pao_tsumo_daisangen_tenhou` | The third dragon pon establishes liability. The liable seat pays all 32,000 plus 300 honba on tsumo. |
| `endgame_east_s4_dealer_repeat` | The only tenpai seat is dealer 3. The 3,000-point draw payment puts the dealer first at 28,000, and play continues in South 4 at honba 1 under both presets. |
| `open_kan_to_robbed_closed_kan` | The first kan uses a simple tile, leaving every necessary Kokushi tile available. Seat 2 robs the second kan for 32,000. The log expects the first kan's owed indicator before the ankan announcement, with no second indicator or replacement. The Mahjong Soul order is unverified. |
| `declined_tsumo_outside_riichi` | The dealer declines tsumo by taking a wait-preserving ankan. Under the Mahjong Soul default the dealer rons for 3,900 at 1 han 80 fu. Under the Tenhou default temporary furiten blocks that ron and clears on the next live draw, allowing a 2 han 70 fu tsumo for 2,300 each. Both client defaults are tagged unverified. |
| `suukaikan_open_kan_owed_dora` | Seat 1 takes the fourth kan. Tenhou reveals the owed indicator at the discard, then the no-ron window resolves to a four-kan abort ahead of seat 2's pon. The Mahjong Soul branch expects the reveal after the window and before the abort, with that ordering tagged unverified. Both carry zero sticks, move zero points and repeat at honba 1. |

## Validation

Recomputed the scoring and settlements from the written rules, checked scoring decompositions and starting-hand shanten with the Python oracle, and checked the expanded draws for incidental waits and Nagashi qualification. Traced answers in the explicit reaction windows against the hands and draw order. The scenario checker validates file structure, wall accounting, tile flow and conservation. Engine execution and client replays were outside this validation.

```text
OK: 132 scenarios passed (19 unverified).
```
