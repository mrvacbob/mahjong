"""Generate a seeded corpus from an mjai replay and checked edge cases."""
import argparse
from collections import Counter
from itertools import permutations
import json
from pathlib import Path
import random
import re
import subprocess

HERE = Path(__file__).resolve().parent
WINDS = "ESWN"
SUITS = "mpsz"
SEED = 0x4D4A
TARGET = 3000


def tile(mjai):
    if len(mjai) == 1:
        return f"{'ESWNPFC'.index(mjai) + 1}z"
    return "0" + mjai[1] if mjai.endswith("r") else mjai


def notation(values):
    values = list(values)
    groups = []
    for suit in SUITS:
        digits = [t[0] for t in values if t[1] == suit]
        if digits:
            digits.sort(key=lambda d: (int(d) or 5, d != "0"))
            groups.append("".join(digits) + suit)
    return "".join(groups) or "-"


def split_tiles(value):
    return [digit + suit for digits, suit in re.findall(r"([0-9]+)([mpsz])", value)
            for digit in digits]


def permute_fields(fields, mapping):
    def group(value):
        return notation(t.translate(mapping) for t in split_tiles(value))

    def meld(value):
        return value[0] + group(value[1:])

    result = fields.copy()
    for key in ("hand", "dora", "draw", "discard", "took"):
        if key in result:
            result[key] = group(result[key])
    if result.get("melds", "-") != "-":
        result["melds"] = ",".join(meld(m) for m in result["melds"].split(","))
    if "called" in result:
        result["called"] = meld(result["called"])
    return result


def permute_action(action, mapping):
    verb, sep, value = action.partition(":")
    return verb + sep + (notation(t.translate(mapping) for t in split_tiles(value)) if sep else "")


def request(op, fields):
    return op + " " + " ".join(f"{key}={value}" for key, value in fields.items())


def run(binary, requests):
    indexed = [f"{i} {entry}" for i, entry in enumerate(requests)]
    output = subprocess.run([binary], input="\n".join(indexed) + "\n", text=True,
                            capture_output=True, check=True).stdout.splitlines()
    if len(indexed) != len(output):
        raise RuntimeError("Runner response count differs from request count")
    results = []
    for i, line in enumerate(output):
        id_, _, fields = line.partition(" ")
        if id_ != str(i) or not fields or fields.startswith("error="):
            raise RuntimeError(f"{indexed[i]} => {line}")
        results.append(dict(pair.split("=", 1) for pair in fields.split()))
    return results


def replay(log, binary):
    rows = [json.loads(line) for line in log.read_text().splitlines() if line.strip()]
    snapshots = []
    calls = {"chi": "c", "pon": "p", "daiminkan": "k"}
    for index, row in enumerate(rows):
        event = row["type"]
        if event == "start_kyoku":
            hands = [list(map(tile, hand)) for hand in row["tehais"]]
            melds = [[] for _ in hands]
            rivers = [set() for _ in hands]
            accepted = [False] * 4
            dora = [tile(row["dora_marker"])]
            wall, kans = 70, 0
            interrupted, rinshan = False, False
            oya = row["oya"]
            round_wind = row["bakaze"]
            continue
        if event == "reach_accepted":
            accepted[row["actor"]] = True
            continue
        if event == "dora":
            dora.append(tile(row["dora_marker"]))
            continue
        if event not in ("tsumo", "dahai", *calls, "ankan", "kakan"):
            continue
        actor = row["actor"]

        def snapshot(seat, fields, required=()):
            base = {
                "hand": notation(hands[seat]),
                "melds": ",".join(melds[seat]) or "-",
                "seat": WINDS[(seat - oya) % 4],
                "round": round_wind,
                "dora": notation(dora),
                "wall": str(wall),
                "kans": str(kans),
            }
            if accepted[seat]:
                base["riichi"] = "1"
            base.update(fields)
            snapshots.append((base, tuple(required), seat, set(rivers[seat]), index))

        # Announcements can intervene between a discard and its response.
        upcoming = []
        for following in rows[index + 1:]:
            if following["type"] not in ("reach_accepted", "dora"):
                upcoming.append(following)
                if following["type"] != "hora":
                    break
        required = []
        if event == "tsumo":
            drawn = tile(row["pai"])
            wall -= 1
            fields = {"draw": drawn}
            if rinshan:
                fields["flags"] = "rinshan"
            elif wall == 0:
                fields["flags"] = "haitei"
            rinshan = False
            if not interrupted and not rivers[actor]:
                fields["first"] = "1"
            following = upcoming[0]
            next_type = following["type"]
            if next_type == "dahai":
                required.append("discard:" + tile(following["pai"]))
            elif next_type == "reach":
                required.append("riichi:" + tile(rows[index + 2]["pai"]))
            elif next_type == "hora":
                required.append("tsumo")
            elif next_type == "kakan":
                required.append("kakan:" + tile(following["pai"]))
            elif next_type == "ankan":
                required.append("ankan:" + tile(following["consumed"][0]).replace("0", "5"))
            snapshot(actor, fields, required)
            hands[actor].append(drawn)
        elif event == "dahai":
            discarded = tile(row["pai"])
            hands[actor].remove(discarded)
            rivers[actor].add(discarded.replace("0", "5"))
            for seat in range(4):
                if seat == actor:
                    continue
                required = ["pass"]
                for following in upcoming:
                    if following.get("actor") == seat and following.get("target") == actor:
                        verb = following["type"]
                        if verb == "hora":
                            required.append("ron")
                        elif verb in ("chi", "pon"):
                            required.append(verb + ":" + notation(map(tile, following["consumed"])))
                        elif verb == "daiminkan":
                            required.append("kan:" + discarded.replace("0", "5"))
                fields = {"discard": discarded, "from": ("", "kamicha", "toimen", "shimocha")[(seat - actor) % 4]}
                if wall == 0:
                    fields["flags"] = "houtei"
                snapshot(seat, fields, required)
        elif event in calls:
            took = tile(row["pai"])
            consumed = list(map(tile, row["consumed"]))
            for paid in consumed:
                hands[actor].remove(paid)
            meld = calls[event] + notation([took, *consumed])
            melds[actor].append(meld)
            interrupted = True
            if event == "daiminkan":
                kans += 1
                rinshan = True
            else:
                snapshot(actor, {"called": meld, "took": took},
                         ["discard:" + tile(upcoming[0]["pai"])])
        elif event == "ankan":
            consumed = list(map(tile, row["consumed"]))
            for paid in consumed:
                hands[actor].remove(paid)
            melds[actor].append("a" + notation(consumed))
            interrupted = rinshan = True
            kans += 1
        elif event == "kakan":
            added = tile(row["pai"])
            hands[actor].remove(added)
            old = "p" + notation(map(tile, row["consumed"]))
            melds[actor][melds[actor].index(old)] = "s" + notation([added, *split_tiles(old[1:])])
            interrupted = rinshan = True
            kans += 1
            for seat in range(4):
                if seat != actor:
                    snapshot(seat, {"discard": added, "flags": "chankan",
                                    "from": ("", "kamicha", "toimen", "shimocha")[(seat - actor) % 4]},
                             ["ron" for following in upcoming
                               if following["type"] == "hora" and following["actor"] == seat])

    # First pass obtains the underlying winning shape and yaku before furiten.
    candidates = run(binary, [request("legal", fields) for fields, *_ in snapshots])
    wait_requests = []
    for fields, _, _, _, _ in snapshots:
        if "discard" in fields:
            wait_requests.append(request("waits", {key: fields[key] for key in ("hand", "melds")}))
    waits = iter(run(binary, wait_requests))
    missed = {}
    result = []
    for (fields, required, seat, river, index), out in zip(snapshots, candidates, strict=True):
        if ("draw" in fields and fields.get("riichi") != "1") or "called" in fields:
            missed.pop(seat, None)
        if "discard" in fields:
            wait = next(waits)
            permanent = wait["shanten"] == "0" and bool(river.intersection(split_tiles(wait["tiles"])))
            # Missed wins are reset by the seat's next decision or a new round.
            temporary = missed.get(seat, -1) >= 0 and not any(
                row["type"] == "start_kyoku" for row in rows[missed[seat]:index]
            )
            if permanent or temporary:
                fields["furiten"] = "1"
            if "ron" in out["actions"].split(",") and "ron" not in required:
                missed[seat] = index
        result.append((fields, required))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=HERE / "target/release/mj-rs")
    parser.add_argument("--log", type=Path, default=HERE / "../../../3p/akochan/haifu_log_sample.json")
    parser.add_argument("--output", type=Path, default=HERE.parent / "legal.txt")
    args = parser.parse_args()
    original = replay(args.log, args.binary)
    fixtures = []
    for line in (HERE / "legal_fixtures.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        label, fields, yes, no = line.split("\t")
        fixtures.append((label, dict(piece.split("=") for piece in fields.split()), yes.split(), no.split()))

    maps = [str.maketrans("mps", "".join(p)) for p in permutations("mps")]
    cases = {}

    def insert(label, fields, yes, no=()):
        entry = request("legal", fields)
        if entry not in cases:
            cases[entry] = (label, set(yes), set(no))
        else:
            _, required, forbidden = cases[entry]
            required.update(yes)
            forbidden.update(no)

    for label, fields, yes, no in fixtures:
        for mapping in maps:
            insert(label, permute_fields(fields, mapping),
                   [permute_action(a, mapping) for a in yes],
                   [permute_action(a, mapping) for a in no])
    fixture_count = len(cases)
    for fields, yes in original:
        insert("replay", fields, yes)
    variants = [(permute_fields(fields, mapping), [permute_action(a, mapping) for a in yes])
                for fields, yes in original for mapping in maps[1:]]
    random.Random(SEED).shuffle(variants)
    for fields, yes in variants:
        if len(cases) == TARGET:
            break
        insert("suit-permuted replay", fields, yes)
    if len(cases) != TARGET:
        raise RuntimeError(f"Expected {TARGET} unique cases, got {len(cases)}")

    results = run(args.binary, list(cases))
    lines = [f"# {TARGET} seeded legal cases from the Akochan mjai replay and directed fixtures",
             f"# Seed {SEED:#x}; {fixture_count} directed cases with checked required and forbidden actions"]
    tally = Counter()
    for i, ((entry, (label, required, forbidden)), out) in enumerate(zip(cases.items(), results, strict=True), 1):
        actions = out["actions"].split(",")
        if actions != sorted(set(actions)) or required.difference(actions) or forbidden.intersection(actions):
            raise RuntimeError(f"{label}: {entry}: got {actions}, require {sorted(required)}, forbid {sorted(forbidden)}")
        id_ = f"legal{i:04d}"
        tally[label] += 1
        lines.extend((f"{id_} {entry}", f"= {id_} actions={out['actions']}"))
    args.output.write_text("\n".join(lines) + "\n")
    for label, n in sorted(tally.items()):
        print(f"{label}\t{n}")


if __name__ == "__main__":
    main()
