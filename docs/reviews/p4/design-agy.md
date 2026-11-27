# Phase 4 design review (`agy`)

Target: `docs/design/bots.md` (draft 1).  
Context checked: `docs/design/engine.md` (§4–§6.1), `Sources/Riichi/View.swift`, `Sources/Riichi/Analysis.swift`, `Sources/RiichiMjai/Mjai.swift`, `Sources/mj/Bots.swift`, `Sources/mj/Driver.swift`, `Sources/mj/MjaiBot.swift`, `Sources/mj/Commands.swift`, `../3p/Mortal/mortal/mortal.py`, `../3p/Mortal/libriichi/src/mjai/{bot,event}.rs`, `../3p/akochan/{main.cpp,Makefile_Linux,ai_src/Makefile_Linux}`.

---

## Findings

### 1. [blocker] §4 — Seed blocking contradicts "fresh random wall seeds per game" for outside bots

**What is wrong:** §4 states both that every match-up is played "over the same seeds in every distinct seat arrangement … so luck of the wall and of seat order cancels" and that "Outside bots get fresh random wall seeds per game recorded in the trace, as Phase 3 requires." If each game gets a distinct random wall seed, seat-rotated games do not share a wall and seed blocking does not exist for outside bots (Mortal, akochan, LLMs).

**Proposed change:** Clarify the two regimes explicitly:
- For **outside bots** that run as fresh stateless child processes per game (Mortal, akochan), draw one fresh 64-bit random seed from the OS per **seed block** (not sequentially from `--seed 0`) and reuse it across the 4/6/24 seat arrangements of that block, recording each game's seed only in its trace. That prevents wall-seed prediction while preserving variance reduction from blocking.
- For **untrusted/stateful remote bots** (Phase 5 LLMs or networked agents that could remember walls across games), add an `--unblocked` mode (1 game = 1 block, fresh random seed per game, seat cycled deterministically or randomly) and compute CIs over individual games.

---

### 2. [blocker] §5 — Protocol and CLI mismatches for Mortal, akochan, and the `--scenario` coverage check

**What is wrong:** §5 implies Mortal and akochan can be wrapped lightly around their existing CLIs and run through `mj selfplay --scenario`. Inspecting the actual code reveals three concrete blockers:
1. **Mortal (`3p/Mortal/mortal/mortal.py`):** `mortal.py` takes `<ID>` on the command line (not from `start_game.id`), prints *nothing* when `bot.react(line)` returns `None` (whereas `MjaiBot.swift` strictly reads one JSON line per sent event and requires `{"type":"none"}`), and `libriichi::mjai::Event` does not have an `"end"` variant (which `MjaiBot.finish()` sends as `{"type":"end"}`). Also, community inference-only checkpoints like `haor/Mortal-S42` may omit `mortal.py`'s expected `state['config']`/`state['timestamp']` keys.
2. **akochan (`3p/akochan/main.cpp`):** Neither `mjai_client` nor `pipe` speaks our stdin/stdout 1-for-1 mjai dialect:
   - `mjai_client` speaks TCP, expects `hello`/`join`, logs debug text to stdout, and crucially only evaluates calls on opponent discards when `recv["possible_actions"]` is non-empty (`main.cpp:330`). Our engine (`Sources/RiichiMjai/Mjai.swift`) does **not** emit `possible_actions`, so `akochan` in `mjai_client` mode would never chi, pon, or ron.
   - `pipe` mode reads stdin, only replies on own `tsumo` and opponent `dahai`/`kakan`, outputs a JSON array of ranked moves from `ai_review` (not a single mjai action), and does not handle two-step `reach`/`pon`/`chi` follow-up discards.
   - On macOS arm64, `3p/akochan/ai_src/Makefile_Linux` also fails out of the box (`grep -c ^processor /proc/cpuinfo`, `-mcmodel=medium`, Apple Clang `-fopenmp`, Boost paths, `libai.so` naming), and `akochan` spawns OpenMP threads internally (which will oversubscribe cores under parallel `mj arena` unless `OMP_NUM_THREADS=1`).
3. **Coverage check (`mj selfplay --scenario`):** `Sources/mj/Commands.swift:123` explicitly rejects any non-`directed` bot when `--scenario` is passed (`"--scenario plays directed bots at every seat"`). Even if relaxed to allow one external seat, the directed bots' choreography can break if the external bot deviates before the target rare state.

**Proposed change:**
- Document the exact wrapper requirements in §5:
  - `agpl/strong/mortal_bot.py` must parse `start_game.id`, instantiate `libriichi.mjai.Bot` lazily, emit `{"type":"none"}` whenever `bot.react` returns `None`, and exit cleanly on `{"type":"end"}` / `end_game`.
  - `agpl/strong/akochan_bot` must either drive `pipe` mode (translating ranked move lists and caching the second step of two-step `reach`/`pon`/`chi` responses, while emitting `{"type":"none"}` on non-prompt events) or inject `possible_actions` into a stdin-bridged wrapper, and pin `OMP_NUM_THREADS=1`.
- Replace the `--scenario` coverage check design with a **single-position / replay-to-prompt** check (feed the masked event prefix of each rare scenario up to the target decision point to the bot and assert its reply is legal and sane), or explicitly add a `--scenario` + `--seat N=BOT` mode where `Commands.swift` allows one tested seat.

---

### 3. [blocker] §3 — Levels 3, 4, 5, and `digital` are underspecified; two writers would build different bots

**What is wrong:** Levels 0–2 are mostly clear, but Levels 3–5 and `digital` read as aspirations rather than specifications:
- **Level 1 (`tsumogiri` / `folder`)** puts two different bots on one rung, making "level N against three of level N−1" ambiguous for both 1 vs 0 and 2 vs 1. `folder` also omits how it ranks tiles when *no* opponent is threatening or when *multiple* opponents are in riichi.
- **Level 2 (`shanten`)** omits `kyuushu` (nine terminals), `ankan`/`kakan`, furiten waits, and red-5 vs plain-5 tie-breaking (both have identical shanten and `unseen` in `discardOptions()`).
- **Level 3 (`menzen`)** does not specify whether tanyao/pinfu/dora only break ties or can trade away ukeire (and at what exchange rate), nor how "shapes that keep tanyao and pinfu" are scored at 2–3 shanten.
- **Level 4 (`yaku`)** does not define how win chance is computed at shanten 2 (full 2-ply search is expensive and unspecified), how hand value is estimated before tenpai, or what "no realistic win" means for declining riichi. It also ignores the other half of riichi-vs-damaten (declining riichi on an already high-value yaku hand).
- **Level 5 (`caller`)** says "pon and chi when the call lowers shanten and the hand keeps a yaku" — calling unconditionally whenever shanten drops will routinely destroy high-value closed hands (e.g., breaking a 1-shanten menzen pinfu/dora hand into a 1,000-pt open tanyao with no defence) and can easily make Level 5 *weaker* than Level 4! "Kans when safe" is also undefined.
- **Level D (`digital`)** jumps three concepts at once over Level 5 (continuous push/fold EV, defence against open hands, and placement-weighted endgame utility) without specifying the EV formula, open-hand tenpai/deal-in model, or placement-utility function.

**Proposed change:** Give each rung a concrete, implementable contract:
- **Level 1:** Make `tsumogiri` Level 1 (the ladder rung) and `folder` a named side control (not a rung). Define `folder`'s per-tile danger score against a threat set $T$ (all riichi seats; if none, all other seats) as $\max_{s \in T} \text{danger}(t, s)$ with explicit total order: genbutsu < 4th-copy honor/terminal < suji 1/9 < suji 2/8 < suji 3/7 < suji 4/5/6 < non-suji outer < non-suji inner, tie-broken by most visible copies then canonical kind.
- **Level 2 (`shanten`):** Minimise `shanten`, then maximise `unseen` improving tiles; never call (`chi`/`pon`/`daiminkan`), never `ankan`/`kakan`, never `kyuushu`; always `tsumo`/`ron`; always `riichi` when legal; tie-break by keeping red fives, then discarding isolated honors/terminals before middle tiles.
- **Level 3 (`menzen`):** Same discard search as Level 2, but score each candidate discard with a weighted sum `score = -W_shanten * shanten + unseen + W_dora * keptDora + W_tanyao * tanyaoBonus + W_pinfu * pinfuBonus` (with named constants so a small ukeire loss can keep dora/tanyao/pinfu, e.g. 1 dora ≈ 2–3 unseen tiles). Fold (`folder` policy against all riichi seats) when any opponent is in riichi and own `shanten >= 2` (or `shanten == 1` with `unseen <= 4` and `liveTilesLeft < 24`).
- **Level 4 (`yaku`):**
  - At `shanten >= 3`: Level 3 policy.
  - At `shanten == 0` (tenpai): score each candidate discard using `ScoreRequest` on each unseen wait kind (exact value for tsumo/ron) × win probability $p_{\text{win}}(\text{unseenWaits}, \text{liveTilesLeft}, \text{furiten})$. Compare riichi EV (adding riichi + expected ippatsu/ura, minus 1,000 stick and loss of defence) vs damaten EV (only if hand has a yaku without riichi; decline riichi if damaten EV > riichi EV, OR if `unseenWaits == 0` / furiten with `unseenWaits <= 1` late).
  - At `shanten == 1` (iishanten): 1-step lookahead over improving draws (sum over improving kind $k$ of `unseen(k)` × best resulting tenpai value/wait score).
  - At `shanten == 2`: fast heuristic hand-value estimate (dora + yakuhai/tanyao/pinfu/honitsu/chitoi potential) × `unseen` improving tiles, avoiding full 2-ply combinatorial explosion.
- **Level 5 (`caller`):** Evaluate calling (`pon`/`chi`) only if the post-call hand has an open yaku (yakuhai, tanyao, honitsu/chinitsu, toitoi, or at least 2 dora + guaranteed yaku) **and** `openEV(afterCall) > closedEV(pass)` using Level 4's evaluator (with a speed multiplier for lowering shanten by 1). Never `daiminkan`; `ankan`/`kakan` only when `shanten <= 1`, no opponent is in riichi, and (for `kakan`) the tile is not live against a threatening open hand. Add basic open-hand folding: treat an opponent with $\ge 2$ open melds showing dora/honitsu as a threat when own `shanten >= 2`.
- **Level D (`digital`):** Specify the exact decision equation:
  $$\text{EV}(a) = \Delta U_{\text{win}} \cdot P(\text{win} \mid a) - \sum_{s \neq \text{me}} \Delta U_{\text{deal-in}}(s) \cdot P(\text{deal-in to } s \mid a) + \Delta U_{\text{draw}} \cdot P(\text{draw} \mid a)$$
  where:
  - $P(\text{deal-in to } s \mid a) = P(\text{tenpai}(s)) \cdot P(\text{tile hits } s \mid \text{tenpai}, \text{tile class})$ using a small table by tile class (genbutsu, 4th-copy, one-chance/kabe, suji, non-suji, honor/terminal/middle) and opponent state (riichi turn, or open meld count $\ge 1$ + dora/honitsu cues).
  - $\Delta U$ maps point deltas to placement-weighted value: in East 1–South 2 use linear point value; in South 3–All Last (or East 3–4 in East-only) convert final-score outcomes to expected rank points (uma + placement) using the current score gap to the seats above/below.

---

### 4. [should-fix] §3 — `occult` built on Level 5 cannot be validated by comparing it to `digital`

**What is wrong:** §3 defines `occult` as "Level 5 with decisions bent by 'flow' … A control: it should measurably lose to `digital`, and by how much is the result." Because Level 5 is already weaker than `digital`, `occult` losing to `digital` confounds two effects (Level 5 vs `digital`, plus the flow bias).

**Proposed change:** Compare `occult` directly against its own unmodified base — either build `occult` on `digital` (and measure `occult` vs `digital`), or keep it on Level 5 and measure `occult` vs Level 5. That isolates the exact cost of "flow" biases.

---

### 5. [should-fix] §4 — Statistics, interval method, sample sizes, and Plackett–Luce edge cases are unspecified

**What is wrong:** §4 states "Confidence intervals are computed over seed blocks" and "Plackett–Luce fit over placements" without specifying the estimator, handling of 1v3 correlation, sample sizes, or failure modes:
1. **Correlated placement difference in 1v3:** In a 1v3 match-up (candidate $A$ vs three copies of $B$), $\bar{r}_A + 3\bar{r}_B = 10$, so $\bar{r}_A - \bar{r}_B = \frac{4}{3}(\bar{r}_A - 2.5)$ with correlation $\rho = -1$. Treating $\bar{r}_A$ and $\bar{r}_B$ as two independent samples would compute the wrong standard error.
2. **No sample-size guidance:** The design does not say how many games are needed to resolve realistic gaps, risking underpowered runs (especially for Mortal vs akochan and checkpoint comparisons). For hanchan placement ($R \in \{1,2,3,4\}$, $\sigma = \sqrt{1.25} \approx 1.118$ per game before ~10–30% blocking variance reduction), 80% power for a 95% CI to exclude 0 requires roughly $N \approx 8\text{–}10 / \Delta^2$ total games:
   - $\Delta = 0.20$ (large gap, lower ladder): ~250 games (~65 blocks of 4).
   - $\Delta = 0.10$ (moderate gap, mid ladder): ~1,000 games (250 blocks).
   - $\Delta = 0.05$ (small gap, upper ladder / `digital` vs `caller`): ~4,000 games (1,000 blocks).
   - $\Delta = 0.02$ (fine gap, two strong Mortal checkpoints): ~25,000 games (~6,250 blocks).
   "A few thousand games" in §5 is enough for Mortal vs `digital` and borderline for Mortal vs `akochan` ($\Delta \approx 0.06\text{–}0.08$), but **not** enough to reliably rank close Mortal checkpoints.
3. **Plackett–Luce combinatorial explosion and separation:** A full 4-bot round robin over 10 bots is $\binom{10}{4} \times 24 = 5,040$ games *per seed*. Worse, if `mortal` never finishes behind `random`, unregularized MLE Plackett–Luce diverges to $\pm\infty$.
4. **Confounders / false positives:** Peeking (stopping as soon as the CI excludes 0), multiple testing across 6+ pairs × 2 rulesets, partial blocks (seat-0 tie-break bias), and CPU-load-induced timeouts on external bots can all create spurious differences.

**Proposed change:**
- Specify the exact interval method: compute the paired difference $d_b = \bar{r}_{A,b} - \bar{r}_{B,b}$ **within each complete seed block $b = 1\dots B$** (in 1v3, $d_b = \frac{4}{3}(\bar{r}_{A,b} - 2.5)$), then compute a one-sample Student-$t$ (or BCa block-bootstrap) 95% CI over $d_1 \dots d_B$. Require pre-registered block counts $B$ per gate (no peeking) and drop no partial blocks.
- Fit **L2-regularized (MAP) Plackett–Luce** (weak Gaussian prior on $\log \theta$, e.g. $\sigma_{\text{prior}} = 3$) over the union of 1v3 ladder matches plus overlapping 4-bot tables (e.g. adjacent-tier quads) rather than all $\binom{K}{4}$ combinations, with block-bootstrap CIs on ratings. Never mix East-only and hanchan games in one PL fit.
- Treat any non-zero timeout/crashed substitution count on an external bot as an invalid benchmark run (or report separately) so host CPU load cannot masquerade as weaker play.

---

### 6. [should-fix] §2 — `Bot` protocol vs `PlayerView` gaps and factual error on what `PlayerView` keeps

**What is wrong:**
1. **Factual error in §2 (lines 54–56):** The doc says "`observe` exists for what the view does not keep, such as which discards were tsumogiri in order, or what was discarded since a riichi." In fact, `PlayerView.Table.ponds` (`[[PondTile]]` in `View.swift:87`) *already* stores `tsumogiri`, `riichi`, `calledAway`, and `order` for every discard!
2. **Real gaps in `PlayerView`:** What `PlayerView` actually omits — and what Levels 4, 5, and `digital` need — are:
   - `ippatsu` active flags per seat, `doubleRiichi` flags, `isRinshan` (whether the current draw is a replacement draw), and `anyCallMade` (first go-around). Without these, every bot that calls `ScoreRequest` or estimates riichi value must duplicate `ViewFolder`'s state machine in `observe`.
   - **Meld timing** (the pond `order` at which each `TableMeld` was made), needed by `digital` to distinguish discards made *before* vs *after* an opponent's open call.
   - `Bot.init(seat:rules:seed:)` forces a fixed initializer signature on the protocol, which makes parameterized bots (e.g., testing two constant sets for `digital`, or `occult` parameters) awkward.

**Proposed change:**
- Correct the §2 rationale for `observe` (it is needed for cross-hand history such as `occult`'s "flow", and for opponent call/meld timing if not added to `PlayerView`).
- Consider adding `ippatsu: [Bool]`, `isRinshan: Bool`, and `meldOrder` (or keeping `ippatsu`/`isRinshan` in a small `RiichiBots` state tracker shared by Levels 4–D so `Sources/Riichi` stays minimal).
- Remove `init(seat:rules:seed:)` from `protocol Bot` (or keep it in a `DefaultBot` refinement) and have `mj arena` accept bot factories `(Seat, Rules, UInt64) -> any Bot`.

---

### 7. [should-fix] §4 — Human-agreement yardstick traps are unaddressed

**What is wrong:** §4 describes the human-agreement yardstick as "does the bot choose the same discard, and the same call-or-pass?" without guarding against its major traps:
1. **Action-class imbalance:** In riichi logs, ~80%+ of call windows are `pass`. A bot that *never* calls (`shanten`, `menzen`) will score >85% raw call-or-pass agreement! Similarly, forced discards (riichi auto-tsumogiri, 1 legal action) inflate discard agreement.
2. **In-sample leakage:** If §7 Q5 fits `digital`'s tables from the real logs, measuring agreement on the same logs is invalid.
3. **Rule mismatch:** Evaluating a Mahjong-Soul-configured bot on Tenhou Phoenix logs (or vice versa) creates artificial disagreements.

**Proposed change:** Specify the yardstick protocol in §4:
- Exclude forced single-action turns (riichi tsumogiri).
- Report **stratified** metrics: (a) non-forced discard top-1 agreement, (b) call windows split into recall on human calls and precision/false-positive rate on human passes (or F1 / balanced accuracy), and (c) push/fold agreement when facing a riichi.
- Partition the external logs into a fixed **fit split** and **holdout eval split** (by game date/ID) before any parameter fitting, and match the bot's `Rules` to the log's platform.

---

### 8. [should-fix] §1, §4 — Determinism hazards in Swift (`Set`/`Dictionary` hashing) and parallel arena seeding

**What is wrong:**
1. Swift's `Set` and `Dictionary` use randomized per-process hash seeds. Any bot in `RiichiBots` that iterates a `Set<Kind>` or `[Tile: Double]` to break ties or pick among equal-scoring actions will silently break §1 goal 3 ("Deterministic: a bot's choices are a function of what it has seen and its own seed").
2. §4 requires parallel arena results not to depend on core count, but does not specify how per-game and per-bot seeds are derived or how results are reduced. Using a shared mutable RNG across worker tasks would break core-count independence.

**Proposed change:**
- Add an explicit `RiichiBots` rule: never depend on `Set`/`Dictionary` iteration order; iterate `Kind.all` or `view.legalActions` in canonical order, and add a unit test that runs each bot twice in separate processes (different Swift hash seeds) and asserts byte-identical traces.
- In `mj arena`, derive `wallSeed = mix(baseSeed, blockIndex)` and `botSeed = mix(baseSeed, blockIndex, arrangementIndex, seat)` purely from indices (never from a shared RNG), and reduce statistics in canonical `(blockIndex, arrangementIndex)` order.

---

### 9. [suggestion] §2 — `RiichiBots` WASM portability and floating-point tie-breaking

**What is wrong:** `RiichiBots` targets WebAssembly as well as native arm64. Floating-point FMA/rounding differences across targets can flip exact ties in Levels 4–D, causing native and WASM replays of the same seed to diverge slightly.

**Proposed change:** Use integer arithmetic where practical (Levels 0–3 can be 100% integer), and in Levels 4–D treat scores within a small epsilon (e.g. `1e-9`) as tied before applying a deterministic canonical tie-breaker.

---

### 10. [suggestion] §5 — Mention `libriichi` vs engine Tenhou-rule micro-differences

**What is wrong:** §5 assumes Mortal under `--rules tenhou` will have zero substitutions automatically. However, `docs/design/engine.md` §4.2 already documents subtle differences between our engine's Tenhou rules and `libriichi`'s `PlayerState` (for example, `fourWindsRiichiStickPaid`: our engine accepts the riichi stick before aborting, while `libriichi` aborts first). If any rare event causes `libriichi`'s internal `PlayerState` to disagree on `cans.can_act()`, Mortal will emit either an `unbound` reply or `none` on a required decision.

**Proposed change:** Note these known edge cases in §5 and verify them explicitly during the coverage/smoke tests so any single substitution is diagnosed immediately as a dialect edge case rather than a wrapper bug.

---

## Answers to §7 Open Questions

1. **Ruleset for the ladder:** Agree with the proposal. Run the ladder gate under both `mahjongsoul` and `tenhou`; run Mortal and akochan under `tenhou` by default (with `mahjongsoul` as a clearly labeled later experiment, checking for zero substitutions first).
2. **Game length:** **Hanchan** for the official ladder gate, `digital` tuning, and all strong-bot benchmarks — East-only distorts endgame push/fold and placement dynamics (South-round score dispersion is central to `digital` and Mortal, which are trained on hanchan). Allow `--length east` as an optional fast smoke-test flag during development of Levels 0–3, never as a substitute for the hanchan gate.
3. **How much `digital` should model:** Agree with the proposal — stop at a clean, explicit push/fold EV model using deal-in rates by tile class (genbutsu, 4th-copy, one-chance/kabe, suji, non-suji, honor/terminal/middle) + simple open-hand threat model + South-3/All-Last placement utility. That is already a strong, interpretable ceiling for a hand-written bot and a great teaching-site opponent.
4. **Whether `occult` is worth a package:** Not a standalone package of its own, but fine bundled in Package J alongside the human-agreement yardstick (as §6 already does). Implement it as a thin parameter/wrapper layer over `digital` (not Level 5 — see Finding 4) so it stays small and scientifically clean.
5. **Fitting from logs:** Technically sound and far better than guessing magic numbers, **provided** (a) the owner approves the ToS posture (small aggregated summary tables like deal-in rates by tile class are non-invertible statistics, not redistributed logs), and (b) a strict train/eval split is enforced so the human-agreement yardstick is never evaluated in-sample.

---

## Verdict

**Revise before implementing.** The architecture (`RiichiBots` pure library, `mj arena` with seed-blocked seat rotation, `agpl/strong/` isolation) is right, and Package I's first step (getting Mortal running via `mj selfplay`) can proceed immediately. Before Packages G and H commit to code, resolve the three blockers: (1) reconcile seed blocking with random seeds for outside bots, (2) specify the concrete `mortal`/`akochan` wrapper and coverage-check mechanics, and (3) tighten Levels 3–5 and `digital` from hand-waving into implementable specs (plus fix the `occult` baseline and 1v3 CI formula).
