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
- `rules.md` §5 item 4: `open_kan_discard_ron_dora.scn`, `open_kan_discard_called_dora.scn`, `open_kan_discard_riichi_ron_ura.scn`, `ippatsu_cancelled_by_kakan.scn`, and `riichi_discard_daiminkan_cancels_ippatsu.scn`
- `rules.md` §5 items 4 & 10: `open_kan_chained_kan_discard_ron.scn`
- `rules.md` §5 item 10: `open_kan_to_closed_kan_chain.scn`
- `rules.md` §5 item 5: `added_kan_robbed_ippatsu_alive.scn`
- `rules.md` §5 item 6: `endgame_nagashi_pushes_dealer_out_of_first.scn`
- `rules.md` §5 item 7: `formal_tenpai_fifth_copy.scn`
- `rules.md` §5 item 8: `endgame_extension_dealer_repeat_priority.scn`
- `rules.md` §5 item 9: `abort_suufon_renda_riichi_stick.scn`

## 6. Physically impossible coverage gaps from `docs/reviews/p3/F-codex.md`

Two items listed in the Package F review coverage table cannot arise in legal 4-player Riichi Mahjong and therefore have no scenario file:

- **Dead-end Pon (`rules.md` §4 item 13):** A seat with $k \in \{0,1,2,3\}$ melds holds $13 - 3k \ge 4$ concealed tiles. Calling Pon on tile kind $X$ uses 2 copies of $X$ from hand plus 1 discarded, leaving $11 - 3k \ge 2$ concealed tiles and at most 1 remaining copy of $X$ in the 4-copy deck. Because Pon kuikae forbids only kind $X$, at least one tile of a different kind always remains to discard.
- **Submitted call losing to Four Riichi (`engine.md` §4.1 row 5):** When the 4th seat declares riichi, all three other seats are already in riichi and cannot legally submit `pon`, `chi`, or `daiminkan`. Only `ron` (covered by `suucha_riichi_discard_ron.scn`) can legally be submitted on the 4th riichi discard.

## 7. Format limitation: post-robbed-kakan meld and kan-count state

- **`docs/reviews/p3/F-codex.md` (§4.2 Kan transactions):** Notes that after a robbed added kan (`added_kan_robbed_ippatsu_alive.scn`), the surviving pon and unchanged kan count are not directly observable from `scenarios/FORMAT.md` assertions. Because a robbed `kakan` ends the round immediately on `ron`, no subsequent turn exists to probe legality, and `FORMAT.md` has no `assert_melds` or `assert_kan_count` directive. Exact `events:` already verifies that no `dora` or replacement `tsumo` event is emitted.

## 8. West 4 dealer repeat below 30,000 (resolved)

`spec/rules.md` §1 `extension_max_round` now states that the limit applies
when play would advance past the last hand of the extension. A below-target
dealer repeat in that hand continues play, as required by `engine.md` §5
step 4 and tested in `endgame_extension_w4_dealer_repeat.scn`.
