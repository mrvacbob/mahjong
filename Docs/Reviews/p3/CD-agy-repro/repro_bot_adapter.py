#!/usr/bin/env python3
"""Repro for Finding 3: MjaiBot hangs forever on a bot ignoring SIGTERM,
and suffers unbounded buffering on output flood.
"""
import os, subprocess, sys, tempfile, time

MJ = os.path.abspath(".build/debug/mj")

with tempfile.TemporaryDirectory() as d:
    # Subtest A: bot ignores SIGTERM and never replies
    hang_bot = os.path.join(d, "hang_bot.py")
    with open(hang_bot, "w") as f:
        f.write(
            "import signal, time, sys\n"
            "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
            "for _ in sys.stdin:\n"
            "    time.sleep(60)\n"
        )
    t0 = time.monotonic()
    try:
        p = subprocess.run(
            [MJ, "selfplay", "--seed", "1", "--games", "1", "--bots", "eager",
             "--seat", f"0=mjai:python3.14 {hang_bot}", "--timeout", "150", "--quiet"],
            capture_output=True, text=True, timeout=2.5,
        )
        print(f"[SIGTERM-ignore] finished in {time.monotonic()-t0:.2f}s rc={p.returncode}")
    except subprocess.TimeoutExpired as e:
        print(f"[SIGTERM-ignore] REPRODUCED: mj hung for >2.5s despite --timeout 150ms!")
        # clean up any leftover python process if needed
        if e.stdout: print("  stdout:", e.stdout[:200])

    # Subtest B: bot floods 64MB without newline before sleeping
    flood_bot = os.path.join(d, "flood_bot.py")
    with open(flood_bot, "w") as f:
        f.write(
            "import sys\n"
            "chunk = 'a' * 65536\n"
            "for _ in sys.stdin:\n"
            "    try:\n"
            "        for _ in range(1000):\n"
            "            sys.stdout.write(chunk)\n"
            "            sys.stdout.flush()\n"
            "    except BrokenPipeError:\n"
            "        break\n"
        )
    t0 = time.monotonic()
    try:
        p = subprocess.run(
            [MJ, "selfplay", "--seed", "1", "--games", "1", "--bots", "eager",
             "--seat", f"0=mjai:python3.14 {flood_bot}", "--timeout", "300", "--quiet"],
            capture_output=True, text=True, timeout=10,
        )
        dt = time.monotonic() - t0
        print(f"[Output flood] finished in {dt:.2f}s (timeout was 0.30s) rc={p.returncode}")
        for line in p.stdout.splitlines():
            if "substitutions" in line or "bot " in line or "time=" in line:
                print(" ", line)
    except subprocess.TimeoutExpired:
        print("[Output flood] REPRODUCED: mj hung >10s despite --timeout 300ms!")
