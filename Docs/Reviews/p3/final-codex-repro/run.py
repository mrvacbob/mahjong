import pathlib
import subprocess
import sys

if len(sys.argv) == 1:
    import json
    for line in sys.stdin:
        event = json.loads(line)
        choice = (
            {"type": "hora", "actor": 3, "target": 0, "pai": "1p"}
            if event["type"] == "kakan" and event["pai"] == "1p"
            else {"type": "none"}
        )
        print(json.dumps(choice), flush=True)
    raise SystemExit

probe = sys.argv[1]
bot = pathlib.Path(__file__).resolve()
subprocess.run([probe, "cases", f'exec python3.14 "{bot}"'], timeout=20, check=True)
for mode in ("honba", "score", "timeout"):
    result = subprocess.run([probe, mode], capture_output=True, timeout=10)
    print(f"{mode}: exit {result.returncode}", flush=True)
    assert result.returncode < 0, result.stderr.decode()
    print("\n".join(result.stderr.decode(errors="replace").splitlines()[:6]))
