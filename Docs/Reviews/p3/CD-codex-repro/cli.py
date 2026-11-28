"""Run the CLI replay, legality export and predictable-seed probes."""
import json
import os
from pathlib import Path
import subprocess
import sys

MASK = (1 << 64) - 1


def mix(x):
    z = (x + 0x9E3779B97F4A7C15) & MASK
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
    return z ^ (z >> 31)


def rotate(x, n):
    return ((x << n) | (x >> (64 - n))) & MASK


def wall(seed):
    key = mix(seed) ^ mix(MASK)
    a, b, c, d = [mix((key + n * 0x9E3779B97F4A7C15) & MASK) for n in range(4)]
    tiles = [str(n) + suit if n != 5 or i != 0 else "5" + suit + "r"
             for suit in "mps" for n in range(1, 10) for i in range(4)]
    tiles += [kind for kind in "ESWNPFC" for _ in range(4)]
    for i in range(135, 0, -1):
        bound = i + 1
        while True:
            r = (rotate((b * 5) & MASK, 7) * 9) & MASK
            t = (b << 17) & MASK
            c ^= a
            d ^= b
            b ^= c
            a ^= d
            c ^= t
            d = rotate(d, 45)
            if r >= (1 << 64) % bound:
                break
        j = r % bound
        tiles[i], tiles[j] = tiles[j], tiles[i]
    return tiles


def child(prediction_path):
    for line in sys.stdin:
        event = json.loads(line)
        if event["type"] == "start_kyoku" and not prediction_path.exists():
            own = sorted(event["tehais"][0])
            for seed in range(256):
                tiles = wall(seed)
                candidate = sorted(tiles[0:4] + tiles[16:20] + tiles[32:36] + tiles[48:49])
                if own == candidate and event["dora_marker"] == tiles[126]:
                    prediction_path.write_text(json.dumps({"seed": seed, "wall": tiles}))
                    break
        if event["type"] == "end":
            return
        if event["type"] == "tsumo" and event["actor"] == 0:
            print(json.dumps({"type": "dahai", "actor": 0,
                              "pai": event["pai"], "tsumogiri": True}), flush=True)
        else:
            print('{"type":"none"}', flush=True)


def run_cli(binary, root):
    import shlex

    for rules, bots in (("tenhou", "eager"), ("mahjongsoul", "random")):
        out = root / ("replay-" + rules)
        out.mkdir(exist_ok=True)
        args = [binary, "selfplay", "--seed", "123456", "--games", "48",
                "--rules", rules, "--bots", bots, "--out", out, "--legal", "--quiet"]

        def run(deterministic):
            env = {k: v for k, v in os.environ.items() if k != "SWIFT_DETERMINISTIC_HASHING"}
            if deterministic:
                env["SWIFT_DETERMINISTIC_HASHING"] = "1"
            subprocess.run(args, env=env, check=True, capture_output=True)
            return {p.name: p.read_bytes() for p in out.iterdir()}

        first = run(False)
        assert len(first) == 144
        assert first == run(False) == run(True)
        result = subprocess.run([binary, "replay", *sorted(out.glob("*.trace"))],
                                check=True, capture_output=True, text=True)
        assert "replayed=48 identical=48" in result.stdout
        print(rules, result.stdout.strip(), "+ identical trace/log/legality on three independent runs")
        rows = [json.loads(line) for line in first["000000.legality"].splitlines()]
        opening = [r for r in rows if r["hand"] == 1 and r["event_index"] == 0]
        assert [r["seat"] for r in opening] == list(range(4))
        assert len({r["x_hand"] for r in opening}) == 4
        print(rules, "legality export opening x_hand:", [r["x_hand"] for r in opening])

    # A valid trace with custom bot names, paired first with the generated
    # header and then with a canonically equivalent different UTF-8 header.
    case = root / "unicode"
    trace = first["000000.trace"].replace(b"bots random,random,random,random",
                                          "bots café,random,random,random".encode(), 1)
    log = first["000000.jsonl"].replace(b'"random"', '"café"'.encode(), 1)
    case.with_suffix(".trace").write_bytes(trace)
    case.with_suffix(".jsonl").write_bytes(log)
    subprocess.run([binary, "replay", case.with_suffix(".trace")], check=True, capture_output=True)
    different = log.replace("café".encode(), "cafe\u0301".encode(), 1)
    assert different != log
    case.with_suffix(".jsonl").write_bytes(different)
    result = subprocess.run([binary, "replay", case.with_suffix(".trace")],
                            check=True, capture_output=True, text=True)
    assert "replayed=1 identical=1" in result.stdout
    print("Unicode replay called unequal UTF-8 bytes identical.")

    prediction = root / "prediction.json"
    prediction.unlink(missing_ok=True)
    out = root / "predictable-seed"
    command = shlex.join([sys.executable, str(Path(__file__).resolve()), "--bot", str(prediction)])
    subprocess.run([binary, "selfplay", "--bots", "random", "--seat", "0=mjai:" + command,
                    "--out", out, "--quiet"], check=True, capture_output=True)
    predicted = json.loads(prediction.read_text())
    opening = json.loads((out / "000000.jsonl").read_text().splitlines()[1])
    assert predicted["seed"] == 0 and predicted["wall"] == opening["wall"]
    print("Protocol-only bot predicted all 136 slots and seed 0 from the masked opening.")


if __name__ == "__main__":
    if sys.argv[1] == "--bot":
        child(Path(sys.argv[2]))
    else:
        run_cli(Path(sys.argv[1]), Path(sys.argv[2]))
