#!/bin/sh
# Differential run against libriichi (design §8 layer 2), in batches so the
# legality rows (≈3 MB per game per side) never pile up on disk.
#   tools/libriichi_diff.sh WORKDIR BOTS FIRST_SEED BATCHES [GAMES_PER_BATCH]
# For each batch: mj selfplay --rules tenhou --legal; libriichi-check check;
# agpl/libriichi-check/compare.py; tools/classify_libriichi.py. Keeps each batch's
# check stderr, compare.py summary and classification; deletes the rows.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
work=$1; bots=$2; seed=$3; batches=$4; per=${5:-50}
checker=$root/agpl/libriichi-check/target/release/libriichi-check
mkdir -p "$work"; cd "$work"
b=0
while [ $b -lt "$batches" ]; do
  d=$(printf "%s%03d" "$bots" $b)
  s=$((seed + b * per))
  rm -rf "$d"
  "$root/mj" selfplay --seed $s --games $per --rules tenhou --bots "$bots" --out "$d" --legal --quiet > "$d.selfplay.txt"
  ls "$d"/*.jsonl | sort > "$d.files"
  "$checker" check $(cat "$d.files") > "$d.lib" 2> "$d.check.txt" || true
  cat $(sed 's/jsonl$/legality/' "$d.files") > "$d.eng"
  python3.14 -B "$root/agpl/libriichi-check/compare.py" "$d.eng" "$d.lib" > "$d.compare.txt" || true
  python3.14 -B "$root/tools/classify_libriichi.py" "$d.eng" "$d.lib" > "$d.classify.json"
  rm -f "$d.eng" "$d.lib" "$d"/*.legality
  [ $b -eq 0 ] || rm -rf "$d"
  b=$((b + 1))
done
