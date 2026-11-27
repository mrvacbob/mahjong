# Brief: Phase 3 package E — differential checker on libriichi

Read `docs/design/engine.md` (draft 2), especially §3 (wall layout), §4, §6 (events)
and §8 layer 2, then `agpl/mj-rs/README.md` and `NOTES.md` for how the existing AGPL
tool is kept separate. Mortal is checked out at `../3p/Mortal`.

Build a new Rust crate, `agpl/libriichi-check/`, AGPL-3.0-or-later, that depends on
Mortal's real `libriichi` (by path, or vendored; it must build offline after a
one-time fetch, and the README must give the exact steps including whatever Python
or pyo3 set-up libriichi's build needs). Do not grow `agpl/mj-rs`.

Input: unmasked mjai logs written by our engine (JSON lines). Each `start_kyoku`
also carries `wall`: 136 mjai tile names in the layout of design §3. Fields beyond
Mortal's are a superset (design §6) and must be tolerated.

Checks, per hand, under Tenhou rules:

1. **Board replay.** Load the wall, hands and indicators into libriichi's own board
   (`arena`), drive it with the actions the log shows were taken, and compare its
   events with the log event by event, then point changes, sticks left on the table,
   and whether the dealer repeats.
2. **Legality.** Feed each seat's masked view of the events to libriichi's player
   state. After every event, for all four seats, emit libriichi's action flags,
   discard candidates, kan candidates, waits, shanten and furiten flag as one JSON
   line per seat, in a format you document. Our engine will emit the same from its
   side and a small script will diff the two; write that script too
   (`compare.py`), with the expected-difference list applied by name.
3. **Known differences.** Keep a written, named list in the crate of where
   libriichi departs from Tenhou's rules or from our log conventions (design §8
   names several; verify each by reading libriichi and add what you find). Every
   filtered difference is counted in the report. Nothing is filtered silently.

Report format: first divergence per hand with file, hand, event index, seat, both
sides' values; totals at the end; non-zero exit on any unexplained difference.

Since our engine does not exist yet, prove the tool on logs you generate with
libriichi's own arena (a few hundred games with its tsumogiri or other built-in
agent, rewritten into our input format with the `wall` field): the checker must
pass them, and must fail when you corrupt a log (change a discard, a delta, drop a
`dora`). Include those self-tests.

Constraints: work only inside `agpl/libriichi-check/`. Do not read `Sources/`
(independence from the engine is the point). Do not commit. Add build output to a
local `.gitignore`. Write `agpl/libriichi-check/NOTES.md`: what works, what libriichi
could not check, and every place the design's description of mjai order or fields
is wrong according to libriichi's source.
