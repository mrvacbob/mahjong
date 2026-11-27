# libriichi-check

A standalone Rust command-line tool for replaying unmasked Tenhou-rule mjai logs
and exporting per-seat legality from Mortal's real arena and player state. It
communicates with the engine through JSONL. The engine does not link to this
crate. Licensed under AGPL-3.0-or-later ([license](LICENSE)).

## Build and self-test

Run from `agpl/libriichi-check/`. The preparation step requires the sibling
checkout at `../../../3p/Mortal`, pinned to commit
`0cff2b52982be5b1163aa9a62fb01f03ce91e0d2`. It copies the crate locally and makes
its Rust arena and poll result public. It leaves the upstream checkout untouched.
The local copy contains the full upstream code and data tables.

Use Rust/Cargo 1.100 and a CPython 3.13 development installation with a linkable
`libpython`. PyO3 0.25 predates Python 3.14. The binary embeds Python because
libriichi always depends on PyO3, but the checker does not import a Python module or
use Python NumPy at runtime. A Python virtual environment is unnecessary.

```sh
python3.14 -B prepare.py
export CARGO_HOME="$PWD/.cargo-cache"
cargo fetch --locked
export PYO3_PYTHON="$(command -v python3.13)"
cargo build --release --offline --locked
python3.14 -B self_test.py
```

Only `cargo fetch` needs network access. On a machine with only CPython 3.14,
PyO3 provides this forward-compatibility path. Verified 2026-11-27 on macOS
arm64 with Homebrew CPython 3.14: build and self-test pass.

```sh
PYO3_PYTHON="$(command -v python3.14)" PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1 \
  cargo build --release --offline --locked
```

The self-test generates 200 East games through the arena using Mortal's
`Tsumogiri` agent and a directed opening-ankan hand, then checks the clean logs
and independently mutates a discard, a draw payment and a dora announcement.
It asserts the corrupted files exit 1 and report the mutated index. Pass a
different game count as the first argument to the script if desired.

## Replay and compare

```sh
target/release/libriichi-check check a.jsonl b.jsonl > libriichi.jsonl
python3.14 -B compare.py engine.jsonl libriichi.jsonl
```

`check` accepts `-` for stdin. Each file contains one or more hands, in game
order, optionally framed by `start_game` and `end_game`. Supply paths in lexical
order for the streaming comparer. Each `start_kyoku.wall` carries 136 physical
tiles in design §3 order. The deal is in dealer order. The tool derives the
hands and initial marker from the wall, validates the physical set, and compares
them with the header. Four red-free copies may occur for non-fives. The three
fives each have three ordinary copies and one red (`5mr`, `5pr`, `5sr`).

Arena replay checks all typed mjai fields with the order of tiles within a hand
or a consumed group normalized. It also checks the added `scores` at
`reach_accepted`, `hora` and `ryukyoku` when supplied, along with `hora.pai`
and `hora.uradora_markers`. Scores on successive `hora` rows are cumulative
through that winner. Other extension fields are accepted. It independently
folds riichi deposits and result deltas and checks final scores and sticks
against the arena's result. The next hand's header checks scores, sticks, honba
and dealer rotation. To assert those results even on an isolated or final hand,
include these optional fields on `end_kyoku`.

- `scores` and `deltas` are four integers in seat order. The latter is the total
  hand change including accepted riichi deposits.
- `kyotaku_left` is the stick count after the hand.
- `dealer_repeats` is the hand's repeat decision before game-end rules.

Diagnostics and totals are JSON on stderr. A difference has `file`, `hand`,
`event_index`, `seat`, `log` and `libriichi`. A table-level mismatch uses a
null seat. A missing event uses null for its value. The first unexplained
difference per hand is reported. For continuity errors the previous hand is
identified and the next header is addressed as the event after `end_kyoku`.
The process exits 1 on an unexplained difference.

### Legality JSONL

The checker emits four objects per event from `start_kyoku` through
`end_kyoku` for each hand that passes board replay. The game envelope has no
hand or turn state. The engine should emit the same row identity and payload
and write rows in ascending `(file, hand, event_index, seat)` order.

| Field | Value |
| --- | --- |
| `file` | Exact input path string (or `-`) |
| `hand` | 1-based hand ordinal within the file |
| `event_index` | 0-based event ordinal within the hand |
| `seat` | Absolute seat, 0–3 |
| `event_type` | The mjai `type` |
| `flags` | Booleans `can_discard`, `can_chi_low`, `can_chi_mid`, `can_chi_high`, `can_pon`, `can_daiminkan`, `can_kakan`, `can_ankan`, `can_riichi`, `can_tsumo_agari`, `can_ron_agari`, `can_ryukyoku` and absolute integer `target_actor` |
| `discard` | Legal physical tile names, including separate red candidates, or empty outside discard windows |
| `ankan`, `kakan` | Candidate tile kinds, with red projected to ordinary five |
| `waits` | Libriichi's cached wait kinds with its visible-tile rules |
| `shanten` | Libriichi's `real_time_shanten()`, including its 3n+2 adjustment |
| `furiten` | Libriichi's current combined Boolean |
| `visible_exhausted` | Reference-only evidence listing kinds with all four copies visible to the seat |

For chi flags, low/mid/high refers to the position of the **called** tile in
the sequence. Pass is implicit when any chi, pon, daiminkan or ron is possible.
Project distinct tsumogiri and from-hand discards to the same physical tile name.
Project distinct red call payloads to their shared action flag. An event
announcement clears the flags when using upstream's ordinary `PlayerState.update`.
The status fields are snapshots of libriichi even on events with no action.

The comparison reports one unexplained difference per hand with both values
and totals for all observed filters. Use `--strict` to disable the contextual
idle-target and exhausted-wait allowances. Tile order is compared as a multiset.
See [NOTES.md](NOTES.md) for the source audit and the scope of each difference.
