# Package F scenario review

Reviewed the 54 scenario files against the wall layout, the round and game transitions in engine.md §§4–6, and the scoring and legality rules in rules.md. Traced live and replacement draws, concealed tiles and calls, reaction seats, waits and furiten. Recomputed the winning hand values, payment rounding, honba and sticks, exhaustive-draw payments, and All Last scores before leftover sticks. Used a supplemental replay of the expanded fixtures to cross-check reaction windows and exhaustive-draw hands. The validator covers tile flow and conservation. Client behavior and engine execution were outside this review.

## Changes

26 scenario files changed. The suite still contains 54 scenarios.

| Scenario | Before → after | Reason |
| --- | --- | --- |
| `abort_suufon_renda` | No answers on the first 1z → seats 1 and 2 pass. | Seat 1 can ron for Chanta and seat 2 for Honitsu. The fourth identical discard still aborts without a ron candidate. |
| `abort_suufon_renda_riichi_stick` | No answers on the first 1z → seats 1 and 2 pass. | The same two early rons are available. The fourth discard still aborts before accepting the stick under the design default. |
| `abort_suukaikan_second_seat_pon` | Event subsequence → exact sequence with four indicator reveals, four replacement draws, and no completed pon. | The exact match catches an erroneous pon event on the aborting discard. |
| `added_kan_robbed_ippatsu_alive` | Only seat 1 answered the first 4m discard → seats 0 and 3 also pass. Event subsequence → exact round events. | Seat 0 can ron that earlier 4m and clears temporary furiten on its own draw before declaring riichi. Seat 3 can chi. The exact sequence catches a stray dora reveal or draw on the robbed kan. The dealer's 5 han 30 fu ron pays 12,000 and recovers its own stick. |
| `dead_end_call` | Seat 2's `56m` → `68m`. Added seat 0's pass on 1s and seat 1's ron assertion and pass on 4m. Seat 2's win changes from 2 han 30 fu and 2,000 to 1 han 40 fu and 1,300. | Seat 2 originally passed its 4m wait and had no intervening draw before the 7m ron. The new 7m kanchan scores Tanyao and 20 + 10 + 2 fu, rounded to 40. Seat 1 can ron 4m with three dragon pons, even though its requested chi leaves only forbidden discards. Seat 0 can call the earlier 1s. |
| `endgame_all_last_extension_start` | Seats 1/2/3 change `1155s/3399s/1122s` → `1156s/3398s/1123s`. | All three had six pairs plus a singleton. With only seat 0 tenpai, it reaches 29,000 after +3,000. The 2,000 on the table does not meet the extension threshold. |
| `endgame_all_last_tenpai_yame` | Seats 0/1/2 change `1155s/3399s/1122s` → `1156s/3398s/1123s`. | Breaks three incidental seven-pairs waits. Only dealer seat 3 gains 3,000 and ends at 33,000 before its leftover stick. |
| `endgame_extension_dealer_repeat_priority` | Seats 2/3 change `1155s/3399s` → `1156s/3398s`. | Breaks two incidental seven-pairs waits. Seats 0 and 1 each gain 1,500. Seat 1 crosses 30,000 while dealer seat 0 retains West 1 under the default. |
| `endgame_nagashi_pushes_dealer_out_of_first` | Seats 0/1/2 change `2233s 4s / 4455s 6s / 6677s 8s` → `2234s 7z / 4456s 7z / 6678s 7z`. | Only the dealer should be tenpai. Seat 0 still earns Nagashi Mangan through the fixed terminal/honor draws. The dealer pays 4,000, drops from 31,000 to 27,000, and repeats South 4 while seat 0 leads with 33,000. |
| `endgame_oka_uma_tiebreak` | Seats 0–3 change `1155s/3399s/1122s/4477s` → `1156s/3398s/1123s/4478s`. | All four originally had seven-pairs waits and the dealer would repeat. With zero tenpai, ranks are 0, 1, 2, 3, and the 2,000 in sticks takes first place to 37,000. Existing adjusted scores already use integer points. Verified Mahjong Soul `27000 4000 -6000 -25000` and Tenhou `47000 4000 -16000 -35000`. |
| `first_go_around_cancelled_by_ankan` | No answer to 1m → seat 2 passes chi. Comments now describe the actual 1m discard and 11 distinct terminals/honors on seat 1's draw. | Seat 2 can chi with 23m. Seat 1 has enough distinct tiles for kyuushu and the earlier ankan bars it. The fixture directly checks kyuushu and chiihou. |
| `formal_tenpai_fifth_copy` | Seats 0/3 change `1155s/6699s` → `1156s/6698s`. | Breaks seat 0's seven-pairs wait after it swaps 1m for its 3z draw, and seat 3's initial seven-pairs wait. Seat 1 has a fifth-copy wait with three copies in its pon and seat 2 has all four concealed. The specified zero vs. one tenpai outcomes and payments now follow. |
| `furiten_no_yaku_wait_not_asked` | No answer to 9m → seat 2 passes pon. Added explicit no-question assertion on the yaku-less 1m. | Seat 1's no-yaku pass must set temporary furiten despite the absence of a ron action. It later wins open Tanyao at 1 han 30 fu, paid 500/300/300. |
| `furiten_own_discard_yaku_less_wait` | Seat 1 expected unasked on 4m → seat 1 can chi but cannot ron, and seats 1 and 3 both pass. Comments name the actual single meld and full concealed shape. | Seat 1 can chi with 23m despite furiten, and seat 3 can pon. Seat 1's called-away 1m continues to block ron. |
| `furiten_surviving_call` | Mahjong Soul cleared furiten on pon and ronned for 1,000 → shared continuation with Tenhou through the next own draw, then 1 han 30 fu Tanyao tsumo for 1,100. Added missing passes on 9m (seat 2), 4m (seat 3), and 2m (seat 2), plus a furiten assertion immediately after pon. | Applies the new ruling in both rulesets. The 3m ron is blocked before seat 1 draws, and the own draw clears temporary furiten. Fu is 20 + 2 tsumo + 4 for two pons + 2 tanki = 28, rounded to 30. |
| `last_tile_houtei_no_calls` | Canonical live indices 43–45 `3s 4s 4s` → explicit `4s 3s 4s`. | The dealer previously discarded 4s at index 44 and was furiten for the last 7s. Swapping 43 and 44 moves 4s to another seat and preserves the live-wall limit and the 5,800 dealer ron. |
| `nagashi_mangan_tenpai_dealer` | Seats 1/2/3 change `2233s 4s / 4455s 6s / 6677s 8s` → `2234s 7z / 4456s 7z / 6678s 7z`. | Breaks three incidental seven-pairs waits. Dealer seat 0 remains the sole tenpai seat. Seat 1's Nagashi Mangan pays 4,000/2,000/2,000 and keeps the stick and increments honba. |
| `open_kan_chained_kan_discard_ron` | No response to seat 1's 1s → seat 0 passes. Both event subsequences → exact round events. | Seat 0 can pon or daiminkan. The exact logs require the owed indicator after kakan and before its replacement draw, and distinguish the final indicator's presence on Tenhou from its absence under the Mahjong Soul default. One dora makes 3 han 30 fu (3,900), while three dora make 5 han (8,000). |
| `pao_composite_yakuman` | Implicit calls → seat 2 passes 1m, seats 0 and 2 pass 1s, seat 0 passes 9s, and seat 3 passes 8p. | All four windows need answers. Majsoul charges the liable seat 32,000 + 300 and distributes the second yakuman 16,000/8,000/8,000. Tenhou charges the liable seat 64,300. |
| `pao_double_ron` | Seat 1's discarded filler `1m` → `1z`, and seat 2 explicitly passes 9m and 1s. Corrected seat 0's initial draw comment from 2z to 8p and tagged the multi-ron honba assumption. | Seat 1's old 1m made the 4m ron furiten. Seat 0 gets 2,900 + 300 + a 1,000 stick. Seat 1 gets 16,000 each from the discarder and liable seat. |
| `pao_ron_from_liable_seat` | Seat 1's initial filler discard `1m` → `1z`. Seat 2 passes 9m, seats 0/2 pass 1s, and seat 3 passes chi when seat 1 rons 4m. | Removes own-discard furiten and completes the windows. The liable discarder pays 32,300. |
| `pao_ron_third_party` | Seat 1's initial filler discard `1m` → `1z`. Seat 2 passes 9m and seats 0/2 pass 1s. | Removes own-discard furiten and completes the windows. The liable seat pays 16,300 and the discarder pays 16,000. |
| `pao_tsumo_daisangen` | Seat 1's initial filler discard `1m` → `1z`. Seat 2 passes 9m and seats 0/2 pass 1s. | Completes the windows and keeps the setup consistent with the ron variants. Seat 2 still pays the full 32,300 on tsumo. |
| `riichi_ankan_waits` | Added passes by seats 2, 3 and 1 on seat 0's 4z, seat 2's 7z and seat 0's 4m, respectively. Fixed the illustrative suits in seat 0's comment. Winner changes from 4 han 50 fu to 6 han 50 fu, and deltas from `-5000 9000 -2000 -2000` to `-7000 13000 -3000 -3000`. | Seat 1 passes ron on 4m and can still tsumo. Its concealed 999p, 333s and 6666s add Sanankou. Fu is 20 + 2 + 8 + 4 + 16, and Haneman pays 6,000/3,000/3,000 before net riichi sticks. |
| `riichi_discard_called` | No answers to 9p and 3z → seat 3 passes chi, then seat 1 passes seven-pairs ron. | Completes both windows. The original dealer win remains 4 han 20 fu, paid 2,600 all. |
| `triple_ron_rulesets` | Multi-ron honba assumption untagged → marked unverified. | Its Mahjong Soul branch uses the same client-unverified closest-winner honba assumption as the double-ron scenarios. |

Updated INDEX.md and QUESTIONS.md to reflect the shared furiten ruling, the confirmed integer adjusted-score unit, and the two additional references to the Mahjong Soul multi-ron honba assumption.

## Left on the stated defaults

No remaining fixture expectation was identified as contradictory to the stated defaults. The following scenarios retain outcomes dependent on unverified behavior.

- `abort_suufon_renda_riichi_stick` uses the no-stick default for the fourth wind.
- `added_kan_robbed_ippatsu_alive` and `riichi_ankan_waits` use the rulings on robbed-kan ippatsu and unchanged wait kinds, respectively. The spec records the rules as resolved and the client replay as outstanding.
- `double_ron_with_sticks_and_honba`, `pao_double_ron`, and the Mahjong Soul branch of `triple_ron_rulesets` use closest-winner honba. A client paying every winner would change all three payouts.
- `open_kan_discard_ron_dora` and `open_kan_chained_kan_discard_ron` use the Mahjong Soul default for an owed indicator on a ronned discard. The latter also uses the default chained-kan order.
- `formal_tenpai_fifth_copy` uses the specified Mahjong Soul formal-tenpai default.
- `endgame_extension_dealer_repeat_priority` and `endgame_nagashi_pushes_dealer_out_of_first` use the design defaults for extension priority and post-Nagashi placement, respectively.

## Coverage

### Engine §4.1

| Row | Existing fixture coverage and gaps |
| --- | --- |
| 1 · Ron | Ron beats call responses, cancels pending reach, pays multiple winners, and produces Tenhou sanchahou. Missing ron on the fourth riichi discard and ron on the fourth multi-seat kan discard. |
| 2 · Four winds | Ordinary fourth wind and fourth-wind riichi are covered. A ron on that fourth copy is physically impossible. |
| 3 · Accept reach | Covered before a draw, a pon and the four-riichi abort. Missing acceptance immediately before chi or daiminkan. |
| 4 · Four kans | Replacement tsumo and pre-pon abort are covered. Missing the ron override on the ensuing discard. |
| 5 · Four riichi | Fourth stick is collected on the abort. Missing a submitted call which loses to the abort, and a submitted ron which wins instead. |
| 6 · Pon or daiminkan | Both resolve successfully. Pon beats chi. Missing explicit daiminkan-versus-chi and ron-versus-daiminkan outcomes. |
| 7 · Chi | Successful chi covered. The dead-end case tests that an illegal chi is absent even in a live reaction window. |
| 8 · Exhaustion | Covered by full-wall draws and both runs of the fifth-copy fixture. Missing terminal pass-to-exhaustion on an explicit legal ron window. |
| 9 · Next draw | Explicit pass-to-next-draw sequences and exact ordinary draw events are covered. |

Robbing windows cover added-kan ron and the Kokushi closed-kan split. The suite has an unrobbed added kan in the chain, with no legal robber in that fixture. Missing a legal robber explicitly passing while the kan completes, furiten triggered by a passed kan, and a genuine open-kan → closed-kan chain with its two indicator reveals. Furiten coverage includes called-away discards, yaku-less waits, calls while furiten, own-draw clearing, and skipped tsumo via ankan in riichi. Missing own-discard furiten becoming false after a wait change and permanent riichi furiten from passing an opponent's discard, verified again after the next draw.

### Engine §4.2

| Bullet | Existing fixture coverage and gaps |
| --- | --- |
| Riichi | Point and live-draw boundaries and double riichi are covered. Missing open-hand rejection, closed noten rejection, furiten and karaten declarations, and a choice between tenpai-preserving and tenpai-breaking discards. |
| Ippatsu | Positive ippatsu, cancellation by pon and own ankan, and survival of robbed kakan are covered. Missing expiry on the next own discard and explicit cancellation by chi, daiminkan, completed kakan, or an opponent's ankan. |
| First go-around | Kyuushu and chiihou cancellation by ankan and positive double riichi are covered. Missing positive Tenhou and Chiihou, double riichi downgraded by an earlier call, and four-winds interruption by an earlier call. |
| Four winds | Both ordinary and fourth-stick variants covered. The fourth-stick client question remains open. |
| Kan transactions | Immediate ankan indicator, robbed added/closed kan, immediate open-kan rinshan without owed indicator, open → added chain, and post-open/added-kan ron timing are covered. Missing post-kan all-pass reveal, reveal followed by a call, immediate added-kan rinshan without its owed indicator, open → closed order, and a post-kan riichi ron whose ura changes with the owed indicator. Exact logs on robbed kakan now check for no replacement or reveal. The surviving pon and kan count are not observable from the current assertions. |
| Four kans | One-seat continuation, a fifth ankan denied, two-seat replacement win and two-seat abort before pon are covered. Missing four-kan discard ron and denial of fifth kakan/daiminkan with suitable tiles. |
| Four riichi | Covered at the ordinary abort. Missing competing ron and call outcomes described above. |
| Last tile | Haitei, Houtei, no last-draw ankan, no last-tile chi/pon, last-live-slot kan and its rinshan/Houtei are covered. Missing zero-live kakan and daiminkan with matching tiles. |
| Kuikae | Chi opposite-end swap, pon same-kind swap, no tsumogiri after call, and dead-end chi covered. Missing matching-red discard rejection, red called-tile suji, kanchan carve-out, and dead-end pon. |
| Pao | Daisangen tsumo, liable/third-party ron, composite tsumo in both rulesets, double ron, and no Suukantsu liability on Mahjong Soul are covered. Missing Daisuushii liability, pao set by daiminkan, composite third-party ron, and Tenhou counterparts for the single-Mahjong-Soul fixtures. |
| Exhaustive draw | Zero, one and two tenpai payments, dealer tenpai, fifth-copy formal tenpai, one Nagashi winner with no honba charge and stick carryover are covered. Missing three and four tenpai fixtures, multiple Nagashi winners, dealer Nagashi, and losing qualification when a terminal/honor is called away. |
| Multi-ron | Double/triple payment, nearest honba/sticks, dealer as a later winner, and Tenhou triple abort are covered. Missing direct Tenhou double-ron payment coverage. |
| Nine terminals | Immediate optional abort and cancellation by earlier ankan covered. Missing opting out and explicit rejection at eight distinct terminals/honors or after the seat has discarded. |

### Engine §5

| Step | Existing fixture coverage and gaps |
| --- | --- |
| 1 · Tobi | Negative score and exact zero after ron are covered. Missing tobi caused by draw payments and precedence over an otherwise repeating dealer. Two other fixtures produce a negative score, `closed_kan_robbed_kokushi` on Mahjong Soul and `pao_ron_from_liable_seat`, with round assertions only. |
| 2 · Honba | Increment on both kinds of draw, increment on dealer win, and reset from positive honba on non-dealer win are covered. |
| 3 · Dealer repeat | Dealer win including a later multi-ron winner, dealer tenpai, abort, and seat advance on non-dealer win or dealer noten are covered. |
| 4 · All Last | Dealer win and dealer tenpai in first, tie lost on seat order, repeat after abort, extension below 30,000 excluding sticks, West sudden death, dealer repeat priority and no-repeat West 4 limit are covered. Missing terminal decision at exactly 30,000, a first-place repeating dealer below 30,000, scheduled All Last ending on a non-dealer win at target, within-extension advance below target, East-game E4/S4 equivalents, and direct Tenhou repeat-priority coverage. A West 4 repeat below target would also pin the design's repeat priority against the specification table's shorthand about the extension limit. |
| 5 · Game result | Leftover sticks, starting-seat tie-break, final ranks/raw scores and integer oka/uma in both rulesets are covered. Most other game-end fixtures assert ranks and raw scores only. |

### Rules §4

- Items 1–2 are missing paired Sanankou/Suuankou shanpon ron and tsumo cases. Item 3 is covered by the tanki ron in both rulesets.
- Items 4–6 are missing Ryanpeikou versus Chiitoitsu, Pinfu exclusions for value pairs and non-ryanmen waits, and maximum-payment selection between legal decompositions. The suite checks positive Pinfu frequently.
- Items 7 and 9 protect 20-fu closed Pinfu tsumo and 30-fu open sequence tsumo. Item 8 lacks a 30-fu open sequence ron. Items 10–11 lack a scored 25-fu Chiitoitsu case, four-of-a-kind rejection as two pairs, and a four-fu double-wind pair.
- Items 12–19 have representative fixtures. Missing subcases include red and kanchan kuikae, okurikan after riichi, and the additional kan, robbing and last-tile paths above.
- Item 20 covers the no-kiriage 4 han 30 fu non-dealer ron on Tenhou. Missing the 3 han 60 fu boundary, a dealer boundary, tsumo boundaries, and the same boundary on Mahjong Soul.
- Items 21–29 have representative fixtures. The gaps above include the ron overrides of abortive draws, first-go-around variants, ippatsu expiry, and furiten persistence variants. Exact zero on riichi acceptance is covered in `riichi_requirements`.
- Items 30–32 cover single Nagashi, Daisangen pao distributions, and Mahjong Soul no-pao Suukantsu. Missing simultaneous Nagashi winners and the additional liability branches above.
- Items 33–36 lack a 26+ han kazoe cap case, a natural yakuman with an explicitly excessive dora total, Ryuuiisou without Hatsu, and Chuuren invalidated by ankan. Existing natural-yakuman cases already assert yakuman-only payouts despite ordinary yaku.
- Item 37 covers ron > pon > chi and positive daiminkan. The two direct daiminkan priority matchups are missing.

## Validation

```text
OK: 54 scenarios passed (11 unverified).
```
