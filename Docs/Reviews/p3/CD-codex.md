# Phase 3 packages C and D focused review

Reviewed HEAD `f6d5a19` against design §§5, 6 and 8, `Spec/rules.md` including its quoted Tenhou manual text, and the package author's notes. The JSON, bot-adapter and check-log input-hardening findings in [the prior review](CD-agy.md) are outside this review. Its finding 12 already covers abortive draws with `dealerRepeatBeforeTarget = false`.

## Findings

### 1. Should-fix · In-process callbacks reveal an opponent's private offer

[Round.swift:391–400](../../../Sources/Riichi/Round.swift#L391) stops after a discard only when someone has a legal response. The analogous kan branch is at [Round.swift:548–569](../../../Sources/Riichi/Round.swift#L548). [Driver.swift:82–90](../../../Sources/mj/Driver.swift#L82) publishes each step as a separate callback to every in-process player, including seats with a nil decision view. An observer can distinguish a discard followed immediately by a draw in one callback from the same two events split across callbacks. The direct view also exposes the retained phase in `table.reacting` to seats with an empty action list. [View.swift:122–127](../../../Sources/Riichi/View.swift#L122)

**Reproduced.** Tenhou seed 51, first hand. Swap wall slot 8 (seat 2's concealed `9p`) with slot 135 (unrevealed `8s`). Seat 0 discards its drawn `8s` in both cases. Seat 2 gains a response and passes. Seat 3 sees the same flat events, always has an empty action list, and has an identical view once the next player draws. Its callback sizes are `[3, 2]` and `[3, 1, 1]`, and its direct view immediately after the discard has `reacting == nil` and `reacting != nil` respectively. [Review.swift](CD-codex-repro/Review.swift)

**Fix.** Publish a flat event interface with a separate private prompt for the recipient. If a seat-facing API exposes intermediate table views, define the public discard and kan checkpoints from announced events independently of whether offers exist. The mjai child already sees a flat event sequence. Its scheduling can reveal a pause via elapsed time, but the reproduced leak needs no clock.

### 2. Blocker · Default self-play with external bots makes the wall predictable

`selfplay` defaults to seed 0 and increments the seed for each game. The public shuffle algorithm derives every wall from that seed and the hand number. Removing the seed from the message schema leaves the default game reproducible by the recipient. An explicit low-entropy seed can be matched against a seat's starting hand and the public dora marker. Consecutive game seeds also make subsequent games predictable once one seed is known. [Commands.swift:78, 98 at HEAD](../../../Sources/mj/Commands.swift#L82) · [Wall.swift:82–97](../../../Sources/Riichi/Wall.swift#L82)

**Reproduced.** A protocol-only mjai bot tried seeds 0–255 using an independent implementation of the shuffle and matched its masked opening hand and dora marker. It recorded seed 0 and all 136 wall tiles before its first discard. The harness compared that prediction with the privileged game log after play and every slot matched. This blocks using the default launch path for an arena with untrusted players. [cli.py](CD-codex-repro/cli.py)

**Fix.** Use independently generated, high-entropy private seeds for competitive bot games and keep reproducible explicit-seed mode for testing. Save each seed in the privileged replay artifact. Keep bot RNG state independent of the wall seed if an in-process player is ever given its RNG state. The current trusted built-ins are initialized by an invertible affine transformation of the game seed. [Commands.swift:66–74](../../../Sources/mj/Commands.swift#L66)

### 3. Suggestion · Label legality rows and other exports as privileged

`--legal` exports all four seats at every event. The location fields are public bookkeeping, but `x_hand` is the literal concealed hand plus draw. `waits`, `shanten`, `furiten`, `x_furiten` and the action flags/candidate lists expose private shape and response eligibility. The omniscient JSONL contains each wall and every draw, the trace contains the seed and all submitted decisions including passes, and `--requests` records private decision inputs and scoring requests. These exports are separate from the protocol pipes. They are privileged inputs for diagnostics. [Legality.swift:33–40, 59–67, 109–120](../../../Sources/mj/Legality.swift#L109) · [Driver.swift:27–42, 79, 99–111](../../../Sources/mj/Driver.swift#L27) · [CrossCheck.swift:27–54](../../../Sources/mj/CrossCheck.swift#L27)

**Reproduced.** Both presets' first `start_kyoku` legality rows contained four distinct `x_hand` values. The ordinary mjai bot test received only its masked opening. The child launcher provides no process-level isolation, so a deployment must separately restrict access to these files. The reproduction checked file contents and protocol delivery. [cli.py](CD-codex-repro/cli.py) · [MjaiBot.swift:18–24](../../../Sources/mj/MjaiBot.swift#L18)

**Fix.** Document the artifacts as referee-only and keep them outside player-accessible storage. If a seat-facing legality export is needed, emit only its row and avoid exposing privileged files or row positions from that interface.

### 4. Suggestion · An injected North 4 can wrap to East 1

The public `GameState` initializer accepts a supplied position and wall. On dealer rotation the flow advances a wind using the cyclic `Wind.next`, then compares the resulting wind with the extension cap. North therefore wraps to East and passes the cap check. A preset game starting in East 1 ends before dealing North 1. [Game.swift:100–125, 166–180](../../../Sources/Riichi/Game.swift#L100) · [Tile.swift:90–91](../../../Sources/Riichi/Tile.swift#L90)

**Reproduced.** Start a Tenhou game in North 4 on seed 0 with 25,000 per seat. Tsumogiri every tile and pass all calls. All four players are noten, scores stay level, and the game deals East 1 at honba 1 with `allLastAdvance`. The extension cap calls for ending or rejecting that injected starting position. [Flow.swift](CD-codex-repro/Flow.swift)

**Fix.** Check the current wind and whether the dealer advances before applying cyclic wind arithmetic. If positions beyond the configured extension are unsupported, enforce that at the game initializer and document it.

### 5. Should-fix · Custom score arithmetic can trap on wasm32

`Rules.oka` multiplies the difference of two unrestricted `Int` settings by four. `GameFlow.result` inherits that intermediate, and also multiplies sticks by 1,000 and combines scores, return points and uma with native-width arithmetic. Other large custom inputs can put similar pressure on honba progression, payments and round deltas. [Rules.swift:132–134](../../../Sources/Riichi/Rules.swift#L132) · [Game.swift:130–138](../../../Sources/Riichi/Game.swift#L130) · [RoundResult.swift:52–55](../../../Sources/Riichi/RoundResult.swift#L52) · [Score.swift:145–151](../../../Sources/Riichi/Score.swift#L145) · [Round.swift:635–636, 781–785](../../../Sources/Riichi/Round.swift#L781)

**Reproduced.** Tenhou with `returnPoints = 600_025_000`, scores `[30_000, 30_000, 20_000, 20_000]` and zero sticks. Native arm64 returns adjusted scores `[1800025000, -599985000, -600015000, -600025000]`. All four final numbers fit a signed 32-bit integer, but the intermediate oka is 2.4 billion and wasm32 traps in `Rules.oka`. The other overflow sites above are from inspection. [Flow.swift](CD-codex-repro/Flow.swift) · [wasm.sh](CD-codex-repro/wasm.sh)

**Fix.** Use fixed-width checked arithmetic for point values and intermediates, with validated bounds for configurable rules, honba, sticks and starting scores. Convert to native-width values only when the range is guaranteed.

### 6. Suggestion · A custom-rules driver trace serializes the wrong rules

The internal driver accepts arbitrary `Rules`, but its trace header writes `tenhou` only for an exact preset match and writes `mahjongsoul` for everything else. The reader reconstructs only the two presets. The current self-play CLI selects those presets, so this affects custom driver callers, including future East-only support. [Driver.swift:68–79, 127–147](../../../Sources/mj/Driver.swift#L68)

**Reproduced.** The production driver recorded East-only Tenhou at seed 0. Reading the trace selected South-length Mahjong Soul, and the replay driver failed with `illegal decision: seat 0 gave no decision`. [Review.swift](CD-codex-repro/Review.swift)

**Fix.** Encode the full effective rules in a versioned header before enabling custom games in this driver. Alternatively, reject custom recording with the preset-only trace version.

### 7. Suggestion · The replay verifier compares Unicode strings instead of bytes

The verifier uses Swift `String` equality, which treats canonically equivalent Unicode sequences as equal. The current CLI-generated labels are ASCII, but the trace reader accepts custom label text. [Commands.swift:160–172 at HEAD](../../../Sources/mj/Commands.swift#L164) · [Driver.swift:138](../../../Sources/mj/Driver.swift#L138)

**Reproduced.** A trace with bot name `café` replayed against the composed UTF-8 header. The test then wrote a decomposed header with different bytes and the CLI again reported `replayed=1 identical=1`. [cli.py](CD-codex-repro/cli.py)

**Fix.** Compare the generated UTF-8 against raw file bytes. Use the same byte equality for the in-process replay check.

## Area 1 · Hidden information checked

| Seat-facing data | Result |
|---|---|
| `start_game` | Names and the recipient's own id only. No seed field. The deterministic default enables seed inference in finding 2. |
| `start_kyoku` | Round wind and number, honba, sticks, dealer, scores and first dora are table facts. One deal is visible and the other three have 13 placeholders each. The masked overload cannot take wall or result extras. |
| `tsumo` including replacement draws | Actor is public and only that actor sees the tile. Replacement allocation, kan count and live-wall length follow public declarations and draws. |
| `dahai`, `chi`, `pon`, `daiminkan`, `ankan`, `kakan` | The named actor, target, discard/source, consumed tiles and tsumogiri information follow the publicly executed action. Ankan shows all four copies of a public kan kind, including the red copy for a five, which is inferable from the fixed tile set. Neither kan event carries the replacement tile, a future indicator or the responders. |
| `dora`, `reach`, `reach_accepted` | Dora carries one newly flipped indicator. Riichi events carry the actor and, on acceptance, public scores. Their emitted order follows the chosen rule for revealing owed dora and the public result of the discard. |
| `hora` | Actor, target, winning tile, winner's concealed hand, scores and deltas are revealed at settlement. The only ura are those paired with already shown dora and only for a winner in accepted riichi. The two wire keys encode the same array. Yaku, fu, fan and the typed `Scored` payment follow the revealed winning hand, its melds, the revealed indicators and the public win situation. Winners are emitted in turn order. |
| `ryukyoku` | Reason, scores, deltas and formal tenpai flags describe the result. Exhaustive draws reveal the tenpai hands as required by §6. Other hands, and all hands on aborts, use placeholders whose lengths follow public meld and draw state. |
| `end_kyoku`, `end_game` | The former has no seat-facing payload and the latter carries final scores. The adapter’s subsequent `end` message carries only its type. |
| `PlayerView` | Own seat, sorted hand, drawn tile, furiten and ordered legal actions. Public wind, kyoku, honba, sticks, dealer, scores, revealed dora, live count, melds, ponds and riichi. No back-reference to the wall or other hands. Legality can evaluate scoring using ura internally, but dora cannot turn a yakuless hand into a legal win. The discard or pending kan in `reacting` describes a public action, but the presence of the window leaks as in finding 1. |
| Event counts, ordering and legality diagnostics | No pass/losing-call event or responder count on the flat wire. Accepted calls, wins, abort reasons and tenpai disclosures legitimately change the public sequence. Driver callback boundaries contain extra information (finding 1). All-seat diagnostic rows intentionally expose private state (finding 3). |

Field paths checked in [View.swift:5–127](../../../Sources/Riichi/View.swift#L5), [Mjai.swift:62–150](../../../Sources/RiichiMjai/Mjai.swift#L62), [Round.swift:324–345, 642–668, 728–795](../../../Sources/Riichi/Round.swift#L642), [RoundLegal.swift:93–99, 180–217, 246–263](../../../Sources/Riichi/RoundLegal.swift#L180), [Score.swift:190–213](../../../Sources/Riichi/Score.swift#L190) and [MjaiBot.swift:114–137](../../../Sources/mj/MjaiBot.swift#L114).

The line protocol handles caller-supplied analysis inputs. The self-play checks and check-log report are operator outputs. The driver gives the privileged event/state hooks to log writers and observers, and the seat interface receives masked data. The debug scoring request takes ura and hypothetical honba from engine state and stays on the tool side. [main.swift:78–158](../../../Sources/mj/main.swift#L78) · [Driver.swift:7–17, 73–90](../../../Sources/mj/Driver.swift#L73) · [Round.swift:686–700](../../../Sources/Riichi/Round.swift#L686)

The swap test stepped full games using production `GameState` and built-in bot policies. It asserted equality of all masked events, serialized mjai messages, callback batches and complete observer decision views. Of 256 baseline seeds, 247 supported a distinct first-hand swap between unrevealed dora and ura slots that would only be exposed by the fourth kan. Another 24 valid first walls forced a public nine-terminals opening abort, allowing a distinct concealed-tile swap across two opponents, and a separate swap between the undrawn last live tile and an unused replacement. Both variants then played the entire rest of the game. The ordinary games rotate the observer seat and alternate preset and policy. The directed discard test holds the public actions and flat stream fixed and demonstrates where callback equality fails. The property covers the exercised swaps and releases, with rare branches also inspected in source.

## Area 2 · Game flow checked

Both presets and both lengths passed the transition controls for dealer repeat, honba across draws and dealer/non-dealer wins, and multi-ron with and without a dealer among the winners. The checks covered pre-all-last target scores, East 4/South 4 entry, sudden death at exactly 30,000, extension cap on dealer rotation, repeats at the extension cap, tobi below zero and continuation at zero. A last dealer tied with an earlier seat repeats, while a seat-0 extension dealer tied for first can stop. Leftover sticks are excluded from the target test and awarded by the existing rank order, then the two presets' return points, oka and uma apply.

The 30,000 and repeat ordering matches the quoted Tenhou text in `Spec/rules.md` §5.8. An actual South 4 nagashi sequence finished on `[33000, 23000, 17000, 27000]`. The dealer repeated when testing after payment and stopped as pre-payment first place with the switch off. This verifies the engine's toggle. The client behavior remains unverified in the rules spec. Turning off repeat priority also ended a non-abortive all-last repeat on another player's target as expected for that setting. The only new flow discrepancy found was the injected North 4 in finding 4. [Game.swift:68–138, 223–250](../../../Sources/Riichi/Game.swift#L68) · [RoundResult.swift:50–55](../../../Sources/Riichi/RoundResult.swift#L50) · [Flow.swift](CD-codex-repro/Flow.swift)

## Area 3 · Determinism checked

The shuffle and built-in RNG use explicit wrapping `UInt64` arithmetic and reduce to small bounds before converting to `Int`. Tile count masks use fixed-width storage and explicitly truncate only when extracting small counts. Decomposition, waits, actions, rank ties, answer traversal, score tie-breaking and yaku output have fixed traversal or canonical sorting. Set membership and counts do not drive output order. The set and dictionary data that feed textual lists are sorted or used as keyed lookups. The JSON writer traverses ordered fields and arrays. Inspection found no pointer-order dependency. [Wall.swift:3–43, 82–97](../../../Sources/Riichi/Wall.swift#L3) · [Tile.swift:172–191](../../../Sources/Riichi/Tile.swift#L172) · [RoundLegal.swift:1–24](../../../Sources/Riichi/RoundLegal.swift#L1) · [Score.swift:78–105](../../../Sources/Riichi/Score.swift#L78) · [Legality.swift:109–120](../../../Sources/mj/Legality.swift#L109) · [CrossCheck.swift:38–45](../../../Sources/mj/CrossCheck.swift#L38)

The CLI emits elapsed-time metrics, and external scheduling or timeouts can change which action a live child submits or which fallback is used. Replay consumes the recorded decisions directly and bypasses those sources of variation. Across 96 preset games, native traces, logs and legality exports matched byte-for-byte over three independent processes, including one run with deterministic hashing enabled. All 96 traces replayed successfully in fresh CLI processes. Native arm64 and wasm32 matched three complete wall vectors and the directed flow controls. Eight complete games run through the portable driver also had byte-identical traces, replayed JSONL and legality exports across architectures, including games seeded with `UInt64.max`. The tested preset paths were clean. The custom-value arithmetic, arbitrary-rules header and Unicode byte-check issues are findings 5–7. [Commands.swift:99–102, 131–159 at HEAD](../../../Sources/mj/Commands.swift#L131) · [MjaiBot.swift:46–59, 114–128](../../../Sources/mj/MjaiBot.swift#L46) · [cli.py](CD-codex-repro/cli.py) · [wasm.sh](CD-codex-repro/wasm.sh)

## Running the reproductions

From the repo root, run `PYTHON=python3.14 sh Docs/Reviews/p3/CD-codex-repro/run.sh` or omit `PYTHON` on hosts with a working `python3`. Then run `sh Docs/Reviews/p3/CD-codex-repro/wasm.sh` with Node and the Swift toolchain matching the installed WASI SDK on `PATH`. The local run used Swiftly's Swift 6.4.3 for wasm32 and set `NATIVE_SWIFTC=/usr/bin/swiftc` to link against the arm64 modules built by the first script. Both scripts accept `SOURCE_ROOT` to compile the same harness against another checkout.

The final native harness used a clean detached worktree at HEAD in a temporary local clone. The workspace's read-only Git metadata prevented creating a worktree directly, and a prior compile of the live tree stopped when the concurrently edited `CheckLog.swift` changed. Line numbers describe HEAD. Concurrent edits can shift links in the working tree.
