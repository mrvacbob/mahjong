# Scenario Index

54 hand-worked scenario tests (`scenarios/*.scn`), validated and expanded to JSON by `tools/scenario.py`.

| Scenario | Rules | What it pins down | Source rule | Status |
| :--- | :---: | :--- | :--- | :---: |
| `abort_kyuushu_kyuuhai` | mahjongsoul | Nine distinct terminals/honors on 1st unbroken draw aborts immediately | `engine.md §4.2`, `rules.md §1, §4.25` | verified |
| `abort_suucha_riichi` | mahjongsoul | Four riichi emits `reach_accepted` for 4th stick and aborts | `engine.md §4.1 rows 3/5, §4.2`, `rules.md §4.24` | verified |
| `abort_suufon_renda` | mahjongsoul | Four identical winds on 1st unbroken go-around abort the round | `engine.md §4.1 row 2, §4.2`, `rules.md §1` | verified |
| `abort_suufon_renda_riichi_stick` | mahjongsoul | Four winds on a riichi discard aborts before `reach_accepted` (no stick) | `engine.md §4.1 row 2, §4.2`, `rules.md §5.9` | **unverified** (`rules.md §5.9`) |
| `abort_suukaikan_second_seat_pon` | mahjongsoul | Fourth kan by 2nd seat aborts ahead of a `pon` on its discard | `engine.md §4.1 row 4, §4.2`, `rules.md §4.22` | verified |
| `added_kan_robbed_ippatsu_alive` | mahjongsoul | Robbing an added kan preserves ippatsu and flips no kan dora | `engine.md §4.2`, `rules.md §4.15, §4.26, §5.5` | **unverified** (`rules.md §5.5`) |
| `call_priority_pon_over_chi` | mahjongsoul | Pon beats Chi in same window; red-five pon variants are distinct | `engine.md §4, §4.1 rows 6/7`, `rules.md §4.37` | verified |
| `call_priority_ron_over_pon_chi` | mahjongsoul | Ron beats Pon and Chi in the same discard window | `engine.md §4.1 rows 1/6/7`, `rules.md §4.37` | verified |
| `closed_kan_rinshan_tsumo` | mahjongsoul | Closed kan flips kan dora immediately for rinshan tsumo and cancels own ippatsu | `engine.md §4.2`, `rules.md §4.17, §4.26` | verified |
| `closed_kan_robbed_kokushi` | both | Robbing closed kan is Kokushi-only on Majsoul and forbidden on Tenhou | `engine.md §4.2`, `rules.md §1, §4.16` | verified |
| `dead_end_call` | mahjongsoul | Chi that would leave only kuikae-forbidden tiles is illegal | `engine.md §4.2`, `rules.md §4.13` | verified |
| `double_ron_with_sticks_and_honba` | mahjongsoul | Double ron gives sticks & honba only to closest CCW winner; dealer repeats | `engine.md §4.1 row 1, §4.2`, `rules.md §1, §4.21, §5.2` | **unverified** (`rules.md §5.2`) |
| `double_yakuman_rulesets` | both | Suuankou Tanki ron pays 2x yakuman on Majsoul and 1x on Tenhou | `engine.md §3`, `rules.md §1, §2.2, §4.3` | verified |
| `endgame_all_last_abort_continues` | mahjongsoul | All Last abortive draw repeats dealer even in 1st with >= 30,000 | `engine.md §5 step 4`, `rules.md §1` | verified |
| `endgame_all_last_agari_yame` | mahjongsoul | All Last dealer win in strict 1st with >= 30,000 ends game (agari-yame) | `engine.md §5 step 4`, `rules.md §1` | verified |
| `endgame_all_last_extension_start` | mahjongsoul | All Last enters West extension when top score < 30,000 excluding sticks | `engine.md §5 step 4`, `rules.md §1, §5.8` | verified |
| `endgame_all_last_tenpai_yame` | mahjongsoul | All Last dealer tenpai in strict 1st with >= 30,000 ends game + takes sticks | `engine.md §5 steps 4/5`, `rules.md §1` | verified |
| `endgame_all_last_tie_not_first` | mahjongsoul | All Last dealer tied for top score is not 1st by seat order -> repeats | `engine.md §5 step 4`, `rules.md §1` | verified |
| `endgame_extension_dealer_repeat_priority` | mahjongsoul | Dealer repeat takes priority over non-dealer passing 30,000 in extension | `engine.md §5 step 4`, `rules.md §5.8` | **unverified** (`rules.md §5.8`) |
| `endgame_extension_max_round_w4` | mahjongsoul | West 4 ends unconditionally when dealer does not repeat even below 30,000 | `engine.md §5 step 4`, `rules.md §1` | verified |
| `endgame_extension_sudden_death` | mahjongsoul | Reaching >= 30,000 in West extension ends game on non-dealer win | `engine.md §5 step 4`, `rules.md §1` | verified |
| `endgame_nagashi_pushes_dealer_out_of_first` | mahjongsoul | All Last Nagashi Mangan pushing tenpai dealer out of 1st prevents tenpai-yame | `engine.md §5`, `rules.md §5.6` | **unverified** (`rules.md §5.6`) |
| `endgame_oka_uma_tiebreak` | both | Game end awards sticks to 1st, breaks ties by seat, applies ruleset oka & uma | `engine.md §5 step 5`, `rules.md §1` | verified |
| `endgame_tobi_below_zero` | mahjongsoul | Dropping strictly below 0 ends game immediately with seat-order tie-break | `engine.md §5 steps 1/5`, `rules.md §1, §4.29` | verified |
| `endgame_zero_continues` | mahjongsoul | Dropping to exactly 0 points does not trigger tobi | `engine.md §5 step 1`, `rules.md §1, §4.29` | verified |
| `first_go_around_cancelled_by_ankan` | mahjongsoul | Dealer closed kan sets `anyCallMade`, cancelling Kyuushu and Chiihou | `engine.md §4.2`, `rules.md §4.25` | verified |
| `formal_tenpai_fifth_copy` | both | Exhaustive draw 5th-copy wait: noten on Majsoul, tenpai on Tenhou unless all 4 concealed | `engine.md §4.2`, `rules.md §5.7` | **unverified** (`rules.md §5.7`) |
| `four_kans_one_seat_no_fifth` | mahjongsoul | Four kans by one seat continues play and forbids any 5th kan | `engine.md §4.2`, `rules.md §4.23` | verified |
| `furiten_no_yaku_wait_not_asked` | mahjongsoul | Passing a yaku-less wait sets temporary furiten even when seat is not asked | `engine.md §4.1`, `rules.md §4.28` | verified |
| `furiten_own_discard_yaku_less_wait` | mahjongsoul | Own-discard furiten checks yaku-less waits and called-away discards | `engine.md §4.1`, `rules.md §4.9, §4.27` | verified |
| `furiten_surviving_call` | both | Temporary furiten across a call (Tenhou survives; Majsoul per `rules.md` vs `engine.md`) | `engine.md §4.1`, `rules.md §1, §4.28` | **unverified** (`QUESTIONS.md #1`) |
| `kan_one_live_tile_discard_houtei` | mahjongsoul | Discard after kan with 1 live tile left can be ronned for Houtei | `engine.md §4.2`, `rules.md §4.18, §4.19` | verified |
| `kan_one_live_tile_rinshan_not_haitei` | mahjongsoul | Kan with 1 live tile left then replacement tsumo scores Rinshan, not Haitei | `engine.md §4.2`, `rules.md §4.18` | verified |
| `kuikae_chi_and_pon` | mahjongsoul | Kuikae forbids suji swap after Chi, same kind after Pon, and tsumogiri after call | `engine.md §4, §4.2`, `rules.md §4.12, §4.13` | verified |
| `last_tile_haitei_tsumo` | mahjongsoul | Haitei Raoyue tsumo on the 70th live draw (0 live tiles left) | `engine.md §4.2`, `rules.md §4.18, §4.7` | verified |
| `last_tile_houtei_no_calls` | mahjongsoul | Last-tile discard forbids kan and calls, allows Houtei ron | `engine.md §4.1 row 8, §4.2`, `rules.md §4.18, §4.19` | verified |
| `nagashi_mangan_tenpai_dealer` | mahjongsoul | Nagashi Mangan replaces tenpai payments without breaking dealer tenpai renchan | `engine.md §4.2`, `rules.md §1, §4.30` | verified |
| `no_pao_suukantsu` | mahjongsoul | Feeding the 4th kan for Suukantsu does not trigger Pao | `engine.md §4.2`, `rules.md §1, §4.32` | verified |
| `open_kan_chained_kan_discard_ron` | both | Open kan -> rinshan -> added kan -> discard -> ron (owed kan dora ordering) | `engine.md §4.2`, `rules.md §4.17, §5.4, §5.10` | **unverified** (`rules.md §5.4, §5.10`) |
| `open_kan_discard_ron_dora` | both | Post-open-kan discard ron: Tenhou counts kan dora, Majsoul default does not | `engine.md §4.2`, `rules.md §1, §4.17, §5.4` | **unverified** (`rules.md §5.4`) |
| `open_kan_rinshan_no_kan_dora` | mahjongsoul | Immediate rinshan tsumo after open kan does not see owed kan dora | `engine.md §4.2`, `rules.md §4.17` | verified |
| `pao_composite_yakuman` | both | Composite yakuman pao splits non-liable yakuman on Majsoul, charges whole hand on Tenhou | `engine.md §4.2`, `rules.md §1, §4.31` | verified |
| `pao_double_ron` | mahjongsoul | Pao inside double ron splits only the pao winner's yakuman with liable seat | `engine.md §4.2`, `rules.md §4.21, §4.31` | verified |
| `pao_ron_from_liable_seat` | mahjongsoul | Pao ron from liable seat itself pays 100% + honba | `engine.md §4.2`, `rules.md §1, §4.31` | verified |
| `pao_ron_third_party` | mahjongsoul | Pao ron from 3rd party splits 50/50 with liable seat paying honba | `engine.md §4.2`, `rules.md §1, §4.31` | verified |
| `pao_tsumo_daisangen` | mahjongsoul | Pao tsumo on Daisangen makes liable seat pay 100% + honba | `engine.md §4.2`, `rules.md §1, §4.31` | verified |
| `riichi_ankan_waits` | mahjongsoul | Riichi ankan compares only wait kinds and forbids wait-changing kan | `engine.md §4.2`, `rules.md §4.14, §5.3` | **unverified** (`rules.md §5.3`) |
| `riichi_discard_called` | mahjongsoul | Calling a riichi discard emits `reach_accepted` first and cancels ippatsu | `engine.md §4.1 rows 3/6, §4.2, §6`, `rules.md §4.26` | verified |
| `riichi_discard_ronned` | mahjongsoul | Ron on a riichi discard cancels `reach_accepted` and pays no stick | `engine.md §4.1 row 1, §4.2, §6` | verified |
| `riichi_furiten_skipped_tsumo_ankan` | mahjongsoul | Skipping self-drawn winning tile via closed kan in riichi sets permanent furiten | `engine.md §4.1`, `rules.md §4.14, §4.28` | verified |
| `riichi_min_live_tiles` | mahjongsoul | Riichi legal with 4 live tiles left, illegal with 3 live tiles left | `engine.md §4.2`, `rules.md §1` | verified |
| `riichi_requirements` | mahjongsoul | Riichi requires >= 1,000 points (900 illegal, 1,000 legal) and grants double riichi | `engine.md §4.2`, `rules.md §1, §4.29` | verified |
| `suukaikan_rinshan_win` | mahjongsoul | Fourth kan by 2nd seat allows Rinshan Kaihou win instead of aborting | `engine.md §4.2`, `rules.md §4.22` | verified |
| `triple_ron_rulesets` | both | Triple ron pays all three on Majsoul and aborts (`sanchahou`) on Tenhou | `engine.md §4.1 row 1, §4.2`, `rules.md §1, §4.21` | verified |
