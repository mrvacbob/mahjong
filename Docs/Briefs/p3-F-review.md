# Brief: review the scenario tests (package F)

`Scenarios/*.scn` (54 files, format in `Scenarios/FORMAT.md`, validator
`python3.14 Tools/scenario.py --check`) are hand-written tests that will be treated
as the truth the engine must match, so an error here becomes a bug in the engine.
They were written by Gemini from `Docs/Design/engine.md` and `Spec/rules.md`. You
are the independent check. Do not read `Sources/`.

For every scenario:

1. Replay it by hand: are the tiles consistent (13-tile hands, draws in the right
   order for the turn sequence including calls and replacement draws, nothing used
   five times)? Does each step follow from the previous one? The validator checks
   tile accounting, not sense.
2. Is every expectation right under `Spec/rules.md` for the stated ruleset: legal
   actions asserted, furiten, event order (design §4.2 and §6), yaku, han, fu,
   payments, sticks, honba, dealer repeat? Redo the arithmetic yourself.
3. Does it actually reach the situation its title claims?

Since this review was commissioned, two rulings changed and scenarios must follow:
temporary furiten now ends at the next own draw under both rulesets, and a call does
not clear it (`rules.md` `furiten_temporary`); adjusted game scores are integer
points (+27.0 is 27000).

Then coverage: compare `Scenarios/INDEX.md` with design §4.1 (every table row),
§4.2 (every bullet), §5 (every branch) and `rules.md` §4. List what is missing.

You may fix scenarios directly when the error is clear (arithmetic, tile slips, the
two rulings above), keeping `--check` passing, and you may add missing scenarios.
Record every change, with before and after and your reasoning, in
`Docs/Reviews/p3/F-codex.md`, along with anything you believe is wrong but did not
change, and the coverage gaps. Do not touch anything outside `Scenarios/` and that
review file. Do not commit.
