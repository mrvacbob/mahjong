# Scenario Index

132 hand-worked scenario tests (`scenarios/*.scn`), validated and expanded to JSON by `tools/scenario.py`.

| Scenario | Rules | What it pins down | Source rule | Status |
| :--- | :---: | :--- | :--- | :---: |
| `abort_kyuushu_kyuuhai` | mahjongsoul | Nine distinct terminals/honors on 1st unbroken draw aborts immediately | `engine.md §4.2`, `rules.md §1, §4.25` | verified |
| `abort_suucha_riichi` | mahjongsoul | Four riichi emits `reach_accepted` for 4th stick and aborts | `engine.md §4.1 rows 3/5, §4.2`, `rules.md §4.24` | verified |
| `abort_suufon_renda` | mahjongsoul | Four identical winds on 1st unbroken go-around abort the round | `engine.md §4.1 row 2, §4.2`, `rules.md §1` | verified |
| `abort_suufon_renda_riichi_stick` | mahjongsoul | Four winds on a riichi discard aborts before `reach_accepted` (no stick) | `engine.md §4.1 row 2, §4.2`, `rules.md §5.9` | **unverified** (`rules.md §5.9`) |
| `abort_suukaikan_second_seat_pon` | mahjongsoul | Fourth kan by 2nd seat aborts ahead of a `pon` on its discard | `engine.md §4.1 row 4, §4.2`, `rules.md §4.22` | verified |
| `added_kan_rinshan_no_kan_dora` | both | Immediate rinshan tsumo after an added kan does not reveal or count the owed kan dora | `engine.md §4.2, rules.md §4.17` | verified |
| `added_kan_robbed_ippatsu_alive` | mahjongsoul | Robbing an added kan preserves ippatsu and flips no kan dora | `engine.md §4.2`, `rules.md §4.15, §4.26, §5.5` | **unverified** (`rules.md §5.5`) |
| `ambiguous_wait_max_payment` | mahjongsoul | Ambiguous decompositions choose the highest-paying reading in both sequence and triplet directions | `rules.md §4.6` | verified |
| `ambiguous_wait_yakuman_beats_higher_han` | both | Double natural yakuman beats a 28-han counted reading on Mahjong Soul and ties it on Tenhou | `rules.md §3, §4.3, §4.6, §4.33` | verified |
| `call_priority_daiminkan_over_chi` | mahjongsoul | Daiminkan beats Chi in the same discard window | `engine.md §4.1 rows 6/7, rules.md §4.37` | verified |
| `call_priority_pon_over_chi` | mahjongsoul | Pon beats Chi in same window; red-five pon variants are distinct | `engine.md §4, §4.1 rows 6/7`, `rules.md §4.37` | verified |
| `call_priority_ron_over_daiminkan` | mahjongsoul | Ron beats Daiminkan in the same discard window | `engine.md §4.1 rows 1/6, rules.md §4.37` | verified |
| `call_priority_ron_over_pon_chi` | mahjongsoul | Ron beats Pon and Chi in the same discard window | `engine.md §4.1 rows 1/6/7`, `rules.md §4.37` | verified |
| `chiitoitsu_25_fu_no_four_of_a_kind` | mahjongsoul | Chiitoitsu rejects four-of-a-kind as two pairs and scores fixed 25 fu on tsumo | `rules.md §1, §3.1, §4.10` | verified |
| `chuuren_invalidated_by_ankan` | mahjongsoul | Declaring ankan breaks Chuuren Poutou and scores ordinary Chinitsu instead | `rules.md §2.2, §4.36` | verified |
| `closed_kan_rinshan_tsumo` | mahjongsoul | Closed kan flips kan dora immediately for rinshan tsumo and cancels own ippatsu | `engine.md §4.2`, `rules.md §4.17, §4.26` | verified |
| `closed_kan_robbed_kokushi` | both | Robbing closed kan is Kokushi-only on Majsoul and forbidden on Tenhou | `engine.md §4.2`, `rules.md §1, §4.16` | verified |
| `dead_end_call` | mahjongsoul | Chi that would leave only kuikae-forbidden tiles is illegal | `engine.md §4.2`, `rules.md §4.13` | verified |
| `declined_tsumo_outside_riichi` | both | Declining tsumo by closing a wait-preserving kan gives temporary furiten only under the Tenhou default | `engine.md §4.2` | **unverified** (`engine.md §4.2`) |
| `double_ron_tenhou` | tenhou | Tenhou double ron gives sticks and honba only to closest CCW winner and repeats dealer | `engine.md §4.1 row 1, §4.2, rules.md §1, §4.21` | verified |
| `double_ron_with_sticks_and_honba` | mahjongsoul | Double ron gives sticks & honba only to closest CCW winner; dealer repeats | `engine.md §4.1 row 1, §4.2`, `rules.md §1, §4.21, §5.2` | **unverified** (`rules.md §5.2`) |
| `double_wind_pair_4_fu` | mahjongsoul | Double-wind pair awards 4 fu pushing closed ron from 40 fu to 50 fu | `rules.md §1, §3.1, §4.11` | verified |
| `double_yakuman_rulesets` | both | Suuankou Tanki ron pays 2x yakuman on Majsoul and 1x on Tenhou | `engine.md §3`, `rules.md §1, §2.2, §4.3` | verified |
| `endgame_all_last_abort_continues` | mahjongsoul | All Last abortive draw repeats dealer even in 1st with >= 30,000 | `engine.md §5 step 4`, `rules.md §1` | verified |
| `endgame_all_last_agari_yame` | mahjongsoul | All Last dealer win in strict 1st with >= 30,000 ends game (agari-yame) | `engine.md §5 step 4`, `rules.md §1` | verified |
| `endgame_all_last_dealer_first_below_30000` | mahjongsoul | All Last first-place repeating dealer below 30000 continues play | `engine.md §5 step 4, rules.md §1` | verified |
| `endgame_all_last_exact_30000` | mahjongsoul | All Last dealer tenpai reaching exactly 30000 in first ends the game | `engine.md §5 steps 4/5, rules.md §1` | verified |
| `endgame_all_last_extension_start` | mahjongsoul | All Last enters West extension when top score < 30,000 excluding sticks | `engine.md §5 step 4`, `rules.md §1, §5.8` | verified |
| `endgame_all_last_nondealer_win_ends` | mahjongsoul | Scheduled All Last ends on a non-dealer win when top score is at least 30000 | `engine.md §5 steps 4/5, rules.md §1` | verified |
| `endgame_all_last_tenpai_yame` | mahjongsoul | All Last dealer tenpai in strict 1st with >= 30,000 ends game + takes sticks | `engine.md §5 steps 4/5`, `rules.md §1` | verified |
| `endgame_all_last_tie_not_first` | mahjongsoul | All Last dealer tied for top score is not 1st by seat order -> repeats | `engine.md §5 step 4`, `rules.md §1` | verified |
| `endgame_east_e4_extension_start` | mahjongsoul | East-game E4 enters South 1 extension when all scores are below 30000 | `engine.md §5 step 4, rules.md §1` | verified |
| `endgame_east_s4_dealer_repeat` | both | East-game South 4 repeats when the tenpai dealer finishes below 30000 | `engine.md §5 step 4, rules.md §1 extension_max_round` | verified |
| `endgame_east_s4_max_round` | mahjongsoul | East-game South 4 ends unconditionally when dealer does not repeat even below 30000 | `engine.md §5 steps 4/5, rules.md §1` | verified |
| `endgame_extension_advance_below_30000` | mahjongsoul | West 1 advances to West 2 when dealer does not repeat and all scores stay below 30000 | `engine.md §5 step 4, rules.md §1` | verified |
| `endgame_extension_dealer_repeat_priority` | mahjongsoul | Dealer repeat takes priority over non-dealer passing 30,000 in extension | `engine.md §5 step 4`, `rules.md §5.8` | **unverified** (`rules.md §5.8`) |
| `endgame_extension_dealer_repeat_priority_tenhou` | tenhou | Tenhou dealer repeat takes priority over non-dealer passing 30000 in West extension | `engine.md §5 step 4, rules.md §5.8` | verified |
| `endgame_extension_max_round_w4` | mahjongsoul | West 4 ends unconditionally when dealer does not repeat even below 30,000 | `engine.md §5 step 4`, `rules.md §1` | verified |
| `endgame_extension_sudden_death` | mahjongsoul | Reaching >= 30,000 in West extension ends game on non-dealer win | `engine.md §5 step 4`, `rules.md §1` | verified |
| `endgame_extension_w4_dealer_repeat` | mahjongsoul | West 4 dealer repeat below 30000 continues West 4 rather than ending | `engine.md §5 step 4, rules.md §1 extension_max_round` | verified |
| `endgame_nagashi_pushes_dealer_out_of_first` | mahjongsoul | All Last Nagashi Mangan pushing tenpai dealer out of 1st prevents tenpai-yame | `engine.md §5`, `rules.md §5.6` | **unverified** (`rules.md §5.6`) |
| `endgame_oka_uma_tiebreak` | both | Game end awards sticks to 1st, breaks ties by seat, applies ruleset oka & uma | `engine.md §5 step 5`, `rules.md §1` | verified |
| `endgame_tobi_below_zero` | mahjongsoul | Dropping strictly below 0 ends game immediately with seat-order tie-break | `engine.md §5 steps 1/5`, `rules.md §1, §4.29` | verified |
| `endgame_tobi_draw_overrides_repeat` | mahjongsoul | Tobi caused by exhaustive draw payments ends the game ahead of dealer tenpai repeat | `engine.md §5 steps 1/3/5, rules.md §1, §4.29` | verified |
| `endgame_zero_continues` | mahjongsoul | Dropping to exactly 0 points does not trigger tobi | `engine.md §5 step 1`, `rules.md §1, §4.29` | verified |
| `exhaustive_draw_four_tenpai` | mahjongsoul | Exhaustive draw with all four seats tenpai transfers zero points and repeats dealer | `engine.md §4.2, rules.md §1` | verified |
| `exhaustive_draw_three_tenpai` | mahjongsoul | Exhaustive draw with three tenpai seats pays +1000 each from the sole noten seat | `engine.md §4.2, rules.md §1` | verified |
| `first_go_around_cancelled_by_ankan` | mahjongsoul | Dealer closed kan sets `anyCallMade`, cancelling Kyuushu and Chiihou | `engine.md §4.2`, `rules.md §4.25` | verified |
| `first_go_around_chiihou` | mahjongsoul | Non-dealer wins on first unbroken draw for Chiihou yakuman | `engine.md §4.2, rules.md §2.2` | verified |
| `first_go_around_double_riichi_cancelled` | mahjongsoul | An earlier call downgrades a first-draw riichi from double riichi to ordinary riichi | `engine.md §4.2, rules.md §4.25` | verified |
| `first_go_around_suufon_cancelled_by_call` | mahjongsoul | An earlier closed kan prevents four identical first-turn winds from aborting as suufon renda | `engine.md §4.1 row 2, §4.2, rules.md §4.25` | verified |
| `first_go_around_tenhou` | mahjongsoul | Dealer wins on initial 14-tile draw for Tenhou yakuman | `engine.md §4.2, rules.md §2.2` | verified |
| `formal_tenpai_fifth_copy` | both | Exhaustive draw 5th-copy wait: noten on Majsoul, tenpai on Tenhou unless all 4 concealed | `engine.md §4.2`, `rules.md §5.7` | **unverified** (`rules.md §5.7`) |
| `four_kans_one_seat_no_fifth` | mahjongsoul | Four kans by one seat continues play and forbids any 5th kan | `engine.md §4.2`, `rules.md §4.23` | verified |
| `four_kans_one_seat_no_fifth_kakan_daiminkan` | mahjongsoul | Four kans by one seat forbids a fifth kakan and fifth daiminkan even with matching tiles | `engine.md §4.2, rules.md §4.23` | verified |
| `furiten_no_yaku_wait_not_asked` | mahjongsoul | Passing a yaku-less wait sets temporary furiten even when seat is not asked | `engine.md §4.1`, `rules.md §4.28` | verified |
| `furiten_own_discard_cleared_by_wait_change` | mahjongsoul | Own-discard furiten becomes false after changing waits away from the discarded tile | `engine.md §4.1, rules.md §4.27` | verified |
| `furiten_own_discard_yaku_less_wait` | mahjongsoul | Own-discard furiten checks yaku-less waits and called-away discards | `engine.md §4.1`, `rules.md §4.9, §4.27` | verified |
| `furiten_riichi_passed_discard_permanent` | mahjongsoul | Passing an opponent's discard in riichi sets permanent furiten that persists after the next own draw | `engine.md §4.1, rules.md §4.28` | verified |
| `furiten_surviving_call` | both | Temporary furiten survives a pon and clears on the next own draw in both rulesets | `engine.md §4.1`, `rules.md §1, §4.28` | verified to spec |
| `ippatsu_cancelled_by_kakan` | mahjongsoul | A completed added kan cancels another seat's ippatsu | `engine.md §4.2, rules.md §4.26, §5.4` | unverified (Mahjong Soul post-kan ron timing) |
| `ippatsu_cancelled_by_opponent_ankan` | mahjongsoul | An opponent's closed kan cancels a riichi seat's ippatsu | `engine.md §4.2, rules.md §4.26` | verified |
| `ippatsu_expires_on_own_discard` | mahjongsoul | Ippatsu expires immediately after the riichi seat's next own discard | `engine.md §4.2, rules.md §2.1, §4.26` | verified |
| `kakan_robbing_pass_furiten` | mahjongsoul | Passing a legal kakan rob completes the kan and triggers temporary furiten until own draw | `engine.md §4.1, §4.2, rules.md §4.28` | verified |
| `kan_one_live_tile_discard_houtei` | mahjongsoul | Discard after kan with 1 live tile left can be ronned for Houtei | `engine.md §4.2`, `rules.md §4.18, §4.19` | verified |
| `kan_one_live_tile_rinshan_not_haitei` | mahjongsoul | Kan with 1 live tile left then replacement tsumo scores Rinshan, not Haitei | `engine.md §4.2`, `rules.md §4.18` | verified |
| `kazoe_yakuman_26_han_cap` | mahjongsoul | A 30-han non-yakuman hand is capped at a single 1x Kazoe Yakuman | `rules.md §1, §4.33` | verified |
| `kuikae_chi_and_pon` | mahjongsoul | Kuikae forbids suji swap after Chi, same kind after Pon, and tsumogiri after call | `engine.md §4, §4.2`, `rules.md §4.12, §4.13` | verified |
| `kuikae_red_five_and_kanchan` | mahjongsoul | Kuikae forbids matching red five after pon, suji after red-five chi, and only middle tile after kanchan chi | `engine.md §4.2, rules.md §4.12, §4.13` | verified |
| `kyuushu_illegal_eight_and_second_turn` | mahjongsoul | Kyuushu kyuuhai is illegal with 8 distinct kinds and illegal after the seat's first discard | `engine.md §4.2, rules.md §1` | verified |
| `kyuushu_opt_out` | mahjongsoul | Opting out of legal kyuushu kyuuhai continues the round normally | `engine.md §4.2, rules.md §1` | verified |
| `last_tile_haitei_tsumo` | mahjongsoul | Haitei Raoyue tsumo on the 70th live draw (0 live tiles left) | `engine.md §4.2`, `rules.md §4.18, §4.7` | verified |
| `last_tile_houtei_no_calls` | mahjongsoul | Last-tile discard forbids kan and calls, allows Houtei ron | `engine.md §4.1 row 8, §4.2`, `rules.md §4.18, §4.19` | verified |
| `last_tile_houtei_pass_exhaustive` | mahjongsoul | Passing a legal Houtei ron on the last discard leads directly to exhaustive draw | `engine.md §4.1 row 8, §4.2, rules.md §4.19` | verified |
| `last_tile_no_kakan_or_daiminkan` | mahjongsoul | Zero live tiles remaining forbids kakan on the last draw and daiminkan on the last discard | `engine.md §4.2, rules.md §1, §4.18, §4.19` | verified |
| `nagashi_mangan_dealer` | mahjongsoul | Dealer Nagashi Mangan pays 4000 all and still rotates dealer when dealer is noten | `engine.md §4.2, rules.md §1, §4.30` | verified |
| `nagashi_mangan_lost_when_called` | mahjongsoul | Having a terminal/honor discard called away disqualifies Nagashi Mangan | `engine.md §4.2, rules.md §1, §4.30` | verified |
| `nagashi_mangan_multiple_winners` | mahjongsoul | Multiple qualifying Nagashi Mangan seats are all paid at exhaustive draw | `engine.md §4.2, rules.md §1, §4.30` | verified |
| `nagashi_mangan_tenpai_dealer` | mahjongsoul | Nagashi Mangan replaces tenpai payments without breaking dealer tenpai renchan | `engine.md §4.2`, `rules.md §1, §4.30` | verified |
| `natural_yakuman_ignores_dora` | mahjongsoul | Natural Yakuman scores 1x Yakuman and ignores all regular yaku and dora | `rules.md §4.34` | verified |
| `no_kiriage_3han60fu_and_4han30fu_ron` | both | No kiriage mangan for dealer 3 han 60 fu (11600) and non-dealer 4 han 30 fu (7700) ron | `rules.md §1, §3.2, §4.20` | verified |
| `no_kiriage_3han60fu_dealer_tsumo` | both | Dealer 3 han 60 fu tsumo pays 3900 all | `rules.md §1, §3.2, §4.20` | verified |
| `no_kiriage_3han60fu_nondealer_tsumo` | both | Nondealer 3 han 60 fu tsumo pays 2000 / 3900 | `rules.md §1, §3.2, §4.20` | verified |
| `no_kiriage_dealer_tsumo` | both | No kiriage mangan for dealer 4 han 30 fu tsumo (3900 all) | `rules.md §1, §3.2, §4.20` | verified |
| `no_kiriage_tsumo_boundaries` | both | No kiriage mangan for non-dealer 4 han 30 fu tsumo (2000 / 3900) | `rules.md §1, §3.2, §4.20` | verified |
| `no_pao_suukantsu` | mahjongsoul | Feeding the 4th kan for Suukantsu does not trigger Pao | `engine.md §4.2`, `rules.md §1, §4.32` | verified |
| `no_pao_suukantsu_tenhou` | tenhou | Tenhou Suukantsu fed by daiminkan has no pao and splits tsumo payment normally | `engine.md §4.2, rules.md §1, §4.32` | verified |
| `open_kan_chained_kan_discard_ron` | both | Open kan -> rinshan -> added kan -> discard -> ron (owed kan dora ordering) | `engine.md §4.2`, `rules.md §4.17, §5.4, §5.10` | **unverified** (`rules.md §5.4, §5.10`) |
| `open_kan_discard_all_pass_dora` | both | Post-open-kan discard with all-pass reveals owed kan dora before the next draw | `engine.md §4.2, rules.md §4.17` | verified |
| `open_kan_discard_called_dora` | both | Post-open-kan discard called by pon reveals the owed kan dora | `engine.md §4.2, rules.md §4.17, §5.4` | **unverified** (`rules.md §5 item 4`) |
| `open_kan_discard_riichi_ron_ura` | both | Post-open-kan riichi ron counts the second ura indicator on Tenhou but not Mahjong Soul default | `engine.md §4.2, rules.md §1, §4.17, §5.4` | **unverified** (`rules.md §5 item 4`) |
| `open_kan_discard_ron_dora` | both | Post-open-kan discard ron: Tenhou counts kan dora, Majsoul default does not | `engine.md §4.2`, `rules.md §1, §4.17, §5.4` | **unverified** (`rules.md §5.4`) |
| `open_kan_rinshan_no_kan_dora` | mahjongsoul | Immediate rinshan tsumo after open kan does not see owed kan dora | `engine.md §4.2`, `rules.md §4.17` | verified |
| `open_kan_to_closed_kan_chain` | both | Open kan -> replacement draw -> closed kan reveals owed dora then ankan then new dora | `engine.md §4.2, rules.md §4.17, §5.10` | **unverified** (`rules.md §5 item 10`) |
| `open_kan_to_robbed_closed_kan` | mahjongsoul | Owed dora precedes a chained closed kan robbed by Kokushi | `engine.md §4.2, rules.md §4.16, §4.17` | **unverified** (`rules.md §5 item 10`) |
| `open_pinfu_ron_30_fu` | mahjongsoul | Open all-sequence ryanmen ron with zero extra fu scores 30 fu minimum | `rules.md §1, §3.1, §4.8` | verified |
| `pao_composite_yakuman` | both | Composite yakuman pao splits non-liable yakuman on Majsoul, charges whole hand on Tenhou | `engine.md §4.2`, `rules.md §1, §4.31` | verified |
| `pao_composite_yakuman_ron` | both | Composite yakuman third-party ron splits only liable yakuman on Mahjong Soul and whole hand on Tenhou | `engine.md §4.2, rules.md §1, §4.31` | verified |
| `pao_daisuushii` | both | Daisuushii pao charges the liable seat 2x yakuman on Mahjong Soul and 1x on Tenhou | `engine.md §4.2, rules.md §1, §4.31` | verified |
| `pao_double_ron` | mahjongsoul | Pao inside double ron splits only the pao winner's yakuman with liable seat | `engine.md §4.2`, `rules.md §4.21, §4.31` | **unverified** (`rules.md §5.2`) |
| `pao_double_ron_tenhou` | tenhou | Tenhou pao inside a double ron splits the pao yakuman while closest winner takes stick and honba | `engine.md §4.2, rules.md §1, §4.21, §4.31` | verified |
| `pao_ron_from_liable_seat` | mahjongsoul | Pao ron from liable seat itself pays 100% + honba | `engine.md §4.2`, `rules.md §1, §4.31` | verified |
| `pao_ron_liable_seat_tenhou` | tenhou | Tenhou pao ron dealt by the liable seat itself pays 100% plus honba | `engine.md §4.2, rules.md §1, §4.31` | verified |
| `pao_ron_third_party` | mahjongsoul | Pao ron from 3rd party splits 50/50 with liable seat paying honba | `engine.md §4.2`, `rules.md §1, §4.31` | verified |
| `pao_ron_third_party_tenhou` | tenhou | Third-party Daisangen ron splits liability and charges honba to the liable seat | `engine.md §4.2, rules.md §1, §4.31` | verified |
| `pao_set_by_daiminkan` | both | Daiminkan completing the third dragon sets Daisangen pao on the discarder | `engine.md §4.2, rules.md §1, §4.31` | verified |
| `pao_tsumo_daisangen` | mahjongsoul | Pao tsumo on Daisangen makes liable seat pay 100% + honba | `engine.md §4.2`, `rules.md §1, §4.31` | verified |
| `pao_tsumo_daisangen_tenhou` | tenhou | Pon-established Daisangen tsumo charges the liable seat the entire hand and honba | `engine.md §4.2, rules.md §1, §4.31` | verified |
| `pinfu_exclusions` | mahjongsoul | Pinfu is excluded by a value pair and by a nobetan tanki wait | `rules.md §4.5` | verified |
| `riichi_ankan_okurikan_illegal` | mahjongsoul | Okurikan (closed kan not using the just-drawn tile) is illegal after riichi | `rules.md §1, §4.14` | verified |
| `riichi_ankan_waits` | mahjongsoul | Riichi ankan compares only wait kinds and forbids wait-changing kan | `engine.md §4.2`, `rules.md §4.14, §5.3` | **unverified** (`rules.md §5.3`) |
| `riichi_discard_called` | mahjongsoul | Calling a riichi discard emits `reach_accepted` first and cancels ippatsu | `engine.md §4.1 rows 3/6, §4.2, §6`, `rules.md §4.26` | verified |
| `riichi_discard_chi_cancels_ippatsu` | mahjongsoul | Chi on a riichi discard emits reach_accepted before chi and cancels ippatsu | `engine.md §4.1 rows 3/7, §4.2, §6, rules.md §4.26` | verified |
| `riichi_discard_daiminkan_cancels_ippatsu` | mahjongsoul | Daiminkan on a riichi discard emits reach_accepted before daiminkan and cancels ippatsu | `engine.md §4.1 rows 3/6, §4.2, §6, rules.md §4.26, §5.4` | unverified (Mahjong Soul post-kan ron timing) |
| `riichi_discard_ronned` | mahjongsoul | Ron on a riichi discard cancels `reach_accepted` and pays no stick | `engine.md §4.1 row 1, §4.2, §6` | verified |
| `riichi_discard_tenpai_only` | mahjongsoul | After declaring riichi, only tenpai-preserving discards are legal | `engine.md §4, §4.2, rules.md §1` | verified |
| `riichi_furiten_and_karaten` | mahjongsoul | Declaring riichi is legal while furiten and while karaten (0 live copies elsewhere) | `engine.md §4.2, rules.md §1` | verified |
| `riichi_furiten_skipped_tsumo_ankan` | mahjongsoul | Skipping self-drawn winning tile via closed kan in riichi sets permanent furiten | `engine.md §4.1`, `rules.md §4.14, §4.28` | verified |
| `riichi_illegal_open_and_noten` | mahjongsoul | Riichi is illegal on a closed noten hand and on an open tenpai hand | `engine.md §4.2, rules.md §1` | verified |
| `riichi_min_live_tiles` | mahjongsoul | Riichi legal with 4 live tiles left, illegal with 3 live tiles left | `engine.md §4.2`, `rules.md §1` | verified |
| `riichi_requirements` | mahjongsoul | Riichi requires >= 1,000 points (900 illegal, 1,000 legal) and grants double riichi | `engine.md §4.2`, `rules.md §1, §4.29` | verified |
| `ryanpeikou_not_chiitoitsu` | mahjongsoul | Ryanpeikou scores 4 sequences plus pair (3 han, 30 fu) rather than Chiitoitsu or Iipeikou | `rules.md §4.4` | verified |
| `ryuuiisou_without_hatsu` | mahjongsoul | Ryuuiisou made purely of green souzu without Hatsu scores 1x Yakuman | `rules.md §2.2, §4.35` | verified |
| `sanankou_shanpon_ron` | mahjongsoul | Ron on a shanpon third triplet makes it open (2 fu) and does not score Sanankou | `rules.md §4.1` | verified |
| `sanankou_shanpon_tsumo` | mahjongsoul | Tsumo on a shanpon third triplet keeps it concealed and scores Sanankou | `rules.md §4.1` | verified |
| `suuankou_shanpon_ron` | mahjongsoul | Shanpon ron on four triplets scores Sanankou + Toitoi instead of Suuankou | `rules.md §4.2` | verified |
| `suuankou_shanpon_tsumo` | mahjongsoul | Shanpon tsumo on four concealed triplets scores 1x Suuankou | `rules.md §4.2` | verified |
| `suucha_riichi_discard_ron` | mahjongsoul | Ron on the fourth riichi discard wins without accepting the fourth stick or aborting | `engine.md §4.1 rows 1/3/5, §4.2, rules.md §4.24` | verified |
| `suukaikan_discard_ron` | mahjongsoul | Ron on the fourth multi-seat kan discard wins instead of aborting as suukaikan | `engine.md §4.1 rows 1/4, §4.2, rules.md §4.22` | verified |
| `suukaikan_open_kan_owed_dora` | both | Fourth open kan reveals owed dora at its discard before the four-kan abort | `engine.md §4.2, rules.md §1, §4.22` | **unverified** on Mahjong Soul (`rules.md §5 item 4`) |
| `suukaikan_rinshan_win` | mahjongsoul | Fourth kan by 2nd seat allows Rinshan Kaihou win instead of aborting | `engine.md §4.2`, `rules.md §4.22` | verified |
| `triple_ron_rulesets` | both | Triple ron pays all three on Majsoul and aborts (`sanchahou`) on Tenhou | `engine.md §4.1 row 1, §4.2`, `rules.md §1, §4.21` | **unverified** (`rules.md §5.2`) |
