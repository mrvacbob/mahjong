# Scenario File Format

Each scenario lives in a single plain-text file `scenarios/<name>.scn`.
`tools/scenario.py` validates every scenario and expands it to JSON (including
the complete 136-tile wall in the layout of `docs/design/engine.md` §3) so the
engine's test runner only needs a JSON parser.

## Syntax

- UTF-8 plain text, line-oriented.
- Comments begin with `#` (full-line or trailing) and are ignored.
- Blank lines are ignored.
- Sections begin with `[section]` on its own line.
- Inside `[meta]`, `[round]`, `[wall]`, and `[expect*]`, lines are `key: value`.
- Inside `[steps*]`, each line is one step or assertion.
- Tiles use **mpsz** notation (`spec/formats.md`): `1m`–`9m`, `1p`–`9p`,
  `1s`–`9s`, `1z`–`7z` (`E S W N haku hatsu chun`), and `0m`, `0p`, `0s` for
  red fives. Tile lists may be compact (`123m05p7z`) or space-separated
  (`1m 2m 3m`).

---

## Sections

### `[meta]`

Required metadata for the scenario.

| Key | Required | Values |
|---|---|---|
| `name` | yes | Identifier matching the filename stem (`<name>.scn`). |
| `title` | yes | Short one-line description. |
| `rules` | yes | `mahjongsoul`, `tenhou`, or `both`. |
| `source` | yes | Rule reference(s), e.g. `engine.md §4.2, rules.md §4.15`. |
| `unverified` | no | Present if the expected behaviour is unverified in a client; value cites `rules.md §5` item(s). |

### `[round]`

Initial round and game context. All keys except `scores` have defaults.

| Key | Default | Values |
|---|---|---|
| `game_length` | `south` | `east` (Tonpuu) or `south` (Hanchan). |
| `wind` | `E` | Round wind (`bakaze`): `E`, `S`, `W`, `N`. |
| `round` | `1` | Round number (`kyoku`): `1`–`4`. |
| `honba` | `0` | Non-negative integer. |
| `sticks` | `0` | Riichi sticks already on the table (`kyotaku`). |
| `dealer` | `round - 1` | Starting dealer seat index (`0`–`3`, `oya`). |
| `scores` | `25000 25000 25000 25000` | Four integers for seats `0 1 2 3`. |

### `[wall]`

Specifies starting hands, live draws, replacement draws, and indicators.
Anything unspecified is filled deterministically from the remaining unused
tiles of the 136-tile set in canonical order (`1m..4m, 0m, 5m..9m, 1p..9p,
1s..9s, 1z..7z`), filling unspecified slots in wall order: live draws
(`52..121`), rinshan (`122..125`), dora (`126..130`), ura (`131..135`).

| Key | Required | Meaning |
|---|---|---|
| `hand 0` .. `hand 3` | yes | Exact 13-tile starting hand for each seat `0`–`3`. |
| `dora` | yes | 1 to 5 dora indicators in order revealed (wall indices `126..130`). |
| `ura` | no | 0 to 5 ura indicators matching `dora` (wall indices `131..135`). |
| `rinshan` | no | 0 to 4 replacement draws in order drawn (wall indices `122..125`). |
| `draws` | no | Live draws in order from live-draw index `0` (wall index `52`). May be repeated; lines concatenate. |
| `draw_at <idx>` | no | Places tile(s) starting at 0-based live-draw index `<idx>` (`0`–`69`, wall index `52 + idx`). Must not overlap `draws` or another `draw_at`. |

**Wall layout (`docs/design/engine.md` §3):**
- `0..51`: Deal in dealer order (`(dealer + 0..3) % 4`): three rounds of 4 tiles each, then 1 tile each (dealer's 13 are `0..3, 16..19, 32..35, 48`).
- `52..121`: 70 live draws in order.
- `122..125`: 4 replacement (rinshan) tiles in order drawn.
- `126..130`: 5 dora indicators in order revealed.
- `131..135`: 5 ura indicators matching the dora indicators.

### `[steps]` (and optional `[steps.mahjongsoul]`, `[steps.tenhou]`)

Ordered list of decisions and mid-round assertions. If `rules: both` and the
rulesets diverge mid-round, shared prefix steps go in `[steps]` and per-ruleset
continuation steps go in `[steps.mahjongsoul]` and `[steps.tenhou]`.

#### Turn actions (`.turn` phase)

- `<seat> discard <tile>` — discard `<tile>` from concealed hand (`tsumogiri=false`).
- `<seat> tsumogiri` — discard the just-drawn tile (`tsumogiri=true`). Optionally `<seat> tsumogiri <tile>` to document and validate the expected drawn tile.
- `<seat> riichi` — declare riichi (moves to `.turn(seat, .riichiDeclared)`; the next step must be `<seat> discard <tile>` or `<seat> tsumogiri`).
- `<seat> tsumo` — win by self-draw.
- `<seat> ankan <kind>` — closed kan of `<kind>` (e.g. `0 ankan 1m`).
- `<seat> kakan <tile>` — added kan using exact `<tile>` (e.g. `0 kakan 0m` or `0 kakan 5m`).
- `<seat> kyuushu` — abortive draw (nine terminals/honors) on first draw.

#### Window resolutions (`.reactions` or `.robbing` phase)

- `window: <seat>=<action>, ...` — simultaneous answers from every seat with a non-empty `legalActions` in the current window (including passes that matter).
  - `<action>` is one of:
    - `ron`
    - `pon:<two tiles>` (e.g. `pon:55m`, `pon:05m`)
    - `daiminkan`
    - `chi:<two tiles>` (e.g. `chi:45m`, `chi:40m`)
    - `pass`

#### Fast-forward helper

- `auto_tsumogiri <n>` — repeats `<n>` turns: the active seat tsumogiris its drawn tile, and if any reaction window opens, every asked seat answers `pass`. Useful for reaching the end of the live wall without listing 60+ trivial discards.

#### Assertions

Evaluated at the current state before the next action:

- `assert_legal <seat>: <action>` — `<action>` must be in `legalActions(for: seat)`.
- `assert_illegal <seat>: <action>` — `<action>` (or any action of that kind, e.g. `ron`, `chi`, `riichi`, `ankan`, `kakan`, `daiminkan`, `discard:4m`, `chi:56m`) must NOT be in `legalActions(for: seat)`.
- `assert_furiten <seat>: true | false` — seat's furiten flag must match.
- `assert_not_asked <seat>` — `legalActions(for: seat)` must be empty in the current window.

### `[expect]` (or `[expect.mahjongsoul]` and `[expect.tenhou]`)

When `rules` is `mahjongsoul` or `tenhou`, use `[expect]`. When `rules: both`,
use `[expect.mahjongsoul]` and `[expect.tenhou]`.

| Key | Required | Meaning |
|---|---|---|
| `outcome` | yes | `ron`, `tsumo`, `exhaustive_draw`, or `abortive_draw`. |
| `abort_reason` | if abort | `kyuushu`, `suufon_renda`, `suucha_riichi`, `suukaikan`, or `sanchahou`. |
| `winners` | if win | Comma-separated winning seat indices in turn order from discarder (or `[tsumo_seat]`). |
| `win <seat>` | no | Per-winner scoring check: `han=<n> fu=<n> yaku=<list>` or `yakuman=<n> yaku=<list>` (yaku names from `spec/formats.md`). |
| `tenpai` | if exhaustive | Comma-separated tenpai seat indices, or `-`. |
| `nagashi` | no | Comma-separated nagashi mangan seat indices, or `-`. |
| `deltas` | yes | Four integer point changes for seats `0 1 2 3` (before leftover game-end sticks). |
| `scores` | no | Four integer post-round scores for seats `0 1 2 3` (`initial + deltas`). |
| `sticks` | yes | Riichi sticks remaining on the table after the round. |
| `honba` | yes | Honba count for the next round. |
| `dealer_repeats` | yes | `true` or `false`. |
| `events` | no | Exact sequence of mjai event types (with optional `(...)` detail, e.g. `reach(0), dahai(0), reach_accepted(0), tsumo(1)`) from `start_kyoku` through `end_kyoku`. |
| `events_order` | no | Ordered subsequence of mjai events that must appear in that order (for fast-forwarded rounds). |
| `game_ended` | no | `true` or `false` (for game-flow / end-of-game scenarios). |
| `next_wind` | no | Expected next round wind when `game_ended: false`. |
| `next_round` | no | Expected next round number (`1`–`4`) when `game_ended: false`. |
| `next_dealer` | no | Expected next dealer (`0`–`3`) when `game_ended: false`. |
| `final_scores` | no | Four integer scores after game-end leftover sticks go to 1st place. |
| `final_ranks` | no | Four seat indices ordered 1st to 4th (e.g. `0 1 2 3`). |
| `adjusted_scores` | no | Four integer adjusted scores (in raw points: `final_score - return_points + oka_bonus + uma * 1000`). |

---

## JSON Expansion

Running `python3.14 tools/scenario.py scenarios/<name>.scn` writes JSON to stdout:

```json
{
  "meta": { "name": "...", "title": "...", "rules": ["mahjongsoul", "tenhou"], "source": "...", "unverified": null },
  "round": { "game_length": "south", "wind": "E", "round": 1, "honba": 0, "sticks": 0, "dealer": 0, "scores": [25000, 25000, 25000, 25000] },
  "wall": ["1m", "... (136 tiles in engine.md §3 layout)"],
  "runs": {
    "mahjongsoul": {
      "steps": [ ... ],
      "expect": { ... }
    }
  }
}
```

Running `python3.14 tools/scenario.py --check` validates every `scenarios/*.scn`
file (syntax, 136-tile accounting, hand simulation of tile availability, point
conservation, and required fields).

Running `python3.14 tools/scenario.py --json-dir DIR [paths...]` writes every
scenario's JSON (as above) to `DIR/<name>.json`; a scenario that fails validation
is written as `{"name": ..., "error": ...}`. The engine's scenario runner
(`Tests/RiichiTests/ScenarioTests.swift`) uses this.
