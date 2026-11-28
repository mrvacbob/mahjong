# F5 scenario reconciliation

The scenario evidence comes from the real-log campaign, `Docs/Notes/p3-reallogs.md`, and the updated rules in `Spec/rules.md` §§1 and 5. Modified payment expectations have hand calculations in their scenario comments.

| Scenario file (under `Scenarios/`) | Change |
| --- | --- |
| `abort_suufon_renda_riichi_stick.scn` | Run both presets. Seat 3 pays 1,000, leaving 24,000 and one carried stick. Assert the engine emits `reach_accepted` before the abort. Remove the tag. |
| `formal_tenpai_fifth_copy.scn` | Both presets count only Seat 1 as tenpai. Seat 1 receives 3,000 and each other seat pays 1,000. Preserve the all-concealed counterexample. Remove the tag. |
| `furiten_surviving_call.scn` → `furiten_cleared_by_own_call.scn` | Rename and retitle. In both presets assert furiten immediately before the pon and its clearance immediately afterward. Seat 1 rons before drawing again for 1,000 from Seat 2. Keep the before-call assertion in this sequence and use the existing kakan pass case for coverage of a blocked ron before the next own draw. |
| `open_kan_discard_ron_dora.scn` | Move the reveal before the discard in Mahjong Soul. Two kan dora bring the nondealer ron to 4 han 30 fu and 7,700. Remove the tag. |
| `open_kan_discard_riichi_ron_ura.scn` | Move the reveal before the discard in Mahjong Soul. The second ura indicator adds two han, so dealer ron is haneman for 18,000. The winner recovers its own stick. Remove the tag. |
| `open_kan_chained_kan_discard_ron.scn` | Describe the first indicator’s different timing relative to the robbing window. Add the second reveal before the discard in Mahjong Soul. Three dora make the ron a 5-han mangan for 8,000. Remove the tag. |
| `open_kan_chained_added_kan_robbed.scn` | Add a distinguishing test. Mahjong Soul emits the earlier kan’s owed indicator after `kakan` and before `hora`, making the ron 3,900. Tenhou has no intervening reveal and pays 2,000. |
| `open_kan_discard_all_pass_dora.scn` | Move Mahjong Soul’s `dora` before `dahai` with exact events. Remove the tag and update the title and commentary. |
| `open_kan_discard_called_dora.scn` | Move Mahjong Soul’s `dora` before `dahai` and the following pon. Update comments and remove the tag. |
| `ippatsu_cancelled_by_kakan.scn` | Insert `dora(1z)` before the post-kan discard. The additional indicator and its ura add zero han. Correct the setup discard in the comment to 9s and remove the tag. |
| `kakan_robbing_pass_furiten.scn` | Move `dora(3z)` before the post-kan discard and cite the campaign. |
| `riichi_discard_daiminkan_cancels_ippatsu.scn` | Insert `dora(2z)` before the post-kan discard. Remove the tag. |
| `suukaikan_open_kan_owed_dora.scn` | Move Mahjong Soul’s reveal before the discard and subsequent four-kan abort. Update the comment and remove the tag. |
| `riichi_fifth_copy_closed_kan.scn` | Add both-preset coverage of declaring riichi on a fifth-copy wait when the four copies are in a closed kan. The dealer pays the stick and subsequently receives 3,000 at exhaustive draw, for a net gain of 2,000. |
| `double_ron_with_sticks_and_honba.scn`, `triple_ron_rulesets.scn`, `pao_double_ron.scn` | Replace the verification tags with the campaign citation for nearest-winner honba. |
| `endgame_nagashi_pushes_dealer_out_of_first.scn`, `endgame_extension_dealer_repeat_priority.scn` | Replace the verification tags with the campaign citation for evaluating post-nagashi scores and prioritizing dealer repeat. Update the dealer-repeat comment. |
| `open_kan_to_closed_kan_chain.scn`, `open_kan_to_robbed_closed_kan.scn` | Clarify that the tags concern chained closed kans. The evidence in §5 item 10 distinguishes chained added kans. |
| `open_kan_rinshan_no_kan_dora.scn`, `pao_composite_yakuman.scn`, `pao_composite_yakuman_ron.scn` | Add tags for expectations the campaign found no discriminating log to settle. |
| `INDEX.md` | Update the scenario count, entries, source citations, and verification statuses. |
| `QUESTIONS.md` | Close the answered questions and document the limits of the evidence. |
| `Docs/Reviews/p3/F5-codex.md` | Record the reconciliation and verification. |

The audit checked kan and dora event sequences, furiten assertions and intervening calls, fourth-wind aborts, and fifth-copy waits and riichi. No other event expectation puts `dora` immediately after `dahai`. The heavenly-hand case asserts the yakuman award and has no winning-tile selection expectation to tag.

Eight scenario tags remain. Two concern chained closed-kan order, two concern composite pao, one concerns open-kan rinshan dora, and one concerns declined-tsumo furiten. The two remaining tags are for riichi ankan with a decomposition change and chankan plus ippatsu, both supported by published rules and still awaiting client replay confirmation.

`python3.14 Tools/scenario.py --check` validates scenario files and wall construction. It does not execute the Swift engine.

```text
OK: 134 scenarios passed (8 unverified).
```
