# Bot ladder and arena design

Status: draft, awaiting go-ahead (reviews in `Docs/Reviews/p4/design-*.md`;
section 9 lists revisions from the first draft). Only the `random` and `eager`
test bots, the mjai adapter, and a Mortal wrapper (`AGPL/strong/`) are
implemented so far.

This covers a ladder of bots of known, increasing strength, an arena that
measures them, and Mortal and akochan as the ceiling. The ladder serves as the
benchmark for LLM players and the opponent pool for the teaching site.

## 1. Goals

1. A ladder where each rung measurably beats the one below, so "plays at level N"
   means something.
2. Every bot sees only a `PlayerView` and masked events.
3. Deterministic: a ladder bot's choice is a function of what it has seen, with no
   random numbers and no dependence on hash order, floating-point library or core
   count. Any game replays from its trace.
4. Fast enough to play 20,000 hanchan per comparison in minutes.
5. Outside bots (Mortal, akochan, later LLMs) sit at the same table through mjai,
   with bad or missing answers counted, never fatal.

Non-goals: rivalling Mortal; three-player; hand reading or opponent modelling.

## 2. Where things live, and the bot interface

```
Sources/RiichiBots/     library: Bot protocol and the ladder; depends on Riichi only
Sources/mj/             arena command, drivers, mjai adapter (existing)
AGPL/strong/            build scripts and wrappers for Mortal and akochan (AGPL, separate)
```

`RiichiBots` has no Foundation and no I/O. It uses integer arithmetic throughout
(probabilities as parts per ten thousand, values in points), which sidesteps the
missing `exp`/`log` on WebAssembly and any difference between math libraries.

```swift
public protocol Bot: Sendable {
    init(seat: Seat, rules: Rules)
    mutating func observe(_ event: MaskedEvent)          // every event of the game, in order
    mutating func decide(_ view: PlayerView) -> Action   // one of view.legalActions
}
```

One bot value lives for one game. `observe` is called for every event before any
`decide` that follows it. A ladder bot that returns an action outside
`legalActions` fails the arena run (it is a bug); for outside bots the same thing
is a counted substitution.

LLM players and mjai processes are not `Bot`s. They implement the existing `Player`
protocol in `mj`, which has the prompt binding, timeouts and counters.

**Additions to `Riichi` that the ladder needs** (done first):

- the order of calls on `TableMeld` (which meld came when, relative to discards);
- for a call action, the discards that will be legal after it; for `riichi`, the
  discards that keep tenpai (they differ by ruleset on fifth-copy waits);
- for a tenpai hand, the value of each wait (`score` per wait, with and without
  riichi);
- a view-only legality path, so a ladder bot can itself be run as an mjai process
  later (today only the full round state computes legal actions and furiten). Not
  needed for the arena; listed so it is not forgotten.

## 3. The ladder

Each rung is the one below plus one idea, and every rule is mechanical.

**Tie-break T**, used wherever choices are otherwise equal: keep red fives, then
dora; then prefer to discard honors in the order guest wind, seat wind, round wind,
dragons; then terminals; then 2 and 8; then the lowest kind. Discarding the drawn
tile wins a tie between equal tiles.

**Threat**: an opponent in riichi, or with three or more melds, or with two melds
one of which is a pon of a dora or of a value honor.

**Danger order** of a tile against one opponent, safest first: genbutsu; honors by
copies visible (3, 2, 1, 0); suji terminals; suji 2/8; suji 3–7; half-suji;
non-suji terminals; non-suji 2/8; non-suji 3–7. A tile's danger is its worst class
over the threats (over all opponents if there is no threat).

| Rung | Name | Rule |
|---|---|---|
| 0 | `random` | Uniform over legal actions. The only bot with a seed. |
| – | `tsumogiri` | Control, not a rung: discards the drawn tile, never calls, takes an offered win. |
| – | `folder` | Control, not a rung: discards the least dangerous tile, ties by more copies visible, then T reversed. Never calls or declares riichi, takes an offered win. |
| 1 | `shanten` | Discard to minimise shanten, then maximise unseen improving tiles, then T. Riichi whenever legal. Always win. Never calls or kans; never declares nine terminals. |
| 2 | `defender` | Rung 1 plus push/fold. Fold when a threat exists and own shanten is 2 or more, or is 1 with fewer than 40 live tiles left. Once folded, stay folded for the hand unless tenpai with 4 or more unseen, non-furiten waits. Folding is the `folder` rule against the threats. |
| 3 | `waits` | Rung 2 plus wait quality. At tenpai, among minimum-shanten discards choose by unseen copies of waits that are not furiten and that have a yaku. At one away, rank by two-step ukeire: over each improving draw, the best resulting tenpai's good waits. |
| 4 | `value` | Rung 3 plus value. Rank by unseen × expected han, counting dora, red fives, value-honor pairs and triplets, and tanyao, pinfu and iipeikou only when already true of the best reading. Stay dama when the hand has a yaku and a dama ron is worth 8,000 or more (12,000 as dealer), or in all last when a dama ron takes first. No riichi when every wait is dead. |
| 5 | `caller` | Rung 4 plus calls. Pon a value honor whenever shanten does not rise. Other calls only if shanten falls and the hand passes one yaku check: holds a value-honor set; or is all 2–8 (open tanyao on); or is one suit plus honors with at most two tiles off; or, for pon, has four or more pairs and triplets. Never call when folded. Closed kan only when it costs no shanten or ukeire and there is no threat; no open or added kan under a threat. |
| D | `digital` | One expected-value formula for every decision (section 4). |
| O | `occult` | Rung 5 with parameters bent by "flow": after a win, lower the fold thresholds and call more; after dealing in, the reverse; a "lucky" suit is kept longer. A wrapper of about a page, compared with rung 5, which it should measurably lose to. |
| S | `mortal`, `akochan` | Outside engines (section 6). |

The gate runs from `shanten` against `random` upward. The two controls and `occult`
are reported in the rating table but are not rungs.

## 4. `digital`

For each legal action `a`, with `H` the hand after it and `t` the turns left:

    EV(a) = W(H, t) · V(H)
          − Σ over opponents s of  P(s, t) · R(tile, s) · L(s)
          − (1 − W − Σ P·R) · N(H, t)

- `W`: chance to win, from a table by shanten, two-step ukeire bucket, `t` and
  number of threats; at tenpai, by good unseen waits and `t`.
- `V`: mean of `score` over the waits weighted by unseen copies, with riichi and an
  ura expectation added when `a` includes riichi.
- `P(s, t)`: chance opponent `s` is tenpai: 1 in riichi, otherwise a table by turn,
  melds and hand discards since the last call.
- `R(tile, s)`: deal-in rate by the danger class of section 3 against a tenpai `s`.
- `L(s)`: expected cost of dealing in, by riichi, dealer, melds and dora shown.
- `N`: expected exhaustive-draw payment.

Before all last the utility is points. In all last and the extension, each outcome
maps to the resulting placement and its uma and oka, exactly for the last hand
(ignoring a dealer repeat); from South 3 it is blended linearly toward that. No
search, no hand reading.

**Where the tables come from.** Every table can be fitted from self-play of rung 5
bots, so the bots never depend on restricted records. Fitting from the real game
records instead would be better data for `P`, `R` and `L`; whether to do that is
the owner's decision (section 8). Either way the tables are generated by a script
into Swift literals, each with its source and sample count, and only aggregates
(no game ids, no names) reach the repository.

## 5. The arena

`mj arena` plays match-ups and reports who is better, with error bars fixed in
advance.

- **Blocks.** A block is one base seed played in every distinct seating of the
  match-up: 4 games for one-against-three (A,B,B,B), 6 for two-against-two, 12 for
  (A,B,C,C), 24 for four different bots. All statistics are over block means.
- **Seeds.** One master seed gives each block's wall seed and, through a one-way
  hash, anything else. Wall seeds are high-entropy and never shown to a bot. With
  an outside bot at the table the block still shares one wall seed across its
  seatings (fresh per block, not per game), because blocking needs it; an outside
  process cannot use that, since processes are restarted or reset per game and the
  seed is not derivable from what a seat sees.
- **Development versus gate seeds.** Tuning uses one master seed; the gate uses a
  different one, chosen and written down before the gate run. A gate run is made
  once per candidate, with the game count fixed beforehand.
- **Size.** Placement per game has a standard deviation of about 1.12, so resolving
  a difference `d` needs about 9.8 / d² games: 3,900 for 0.05, 10,900 for 0.03,
  24,500 for 0.02. Budget: 20,000 hanchan (5,000 blocks) per adjacent pair per
  ruleset.
- **Gate statistic.** One-against-three: the candidate's mean placement minus 2.5.
  A rung passes when the upper end of the 95% interval (a t-interval over block
  means) is below zero, under both rulesets.
- **Measures**, per bot: mean placement, rank points (bootstrap interval; busts
  give heavy tails), placement shares, mean final score; per hand: win, deal-in,
  riichi and call rates, mean win and deal-in values, tenpai rate at draws; time
  per decision; substitutions by kind; and the measured design effect of blocking
  (walls are per hand, so blocking mostly balances seats and the first hand).
- **Ratings.** A Plackett–Luce fit over all games, per ruleset and game length,
  with intervals from resampling whole blocks; the direct one-against-three results
  are published beside it and take precedence.
- **Reproducible.** Results are summed in game order after the run, so they do not
  depend on core count. Referee files (traces, unmasked logs) are written where bot
  processes cannot read them.
- **Throughput target:** 100 hanchan per second per core for rungs up to 5, 20 for
  `digital`; a benchmark reports each.

**Completion gate:** every adjacent pair passes; a rating table for the whole ladder
with the controls, `occult` and the strong bots; zero illegal actions from ladder
bots over 100,000 games including the directed rare-situation games; code review
of the bot code.

**Agreement with strong humans** (second yardstick, reported beside the arena,
never instead): on held-out real games, for decisions with more than one sensible
option, how often a bot's discard matches a top-room player's; call-or-pass scored
as balanced accuracy; `random` and `shanten` as baselines. Human ranked play
optimises a different objective from the arena's uma, so this is a rough proxy.
It needs the owner's decision on using the records (section 8).

## 6. Mortal and akochan

Both are AGPL and live under `AGPL/strong/` as child processes; nothing links to
them.

- **Mortal: running.** `AGPL/strong/mortal_bot.py` wraps Mortal's own libriichi bot
  and the `haor/Mortal-S42` checkpoint (hash-verified, loaded with
  `weights_only=True`, kept on the external volume). It answers every event, takes
  its seat from `start_game`, and plays complete Tenhou-rules games through
  `mj selfplay --seat` with zero substitutions, at about 7 ms a decision on CPU.
  Still to do: keep one process across games (start-up is about 1.5 s), the other
  three community checkpoints, and a count of the times Mortal's own state
  disagrees with the engine about whether it may act.
- **akochan: not started.** It needs a shim: its pipe mode answers only some
  events, replies with arrays (`reach` then `dahai`; `pon` then `dahai`), and
  expects the original protocol's fields. Building on macOS arm64 needs Homebrew
  LLVM with OpenMP and a current Boost; it must run from its own directory; and it
  is slow (expect on the order of 100 CPU-hours for a few thousand games), so its
  sample will be small.
- **Rules.** Both assume Tenhou rules; games with them run under `--rules tenhou`.
- **Measured first:** each strong bot one-against-three versus rung 5 and versus
  `digital`; Mortal against akochan; the four Mortal checkpoints against each
  other. Protocol failures are reported separately from strength.
- **Coverage check** (the roadmap's question about what the checkpoints were
  trained to handle): run the strong bots through the directed rare-situation
  games and score what they do where the right answer is known (take the win,
  declare the abort, do not kan into a changed wait), alongside how often each
  situation occurs in a million real hands (`Docs/Notes/p3-reallogs.md`).

## 7. Who does what

| # | Package | Writer | Reviewers |
|---|---|---|---|
| G | `Riichi` additions of section 2; `RiichiBots` protocol; controls and rungs 0–3; `mj arena` with blocks, measures and intervals | Opus | Codex, Gemini |
| H | Rungs 4, 5, `digital`, and the table-fitting script | Codex | Opus, Gemini |
| I | Mortal (persistent process, all checkpoints), the akochan shim and build, strong-bot measurements, the coverage check | Gemini | Codex, Opus |
| J | `occult`; the human-agreement yardstick | Gemini | Opus |

G first. I continues now, since it needs only what exists.

## 8. Decisions for the owner

1. **Fitting constants from the real game records.** Self-play fitting works and
   needs no permission. The records would give better opponent-behaviour tables,
   and the human-agreement yardstick cannot be done without them. Only aggregate
   tables would enter the repository. Tenhou restricts reuse of its records.
2. **`occult`**: implemented as a one-page parameter wrapper on rung 5 rather
   than a full package.
3. **Game length**: hanchan for every gate and published number; East-only games
   only as a development convenience.

## 9. Changes from draft 1

| Change | Raised by |
|---|---|
| Ladder redefined with mechanical rules; push/fold is its own rung; wait quality, riichi versus dama and call conditions specified; `tsumogiri` and `folder` are controls | all three |
| `digital` given a formula, integer arithmetic, and an all-last placement utility | Opus, Codex |
| Gate statistic, block definition per format, 20,000 games per pair fixed in advance, held-out gate seeds | all three |
| One wall seed per block even with outside bots; one-way seed derivation | Gemini, Opus, Codex |
| Ratings per ruleset with block resampling; direct results take precedence | Codex, Opus |
| `Riichi` additions the bots need (call order, post-call and post-riichi discards, per-wait value) | Opus, Gemini |
| Bots are deterministic without a seed; no floating point in `RiichiBots` | Opus, Gemini |
| Outside engines need shims; akochan's protocol and build problems written down; Mortal's wrapper already built and working | all three |
| `occult` reduced to a wrapper and compared with rung 5, not `digital` | all three |
| Human-agreement yardstick given controls and baselines | Opus, Codex, Gemini |
