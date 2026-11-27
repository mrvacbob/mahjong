# Brief: finalize a shootout representative

Each language's representative entry (chosen by cross-review) gets its known bugs
fixed and one simplification pass before the languages are judged. You have one
entry: `shootout/<language>/opus/`. Write only inside it. No git commands.

1. Read the entry (DESIGN.md, NOTES.md, source) and what the reviewers said about
   it: search `docs/reviews/p2/codex.md`, `docs/reviews/p2/agy.md` and
   `docs/reviews/p2/agy-mercury.md` for your language's section on the opus entry.
2. Fix the bugs they found. `corpus/legal_review.txt` holds the confirmed failing
   requests. Fix the cause, not the case: both known bugs are about structural
   waits that include a fifth copy of a tile during the riichi-ankan check, and
   the reviewers suggest checking completion directly instead of going through
   shanten. Apply the cleanup items the reviewers listed for this entry where you
   agree; where you don't, say why in NOTES.md.
3. Then run the `simplify` skill (invoke it with the Skill tool) on the entry,
   treating the whole entry as the code under review, and apply what it finds.
   The goal is the version of this code that best shows what the language can do
   for this problem: less code where that makes it clearer, rules stated once and
   close to the rule text, types carrying the distinctions. Do not golf it, do not
   trade readability for speed, and do not change the design wholesale.
4. Keep it correct throughout: from the repository root,
   `python3.14 tools/harness.py shootout/<language>/opus/mj corpus/*.txt` must be
   100% (12,439 cases including legal_review.txt) after `./build.sh` from clean.
5. Append a "Finalization" section to NOTES.md: bugs fixed and their cause,
   what the simplify pass changed and what it left alone, lines of code before and
   after (non-blank, non-comment), `--time` numbers before and after, and anything
   in the language that got in the way. Update DESIGN.md if the design moved.

The contest rules still apply: standard library only; do not read other entries
under `shootout/`, or `3p/`, `agpl/`, `tools/oracle_mj.py`, `tools/gen/`.

Report: what you fixed, what simplify changed, before/after lines and timings.
