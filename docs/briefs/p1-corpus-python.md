# Brief: harness + corpus from the Python oracle

Repo: /Users/astrange/Projects/mahjong/my_mahjong (branch `shootout`). Do not run git
commands. Write only under `tools/`, `corpus/`, and the "Decisions log" section of
`spec/formats.md`. Another agent is working in `corpus/rs/`; leave it alone.

Read `spec/formats.md` first. It defines the text format and the five ops.
`spec/rules.md` (Mahjong Soul ranked rules) is being researched in parallel and may
not exist yet; assume standard ari-ari rules with three red fives, kazoe yakuman,
no kiriage mangan, no double yakuman, 2-fu double-wind pair... and list every such
assumption you had to make in the Decisions log so it can be checked later.

Oracle: the Python library at /Users/astrange/Projects/mahjong/3p/mahjong (read-only;
run things with `uv run --project <that path> python ...`; its tests pass). Read its
source to learn its conventions and its known deviations.

Deliver:

1. `tools/harness.py` (stdlib only, python3.14): `harness.py <path-to-mj> corpus/*.txt`
   feeds requests to the executable, compares responses with expected lines
   (key order insensitive), prints per-op pass/fail counts and the first N diffs,
   exits non-zero on any failure. Add `--time` to report requests/second per op.
2. `tools/gen/` generators that emit `corpus/agari.txt`, `corpus/shanten.txt`,
   `corpus/waits.txt`, `corpus/score.txt` in the spec format, deterministic from a
   seed. Aim for roughly 2000 cases each for agari/shanten/waits and 5000 for score:
   a mix of random hands (biased so that wins, tenpai and near-tenpai hands are
   common, with melds, red fives, all winds, dora, honba, flags) and targeted cases
   for every yaku and yakuman in the spec's name list and for fu edge cases.
   Also convert the oracle library's own test cases (tests/ directory) where they fit.
3. `tools/oracle_mj.py`: an `mj` executable built on the oracle library that
   implements the four ops, so the harness can be self-tested (must pass 100%).
4. `corpus/handwritten.txt`: at least 60 hand-derived cases for edge cases, written
   from the rules, not from the oracle — then run them through the oracle. Any case
   where the oracle disagrees with your hand derivation goes in `corpus/disputed.txt`
   with a comment explaining both answers. Do not silently "fix" either side.
5. Skip the `legal` op (the other agent covers it).

If the spec is ambiguous or unimplementable somewhere, choose, and record the choice
in the Decisions log of `spec/formats.md` (append only; don't rewrite the spec body
except to fix outright errors, which you must also log).

Report: counts per file, oracle self-test result, list of disputed cases, list of
decisions logged, anything in the spec you think is wrong.
