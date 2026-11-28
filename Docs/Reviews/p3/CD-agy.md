# Phase 3 Packages C & D Review (Antigravity)

Scope: `Sources/Riichi/Game.swift`, `Sources/Riichi/View.swift`, `Sources/RiichiMjai/`, `Sources/mj/` (and their tests), reviewed against `Docs/Design/engine.md` §§5–8 and `Spec/rules.md`.

All reproductions live in `Docs/Reviews/p3/CD-agy-repro/` and were run against `.build/debug/mj` (and `.build/out/Products/Debug/libRiichi` + `libRiichiMjai`) built at HEAD (`8af34a7`).

---

## Summary by Priority Area

1. **Game flow (`Sources/Riichi/Game.swift`):** Every branch of design §5 under both default rulesets (`mahjongSoul`, `tenhou`) is sound — tobi (`< 0`, `0` continues), honba increment/reset (including multi-ron with dealer), dealer repeat, all-last seat-order tie-break (including West 1 dealer tied for 1st), extension and sudden death (including West 4 / South 4 repeat), leftover sticks excluded from the 30,000 test and awarded to 1st at end, oka and uma for both rulesets. One edge-case bug found when the optional `dealerRepeatBeforeTarget` field is set to `false` on an abortive draw (Finding 12).
2. **Hidden information (`Sources/Riichi/View.swift`, `Sources/RiichiMjai/Mjai.swift`):** Clean. `MaskedEvent` is a distinct type; `start_game` has no seed; `start_kyoku` and `tsumo` mask other seats' tiles to `nil`/`"?"`; `hora` emits `ura_markers: []` for non-riichi winners and only `0..<doraShown` for riichi winners; `ryukyoku` masks noten hands (and all hands on abortive draws); `PlayerView` exposes only own hand/drawn/furiten/legalActions and public table state, with no reference back to `RoundState` or `Wall`; `Mjai.encode(_:MaskedEvent)` never emits `wall`.
3. **mjai codec & bot adapter (`Sources/RiichiMjai/`, `Sources/mj/MjaiBot.swift`):** Three blockers (surrogate-pair underflow crash, unbounded recursion stack overflow, `SIGTERM`-ignoring bot hanging `stop()` + unbounded line buffer) and four should-fix validation/classification issues (Findings 1–3, 8–11).
4. **`check-log` (`Sources/mj/CheckLog.swift`):** Two blockers (empty/out-of-hand events silently accepted; negative `honba`/`kyotaku` crashes with precondition failure) and two should-fix bugs (rejects valid riichi wins when `ura_markers` is omitted or named `uradora_markers`; accepts fabricated `ryukyoku.reason`/`tenpais` and unchecked `hora` fields) (Findings 4–7).
5. **Determinism:** Clean across `Riichi`, `RiichiMjai`, and `mj` — no `Dictionary` or `Set` iteration affects output order (all map/set outputs are sorted before formatting; `JSONObject` and `JSONOut` preserve array order; `Answers` is 4 fixed slots; `BotRNG` uses SplitMix64). `ContinuousClock` is used only for timing metrics and `MjaiBot` timeouts.

---

## Findings

### 1. [blocker] Surrogate-pair arithmetic underflow crashes `Scanner.string()` on hostile JSON

- **Location:** `Sources/RiichiMjai/JSON.swift:128-135`
- **Issue:** When decoding a `\u` escape in the high-surrogate range (`0xD800..<0xDC00`) followed by another `\uXXXX`, `Scanner.string()` computes `code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)` without checking that `low` is in `0xDC00...0xDFFF`. Because `low` is `UInt32`, any `low < 0xDC00` (e.g. `{"type":"\uD800\u0000"}`) traps with integer underflow and crashes the entire `mj` process (in `selfplay` with an mjai bot or `check-log`).
- **Reproduction:** **Reproduced.** `python3.14 Docs/Reviews/p3/CD-agy-repro/repro_json_crashes.py` → `[Finding 1: surrogate underflow] returncode=-5 (signal=5)` (`SIGTRAP`).
- **Proposed fix:** Only combine surrogates when `(0xDC00...0xDFFF).contains(low)`; otherwise emit `U+FFFD` (or throw `JSONError`) for the unpaired high surrogate and do not consume the following `\uXXXX` as a low surrogate.

---

### 2. [blocker] Unbounded recursion in `Scanner.skip()` and `Scanner.value()` stack-overflows on deeply nested JSON

- **Location:** `Sources/RiichiMjai/JSON.swift:187-246`
- **Issue:** `Scanner.skip()` and `Scanner.value()` recurse without any nesting-depth limit. A hostile mjai bot replying with deeply nested arrays/objects (e.g. `{"type":"none","meta":[[[...]]]}`) overflows the call stack and crashes the `mj` process instead of being counted as `malformed`.
- **Reproduction:** **Reproduced.** `python3.14 Docs/Reviews/p3/CD-agy-repro/repro_json_crashes.py` → `[Finding 2: deep nesting] returncode=-11 (signal=11)` (`SIGSEGV`).
- **Proposed fix:** Thread a `depth: Int` parameter through `object()`, `skip()`, and `value()`, throwing `JSONError(message: "nesting too deep", offset: i)` once `depth > 64`.

---

### 3. [blocker] `ChildProcess.stop()` hangs forever on bots that ignore `SIGTERM`, and `readLine()` has no line-length cap

- **Location:** `Sources/mj/MjaiBot.swift:46-72`
- **Issue:**
  1. `ChildProcess.stop()` sends `SIGTERM` via `process.terminate()` (to `/bin/sh` only, not the process group) and blocks indefinitely in `process.waitUntilExit()`. A bot (or grandchild) that ignores `SIGTERM` hangs the arena forever, defeating `--timeout`.
  2. `readLine(timeoutMs:)` appends 4 KB chunks into `buffer` with no maximum byte limit and re-scans from index 0 (`buffer.firstIndex(of: 0x0A)`) on every chunk (`O(N²)` CPU and unbounded memory until timeout). A bot that writes multiple lines per event also leaves stale replies queued in `buffer`.
  3. `stop()` calls `close(toChild)` on a descriptor still owned by `handles[0].fileHandleForWriting`, risking double-close on deallocation.
- **Reproduction:** **Reproduced.** `python3.14 Docs/Reviews/p3/CD-agy-repro/repro_bot_adapter.py`:
  - `[SIGTERM-ignore] REPRODUCED: mj hung for >2.5s despite --timeout 150ms!`
  - `[Output flood] finished in 0.72s (timeout was 0.30s) rc=0` (overran 0.30s timeout to 0.72s scanning a multi-MB buffer).
- **Proposed fix:** Cap `buffer` at a fixed max line size (e.g. 1 MiB) and scan only the newly appended slice for `0x0A`; treat overflow as a failure and kill the bot. In `stop()`, close via `fileHandleForWriting.closeFile()`, wait briefly for exit, then escalate to `SIGKILL` (targeting the child's process group).

---

### 4. [blocker] `check-log` silently accepts empty logs and skips arbitrary impossible events outside `start_kyoku`..`end_kyoku`

- **Location:** `Sources/mj/CheckLog.swift:26-37, 40-67`
- **Issue:**
  1. A log with zero `start_kyoku` events (empty file, or only `start_game` / `end_game` / bogus actions) produces `hands = []`, `errors = 0`, and exit code `0`.
  2. Any events before the first `start_kyoku`, between `end_kyoku` and the next `start_kyoku`, or after the last `end_kyoku` (e.g. an injected `hora` or `dahai`) are silently skipped by `guard msgs[i].type == "start_kyoku" else { i += 1; continue }`.
- **Reproduction:** **Reproduced.** `python3.14 Docs/Reviews/p3/CD-agy-repro/repro_checklog_bugs.py`:
  - `[Finding 4a: empty log] rc=0 out='files=1 hands=0 errors=0\nnot checked: -'`
  - `[Finding 4b: bogus events outside hands] rc=0 out='files=1 hands=0 errors=0\nnot checked: -'`
- **Proposed fix:** Fail if `hands.isEmpty`, and reject any event outside `start_kyoku`..`end_kyoku` other than `start_game` (before the first hand) and `end_game` (after the last hand).

---

### 5. [blocker] `check-log` crashes with precondition failure on negative `honba` or `kyotaku`

- **Location:** `Sources/mj/CheckLog.swift:136-148` (calls `RoundState.init` at `Sources/Riichi/Round.swift:154`)
- **Issue:** `HandChecker.run` validates `(1...4).contains(kyoku)` and `scores.count == 4`, but does not check `honba >= 0 && sticks >= 0`. Passing a log with `"honba": -1` or `"kyotaku": -1` hits `precondition(honba >= 0 && sticks >= 0)` in `RoundState.init` and crashes `mj check-log`.
- **Reproduction:** **Reproduced.** `python3.14 Docs/Reviews/p3/CD-agy-repro/repro_checklog_bugs.py` → `[Finding 5: negative honba] rc=-5 (signal=5) stderr='Riichi/Round.swift:154: Precondition failed'`.
- **Proposed fix:** Add `guard honba >= 0, sticks >= 0 else { fail(&r, 0, "negative honba or kyotaku"); return nil }` in `HandChecker.run`.

---

### 6. [should-fix] `check-log` rejects valid riichi wins when `ura_markers` is omitted or uses `uradora_markers`

- **Location:** `Sources/mj/CheckLog.swift:120, 124-131, 232-234` and `Sources/RiichiMjai/Mjai.swift:258`
- **Issue:**
  1. `Mjai.decode` only reads `"ura_markers"`, ignoring `"uradora_markers"` (the original mjai/akochan field name in design §6).
  2. When a riichi `hora` omits `ura_markers` (which line 233 explicitly intends to track via `r.note("unseen_ura")`), `rebuildWall` fills slots `131..<136` with arbitrary unused tiles from `Wall.sorted`. If those fabricated ura indicators differ in ura dora count from the actual hand, `differs()` rejects the valid log on `deltas`/`scores`.
- **Reproduction:** **Reproduced.** `python3.14 Docs/Reviews/p3/CD-agy-repro/repro_checklog_bugs.py`:
  - `[Finding 6a: uradora_markers only (game 1)] REPRODUCED rc=1 ... hora.deltas: log [0, 13300, -12300, 0], engine [0, 9300, -8300, 0]`
  - `[Finding 6b: omitted ura_markers (game 1)] REPRODUCED rc=1 ... hora.deltas: log [0, 13300, -12300, 0], engine [0, 9300, -8300, 0]`
- **Proposed fix:** In `Mjai.decode`, fall back to `try known("uradora_markers")` when `ura_markers` is absent. When a riichi `hora` omits ura markers, record `unseen_ura` and avoid failing on ura-dependent `deltas`/`scores` (or verify that the logged payment is achievable for some valid ura count).

---

### 7. [should-fix] `check-log` `differs()` does not verify `ryukyoku.reason`, `ryukyoku.tenpais`, `ryukyoku.tehais`, or `hora` scoring fields

- **Location:** `Sources/mj/CheckLog.swift:239-257`
- **Issue:** Even when present in the log, `ryukyoku.reason`, `ryukyoku.tenpais`, `ryukyoku.tehais`, and `hora`'s `hora_tehais`/`yakus`/`fu`/`fan` are never checked by `differs()`. An impossible log with `"reason": "completely_bogus_reason"` and `"tenpais": [true, true, true, true]` on a draw with noten seats is accepted with `errors=0`.
- **Reproduction:** **Reproduced.** `python3.14 Docs/Reviews/p3/CD-agy-repro/repro_checklog_bugs.py` → `[Finding 7: bogus ryukyoku reason & tenpais (game 0)] rc=0 out='files=1 hands=12 errors=0\nnot checked: passes=70'`.
- **Proposed fix:** Compare `log.reason` against `mine.reason` in `differs()`, and decode/compare `tenpais` and `hora_tehais` when present.

---

### 8. [should-fix] `JSON.swift` `skip()` skips invalid string escapes, `subscript` swallows parse errors with `try?`, and `number()` accepts malformed numbers

- **Location:** `Sources/RiichiMjai/JSON.swift:51-55, 171-184, 191-197`
- **Issue:**
  1. `Scanner.skip()` advances past `\` + 1 byte without validating the escape, and `JSONObject.subscript` uses `try? s.value()`. A reply like `{"type":"dahai","actor":0,"pai":"\q","tsumogiri":false}` passes `JSONObject(parsing:)`, then `o["pai"]` returns `nil`, causing `MjaiBot` to misclassify a `malformed` reply as `illegal`.
  2. `Scanner.number()` accepts any mix of digits and `.eE+-` (e.g. `1..2e+-3`, `01`, `.5`).
  3. `Scanner.string()` accepts raw unescaped control characters (`< 0x20`).
- **Reproduction:** **Reproduced.** `python3.14 Docs/Reviews/p3/CD-agy-repro/repro_json_validation.py`:
  - `[Finding 8a: bad escape \q in pai] substitutions malformed=0 illegal=1 ...`
  - `[Finding 8b: bogus number 1..2e+-3] rc=0 out='files=1 hands=0 errors=0'`
- **Proposed fix:** Validate string escapes and reject bytes `< 0x20` in both `skip()` and `string()`, and enforce the RFC 8259 number grammar in `number()`.

---

### 9. [should-fix] `JSONObject` duplicate keys use first-wins (`firstIndex`) instead of last-wins

- **Location:** `Sources/RiichiMjai/JSON.swift:52`
- **Issue:** `JSONObject.subscript` uses `keys.firstIndex(of: key)`, whereas standard JSON parsers (Python `json`, Rust `serde_json`, JavaScript `JSON.parse`) use last-wins. On duplicate keys (`{"type":"none","type":"dahai",...}`), `RiichiMjai` disagrees with libriichi/Python/Mortal.
- **Reproduction:** **Reproduced.** `Docs/Reviews/p3/CD-agy-repro/repro_gameflow_and_mjai.swift` → `[Finding 9: duplicate key type] parsed type=none (standard JSON last-wins would be 'dahai')`.
- **Proposed fix:** Use `keys.lastIndex(of: key)` (or reject duplicate keys during parsing).

---

### 10. [should-fix] `Mjai.decode` silently ignores wrong-typed values for `pai`, `tsumogiri`, `tehais`, `bakaze`, `names`, `reason`, `dealer_repeats`

- **Location:** `Sources/RiichiMjai/Mjai.swift:235-264`
- **Issue:** Unlike `actor`/`target`/`scores` (which throw `MjaiError` on type mismatch), wrong-typed fields like `"pai": 123` or `"tsumogiri": "nope"` are silently treated as `nil`. In `MjaiBot`, `"pai": 123` is misclassified as `illegal` instead of `malformed`, and `"tsumogiri": "nope"` on an otherwise valid discard is accepted with zero substitutions.
- **Reproduction:** **Reproduced.** `python3.14 Docs/Reviews/p3/CD-agy-repro/repro_json_validation.py`:
  - `[Finding 10a: int pai=123] substitutions malformed=0 illegal=1 ...`
  - `[Finding 10b: string tsumogiri='nope' accepted] substitutions malformed=0 illegal=0 timeout=0 crashed=0`
- **Proposed fix:** Whenever a key is present and non-null, require the expected JSON type and throw `MjaiError` on mismatch.

---

### 11. [should-fix] `Mjai.action` does not validate `ankan.consumed` length/kinds or `pon`/`chi`/`daiminkan` `pai`/`target`

- **Location:** `Sources/RiichiMjai/Mjai.swift:290-299`
- **Issue:** For `ankan`, `Mjai.action` checks only `c.first?.kind` without requiring `c.count == 4` or matching kinds, so `{"type":"ankan","actor":0,"consumed":["1m"]}` and `{"type":"ankan","actor":0,"consumed":["1m","9p","2s","E"]}` both resolve to `.ankan(1m)`. For `daiminkan`, `pai`/`target`/`consumed` are not validated at all.
- **Reproduction:** **Reproduced.** `Docs/Reviews/p3/CD-agy-repro/repro_gameflow_and_mjai.swift` → `[Finding 11: bogus ankan consumed] 1-tile=Optional(ankan:1m) mismatched=Optional(ankan:1m)`.
- **Proposed fix:** Require `c.count == 4 && c.allSatisfy { $0.kind == k }` for `ankan`, and validate `pai`/`target` when provided on calls.

---

### 12. [should-fix] `GameFlow.next` with `dealerRepeatBeforeTarget == false` ends the game on an abortive draw in all-last

- **Location:** `Sources/Riichi/Game.swift:111-118`
- **Issue:** When `rules.dealerRepeatBeforeTarget == false`, line 117 (`if target && !rules.dealerRepeatBeforeTarget { return (nil, .ends(.target)) }`) executes even when `abort == true`. An abortive draw (e.g. `kyuushu`) in all-last when the dealer (or anyone) already has ≥ 30,000 ends the game instead of repeating, contradicting design §5 ("if the dealer repeats by winning or by tenpai (not by an abortive draw)...").
- **Reproduction:** **Reproduced.** `Docs/Reviews/p3/CD-agy-repro/repro_gameflow_and_mjai.swift` → `[Finding 12: dealerRepeatBeforeTarget=false + abortive draw in S4] next=nil transition=ends(Riichi.GameEnd.target)`.
- **Proposed fix:** Guard line 117 with `if !abort && target && !rules.dealerRepeatBeforeTarget`.

---

### 13. [suggestion] `Mjai.encode` field order on `start_game` and `start_kyoku` differs slightly from design §6 table

- **Location:** `Sources/RiichiMjai/Mjai.swift:88-96`
- **Issue:** Design §6 lists `start_game` as `names, id` and `start_kyoku` as `bakaze, kyoku, honba, kyotaku, oya, dora_marker, scores, tehais`. `Mjai.swift` emits `id, names` and places `dora_marker` second in `start_kyoku`. Key order is fixed and deterministic, so this is only a minor doc/code mismatch.
- **Proposed fix:** Align either the design table or `Mjai.swift`.

---

### 14. [suggestion] `ChildProcess.send`/`readLine` treat `EINTR` on `read`/`write` as crashed, and `mj selfplay --seed -1` traps

- **Location:** `Sources/mj/MjaiBot.swift:38, 63`; `Sources/mj/Commands.swift:78-79`
- **Issue:** `write` and `read` returning `-1` with `errno == EINTR` are not retried (unlike `poll`), so a signal during I/O falsely marks the bot crashed. In `Commands.swift`, `UInt64(try o.int("seed", 0))` traps on negative values (`mj selfplay --seed -1` reproduced: `Fatal error: Negative value is not representable`) and rejects valid `UInt64` seeds `> Int.max`; `--games -1` traps on `0..<games`.
- **Proposed fix:** Retry `read`/`write` on `EINTR`; parse `--seed` as `UInt64` directly and validate `games >= 0`.
