#!/usr/bin/env python3
"""Compare two per-seat JSONL traces produced from the same logs."""

import argparse
from collections import Counter
import json
import sys

KEY = ("file", "hand", "event_index", "seat")
FIELDS = ("event_type", "flags", "discard", "ankan", "kakan", "waits", "shanten", "furiten")
TILE_LISTS = {"discard", "ankan", "kakan", "waits"}
REACTIONS = (
    "can_chi_low", "can_chi_mid", "can_chi_high", "can_pon", "can_daiminkan", "can_ron_agari"
)
FLAGS = REACTIONS + (
    "can_discard", "can_kakan", "can_ankan", "can_riichi", "can_tsumo_agari", "can_ryukyoku"
)


def rows(stream):
    previous = None
    for number, line in enumerate(stream, 1):
        try:
            row = json.loads(line)
            key = tuple(row[name] for name in KEY)
            if not (isinstance(key[0], str) and all(type(n) is int for n in key[1:])
                    and key[1] >= 1 and key[2] >= 0 and 0 <= key[3] <= 3):
                raise ValueError("invalid row identity")
            if previous is not None and key <= previous:
                raise ValueError("duplicate or out-of-order row")
            for name in FIELDS:
                row[name]
            if any(not isinstance(row[name], list) or
                   any(not isinstance(tile, str) for tile in row[name]) for name in TILE_LISTS):
                raise ValueError("invalid tile array")
            if (any(type(row["flags"][flag]) is not bool for flag in FLAGS)
                    or type(row["flags"]["target_actor"]) is not int
                    or not 0 <= row["flags"]["target_actor"] <= 3
                    or type(row["furiten"]) is not bool or type(row["shanten"]) is not int
                    or not isinstance(row["event_type"], str)):
                raise ValueError("invalid action flags or state")
            previous = key
            yield key, row
        except (ValueError, KeyError, TypeError) as error:
            raise ValueError(f"{stream.name}:{number}: {error}") from error


def differences(engine, reference, strict, counts):
    if engine is None or reference is None:
        return {"row": (engine, reference)}
    result = {}
    same_event = engine["event_type"] == reference["event_type"]
    for field in FIELDS:
        left, right = engine[field], reference[field]
        if left == right:
            continue
        if field in TILE_LISTS and sorted(left) == sorted(right):
            counts["candidate_tile_order"] += 1
            continue
        if field == "flags":
            # Target is meaningful for reactions. Other flag keys are extensions.
            for flag in (*FLAGS, "target_actor"):
                if left[flag] == right[flag]:
                    continue
                if (not strict and same_event and flag == "target_actor"
                        and not any(left[name] or right[name] for name in REACTIONS)):
                    counts["idle_target_actor"] += 1
                    continue
                result[f"flags.{flag}"] = (left[flag], right[flag])
            continue
        if (not strict and same_event and field == "waits" and set(right) < set(left)
                and len(set(left)) == len(left) and len(set(right)) == len(right)
                and set(left) - set(right) <= set(reference.get("visible_exhausted", []))):
            counts["visible_exhausted_waits"] += 1
            continue
        result[field] = (left, right)
    return result


def compare(left, right, strict):
    counts = Counter()
    compared = failed = hands = 0
    previous_hand = None
    left_row, right_row = next(left, None), next(right, None)
    while left_row is not None or right_row is not None:
        key = min(row[0] for row in (left_row, right_row) if row is not None)
        engine = reference = None
        if left_row is not None and left_row[0] == key:
            engine = left_row[1]
            left_row = next(left, None)
        if right_row is not None and right_row[0] == key:
            reference = right_row[1]
            right_row = next(right, None)
        compared += 1
        if key[:2] != previous_hand:
            previous_hand = key[:2]
            hands += 1
            reported = False
        diff = differences(engine, reference, strict, counts)
        if diff and not reported:
            reported = True
            failed += 1
            print(json.dumps(dict(zip(KEY, key)) | {
                "engine": {field: pair[0] for field, pair in diff.items()},
                "libriichi": {field: pair[1] for field, pair in diff.items()},
            }))
    print(json.dumps({"hands": hands, "failed": failed, "rows": compared, "filtered": counts}))
    return int(failed > 0 or compared == 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=argparse.FileType("r"))
    parser.add_argument("libriichi", type=argparse.FileType("r"))
    parser.add_argument("--strict", action="store_true", help="disable rule and idle-target filters")
    args = parser.parse_args()
    try:
        return compare(rows(args.engine), rows(args.libriichi), args.strict)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
