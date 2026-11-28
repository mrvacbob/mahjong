# mahjong

A riichi mahjong engine in Swift: scoring, legal moves, whole games under Mahjong
Soul and Tenhou rules, the mjai protocol, and a per-seat view of the table. Bots,
benchmarks for LLM players and a teaching site are planned on top of it. A Mercury
implementation of the hand-analysis core is kept as an independent cross-check.

## Layout

| Path | What |
|---|---|
| `Sources/Riichi/` | The engine library. No imports, no floating point. |
| `Sources/RiichiMjai/` | mjai JSON for events and bot replies |
| `Sources/mj/` | Command-line tool: line protocol, self-play, replay, log checking, bot adapters |
| `Sources/Mercury/` | Mercury implementation of the line-protocol operations, for differential testing |
| `Tests/` | Unit tests (`swift test`) |
| `Spec/rules.md` | Rules: Mahjong Soul ranked 4-player, with Tenhou differences |
| `Spec/formats.md` | The line protocol and its five operations |
| `Spec/wall.md` | Wall layout and the seeded shuffle, with test vectors |
| `Corpus/` | Line-protocol test cases: request line, then `= ` expected response |
| `Scenarios/` | Hand-written whole-round test cases (`Scenarios/FORMAT.md`) |
| `Tools/` | Corpus harness, scenario runner, cross-check drivers, real-log replay |
| `Tools/oracle_mj.py`, `Tools/Gen/` | Reference implementation and corpus generators built on the [mahjong](https://github.com/MahjongRepository/mahjong) Python library (MIT) |
| `AGPL/` | Tools built on Mortal's libriichi: two reference checkers and the Mortal bot wrapper. **AGPL-3.0, separate from everything else here.** See each README. |
| `Docs/Design/` | Design documents: the engine as built, the bot plan |
| `Docs/Notes/`, `Docs/Briefs/`, `Docs/Reviews/` | Working record: implementation notes, task briefs given to coding agents, and their reviews |

The language comparison that chose Swift (Swift, Mercury, Python and Haskell
entries, with its briefs and reviews) is on the `shootout` branch.

## Building and running the corpus

    make                # needs Swift 6; builds the Mercury cross-check too if `mmc` is installed
    make check          # unit tests, corpus (both implementations), scenarios

`mj` is any executable following the runner contract in `Spec/formats.md`.

`mj selfplay` runs bots against each other, including external mjai bots. Pass
`--length east` for East-only games, or `--scenario NAME` to play directed games that
reach rare branches in bulk (four winds, four riichi, triple ron, a robbed closed kan,
pao, nagashi, four kans by one seat, all-last positions). `Tools/libriichi_diff.sh`
and `Tools/mercury_diff.sh` run those games through the two cross-checks (see
`Docs/Notes/p3-closeout.md`).

`mj selfplay` writes referee-only files: the unmasked mjai log (`.jsonl`, with every
wall and hand), the trace (`.trace`, with the game seed and every decision), `--legal`
rows (all four seats' hands and waits), and `--requests` dumps. Keep them out of reach
of any player or bot. With an external bot at the table, each game draws a fresh seed
from the system unless `--seed` is given (which makes the walls predictable to the
bot and is for tests only).

`mj check-log` checks mjai logs from elsewhere; `Tools/reallogs.py` runs it over tar
shards of real game records (see `Docs/Notes/p3-reallogs.md`).

The reference tools expect the third-party sources checked out beside this repo, in
`../3p/mahjong` and `../3p/Mortal` (or set `MJ_ORACLE_PATH`).

## License

BSD 2-Clause (see `LICENSE`) for everything except `AGPL/`, which is built on
Mortal's libriichi and is AGPL-3.0; those are separate test and bot tools and no
engine code derives from them. Most of this repository was written by AI coding agents
(Claude, Codex, Gemini) under human direction.
