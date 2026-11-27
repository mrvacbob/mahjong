# Brief: shootout cross-review

Repo root: the directory you are started in. Read-only review: write exactly one
file, `docs/reviews/p2/<your-name>.md`. No other writes, no git commands. Do not
read the other reviewers' files in `docs/reviews/p2/` (you may read
`measurements.md` there).

Twelve entries implement the same slice (`spec/formats.md`, `spec/rules.md`,
brief in `docs/briefs/p2-implement.md`): `shootout/<language>/<model>/` for
language in swift, mercury, python, haskell and model in opus, codex, agy. All
twelve pass the corpus and a held-back set, so correctness on tested cases does
not separate them. Each has DESIGN.md, NOTES.md (with a working log) and source.

You review the EIGHT entries you did not write: for each language, the two
entries by the other two models. (If you are opus, skip `*/opus`; and so on.)

Part A — per language, compare the two entries and pick one. Judge:
1. Rule fidelity: can someone who knows riichi read a yaku, a fu rule, the
   kuikae rule, the riichi-ankan rule and find it stated once, close to how the
   rules state it? Quote the code for 2–3 rules from each entry side by side.
2. Structure: are tile kinds vs physical tiles, concealed vs melded groups, and
   decomposition vs interpretation kept apart by types, or by convention?
3. Idiom: is this how a good programmer in that language would write it, or a
   transliteration of imperative code? For Mercury: are nondeterminism, modes
   and determinism declarations used to carry the logic; is `bag` used where the
   problem is a multiset and `set` where it is not, and does that help or hurt?
4. Latent bugs: read for errors the corpus would not catch (inputs the generators
   never produce, rules covered by few cases). Report anything concrete with a
   failing request line if you can construct one and run it
   (`./build.sh` in the entry, then pipe a request to `./mj`).
5. Cheating or shortcuts: hard-coded answers, tables derived from the corpus,
   reading files at run time, special-casing corpus ids.
6. Whether its NOTES.md log looks like an honest working record, and what it
   tells you about how hard the language was for that model.
State which of the two you would keep as that language's representative and why,
and list what should be cleaned up in it before the languages are judged.

Part B — across languages, from all eight entries you read plus the measurements:
rank the four LANGUAGES for writing the full engine (round state machine, game
flow, protocol, bots calling into it millions of times, eventually a web
front end), separating what is inherent to the language from what was one
model's choice. Cover: expressiveness for rules, safety (what the compiler
proved), performance and how much work it took to get, how well AI agents coped
(use the logs), tooling/build/deployment (including reaching a browser), and
maintainability by a human who dislikes Python and likes Mercury. Say where you
are unsure.

Be concrete; quote code. No praise sections. Say plainly what you did not read.
