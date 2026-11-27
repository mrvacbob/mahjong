# Open Questions & Spec Discrepancies

Disagreements between `docs/design/engine.md` (draft 2) and `spec/rules.md`, or
places where either document looks incomplete or ambiguous. Per the brief,
scenarios follow `spec/rules.md` where the two disagree and list the item here.

## 1. Temporary furiten clearing on a call (resolved)

In both clients, the seat’s own chi, pon, or open kan clears temporary furiten.
`furiten_cleared_by_own_call.scn` checks the flag immediately before and after
the pon and takes a legal ron before the seat draws again. Source is the
real-log campaign, `docs/notes/p3-reallogs.md`.

## 2. Pao on Ron honba in Mahjong Soul vs `engine.md` §4.2 (resolved)

- **`spec/rules.md` (§1 `pao_ron_split`, §4 item 31):** Explicitly states for
  Mahjong Soul that on a 3rd-party ron with pao, the liable player and discarder
  split the yakuman 50/50 and **the liable player pays the honba** (citing
  `mahjongsoul.com/news/46/`), matching Tenhou.
- **`docs/design/engine.md` (§4.2):** Mentions *"and the liable seat pays the
  honba"* only in the Tenhou clause, leaving Mahjong Soul honba payment implicit.
- **Action taken:** `scenarios/pao_ron_third_party.scn` follows `spec/rules.md`
  (liable seat pays the honba in Mahjong Soul as well). The real-log campaign,
  `docs/notes/p3-reallogs.md`, found results consistent with this settlement.

## 3. Open kan → closed kan owed-indicator order if robbed by Kokushi (Mahjong Soul)

- **`docs/design/engine.md` (§4.2):** For open kan → closed kan, states the
  event order is `dora` (owed), `ankan`, `dora` (new), `tsumo`.
- **Question:** Under Mahjong Soul, a closed kan (`ankan`) can be robbed by
  Kokushi Musou (`rules.md` §4 item 16). If `dora` (owed) is emitted *before*
  `ankan`, it flips even if the `ankan` is robbed (which does not affect a
  Kokushi yakuman's score, only the mjai event log). `rules.md` §5 item 10
  settles the chained added-kan order. The evidence does not answer this
  chained closed-kan question, so both closed-kan order scenarios retain their tags.

## 4. Adjusted score units for `GameResult` (resolved)

- **`docs/design/engine.md` (§2, §5 step 5):** States `Riichi` uses no floating
  point (*"uma and oka stay in integer points"*), and `spec/rules.md` §1 gives
  Mahjong Soul `25,000` return, `0` oka, `[+15, +5, -5, -15]` uma, and Tenhou
  `30,000` return, `+20` oka (`+20,000` to 1st), `[+20, +10, -10, -20]` base uma.
- **Action taken:** `scenarios/endgame_oka_uma_tiebreak.scn` expresses
  `adjusted_scores` in raw integer points (`final_score - return + oka*1000 +
  uma*1000`, e.g., `+27000` for `+27.0`). The Phase 3 ruling confirms those integer point units.

## 5. Client behavior checked in the real-log campaign

The real-log campaign, `docs/notes/p3-reallogs.md`, closes these questions:

- Both clients reveal the owed indicator just before the post-kan discard, and
  ron counts that indicator and its ura.
- Mahjong Soul shows an earlier kan’s owed indicator immediately after the
  chained added-kan announcement and before its robbing window. Tenhou waits
  for the window to pass.
- Riichi on the fourth-wind discard pays its stick in both clients. The
  campaign confirms payment from the next hand’s header. The engine scenario
  asserts its corresponding `reach_accepted` event before the abort.
- A fifth-copy wait counts at exhaustive draw in both clients if the four
  copies are not all concealed. Both permit riichi on the documented closed-kan
  form of that wait.
- Multi-ron honba go only to the nearest winner, all-last evaluates the
  post-nagashi scores, and dealer repeat takes priority in extension in both clients.

Still open:

- The chained closed-kan order in §3 above.
- Riichi ankan that preserves wait kinds while changing hand decomposition,
  and chankan with ippatsu. Published rules settle both, but neither has
  a distinguishing client replay cited here.
- Composite pao, open-kan rinshan dora, and declined tsumo. The relevant
  scenarios retain or now carry `unverified` tags.
- The winning tile of a heavenly hand and leftover sticks at game end.
  The heavenly-hand scenario tests the yakuman award only, and no scenario
  asserts either unresolved behavior.

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
