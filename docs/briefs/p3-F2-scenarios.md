# Brief: scenario tests, second batch

The first 54 scenarios (`scenarios/*.scn`) were reviewed by Codex
(`docs/reviews/p3/F-codex.md`). Read that review in full first: it changed 26 of
them, and the reasons are lessons for this batch. The recurring errors were:

- **accidental waits**: filler hands that happened to be tenpai (usually on seven
  pairs), which changed draw payments or made a seat able to ron;
- **missing answers**: a seat that could legally pon, chi or ron in a window was
  not given an explicit answer (every seat with any legal option must answer);
- **own-discard furiten** in hands meant to win by ron;
- event sequences too loose to catch the fault the scenario is about.

Check each new scenario against all four before moving on: for every discard, ask
of each other seat "could this seat call or win on it?", and for every hand at a
draw, "is this seat tenpai in any form, including seven pairs and thirteen orphans?"

Now write scenarios for every gap listed in the "Coverage" section of that review
(§4.1 rows, §4.2 bullets, §5 steps, and `rules.md` §4 items), one scenario per gap
unless two fit naturally. Same format (`scenarios/FORMAT.md`), same rules as the
first brief (`docs/briefs/p3-F-scenarios.md`): work every number by hand in a
comment, use `rules: both` where the rulesets differ, tag `unverified` where the
ruling is, follow `spec/rules.md` and list disagreements in
`scenarios/QUESTIONS.md`. Note the current rulings: temporary furiten ends at the
next own draw under both rulesets and a call does not clear it; adjusted game
scores are integer points.

Update `scenarios/INDEX.md`. `python3.14 tools/scenario.py --check` must pass. Do
not change the existing 54 scenarios or `tools/scenario.py` semantics (if the format
cannot express something a gap needs, say so in `QUESTIONS.md` instead). Do not read
`Sources/`, `Tests/`, `agpl/` or `../3p/`. Do not commit.
