#!/usr/bin/env python3
"""Repro for Findings 8, 9, 10, 11: JSON reader & Mjai.decode/action validation bugs.
- Finding 8a: invalid escape in value (\\q) misclassified as illegal instead of malformed.
- Finding 8b: bogus number 1..2e+-3 accepted by JSON reader.
- Finding 9: duplicate keys use first-wins instead of last-wins.
- Finding 10: wrong-typed pai (int) misclassified as illegal instead of malformed;
  wrong-typed tsumogiri ("nope") accepted as a legal discard.
- Finding 11: ankan with 1-element consumed (["1m"]) accepted as legal.
"""
import json, os, subprocess, sys, tempfile

MJ = os.path.abspath(".build/debug/mj")

with tempfile.TemporaryDirectory() as d:
    def run_bot(raw_reply: str, label: str):
        bot = os.path.join(d, "bot.py")
        with open(bot, "w") as f:
            f.write(
                "import json, sys\n"
                f"PAYLOAD = {raw_reply!r}\n"
                "seat = None; sent = False\n"
                "for line in sys.stdin:\n"
                "    e = json.loads(line)\n"
                "    if e['type'] == 'start_game': seat = e['id']; print('{\"type\":\"none\"}', flush=True); continue\n"
                "    if e['type'] == 'tsumo' and e['actor'] == seat:\n"
                "        if not sent:\n"
                "            sent = True\n"
                "            print(PAYLOAD, flush=True); continue\n"
                "        print(json.dumps({'type':'dahai','actor':seat,'pai':e['pai'],'tsumogiri':True}), flush=True); continue\n"
                "    print('{\"type\":\"none\"}', flush=True)\n"
            )
        p = subprocess.run(
            [MJ, "selfplay", "--seed", "1", "--games", "1", "--bots", "eager",
             "--seat", f"0=mjai:python3.14 {bot}", "--quiet"],
            capture_output=True, text=True, timeout=10,
        )
        subs = [l for l in p.stdout.splitlines() if l.startswith("substitutions") or l.startswith("bot ")]
        print(f"[{label}] " + " | ".join(subs))

    run_bot(r'{"type":"dahai","actor":0,"pai":"\q","tsumogiri":false}', "Finding 8a: bad escape \\q in pai (expect malformed, got illegal)")
    run_bot(r'{"type":"dahai","actor":0,"pai":123,"tsumogiri":false}', "Finding 10a: int pai=123 (expect malformed, got illegal)")
    run_bot(r'{"type":"none","type":"dahai","actor":0,"pai":"9s","tsumogiri":true}', "Finding 9: dup key none then dahai (first-wins parses as none)")

    # Finding 10b: wrong-typed tsumogiri="nope" on a valid discard is ACCEPTED with 0 substitutions!
    bot10b = os.path.join(d, "bot10b.py")
    with open(bot10b, "w") as f:
        f.write(
            "import json, sys\n"
            "seat = None\n"
            "for line in sys.stdin:\n"
            "    e = json.loads(line)\n"
            "    if e['type'] == 'start_game': seat = e['id']; print('{\"type\":\"none\"}', flush=True); continue\n"
            "    if e['type'] == 'tsumo' and e['actor'] == seat:\n"
            "        print(json.dumps({'type':'dahai','actor':seat,'pai':e['pai'],'tsumogiri':'nope'}), flush=True); continue\n"
            "    print('{\"type\":\"none\"}', flush=True)\n"
        )
    p = subprocess.run(
        [MJ, "selfplay", "--seed", "1", "--games", "1", "--bots", "eager",
         "--seat", f"0=mjai:python3.14 {bot10b}", "--quiet"],
        capture_output=True, text=True, timeout=10,
    )
    subs = [l for l in p.stdout.splitlines() if l.startswith("substitutions")]
    print("[Finding 10b: string tsumogiri='nope' accepted] " + " | ".join(subs))

    # Finding 8b: bogus number in check-log
    p_num = os.path.join(d, "badnum.jsonl")
    open(p_num, "w").write('{"type":"start_game","x":1..2e+-3}\n')
    p = subprocess.run([MJ, "check-log", p_num], capture_output=True, text=True)
    print(f"[Finding 8b: bogus number 1..2e+-3] rc={p.returncode} out={p.stdout.strip()!r}")
