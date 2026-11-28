# Source audit and verification

Upstream references below are relative to `libriichi/src/` at Mortal commit
`0cff2b52982be5b1163aa9a62fb01f03ce91e0d2`.

## Known differences

| Name | Source finding | Handling |
| --- | --- | --- |
| `triple_ron_abort` | `arena/board.rs` handles all three winners as ordinary multi-ron. Tenhou and the design abort. | Report the board divergence. An mjai draw does not identify the three ron decisions. |
| `first_draw_yakuman_stack` | `state/agent_helper.rs::agari_points` returns a single yakuman for tenhou/chiihou before inspecting the rest of the hand. | Report differing payments. |
| `four_riichi_extra_draw` | `arena/board.rs::step` checks the fourth accepted reach at the start of the next step. After acceptance it can first draw, or process the selected call. | Allow one arena-only `tsumo` immediately after the fourth acceptance paired with an immediate zero-delta draw. Count it. Other timing differences report. |
| `four_winds_before_reactions` | The arena aborts within the fourth `dahai` step, before any subsequent reactions or reach acceptance. The design gives ron priority (and notes none can occur on that fourth identical wind). Both default to no fourth stick here. | Source order recorded. |
| `four_kan_before_reach_acceptance` | The arena's four-kan abort test runs before the pending reach payment, except that ron wins first. The design accepts a reach before the four-kan abort. | Report the resulting event and payment differences. |
| `chained_kan_dora` | For open/added kan followed by added kan, the arena leaves the owed bit pending and emits `kakan`, then `dora`, then replacement `tsumo` if unrobbed. It emits no owed dora if the kakan is robbed. For open/added followed by closed, the arena emits owed `dora`, `ankan`, new `dora`, `tsumo`. For a post-kan discard, it emits `dora` immediately before `dahai`, so ron sees it. | The two unrobbed chains agree with §4.2. Board compares this order and every indicator; a missing dora is an error. |
| `kakan_eager_commit` | `state/update.rs::kakan` upgrades the pon and increments kans on announcement, before the robbing outcome. The arena increments its kan count then too, but leaves the indicator and replacement draw pending. The design defers committing the meld and count. | Report observable state or payment differences. |
| `furiten_on_window_event` | On a matching discard with yaku, `dahai` marks furiten on the next event; without yaku it marks furiten on the discard itself. `kakan` schedules it on the next event. This is driven by the cached wait set, which can omit exhausted waits. The design settles passed waits when the window closes. | Report state differences. |
| `temporary_furiten_reset` | `tsumo` does not clear `at_furiten`. A non-riichi own discard, or a kan path calling `update_waits_and_furiten`, recomputes it and clears the temporary component. A chi or pon alone does not clear it, but the following discard can. The design resets temporary furiten at the next own draw. | Report state differences. |
| `riichi_skipped_tsumo_ankan` | After accepted reach, `dahai` marks furiten on discarding a cached winning kind, but the riichi `ankan` path skips wait recomputation and does not mark a skipped winning draw. The design marks it even on a closed kan. | Report state differences if observable. |
| `visible_exhausted_waits` | `update_waits_and_furiten` excludes kinds with four concealed copies, and only stores a structural wait when fewer than four copies have been seen at the last recomputation. It still uses structural waits for own-discard furiten. The exhaustive draw uses cached shanten zero, so visible exhaustion alone does not invalidate formal tenpai. | Count a reference-only omission when the reference is a strict subset and every omitted kind is proven exhausted in that seat's view. |
| `cached_waits` | Waits are cached through draws, chi/pon until the following discard, and some riichi updates. The getter is not a fresh structural query for every event. Riichi eligibility and riichi discard candidates use shanten transitions rather than the current wait flags. | Report the other state differences. |
| `riichi_discard_projection` | `state/action.rs` has a generic discard flag. Contrary to a broad reading of design §8, `state/agent_helper.rs::discard_candidates_aka` **does** expose tenpai-preserving tile candidates after reach, separating red fives. It has no separate same-tile tsumogiri/from-hand bits. | Compare the projected physical tiles and validate the logged discard's tsumogiri marker. |
| `red_call_projection` | Chi direction, pon and kan flags do not enumerate red-five call payloads. The arena event does carry the concrete red tiles, and submitted calls are checked against the available physical tiles. | Compare projected flags and concrete logged calls. |
| `pao_open_sets` | `arena/board.rs::update_paos` counts open pons and minkans only, excluding prior closed kans; it records a single liable seat per winner and can overwrite it. Distribution uses the whole composite score and charges pao the honba, consistent with design Tenhou pao once liability is assigned. | Report different payments. |
| `idle_target_actor` | `PlayerState.update` uses the event actor or the observer's ID as `target_actor`, even when no reaction is offered. | Count unequal values only when neither side has a reaction flag and the event types match. |
| `deal_tile_order`, `consumed_tile_order`, `candidate_tile_order` | The tile arrays in these fields represent multisets. | Count normalized ordering differences by field class. |
| `scoring_detail` | Arena `hora` has neither yaku names nor han/fu. The lower-level `algo/agari.rs` calculator does expose aggregate han/fu for ordinary hands, contrary to a blanket claim that libriichi never exposes fu. Its point-only arena path and limit handling do not supply full scoring detail. | Compare arena payments and ura. |
| `game_end` | The game API generates its own walls and `end_game` has no event payload. | Check hand transitions and optional end-of-hand fields. Game ranking, residual sticks awarded at game end, oka and uma are out of scope. |

Closed-kan robbery is unavailable in libriichi, agreeing with design Tenhou.
Last-tile calls/kans, exclusion of haitei on rinshan, multi-ron honba and stick
assignment, and nagashi-as-draw settlement agree in the cited arena code.
Natural yakuman stack in the ordinary scorer, and the four variant double
yakuman described for Mahjong Soul are not separate multipliers in this
Tenhou-oriented implementation.

## Engine mjai field and ordering disagreements

These are comparisons with the source's dialect. Engine extensions can still
be useful to other mjai clients.

- **`start_game`.** `mjai/event.rs` has `names` (defaultable) and optional
  `seed: [nonce, key]`. `arena/result.rs::dump_json_log` includes the seed.
  The wire event has no `id`; the bot receives its seat at construction
  (`mjai/bot.rs`).
- **`start_kyoku`.** The core fields match. Upstream has no `wall` field,
  deals from its own seeded sequence, and dumps unmasked hands. `?` is a valid
  `Tile`, and the per-seat state reads only that seat's starting hand. The
  replacement draw uses ordinary `tsumo`, as the design says.
- **`reach_accepted`.** Only `actor` is native. It can also precede a
  late extra draw (or an accepted call) on the fourth reach. A four-kan abort
  can preempt an otherwise pending acceptance. Four winds runs before any
  acceptance, as the design's default describes. A ronned declaration discard
  gets no acceptance.
- **Dora and kans.** The unrobbed Tenhou dora orders in §4.2 match the arena.
  Its `dora` is before the post-kan `dahai`, not after a ron response.
  An added kan is applied to the state at the announcement even when it is
  later robbed. A fourth kan abort occurs after the discard and possible ron,
  before pending reach acceptance rather than after.
- **`hora`.** Only `actor`, `target`, optional `deltas`, and optional
  `ura_markers` are native. Arena results fill the two optional fields and
  supply an empty ura array for a non-riichi winner. `pai`,
  `uradora_markers`, `hora_tehais`, `yakus`, `fu`, `fan` and `scores`
  are extensions. The source emits one hora per winner in turn order, including
  all three in triple ron. It broadcasts neither the result hora nor the draw
  result to its own arena player states.
- **`ryukyoku`.** Only optional `deltas` is native. `reason`, `tenpais`,
  `tehais` and `scores` are extensions. Generated aborts all use a zero
  array without a reason. A nine-terminals reply may omit deltas.
- **`end_kyoku`, `end_game`.** Both are unit variants. `end_game.scores`
  is an extension. Game scores are returned separately in `GameResult`.
- **Bot replies and announcements.** The Rust/Python bot API returns an absent
  reply when it has no action, with optional `can_act` input gating. A process
  wrapper may emit a literal `none` event. Normal state updates clear candidates
  on announcements. `update_with_keep_cans` is a special log-validator option
  for `reach_accepted`, `dora` and `hora`.
- **Playback input.** `Docs/Design/engine.md` §8 refers to the decision trace,
  whereas this tool reads the unmasked event log. It cannot recover passes,
  suppressed or losing calls, or competing unlogged winning decisions.

## Verification status

Preparation and Rust formatting ran locally. Python comparison smoke tests
passed for identical traces, counted visible-exhausted waits, strict rejection
of that omission, a mismatched furiten flag and a missing row. The Rust
verification loop is blocked. `cargo fetch --locked` failed resolving
`index.crates.io` and the cache lacks even `anyhow`. The offline build failed
before compilation. `self_test.py` therefore reported that the release binary
was missing. The clean arena replay and the three corruption tests remain
unverified in this environment.

The checker can compare only outcome fields the arena produces or that can be
reconstructed from those fields and the wall. Draw reasons, revealed draw hands,
tenpai declarations as log payloads, detailed yaku breakdowns, and a last hand's
repeat decision without a result extension have no independent counterpart to
compare. The comparison script consumes legality snapshots from the same logs and
cannot infer whether an omitted action window would have changed the game.
