#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Standalone Mortal mjai bot process for CPU inference.

Protocol (matching Sources/mj/MjaiBot.swift):
- Reads one mjai JSON event per line on stdin.
- Writes exactly one mjai JSON reply per line on stdout
  ({"type":"none"} when the bot has nothing to do).
- Takes its seat (0..3) from the start_game event's `id` field.
- Exits cleanly on {"type":"end"} or EOF.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILD_MORTAL = HERE / "build" / "mortal"
if str(BUILD_MORTAL) not in sys.path:
    sys.path.insert(0, str(BUILD_MORTAL))

DEFAULT_WEIGHTS = Path("/Volumes/Psyche/mahjong/strong/weights/s42-inference.pth")


def load_engine(weights_path: Path, *, quick_eval: bool = True):
    import torch
    from engine import MortalEngine
    from model import Brain, DQN

    state = torch.load(weights_path, map_location="cpu", weights_only=True)
    if not isinstance(state, dict) or "mortal" not in state or "current_dqn" not in state:
        raise ValueError(f"Unexpected checkpoint keys: {sorted(state.keys()) if isinstance(state, dict) else type(state)}")

    if "config" in state:
        cfg = state["config"]
        version = int(cfg["control"].get("version", 4))
        num_blocks = int(cfg["resnet"]["num_blocks"])
        conv_channels = int(cfg["resnet"]["conv_channels"])
    else:
        # Inference-only checkpoint (e.g. haor/Mortal-S42 weights/s42-inference.pth)
        version = 4
        num_blocks = 40
        conv_channels = 192

    brain = Brain(version=version, num_blocks=num_blocks, conv_channels=conv_channels).eval()
    dqn = DQN(version=version).eval()
    brain.load_state_dict(state["mortal"], strict=True)
    dqn.load_state_dict(state["current_dqn"], strict=True)

    return MortalEngine(
        brain,
        dqn,
        is_oracle=False,
        version=version,
        device=torch.device("cpu"),
        enable_amp=False,
        enable_quick_eval=quick_eval,
        enable_rule_based_agari_guard=True,
        name="mortal",
        boltzmann_epsilon=0,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Mortal mjai bot (stdin/stdout JSONL, CPU)")
    parser.add_argument(
        "--weights",
        type=Path,
        default=Path(os.environ.get("MORTAL_WEIGHTS", str(DEFAULT_WEIGHTS))),
        help="Path to Mortal .pth checkpoint (loaded with weights_only=True)",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=int(os.environ.get("MORTAL_THREADS", "0")),
        help="Optional torch.set_num_threads value (0 = PyTorch default)",
    )
    parser.add_argument(
        "--no-quick-eval",
        action="store_true",
        help="Disable enable_quick_eval (always run neural net even with 1 legal action)",
    )
    args = parser.parse_args()

    import torch
    if args.threads > 0:
        torch.set_num_threads(args.threads)

    from libriichi.mjai import Bot

    t_load0 = time.perf_counter()
    engine = load_engine(args.weights, quick_eval=not args.no_quick_eval)
    t_load = time.perf_counter() - t_load0

    bot: Bot | None = None
    decisions = 0
    decision_time = 0.0
    events_seen = 0
    stats_file = os.environ.get("MORTAL_STATS_FILE")

    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        ev = json.loads(line)
        ev_type = ev.get("type")

        if ev_type == "end":
            break

        if ev_type == "start_game":
            seat = ev.get("id")
            if not isinstance(seat, int) or seat not in range(4):
                raise ValueError(f"start_game missing valid integer id (0..3): {line}")
            bot = Bot(engine, seat)

        if bot is None:
            raise RuntimeError(f"Received {ev_type!r} before start_game")

        events_seen += 1
        t0 = time.perf_counter()
        reaction = bot.react(line)
        dt = time.perf_counter() - t0

        if ev_type == "end_game" and stats_file:
            rec = {
                "seat": seat,
                "load_s": round(t_load, 4),
                "events": events_seen,
                "decisions": decisions,
                "decision_time_s": round(decision_time, 4),
                "s_per_decision": round(decision_time / decisions, 6) if decisions else 0.0,
            }
            with open(stats_file, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec) + "\n")

        if reaction is not None:
            decisions += 1
            decision_time += dt
            sys.stdout.write(reaction + "\n")
        else:
            sys.stdout.write('{"type":"none"}\n')
        sys.stdout.flush()

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(0)
    except KeyboardInterrupt:
        raise SystemExit(0)
