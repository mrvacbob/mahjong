#!/usr/bin/env python3
"""Repro for Findings 1 & 2: JSON reader crashes on hostile input.
1. Malformed surrogate pair (\\uD800\\u0000) -> UInt32 underflow trap (SIGTRAP/SIGILL).
2. Deeply nested JSON ([[[...]]]) -> stack overflow (SIGSEGV/SIGBUS).
"""
import os, subprocess, sys, tempfile

MJ = os.path.abspath(".build/debug/mj")

def run_checklog(payload: str, label: str):
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
        f.write(payload + "\n")
        path = f.name
    try:
        p = subprocess.run([MJ, "check-log", path], capture_output=True, text=True, timeout=10)
        print(f"[{label}] returncode={p.returncode} (signal={-p.returncode if p.returncode < 0 else 'none'})")
        if p.stdout.strip(): print("  stdout:", p.stdout.strip()[:200])
        if p.stderr.strip(): print("  stderr:", p.stderr.strip()[:200])
        return p.returncode
    finally:
        os.unlink(path)

rc1 = run_checklog(r'{"type":"\uD800\u0000"}', "Finding 1: surrogate underflow")
rc2 = run_checklog('{"type":"none","meta":' + '[' * 200000 + ']' * 200000 + '}', "Finding 2: deep nesting")
sys.exit(0 if (rc1 < 0 and rc2 < 0) else 1)
