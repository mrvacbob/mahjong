#!/bin/sh
# Mercury cross-check (design §8 layer 3) of Mahjong Soul self-play:
#   tools/mercury_diff.sh WORKDIR FIRST_SEED GAMES [SELFPLAY ARGS...]
# e.g. tools/mercury_diff.sh W 1000 300 --scenario pao --check
# `mj selfplay --requests` dumps every decision as a `legal` request and every win as
# a `score` request (with the round engine's own answers in rq.txt.expected); then
# ./mj and crosscheck/mercury/mj answer them. Prints the counts: Mercury against
# ./mj (must be identical), and ./mj against the round engine (known differences:
# the requests in rq.txt.lowpoints, a riichi the line protocol offers under 1,000
# points; and fifth-copy riichi, which the line protocol never offers).
# MJ overrides the binary (default ./mj).
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
work=$1; seed=$2; games=$3; shift 3
mj=${MJ:-$root/mj}
mkdir -p "$work"; cd "$work"
"$mj" selfplay --seed "$seed" --games "$games" "$@" --requests rq.txt > selfplay.txt || true
"$mj" < rq.txt > swift.out
"$root/crosscheck/mercury/mj" < rq.txt > mercury.out
python3.14 -B - <<'EOF'
import collections
rq = open("rq.txt").read().splitlines()
sw = open("swift.out").read().splitlines()
me = open("mercury.out").read().splitlines()
ex = open("rq.txt.expected").read().splitlines()
low = set(open("rq.txt.lowpoints").read().split())
kinds = collections.Counter(l.split()[1] for l in rq)
assert len(rq) == len(sw) == len(me) == len(ex), (len(rq), len(sw), len(me), len(ex))
mer = [i for i in range(len(rq)) if sw[i] != me[i]]
eng = collections.Counter()
for i in range(len(rq)):
    if sw[i] == ex[i]: continue
    q = rq[i].split()[0]
    if q in low: eng["riichi under 1,000 points (lowpoints)"] += 1
    else:
        a = set(sw[i].split("=", 1)[1].split(",")) if "=" in sw[i] else set()
        b = set(ex[i].split("=", 1)[1].split(",")) if "=" in ex[i] else set()
        only = b - a
        if only and all(x.startswith("riichi:") for x in only) and not (a - b):
            eng["riichi the line protocol refuses (fifth copy)"] += 1
        else:
            eng["UNEXPLAINED"] += 1
            if eng["UNEXPLAINED"] <= 5: print("unexplained:", rq[i], "|", sw[i], "|", ex[i])
print(f"requests={len(rq)} {dict(kinds)} mercury_vs_mj_differ={len(mer)} mj_vs_engine={dict(eng)}")
for i in mer[:5]: print("mercury differs:", rq[i], "|", sw[i], "|", me[i])
EOF
