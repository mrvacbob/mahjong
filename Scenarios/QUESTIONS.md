# Open Questions & Spec Discrepancies

Disagreements between `Docs/Design/engine.md` and `Spec/rules.md`, and places
where either document is incomplete or ambiguous. Where the two disagree,
scenarios follow `Spec/rules.md` and list the item here.

## 1. Temporary furiten clearing on a call (resolved)

In both clients, a seat's own chi, pon, or open kan clears temporary furiten.
`furiten_cleared_by_own_call.scn` checks the flag immediately before and after
the pon and takes a legal ron before the seat draws again. Confirmed in real
game logs (`Docs/Evidence/real-logs.md`).

## 2. Pao on Ron honba in Mahjong Soul vs `engine.md` §4.2 (resolved)

- `Spec/rules.md` (§1 `pao_ron_split`, §4 item 31): States for Mahjong Soul
  that on a 3rd-party ron with pao, the liable player and discarder split the
  yakuman 50/50 and the liable player pays the honba (citing
  `mahjongsoul.com/news/46/`), matching Tenhou.
- `Docs/Design/engine.md` (§4.2): Mentions "and the liable seat pays the honba"
  only in the Tenhou clause, leaving Mahjong Soul honba payment implicit.
- Action taken: `Scenarios/pao_ron_third_party.scn` follows `Spec/rules.md`
  (liable seat pays the honba in Mahjong Soul as well). Real game logs
  (`Docs/Evidence/real-logs.md`) are consistent with this settlement.

## 3. Open kan → closed kan owed-indicator order if robbed by Kokushi (Mahjong Soul)

- `Docs/Design/engine.md` (§4.2): For open kan → closed kan, states the event
  order is `dora` (owed), `ankan`, `dora` (new), `tsumo`.
- Question: Under Mahjong Soul, a closed kan (`ankan`) can be robbed by Kokushi
  Musou (`rules.md` §4 item 16). If `dora` (owed) is emitted before `ankan`, it
  flips even if the `ankan` is robbed (which affects only the mjai event log,
  not a Kokushi yakuman's score). `rules.md` §5 item 10 settles the chained
  added-kan order, but no replay evidence answers this chained closed-kan
  question, so both closed-kan order scenarios carry `unverified` tags.

## 4. Adjusted score units for `GameResult` (resolved)

- `Docs/Design/engine.md` (§2, §5 step 5): States `Riichi` uses no floating
  point ("uma and oka stay in integer points"), and `Spec/rules.md` §1 gives
  Mahjong Soul `25,000` return, `0` oka, `[+15, +5, -5, -15]` uma, and Tenhou
  `30,000` return, `+20` oka (`+20,000` to 1st), `[+20, +10, -10, -20]` base uma.
- Action taken: `Scenarios/endgame_oka_uma_tiebreak.scn` expresses
  `adjusted_scores` in raw integer points (`final_score - return + oka*1000 +
  uma*1000`, e.g., `+27000` for `+27.0`), matching the engine's integer point
  units.

## 5. Client behavior checked in real game logs

Real game logs (`Docs/Evidence/real-logs.md`) settle these questions:

- Both clients reveal the owed indicator just before the post-kan discard, and
  ron counts that indicator and its ura.
- Mahjong Soul shows an earlier kan's owed indicator immediately after the
  chained added-kan announcement and before its robbing window. Tenhou waits
  for the window to pass.
- Riichi on the fourth-wind discard pays its stick in both clients. The logs
  confirm payment from the next hand's header, and the engine scenario asserts
  the corresponding `reach_accepted` event before the abort.
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
  scenarios carry `unverified` tags.
- The winning tile of a heavenly hand and leftover sticks at game end.
  The heavenly-hand scenario tests the yakuman award only, and no scenario
  asserts either unresolved behavior.

## 6. Physically impossible coverage gaps

Two items a reviewer asked for cannot arise in legal 4-player Riichi Mahjong and therefore have no scenario file:

- Dead-end Pon (`rules.md` §4 item 13): A seat with $k \in \{0,1,2,3\}$ melds holds $13 - 3k \ge 4$ concealed tiles. Calling Pon on tile kind $X$ uses 2 copies of $X$ from hand plus 1 discarded, leaving $11 - 3k \ge 2$ concealed tiles and at most 1 remaining copy of $X$ in the 4-copy deck. Because Pon kuikae forbids only kind $X$, at least one tile of a different kind always remains to discard.
- Submitted call losing to Four Riichi (`engine.md` §4.1 row 5): When the 4th seat declares riichi, all three other seats are already in riichi and cannot legally submit `pon`, `chi`, or `daiminkan`. Only `ron` (covered by `suucha_riichi_discard_ron.scn`) can legally be submitted on the 4th riichi discard.

## 7. Format limitation: post-robbed-kakan meld and kan-count state

After a robbed added kan (`added_kan_robbed_ippatsu_alive.scn`), the surviving pon and unchanged kan count are not directly observable from `Scenarios/FORMAT.md` assertions. Because a robbed `kakan` ends the round immediately on `ron`, no subsequent turn exists to probe legality, and `FORMAT.md` has no `assert_melds` or `assert_kan_count` directive. Exact `events:` already verifies that no `dora` or replacement `tsumo` event is emitted.

## 8. West 4 dealer repeat below 30,000 (resolved)

`Spec/rules.md` §1 `extension_max_round` states that the limit applies
when play would advance past the last hand of the extension. A below-target
dealer repeat in that hand continues play, as required by `engine.md` §5
step 4 and tested in `endgame_extension_w4_dealer_repeat.scn`.
