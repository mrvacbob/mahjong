#!/usr/bin/env python3
"""Repro for Findings 4, 5, 6, 7: check-log bugs.
- Finding 4: accepts empty log and silently skips arbitrary events outside hands.
- Finding 5: crashes with precondition failure on negative honba / kyotaku.
- Finding 6: rejects valid riichi win when ura_markers is renamed to uradora_markers or omitted.
- Finding 7: accepts impossible ryukyoku reason and tenpais.
"""
import json, os, subprocess, sys, tempfile

MJ = os.path.abspath(".build/debug/mj")

def check(path, rules="mahjongsoul"):
    return subprocess.run([MJ, "check-log", "--rules", rules, path], capture_output=True, text=True, timeout=10)

with tempfile.TemporaryDirectory() as d:
    # Finding 4a: empty log
    empty = os.path.join(d, "empty.jsonl")
    open(empty, "w").close()
    p = check(empty)
    print(f"[Finding 4a: empty log] rc={p.returncode} out={p.stdout.strip()!r}")

    # Finding 4b: bogus events outside start_kyoku..end_kyoku
    bogus = os.path.join(d, "bogus.jsonl")
    with open(bogus, "w") as f:
        f.write('{"type":"start_game","names":["0","1","2","3"]}\n')
        f.write('{"type":"hora","actor":0,"target":1,"pai":"1m","deltas":[999999,0,0,0]}\n')
        f.write('{"type":"end_game","scores":[999999,0,0,0]}\n')
    p = check(bogus)
    print(f"[Finding 4b: bogus events outside hands] rc={p.returncode} out={p.stdout.strip()!r}")

    # Finding 5: negative honba crashes check-log
    # Generate a real game first to borrow a valid start_kyoku
    out_dir = os.path.join(d, "sp")
    subprocess.run([MJ, "selfplay", "--seed", "1", "--games", "5", "--bots", "eager", "--out", out_dir, "--quiet"],
                   check=True, capture_output=True)
    log0 = open(os.path.join(out_dir, "000000.jsonl")).read().splitlines()
    neg_lines = list(log0)
    for idx, line in enumerate(neg_lines):
        obj = json.loads(line)
        if obj["type"] == "start_kyoku":
            obj["honba"] = -1
            neg_lines[idx] = json.dumps(obj)
            break
    neg_path = os.path.join(d, "neg_honba.jsonl")
    open(neg_path, "w").write("\n".join(neg_lines) + "\n")
    p = check(neg_path)
    print(f"[Finding 5: negative honba] rc={p.returncode} (signal={-p.returncode if p.returncode < 0 else 'none'}) stderr={p.stderr.strip()[:120]!r}")

    # Finding 6: find a riichi win where ura dora actually scored (or any riichi win with non-empty ura_markers)
    repro6_uradora = False
    repro6_omitted = False
    for g in range(5):
        lines = open(os.path.join(out_dir, f"{g:06d}.jsonl")).read().splitlines()
        # Test 6a: replace ura_markers with uradora_markers only
        mod_a = []
        changed_a = False
        for line in lines:
            obj = json.loads(line)
            if obj["type"] == "hora" and obj.get("ura_markers"):
                # Keep uradora_markers, drop ura_markers
                obj.pop("ura_markers", None)
                changed_a = True
            mod_a.append(json.dumps(obj))
        if changed_a and not repro6_uradora:
            pa = os.path.join(d, f"uradora_{g}.jsonl")
            open(pa, "w").write("\n".join(mod_a) + "\n")
            p = check(pa)
            if p.returncode != 0:
                repro6_uradora = True
                print(f"[Finding 6a: uradora_markers only (game {g})] REPRODUCED rc={p.returncode} out={p.stdout.strip().splitlines()[0]!r}")
        # Test 6b: omit both ura_markers and uradora_markers
        mod_b = []
        changed_b = False
        for line in lines:
            obj = json.loads(line)
            if obj["type"] == "hora" and obj.get("ura_markers"):
                obj.pop("ura_markers", None)
                obj.pop("uradora_markers", None)
                changed_b = True
            mod_b.append(json.dumps(obj))
        if changed_b and not repro6_omitted:
            pb = os.path.join(d, f"no_ura_{g}.jsonl")
            open(pb, "w").write("\n".join(mod_b) + "\n")
            p = check(pb)
            if p.returncode != 0:
                repro6_omitted = True
                print(f"[Finding 6b: omitted ura_markers (game {g})] REPRODUCED rc={p.returncode} out={p.stdout.strip().splitlines()[0]!r}")

    # Finding 7: tamper ryukyoku reason and tenpais
    for g in range(5):
        lines = open(os.path.join(out_dir, f"{g:06d}.jsonl")).read().splitlines()
        mod = []
        tampered = False
        for line in lines:
            obj = json.loads(line)
            if obj["type"] == "ryukyoku" and not tampered:
                obj["reason"] = "completely_bogus_reason"
                obj["tenpais"] = [True, True, True, True]
                tampered = True
            mod.append(json.dumps(obj))
        if tampered:
            p7 = os.path.join(d, f"bad_ryukyoku_{g}.jsonl")
            open(p7, "w").write("\n".join(mod) + "\n")
            p = check(p7)
            print(f"[Finding 7: bogus ryukyoku reason & tenpais (game {g})] rc={p.returncode} out={p.stdout.strip()!r}")
            break
