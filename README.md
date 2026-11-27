# mahjong

A riichi mahjong engine project: an engine (scoring, legal moves, game state), bot
players, benchmarks for LLM players, and a teaching site. Early days: a language
shootout chose Swift for the engine (see `shootout/RESULTS.md`), with a Mercury
implementation of the hand-analysis core kept as an independent cross-check. So far
the engine covers hand analysis (winning shapes, shanten, waits, scoring, legal
actions for one seat); the full game state machine is next.

## Layout

| Path | What |
|---|---|
| `Package.swift`, `Sources/Riichi/`, `Sources/mj/`, `Tests/RiichiTests/` | The Swift engine (library `Riichi`), its `mj` command-line tool, and its unit tests (`swift test`) |
| `crosscheck/mercury/` | Mercury implementation of the same operations, for differential testing |
| `spec/rules.md` | Rules: Mahjong Soul ranked 4-player, with Tenhou differences |
| `spec/formats.md` | Text protocol and the five operations each shootout entry implements |
| `spec/wall.md` | Wall layout and the seeded shuffle, with test vectors |
| `corpus/` | Test cases: request line, then `= ` expected response |
| `tools/harness.py` | Runs an implementation against the corpus |
| `tools/oracle_mj.py`, `tools/gen/` | Reference implementation and corpus generators built on the [mahjong](https://github.com/MahjongRepository/mahjong) Python library (MIT) |
| `agpl/mj-rs/` | Second reference built on Mortal's libriichi. **AGPL-3.0, separate from everything else here.** See its README. |
| `shootout/` | The finished language comparison (Swift, Mercury, Python, Haskell), kept for the record |
| `docs/briefs/`, `docs/reviews/` | Task briefs given to coding agents, and their reviews |

## Building and running the corpus

    ./build.sh          # needs Swift 6; builds the Mercury cross-check too if `mmc` is installed
    python3.14 tools/harness.py <path-to-mj> corpus/*.txt

`mj` is any executable following the runner contract in `spec/formats.md`.

`mj selfplay` (bots against each other, including external mjai bots) writes
referee-only files: the unmasked mjai log (`.jsonl`, with every wall and hand), the
trace (`.trace`, with the game seed and every decision), the `--legal` rows (all four
seats' hands and waits) and the `--requests` dumps. Keep them out of reach of any
player or bot. With an external bot at the table each game draws a fresh seed from
the system unless `--seed` is given (which makes the walls predictable to the bot;
for tests only). `mj check-log` checks mjai logs from elsewhere; `tools/reallogs.py`
runs it over tar shards of real game records (see `docs/notes/p3-reallogs.md`).

The reference tools expect the third-party sources checked out beside this repo, in
`../3p/mahjong` and `../3p/Mortal` (or set `MJ_ORACLE_PATH`).

## License

BSD 2-Clause (see `LICENSE`) for everything except `agpl/mj-rs/`, which is built on
Mortal's libriichi and is AGPL-3.0; it is a separate test-generation tool and no
engine code derives from it. Most of this repository was written by AI coding agents
(Claude, Codex, Gemini) under human direction.
