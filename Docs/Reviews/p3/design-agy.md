# Phase 3 Engine Design Review (`agy`)

Review of `Docs/Design/engine.md` (draft 1) against `Spec/rules.md`, `Spec/formats.md`, `Sources/mj/`, `Docs/Design/wasm-spike.md`, and Mortal's `libriichi` (`../3p/Mortal/libriichi/src/{mjai,state,arena}`).

---

## Findings

### 1. [blocker] `Wall(seed:kyoku:)` deals the exact same wall on renchan and abortive draws
- **Section:** §3 (Core types — Wall)
- **What is wrong:** `Wall.init(seed: UInt64, kyoku: Int)` keys the shuffle only on `(seed, kyoku)`. Whenever a dealer repeats (dealer win, dealer tenpai, or abortive draw), `kyoku` does not advance — only `honba` increments. Every renchan or abortive draw would therefore replay the identical 136-tile wall.
- **Proposed change:** Seed the wall from `(seed, handIndex)` (a monotonically increasing 0-based counter of dealt hands in the game) or `(seed, kyoku, honba)` (matching `libriichi`'s `Board::init_from_seed`, which hashes `(nonce, key, kyoku, honba)`).

### 2. [blocker] Tenhou kan-dora timing contradicts Tenhou's rules and `libriichi`
- **Section:** §4.2 (Kan dora), §8 (Layer 2), and `Spec/rules.md` §1 (`kan_dora_daiminkan_timing`, `kan_dora_shouminkan_timing`)
- **What is wrong:** `engine.md` §4.2 says open and added kans reveal their kan dora *after the following discard passes*, and `rules.md` §1 lists `after_discard` ("not active if the post-kan discard is Ron'd") for **both** Mahjong Soul and Tenhou. In Tenhou (`tenhou.net/man/` and `libriichi/src/arena/board.rs`), a daiminkan or kakan flips its kan dora **at the moment of the post-kan discard**, before ron resolution — so in mjai `dora` is emitted *before* `dahai`, and a ron on that discard *does* see the new kan dora. Because Layer 2 runs under `--rules tenhou`, defaulting Tenhou to "not revealed on post-kan ron" will produce both rule errors and differential failures on every post-kan discard.
- **Proposed change:** Set `Rules.tenhou`'s kan-dora-on-discard field to `true` (emit `dora` before `dahai`; active on ron of that discard) and keep `Rules.mahjongSoul` at `false` (emit `dora` after `dahai` passes; unverified §5 item 4). Update the Tenhou column of `Spec/rules.md` §1 accordingly. Also specify chained-kan ordering (`daiminkan` → `kakan`): `libriichi` delays the first kan's `dora` until after the `kakan` clears chankan (right before the second replacement `tsumo`), because emitting `dora` between `kakan` and `ron` clears `PlayerState::last_cans`.

### 3. [blocker] §4.1 resolution order allows pon/chi to prevent `suukaikan` (and omits `suukaikan` vs exhaustive-draw priority)
- **Section:** §4.1 (Decision points), §4.2 (Four kans)
- **What is wrong:** §4.1 resolves reactions in order: (1) ron, (2) pon/daiminkan, (3) chi, (4) next draw / exhaustive draw / abortive draw. When two or more seats have declared 4 total kans and the 4th kan's discard enters `.reactions`, putting steps 2–3 before step 4 allows a non-riichi player to call pon or chi on that discard and prevent `suukaikan`. Under both Tenhou and Mahjong Soul rules (`rules.md` §4 item 22), only `ron` can preempt `suukaikan`; if nobody rons, the round aborts immediately. Furthermore, if the 4th kan was declared with 1 live tile remaining, the post-kan discard leaves `wall == 0`: §4.1 does not state whether `suukaikan` takes priority over exhaustive draw (it does in Tenhou/`libriichi` and Mahjong Soul).
- **Proposed change:** In §4.1, check pending `suukaikan` immediately after step 1 (ron) and before steps 2–3 and exhaustive draw. Decide explicitly whether `legalActions` suppresses pon/chi on a pending-suukaikan discard (cleaner for rules) or whether `applying` aborts over them (note: `libriichi`'s `PlayerState` does not suppress `can_pon`/`can_chi` here; see Finding 13).

### 4. [blocker] Setting `haitei` from `wall == 0` illegally combines Haitei + Rinshan
- **Section:** §4.2 (Last tile)
- **What is wrong:** §4.2 states "Haitei and houtei flags are set from the wall count." When a player declares a kan with 1 live tile remaining (`wall == 1`, which is legal), the replacement draw decrements `live_tiles` to `0` (`70 - draws - kans == 0`). Setting `haitei` purely from `wall == 0` would award both `rinshan` and `haitei` on a rinshan tsumo, directly contradicting `rules.md` §4 item 18 ("Haitei Raoyue and Rinshan Kaihou cannot combine"). Note that `houtei` *does* apply to the post-kan discard when `wall == 0`.
- **Proposed change:** Set `haitei` only when `wall == 0` **and** `TurnStart` is `.draw` (never `.replacementDraw`). Keep `houtei` on any discard with `wall == 0`.

### 5. [blocker] `TurnStart.call(Meld)` cannot represent kuikae after chi
- **Section:** §4 (The round state machine)
- **What is wrong:** `TurnStart` is `case call(Meld)`, and `Meld` in `Sources/mj/Tile.swift` only stores `(kind: MeldKind, tiles: [Tile])` — it does not record *which* tile was called (`took`). For a chi (e.g. `456m`), knowing whether `4m`, `5m`, or `6m` was called is required to compute kuikae (`4m`/`7m` vs `5m` vs `6m`/`3m`). `Sources/mj/Legal.swift` already had to carry `case called(Meld, took: Tile)` for this reason.
- **Proposed change:** Change `TurnStart.call` to `case call(Meld, took: Tile)` (or store `calledTile: Tile` and `from: Seat` on `Meld` itself, which also helps `PlayerView` and pao). Also note explicitly that `Action.discard(tile, tsumogiri: true)` is illegal when `after` is `.call`.

### 6. [blocker] `Action.riichi(discard)` omits `tsumogiri` and clashes with mjai's two-step `reach` → `dahai` flow
- **Section:** §4 (The round state machine), §6 (Events, mjai, and the player's view)
- **What is wrong:** Two issues with combining riichi into a single `Action.riichi(discard)`:
  1. It has no `tsumogiri: Bool` flag. If a seat holds `5m` and draws `5m`, discarding `5m` for riichi can be either tedashi (`tsumogiri: false`) or tsumogiri (`tsumogiri: true`). Both mjai and real clients record this distinction.
  2. Standard mjai bots (including Mortal and akochan) do **not** declare riichi and discard in one reply: on `tsumo` they reply `{"type":"reach","actor":A}`, wait for the server to echo `reach`, and then reply with `{"type":"dahai","actor":A,"pai":...,"tsumogiri":...}`. With a single-step `riichi(discard)`, any mjai `Player` adapter must perform a synthetic internal round-trip inside `decide(_:)` and then suppress the duplicate `reach` event when `observe(_:)` is called.
- **Proposed change:** Either (a) mirror mjai directly with `Action.riichi` (no tile) transitioning to a `.turn(seat, after: .riichi)` sub-phase where only tenpai-keeping `discard(tile, tsumogiri)` is legal (this makes `Player` adapters trivial and matches `libriichi` 1-to-1), or (b) add `tsumogiri: Bool` to `Action.riichi(discard, tsumogiri)` and document the mjai adapter's two-step handshake. Option (a) is cleaner.

### 7. [blocker] §4.1 furiten specification misses no-yaku temporary furiten and misstates the losing-call case
- **Section:** §4.1 (Decision points)
- **What is wrong:** §4.1 says: *"A seat that could ron and answers `pass`, or answers with a call that loses to someone else's ron — reviewers please check the second case — becomes furiten (temporary, or permanent if in riichi)."* Three problems:
  1. **Losing to someone else's ron** ends the round immediately, so furiten is moot. The real case is a seat that could ron, instead answers with a **call** (pon/chi/daiminkan) that **loses to another seat's higher-priority call** (e.g. Seat A chooses chi over ron, Seat B wins with pon): the round continues and Seat A must become temporary furiten.
  2. **No-yaku temporary furiten is missing.** Under `rules.md` §4 item 28 (and `libriichi/src/state/update.rs`), if a tenpai seat's winning tile is discarded (or kakan'd) and the seat cannot ron because it has **no yaku**, it still becomes temporary furiten until its next draw/call. Under §4.1 that seat is not even asked (its only option is `pass`), so tying furiten updates only to "seats that could ron and answered" will miss it completely.
  3. **Riichi furiten on self-drawn winning tile:** `rules.md` §4 item 28 requires permanent furiten if a riichi player passes *any* winning tile, discarded or self-drawn. Discarding a self-drawn winning tile already triggers discard furiten, *except* in the rare case where the riichi player **ankans** a self-drawn winning tile that preserves waits (e.g., holding `34555m...` waiting `2m/5m`, drawing `5m`, and declaring `ankan 5m`). That must also set permanent riichi furiten.
- **Proposed change:** Update furiten on **every** discard (and kakan) for all non-discarding seats whose waits include that tile — regardless of whether they had yaku or were asked — whenever the round does not end in ron (and clear temporary furiten on a seat's own next discard/call). Also set riichi furiten if a riichi seat does not `tsumo` when a drawn tile is in its waits (even if it `ankan`s).

### 8. [blocker] `score()` hardcodes Mahjong Soul rules and is not parameterized by `Rules`
- **Section:** §1 (Goal 6), §3 (Core types), §8 (Layer 2)
- **What is wrong:** `engine.md` keeps the existing scoring code unchanged (`Sources/mj/Yaku.swift`, `Sources/mj/Score.swift`) while promising `--rules tenhou` from day one and running Layer 2 differential testing under Tenhou rules. However, `Yaku.swift` hardcodes `:2` (double yakuman) for `kokushi_13`, `suuankou_tanki`, `daisuushii`, and `junsei_chuuren`, and `Score.swift` hardcodes Mahjong Soul's `tenhou` best-tile upgrade (which turns `tenhou` + `kokushi`/`suuankou`/`chuuren` into double yakuman). Under Tenhou rules (`rules.md` §1), all four are 1x.
- **Proposed change:** Thread `Rules` into `score()` (and `legalActions()`), gating at least `naturalDoubleYakuman`, `kiriageMangan`, `kazoeYakuman`, `kuitan`, `doubleWindPairFu`, and `tenhou` stacking/upgrading, while keeping the default `Rules.mahjongSoul` for the existing line-protocol corpus.

### 9. [should-fix] State machine is silent on whether `applying` auto-advances past empty-reaction phases
- **Section:** §4.1 (Decision points)
- **What is wrong:** On most discards and almost all kans, no other seat has a legal action besides `pass`. §4.1 says *"A seat whose only option would be `pass` is not asked at all"* and *"every seat with a non-empty `legalActions` must answer before the state advances"*, but never says whether `applying` automatically advances through `.reactions`/`.robbing` when **zero** seats have non-empty `legalActions` (emitting e.g. `[dahai, reach_accepted, tsumo]` in one call) or pauses in `.reactions` waiting for `applying([:])`. Packages B, D, E, and F are scheduled to start in parallel from this doc; they need this contract pinned down.
- **Proposed change:** Specify that `applying` always advances until either at least one seat has a non-empty `legalActions` or `phase` is `.ended` (matching `libriichi::arena::BoardState::poll`). Document that a single `applying` call can therefore return multiple events (e.g., `[dahai, reach_accepted, tsumo]`, or `[ankan, dora, tsumo]`).

### 10. [should-fix] Game-end checks in §5 have edge-case bugs (W4 renchan, sudden-death renchan priority, tie-break on yame, missing `oka`)
- **Section:** §5 (Game flow)
- **What is wrong:**
  1. **"ends unconditionally after the extension wind's fourth round"**: In both Tenhou (`libriichi/src/arena/game.rs`, `kyoku >= length + 4`) and Mahjong Soul, W4 (or S4 in Tonpuu) **still repeats** on dealer renchan if nobody has reached 30,000 (or on an abortive draw); the game ends unconditionally only when the dealer rotates *past* W4 (would enter North round).
  2. **Sudden-death renchan priority in Tenhou**: Per `tenhou.net/man/#RULE` (and `libriichi/src/arena/game.rs` lines 47–54), during West round sudden death, if someone reaches ≥ 30,000 *and* the dealer has renchan while **not** 1st (possible on double ron or exhaustive draw where both dealer and another seat are tenpai), **renchan takes priority** and the game continues. (Unsure whether Mahjong Soul ranked follows Tenhou here or ends immediately; make it a `Rules` field.)
  3. **Dealer rotation before end checks**: §5 says *"dealer repeat or rotation; honba update; then end checks..."*. Rotating before checking "all-last with dealer win or tenpai" and "last scheduled round finished" is easy to get wrong — specifically, S4 is only "finished" when the dealer does *not* repeat, and abortive draws in All-Last grant renchan but must *not* trigger `agari_yame`/`tenpai_yame`.
  4. **Tie-break for "while first on ≥ 30,000"**: §5 only mentions starting-seat tie-breaking "At game end", not for `agari_yame`/`tenpai_yame`. In S4, the dealer is seat 3 (lowest tie-break priority), so a tie for 1st at ≥ 30,000 is **2nd place** and does not end the game.
  5. **`oka` and `GameResult` omitted**: `rules.md` §1 defines `oka = 20` (30,000 return) for Tenhou and `0` (25,000 return) for Mahjong Soul, but §5 only mentions uma.
- **Proposed change:** Write out the exact post-round state machine in §5: (1) apply deltas; (2) check `tobi` (`< 0`); (3) if abortive draw → `honba += 1`, repeat; (4) check `agari_yame`/`tenpai_yame` using starting-seat tie-break; (5) check sudden-death / scheduled-end (respecting `renchan` priority in Tenhou); (6) rotate or repeat and update `honba`; (7) check `kyoku >= maxRounds` (past W4). Add `oka` and define `GameResult`.

### 11. [should-fix] `first-turn-uninterrupted` cannot be a single table-wide boolean, and `suufon_renda` must yield to `ron`
- **Section:** §4.2 (Double riichi, tenhou, chiihou, kyuushu, four winds)
- **What is wrong:** §4.2 describes these as hanging off *"one flag: 'no call has happened and this seat has not yet discarded'"*. "No call has happened" (including ankan) is table-wide, while "this seat has not yet discarded" is **per-seat** (after East's first discard, East loses first-turn status while South/West/North keep it). Also, `tenhou` is strictly East's initial 14 tiles (cleared even by East's own ankan). Finally, for `suufon_renda`, the 4th identical wind discard can still be **ronned** (e.g., kokushi or tanki wait holding 0 copies of that wind), so `suufon_renda` must be checked *after* `.reactions` (unlike `libriichi`'s `BoardState`, which aborts immediately on `dahai`).
- **Proposed change:** Store a table-wide `anyCallMade: Bool` plus per-seat discard counts (already in ponds), and explicitly state that `suufon_renda` triggers only if the 4th wind discard passes without ron.

### 12. [should-fix] mjai protocol details and masking edge cases are underspecified
- **Section:** §6 (Events, mjai, and the player's view)
- **What is wrong:** Several Mortal/libriichi mjai specifics are missing from §6:
  1. **`none` event**: Omitted from the event list, yet required to parse `pass` responses from mjai bots.
  2. **`start_kyoku.kyoku` is 1-indexed (`1...4`)** while `oya` is 0-indexed (`0...3`), and `kyotaku` is stick count (not points).
  3. **`reach_accepted` before calls**: When a riichi discard is called for `pon`/`chi`/`daiminkan`, `reach_accepted` must be emitted *before* the call event (and ippatsu is immediately cleared by the call).
  4. **`kyuushu` bot action & `ryukyoku` fields**: In Mortal's mjai, a bot declares kyuushu by returning `{"type":"ryukyoku"}` (no `actor`, no `deltas`), and `Event::Ryukyoku` has no `reason` field (so `mj replay` must not require `reason`).
  5. **`hora` fields**: For tsumo, `target == actor`; `deltas` includes `kyotaku * 1000` and honba (excluding the `-1000` already booked at `reach_accepted`); `ura_markers` is `[]` (or omitted) when the winner is not in riichi.
  6. **Masking `start_game.seed`**: If `start_game` carries the RNG seed (as in `libriichi`), `masked(for:)` must strip `seed` so a bot cannot reconstruct the wall.
- **Proposed change:** Add a concise mjai event/field/ordering table to §6 covering these six points.

### 13. [should-fix] Validation Layer 2 has major blind spots if limited to `libriichi::PlayerState`, plus known `libriichi` divergences
- **Section:** §8 (How we will know it is right)
- **What is wrong:** Layer 2 plans to feed self-play logs to `libriichi`'s `PlayerState` and compare legal-action flags and `agari_points`. Reading `libriichi/src/state/` reveals what `PlayerState` **will NOT catch**:
  - **Game flow** (dealer rotation, honba, kyotaku carryover, tobi, agari/tenpai-yame, West round, uma/oka) — `PlayerState` resets on every `start_kyoku`.
  - **Draw & abortive settlement** (`Event::Ryukyoku` is a no-op in `PlayerState`) — exhaustive draw tenpai, tenpai/noten deltas, nagashi mangan, and abortive triggers are completely unchecked.
  - **Multi-ron and pao point distribution** — `agari_points` only returns base `Point`, not `deltas`.
  - **Red-five call choices** (`pon:05m` vs `pon:55m`) and **riichi-eligible discard sets** (before `Event::Reach`, `can_riichi` is only a single `bool`).
  - **Known `libriichi` divergences** that will cause false alarms unless handled in Package E: (a) `BoardState` omits `sanchahou` (triple-ron abort) and does not stack `tenhou`/`chiihou`; (b) `PlayerState` never sets `can_ron_agari` on `Ankan` (no kokushi chankan); (c) `PlayerState` does not suppress `can_pon`/`can_chi` on a pending-suukaikan discard; (d) `BoardState` checks `suufon_renda` before ron reactions.
  - Also, pure uniform-random bots rarely hit 4 kans, 4 riichi, double/triple ron, pao, or nagashi mangan.
- **Proposed change:**
  1. Extend Package E (`AGPL/mj-rs`) to **also** drive `libriichi::arena::BoardState` (initialized with the exact same `Board` wall/haipai/dora/ura/scores) using our self-play actions, comparing `deltas`, `kyotaku`, `can_renchan`, `has_abortive_ryukyoku`, and post-kyoku `scores`!
  2. Add a **biased stress-bot** mode (e.g. always call/kan/riichi/kyuushu when legal, and occasionally pass ron to exercise furiten) alongside uniform random self-play.
  3. Add a **self-replay round-trip** check (`mj selfplay` → `mj replay`) to verify `RiichiMjai` end-to-end.
  4. Document the known `libriichi` divergences in Package E's spec so they are filtered explicitly rather than discovered mid-run.

### 14. [should-fix] `PlayerView`, `Player` protocol, and `mj replay` wall construction have design gaps
- **Section:** §6 (Player view / `Player`), §7 (`mj replay`)
- **What is wrong:**
  1. **`PlayerView` omits essential public state**: §6 lists hand, melds, ponds, scores, dora indicators, tiles left, and legal actions — missing round wind, kyoku number, honba, kyotaku (riichi sticks), dealer/seat wind, each seat's riichi status, own furiten status, and the current reaction trigger (discard/kan being reacted to and by whom).
  2. **`Player` protocol has no error channel**: `observe` and `decide` are non-throwing, so an mjai subprocess adapter cannot cleanly distinguish a crashed/EOF/timed-out bot from an illegal move.
  3. **`mj replay` vs full-wall `RoundState`**: An mjai log does not contain the full 136-tile wall (only haipai, drawn tiles, revealed dora/ura). §3–4 only define `Wall` from a full 136-tile array or RNG seed.
- **Proposed change:** Add the missing public fields to `PlayerView`; allow `Player` methods to `throw` (or return a result distinguishing I/O failure from illegal action); and specify that `mj replay` performs a two-pass per-kyoku reconstruction of a partial `Wall` (filling unrevealed slots with unused tiles) so `RoundState` stays single-mode.

### 15. [should-fix] 500 hanchan/s/core target is at odds with pure-copying `RoundState` and current `Counts` allocations
- **Section:** §1 (Goal 5), §4 (The round state machine)
- **What is wrong:** 500 hanchan/s/core ≈ 325,000 turns/s ≈ **3 µs per turn** (including draw, `legalActions` for 1–4 seats, `PlayerView` construction, and state transition). Currently `Sources/mj/Tile.swift` backs `Counts` with a heap-allocated `[Int]`, `Legal.swift` calls `score()` on every check and allocates `Set`/`Array`s, and `engine.md` §4 proposes `applying(_ decisions: [Seat: Action]) -> (RoundState, [Event])` (allocating a `Dictionary` and potentially triggering CoW copies of `RoundState`'s arrays on every step).
- **Proposed change:** Provide `mutating func apply(...)` as the primary transition (with `applying` as a thin non-mutating wrapper), replace `[Seat: Action]` on the hot path with a stack-friendly representation (e.g. separate `applyTurn(_:)` / `applyReactions(_:)` or a 4-element inline struct), cache per-seat `shanten`/`waits` in `RoundState` so `legalActions` only calls `score()` when a tile completes the hand, and move `Counts` off heap `[Int]` if profiling shows it's hot.

### 16. [suggestion] Store `from: Seat` on `Meld` and define `GameResult` / `Rules` fields before splitting work
- **Section:** §3, §5, §9
- **What is wrong:** `Meld` currently has no `from: Seat` (needed for UI sideways-tile display, `PlayerView` fidelity, and pao attribution), and `GameResult` is not sketched anywhere.
- **Proposed change:** Add `from: Seat?` and `called: Tile?` to `Meld` (optional for `ankan`), and include a concrete `GameResult` struct in Package A so Packages C, D, E, and F share exact types from day one.

---

## Answers to Open Questions (§10)

1. **Real logs:** Yes — Layer 2 (upgraded to diff against both `libriichi`'s `PlayerState` and `BoardState`, plus biased stress bots) + Layer 1 (scenario tests) is sufficient to exit Phase 3. To test against realistic human-like play without Tenhou ToS ambiguity, generate Mortal-vs-Mortal logs locally via `libriichi`'s arena (or export your own Mahjong Soul/Tenhou games) and replay them with `mj replay`.
2. **Asking only seats that can act vs asking every seat:** Keep "ask only seats that can act" in `RoundState`. It matches `libriichi`, avoids wasted work in bot arenas, and every seat still receives every `observe(_:)` event. If a future web UI wants to mask timing tells, add synthetic delays in the UI/server layer.
3. **Simultaneous answers:** Keep simultaneous collection and resolution in the engine — it is deterministic and matches real servers. Timeout handling belongs in the server/UI adapter, substituting `pass`/`tsumogiri`.
4. **Mercury:** Agree with the proposal — do not port the full state machine to Mercury. `libriichi` (especially with `BoardState`) already serves as an independent state machine, and cross-checking `score` and `legal` against Mercury is high value for low cost.
5. **Unverified Mahjong Soul rulings:** Parameterizing each in `Rules` is the right approach, **except** that `kan_dora_on_post_kan_ron` is verified `true` for Tenhou (`tenhou.net/man/`, `libriichi`), so `Rules.tenhou` and `Rules.mahjongSoul` must use different defaults (Finding 2).

---

## Overall Verdict

**Revise before starting parallel implementation (Packages A–F).** The core architecture—Foundation-free `Riichi` + `RiichiMjai`, single `legalActions` source of truth, `PlayerView` information isolation, and differential validation against `libriichi`—is sound and well-scoped. However, there are eight concrete blockers (wall reseeding on renchan, Tenhou kan-dora timing, `suukaikan` resolution priority, `haitei`+`rinshan` collision, missing `took` tile for chi kuikae, missing `tsumogiri` / two-step `reach` mismatch with mjai bots, incomplete furiten rules, and `Rules` not threaded into `score()`) plus key contract gaps around auto-advancement and `BoardState`-level differential testing that are far cheaper to fix in this document than after four parallel work packages diverge.
