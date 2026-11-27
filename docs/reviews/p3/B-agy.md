# Phase 3 package B review (agy)

Reviewed `Sources/Riichi/Round.swift`, `RoundLegal.swift`, `RoundResult.swift`, `Action.swift`, `Event.swift`, and their tests against `docs/design/engine.md` §4 & §6 and `spec/rules.md`.

Note: The three issues already reported by the other reviewer and fixed in the working tree (declined tsumo + ankan temporary furiten under Tenhou; robbed closed kan left in `melds`; fourth open kan's owed dora before `suukaikan`) are omitted, as is item 6 of the brief (the seven disputed scenarios). The two obsolete partial files from an earlier attempt (`repro_skip_tsumo.swift` and `tenhou_skip_tsumo_temporary_furiten.scn`) were discarded since that fix is already in `Round.swift`.

---

## Findings

### 1. Stale `counts`, `waits`, and `isFuriten` on the declarer during a closed-kan robbing window

- **Severity**: should-fix
- **Location**: `Sources/Riichi/Round.swift:529-550` (`announceClosedKan`)
- **Details**:
  When `announceClosedKan` removes the four kan tiles from `players[i].hand` / `drawn` and inserts the drawn tile into `hand` (when `d.kind != k`), it does not update `players[i].counts` or `players[i].waits`. By contrast, `announceAddedKan` (`Round.swift:561`) calls `players[i].refresh()` before emitting `.kakan` and entering `.robbing(pk)`.
  As a result, while `phase == .robbing(pk)` (under Mahjong Soul when another seat holds kokushi waiting on `k`) — and during the `observe` callback on `.ankan` — `waits(of: seat)` and `isFuriten(seat)` return stale values computed from the pre-kan hand.
- **Reproduction**: `docs/reviews/p3/B-agy-repro/repro_ankan_robbing_stale_waits.swift` (reproduced).
  Seat 0 holds `1111m 234p 567p 88s 4z` (`waits == []`), draws `8s`, and declares `ankan(1m)` while Seat 1 holds kokushi on `1m`. In `.robbing(.closed)`, Seat 0's hand is `234p 567p 888s 4z` (tanki on `4z`), but `waits(of: Seat(0))` still returns `[]`.
- **Proposed fix**:
  In `announceClosedKan`, after updating `players[i].hand` and clearing `players[i].drawn`, update `players[i].counts = Counts(players[i].hand)` and `players[i].waits = waitMask(players[i].counts, meldCount: players[i].melds.count + 1)` (using `melds.count + 1` since `hand` already has `13 - 3*(melds.count + 1)` tiles while the kan is pending; if robbed, `closeKanWindow` already restores the three tiles and calls `refresh()`).

---

### 2. Tile lost on `sanchahou` (triple ron abort) robbing a closed kan

- **Severity**: should-fix
- **Location**: `Sources/Riichi/Round.swift:574-586` (`closeKanWindow`)
- **Details**:
  In `closeKanWindow`:
  ```swift
  if !winners.isEmpty {
      if pk.kind == .closed, let tiles = pendingClosedKan {
          // The robbed copy is the winning tile; the other three stay concealed.
          for t in tiles.dropFirst() { players[pk.seat.index].insert(t) }
          players[pk.seat.index].refresh()
          pendingClosedKan = nil
      }
      if winners.count == 3 && rules.tripleRonAborts { return abort(.sanchahou, &e) }
      return settle(winners: winners, tile: pk.tile, from: pk.seat, source: .robbing(pk.kind), &e)
  }
  ```
  When a custom `Rules` enables both `kokushiRobsClosedKan` and `tripleRonAborts` and all three other seats rob a closed kan with kokushi (which is legally reachable within the 136-tile wall: Seat 0 holds `1111m`, and Seats 1–3 each hold single-wait kokushi on `1m`), `closeKanWindow` returns only `tiles.dropFirst()` (3 tiles) to Seat 0's hand, clears `pendingClosedKan`, and aborts with `.sanchahou` without calling `settle`. Because there is no `Win` to hold the fourth copy, `tiles[0]` disappears from `RoundState` (135 tiles in play instead of 136, violating tile conservation).
  *(Note: triple chankan on an added kan cannot arise in legal play because one of the three other seats must have discarded the ponned tile and is therefore own-discard furiten on that kind.)*
- **Reproduction**: `docs/reviews/p3/B-agy-repro/repro_sanchahou_ankan_tile_loss.swift` (reproduced).
  With `rules = Rules.tenhou` and `rules.kokushiRobsClosedKan = true`, Seat 0 declares `ankan(1m)` and Seats 1, 2, 3 all answer `.ron`. The round ends with `.abortiveDraw(.sanchahou)`, Seat 0 holds only three `1m`s with `drawn == nil`, and total tiles in play is `52` instead of `53` (`52` dealt + `1` live draw).
- **Proposed fix**:
  In `closeKanWindow`, handle `winners.count == 3 && rules.tripleRonAborts` before dropping `tiles[0]`: restore all four tiles (`for t in tiles.dropFirst() { players[i].insert(t) }; players[i].drawn = tiles.first; players[i].refresh(); pendingClosedKan = nil`, matching `kyuushu` where `hand` has `13 - 3k` tiles and `drawn` holds the 14th), and likewise restore `players[i].drawn = pk.tile` defensively if `pk.kind == .added`, before calling `abort(.sanchahou, &e)`.

---

## Areas audited with no bugs found

- **Payments (`Round.swift:631-652, 697-759`, `RoundResult.swift`)**:
  - Pao on daisangen and daisuushii (`checkPao`, tsumo, third-party ron, liable-seat ron, composite yakuman under both `paoCoversWholeHand == false` and `true`, double yakuman daisuushii, pao inside multi-ron with honba and sticks, pao on chankan). All exact and point-conserving.
  - Multi-ron sticks and honba (`honbaToEveryRonWinner` off and on, turn-order head-bump from `from`, `dealerRepeats` if any winner is dealer, `nextHonba(after:)`). All exact.
  - Exhaustive draw with 0–4 tenpai (including `fifthCopyTenpaiAtDraw` on/off) and nagashi mangan (single, multiple, dealer, non-dealer, empty-pond guard, sticks/honba/renchan). All exact.
  - Riichi sticks on ronned vs accepted declarations, four-riichi abort, and four-winds abort (`fourWindsRiichiStickPaid` on/off). All exact.
- **State transitions & flags (`Round.swift`, `RoundLegal.swift`)**:
  - `ippatsu` (start on `acceptRiichi`, cleared on own next discard, any call, or committed kan; preserved on robbed `kakan` for `riichi + ippatsu + chankan`).
  - First-go-around flags (`anyCallMade`, `tenhou`, `chiihou`, `doubleRiichi`, `kyuushu`, `isFourWinds`).
  - `doraOwed` across open/added/closed kans, chained kans, and `openKanDoraBeforeRon` on/off.
  - Furiten in all three kinds (own-discard including called-away, temporary including yaku-less waits and calls not clearing it, riichi furiten including skipped draws and riichi ankans).
  - Drawn-tile slot (`drawn` cleared on all turn exits except `.riichiDeclared` and round-ending `.tsumo`/`.kyuushu`).
- **Crashes, traps, determinism, and hot path**:
  - All force unwraps (`!`) and `precondition`s in `Round.swift`, `RoundLegal.swift`, `Wall.swift`, and `Seat.swift` are guarded by prior legality/bounds checks (`liveTilesLeft >= 0`, `liveDrawn < 70`, `replacementsDrawn < 4`, `doraShown <= 5`, `TableMeld` constructors).
  - `apply` and `resolve` validate before mutating and restore `events` on throw.
  - No hidden nondeterminism (`Answers` is fixed 4-slot; all action lists are canonically sorted) and no quadratic loops on the hot path.
