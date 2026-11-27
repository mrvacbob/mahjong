# Brief: Phase 3 package F — scenario tests

Read `docs/design/engine.md` (draft 2) and `spec/rules.md` in full. You are writing
the hand-made tests that pin down the engine's behaviour on rules that are easy to
get wrong. The engine is being written by someone else at the same time; do not
read `Sources/`. Your expectations come from the rules, not from any code.

Deliver, all under `scenarios/` plus one tool:

1. **A scenario file format**, documented in `scenarios/FORMAT.md`: plain text, one
   scenario per file, readable and writable by hand. A scenario gives the ruleset
   (`mahjongsoul`, `tenhou`, or both with per-ruleset expectations), the round
   header (wind, round number, honba, sticks, scores, dealer), the four starting
   hands, the tiles each draw will produce (live draws, replacement draws, dora and
   ura indicators; anything unspecified is filled from the unused tiles
   deterministically), the sequence of decisions (for windows: every seat's answer,
   including passes that matter), and the expected outcome: the mjai event sequence
   where order is the point, legal-action assertions at named steps ("seat 2 may
   not chi here", "ron is not offered to seat 1"), furiten assertions, and final
   point changes, sticks and dealer repeat. Tiles in mpsz notation as in
   `spec/formats.md`.
2. **`tools/scenario.py`** (Python 3.14, standard library only): validates a
   scenario file (136-tile accounting, hands of 13, every referenced tile
   available) and expands it to JSON with the full wall in the layout of design §3,
   so the engine's test runner needs no parser of its own beyond JSON. `--check`
   mode validates every file under `scenarios/`.
3. **The scenarios.** At least one for every bullet in design §4.2, every row of
   the table in §4.1, every branch of §5, and every numbered case in `rules.md` §4
   that involves game flow rather than only scoring. Where the rulesets differ
   (triple ron, robbing a closed kan, pao on a composite yakuman, kan dora on a ron
   after an open kan, double yakuman, formal tenpai on a fifth copy), one scenario
   with both expectations. Where a ruling is marked unverified, write the scenario
   to the design's stated default and tag it `unverified` with the `rules.md` item.
   Include the sequences the reviewers walked: riichi discard ronned; riichi discard
   called; added kan robbed with ippatsu alive; closed kan then rinshan tsumo; open
   kan, replacement draw, another kan, discard, ron; fourth kan by a second seat
   then pon attempted; four kans by one seat; kuikae after chi and pon; dead-end
   call; last-tile discard; kan with one live tile left then tsumo (rinshan, not
   haitei) and then discard ronned (houtei); double ron with sticks on the table;
   triple ron; nine terminals; four winds; four riichi; no-yaku wait causing
   furiten without being asked; furiten surviving a call; riichi furiten after a
   skipped tsumo via closed kan; nagashi mangan with a tenpai dealer; every pao
   case; each end-of-game branch.
4. `scenarios/INDEX.md`: a table of scenario, what it pins down, source rule,
   verified or unverified.

Work every expected number by hand and show the working in a comment in the
scenario (han, fu, payment). If the design and `rules.md` disagree, or either looks
wrong, do not pick silently: write it to `rules.md` and list it in
`scenarios/QUESTIONS.md`.

Constraints: work only in `scenarios/` and `tools/scenario.py`. Do not read
`Sources/`, `agpl/` or `../3p/`. Do not commit. `python3.14 tools/scenario.py
--check` must pass on everything you deliver.
