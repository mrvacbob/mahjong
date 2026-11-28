#!/bin/sh
# Differential run against libriichi (design §8 layer 2), in batches so the
# legality rows (≈3 MB per game per side) never pile up on disk.
#   Tools/libriichi_diff.sh WORKDIR BOTS FIRST_SEED BATCHES [GAMES_PER_BATCH [EXTRA]]
# BOTS is random, eager, or scenario:NAME (directed self-play, `mj selfplay
# --scenario NAME`; batches are named NAME000…). EXTRA is passed to selfplay as is
# (e.g. --check). MJ overrides the binary (default ./mj).
# For each batch: mj selfplay --rules tenhou --legal; libriichi-check check;
# AGPL/libriichi-check/compare.py; Tools/classify_libriichi.py. Keeps each batch's
# selfplay output (coverage, invariants), check stderr, compare.py summary and
# classification; deletes the rows.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
work=$1; bots=$2; seed=$3; batches=$4; per=${5:-50}; extra=${6:-}
mj=${MJ:-$root/mj}
checker=$root/AGPL/libriichi-check/target/release/libriichi-check
case "$bots" in
  scenario:*) name=${bots#scenario:}; play="--scenario $name" ;;
  *) name=$bots; play="--bots $bots" ;;
esac
mkdir -p "$work"; cd "$work"
b=0
while [ $b -lt "$batches" ]; do
  d=$(printf "%s%03d" "$name" $b)
  s=$((seed + b * per))
  rm -rf "$d"
  "$mj" selfplay --seed $s --games $per --rules tenhou $play --out "$d" --legal $extra > "$d.selfplay.txt" || true
  ls "$d"/*.jsonl | sort > "$d.files"
  "$checker" check $(cat "$d.files") > "$d.lib" 2> "$d.check.txt" || true
  cat $(sed 's/jsonl$/legality/' "$d.files") > "$d.eng"
  python3.14 -B "$root/AGPL/libriichi-check/compare.py" "$d.eng" "$d.lib" > "$d.compare.txt" || true
  python3.14 -B "$root/Tools/classify_libriichi.py" "$d.eng" "$d.lib" > "$d.classify.json"
  rm -f "$d.eng" "$d.lib" "$d"/*.legality
  [ $b -eq 0 ] || rm -rf "$d"
  b=$((b + 1))
done
