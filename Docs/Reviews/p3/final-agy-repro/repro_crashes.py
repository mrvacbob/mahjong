#!/usr/bin/env python3.14
"""Reproduces Finding 1: crashes in `mj` line protocol via parseTiles and Counts.init."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
MJ = ROOT / ".build/debug/mj"
if not MJ.exists():
    MJ = ROOT / "mj"

cases = [
    ("non-ASCII wholeNumberValue > 9 (U+247D '⑽')", "1 shanten hand=\u247dm\n"),
    ("16 copies of 1m overflowing Counts nibble", "1 shanten hand=" + "1" * 16 + "m\n"),
]

for label, payload in cases:
    p = subprocess.run([str(MJ)], input=payload, text=True, capture_output=True)
    print(f"[{label}]")
    print(f"  returncode={p.returncode} stdout={p.stdout!r} stderr={p.stderr.strip()!r}")
