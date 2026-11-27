# 4-Player Riichi Mahjong Rules Specification (Mahjong Soul Ranked Default)

Target ruleset: **Mahjong Soul (Jantama / 雀魂)** 4-player ranked matches (East / South rooms).
Secondary reference: **Tenhou (天鳳)** 4-player ranked matches.

Primary reference URLs used throughout:
- Mahjong Soul official site / in-game rules mirror: `https://mahjongsoul.com/` (in-game Rules / 対戦ルール), `https://w.atwiki.jp/mahjongsoul/`
- Tenhou official manual: `https://tenhou.net/man/`
- General riichi reference (note: `https://riichi.wiki` was unreachable/unindexed during lookup; see **Unverified**): `https://mahjong-item.jp/`, `https://game8.jp/jantama/`

---

## 1. `Ruleset` Table

| `field_name` | Mahjong Soul (Ranked 4P) | Tenhou (Ranked 4P) | Notes / Source |
| :--- | :--- | :--- | :--- |
| `starting_points` | `25000` | `25000` | Per player at game start (`mahjongsoul.com`, `tenhou.net/man/`). |
| `target_points` | `30000` | `30000` | Minimum 1st-place score to avoid extension round (`mahjongsoul.com`, `tenhou.net/man/`). |
| `uma` | `[+15, +5, -5, -15]` (+ room rank Pt) | Room-dependent fixed rank Pt (base `[+20, +10, -10, -20]` in score terms) | Majsoul score screen uses 25,000 return + 5-15 uma; ranked ladder Pt adds room/tier adjustments (`mahjongsoul.com`, `mahjongsoul.info`, `tenhou.net/man/`). |
| `oka` | `0` (25,000 return) | `20` (30,000 return; +20k to 1st) | Majsoul computes raw score delta as `(score - 25000) / 1000` (`mahjongsoul.com`); Tenhou manual states 25,000 start / 30,000 return (`tenhou.net/man/`). |
| `tobi_enabled` | `true` | `true` | Game ends immediately when any player drops below `0` (`mahjongsoul.com`, `tenhou.net/man/`). |
| `tobi_threshold` | `< 0` (`0` continues) | `< 0` (`0` continues) | Exactly `0` points does not bust (`mahjongsoul.com`). |
| `game_length` | `east` (Tonpuu) or `south` (Hanchan) | `east` (Tonpuu) or `south` (Hanchan) | Standard ranked queues (`mahjongsoul.com`, `tenhou.net/man/`). |
| `extension_round_enabled` | `true` (South in East; West in South) | `true` (South in East; West in South) | Triggered if 1st place `< 30000` at end of E4 (Tonpuu) or S4 (Hanchan) (`mahjongsoul.com`, `tenhou.net/man/`). |
| `extension_max_round` | 1 extra round (no North round) | 1 extra round (no North round) | Ends unconditionally after S4 (Tonpuu) or W4 (Hanchan) (`mahjongsoul.com`). |
| `sudden_death_target` | `>= 30000` | `>= 30000` | During extension, game ends immediately after any hand where a player reaches `>= 30000` (`mahjongsoul.com`). |
| `agari_yame` | `true` (automatic) | `true` (automatic) | In All Last, if dealer wins and is 1st with `>= 30000`, game ends automatically (`mahjongsoul.com`, `tenhou.net/man/`). |
| `tenpai_yame` | `true` (automatic) | `true` (automatic) | In All Last, if dealer is tenpai at exhaustive draw and is 1st with `>= 30000`, game ends automatically (`mahjongsoul.com`, `tenhou.net/man/`). |
| `renchan_on_dealer_win` | `true` | `true` | Dealer retains seat and `honba += 1` (`mahjongsoul.com`). |
| `renchan_on_dealer_tenpai` | `true` (tenpai renchan) | `true` (tenpai renchan) | Exhaustive draw: dealer tenpai -> retains seat, `honba += 1`; noten -> seat rotates, `honba += 1` (`mahjongsoul.com`, `tenhou.net/man/`). |
| `renchan_on_abortive_draw` | `true` | `true` | Abortive draw: dealer retains seat, `honba += 1` (`mahjongsoul.com`, `tenhou.net/man/`). |
| `honba_value_ron` | `300` per honba | `300` per honba | Paid by discarder on ron (`mahjongsoul.com`, `tenhou.net/man/`). |
| `honba_value_tsumo` | `100` per opponent per honba (`300` total) | `100` per opponent per honba (`300` total) | Paid equally by all 3 opponents (`mahjongsoul.com`, `tenhou.net/man/`). |
| `aka_dora_count` | `3` | `3` (standard aka rooms) | 1 red five per suit (`mahjongsoul.com`, `tenhou.net/man/`). |
| `aka_dora_tiles` | `0m, 0p, 0s` (one `5m`, `5p`, `5s`) | `0m, 0p, 0s` (one `5m`, `5p`, `5s`) | Each red 5 counts as +1 dora; does not satisfy yaku requirement (`mahjongsoul.com`). |
| `kuitan_enabled` | `true` | `true` (standard ranked rooms) | Open Tanyao allowed (`mahjongsoul.com`, `tenhou.net/man/`). |
| `atozuke_enabled` | `true` | `true` | Open calls permitted before securing a yaku, provided winning tile completes a yaku (`mahjongsoul.com`, `tenhou.net/man/`). |
| `kuikae_allowed` | `false` | `false` | Swap-calling forbidden. After **Pon** of tile `X`: cannot discard `X` (same kind, ignoring red/normal). After **Chi** of `X` with `Y,Z`: cannot discard `X` (same kind) OR the opposite-end suji tile (e.g., chi `4` with `56` forbids `4` and `7`; chi `6` with `45` forbids `6` and `3`; kanchan `5` with `46` forbids `5` only; penchan `3` with `12` forbids `3` only). Call is illegal if no legal discard remains (`mahjongsoul.com`, `tenhou.net/man/`). |
| `double_ron_enabled` | `true` | `true` | Both winners collect full hand score from discarder (`mahjongsoul.com`, `tenhou.net/man/`). |
| `triple_ron_enabled` | `true` | `false` (abortive draw: `sanchahou`) | Majsoul allows all 3 players to win; Tenhou aborts hand (`mahjongsoul.com`, `w.atwiki.jp/mahjongsoul/`, `tenhou.net/man/`). |
| `atamahane_enabled` | `false` | `false` | No head bump for hand wins in ranked; head-bump order still governs riichi sticks/honba (`mahjongsoul.com`, `tenhou.net/man/`). |
| `multi_ron_riichi_sticks` | `closest_ccw` (上家取り) | `closest_ccw` (上家取り) | Winner closest in counter-clockwise turn order from discarder takes all riichi sticks (`mahjongsoul.com`, `tenhou.net/man/`). |
| `multi_ron_honba` | `closest_ccw` (上家取り)* | `closest_ccw` (上家取り) | Only closest winner in turn order receives honba bonus; *see Unverified for conflicting English wiki claims (`mahjongsoul.com`, `mahjong-item.jp`). |
| `multi_ron_renchan` | `any_winner_is_dealer` | `any_winner_is_dealer` | If dealer is among the winners, dealer retains seat and `honba += 1` (`mahjongsoul.com`). |
| `abort_kyuushu_kyuuhai` | `true` | `true` | 9+ distinct terminal/honor tiles on player's 1st unbroken draw (no prior calls, incl. ankan); optional declaration (`mahjongsoul.com`, `tenhou.net/man/`). |
| `abort_suufon_renda` | `true` | `true` | All 4 players discard the same wind on 1st unbroken turn (no prior calls, incl. ankan) (`mahjongsoul.com`, `tenhou.net/man/`). |
| `abort_suucha_riichi` | `true` | `true` | All 4 players declare riichi; triggers after 4th player's riichi discard passes without ron (`mahjongsoul.com`, `tenhou.net/man/`). |
| `abort_suukaikan` | `true` | `true` | 4 total kans by 2+ players; triggers after 4th kan's discard passes without rinshan tsumo or ron (`mahjongsoul.com`, `tenhou.net/man/`). |
| `abort_sanchahou` | `false` | `true` | 3-player ron: all 3 win in Majsoul; abortive draw in Tenhou (`mahjongsoul.com`, `tenhou.net/man/`). |
| `nagashi_mangan_enabled` | `true` | `true` | At exhaustive draw: all own discards are terminals/honors and none were called (`mahjongsoul.com`, `tenhou.net/man/`). |
| `nagashi_mangan_treated_as` | `ryuukyoku` (mangan tsumo payout) | `ryuukyoku` (mangan tsumo payout) | Replaces tenpai/noten payments with mangan tsumo payment (dealer: 4000 all; non-dealer: 2000/4000). Riichi sticks stay on table; honba not paid and increments +1 (`mahjongsoul.com`, `tenhou.net/man/`). |
| `nagashi_mangan_interrupts_renchan` | `false` | `false` | Treated as draw: renchan depends solely on whether dealer is tenpai (`mahjongsoul.com`, `tenhou.net/man/`). |
| `kazoe_yakuman_enabled` | `true` | `true` | `>= 13` han from regular yaku + dora = 1x Yakuman (capped at 1x regardless of han) (`mahjongsoul.com`, `tenhou.net/man/`). |
| `kiriage_mangan_enabled` | `false` | `false` | 30 fu 4 han (`7700`/`11600`) and 60 fu 3 han (`7700`/`11600`) are NOT rounded up to Mangan (`mahjongsoul.com`, `tenhou.net/man/`). |
| `natural_double_yakuman` | `true` (4 hands) | `false` (all 1x) | Majsoul 2x hands: `suuankou_tanki`, `kokushi_13_wait`, `junsei_chuuren`, `daisuushii` (`mahjongsoul.com`, `mahjong-item.jp`). Tenhou treats all 4 as 1x (`tenhou.net/man/`). |
| `yakuman_stacking_enabled` | `true` | `true` | Multiple distinct yakuman sum their multipliers (e.g., Daisangen + Tsuuiisou = 2x; Daisuushii + Tsuuiisou = 3x in Majsoul, 2x in Tenhou) (`mahjongsoul.com`, `tenhou.net/man/`). No cap is applied: no source for a 6x cap was found, and the largest sum the ranked list can reach is 6x anyway (Daisuushii 2 + Suuankou Tanki 2 + Tsuuiisou 1 + Tenhou or Suukantsu 1), so a cap could never bind. |
| `renhou_enabled` | `false` | `false` | Not recognized in ranked (`mahjongsoul.com`, `tenhou.net/man/`). |
| `pao_daisangen` | `true` | `true` | Discarding 3rd dragon melded into open Pon/Daiminkan (`mahjongsoul.com`, `tenhou.net/man/`). |
| `pao_daisuushii` | `true` | `true` | Discarding 4th wind melded into open Pon/Daiminkan (`mahjongsoul.com`, `tenhou.net/man/`). |
| `pao_suukantsu` | `false` | `false` | No pao on 4th kan (`mahjongsoul.com`, `tenhou.net/man/`). |
| `pao_tsumo_split` | `pao_pays_100_percent` | `pao_pays_100_percent` | On tsumo, liable player pays full yakuman + honba (`mahjongsoul.com`, `tenhou.net/man/`). |
| `pao_ron_split` | `50_50_with_discarder` | `50_50_with_discarder` | On ron by 3rd party, liable player and discarder split yakuman 50/50 (the liable player pays the honba, per the ranked rules publication `mahjongsoul.com/news/46/`; if the liable player deals in, pays 100%) (`mahjongsoul.com`). Pao is out of scope for the shootout's `score` op, which answers the ordinary payment. |
| `pao_composite_yakuman` | `liable_yakuman_only` | `whole_hand` | In composite yakuman (e.g., Daisangen + Tsuuiisou), pao applies only to the Daisangen portion; other yakuman paid normally (`mahjongsoul.com`). Tenhou: 「複合役満を含む得点を、ツモ＝全額・ロン＝折半で支払う。積み棒は包。」, so pao covers the whole composite hand. (Tenhou column corrected after the Phase 3 design review, from the manual text at `tenhou.net/man/`.) |
| `riichi_min_points` | `1000` | `1000` | Having exactly `1000` points is allowed (drops to `0`, no tobi) (`mahjongsoul.com`, `tenhou.net/man/`). |
| `riichi_min_live_wall_tiles` | `4` | `4` | Must have `>= 4` tiles left in live wall (caller has at least 1 draw remaining) (`mahjongsoul.com`, `tenhou.net/man/`). |
| `riichi_furiten_allowed` | `true` | `true` | Declaring riichi while furiten is legal (`mahjongsoul.com`). |
| `riichi_karaten_allowed` | `true` | `true` | Declaring riichi with 0 live winning tiles (karaten) is legal when the missing copies are elsewhere at the table (`mahjongsoul.com`). A wait that exists only as a fifth copy of a kind the hand already holds four of does not count as tenpai for riichi (`spec/formats.md`, `legal`). |
| `endgame_riichi_sticks` | `awarded_to_first_place` | `awarded_to_first_place` | Unclaimed riichi sticks at game end go to 1st place (`mahjongsoul.com`, `tenhou.net/man/`). |
| `riichi_ankan_rule` | `same_waits_no_okurikan` | `same_waits_no_okurikan` | Must kan the just-drawn tile (no okurikan) and the set of wait kinds must be unchanged. Only the waits are compared: a kan that changes the hand's decomposition or its yaku is allowed (`mahjongsoul.com/news/46/`, `tenhou.net/man/`, riichi.wiki/Kan). |
| `kan_dora_ankan_timing` | `immediate` | `immediate` | Flipped immediately on declaration (active for rinshan draw) (`mahjongsoul.com`, `w.atwiki.jp/mahjongsoul/`). |
| `kan_dora_daiminkan_timing` | `after_discard` | `at_discard` | Flipped after discard passes without ron (or right before a subsequent kan); not active on rinshan tsumo (`mahjongsoul.com`, `w.atwiki.jp/mahjongsoul/`). Tenhou: 「明槓/加槓は後めくり（打牌または続く嶺上の直前）」: the indicator is turned at the discard, or just before the next replacement draw, so a ron on the post-kan discard does count it. Mahjong Soul behaviour on that ron stays unverified. (Tenhou column corrected after the Phase 3 design review, from the manual text at `tenhou.net/man/`.) |
| `kan_dora_shouminkan_timing` | `after_discard` | `at_discard` | Same as daiminkan; not flipped if robbed via chankan or on rinshan tsumo (`mahjongsoul.com`, `w.atwiki.jp/mahjongsoul/`). Tenhou: 「明槓/加槓は後めくり（打牌または続く嶺上の直前）」: the indicator is turned at the discard, or just before the next replacement draw, so a ron on the post-kan discard does count it. Mahjong Soul behaviour on that ron stays unverified. (Tenhou column corrected after the Phase 3 design review, from the manual text at `tenhou.net/man/`.) |
| `rinshan_tsumo_fu` | `2` | `2` | Standard +2 tsumo fu applies to Rinshan Kaihou (`mahjongsoul.com`, `tenhou.net/man/`). |
| `pinfu_tsumo_20_fu` | `true` | `true` | Pinfu + Tsumo is fixed 20 fu (no +2 tsumo fu) (`mahjongsoul.com`, `tenhou.net/man/`). |
| `chiitoitsu_25_fu` | `true` | `true` | Chiitoitsu is fixed 25 fu (no rounding to 30) (`mahjongsoul.com`, `tenhou.net/man/`). |
| `open_pinfu_ron_30_fu` | `true` | `true` | Open hand with 0 extra fu on ron scores 30 fu (not 20 fu) (`mahjongsoul.com`, `tenhou.net/man/`). |
| `double_wind_pair_fu` | `4` | `4` | Seat wind == round wind pair awards 4 fu (breaks pinfu) (`game8.jp/jantama/`, `tenhou.net/man/`). |
| `chankan_ankan_kokushi` | `true` | `false` | Robbing an ankan is allowed exclusively for Kokushi Musou. In practice only a single-wait kokushi waiting on that kind (holding no copy of it) can do so: a 13-sided wait holds one copy, and four more are in the kan (`mahjongsoul.com`, `tenhou.net/man/`). Tenhou: 「他家が暗槓した牌では国士無双はあがれない」, so no robbery of a closed kan at all. (Tenhou column corrected after the Phase 3 design review, from the manual text at `tenhou.net/man/`.) |
| `furiten_discard` | `true` | `true` | Cannot ron if any wait tile is in own discards (including called-away discards) (`mahjongsoul.com`). |
| `furiten_temporary` | `true` (until next own draw; unverified whether a call clears it) | `true` (until next own draw) | Passing a ron opportunity forbids ron until own next draw/call (`mahjongsoul.com`). Tenhou: lasts until the next own draw (「次の自分のツモ番まで」); a call in between does not clear it (「逆巡副露では解消しない」). Applies also when the tile could not be ronned for lack of yaku. (Tenhou column corrected after the Phase 3 design review, from the manual text at `tenhou.net/man/`.) Mahjong Soul column changed from "draw/call" to "next own draw" after the Phase 3 reviews: the published ranked rules name the next own draw; whether a call in between clears it is not checked in a client, and the engine has a `Rules` field for it (default: not cleared). |
| `furiten_riichi` | `true` | `true` | Passing any winning tile after declaring riichi makes player permanently furiten for the hand (`mahjongsoul.com`). |
| `last_tile_kan_allowed` | `false` | `false` | Cannot declare ankan/shouminkan on haitei draw or daiminkan on houtei discard (0 live wall tiles left) (`mahjongsoul.com`, `tenhou.net/man/`). |
| `ryuukyoku_tenpai_pool` | `3000` total | `3000` total | 1 tenpai: +3000 / -1000 each; 2 tenpai: +1500 / -1500; 3 tenpai: +1000 / -3000; 0 or 4 tenpai: 0 (`mahjongsoul.com`, `tenhou.net/man/`). |
| `tie_break_order` | `seat_order_from_east_1` (E > S > W > N) | `seat_order_from_east_1` (E > S > W > N) | Closer to starting East (chiicha) ranks higher (`mahjongsoul.com`, `tenhou.net/man/`). |
| `max_kans_per_hand` | `4` | `4` | Only 4 rinshan tiles exist in the dead wall (`mahjongsoul.com`, `tenhou.net/man/`). |
| `fifth_kan_allowed_on_suukantsu` | `false` | `false` | Even when 1 player has 4 kans (suukantsu tenpai), no 5th kan may be declared by anyone (`mahjongsoul.com`, `tenhou.net/man/`). |

---

## 2. Full Yaku & Yakuman List (Mahjong Soul Ranked)

### 2.1 Standard Yaku

| Japanese | English | Closed | Open | Condition / Notes |
| :--- | :--- | :---: | :---: | :--- |
| 立直 (Riichi) | Riichi | 1 | — | Closed tenpai, `>= 1000` pts, `>= 4` live wall tiles; bets 1000 pts. |
| 一発 (Ippatsu) | Ippatsu | 1 | — | Win within 1 unbroken turn cycle after riichi; broken by any completed call (incl. ankan). An added kan robbed by chankan never completes, so chankan and ippatsu combine. |
| 門前清自摸和 (Menzen Tsumo) | Fully Concealed Tsumo | 1 | — | Self-draw win with closed hand. |
| 平和 (Pinfu) | Pinfu | 1 | — | Closed; 4 sequences, non-yakuhai pair, ryanmen wait (0 extra fu). |
| 断么九 (Tanyao) | All Simples | 1 | 1 | Only 2–8 numbered tiles (Kuitan enabled). |
| 一盃口 (Iipeikou) | Pure Double Sequence | 1 | — | Closed; 2 identical sequences in same suit. Does not stack with Ryanpeikou. |
| 役牌 (Yakuhai) | Value Triplet | 1 | 1 | Triplet/kan of any dragon (Haku/Hatsu/Chun), seat wind, or round wind. Double wind = 2 han. |
| 嶺上開花 (Rinshan Kaihou) | After a Kan | 1 | 1 | Tsumo on dead-wall replacement tile after any kan. |
| 槍槓 (Chankan) | Robbing a Kan | 1 | 1 | Ron on opponent's shouminkan (kakan). |
| 海底摸月 (Haitei Raoyue) | Under the Sea | 1 | 1 | Tsumo on the very last tile of the live wall. |
| 河底撈魚 (Houtei Raoyui) | Under the River | 1 | 1 | Ron on the discard after the very last live wall draw. |
| ダブル立直 (Double Riichi) | Double Riichi | 2 | — | Riichi on 1st unbroken draw (no prior calls, incl. ankan). Replaces 1-han Riichi. |
| 三色同順 (Sanshoku Doujun) | Mixed Triple Sequence | 2 | 1 | Same numerical sequence in all 3 suits. |
| 三色同刻 (Sanshoku Doukou) | Triple Triplets | 2 | 2 | Same numerical triplet/kan in all 3 suits. |
| 三暗刻 (Sanankou) | Three Concealed Triplets | 2 | 2 | 3 concealed triplets/ankans (hand itself may be open via 4th meld). |
| 一気通貫 (Ittsuu) | Pure Straight | 2 | 1 | `123`, `456`, `789` in one suit. |
| 七対子 (Chiitoitsu) | Seven Pairs | 2 | — | Closed; 7 distinct pairs (fixed 25 fu; cannot reuse same tile for 2 pairs). |
| 対々和 (Toitoi) | All Triplets | 2 | 2 | 4 triplets/kans + pair. |
| 混全帯么九 (Chanta) | Half Outside Hand | 2 | 1 | Every meld and pair contains a terminal or honor (at least 1 sequence & 1 honor). |
| 三槓子 (Sankantsu) | Three Kans | 2 | 2 | 3 kans (open or closed). |
| 混老頭 (Honroutou) | All Terminals and Honors | 2 | 2 | Only 1s, 9s, honors. Always combines with Toitoi or Chiitoitsu (min 4 han). |
| 小三元 (Shousangen) | Little Three Dragons | 2 | 2 | 2 dragon triplets/kans + 1 dragon pair (always +2 Yakuhai = min 4 han). |
| 混一色 (Honitsu) | Half Flush | 3 | 2 | One numbered suit + honors. |
| 純全帯么九 (Junchan) | Fully Outside Hand | 3 | 2 | Every meld and pair contains a terminal (at least 1 sequence, no honors). |
| 二盃口 (Ryanpeikou) | Twice Pure Double Sequence | 3 | — | Closed; 2 pairs of identical sequences (4 melds + 1 pair; does NOT combine with Chiitoitsu or Iipeikou). |
| 清一色 (Chinitsu) | Full Flush | 6 | 5 | One numbered suit only (no honors). |

*Dora (indicator dora, kan dora, ura dora, aka dora) add 1 han each, but are **not yaku** and cannot satisfy the 1-yaku minimum.*

### 2.2 Yakuman List

| Japanese | English | Closed Only? | Majsoul Ranked | Tenhou Ranked | Condition / Notes |
| :--- | :--- | :---: | :---: | :---: | :--- |
| 天和 (Tenhou) | Blessing of Heaven | Yes (Dealer) | 1x | 1x | Dealer wins on initial 14-tile dealt hand. Any of the 14 tiles may be treated as the winning tile and the best choice is scored, so tenhou with kokushi, suuankou or chuuren always takes the double form (`kokushi_13`, `suuankou_tanki`, `junsei_chuuren`) in Majsoul (`mahjongsoul.com/news/46/`, riichi.wiki/Mahjong_Soul). |
| 地和 (Chiihou) | Blessing of Earth | Yes (Non-dealer) | 1x | 1x | Non-dealer wins on 1st unbroken draw (no prior calls, incl. ankan). The drawn tile is the winning tile (no free choice as for tenhou). |
| 国士無双 (Kokushi Musou) | Thirteen Orphans | Yes | 1x | 1x | 1 of each terminal/honor + 1 duplicate (single wait). |
| 国士無双十三面待ち (Kokushi 13-Wait) | Thirteen Orphans (13-Wait) | Yes | **2x** | 1x | Holding all 13 unique terminals/honors, winning on any of the 13. |
| 四暗刻 (Suuankou) | Four Concealed Triplets | Yes | 1x | 1x | 4 concealed triplets/ankans; shanpon wait must be won by tsumo. |
| 四暗刻単騎 (Suuankou Tanki) | Four Concealed Triplets (Single Wait) | Yes | **2x** | 1x | 4 completed concealed triplets/ankans, waiting on pair (ron or tsumo). |
| 大三元 (Daisangen) | Big Three Dragons | No | 1x | 1x | Triplets/kans of all 3 dragons (Pao applies). |
| 小四喜 (Shousuushii) | Little Four Winds | No | 1x | 1x | 3 wind triplets/kans + 1 wind pair. |
| 大四喜 (Daisuushii) | Big Four Winds | No | **2x** | 1x | 4 wind triplets/kans (Pao applies). |
| 字一色 (Tsuuiisou) | All Honors | No | 1x | 1x | All tiles are winds/dragons (valid as 4 melds + pair OR 7 pairs). |
| 清老頭 (Chinroutou) | All Terminals | No | 1x | 1x | All tiles are 1s and 9s. |
| 緑一色 (Ryuuiisou) | All Green | No | 1x | 1x | Only `2s, 3s, 4s, 6s, 8s, Hatsu` (`Hatsu` is optional). |
| 九蓮宝燈 (Chuuren Poutou) | Nine Gates | Yes (no kan) | 1x | 1x | `1112345678999` + 1 extra tile in one suit (non-9-way wait). |
| 純正九蓮宝燈 (Junsei Chuuren) | True Nine Gates (9-Wait) | Yes (no kan) | **2x** | 1x | Holding exact `1112345678999` in one suit, winning on any tile 1–9. |
| 四槓子 (Suukantsu) | Four Kans | No | 1x | 1x | 4 kans (open or closed) + pair (No Pao). |
| 数え役満 (Kazoe Yakuman) | Counted Yakuman | No | 1x | 1x | `>= 13` han from normal yaku + dora (does not stack into 2x). |

### 2.3 Local Yaku NOT Used in Mahjong Soul Ranked

- **Renhou (人和)** — Blessing of Man (disabled in ranked; optional yakuman in friendly rooms).
- **Open Riichi (オープン立直)** — Not implemented.
- **Daisharin (大車輪) / Daichikurin (大竹林) / Daisuuring (大数隣)** — 2–8 single-suit seven pairs (disabled in ranked; optional in friendly rooms).
- **Paarenchan (八連荘)** — 8 consecutive dealer wins (not implemented).
- **Daichisei (大七星)** — 7-pair All Honors is scored as regular 1x `Tsuuiisou` in ranked, NOT as a separate 2x local yakuman.
- **Other local yaku disabled in ranked**: Sanrenkou (三連刻), Iishoku Sanjun (一色三順), Shiisanputaa (十三不塔), Uumensai (五門斉), Tsubamegaeshi (燕返し), Kanburi (槓振り), Beni Kujaku (紅孔雀), Hyakumangoku (百万石), Nagashi Mangan as a yaku (it is a draw settlement, not a winning hand yaku).

---

## 3. Fu Calculation & Score Tables

### 3.1 Fu Calculation Table

| Component | Condition | Fu |
| :--- | :--- | :---: |
| **Base (Fuutei)** | Every standard 4-meld + 1-pair hand | `20` |
| **Menzen Ron** | Closed hand won by Ron | `+10` |
| **Tsumo** | Won by Tsumo (EXCEPT Pinfu Tsumo) | `+2` |
| **Sequence (Shuntsu)** | Open or closed | `0` |
| **Open Triplet (Minkou)** | Simples (2–8) / Terminals & Honors | `+2` / `+4` |
| **Closed Triplet (Ankou)** | Simples (2–8) / Terminals & Honors | `+4` / `+8` |
| **Open Kan (Minkan)** | Simples (2–8) / Terminals & Honors | `+8` / `+16` |
| **Closed Kan (Ankan)** | Simples (2–8) / Terminals & Honors | `+16` / `+32` |
| **Pair (Jantou)** | Non-yakuhai | `0` |
| **Pair (Jantou)** | Dragon, Seat Wind, or Round Wind (single) | `+2` |
| **Pair (Jantou)** | Double Wind (Seat Wind == Round Wind) | `+4` |
| **Wait** | Ryanmen (two-sided) or Shanpon (dual-pon) | `0` |
| **Wait** | Kanchan (closed), Penchan (edge), or Tanki (pair) | `+2` |
| **Rounding** | Sum rounded **up** to nearest multiple of `10` (e.g., `22 -> 30`, `32 -> 40`) | `ceil(fu / 10) * 10` |

**Fixed-Fu Exceptions (override the table above):**
1. **Pinfu + Tsumo**: Fixed **`20` fu** (no +2 tsumo fu).
2. **Chiitoitsu**: Fixed **`25` fu** (not rounded up to 30).
3. **Open Pinfu-shape Ron**: Open hand with 0 extra fu won by Ron scores **`30` fu** (minimum 30 fu for open ron).
4. **Multiple hand decompositions**: Yaku from different decompositions never combine. Choose the decomposition with the **highest total payment**. Only on an equal total: a real yakuman beats a kazoe yakuman, then higher han, then higher fu, then the yaku list that sorts first as a string (`spec/formats.md`). Han does not come first: a 3 han 70 fu ron (8000) beats a 4 han 30 fu ron (7700).

### 3.2 Basic Points & Limit Thresholds

- **Formula (below Mangan)**: $\text{basic} = \text{fu} \times 2^{2 + \text{han}}$
- **Limit Caps (No Kiriage Mangan)**:
  - **Mangan** (`basic = 2000`): `5` han; `4` han at `>= 40` fu; `3` han at `>= 70` fu. *(Note: `4` han `30` fu = `1920` basic and `3` han `60` fu = `1920` basic are NOT Mangan.)*
  - **Haneman** (`basic = 3000`): `6–7` han.
  - **Baiman** (`basic = 4000`): `8–10` han.
  - **Sanbaiman** (`basic = 6000`): `11–12` han.
  - **Yakuman / Kazoe Yakuman** (`basic = 8000`): `>= 13` han or 1x Yakuman.
  - **N-tuple Yakuman**: `basic = 8000 * N`.
- **Payment Formulas** (each individual payment rounded **up** to nearest `100`):
  - **Non-dealer Ron**: `ceil100(4 * basic)` from discarder.
  - **Non-dealer Tsumo**: `ceil100(2 * basic)` from dealer, `ceil100(1 * basic)` from each non-dealer.
  - **Dealer Ron**: `ceil100(6 * basic)` from discarder.
  - **Dealer Tsumo**: `ceil100(2 * basic)` from each of the 3 non-dealers.

### 3.3 Score Lookup Table — Non-Dealer (`Ron` / `Tsumo non-dealer, dealer`)

| Fu | 1 Han | 2 Han | 3 Han | 4 Han |
| :---: | :---: | :---: | :---: | :---: |
| **20** | — | `—` / `400, 700` | `—` / `700, 1300` | `—` / `1300, 2600` |
| **25** | — | `1600` / `—` | `3200` / `800, 1600` | `6400` / `1600, 3200` |
| **30** | `1000` / `300, 500` | `2000` / `500, 1000` | `3900` / `1000, 2000` | `7700` / `2000, 3900` |
| **40** | `1300` / `400, 700` | `2600` / `700, 1300` | `5200` / `1300, 2600` | `8000` / `2000, 4000` |
| **50** | `1600` / `400, 800` | `3200` / `800, 1600` | `6400` / `1600, 3200` | `8000` / `2000, 4000` |
| **60** | `2000` / `500, 1000` | `3900` / `1000, 2000` | `7700` / `2000, 3900` | `8000` / `2000, 4000` |
| **70** | `2300` / `600, 1200` | `4500` / `1200, 2300` | `8000` / `2000, 4000` | `8000` / `2000, 4000` |
| **80** | `2600` / `700, 1300` | `5200` / `1300, 2600` | `8000` / `2000, 4000` | `8000` / `2000, 4000` |
| **90** | `2900` / `800, 1500` | `5800` / `1500, 2900` | `8000` / `2000, 4000` | `8000` / `2000, 4000` |
| **100** | `3200` / `800, 1600` | `6400` / `1600, 3200` | `8000` / `2000, 4000` | `8000` / `2000, 4000` |
| **110** | `3600` / `900, 1800` | `7100` / `1800, 3600` | `8000` / `2000, 4000` | `8000` / `2000, 4000` |

### 3.4 Score Lookup Table — Dealer (`Ron` / `Tsumo all`)

| Fu | 1 Han | 2 Han | 3 Han | 4 Han |
| :---: | :---: | :---: | :---: | :---: |
| **20** | — | `—` / `700 all` | `—` / `1300 all` | `—` / `2600 all` |
| **25** | — | `2400` / `—` | `4800` / `1600 all` | `9600` / `3200 all` |
| **30** | `1500` / `500 all` | `2900` / `1000 all` | `5800` / `2000 all` | `11600` / `3900 all` |
| **40** | `2000` / `700 all` | `3900` / `1300 all` | `7700` / `2600 all` | `12000` / `4000 all` |
| **50** | `2400` / `800 all` | `4800` / `1600 all` | `9600` / `3200 all` | `12000` / `4000 all` |
| **60** | `2900` / `1000 all` | `5800` / `2000 all` | `11600` / `3900 all` | `12000` / `4000 all` |
| **70** | `3400` / `1200 all` | `6800` / `2300 all` | `12000` / `4000 all` | `12000` / `4000 all` |
| **80** | `3900` / `1300 all` | `7700` / `2600 all` | `12000` / `4000 all` | `12000` / `4000 all` |
| **90** | `4400` / `1500 all` | `8700` / `2900 all` | `12000` / `4000 all` | `12000` / `4000 all` |
| **100** | `4800` / `1600 all` | `9600` / `3200 all` | `12000` / `4000 all` | `12000` / `4000 all` |
| **110** | `5300` / `1800 all` | `10600` / `3600 all` | `12000` / `4000 all` | `12000` / `4000 all` |

### 3.5 Limit Hands Summary

| Tier | Han | Basic | Non-Dealer (Ron / Tsumo) | Dealer (Ron / Tsumo) |
| :--- | :---: | :---: | :---: | :---: |
| **Mangan** | 5 (or 4/40, 3/70) | 2000 | `8000` / `2000, 4000` | `12000` / `4000 all` |
| **Haneman** | 6–7 | 3000 | `12000` / `3000, 6000` | `18000` / `6000 all` |
| **Baiman** | 8–10 | 4000 | `16000` / `4000, 8000` | `24000` / `8000 all` |
| **Sanbaiman** | 11–12 | 6000 | `24000` / `6000, 12000` | `36000` / `12000 all` |
| **Yakuman (1x)** | 13+ / Yakuman | 8000 | `32000` / `8000, 16000` | `48000` / `16000 all` |
| **Double Yakuman (2x)** | 2x Yakuman | 16000 | `64000` / `16000, 32000` | `96000` / `32000 all` |

---

## 4. Tricky Edge Cases (Test Cases for Mahjong Soul Ranked)

1. **Ron on 3rd concealed triplet breaks Sanankou**: Holding two concealed triplets + shanpon wait (`22m 55p`) + 1 sequence, winning by Ron on `2m` makes `222m` an *open* triplet (2 fu, not 4 fu) and **Sanankou does not count**. Winning by Tsumo counts Sanankou.
2. **Shanpon Ron on 4 concealed triplets is NOT Suuankou**: Holding 3 concealed triplets + shanpon wait (`22m 55p`), Ron on `2m` scores **Sanankou + Toitoi** (not Suuankou). Tsumo scores 1x Suuankou.
3. **Suuankou Tanki on Ron IS 2x Yakuman**: Holding 4 completed concealed triplets + single tile `5p`, Ron or Tsumo on `5p` scores **Double Yakuman** (2x) in Mahjong Soul (1x in Tenhou).
4. **Ryanpeikou is NOT Chiitoitsu**: `223344m 556677p 88s` is scored as 4 sequences + 1 pair (**Ryanpeikou**, 3 han, normal fu), NOT Chiitoitsu, and does not stack with Iipeikou or Chiitoitsu.
5. **Pinfu requires ryanmen wait and non-yakuhai pair**: A closed all-sequence hand with a dragon/seat-wind/round-wind pair, or a kanchan/penchan/tanki wait (including nobetan `2345m` waiting `2m`/`5m`, which is tanki), does **not** score Pinfu.
6. **Ambiguous wait chooses highest-scoring interpretation**: Closed `2233445m 234p 678s` winning on `5m` by ron reads either as `22m 345m 345m` (the `5m` completes `34m`, a ryanmen: pinfu + iipeikou + tanyao = 3 han 30 fu, `3900` non-dealer) or as `234m 234m 55m` (tanki on `5m`: iipeikou + tanyao, 30 + 2 = 32 -> 40 fu, 2 han 40 fu = `2600`). The pinfu reading pays more and is scored. The other direction also happens: `111222333m 456p 7s` + ron `7s` scores the triplet reading (riichi + sanankou, 3 han 50 fu = `6400`) over the `123m` x3 reading (riichi + iipeikou, 2 han 40 fu = `2600`). (Both checked against the oracle, and the second is `corpus/handwritten.txt` hw87.)
7. **Pinfu + Tsumo is 20 fu**: Closed Pinfu hand won by Tsumo scores **20 fu** (not 22 -> 30 fu); minimum 2 han (Pinfu + Menzen Tsumo = `400/700` non-dealer, `700 all` dealer).
8. **Open Pinfu-shape Ron is 30 fu**: Open hand with 4 sequences, non-yakuhai pair, ryanmen wait won by Ron (0 extra fu) scores **30 fu** (`1000` at 1 han non-dealer), never 20 fu.
9. **Open Pinfu-shape Tsumo is 30 fu**: Same open hand won by Tsumo gets `20 + 2 (tsumo) = 22 -> 30 fu` (`300/500` at 1 han non-dealer).
10. **Chiitoitsu is fixed 25 fu and forbids 4-of-a-kind**: `2222m` cannot be used as two `2m` pairs in Chiitoitsu; Chiitoitsu is always 25 fu (never rounded to 30 fu), even on Tsumo.
11. **Double-wind pair is 4 fu**: East player in East round with `EE` pair gets `+4 fu` for the pair (breaks Pinfu; e.g., open `EE` pair + 3 simple sequences + simple open triplet = `20 + 4 + 2 = 26 -> 30 fu`, or closed ron `20 + 10 + 4 = 34 -> 40 fu`).
12. **Kuikae after Chi (suji swap forbidden)**: Calling `4m` with `56m` forbids discarding `4m` or `7m` on that turn. Calling `5m` (or `0m`) with `67m` forbids discarding `5m`, `0m`, or `8m`. Calling kanchan `5m` with `46m` forbids `5m`/`0m` only.
13. **Kuikae after Pon & dead-end call prohibition**: Calling Pon on `5m` forbids discarding `5m` or `0m`. If a call would leave only forbidden tiles in hand (e.g., 4 tiles left `4567m`, calling `4m` with `56m` leaves `47m`), the call itself is **illegal**.
14. **Riichi Ankan: only the waits are compared**: After riichi with `123456m 4445s 111z` (waiting `3s` via `345+44`, `5s` via `444+55`, `6s` via `456+44`), drawing the 4th `4s` may **not** be kanned: after `ankan 4444s` the hand waits only on `5s` (tanki). With `23m 999p 33345666s` (waits `1m`/`4m`; the souzu read `333+456+66` or `33+345+666`), drawing the 4th `6s` **may** be kanned: the `333+456+66` reading disappears, but the waits stay `1m`/`4m`. Okurikan (kanning a quad that does not use the just-drawn tile) is always illegal after riichi.
15. **Chankan on Shouminkan flips no kan dora**: If Player B robs Player A's added kan (`shouminkan`), Player A draws no rinshan tile, **no kan dora is revealed**, and Player B receives `+1 han` (Chankan).
16. **Chankan on Ankan is Kokushi-only**: Player A declares Ankan of `1m`. Player B waiting on `1m` for a normal hand (or Suuankou/Chinroutou) **cannot** ron. Player B holding `9m 19p 19s 1234567z` plus a duplicate (single-wait kokushi on `1m`) **can** ron, before the rinshan draw. A 13-sided kokushi wait cannot arise here: it holds one `1m`, and the kan holds the other four.
17. **Kan dora timing differs between Ankan and Minkan**: On Ankan, the new kan dora indicator flips **immediately** and counts toward a Rinshan Kaihou win. On Daiminkan or Shouminkan, the new kan dora does **not** flip until after the caller discards (so it does **not** count toward a Rinshan Kaihou win).
18. **Haitei Raoyue and Rinshan Kaihou cannot combine**: Declaring a kan on the last live wall tile (0 live tiles remaining) is illegal, and rinshan draws come from the dead wall, so Haitei + Rinshan is impossible.
19. **Houtei Raoyui and Chankan cannot combine**: Because no kan is allowed on the last live tile, a chankan can never occur on the houtei discard.
20. **No Kiriage Mangan**: Non-dealer `4 han 30 fu` = `7700` (Ron) / `2000, 3900` (Tsumo); Dealer `4 han 30 fu` = `11600` / `3900 all`. Same for `3 han 60 fu`.
21. **Triple Ron (Sanchahou) pays all 3 in Majsoul**: When 3 players ron the same discard in Mahjong Soul ranked, **all 3 win** (no abortive draw, unlike Tenhou). Only the winner closest counter-clockwise from the discarder receives the riichi sticks (and honba); if the dealer is any of the 3 winners, dealer retains seat.
22. **Suukaikan timing vs Rinshan/Ron**: When a 2nd player declares the 4th kan of the hand, the hand does **not** abort immediately; the caller draws the rinshan tile (may win by Rinshan Kaihou) and discards (opponents may Ron). Only if the discard passes without a win does `suukaikan` abort the hand.
23. **Suukantsu allows no 5th kan**: If a single player makes 4 kans, the hand continues (no `suukaikan`), but **no player** may declare a 5th kan (dead wall has only 4 replacement tiles).
24. **Suucha Riichi timing**: The 4th player's riichi discard can still be Ron'd. Only if it passes without Ron does `suucha_riichi` abort the hand (the 4th player's 1,000-point riichi stick remains on the table).
25. **Any call cancels 1st-turn specials**: An opponent's Chi, Pon, Daiminkan, OR **Ankan** before a player's first draw cancels **Double Riichi**, **Chiihou**, **Kyuushu Kyuuhai**, and **Suufon Renda**.
26. **Ippatsu cancelled by any completed call, including Ankan**: Any completed call (Chi, Pon, Daiminkan, Shouminkan, or Ankan)—even the riichi player's own Ankan—cancels **Ippatsu** for all riichi players. A Shouminkan robbed by Chankan is not completed, so it does **not** cancel Ippatsu: Riichi + Ippatsu + Chankan is a valid combination (riichi.wiki/Ippatsu, riichi.wiki/Chankan; `corpus/handwritten.txt` hw89–hw90).
27. **Furiten checks ALL waits, including yaku-less waits**: If an open hand waits on `1m` (no yaku) and `4m` (Tanyao) and `1m` is in the player's own discards, the player is **furiten** and cannot Ron `4m` either (must win by Tsumo).
28. **Temporary vs Riichi Furiten**: Outside riichi, passing a Ron (or being unable to Ron due to no yaku) triggers temporary furiten until your next draw (a call in between does not clear it; see `furiten_temporary`). After declaring riichi, passing **any** winning tile (discarded or self-drawn) makes you **permanently furiten** for the rest of the hand.
29. **Tobi at `< 0`, NOT `0`**: A player with `1000` points may legally declare riichi (dropping to `0`); the game continues. Dropping to `-100` ends the game immediately.
30. **Nagashi Mangan does not interrupt dealer tenpai renchan**: If non-dealer achieves Nagashi Mangan at exhaustive draw while dealer is tenpai, the non-dealer receives `2000/4000` (replacing tenpai payments), riichi sticks remain on table, `honba += 1`, and **dealer retains seat**. If multiple players achieve Nagashi Mangan, all qualifying players are paid.
31. **Pao on composite yakuman applies only to the liable yakuman**: If Player A feeds the 3rd dragon for **Daisangen** and the winner also completes **Tsuuiisou** (2x Yakuman total) by Tsumo, Player A pays 100% of the Daisangen yakuman + honba, while the Tsuuiisou yakuman is split normally among all 3 opponents. On a ron by a third party, Player A and the discarder split the Daisangen yakuman 50/50 and Player A pays the honba (ranked rules publication; see `pao_ron_split`).
32. **No Pao on Suukantsu**: Discarding the tile called for a player's 4th kan (Daiminkan) does **not** trigger Pao in Mahjong Soul or Tenhou.
33. **Kazoe Yakuman never exceeds 1x**: A non-yakuman hand with 26 han (e.g., 14 han yaku + 12 dora) is still a **single** Kazoe Yakuman (`32000`/`48000`), never a Double Yakuman.
34. **Natural Yakuman ignores regular yaku & dora**: A natural Yakuman (e.g., Daisangen + 4 dora) scores only the Yakuman value; dora and normal yaku do not add to it.
35. **Ryuuiisou does not require Hatsu**: A hand made purely of `2s, 3s, 4s, 6s, 8s` (with zero Green Dragons) is a valid **Ryuuiisou** (and does not also score Chinitsu).
36. **Chuuren Poutou forbids Ankan**: Even though Ankan keeps a hand "closed," declaring an Ankan breaks the 14-tile `1112345678999+X` shape and invalidates Chuuren Poutou.
37. **Call priority**: On any discard, **Ron > Pon / Daiminkan > Chi**.

---

## 5. Unverified / Conflicting Items

1. **`riichi.wiki` live text**: `https://riichi.wiki` was unindexed/unreachable via web search during this research pass; all rules were cross-verified via `mahjongsoul.com` mirrors, `tenhou.net/man/`, `w.atwiki.jp/mahjongsoul/`, `mahjong-item.jp`, and `game8.jp`.
2. **Mahjong Soul Multi-Ron Honba**: Japanese official-rule summaries (`mahjongsoul.com`, `mahjong-item.jp`, `note.com`) state that on Double/Triple Ron **only the closest winner counter-clockwise (`上家取り`)** receives honba (matching Tenhou), whereas several English Reddit threads claim every winner receives honba. Recorded as `closest_ccw` above; verify directly in a Mahjong Soul client replay.
3. **Riichi Ankan that preserves exact waits but changes mentsu decomposition**: *Resolved after the Phase 1 review*: allowed. The ranked rules publication (`mahjongsoul.com/news/46/`), the Tenhou manual and riichi.wiki/Kan all compare only the wait kinds; changes of shape or yaku are allowed (see item 14). Not checked in a client.
4. **Daiminkan / Shouminkan kan dora flip on Ron of the post-kan discard**: Secondary sources state the kan dora is not active if the post-kan discard is Ron'd (it flips only after the discard passes cleanly or right before a chained kan); verify exact frame/order in Mahjong Soul client logs.
5. **Chankan on Shouminkan + Ippatsu**: *Resolved after the Phase 1 review*: they combine (item 26). The earlier text here had it backwards. Sources: riichi.wiki/Ippatsu and /Chankan, and agreement of all three reviewers; not checked in a client.
6. **Nagashi Mangan + All-Last Tenpai-Yame edge case**: Exact behavior when All-Last dealer is 1st (`>= 30000`) and tenpai, and a non-dealer's Nagashi Mangan drops the dealer out of 1st or below `30000` (whether tenpai-yame checks post-Nagashi scores) was not confirmed from primary documentation.
7. **Tenhou formal tenpai on a fifth copy** (added after the Phase 3 design review): Tenhou's manual counts a hand as tenpai at an exhaustive draw when its only wait is a tile it already shows four of, as long as the four are not all in the concealed hand (「5枚目を待つ聴牌あり(手牌＝純手牌＋副露手牌として純手牌で４枚使用していなければ成立)」). Whether Mahjong Soul does the same, and whether either allows riichi on such a hand, is unverified; `spec/formats.md` currently says no riichi.
8. **Tenhou sudden death and dealer repeat**: 「30000点(供託未収)以上になった時点で終了、ただし親の連荘がある場合は連荘を優先する」. The 30,000 test excludes sticks on the table, and a dealer repeat takes priority over ending unless the dealer is the one in first on 30,000 or more. Mahjong Soul's handling of the same case is unverified.
9. **Four winds on the fourth discard**: whether a riichi declared on that discard pays its stick, and the order of the abort against a (practically impossible) ron, are unverified for both clients. libriichi aborts at the discard.
10. **Kan dora order in chained kans on Mahjong Soul**: unverified; Tenhou's is in the `kan_dora_*` rows.
