# Review of `docs/design/engine.md` (draft 1): opus

Read: `docs/design/engine.md`, `spec/rules.md`, `spec/formats.md`, `Sources/mj/*`,
`docs/design/wasm-spike.md`, `agpl/mj-rs/{README,NOTES,DISAGREEMENTS}.md`, and, for the
protocol only, Mortal's `libriichi/src/{mjai,state,arena}` and akochan's mjai client.
Nothing is copied from either. Where I cite libriichi I describe its behaviour and do
not quote its code.

Severity counts: 1 blocker, 9 should-fix, 5 suggestions.

---

## Findings

### 1. Blocker. §4.1: furiten is tied to being asked, which misses cases the rules require

The design makes a seat furiten only if it "could ron and answers `pass`". Two cases in
`rules.md` fall outside that:

- **A wait that cannot ron for lack of yaku.** `rules.md` §4 item 28: passing a ron
  "(or being unable to Ron due to no yaku) triggers temporary furiten". That seat has
  no legal `ron`, so under §4.1 it is not asked and never becomes furiten. It could
  then ron the same kind from the next seat in the same go-around, after picking up a
  yaku-bearing reading, or ron a different wait that does have a yaku. libriichi marks
  this "no-yaku furiten" straight away when the discard is seen (`state/update.rs`,
  the `dahai` handler), which matches Tenhou's display.
- **Riichi and a missed tsumo.** Item 28 also says that after riichi, passing a winning
  tile that you drew yourself makes you permanently furiten. That is a `turn` phase
  event, and §4.1 only covers reactions.

The case the brief asks about, a call or pass that loses to another seat's ron, does
not matter: the round ends on the ron, or on sanchahou under Tenhou rules, so nobody's
furiten state is ever read again. Don't spend code or tests on it. The case that does
need care is a call that loses to another seat's call. A seat that could have ronned
but answered `chi`, and lost to someone's `pon`, must become temporarily furiten.
"Answered something other than ron" covers it.

**Change.** Take furiten out of the answer-handling code. When a reactions or robbing
window resolves without a win, the rule is: every seat other than the actor that holds
the tile's kind as a structural wait becomes temporarily furiten, or permanently furiten
if it is in riichi. This holds whether or not the seat was asked, and whether or not it
had a yaku. In the `turn` phase, a riichi seat that has `tsumo` among its legal actions
and picks anything else becomes permanently furiten. The design also has to say what
happens on a closed kan of one of your wait kinds when you are not on kokushi, so you
cannot ron it. libriichi does not mark furiten there. I believe that is right for
Tenhou and Mahjong Soul because the tile is not a winning tile for you, but I am unsure.
Add one scenario test for each of these three cases. Stop storing "discard furiten" as
a flag: compute it from the pond and the current waits, because the waits change on
every discard and call, and a stored flag goes stale.

### 2. Should-fix. §3: walls are seeded by `(seed, kyoku index)`, so repeated hands get the same wall

E1 with 0 honba and E1 with 1 honba (a dealer repeat or an abortive draw) have the same
kyoku index. Implemented literally, the repeated hand deals the identical wall.
libriichi avoids this by hashing kyoku and honba together (`arena/board.rs`,
`init_from_seed`). **Change.** Use a hand sequence number that counts every hand played
in the game from 0, and write that into the shuffle spec. Never put the seed in a
masked `start_game`. Mortal's `start_game` has a `seed` field, and any bot that is given
the seed can rebuild every wall.

### 3. Should-fix. Rule error in `rules.md` §1 `pao_composite_yakuman` for Tenhou

`rules.md` gives Tenhou `liable_yakuman_only`. Tenhou's manual says the liable player
pays the whole score "including composite yakuman": 「複合役満を含む得点を、ツモ＝全額・ロン＝折半で支払う。積み棒は包。」
(tenhou.net/man, rule section. libriichi quotes the same line in `arena/board.rs` and
applies pao to the full point value.) So for Tenhou, pao covers the whole hand. **Change.**
Make it a `Rules` field: Tenhou = `whole_hand`, Mahjong Soul = `liable_yakuman_only` as
`rules.md` has it, still marked unverified since I could not confirm it. Correct the
`rules.md` row. Otherwise the libriichi differential will report this on every pao
composite.

### 4. Should-fix. §4.2, kan dora: the Tenhou default and the chained-kan order disagree with libriichi

- **Ron on the discard after an open kan.** The design defaults to "not revealed" for
  both rulesets. libriichi, which follows Tenhou, reveals the pending indicator *before*
  it broadcasts the kan player's `dahai`. A ron on that discard therefore counts the new
  dora, and its ura as well, since libriichi takes the ura count from the indicators
  revealed. I am fairly sure this is Tenhou's real behaviour (the new indicator is
  flipped when the tile is discarded), but I have not checked it against a Tenhou log.
  **Change.** Make the default per ruleset: Tenhou = revealed at the discard, Mahjong
  Soul = the unverified `rules.md` §5 item 4. In the log, emit `dora` *before* `dahai`
  when the field says "revealed" and after the window when it says not.
- **Chained kans.** The design says the pending dora is revealed "just before another
  kan by the same seat". libriichi does that only for an ankan, where the order is
  `dora`(pending), `ankan`, `dora`(new), then the rinshan `tsumo`. For a kakan after an
  open kan it waits until the chankan window has passed: `kakan`, robbing window,
  `dora`(pending), `tsumo`. As a result a robber of the kakan does not see the earlier
  kan's dora. (A daiminkan can never directly follow the same seat's open kan.) **Change.**
  Write down the order for both chains. Mahjong Soul's order here is unverified; add it
  to `rules.md` §5.

### 5. Should-fix. §6: "Event order follows Mortal's dialect" is never written out, and several orders are not obvious

Put a table in the design. These are the orders libriichi's arena produces
(`arena/board.rs`), and libriichi's `PlayerState` expects them:

| Situation | Order |
|---|---|
| Riichi | `reach`(actor), then `dahai`. `reach_accepted` comes **immediately before** the next `tsumo`, `chi`, `pon` or `daiminkan`, and that is when the 1,000 points move. There is no `reach_accepted` if the discard is ronned. |
| Ankan | `ankan`, `dora`, `tsumo` (rinshan). See item 4 for an ankan that follows an open kan. |
| Kakan / daiminkan | `kakan`/`daiminkan`, `tsumo` (rinshan), … `dora` before or after `dahai`, as in item 4. A `reach_accepted` that is due comes before the `daiminkan` event. |
| Multi-ron | One `hora` per winner, in turn order starting after the discarder. Each `hora` carries its own `deltas`. The first carries all sticks and honba. `ura_markers` is `[]` for winners not in riichi. |
| Four riichi | libriichi logs `reach_accepted`, then the next seat's `tsumo`, then `ryukyoku`. It checks for the abort one step late. Our engine will reasonably omit that `tsumo`. `PlayerState` accepts both forms, but an arena-log diff (item 8) has to normalise it. |
| Four winds | libriichi ends the round **at** the fourth wind's `dahai`, before any `reach_accepted`, so a riichi declared on that discard pays no stick. Nobody can ron or call that tile: all four copies have been discarded, and the three earlier discarders are furiten on it. So the only open question is the stick. Unsure what Tenhou and Mahjong Soul do. State the engine's choice. |
| Four kans (2+ seats) | The abort comes ahead of anything except `hora` on the discard after the fourth kan. A `pon` answered on that discard is not made, and a riichi declared on it is not accepted. "Passes" in §4.2 should mean "no ron". |

### 6. Should-fix. §6: the fields to emit, and a JSON reader that can handle real bots

Mortal's `Event` is a subset of the original mjai protocol: `hora` has only
`actor, target, deltas, ura_markers`, `ryukyoku` has only `deltas`, `start_game` has
`names, seed`, and `end_kyoku`/`end_game` carry no fields. akochan speaks the original
protocol. It reads `id` from `start_game` (its `main.cpp`) and updates its scores from
`scores` fields on later events (`mjai_client.cpp`). It also expects the `hello`/`join`
handshake of the TCP-era server. **Change.** Emit a superset; serde in Mortal ignores
unknown fields:

- `start_game.id` in each seat's stream.
- `hora`: `pai`, `deltas`, `ura_markers` *and* `uradora_markers`, `hora_tehais`, `yakus`,
  `fu`, `fan`, `scores`.
- `ryukyoku`: `reason`, `tenpais`, `tehais` with noten hands masked, `deltas`, `scores`.
  Kyuushu can only be told apart from other abortive draws by `reason`.
- `reach_accepted.scores` and `end_game.scores`.

Then the JSON reader. Mortal's replies are not flat: they carry `meta` with
`q_values` (float arrays), `mask_bits`, and a nested `kan_select` object. The
hand-written reader must skip any nested value, floats included, or it will reject
every Mortal answer.

### 7. Should-fix. §6: the `Player` adapter: two-step riichi, replies to every event, defaults, hangs

- mjai riichi is two decisions. The bot answers `reach`, receives the `reach` event, and
  only then answers `dahai`. The engine's single `riichi(discard)` is fine, but the
  adapter must run both steps. It also has to say what happens when the second answer
  is not a tenpai-keeping discard. Proposed rule: the riichi is cancelled and the
  answer is treated as an illegal plain discard, then the normal substitution applies.
- "Replaced by a default (tsumogiri, or pass)". After a chi or pon there is no drawn
  tile, so there is nothing to tsumogiri. **Change.** The default is the drawn tile if
  it is legal, otherwise the first legal discard in canonical order, and `pass` in a
  reactions window.
- The mjai stdin protocol sends every event and expects a reply (`none`) to each one.
  The adapter must feed all masked events and throw away the `none`s, and ask for a
  real answer only from seats that have legal actions.
- Open question 3 belongs here now, not later. A child process that hangs stalls the
  arena just as badly as one that sends malformed output. Give the adapter a timeout
  that counts as an illegal answer.

### 8. Should-fix. §8 layer 2 is not feasible as described, and a stronger variant is available

**Feasibility.** `agpl/mj-rs/NOTES.md` says that crate deliberately *omits* libriichi's
mjai event processor and `PlayerState` update logic. It ports only the snapshot
decisions, because crates.io was unreachable and libriichi has unconditional `pyo3`,
`numpy` and `ndarray` dependencies. "Feed masked events to libriichi's player state"
therefore means one of two things. The first is a real build of Mortal's `libriichi`:
one-time network access, Python headers for `pyo3`, plus `serde`, `serde_with` and
`derivative`. The second is porting about 2,000 lines of `state/*.rs` and `mjai/event.rs`
into mj-rs, which creates a second implementation with its own bugs and makes it a
weaker oracle. **Change.** Build a new, small AGPL crate next to mj-rs that depends on
upstream `libriichi` by path, and `cargo vendor` it once so it builds offline from then
on. Do not grow mj-rs.

**What libriichi exposes.** Per seat, `ActionCandidate` holds booleans: `can_discard`,
`can_chi_low/mid/high`, `can_pon`, `can_daiminkan`, `can_kakan`, `can_ankan`,
`can_riichi`, `can_tsumo_agari`, `can_ron_agari`, `can_ryukyoku`. It also gives
`ankan_candidates`, `kakan_candidates`, `discard_candidates` (kuikae), `waits`,
`at_furiten` and `shanten`, and `agari_points(is_ron, ura)` returns a `Point` with ron
and tsumo payments only, without yaku or fu. And there is a full arena: `Board` has
`pub` fields for `haipai`, `yama`, `rinshan`, `dora_indicators`, `ura_indicators`,
`scores`, `kyoku`, `honba` and `kyotaku`, and `BoardState::poll` runs a hand from those
fields given the reactions.

**Stronger variant.** For each hand, load *our* wall into a `Board`, feed it the
actions from our log as reactions, and diff its log against ours event by event after
normalising the items in item 5. Then check `KyokuResult` (`can_renchan`, sticks left,
scores). This also checks draw payments, nagashi, pao, the stick and honba split,
multi-ron deltas, abort timing, dora order and renchan, none of which the per-seat
`PlayerState` comparison sees. Keep the `PlayerState` comparison for legality, and
compare **all four seats after every event**, not only the seats our engine asked. That
is what catches a decision point the engine failed to offer, which is exactly the
mistake in item 1.

**What it will not catch.**

- The Mahjong Soul rules, as the design says.
- libriichi's own deviations, which must go on a written whitelist:
  - It never offers a kokushi ron on an ankan; the `ankan` handler does not set ron.
    Tenhou allows it.
  - Tenhou and chiihou are always exactly 1x and do not stack (board.rs header).
  - No sanchahou abort (board.rs header).
  - `can_riichi` is a boolean only, so the choice of riichi discards is unchecked.
- Red-five variants of chi and pon, which are not distinguished.
- Yaku lists and fu.
- Game end, because `Game` draws its own walls from its own seed. Port the end-check
  logic separately (see item 9).
- Anything both engines get wrong in the same way.

**Bots.** Random play rarely reaches tenpai. Use biased random bots instead: always
win when they can, declare riichi when legal, and call and kan with high probability.
That is what drives play into scoring, pao, the four-kan rules and chankan.

### 9. Should-fix. §5: end-of-game conditions are incomplete

As written ("last scheduled round finished with someone ≥ 30,000", "sudden death once
anyone reaches 30,000"), the game would end in cases where it continues.

- In All Last, a dealer repeat (win or tenpai) with the dealer **not** first continues
  the game, even when another player has ≥ 30,000.
- The same holds in the extension round. Sudden death is suspended while the dealer
  repeats and is not first. libriichi's `arena/game.rs` handles this, with a comment
  citing Tenhou's rule.
- The 30,000 test uses scores **before** the leftover sticks are paid out (供託未収).
- "First" for agari-yame and tenpai-yame uses the seat-order tie-break.
- An abortive draw in All Last continues with honba + 1. No yame check applies.
- Tobi is checked first, including in the extension round.

**Change.** Write the end check as a single function with a small truth table in the
design, and give each row a scenario test.

### 10. Should-fix. §3/§4: hidden nondeterminism and shared mutable state in Swift

- `applying(_ decisions: [Seat: Action])` uses a `Dictionary`. Swift's `Hasher` is
  seeded randomly per process, so any iteration over it, or over a `Set` (the existing
  code uses `Set<Flag>`, `Set<Kind>` and `Array(Set(self))` in `Tile.swift`), can differ
  between runs and platforms. That breaks goal 2 as soon as anyone iterates instead of
  sorting. Use a fixed four-slot value (`struct Decisions { var bySeat: (Action?, Action?, Action?, Action?) }`
  or `[Action?]` of count 4) and make it a lint rule that Set and Dictionary iteration
  in `Riichi` is always sorted.
- `ShantenCalculator` is a `final class` with a growing memo dictionary. That is hidden
  shared mutable state behind an API described as pure. It is not `Sendable` under
  Swift 6, so a multi-threaded arena either fails to compile or races. Replace it with
  precomputed immutable per-suit tables (there are only 5^9 suit states, fewer that
  are reachable), or pass an instance per thread explicitly.

### 11. Should-fix. §1/§3: the 500 hanchan/s target is unmeasured and about 20× beyond the current code

`wasm-spike.md` measures `legal` at about 44k requests/s natively, about 23 µs each,
though that includes line-protocol parsing. Ron checks today call the full `score`
through `try?` (`Legal.swift`). A random-bot hanchan has roughly 8 to 10 hands of 60 to
70 turns. With one turn-legal and up to three reaction checks per discard, that is more
than 2,000 evaluations per game. At current speed that is tens of milliseconds per
game, so on the order of 20 hanchan/s. **Change.** Either state the target after
package B is measured, or design for it now:

- Cache each seat's waits whenever its 13-tile hand changes.
- Make a ron check a wait lookup plus a cheap "has any yaku" test; call full `score`
  only when someone actually wins.
- Run the riichi-discard search only when shanten is 1 or less.
- Store `Counts` in fixed-size inline storage (`InlineArray`, available on the 6.4
  toolchain) instead of a heap `[Int]`.
- Make the core a `mutating func apply`, with `applying` as a wrapper that copies.

### 12. Should-fix. §3: "`Meld` kept as is" does not hold for the engine

Today's `Meld` is `kind` plus `tiles`. The engine needs, for every open meld, **which
seat it came from** and **which tile was taken**: mjai `target` and `pai`, pao
liability, kuikae, nagashi ("none of your discards were called"), and the `kakan`
`consumed` field all depend on them. Add `from: Seat?` and `taken: Tile?`. That changes
the line-protocol parser only in that it leaves both fields nil.

### 13. Suggestion. §4: smaller corrections in the 4.2 bullets and the phase model

- Ippatsu: "for a seat after its own next discard" should read "at that seat's first
  discard after the riichi discard". The riichi discard is itself a discard.
- Haitei must exclude rinshan draws. A kan made with one live tile left leads to a
  rinshan draw at live count 0. That draw is rinshan only, and the discard after it is
  houtei. libriichi tests `tiles_left == 0 && !at_rinshan`. "Set from the wall count"
  alone gets this wrong.
- Wall layout: mjai has no deal order. `start_kyoku` only lists the 13-tile hands, and
  akochan's sample log has them unsorted. Drop "in mjai's order" and define our own.
- A phase where no seat has a decision, such as a discard nobody can react to, should
  never be observable. `applying` should advance through it. Otherwise every driver
  has to remember to call `applying([:])`, and the invariant "the seat to act has legal
  actions" does not cover reactions.
- Pao with multi-ron, and pao when the liable seat is the discarder: both are in
  `rules.md`. Name them in §4.2 so that each gets a test.
- Everything else in 4.2 matches `rules.md` as far as I checked: the riichi preconditions,
  the first-turn flag and the ankan clearing it, the chankan conditions, one seat with
  four kans, the four-riichi stick, the last-tile rules, kuikae, nagashi and multi-ron
  sticks.

### 14. Suggestion. §6/§2: WebAssembly and JavaScript

- JavaScript cannot block inside `decide`. The step API (`legalActions` plus `applying`)
  is the JS API. `Player` is a native convenience, so keep it out of `Riichi`, or make it
  generic. Embedded Swift, which `wasm-spike.md` lists as a size option, forbids
  existentials, so `[any Player]` would not compile there.
- mjai JSON alone cannot drive a UI. Export `PlayerView` and the legal actions as JSON
  too.
- Seeds are `UInt64`, and JS numbers are exact only up to 2^53, so pass seeds as decimal
  strings. `Int` is 32 bits on wasm32. That is fine for points, but should be stated.
- Masked events need an "unknown tile" in the `Event` type (`Tile?` or `.unknown`).
  Decide which now, because it shapes every `switch`.
- Uma and oka should stay in integer points, with no floating point anywhere in
  `Riichi`.

### 15. Suggestion. §8: more cheap checks

1. **View reconstruction.** For every seat at every step, fold the masked events into a
   view and compare it with `PlayerView(state, seat)`. This catches leaks and view bugs.
2. **Self round-trip.** `selfplay` log → `mj replay` must reproduce the log byte for
   byte.
3. Native and wasm produce the same log hash for the same seed.
4. **Suit permutation.** A metamorphic test: swap m/p/s, reds included, and expect the
   same results for legality, scoring and deltas.
5. **Action fuzzing.** Every action in `legalActions` applies without error, and
   sampled actions outside it throw.
6. **Furiten invariant** (item 1). After every resolved window, every non-winning seat
   whose wait includes the tile is furiten.

---

## Sequence walkthrough

| Sequence | Verdict |
|---|---|
| Riichi discard ronned | Correct: no stick, no `reach_accepted`. The event order needs writing down (item 5). |
| Added kan robbed | Correct (ippatsu kept, no dora, no rinshan). The pending dora from an earlier open kan has to stay hidden through the window (item 4). |
| Closed kan, rinshan tsumo | Correct: dora immediately, rinshan flag, ippatsu cleared (item 26). The kokushi rob window is correct but libriichi will not check it (item 8). |
| Open kan, replacement, another kan, discard | The design is unclear and does not match libriichi on reveal order (item 4). |
| Fourth kan | Correct for one seat. For two or more, "passes" has to mean "no ron", and calls on that discard are not made (item 5). |
| Pon then kuikae | Correct (existing code). `turn(after: call)` must offer discards only. |
| Last-tile discard | Correct. Haitei after a rinshan draw is wrong as worded (item 13). |
| Double ron with a riichi stick on the table | Correct split. Event order and per-hora deltas need writing down (item 5). |
| Nine terminals | Correct. Emit `reason` so the log can tell it apart (item 6). |
| Four winds | The stick timing for a riichi on the fourth wind is not stated (item 5). |

## Answers to §10

1. **Real logs.** Yes: start with layer 2, using the arena variant (item 8). For real
   logs:
   - The owner's own Mahjong Soul game records are lawful to use. They are also the only
     way to settle `rules.md` §5 items 2, 4 and 6 and the open order questions in items 4
     and 5. A few dozen targeted games beat thousands of random ones.
   - Tenhou's phoenix archives can be converted locally with our own tenhou6→mjai
     converter. Keep them out of the repository. Whether this is within Tenhou's terms is
     unsure, so the owner should decide.
   - akochan's `haifu_log_sample.json` works as a replay smoke test now.
2. **Asking only seats that can act.** Keep it, but take furiten out of the asking
   (item 1). The pause that gives a seat away is a UI matter for later, and can be
   hidden with a uniform delay.
3. **Simultaneous answers.** Collecting every answer and then resolving them is right.
   The adapter needs a timeout now (item 7).
4. **Mercury.** I agree a second state machine is not worth building. libriichi's
   `Board`, driven with our walls, is that second state machine for Tenhou rules, at no
   cost.
5. **Unverified Mahjong Soul rulings.** One `Rules` field each is fine, but set the
   defaults per ruleset. Kan dora on a ronned post-kan discard: Tenhou "revealed"
   (item 4). Multi-ron honba: nearest winner. Nagashi against tenpai-yame: check after
   all payments. Add pao on composite yakuman for Tenhou (item 3) and the chained-kan
   dora order (item 4) to the list.

## Overall verdict

The architecture is right: one legality function, pure value-type steps, masked views,
mjai at the edge, and differential testing as the main source of confidence. Package A
can start now. Package B should not start until item 1 is fixed. The design ties furiten
to being asked, which contradicts `rules.md` item 28. The libriichi comparison would
eventually flag it, but only if the checker compares all seats. The should-fix items
are cheap to settle on paper now and expensive later:

- the wall seed (item 2)
- the Tenhou pao and kan-dora defaults (items 3 and 4)
- an explicit event order and field superset (items 5 and 6)
- the adapter details (item 7)
- a feasible libriichi build and an arena-level diff (item 8)
- the game-end table (item 9)
- determinism and `Sendable` problems (item 10)
- an honest performance target (item 11)
- a richer `Meld` (item 12)

With those folded into draft 2 I would approve it.
