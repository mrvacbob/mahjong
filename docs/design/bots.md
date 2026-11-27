# Phase 4 design: bots and the arena

Status: **draft 1, for council review.** Nothing here is implemented yet, apart from
the `random` and `eager` test bots and the mjai child-process adapter that Phase 3
built in `Sources/mj/`.

Phase 4 delivers a ladder of bots of known, increasing strength, an arena that
measures them, and the two outside engines (Mortal and akochan) as the ceiling.
The ladder is what LLM players will be measured against in Phase 5 and what the
teaching site's opponents will be in Phase 6.

## 1. Goals

1. A ladder where each level measurably beats the one below, so "plays at level N"
   means something.
2. Every bot sees only a `PlayerView` and masked events. A bot cannot be handed the
   wall or another hand, by construction.
3. Deterministic: a bot's choices are a function of what it has seen and its own
   seed, so any game can be replayed from its trace.
4. Fast enough to play tens of thousands of hanchan in minutes, so differences of a
   few hundredths of a placement can be resolved.
5. Outside bots (Mortal, akochan, later LLMs) sit at the same table through mjai,
   with illegal or missing answers counted, never fatal.

Non-goals: a bot that rivals Mortal; three-player; time controls beyond a per-move
timeout for outside bots.

## 2. Where things live

```
Sources/RiichiBots/     library: the Bot protocol and the ladder; depends on Riichi only
Sources/mj/             arena command, drivers, mjai adapter (existing)
agpl/strong/            scripts to build and run Mortal and akochan (AGPL, separate)
```

`RiichiBots` has no Foundation and no I/O, so the ladder also runs in WebAssembly
for the website.

```swift
public protocol Bot: Sendable {
    init(seat: Seat, rules: Rules, seed: UInt64)
    mutating func observe(_ event: MaskedEvent)          // every event, already masked
    mutating func decide(_ view: PlayerView) -> Action   // must return one of view.legalActions
}
```

The existing internal `Player` protocol in `mj` (which the mjai adapter and the
trace player implement) wraps a `Bot`. A `Bot` that returns an action outside
`legalActions` is a bug in the bot: the arena counts it as a substitution, as it
does for outside bots, and the bot's own tests assert it never happens.

Most ladder bots need no memory beyond the view: `PlayerView` already carries ponds,
melds, riichi status, scores and the analysis helpers (`discardOptions`,
`visibleCounts`, `genbutsu`, `suji`). `observe` exists for what the view does not
keep, such as which discards were tsumogiri in order, or what was discarded since a
riichi.

## 3. The ladder

Each level is the level below plus one idea. Parameters are named constants in one
place per bot, not scattered.

| Level | Name | Adds |
|---|---|---|
| 0 | `random` | Uniform over legal actions (exists). |
| 1 | `tsumogiri` / `folder` | Two controls: one discards what it drew and never calls; one always discards the safest tile (genbutsu, then suji, then most copies visible). Neither tries to win except by taking a win offered. |
| 2 | `shanten` | Discards to minimise shanten, ties by most improving tiles unseen. Riichi whenever legal. Always takes a win. Never calls. |
| 3 | `menzen` | Level 2, plus: prefers shapes that keep tanyao and pinfu; counts dora and red fives as value when choosing between equal discards; folds (level 1 `folder` policy) against a riichi when its own hand is two or more away. |
| 4 | `yaku` | From two away, estimates for each candidate discard the yaku it can still reach and a rough hand value, and maximises value × chance instead of raw tile count. Declines riichi on a hand with no realistic win. |
| 5 | `caller` | Level 4 plus calls: pon and chi when the call lowers shanten and the hand keeps a yaku (yakuhai, tanyao, honitsu, toitoi); otherwise stays closed. Kans when safe. |
| D | `digital` | Level 5 with one model throughout: for each action, expected placement-weighted points from an explicit estimate of win chance, win value, deal-in chance against each opponent (from their discards, calls and riichi) and deal-in cost. Push or fold falls out of the numbers instead of a rule. |
| O | `occult` | Level 5 with decisions bent by "flow": recent wins and losses, who is "hot", lucky tiles. A control: it should measurably lose to `digital`, and by how much is the result. |
| S | `mortal`, `akochan` | Outside engines through mjai (section 5). |

How strong each idea makes a bot is an empirical question the arena answers; a
level that does not beat its predecessor is either fixed or removed from the ladder.

## 4. The arena

`mj arena` plays many games between named bots and reports who is better, with
honest error bars.

- **Seating.** A match-up is a multiset of four bots. Each is played over the same
  seeds in every distinct seat arrangement (4 for one-against-three, 6 for
  two-against-two, 24 for four different bots), so luck of the wall and of seat
  order cancels.
- **Seeds.** One base seed gives every game's wall seed and every bot's own seed;
  bot seeds are not derivable from wall seeds. Outside bots get fresh random wall
  seeds per game recorded in the trace, as Phase 3 requires.
- **Parallel.** Games are independent; the arena spreads them over cores and the
  result does not depend on the number of cores.
- **Measures**, per bot: average placement; rank points under the ruleset's uma;
  share of each placement; average final score; and per hand: win rate, deal-in
  rate, riichi rate, call rate, average win value, average deal-in value, tenpai
  rate at exhaustive draws. Also substitutions (illegal, malformed, timeout,
  crashed, unbound) and time per decision.
- **Uncertainty.** Confidence intervals are computed over seed blocks (all seat
  arrangements of one seed are one block), not over individual games, because
  games sharing a wall are correlated.
- **Formats.** One-against-three (the candidate against three copies of a
  baseline) is the standard test for "A beats B"; a round robin over the whole
  ladder gives a rating table (Plackett–Luce fit over placements).
- **Output.** A JSON result file per run (bots, rules, seeds, measures, intervals)
  and optional traces, so any game can be replayed.

**Ladder gate.** Each level against three of the level below, both rulesets: the
95% interval for the difference in average placement excludes zero, in the right
direction.

**A second yardstick: agreement with strong humans.** Using the real game records
(kept outside the repository), for a sample of decisions by top-room players,
does the bot choose the same discard, and the same call-or-pass? This is cheap,
needs no opponent, and gives each level a number comparable with what model cards
report for Mortal-family models ("agreement with Mortal" is a common measure). It
is a rough proxy, reported beside arena results, never instead of them.

## 5. Mortal and akochan

Both are AGPL and both speak mjai. Everything about them lives under `agpl/strong/`
(build scripts, wrappers, a README) and they run as child processes of `mj arena`
through the existing adapter; no engine or bot code links to or copies from them.

- **Mortal.** Build `libriichi` as a Python extension from `../3p/Mortal`, load a
  community checkpoint with `weights_only=True`, and wrap it as an mjai bot
  process. First checkpoint to try: `haor/Mortal-S42` (best documented; includes
  Mahjong Soul training data); then the others, so the arena can rank them. Weights
  are downloaded to the external volume, hashed, and never committed.
- **akochan.** Build from `../3p/akochan`; it speaks the original mjai protocol,
  which is why the engine emits a superset of fields.
- **Rules.** Mortal and akochan assume Tenhou rules. Arena games that include them
  run under `--rules tenhou` by default. Running them under Mahjong Soul rules is
  possible (the event stream is the same) and is a later experiment.
- **What is measured first:** each strong bot one-against-three versus `digital`,
  and Mortal versus akochan, a few thousand games each; throughput on this machine
  (CPU, and Apple GPU if it works); substitution counts, which should be zero.
- **The coverage check** from the roadmap: put the strong bots through the
  directed rare-situation games (`mj selfplay --scenario`) and record what they do
  where the engine knows the right answer exists (a win available, a legal kan
  that changes nothing, an abort available).

## 6. Who does what

| # | Package | Writer | Reviewers |
|---|---|---|---|
| G | `RiichiBots` protocol, levels 0–3, `mj arena` with the measures and intervals | Opus | Codex, Gemini |
| H | Levels 4, 5 and `digital` | Codex | Opus, Gemini |
| I | `agpl/strong/`: Mortal and akochan running through the arena; checkpoint comparison; the coverage check | Gemini | Codex |
| J | `occult`, and the human-agreement yardstick over the real logs | Gemini | Opus |

G first, since H and J build on its protocol and arena. I can start at once: it
needs only the existing mjai adapter.

Gate for leaving Phase 4: the ladder gate holds for every adjacent pair; a rating
table for the whole ladder including the strong bots; zero substitutions from
ladder bots over 100,000 games; council review of the bot code.

## 7. Open questions

1. **Ruleset for the ladder.** Mahjong Soul is the project default, but the strong
   bots are Tenhou-trained. Proposal: the ladder gate runs under both; anything
   involving Mortal or akochan runs under Tenhou rules.
2. **Game length.** Hanchan throughout, or East-only games for faster statistics on
   the lower levels?
3. **How much `digital` should model.** A push/fold model from discards is a
   research area of its own. Proposal: start from published deal-in statistics by
   tile class (genbutsu, suji, one-chance, live) fitted on the real logs, and stop
   there for Phase 4.
4. **Whether `occult` is worth a package** or should be a paragraph of parameters
   on level 5.
5. **Fitting from logs.** Using the real game records to fit constants (deal-in
   rates by tile class, value estimates) is the cheapest way to make levels 4 and
   up sensible. The records stay outside the repository; fitted tables are small
   derived statistics. Is that acceptable for records Tenhou restricts reuse of?
   (Owner's call.)
