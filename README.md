# mahjong

A riichi mahjong engine project: an engine (scoring, legal moves, game state), bot
players, benchmarks for LLM players, and a teaching site. Early days: the current
work is a language shootout to choose what to write the engine in.

## Layout

| Path | What |
|---|---|
| `spec/rules.md` | Rules: Mahjong Soul ranked 4-player, with Tenhou differences |
| `spec/formats.md` | Text protocol and the five operations each shootout entry implements |
| `corpus/` | Test cases: request line, then `= ` expected response |
| `tools/harness.py` | Runs an implementation against the corpus |
| `tools/oracle_mj.py`, `tools/gen/` | Reference implementation and corpus generators built on the [mahjong](https://github.com/MahjongRepository/mahjong) Python library (MIT) |
| `agpl/mj-rs/` | Second reference built on Mortal's libriichi. **AGPL-3.0, separate from everything else here.** See its README. |
| `shootout/` | Implementations under comparison (Swift, Mercury, Python, Haskell) |
| `docs/briefs/`, `docs/reviews/` | Task briefs given to coding agents, and their reviews |

## Running the corpus

    python3.14 tools/harness.py <path-to-mj> corpus/*.txt

`mj` is any executable following the runner contract in `spec/formats.md`.

The reference tools expect the third-party sources checked out beside this repo, in
`../3p/mahjong` and `../3p/Mortal` (or set `MJ_ORACLE_PATH`).

## License

Not yet chosen for the project's own code (LGPL or BSD, to be decided after the
shootout). `agpl/mj-rs/` is AGPL-3.0. Most of this repository was written by AI
coding agents (Claude, Codex, Gemini) under human direction.
