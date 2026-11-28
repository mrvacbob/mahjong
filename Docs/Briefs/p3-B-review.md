# Brief: review package B (the round state machine)

Review `Sources/Riichi/Round.swift`, `RoundLegal.swift`, `RoundResult.swift`,
`Action.swift`, `Event.swift` and their tests against `Docs/Design/engine.md` §4 and
§6 and `Spec/rules.md`. The author's notes are `Docs/Notes/p3-B.md`. The author is
now adding game flow and mjai in other files; ignore `GameState`, `RiichiMjai` and
new `mj` subcommands.

This is the heart of the engine, so hunt for wrong behaviour, not style:

1. For every row of design §4.1 and every bullet of §4.2, find the code that
   implements it and try to break it: construct a state (a wall and actions) where
   you believe the code does the wrong thing, and run it. `Tests/RiichiTests`
   shows how to drive a round from a wall; `Scenarios/FORMAT.md` plus
   `python3.14 Tools/scenario.py` let you write a scenario file and run it through
   the scenario test. Put reproductions in `Docs/Reviews/p3/B-<you>-repro/` (as
   `.scn` files or Swift test snippets); do not add them to `Scenarios/` or
   `Tests/`.
2. Payments: pao in every form, multi-ron with sticks and honba, exhaustive draw
   with 0–4 tenpai, nagashi (one, several, dealer), riichi sticks on ronned and
   accepted declarations, points conserved.
3. Furiten in all three kinds, including the cases the author lists as open.
4. State that can go stale: cached waits after calls and kans, ippatsu and
   first-go-around flags, kan dora owed, the drawn-tile slot.
5. Hidden nondeterminism, traps that malformed-but-legal play could hit
   (`precondition`, force unwraps, array indices), anything quadratic on the hot
   path.
6. The 7 scenarios the author disputes (notes §"Disputed scenarios"): give your
   own verdict on each, with working.

Write `Docs/Reviews/p3/B-<you>.md` (`codex` or `agy`): numbered findings, severity
(blocker / should-fix / suggestion), file and line, a concrete reproduction or the
reason you could not produce one, and the fix you propose. Do not edit `Sources/`,
`Tests/` or `Scenarios/`. Do not commit. Build products you create must not be left
in the tree outside `.build/`.
