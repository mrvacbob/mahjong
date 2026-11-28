"""Compare mj-rs against paired corpus files."""
import argparse
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def fields(line):
    id_, *tokens = line.split()
    result = {}
    for token in tokens:
        key, value = token.split("=", 1)
        if not key or not value or key in result:
            raise ValueError(f"invalid response: {line}")
        result[key] = value
    if not result:
        raise ValueError(f"missing response fields: {line}")
    return id_, result


def compare(binary, path):
    lines = [line.strip() for line in path.read_text().splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    cases = list(zip(lines[::2], lines[1::2], strict=True))
    requests = []
    expected = []
    for request, reply in cases:
        if not reply.startswith("= "):
            raise ValueError(f"invalid case in {path}: {request} / {reply}")
        reply = reply[2:]
        if fields(reply)[0] != request.split()[0]:
            raise ValueError(f"mismatched expected id in {path}: {request} / {reply}")
        requests.append(request)
        expected.append(reply)
    replies = subprocess.run([binary], input="\n".join(requests) + "\n", text=True,
                             capture_output=True, check=True, timeout=180).stdout.splitlines()
    disagreements = []
    for request, want, got in zip(requests, expected, replies, strict=True):
        if fields(want) != fields(got):
            disagreements.append((request, want, got))
    return len(cases), disagreements


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=HERE / "target/release/mj-rs")
    parser.add_argument("--out", type=Path, help="Write a Markdown record of every raw mismatch")
    parser.add_argument("corpora", type=Path, nargs="*")
    args = parser.parse_args()
    corpora = args.corpora or [HERE.parent / f"{op}.txt" for op in ("shanten", "waits", "score")]
    report = ["# Comparison with mj-rs", "", "| Corpus | Compared | Disagreements |",
              "| --- | ---: | ---: |"]
    details = []
    missing = False
    for path in corpora:
        if not path.is_file():
            report.append(f"| `{path.name}` | Missing | — |")
            print(f"{path.name}: missing", file=sys.stderr)
            missing = True
            continue
        count, mismatches = compare(args.binary.resolve(), path)
        report.append(f"| `{path.name}` | {count} | {len(mismatches)} |")
        print(f"{path.name}: {count} compared, {len(mismatches)} disagreements")
        for request, want, got in mismatches:
            details.extend(["", "~~~text", request, f"corpus  {want}", f"mj-rs   {got}", "~~~"])
    if args.out:
        args.out.write_text("\n".join(report + details) + "\n")
    return 2 if missing else int(bool(details))


if __name__ == "__main__":
    sys.exit(main())
