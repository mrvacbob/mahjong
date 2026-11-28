# Review of `Docs/Design/bots.md` (draft 1): opus

Read: `Docs/Design/bots.md`, `Docs/Design/engine.md` (§4.4, §5, §6, §6.1),
`Docs/Design/wasm-spike.md`, `Docs/Notes/p3-reallogs.md`, `Sources/Riichi/{View,Analysis,
Action,Seat,Score,Reading,Game,Rules}.swift`, `Sources/mj/{Bots,Driver,MjaiBot,Commands}.swift`,
and, for protocol and build only, `../3p/Mortal/{mortal/mortal.py,mortal/config.py,
libriichi/Cargo.toml,libriichi/build.rs,libriichi/src/mjai/{bot,event}.rs}` and
`../3p/akochan/{main.cpp,mjai_client.*,Makefile_MacOS,ai_src/Makefile_MacOS,setup_mjai.json}`.
I describe what they do and do not quote their code.

Severity counts: 2 blockers, 12 should-fix, 7 suggestions.

---

## Findings

### 1. Blocker. §5: neither Mortal nor akochan speaks the dialect the existing adapter expects

The Phase 3 adapter sends every event and waits for **one reply per event** (`none` when
there is nothing to do). Neither outside engine does that as shipped:

- **Mortal.** `mortal.py` prints a line only when libriichi's `Bot.react` returns a
  reaction. That happens only when libriichi's *own* `PlayerState` decides the seat can
  act. Outside review mode it prints nothing at all for the other events. Through our
  adapter, every `start_kyoku`, other seat's `tsumo`, `dora`, `reach_accepted` and so on
  waits until the timeout and is then counted as a timeout. Since a timeout kills the
  process, the result is "crashed" for the rest of the game. A second problem: Mortal
  decides `can_act` from its own state, not from our prompt. Where the two disagree
  (Mahjong Soul's `riichiOnFifthCopyWait` and `temporaryFuritenEndsOnCall`, the no-yaku
  ron guard), either we prompt and it stays silent, or it answers an event we did not
  prompt (unbound).
- **akochan.** It has two modes. `mjai_client` is a TCP *client* that connects to an
  mjai server (boost::asio). `pipe <tactics> <id>` reads stdin. In pipe mode it replies
  only to its own `tsumo` and to other seats' `dahai`/`kakan`, and each reply is a
  **JSON array** of moves: `reach` with its `dahai`, or `pon`/`chi` with the discard that
  follows. It never answers the `reach` or `pon` event shown back to it, which is where
  our adapter asks for the discard. It also ignores `ankan`, so it cannot rob a closed
  kan with kokushi.

**Change.** Write one dialect shim per engine under `AGPL/strong/`. Each shim runs
the engine in-process (Mortal) or as a pipe (akochan) and speaks our one-reply-per-event
protocol: `none` where the engine is silent, and the second move of an akochan array
buffered and returned at the `reach`/`pon`/`chi` prompt. Also add `can_act` to every
event the adapter sends: `true` exactly on the prompt event, `false` otherwise. Both
engines honour `can_act: false`. It is no leak, because a seat can work out its own
`can_act` for itself. With it, Mortal stops answering unprompted, and akochan stops
running its expensive search on every other seat's discard (see 11). Count disagreements
between Mortal's `can_act` and our prompt as their own measure ("silent at prompt",
"answered unprompted"), separate from substitutions. They are rule divergences, not bot
errors. The §5 claim "akochan speaks the original mjai protocol, which is why the engine
emits a superset" covers the fields but not the conversation, so it should say that too.

### 2. Blocker. §3: levels 3, 4, 5 and `digital` are not specified tightly enough to build or gate

Two writers would build different bots from "prefers shapes that keep tanyao and pinfu",
"rough hand value", "no realistic win", "kans when safe", "the hand keeps a yaku", and
"an explicit estimate of win chance". The order also hides the biggest single gain.
Folding against riichi is worth more than everything else in levels 3–4 combined, but it
is bundled into level 3 with shape preferences. Shape preferences cannot be measured on
their own, and their effect is small (a few hundredths of a placement). Wait quality,
riichi versus damaten, defence against open hands, and placement in the last hands are
missing or implicit. Proposed ladder, each rung one idea and each rule mechanical (all
inputs exist in `PlayerView` today, see 7):

| Level | Name | Precise rule |
|---|---|---|
| 2 | `shanten` | Discard minimising shanten, then maximising `DiscardOption.unseen`, then the fixed tie-break T. Riichi whenever legal (using the discard that level 2 would make after riichi). Always `tsumo`/`ron`. Never calls, never kans, `kyuushu` never. |
| 3 | `defender` | Level 2, plus push/fold. *Threat*: an opponent whose riichi is declared or accepted, or one with ≥ 3 melds, or one with 2 melds of which one is a dora pon or a yakuhai pon. *Fold* when a threat exists and (own shanten ≥ 2, or shanten 1 with `liveTilesLeft` < 40). Once folded, stay folded for the hand unless own shanten reaches 0 with ≥ 4 unseen non-furiten waits. Folding = the `folder` order from 4 against the threats only. |
| 4 | `waits` | Level 3, plus wait quality. At tenpai, choose among the discards of minimum shanten by unseen copies of waits that are not furiten (`own` pond) and that have a yaku (score each wait with `score`: `noYaku` waits count 0 when dama). At 1-shanten, rank by the sum over improving draws of the best resulting tenpai's non-furiten unseen waits ("two-step ukeire"), not raw ukeire. |
| 5 | `value` | Level 4, plus value. The ranking key becomes `unseen × expected han` where expected han counts dora, red fives, yakuhai pairs and triplets, and tanyao/pinfu/iipeikou *only when already structurally true of the best reading*. Riichi versus dama: dama if the dama hand has a yaku and either its ron value is ≥ 8,000 (non-dealer) / 12,000 (dealer), or it is all last and a dama ron takes first. Riichi otherwise. No riichi when every wait is unseen 0 (stay tenpai dama for the noten payment). |
| 6 | `caller` | Level 5, plus calls. Pon a yakuhai (seat, round, dragons) always when shanten does not rise. Other pons and chis only if after the call (a) shanten falls, and (b) the hand satisfies one *yaku-feasibility* check: holds a yakuhai triplet or meld; or every concealed and melded tile is 2–8 (`kuitan` on); or every tile is one suit plus honors with ≤ 2 off-suit tiles; or (pon only) ≥ 4 pairs/triplets. Never call from a fold. Ankan only when it does not lower shanten or ukeire and there is no threat. Never daiminkan or kakan under a threat. |
| D | `digital` | Defined in 3. |

T, the tie-break: keep red fives, then dora, then prefer discarding honors in the order
"guest wind, seat wind, round wind, dragons", then terminals, then 2/8, then the lowest
kind index. Every ladder bot must be deterministic without its RNG (see 13).

The `tsumogiri` and `folder` controls stay. They should be reported, not gated (see 5).

### 3. Should-fix. §3 level D: `digital` needs a formula, not a sentence

Proposed, so Codex and the reviewers build and judge the same thing. For each legal
action `a` (each discard, call then discard, riichi then discard, pass), take the hand
`H_a` and the turns left `t = liveTilesLeft / 4`:

    EV(a) = W(H_a, t) · V(H_a)
          − Σ_s  P_t(s) · R(tile_a, s) · L(s)
          − (1 − W(H_a, t) − Σ_s P_t(s) R(tile_a, s)) · N(H_a, t)

- `W`: win probability from a table fitted by (shanten, two-step ukeire bucket, `t`,
  number of threats). For tenpai, `W` is a function of non-furiten unseen waits and `t`.
- `V`: mean of `score` over the waits, weighted by unseen copies, with riichi and ura
  expectation added if `a` includes riichi.
- `P_t(s)`: opponent `s`'s tenpai probability, 1 for riichi, otherwise a table by
  (turn, melds, tedashi count since the last call).
- `R(tile, s)`: deal-in rate by tile class against a tenpai `s` (genbutsu 0, suji 1/9,
  suji 2/8, suji 3–7, half-suji, non-suji 1/9, non-suji 2/8, non-suji 3–7, honors by
  visible copies 0/1/2/3, one-chance and no-chance adjustments from `visibleCounts`).
  This is the table that open question 3 proposes.
- `L(s)`: expected deal-in cost by (riichi, dealer, melds, visible dora in melds).
- `N`: the exhaustive-draw payment, from own and opponents' tenpai probabilities.

**Placement.** The utility is points before all last. In all last, and in the extension,
apply a utility `U(final scores)`: each outcome's point change maps to the resulting
placement and the ruleset's uma plus oka. This is exact for the last hand if a dealer
repeat is ignored. Elsewhere use a linear blend toward it from S3 (E3 in East-only
games). That gives placement awareness without a game-tree search. Stop there for
Phase 4. No hand reading beyond tile class, and no opponent modelling. Write the
fitted tables as Swift literals generated by a script, each with its source and count.

### 4. Should-fix. §3 level 1: "safest tile" is not defined

Against whom, when nobody is in riichi, and how are classes compared across three
opponents? **Change.** For each kind `k` and opponent `s`, the class index is the order
of `R` in 3: genbutsu 0 … live 3–7 highest. Danger is the maximum over threats of the
class index, or over all opponents if there is no threat. Discard the kind with the least
danger. Break ties by more visible copies, then by T in reverse (keep honors, which go
dead later). Tsumogiri wins ties between equal tiles.

### 5. Should-fix. §3/§4: level 1 has two bots, and the gate's comparison is not defined

"Each level against three of the level below" has no meaning for level 1 (which of the
two?) or for level 2 (against `tsumogiri` or `folder`?). Placement in one-against-three
also needs a definition. **Change.** Gate from `shanten` against `random` upwards. Report
`tsumogiri` and `folder` as controls in the rating table, not as rungs. Define the
statistic as the candidate's mean placement `p̄` minus 2.5 (with three identical copies,
the baseline's mean is `(10 − p̄)/3`, so nothing else carries information). A
level passes when the upper end of the interval is below 0.

### 6. Should-fix. §4: the sample size, the interval and the stopping rule

Mean placement per game has SD √1.25 ≈ 1.118 when the two sides are equal. That is
close to the truth for adjacent levels. For a two-sided 95% test with 80% power,
`n ≈ 7.84 · 1.25 / d² ≈ 9.8 / d²` games:

| true difference `d` | games | 4-seat blocks |
|---|---|---|
| 0.10 | 1,000 | 250 |
| 0.05 | 3,900 | 980 |
| 0.03 | 10,900 | 2,720 |
| 0.02 | 24,500 | 6,130 |
| 0.01 | 98,000 | 24,500 |

My guesses at the gaps: `shanten` versus `random` and `defender` versus `shanten` are
large (≥ 0.3). `waits` versus `defender` and `value` versus `waits` are probably 0.02–0.05.
`caller` and `digital` are about 0.05. So budget **20,000 hanchan (5,000 blocks) per pair
and ruleset**. A real 0.025 then passes with about 80% power. Fix that count in advance.
The design as written lets a writer rerun until the interval clears zero, and tuning
constants on the same seeds the gate uses is the same mistake in slow motion. Use one
seed range for development and a disjoint, held-out base seed for the gate run. If early
stopping is wanted, use a sequential test (SPRT on block means) instead of repeated
peeks.

Seed blocking buys less than §4 implies. Walls are `walls(seed, handIndex)`, so the
four arrangements share hand 0 exactly. After that the score paths diverge, and the same
hand index is a different situation (another dealer after a repeat, different scores).
The gain is mostly in the first hand. **Change.** The interval is a t-interval (or a
bootstrap) over block means, as §4 says. Report the measured design effect: (variance
of block means × 4) / variance of games. If it is near 1, blocking is only seat
balancing. That is still worth doing, but do not count on halving `n`. For mean
placement on a 1–4 scale at n ≥ 1,000 blocks, the normal approximation is fine. Rank
points have heavier tails (busts), so use the bootstrap for them.

Also: name the 12-arrangement format (A, B, C, C), which the round robin will need.
Make the reported numbers independent of core count by summing per-game results in
game-index order after the run, not in completion order. Floating-point sums are not
associative.

### 7. Should-fix. §2: what a bot can and cannot get from `PlayerView` and masked events

I wrote these APIs, so here is the inventory for the levels above:

**Present and sufficient:** own hand, drawn tile, furiten and its parts. Every pond, with
tsumogiri flag, riichi tile, called-away flag and global order. Melds with `taken`/`from`
and `kuikaeForbidden`. Riichi status, scores, sticks, honba, dealer, round, indicators,
`liveTilesLeft`. `genbutsu`, `suji`, `allCopiesSeen`, `visibleCounts`, `unseen`. A
hypothetical call is `discardAnalysis(concealed:meldCount: m+1 …)` on the hand minus the
consumed tiles (the tile counts work out). Hypothetical value is `score(ScoreRequest(hand:
tableMelds:…), rules:)`, which separates `notAgari` from `noYaku`. All last is
`GameFlow.isAllLast(GamePosition(…), rules:)`, public, with `Rules` handed to `init`.

**Missing:**

- **When each call happened.** `TableMeld` has no order. The time can be matched
  through the called `PondTile` (`from`, `taken`, `calledAway`), but not reliably for two
  calls on the same kind, and an added kan has no time at all. `P_t(s)` in 3 needs
  "discards since the last call". Either add `order` to `TableMeld` (the pond order of the
  taken discard, or the global discard count at an ankan or kakan) or make `observe`
  mandatory for this. I prefer the field: `ViewFolder` keeps its "view = fold of events"
  property, and every bot gets it free.
- **Which discards are legal after a call.** The bot can rebuild kuikae from
  `TableMeld.kuikaeForbidden` on a meld it builds, but nobody should need to. Add a pure
  `PlayerView.discardsAfter(_ call: Action) -> [Tile]`.
- **Which discards keep tenpai for riichi.** `legalActions` offers `.riichi` but not the
  discards that may follow it. Fifth-copy waits (`riichiOnFifthCopyWait`) make this
  ruleset-dependent, so a bot's own `shanten == 0` test can disagree with the engine.
  Add `PlayerView.riichiDiscards: [Tile]`.
- **Value per wait.** Every level from 4 up will rebuild the same `WinContext` (seat and
  round wind, riichi, ippatsu, haitei) and loop over waits. One `waitValues(after:
  riichi:)` returning (kind, unseen, furiten, han, fu, ron points, tsumo points) per wait
  keeps that in one tested place. The teaching site will want exactly this view too.

**Not obtainable by design, and fine:** another seat's furiten or hand, the wall, and
whether another seat was asked. A bot needs nothing else.

`observe` is then needed only for tsumogiri patterns beyond the pond (none for these
levels) and for the occult bot's history. Keep it, but say that no ladder level up to D
depends on it.

### 8. Should-fix. §2: protocol details that matter for the wrapper and for WebAssembly

- Say that one `Bot` value lives for exactly one game and one seat, that `observe`
  receives every event of the step before `decide` (as the driver delivers them), and
  that `decide` is called only when `legalActions` is non-empty.
- **WebAssembly:** "no Foundation" also means no `exp`, `log` or `pow`. They come from
  Darwin, Glibc or WASILibc, not the standard library. `digital` will want a logistic or
  two. Either allow `swift-numerics` (RealModule), import the platform C library under
  `#if canImport`, or keep every fitted curve as a lookup table. The table is the best
  choice for determinism too (13).
- **Our bots as mjai processes** (for Mortal's arena, Akagi-style clients, or anyone
  else's server) are not possible with today's API. `ViewFolder` rebuilds the `Table`
  but not `furiten` or `legalActions`, which only `RoundState` computes. Deriving them
  from one seat's events needs the seat's furiten history and the kuikae, haitei and
  riichi-kan rules, all reimplemented outside `RoundState`. Either list this as a non-goal
  for Phase 4 or plan a `SeatTracker` in `Riichi` that folds masked events into a full
  `PlayerView`, legal actions included, and test it against `RoundState.view(of:)` over
  the corpus, the way `ViewFolder` was tested.
- LLM players (Phase 5) are asynchronous, while `Bot.decide` and the driver's `Player`
  are synchronous. Keep `Bot` synchronous, which suits WebAssembly and the arena, and
  state that LLMs come in as `Player`s, like mjai bots, not as `Bot`s.

### 9. Should-fix. §4 seeds: "fresh random wall seeds per game" for outside bots breaks blocking

Phase 3 requires unpublished walls for outside bots. If every *game* gets a fresh seed,
the four arrangements no longer share a wall. **Change.** Use one fresh seed per
*block*, recorded in each game's trace. Derive bot seeds from the base seed through a
one-way function (a keyed hash), not SplitMix. The SplitMix output mix is a bijection,
so a bot that knows how seeds are derived could invert its own seed back to the base
seed and rebuild the walls. In-process bots are our own code, so this guards against
accidents, not adversaries. Still, goal 2 says "by construction", and this costs nothing.

### 10. Should-fix. §5: what goes wrong building and running Mortal on macOS arm64

- **Python version.** pyo3 0.25 in `libriichi/Cargo.toml`. Use the Python 3.12 that
  `environment.yml` pins, in a venv on the external volume, not Homebrew's newest Python.
  `environment.yml` does not list torch: install the macOS arm64 wheel separately.
- **Building the extension.** `cargo build -p libriichi --release` (edition 2024 needs
  Rust ≥ 1.85) produces `target/release/libriichi.dylib`. Python only imports it after
  it is copied as `mortal/libriichi.so`. `build.rs` adds the macOS `-undefined
  dynamic_lookup` link arguments, so plain cargo works. `maturin develop` is the less
  fragile route.
- **Running.** `mortal.py` reads `config.toml` from the working directory, or from
  `MORTAL_CFG` (`[control] state_file` at least). It hard-codes `device = cpu`. It takes
  the seat as `argv[-1]` and ignores `start_game.id`. So the shim from 1 must read the
  seat from `start_game` or be started per seat. With seat rotation, keep a process per
  seat index, not per bot.
- **Start-up cost.** Importing torch and loading a checkpoint takes seconds. If the
  adapter starts a process per game, as the Phase 3 adapter does, start-up will exceed
  play time. The shim should accept several games in a row (libriichi's `Bot` resets on
  `start_game`).
- **Apple GPU.** At batch size 1 per decision, MPS will probably be slower than CPU
  because of kernel-launch latency. Measure it, but plan on CPU with one process per
  core. libriichi's own batched arena is how Mortal reaches high throughput, and it
  plays on libriichi's rules engine, not ours.
- **Checkpoints.** Mortal ships no weights. Community checkpoints differ in model
  `version` (1–4), in `state['config']` layout, and in whether `weights_only=True`
  loads them (one with pickled numpy scalars will not). Record each checkpoint's hash,
  version and `num_blocks`/`conv_channels`. "Includes Mahjong Soul training data" for
  `haor/Mortal-S42` should be checked against its card, not assumed. Mortal decides
  greedily (no Boltzmann sampling) by default, so its play is deterministic up to
  floating point.

### 11. Should-fix. §5: what goes wrong building and running akochan on macOS arm64

- `Makefile_MacOS` (both of them) uses Homebrew `llvm` clang with `-fopenmp` and four
  `-mllvm -polly…` flags. If the installed LLVM has no Polly, delete those flags. They
  are optimisation only.
- `mjai_client.cpp` uses `boost::asio::io_service`, which recent Boost releases have
  removed. The `-lboost_system` link may also fail, since `boost_system` has been
  header-only for years and newer Boost drops the stub library. Pipe mode does not need
  asio, but the Makefile compiles every `*.cpp`. Either pin an older Boost or exclude
  `mjai_client.cpp` and drop `-lboost_system`, in a patch kept under `AGPL/strong/`.
- `libai.so` is linked with `-rpath ./`, and `params/` and the tactics JSON are read
  relative to the working directory. So the child process must run with the akochan
  checkout as its working directory. Set that in the shim, not in the command string.
- Its search is OpenMP across `hw.ncpu` threads per decision. Running games in parallel
  oversubscribes the machine. Set `OMP_NUM_THREADS=1` and parallelise games.
- **Speed.** akochan spends a large fraction of a second up to seconds per decision.
  "A few thousand games" with one akochan seat is then on the order of 100+ CPU-hours,
  and three akochan seats (one-against-three versus akochan) is three times that.
  Measure seconds per decision on 20 games first and size the runs from that.
  `can_act: false` (finding 1) cuts most of the cost, since pipe mode otherwise searches
  on every other seat's discard.
- Its tactics have `jun_pt` [90, 30, −30, −90], which is neither ruleset's uma. Record
  the tactics file used and its hash in the result, the way checkpoints are recorded.

### 12. Should-fix. §4 human-agreement yardstick: meaningful only with controls

It measures resemblance to strong humans, which correlates with strength but is not
strength. Traps, with the fix for each:

- **Forced and trivial decisions inflate it.** Report it over decisions with at least two
  distinct legal kinds, and separately over "contested" decisions, where the top two
  candidates by `digital`'s EV are within a margin.
- **Equivalent tiles.** Treat the same kind as the same choice, except red versus black
  five. Tsumogiri versus discarding the same kind from the hand is one choice.
- **Call-or-pass is ~90% pass.** Accuracy rewards a bot that never calls. Report the
  confusion matrix and balanced accuracy, plus riichi-or-dama separately.
- **Humans play a different objective.** Tenhou's houou room scores 4th place with a
  heavy dan-point penalty, and Mahjong Soul's Throne and Jade rooms do the same. Both
  differ from the arena's uma. A bot that is optimal for the uma will "disagree" more in
  all-last and defensive spots. Report agreement by game phase.
- **Leakage.** If the constants of levels 4+ are fitted on the same records, agreement on
  those records is optimistic. Split by game (or by year) into fit and evaluation sets
  before fitting anything.
- **The "agreement with Mortal" figures in model cards are a different quantity**
  (Mortal as reference, not humans). Do not put the two in one column.
- **Reconstructing the view** from records goes through the Phase 3 converters and the
  engine replay. Record the count of positions skipped (log defects, reduced-format Jade
  hands) so the sample is known.

Also report the baselines: `random` and `shanten` agreement on the same sample.
Without them a number like "62%" means nothing.

### 13. Should-fix. §1 goal 3: determinism has concrete traps in Swift

- `Set` and `Dictionary` iteration order is seeded per process (`Hasher`). A bot that
  breaks ties by iterating a `Set<Kind>` plays different games run to run. Rule: no
  decision may depend on hash-collection order. Iterate `Kind.all` and filter, as
  `genbutsu` does. Test it: play 100 games twice in separate processes and compare the
  traces byte for byte.
- Basic floating-point operations are reproducible, but `exp`/`log` differ between
  Darwin libm and WASILibc. A `digital` built on them can choose differently in the
  browser than in the arena. Use lookup tables or rational approximations written in
  Swift (see 8).
- Outside bots are not reproducible from seeds. A timeout depends on machine load and
  changes the game. State that their games replay only from the trace, and report
  timeouts per core count.

### 14. Should-fix. §1 goal 4: throughput is unmeasured for anything above `random`

14,000 rounds/s per core is uniform random play. A `discardOptions()` call is ≈ (distinct
tiles) × (1 + 34) shanten evaluations, about 350, and a hanchan has ~500 discard
decisions across four seats. So four `shanten` bots spend ~0.1–0.2 s per hanchan per
core. The 12-core machine then does 20,000 hanchan in a few minutes, while the round
robin and `digital` (with a `score` call per wait per candidate) will take hours. That
is fine, but put a per-level target in the design (games/s/core) and a benchmark
command. Cache shanten by `Counts` inside a decision. Two-step ukeire (finding 2, level
4) is the cost driver.

### 15. Suggestion. §3 `occult`: compare it against its own base

"Level 5 bent by flow" should be measured against level 5 (now `caller`), not against
`digital`. Otherwise the result measures `digital`'s model, not the cost of
superstition. See open question 4.

### 16. Suggestion. §4: the rating fit

Plackett–Luce over four-player placements is a reasonable summary, but mahjong is not
transitive. A folder makes the other three's wins cheaper, and a bot can beat three
copies of B while losing at a mixed table. Fit PL on *all* games, one-against-three
included. PL takes any table composition, so a full round robin with Mortal and akochan
in all 24 arrangements is unnecessary. Get PL intervals from a block bootstrap, not the
Fisher information. Publish the one-against-three matrix next to the ratings.

### 17. Suggestion. §2: decisions should be explainable

The teaching site and the LLM benchmark both want to know *why* a bot played a tile.
Add an optional `explain(_ view:) -> [ (Action, score, reason) ]` with a default
implementation that returns empty. `digital` fills it with its EV terms. It costs
nothing in the arena.

### 18. Suggestion. §2: an in-process illegal action should fail the run, not be substituted

Counting substitutions is right for outside bots. For ladder bots, an illegal action
under `mj arena --strict` (the default in tests and the gate) should stop the game with
the view and the action. A substitution hides the bug inside a statistic.

### 19. Suggestion. §6: the gate's "100,000 games with zero substitutions"

Run it with every ladder bot at once (the round-robin games count), under both
rulesets, including the directed scenarios. Rare paths (chankan, four kans, nagashi)
are where a bot hands back something illegal.

### 20. Suggestion. §5 coverage check: score it

For each scenario, write down the action the engine knows is available and the
"right" one where one exists: take the win, decline a pointless kan. Report agreement
counts, not prose.

### 21. Suggestion. §6: package I has one reviewer

The mjai shims (finding 1) touch the adapter Opus wrote. Add Opus as a reviewer of I.

---

## Answers to the open questions

1. **Ruleset.** Agree. The ladder bots are cheap, so run the gate under both rulesets.
   Run anything with Mortal or akochan under Tenhou rules. Add `can_act` divergence
   counts (finding 1) whenever an outside bot plays Mahjong Soul rules.
2. **Game length.** Hanchan for the gate and the rating table: `digital`'s placement
   term, and level 5's all-last dama rule, behave differently in East-only games, and the
   ladder is meant for hanchan opponents. East-only is fine for development runs below
   level 5. Placement SD per game is the same in both, so East-only only buys about 2×
   wall-clock.
3. **How much `digital` models.** Tile-class deal-in rates alone are not enough. Push or
   fold also needs `P_t(s)` (opponent tenpai probability) and `W` (own win probability by
   shanten, ukeire and turns left), plus the all-last placement utility. That is four
   small tables and one exact mapping (finding 3). Stop there: no hand reading or
   opponent modelling in Phase 4.
4. **`occult`.** A paragraph of parameters on level 5, not a package. It is a control.
   Make it a wrapper that perturbs another bot's ranking keys, run one
   one-against-three, and report. Package J then becomes the yardstick alone, which is
   the more useful half.
5. **Fitting from logs.** The owner's call. Technically: keep only aggregate tables
   (counts by class, no game ids, no per-game rows), with the script and the summary of
   the data's source and date range kept outside the repository. Also make every table
   refittable from self-play (`digital` against `digital`, or Mortal games), so the
   bots never *depend* on the restricted records. If the owner says no, self-play tables
   are a usable fallback. They are biased toward the bots' own style, which is an
   acceptable cost for Phase 4.

## Verdict

The structure is right. One protocol on `PlayerView`, an arena with seat rotation and
block intervals, and the AGPL engines kept as child processes are all sound, and the
engine's view API covers nearly everything a ladder bot needs. Two things must change
before work starts:

- **The mjai dialect (1).** As written, package I would spend its first week
  discovering that Mortal is silent between decisions and akochan answers in arrays.
- **The ladder (2, 3).** It needs mechanical definitions and a reordering that puts
  defence and wait quality on their own rungs. Otherwise packages G and H build bots
  that cannot be gated or compared.

The should-fix items (sample sizes and a held-out gate seed, the four small API
additions, seeds per block, the build notes, the yardstick's controls, determinism)
are cheap now. With those in draft 2 I would approve it, and package I can start on
the shims at once.
