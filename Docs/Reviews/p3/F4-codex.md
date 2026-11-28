# Package F4 scenario review

Corrected the seven fixtures listed in the known issues in `Docs/Notes/p3-CD.md`. In all six kan fixtures, the Tenhou expectation now places the owed `dora` immediately before the replacement-tile discard. This matches engine design §4.2 and the ranked four-player rule for open and added kans. [Tenhou manual](https://tenhou.net/man/)

Traced both rulesets by hand from the seeded hands and draws through the legal reactions, event order, and settlement. Under the design's Mahjong Soul default, the owed reveal follows a window with no ron and precedes the call, draw, or abort. A ron on that discard ends the hand with the indicator still owed. The six Mahjong Soul event lists match that default. Added the missing unverified timing tag to the all-pass fixture and its index entry.

| Scenario | Hand review |
| --- | --- |
| `open_kan_chained_kan_discard_ron` | Seat 1 pons 9p, seat 0 passes the 1s discard, and seat 1 later calls daiminkan on 5z. The drawn fourth 9p makes kakan with no robber. Both runs reveal 1p before the second replacement draw. Seat 2's 7s ron has Pinfu, Tanyao and one 2p dora for 3 han 30 fu and 3,900 from seat 1. Tenhou also counts both 8p for 5 han 30 fu and 8,000. |
| `open_kan_discard_all_pass_dora` | Seat 3 passes its East pon. Both runs have 7p active by seat 2's 7s draw. Menzen tsumo, Pinfu, Tanyao and two 8p dora give 5 han 20 fu. The dealer pays 4,000 and the other two opponents pay 2,000 each. |
| `open_kan_discard_called_dora` | Seat 2 pons 6z, discards 9m and rons seat 3's 7s. The exposed green-dragon triplet is 4 fu, rounding the open ryanmen hand from 24 to 30 fu. Hatsu and two 8p dora give 3 han and 3,900 from seat 3 under both defaults. |
| `open_kan_discard_riichi_ron_ura` | Seat 0 declares double riichi on its first discard. The stick is accepted before seat 1's daiminkan cancels ippatsu. The dealer's 7s ron is 4 han 30 fu with double riichi, Pinfu and Tanyao for 11,600. Tenhou activates the second ura indicator, 7p, adding two han for 18,000. The dealer recovers its own stick and repeats at honba 1. |
| `open_kan_discard_ron_dora` | Seat 2's closed ryanmen ron on seat 1's 7s has Pinfu and Tanyao for 2 han 30 fu and 2,000. Tenhou counts both 8p, giving 4 han 30 fu and 7,700 without kiriage. |
| `suukaikan_open_kan_owed_dora` | Seat 0's three closed kans each reveal an indicator before the replacement draw. Seat 1's open kan makes four kans across two seats. Seat 2 can submit pon on 5z and the no-ron window resolves to the four-kan abort before the call is made. All scores stay at 25,000, the table has zero sticks, and East 1 repeats at honba 1. |
| `declined_tsumo_outside_riichi` | The legal 1s tsumo is declined by declaring ankan, preserving the structural 1s/4s waits. In Tenhou, temporary furiten survives rinshan. Seat 0 is offered `pon:44s` on seat 1's 4s, is explicitly barred from ron, and passes. Its next live draw clears furiten and wins on 4s. Haku and menzen tsumo give 2 han 70 fu and 2,300 from each opponent. The Mahjong Soul default permits the earlier ron. The tanki reading adds 2 fu for 80 fu and 3,900 from seat 1 at 1 han. Each dealer win repeats at honba 1 with zero sticks. |

The four nondealer wins above leave zero sticks and advance the round at honba 0. Each score vector matches the starting scores plus the listed payments.

The checker validates the fixtures structurally. The rule and result review was by hand, with no engine or client replay.

```text
OK: 132 scenarios passed (20 unverified).
```
