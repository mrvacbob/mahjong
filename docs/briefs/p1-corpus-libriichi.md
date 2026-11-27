# Brief: second oracle from Mortal's libriichi (Rust), plus `legal` corpus

Repo: . (branch `shootout`). Do not run git
commands. Write only under `agpl/mj-rs/` (your Rust crate and its outputs) and
`corpus/legal.txt`. Do not modify anything under ../3p.

Read `spec/formats.md` first. It defines a text format and five ops
(agari, shanten, waits, score, legal). Another agent is generating corpus files for
the first four from a Python library and writing `tools/harness.py`; your job is an
independent second opinion plus the `legal` op.

Reference: ../3p/Mortal/libriichi (Rust; cargo 1.100 is
installed). Its default features include a pyo3 Python module; depend on it as a
path dependency with `default-features = false` (or vendor the minimal modules into
your crate if that fails to build) so no Python is needed.

Deliver:

1. `agpl/mj-rs/` — a Rust crate building a binary `mj-rs` that follows the runner
   contract in the spec (stdin requests -> stdout responses) for `shanten`, `waits`,
   `score`, and `legal`, implemented on top of libriichi's algo/ and state/ modules
   (shanten, agari calc, PlayerState legal-action flags). `agari` only if cheap.
2. `corpus/legal.txt` — about 3000 `legal` cases in the spec format, deterministic
   from a seed. Best source of realistic states: have libriichi play out random
   games (or replay ../3p/akochan/haifu_log_sample.json,
   an mjai log) and snapshot a seat's PlayerState at decision points, emitting the
   spec's inputs and the legal action set. Make sure these are well represented:
   chi with and without red fives, kuikae restrictions after chi and pon, riichi
   declaration choices, ankan during riichi (legal and illegal), kakan, kyuushu on
   the first turn, ron blocked by furiten, ron/tsumo blocked by no yaku, haitei /
   houtei / rinshan / chankan wins, calls refused at wall=0, 4-kan limit.
3. A cross-check mode: `mj-rs` can be run through `tools/harness.py` (once the other
   agent has written it; if it isn't there yet, write a tiny comparison script of
   your own under `agpl/mj-rs/`) against `corpus/shanten.txt`, `corpus/waits.txt`,
   `corpus/score.txt`. Report every disagreement in `agpl/mj-rs/DISAGREEMENTS.md`
   with the request, both answers, and your judgment of which is right and why.
   Do not edit the other agent's corpus files.

Where libriichi's rules differ from the spec (it follows Tenhou rules), note it in
`agpl/mj-rs/NOTES.md`. Where the spec's `legal` definition is ambiguous or can't be
derived from libriichi state, choose, and record it in `agpl/mj-rs/NOTES.md`.

Report: case counts, build instructions, disagreement summary, spec problems found.
