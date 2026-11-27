#!/usr/bin/env python3.14
"""Reproduces Finding 4: ChildProcess.stop() kills /bin/sh but leaks grandchild processes."""
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
MJ = ROOT / ".build/debug/mj"
if not MJ.exists():
    MJ = ROOT / "mj"

with tempfile.TemporaryDirectory() as td:
    pidfile = Path(td) / "grandchild.pid"
    # A shell command with '&&' prevents /bin/sh from exec-optimizing the python process,
    # so /bin/sh spawns python3.14 as a grandchild that hangs until killed.
    cmd = f'python3.14 -c "import os, signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); f=open(\\"{pidfile}\\", \\"w\\"); f.write(str(os.getpid())); f.flush(); f.close(); time.sleep(60)"; true'
    p = subprocess.run(
        [str(MJ), "selfplay", "--seed", "1", "--games", "1", "--bots", "eager",
         "--seat", f"0=mjai:{cmd}", "--timeout", "500", "--quiet"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        timeout=10,
    )
    time.sleep(0.2)
    alive = False
    pid = None
    if pidfile.exists():
        pid = int(pidfile.read_text().strip())
        try:
            os.kill(pid, 0)
            alive = True
        except ProcessLookupError:
            alive = False
        if alive:
            os.kill(pid, signal.SIGKILL)
    print(f"mj exit={p.returncode}, grandchild pid={pid}, survived_after_mj_exit={alive}")
