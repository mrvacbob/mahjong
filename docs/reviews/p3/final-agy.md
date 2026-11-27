# Phase 3 Final Review — agy

Reviewer: `agy`
Scope: `Sources/`, `Tests/`, `docs/design/engine.md`, `spec/rules.md`, `spec/formats.md`, `spec/wall.md` at HEAD.
Reproductions: `docs/reviews/p3/final-agy-repro/`.

---

## Executive Summary

The core rules engine (`Riichi`) is remarkably solid: no core mahjong-rule or scoring bugs were found in composite pao, double yakuman combinations, kokushi robbing a closed kan, chained-kan dora, or `ViewFolder`. The architecture (value-type `RoundState`/`GameState`, zero Foundation in `Riichi`/`RiichiMjai`, strict `MaskedEvent`/`PlayerView` separation, deterministic ordering) is clean and well suited for bots, benchmarks, and WebAssembly.

However, this review found **0 blockers** and **7 should-fix issues** (plus 2 suggestions), including:
- Two reproducible **precondition crashes** in `parseTiles` and `Counts.init` reachable from the `mj` line protocol (`spec/formats.md`: "never a crash").
- Wrong `honba` calculation in `RoundState.winRequest(for:)` (affects multi-ron passes and `honbaToEveryRonWinner`).
- Incomplete validation in `Mjai.action` (accepts bogus `hora` target/pai and impossible red-five counts in `ankan`/`daiminkan`) and missing `target`/`pai` in `Mjai.reply`.
- Orphan grandchild process leak in `ChildProcess.stop()` when a misbehaving bot ignores `SIGTERM` behind `/bin/sh`, plus missing `deinit`.
- Stale `disputedScenarios` entry in `ScenarioTests.swift`, a no-op test in `RulesFieldScenarioTests`, and contradictory documentation drift across `docs/design/engine.md`, `spec/rules.md`, and `Rules.swift`.

---

## Findings

### Finding 1 — `should-fix`: Precondition crashes in `parseTiles` and `Counts.init` reachable from `mj` line protocol

- **Files & lines:**
  - `Sources/Riichi/Tile.swift:127, 135` (`parseTiles`)
  - `Sources/Riichi/Tile.swift:183-195` (`Counts.init` / `subscript`)
  - `Sources/mj/main.swift:67` (`Request.hand(plus:)`)
- **What happens:**
  1. `parseTiles` uses `ch.wholeNumberValue`, which in Swift accepts non-ASCII Unicode numeric characters with values `> 9` (such as `⑽` `U+247D` = 10, `Ⅻ` = 12). When followed by a suit letter (`m`/`p`/`s`), `d != 0` falls through to `Kind(suit, d)` and traps `precondition((1...suit.size).contains(number))`.
  2. `Request.hand(plus:)` validates tile multiplicity by constructing `Counts(all)` and checking `count(where: { $0 > 4 }) == 0`. Because `Counts` packs each kind into a 4-bit nibble (`0...15`), passing 16+ copies of one kind (e.g., `hand=1111111111111111m`) traps `precondition((0...15).contains(newValue))` inside `Counts.init` before the `> 4` check runs.
  Both violate `spec/formats.md` ("A request it cannot handle gets `<id> error=<reason>`, never a crash") and affect any LLM tool server or WASM caller passing untrusted mpsz strings to `parseTiles` or `Counts`.
- **Reproduction:** **Reproduced** via `docs/reviews/p3/final-agy-repro/repro_crashes.py`:
  - `1 shanten hand=⑽m` → exit `-5` (`SIGTRAP`), `Riichi/Tile.swift:32: Precondition failed: kind number out of range for its suit`.
  - `1 shanten hand=1111111111111111m` → exit `-5` (`SIGTRAP`), `Riichi/Tile.swift:191: Precondition failed: count out of range`.
- **Proposed fix:**
  - In `parseTiles`, accept only ASCII `'0'..."9"` (checking `ch.asciiValue`).
  - In `Request.hand(plus:)`, check per-kind counts in a `[Int](repeating: 0, count: Kind.count)` (or reject `all.count > 18`) before constructing `Counts(all)`. Optionally add a failable `Counts(validating:)` or document `Counts.init`'s max-15 precondition clearly.

---

### Finding 2 — `should-fix`: `RoundState.winRequest(for:)` returns wrong `honba` on multi-ron pass and ignores `honbaToEveryRonWinner`

- **File & lines:** `Sources/Riichi/Round.swift:702-715` (used by `Sources/mj/CrossCheck.swift:29`)
- **What happens:**
  In `.reactions` and `.robbing`, `winRequest(for: seat)` computes `first` as the closest seat in turn order that *could* ron (`legalActions(for: $0).contains(.ron)`), and unconditionally passes `honba: first == seat ? honba : 0`:
  1. When `rules.honbaToEveryRonWinner == true`, a second ronner still gets `honba: 0` instead of `honba`.
  2. Even under default rules (`honbaToEveryRonWinner == false`), if seat 1 and seat 2 can both ron seat 0's discard with `honba > 0`, and seat 1 passes while seat 2 rons, `settle()` pays seat 2 the honba (`winners[0]`), whereas `winRequest(for: Seat(2))` reported `honba: 0`. In `CrossCheck.swift`, `deciding` calls `winRequest(for:)` before resolving the window, so the Mercury cross-check dump records `honba=0` even when seat 2 won with honba.
- **Reproduction:** **Reproduced** via `docs/reviews/p3/final-agy-repro/repro_swift.swift`:
  - `[Finding 2a] honbaToEveryRonWinner=true, seat 2 winRequest.honba = 0 (expected 2)`
  - `[Finding 2b] seat 1 passes, seat 2 rons: winRequest.honba = 0, actual seat 2 delta = 2600 (includes 600 honba)`
- **Proposed fix:**
  - Respect `rules.honbaToEveryRonWinner` in `winRequest(for:)`.
  - Add a `honba: Int? = nil` override (or a `winRequests(for answers: Answers)` helper) so `CrossCheck.swift` can dump score requests in `resolving(_:answers:)` using the *actual* ron winners rather than hypothetical ones.

---

### Finding 3 — `should-fix`: `Mjai.action` fails to validate `hora` target/pai, red-five multiplicity in `ankan`/`daiminkan`, and `kakan` consumed tiles

- **Files & lines:**
  - `Sources/RiichiMjai/Mjai.swift:316-352` (`Mjai.action`)
  - `Sources/mj/MjaiBot.swift:151` (`MjaiBot.receive`)
- **What happens:**
  1. `Mjai.action` only checks `offered` (`pai` and `target`) for `pon`, `chi`, and `daiminkan`. On `"hora"`, a misbehaving bot can send a wrong `target` or wrong `pai` (e.g., `{"type":"hora","actor":0,"target":3,"pai":"9p"}` when seat 1 discarded `4s`), and `Mjai.action` accepts it as `.ron` instead of rejecting it as `.illegal`.
  2. `MjaiBot.swift:151` only populates `offered` for `.discard(let d)` and passes `nil` for `.kan(let k)` (robbing windows).
  3. On `"ankan"` and `"daiminkan"`, `Mjai.action` only checks `c.allSatisfy { $0.kind == k }`, accepting impossible red-five counts such as `["5mr","5mr","5mr","5mr"]` (4 reds) or `["5mr","5mr","5mr"]` (3 reds).
  4. On `"kakan"`, if `consumed` is provided, it is never checked to be 3 tiles of `pai.kind` (with at most 1 red total with `pai`).
- **Reproduction:** **Reproduced** via `docs/reviews/p3/final-agy-repro/repro_swift.swift`:
  - `[Finding 3a] bogus hora (wrong target=3, pai=9p) -> Optional(ron) (expected nil)`
  - `[Finding 3b] ankan with 4 red fives -> Optional(ankan:5m) (expected nil)`
  - `[Finding 3c] daiminkan with 3 red fives -> Optional(daiminkan) (expected nil)`
- **Proposed fix:**
  - Pass `offered` for both `.discard(d)` and `.kan(k)` in `MjaiBot.swift:151`.
  - In `Mjai.action`: on `"hora"` in a window (`offered != nil`), validate `m.pai == offered.tile` (if present) and `m.target == offered.from.index` (if present); on a turn tsumo, validate `m.target == seat.index` (if present).
  - Validate red-five multiplicity (`<= 1` red across `consumed` + `offered.tile` for `daiminkan`, `<= 1` red in `consumed` for `ankan`, and if `kakan` provides `consumed`, 3 tiles of `t.kind` with `<= 1` red total).

---

### Finding 4 — `should-fix`: `ChildProcess` leaks orphan grandchild processes on timeout/kill and lacks `deinit`

- **File & lines:** `Sources/mj/MjaiBot.swift:12-35, 80-89` (`ChildProcess`)
- **What happens:**
  1. `ChildProcess` spawns `/bin/sh -c <command>`. When a bot times out or floods stdout, `stop()` sends `SIGTERM` and then `SIGKILL` only to `/bin/sh`'s PID (`process.processIdentifier`), not to a process group. If `<command>` runs a subprocess that `/bin/sh` does not `exec`-optimize (e.g., `python3 bot.py; cleanup`, pipelines, wrapper scripts) and that subprocess ignores `SIGTERM`, `SIGKILL` kills `/bin/sh` while the grandchild survives indefinitely, holding open inherited file descriptors (which can even hang callers capturing `mj`'s stderr!).
  2. `ChildProcess` has no `deinit` calling `stop()`, so if `playGame` throws before `finish()` runs (e.g., `DriverError.illegal` on another seat), all running `MjaiBot` children are leaked.
- **Reproduction:** **Reproduced** via `docs/reviews/p3/final-agy-repro/repro_orphan.py`:
  - `mj exit=0, grandchild pid=76052, survived_after_mj_exit=True` (and when capturing stderr, the parent `subprocess.run` hung waiting on the orphaned grandchild's stderr FD).
- **Proposed fix:**
  - Spawn the child in its own process group (`posix_spawn` with `POSIX_SPAWN_SETPGROUP`, or `setpgid` before `exec`, or `/bin/sh -c "exec ..."` only when appropriate — `posix_spawn` with a new process group is cleanest) and send `SIGTERM`/`SIGKILL` to `-pgid` in `stop()`.
  - Add `deinit { stop() }` on `ChildProcess`, and close both pipe ends in `stop()`.

---

### Finding 5 — `should-fix`: `Mjai.reply` omits `target` on `pon`/`chi`/`daiminkan` and `pai` on `daiminkan`

- **File & lines:** `Sources/RiichiMjai/Mjai.swift:356-374` (`Mjai.reply`)
- **What happens:**
  `Mjai.reply(_:seat:target:tile:consumed:)` accepts `target: Seat? = nil` and `tile: Tile? = nil`, but only writes `"target"` for `.ron` (and `.tsumo`). For `.pon`, `.chi`, and `.daiminkan`, `"target"` is dropped; for `.daiminkan`, `"pai"` is also dropped. External mjai servers/bots (such as Mortal/mjai-reviewer) expect `target` and `pai` on call replies.
- **Reproduction:** **Reproduced** via `docs/reviews/p3/final-agy-repro/repro_swift.swift`:
  - `[Finding 5a] pon reply: {"type":"pon","actor":0,"pai":"5m","consumed":["5m","5m"]}` (missing `"target":1`)
  - `[Finding 5b] daiminkan reply: {"type":"daiminkan","actor":0,"consumed":["5mr","5m","5m"]}` (missing `"target":1,"pai":"5m"`)
- **Proposed fix:**
  - Include `("target", .int(target.index))` when `target != nil` on `.pon`, `.chi`, and `.daiminkan`, and `("pai", .string(name(tile)))` when `tile != nil` on `.daiminkan`. Add round-trip unit tests for `Mjai.reply` in `MjaiTests.swift`.

---

### Finding 6 — `should-fix`: Stale `disputedScenarios` entry and no-op `RulesFieldScenarioTests.openKanDoraBeforeRonOnMahjongSoul`

- **Files & lines:**
  - `Tests/RiichiTests/ScenarioTests.swift:14-18`
  - `Tests/RiichiTests/RoundTests.swift:221-230`
- **What happens:**
  1. `Tests/RiichiTests/ScenarioTests.swift:14-18` still lists `"declined_tsumo_outside_riichi.tenhou"` in `disputedScenarios`. Now that `scenarios/declined_tsumo_outside_riichi.scn` has been updated (Task 1), `swift test` fails `ScenarioTests` with 1 issue because the expected known issue no longer fires.
  2. `Tests/RiichiTests/RoundTests.swift:221-230` (`openKanDoraBeforeRonOnMahjongSoul`) sets `var r = Rules.mahjongSoul; r.openKanDoraBeforeRon = true` and runs `open_kan_discard_ron_dora`. Since `Rules.mahjongSoul.openKanDoraBeforeRon` is *already* `true`, this test is a no-op, and `openKanDoraBeforeRon == false` is tested nowhere in `Tests/`.
- **Reproduction:** Observed directly in `swift test` output (`Suite ScenarioTests failed after 10.572 seconds with 1 issue`) and by code inspection of `RoundTests.swift:223-224`.
- **Proposed fix:**
  - Empty `disputedScenarios` in `ScenarioTests.swift`.
  - Rewrite `openKanDoraBeforeRonOnMahjongSoul` into `openKanDoraAfterRon` setting `r.openKanDoraBeforeRon = false` and asserting the delayed-dora score (2 han 30 fu, 2000 instead of 4 han 30 fu, 7700) and event order (no `dora(7p)` before `hora(2)`).

---

### Finding 7 — `should-fix`: Documentation drift across `docs/design/engine.md`, `spec/rules.md`, and `Rules.swift`

- **Files & lines:** Detailed item-by-item list in **Documentation Drift** below.
- **What happens:**
  - `spec/rules.md` §1 (`kan_dora_daiminkan_timing`, `kan_dora_shouminkan_timing`, `furiten_temporary`) and §4 item 28 contain contradictory stale notes ("Mahjong Soul behaviour on that ron stays unverified", "default: not cleared", "a call in between does not clear it") that directly contradict the updated table values, §5, and `Rules.swift`.
  - `docs/design/engine.md` still has stale defaults in §4.1, §4.2, §4.4, §5, §6, and §7 (e.g., claims `temporaryFuritenEndsOnCall`, `fourWindsRiichiStickPaid`, `openKanDoraBeforeRon`, `fifthCopyTenpaiAtDraw` are off/unverified; claims `canRon` uses a cheap has-a-yaku test instead of full `score()`).
  - `Sources/Riichi/Rules.swift` has stale "unverified" doc comments on `dealerRepeatBeforeTarget`, `allLastTestAfterNagashi`, and `honbaToEveryRonWinner`, and omits `owedDoraAtChainedAddedKan` from `Rules.init(...)`.
- **Reproduction:** Code & doc inspection (no runtime repro needed).
- **Proposed fix:** Update the stale sentences in `spec/rules.md`, `docs/design/engine.md`, and `Rules.swift`, and add `owedDoraAtChainedAddedKan: Bool = false` to `Rules.init(...)`.

---

### Finding 8 — `suggestion`: Test coverage gaps (East-only games, `allLastTestAfterNagashi == false`, `ScenarioRunner` silent pass, `mixedRules` / `replayIsExact`)

- **Files & lines:**
  - `Tests/RiichiTests/ScenarioTests.swift:204`
  - `Tests/RiichiTests/SelfPlayTests.swift:299-335`
  - `Tests/RiichiTests/GameTests.swift:33-62`
  - `Sources/mj/Driver.swift:74-76` / `Sources/mj/Commands.swift:50-56`
- **What happens:** Detailed in **Test Audit** below. In brief: `ScenarioRunner` silently fills `.pass` for omitted asked seats; `SelfPlayTests.mixedRules` omits `owedDoraAtChainedAddedKan` and `GameState`-level rules; `SelfPlayTests.replayIsExact` re-runs the bot instead of replaying `decisions`; full East-only (`length: .east`) games are never played through `GameState` in tests and cannot be run via `mj selfplay`.
- **Reproduction:** Code inspection.
- **Proposed fix:** Make `ScenarioRunner` reject omitted asked seats unless explicitly opted in; add `owedDoraAtChainedAddedKan` to `mixedRules`; replay `decisions` in `replayIsExact`; add a `GameTests` test for full East-only games and `allLastTestAfterNagashi == false`.

---

### Finding 9 — `suggestion`: `canTsumo`/`canRon` call full `score()`, and `GameState.apply`/`resolve` trigger unnecessary CoW on `events`

- **Files & lines:**
  - `Sources/Riichi/RoundLegal.swift:97-101, 183-187`
  - `Sources/Riichi/Game.swift:212-233`
- **What happens:**
  1. `RoundLegal.canTsumo` and `canRon` call `scoreWin(...)`, which runs full `score()` (including all readings, dora/aka/ura counting, fu calculation, and payment sorting), whereas `docs/design/engine.md` §4.4 specifies a cheap `hasYaku` check.
  2. Unlike `RoundState.apply` (`Round.swift:241`), which sets `events = []` before handing the array to `Emitter` to preserve unique ownership, `GameState.apply` and `GameState.resolve` (`Game.swift:214, 228`) copy `events` into `Emitter` without clearing the caller's reference first, causing a CoW copy on every append when `events` is non-empty.
- **Reproduction:** Code inspection.
- **Proposed fix:** Clear `events = []` after moving into `Emitter` in `GameState.apply`/`resolve` (and `GameState.init`). Consider a fast `hasYaku` path in `RoundLegal` if profiling shows `canRon`/`canTsumo` hot in Phase 4 arenas.

---

## Design, Maintainability, and API Recommendations (Phase 4 & Phase 5)

### 1. Public API of `Riichi` — Fit for Bots, LLM Tool Server, and WebAssembly?

The core step API (`GameState`, `RoundState`, `legalActions`, `apply`, `resolve`, `PlayerView`, `MaskedEvent`) is clean, value-typed, `Sendable`, Foundation-free, and 32-bit `Int`-safe. That is a strong foundation. However, building Phase 4 (bots + LLM benchmark) and Phase 5 (WASM website) exposes specific gaps:

#### For Bots (`PlayerView` → `Action`)
1. **Expose `PlayerView.Table.seatWind` and `turnStart` / `inRiichi` / `isClosed` helpers.** Right now a bot given a `PlayerView` has to recompute `seat.wind(dealer: table.dealer)`, `table.melds[seat.index].allSatisfy { $0.kind == .ankan }`, and infer whether it is in `riichiDeclared` or `call` vs `draw` from `table.drawn` and `table.riichi[seat.index]`. Adding small computed properties on `PlayerView` eliminates boilerplate across every bot.
2. **Expose `visibleCounts` / remaining-tile counts on `PlayerView`.** Every tactical bot (and shanten/ukeire heuristic) needs the 34-kind count of all tiles visible to `seat` (own hand + drawn + all melds + all ponds + dora indicators). Providing `PlayerView.visibleCounts: Counts` avoids every bot re-implementing this and risking off-by-one bugs with `calledAway` pond tiles!
3. **Expose `PlayerView.furitenParts` or keep `furiten` + `waits`.** `PlayerView` exposes `furiten: Bool`, which is good, and adding `waits: [Kind]` (or letting bots call `completingKinds`) avoids recomputing structural waits on every turn.
4. **Add `GameState.view(of:)` forwarding to `round.view(of:)`.** Currently callers must reach into `game.round.view(of: seat)`, whereas `game.legalActions(for:)` and `game.seatsToAnswer` are forwarded on `GameState`.

#### For an LLM Tool Server (legal moves, shanten & ukeire, hypothetical scoring, safe tiles)
1. **Per-discard ukeire / shanten analysis (`discardAnalysis` / `ukeire`).** Currently `waits(_:melds:)` only takes a 13-tile hand (`shanten`, `tiles`, `count`) and only subtracts *hand + melds*, NOT table-visible tiles (ponds, other melds, dora indicators). An LLM tool server needs:
   - `ukeire(hand:melds:visible:)` that subtracts *all* visible tiles (`Counts`), and
   - `bestDiscards(hand:melds:visible:)` returning, for each distinct discard of a 14-tile hand, the resulting shanten, accepting kinds, and remaining visible count.
2. **Hypothetical hand scoring (`ScoreRequest` + `score`).** `ScoreRequest` and `score(_:rules:)` are already public and clean! One gap: `ScoreRequest` takes `[Meld]` while `PlayerView` holds `[TableMeld]`, so callers must `.map(\.meld)`. Also, `ScoreError` does not distinguish malformed tile counts (e.g. >4 of a kind) from `.notAgari` — an LLM tool server should validate input tiles without trapping `Counts` (see Finding 1).
3. **Safe-tile / defensive analysis (`genbutsu`, `suji`, `kabe` / `noChance`).** Nothing in `Riichi` computes defensive tile safety from a `PlayerView` yet. Adding a small, pure `Defense` helper on `PlayerView` (at minimum `genbutsu(against: Seat) -> Set<Kind>`, taking into account discards *after* riichi declaration and same-turn discards by other seats) is high leverage for both bots and the LLM tool server.
4. **Fix `RoundState.winRequest(for:)`** (Finding 2) or provide `RoundState.previewScore(for: Seat, honba: Int)` if tools want to query exact win scores from a live state.

#### For JavaScript through WebAssembly (Phase 5)
1. **JSON codecs for `PlayerView`, `Action`, `GameResult`, and `Rules` in `RiichiMjai` (or a sibling `RiichiJSON` target).** Right now `RiichiMjai` only encodes/decodes mjai `Event`/`MaskedEvent` and bot replies — as `docs/design/engine.md` §6 notes, "mjai alone cannot drive a UI." A WASM bridge needs zero-Foundation JSON encoding of `PlayerView` (including `legalActions` in a structured form, not just `Action.description` strings) and `GameResult`, plus decoding `Action` and `Rules` (with `Rules.isValid` checked before `GameState.init` so bad JS input returns an error instead of trapping WASM!).
2. **Replace `precondition` traps on public API boundaries with failable/throwing initializers where untrusted input enters.** On `wasm32`, a Swift `precondition` failure aborts the entire WASM instance (`unreachable`). `GamePosition.init`, `RoundState.init`, `GameState.init`, `Rules.uma.didSet`, `Kind.init`, `Seat.init`, and `Counts.subscript` all trap on bad inputs. Keep preconditions on hot internal paths, but provide validated entry points (or validate in the WASM boundary layer) so JS can never crash the WASM module.
3. **Include `owedDoraAtChainedAddedKan` in `Rules.init`** (Finding 7) and make `Rules` `Codable`-free JSON-serializable via `JSONOut`/`JSONObject` for JS configuration.

### 2. Maintainability of `Round.swift`

`Sources/Riichi/Round.swift` is 821 lines — large, but well-organized by `// MARK:` sections (`start`, `queries`, `stepping`, `draws`, `discards`, `calls`, `kans`, `endings`) and already split from `RoundLegal.swift` (266 lines) and `RoundResult.swift` (56 lines). It is **maintainable as-is** and does **not** need a rewrite.

- **Refactorings worth doing now (small, surgical):**
  1. Extract `settle(winners:tile:from:source:_:)` + `winRequest` (~115 lines, lines 694–809) into `RoundSettlement.swift` (or `RoundResult.swift`). Pao redistribution and `ScoreRequest` assembly are self-contained and easier to audit in isolation.
  2. Extract `PlayerState` + `PondTile` + `RiichiStatus` + `Pao` + `waitMask` (lines 7–82) into `PlayerState.swift` so `Round.swift` focuses purely on state transitions.
  3. Fix `winRequest(for:)` (Finding 2) and clear `events = []` in `GameState.apply`/`resolve` (Finding 9).
- **Refactorings to leave alone:**
  - Do **not** split `RoundState` into separate phase-specific state structs or a protocol hierarchy — the single value-type `RoundState` with `Phase` enum is fast, easy to copy for speculative search, and straightforward to reason about.
  - Do **not** replace `offers: [[Action]]` caching or `UInt64` bitmasks (`waits`, `pondKinds`, `kuikae`) — they are clean, deterministic, and fast.

---

## Documentation Drift

### `spec/rules.md` vs `Sources/Riichi/Rules.swift` (field by field)

All 22 `Rules` fields match the **table values** in `spec/rules.md` §1 for both `Rules.mahjongSoul` and `Rules.tenhou`, **except** for contradictory prose in `spec/rules.md` and stale doc comments in `Rules.swift`:

| Location | Drift |
| :--- | :--- |
| `spec/rules.md` §1 `kan_dora_daiminkan_timing` (L71) & `kan_dora_shouminkan_timing` (L72) | Table says `at_discard` / `at_discard`, but the Notes column ends with the contradictory stale sentence: *"Mahjong Soul behaviour on that ron stays unverified."* |
| `spec/rules.md` §1 `furiten_temporary` (L80) | Table says `until next own draw or own call` for both, but Notes still ends with *"whether a call in between clears it is not checked in a client, and the engine has a `Rules` field for it (default: not cleared)."* |
| `spec/rules.md` §4 item 28 (L274) | Still says *"triggers temporary furiten until your next draw (a call in between does not clear it; see `furiten_temporary`)"* — contradicts §1, §5 item 11, and both presets (`temporaryFuritenEndsOnCall = true`). |
| `spec/rules.md` §1 `sudden_death_target` (L26) | Says game ends immediately when a player reaches `>= 30000`, without noting dealer-repeat priority (`dealerRepeatBeforeTarget = true`, §5 item 8). |
| `Sources/Riichi/Rules.swift:29, 32, 56` | Doc comments on `dealerRepeatBeforeTarget`, `allLastTestAfterNagashi`, and `honbaToEveryRonWinner` still say "unverified" despite being settled in `docs/notes/p3-reallogs.md`. |
| `Sources/Riichi/Rules.swift:76, 119-150` | `owedDoraAtChainedAddedKan` is missing from `Rules.init(...)` (only a mutable property with default `false`). |

### `docs/design/engine.md` vs Implementation

| Section / Line | Drift |
| :--- | :--- |
| Header (L3-5) | Still says *"Status: draft 2. ... Nothing here is implemented yet."* |
| §4.1 (L186-188) | Claims temporary furiten ends only on next draw and *"A call does not end it."* Both presets have `temporaryFuritenEndsOnCall = true`. |
| §4.2 Four winds (L212-214) | Claims four-winds riichi stick is unverified and *"default not paid"*. Both presets have `fourWindsRiichiStickPaid = true`. |
| §4.2 Kans (L225-236) | Claims open-kan → added-kan order is always `kakan`, robbing window, `dora`, `tsumo` (under Mahjong Soul `owedDoraAtChainedAddedKan = true`, `dora` precedes the robbing window); claims `openKanDoraBeforeRon` defaults to `false` on Mahjong Soul (it is `true` for both). |
| §4.2 Exhaustive draw (L253-255) | Claims Mahjong Soul does not count fifth-copy formal tenpai (`fifthCopyTenpaiAtDraw` is `true` for both). |
| §4.4 Speed (L291) | Claims *"Can this seat ron this tile is a wait lookup plus a cheap has-a-yaku test. Full scoring runs only when someone actually wins."* Actually `canRon`/`canTsumo` call full `scoreWin(...)`. |
| §5 (L324-326, 333) | Still calls `dealerRepeatBeforeTarget` (Mahjong Soul) and `allLastTestAfterNagashi` (both) unverified. |
| §6 Event table (L344, 355) | `Event.startGame` carries no fields (names/id added in `RiichiMjai`); `end_kyoku` in unmasked logs also carries optional `scores`, `deltas`, `kyotaku_left`, `dealer_repeats` (`Mjai.Extras.result`). |
| §6 PlayerView (L359-365) | Doesn't reflect the `PlayerView.Table` split or hiding `reacting` (`nil`) when `legalActions` is empty. |
| §7 Command line (L393-407) | Missing `--scenario`, `--seat`, `--legal`, `--requests`, `--check`, `--timeout`, `--quiet` on `selfplay`; missing `--set`, `--json`, `--stdin` on `check-log`; missing `bench-round`. |

---

## Test Audit

### Tests that would still pass if the code were wrong
1. **`Tests/RiichiTests/RoundTests.swift:221-230` (`RulesFieldScenarioTests.openKanDoraBeforeRonOnMahjongSoul`)**: Sets `r.openKanDoraBeforeRon = true` on `Rules.mahjongSoul`, which is already `true`. Completely fails to test `openKanDoraBeforeRon == false`.
2. **`Tests/RiichiTests/ScenarioTests.swift:204` (`ScenarioRunner.perform` for `window`)**: Silently fills `.pass` for any seat in `seatsToAnswer` not listed in the scenario's `window:` line. If the engine erroneously offers an illegal call to an unlisted seat, `ScenarioTests` still passes.
3. **`Tests/RiichiTests/SelfPlayTests.swift:321-335` (`replayIsExact`)**: Plays `playRound` twice with the same `TestRNG` seed instead of replaying the recorded `decisions` array — tests bot determinism rather than decision replay.

### What is asserted nowhere
1. **`Rules.openKanDoraBeforeRon == false`** (delayed kan dora after discard window closes) — no unit or scenario test asserts its score or event order.
2. **`Rules.allLastTestAfterNagashi == false`** through `GameState` (`GameState.testScores` at `Game.swift:241-248` is never exercised in any test!).
3. **Full East-only (`Rules.length = .east`) games** through `GameState` (only a single `GameFlow.next` call in `GameTests.transitions()`; `mj selfplay` also cannot run East-only games).
4. **`RoundState.winRequest(for:)`** — no direct unit tests anywhere (which hid Finding 2).
5. **`Mjai.reply(...)`** — never called or asserted in `MjaiTests.swift` (which hid Finding 5).
6. **`Rules.owedDoraAtChainedAddedKan` in `SelfPlayTests.mixedRules`** — omitted when flipping boolean `Rules` fields (and `mixedRules` only runs `RoundState`, never `GameState`).
7. **Malformed/hostile inputs to `parseTiles` and `mj` line protocol** (non-ASCII Unicode digits, >15 identical tiles) — would have caught Finding 1.

---

## Verdict

**Ready to build on with minor pre-Phase-4 fixes (conditional GO).**

The core mahjong engine (`Riichi`) is sound, fast, deterministic, and thoroughly cross-checked; there are **no blockers** in game rules, scoring, legality, or information hiding. Before building Phase 4 (bot arena + LLM tool server) and Phase 5 (WASM UI) on top of it, fix these concrete items first:

1. **Fix Finding 1** (`parseTiles` ASCII-only digits + `Request.hand` tile-count check before `Counts(all)`) so untrusted inputs cannot crash `mj` or the library.
2. **Fix Finding 3 & Finding 4** (`Mjai.action` validation for `hora`/kans + `ChildProcess` process-group kill and `deinit`) before running external or LLM bots in an arena.
3. **Fix Finding 2 & Finding 5** (`RoundState.winRequest(for:)` honba handling and `Mjai.reply` `target`/`pai` fields).
4. **Fix Finding 6** (clear `disputedScenarios` so `swift test` is 100% green, and fix `openKanDoraBeforeRonOnMahjongSoul` to actually test `false`).
5. **Clean up Finding 7** (add `owedDoraAtChainedAddedKan` to `Rules.init` and remove contradictory notes in `spec/rules.md` and `docs/design/engine.md`).
