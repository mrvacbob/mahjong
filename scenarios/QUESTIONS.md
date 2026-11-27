# Open Questions & Spec Discrepancies

Disagreements between `docs/design/engine.md` (draft 2) and `spec/rules.md`, or
places where either document looks incomplete or ambiguous. Per the brief,
scenarios follow `spec/rules.md` where the two disagree and list the item here.

## 1. Temporary furiten clearing on a call (resolved for scenarios)

The Phase 3 ruling keeps temporary furiten until the next own draw for both
rulesets. A call leaves it in place. `furiten_surviving_call.scn` uses one
play sequence and the same outcome for both rulesets. The Mahjong Soul
client behavior of an intervening call remains untested in a replay.

## 2. Pao on Ron honba in Mahjong Soul vs `engine.md` §4.2

- **`spec/rules.md` (§1 `pao_ron_split`, §4 item 31):** Explicitly states for
  Mahjong Soul that on a 3rd-party ron with pao, the liable player and discarder
  split the yakuman 50/50 and **the liable player pays the honba** (citing
  `mahjongsoul.com/news/46/`), matching Tenhou.
- **`docs/design/engine.md` (§4.2):** Mentions *"and the liable seat pays the
  honba"* only in the Tenhou clause, leaving Mahjong Soul honba payment implicit.
- **Action taken:** `scenarios/pao_ron_third_party.scn` follows `spec/rules.md`
  (liable seat pays the honba in Mahjong Soul as well).

## 3. Open kan → closed kan owed-indicator order if robbed by Kokushi (Mahjong Soul)

- **`docs/design/engine.md` (§4.2):** For open kan → closed kan, states the
  event order is `dora` (owed), `ankan`, `dora` (new), `tsumo`.
- **Question:** Under Mahjong Soul, a closed kan (`ankan`) can be robbed by
  Kokushi Musou (`rules.md` §4 item 16). If `dora` (owed) is emitted *before*
  `ankan`, it flips even if the `ankan` is robbed (which does not affect a
  Kokushi yakuman's score, only the mjai event log). `rules.md` §5 item 10
  already marks Mahjong Soul chained-kan dora order as unverified.

## 4. Adjusted score units for `GameResult` (resolved)

- **`docs/design/engine.md` (§2, §5 step 5):** States `Riichi` uses no floating
  point (*"uma and oka stay in integer points"*), and `spec/rules.md` §1 gives
  Mahjong Soul `25,000` return, `0` oka, `[+15, +5, -5, -15]` uma, and Tenhou
  `30,000` return, `+20` oka (`+20,000` to 1st), `[+20, +10, -10, -20]` base uma.
- **Action taken:** `scenarios/endgame_oka_uma_tiebreak.scn` expresses
  `adjusted_scores` in raw integer points (`final_score - return + oka*1000 +
  uma*1000`, e.g., `+27000` for `+27.0`). The Phase 3 ruling confirms those integer point units.

## 5. Unverified Mahjong Soul client behaviours (tracked in `spec/rules.md` §5)

All items marked unverified in `spec/rules.md` §5 are written to the design's
stated defaults and tagged `unverified` in their scenario `[meta]` headers:
- `rules.md` §5 item 2: `double_ron_with_sticks_and_honba.scn`, `triple_ron_rulesets.scn`, and `pao_double_ron.scn`
- `rules.md` §5 item 3: `riichi_ankan_waits.scn`
- `rules.md` §5 item 4: `open_kan_discard_ron_dora.scn`
- `rules.md` §5 items 4 & 10: `open_kan_chained_kan_discard_ron.scn`
- `rules.md` §5 item 5: `added_kan_robbed_ippatsu_alive.scn`
- `rules.md` §5 item 6: `endgame_nagashi_pushes_dealer_out_of_first.scn`
- `rules.md` §5 item 7: `formal_tenpai_fifth_copy.scn`
- `rules.md` §5 item 8: `endgame_extension_dealer_repeat_priority.scn`
- `rules.md` §5 item 9: `abort_suufon_renda_riichi_stick.scn`
