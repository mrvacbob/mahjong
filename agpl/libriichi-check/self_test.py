#!/usr/bin/env python3
"""Generate real arena logs, replay them, and reject three corruptions."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent
binary = root / "target/release/libriichi-check"
games = int(sys.argv[1]) if len(sys.argv) > 1 else 200
if not binary.is_file():
    raise SystemExit(f"Build the release binary before running self-tests: {binary}")


def run(*args):
    return subprocess.run([binary, *args], stdout=subprocess.DEVNULL,
                          stderr=subprocess.PIPE, text=True)


def read(path):
    return [json.loads(line) for line in path.read_text().splitlines()]


def write(path, rows):
    path.write_text("".join(json.dumps(row) + "\n" for row in rows))


with tempfile.TemporaryDirectory(dir=root / "target") as temp:
    directory = Path(temp)
    subprocess.run([binary, "generate", str(games), directory], check=True)
    logs = sorted(directory.glob("*.jsonl"))
    clean = run("check", *logs)
    print("clean:", clean.stderr.strip())
    assert clean.returncode == 0, clean.stderr
    totals = json.loads(clean.stderr.splitlines()[-1])
    assert totals["files"] == games + 1 and totals["hands"] >= 4 * games + 1
    expected_rows = sum(4 for log in logs for row in read(log)
                        if row["type"] not in {"start_game", "end_game"})
    assert totals["state_rows"] == expected_rows

    for corruption in ("dahai", "deltas", "dora"):
        rows = read(directory / "kan.jsonl")
        kind = {"dahai": "dahai", "deltas": "ryukyoku", "dora": "dora"}[corruption]
        index = next(i for i, row in enumerate(rows) if row["type"] == kind)
        if corruption == "dahai":
            row = rows[index]
            row["pai"] = "1m" if row["pai"] != "1m" else "2m"
        elif corruption == "deltas":
            rows[index]["deltas"][0] += 100
        else:
            del rows[index]
        corrupt = directory / f"corrupt-{corruption}.jsonl"
        write(corrupt, rows)
        failure = run("check", corrupt)
        print(f"corrupt {corruption}: exit {failure.returncode}, {failure.stderr.splitlines()[0]}")
        assert failure.returncode == 1, failure.stderr
        diagnostic = json.loads(failure.stderr.splitlines()[0])
        assert diagnostic["event_index"] == index, diagnostic
        assert diagnostic["log"] != diagnostic["libriichi"], diagnostic
        assert json.loads(failure.stderr.splitlines()[-2])["failed"] == 1
