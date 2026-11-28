"""Generate a seeded corpus from an mjai replay and checked edge cases."""
import argparse
from collections import Counter, defaultdict, deque
import json
from pathlib import Path
import random
import re
import subprocess

HERE = Path(__file__).resolve().parent
WINDS = "ESWN"
SUITS = "mpsz"
SEED = 0x4D4A
REPLAY_LIMIT = 600
FROM = ('', 'kamicha', 'toimen', 'shimocha')


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
            interrupted, rinshan, after_rinshan = False, False, False
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
            after_rinshan, rinshan = rinshan, False
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
                fields = {"discard": discarded, "from": FROM[(seat - actor) % 4]}
                if wall == 0 and not after_rinshan:
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
        else:  # ankan or kakan
            consumed = list(map(tile, row["consumed"]))
            robbed = [event for event in upcoming if event["type"] == "hora"]
            if event == "ankan":
                incoming = tile(robbed[0]["pai"]) if robbed and "pai" in robbed[0] else consumed[0]
                flag = "ankan_rob"
            else:
                incoming = tile(row["pai"])
                flag = "chankan"
            for seat in range(4):
                if seat != actor:
                    snapshot(seat, {"discard": incoming, "flags": flag,
                                    "from": FROM[(seat - actor) % 4]},
                             ["pass", *["ron" for win in robbed if win["actor"] == seat]])
            if event == "ankan":
                for paid in consumed:
                    hands[actor].remove(paid)
                melds[actor].append("a" + notation(consumed))
            else:
                hands[actor].remove(incoming)
                old = "p" + notation(consumed)
                melds[actor][melds[actor].index(old)] = "s" + notation([incoming, *consumed])
            interrupted = rinshan = True
            kans += 1

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


def select_replay(binary, original, fixtures):
    unique = {}
    for fields, required in original:
        entry = request("legal", fields)
        if entry not in fixtures:
            unique.setdefault(entry, (fields, set()))[1].update(required)
    results = run(binary, list(unique))
    buckets = defaultdict(list)
    for (entry, (fields, required)), out in zip(unique.items(), results, strict=True):
        actions = out["actions"].split(",")
        if required.difference(actions):
            raise RuntimeError(f"{entry}: recorded actions {sorted(required)} missing from {actions}")
        verbs = tuple(sorted({action.split(":")[0] for action in actions}))
        event = next(key for key in ("draw", "discard", "called") if key in fields)
        situation = (event, verbs, fields.get("flags"), fields.get("riichi"),
                     fields.get("furiten"), fields.get("first"), fields.get("from"),
                     fields["melds"] != "-")
        buckets[situation].append((entry, required))

    # Round-robin across situations keeps rare actions and contexts in the sample.
    rng = random.Random(SEED)
    queues = deque()
    for bucket in sorted(buckets.values(), key=len):
        rng.shuffle(bucket)
        queues.append(deque(bucket))
    for _ in range(min(REPLAY_LIMIT, len(unique))):
        queue = queues.popleft()
        yield queue.popleft()
        if queue:
            queues.append(queue)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=HERE / "target/release/mj-rs")
    parser.add_argument("--log", type=Path, default=HERE / "../../../3p/akochan/haifu_log_sample.json")
    parser.add_argument("--output", type=Path, default=HERE.parent / "legal.txt")
    args = parser.parse_args()
    original = replay(args.log, args.binary)
    cases = {}
    for line in (HERE / "legal_fixtures.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        label, fields, yes, no = line.split("\t")
        entry = request("legal", dict(piece.split("=") for piece in fields.split()))
        if entry in cases:
            raise RuntimeError(f"Duplicate directed case: {entry}")
        cases[entry] = (label, set(yes.split()), set(no.split()))

    fixture_count = len(cases)
    for entry, required in select_replay(args.binary, original, cases):
        cases[entry] = ("replay", required, set())
    replay_count = len(cases) - fixture_count
    results = run(args.binary, list(cases))
    lines = [f"# {replay_count} unique Akochan mjai replay snapshots and {fixture_count} directed cases",
             f"# Seed {SEED:#x}; replay sampled across action sets and decision contexts",
             "# Expected action sets come from mj-rs, checked against replay moves or fixture constraints."]
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
