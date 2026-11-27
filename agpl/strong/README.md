# strong (Mortal mjai bot)

Standalone wrappers and build scripts for running strong external riichi mahjong
engines (starting with Mortal) as child processes of `./mj` over the newline-delimited
JSON `mjai` protocol. The Swift engine does not link to, embed, or copy from any code
here; it communicates only over stdin/stdout pipes (`Sources/mj/MjaiBot.swift`).
Licensed under **AGPL-3.0-or-later** ([LICENSE](LICENSE)).

## Layout and disk placement

The Python virtual environment, `uv` caches, Cargo cache, and model weights are kept
on the external volume under `/Volumes/Psyche/mahjong/strong/` (not in this repository
and not on the internal disk). The local Rust/Python build copy lives in
`agpl/strong/build/`, which is git-ignored. The upstream checkout at `../../../3p/Mortal`
(commit `0cff2b52982be5b1163aa9a62fb01f03ce91e0d2`) is treated as strictly read-only.

## Checkpoint

- **Source:** [`haor/Mortal-S42`](https://huggingface.co/haor/Mortal-S42) (`weights/s42-inference.pth`, 41.6 MB, Apache-2.0 weights; Mortal v4, 40 blocks, 192 channels, 10,835,631 params).
- **Local path:** `/Volumes/Psyche/mahjong/strong/weights/s42-inference.pth`
- **SHA-256:** `e5f6955b6f19007fd65315e53291b36994493046bc118b991b959e9dc596d660` (matches upstream `SHA256SUMS.txt`).
- **Safety:** `mortal_bot.py` loads checkpoints **only** with `torch.load(..., map_location="cpu", weights_only=True)` and never falls back to `weights_only=False`.

## Exact reproduction steps (macOS arm64)

Prerequisites: Rust/Cargo 1.100, `uv`, Swift 6.4 (`./build.sh` to build `./mj`).

1. **Create the Python 3.12 environment on `/Volumes/Psyche` and build `libriichi`:**

   ```sh
   sh agpl/strong/build_mortal.sh
   ```

   This creates `/Volumes/Psyche/mahjong/strong/.venv` (CPython 3.12.16, `torch==2.15.0`,
   `numpy==2.5.5`), copies `Cargo.toml`, `Cargo.lock`, `libriichi/`, `exe-wrapper/`,
   `mortal/model.py`, and `mortal/engine.py` from `../3p/Mortal` into `agpl/strong/build/`,
   compiles `libriichi` in release mode (`--locked`) against the venv's Python, and copies
   `agpl/strong/build/target/release/libriichi.dylib` to `agpl/strong/build/mortal/libriichi.so`.

2. **Download and verify the checkpoint:**

   ```sh
   mkdir -p /Volumes/Psyche/mahjong/strong/weights
   curl -fSL https://huggingface.co/haor/Mortal-S42/resolve/main/weights/s42-inference.pth \
     -o /Volumes/Psyche/mahjong/strong/weights/s42-inference.pth
   echo "e5f6955b6f19007fd65315e53291b36994493046bc118b991b959e9dc596d660  /Volumes/Psyche/mahjong/strong/weights/s42-inference.pth" \
     | shasum -a 256 -c -
   ```

3. **Build `./mj` (if not already built) and run 4 Tenhou games against `eager`:**

   ```sh
   ./build.sh
   MORTAL_STATS_FILE=/Volumes/Psyche/mahjong/strong/smoke-stats.jsonl \
     ./mj selfplay --rules tenhou --games 4 --bots eager \
     --seat "0=mjai:/Volumes/Psyche/mahjong/strong/.venv/bin/python agpl/strong/mortal_bot.py" \
     --out /Volumes/Psyche/mahjong/strong/smoke-out --check --quiet
   ```

## Verification results (2026-11-27, Apple Silicon CPU)

Run: 4 Tenhou hanchan, Mortal (`s42-inference.pth`) in seat 0 vs three built-in `eager` bots (`--check` enabled: invariants, byte-identical trace replay, and `check-log` all passed):

- **Games / hands / total table decisions:** 4 games, 47 hands, 3,191 total decisions (880 Mortal decisions).
- **Substitutions:** `malformed=0 illegal=0 timeout=0 crashed=0 unbound=0`.
- **Mortal placements:** `1, 1, 1, 1` (average placement **1.00**; final scores `51100`, `66700`, `59000`, `53400`).
- **Speed:** `8.01s` total wall time (`0.5 games/s`, ~`2.0s/game` including Python + PyTorch startup); checkpoint load `~0.041s/game`; **0.00705 s/decision (7.05 ms/decision)** across 880 decisions (`6.2001s` total `bot.react` time).
- **Non-zero seat check:** 1 additional Tenhou hanchan with Mortal in seat 2 (`--seat 2=mjai:... --check`) completed in `1.72s` with `0` substitutions and `invariants ok`, confirming seat binding from `start_game.id`.

## Notes and issues encountered

1. **Python version (PyO3 0.25 vs Python 3.14):** `libriichi` pins `pyo3 = "0.25"`, which predates Python 3.14. Creating a Python 3.12 venv via `uv` avoids ABI3 forward-compatibility workarounds and matches both PyTorch wheels and Mortal's upstream `environment.yml`.
2. **macOS `.dylib` -> `.so` rename:** Cargo compiles the `cdylib` target `name = "riichi"` to `target/release/libriichi.dylib`, while CPython expects `.so` for extension modules. `build_mortal.sh` copies it to `build/mortal/libriichi.so`.
3. **Upstream `mortal.py` protocol mismatch:** Upstream `mortal/mortal.py` takes `<ID>` as a CLI argument, prints *nothing* when `bot.react(line)` returns `None`, and passes every line to `libriichi::mjai::Bot`. Our adapter (`Sources/mj/MjaiBot.swift`) sends `id` inside `start_game`, strictly reads one JSON line per event (`{"type":"none"}` when idle), and sends `{"type":"end"}` on shutdown (which `libriichi`'s serde `Event` enum does not recognize). `mortal_bot.py` handles all three cleanly.
4. **Inference-only checkpoint keys:** `haor/Mortal-S42`'s `weights/s42-inference.pth` contains only `{'mortal', 'current_dqn'}` (omitting `config` and `timestamp` expected by upstream `mortal.py`). `mortal_bot.py` supports both inference-only v4 (`40×192`) checkpoints and full training checkpoints with `state['config']`.
5. **Immediate `SIGTERM` on `finish()`:** `MjaiBot.finish()` writes `{"type":"end"}` and immediately calls `child.stop()` (`SIGTERM` to the process group). Consequently, any post-loop cleanup after reading `{"type":"end"}` can be raced by `SIGTERM`; `mortal_bot.py` flushes `MORTAL_STATS_FILE` upon receiving `end_game` *before* writing the `{"type":"none"}` reply.
6. **No engine adapter bugs found:** Zero changes to `Sources/` were needed; the existing `MjaiBot.swift` and `RiichiMjai` dialect worked cleanly with `libriichi` across all 5 verified Tenhou games (58 hands).
