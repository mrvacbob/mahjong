# Brief: Phase 3 packages C and D — game flow, mjai, command line

Read the current `Docs/Design/engine.md` (§4.2 gained four bullets since package B:
the nagashi event reason, robbed kans not counting, declining a self-drawn win, and
replacement draws not clearing temporary furiten; the last two answer points 1 and 2
of your package B notes, so implement the new `Rules` field), your
`Docs/Notes/p3-B.md`, and `AGPL/libriichi-check/README.md` for the input the
differential checker expects (do not read its Rust source or `mortal/`).

**Package C**, design §5: `GameState` (rules, seed, hands dealt, round wind and
number, honba, sticks, scores, current round), the after-round transition exactly
as written there, `GameResult`. Enable the `endgame_*` scenarios in the runner.

**Package D**, design §6–§7:

1. `Sources/RiichiMjai/`: encode every `Event` to mjai JSON with the superset of
   fields in the §6 table, decode mjai events and bot replies, hand-written JSON
   with no Foundation, skipping nested values it does not need. Masked events as a
   distinct type; `PlayerView`.
2. `mj selfplay` (random and eager bots; engine trace; unmasked log with `wall` on
   each `start_kyoku`), `mj replay`, `mj check-log`, and a `mj dump-state` (or a
   flag on `selfplay`) that writes, after every event and for all four seats, the
   legality rows `AGPL/libriichi-check/compare.py` expects from the engine side:
   read that script and the README for the exact row format, and say in your notes
   if the format cannot express something.
3. The mjai bot adapter (child process, one reply per event, two-step riichi,
   timeout, substitution and its four counters) with a tiny scripted fake bot as
   its test. Real Mortal and akochan are not needed yet.
4. The remaining invariants of design §8 layer 4 (view reconstruction from masked
   events, byte-identical replay, `check-log` accepting our own logs, answer-order
   independence), the coverage report of layer 5, and the Mercury cross-check dump
   of layer 3 (`score` and `legal` requests from self-play, compared by running
   both `./mj` and `Sources/Mercury/mj`; report the result).
5. Then run the real thing: build the checker as its README says (it is already
   built at `AGPL/libriichi-check/target/release/libriichi-check`), generate 2,000
   eager and 2,000 random games under `--rules tenhou`, run `check` and
   `compare.py`, and work through what it reports. For each difference decide:
   engine bug (fix it, add a test), a known libriichi difference already named in
   the checker's `NOTES.md` (leave it; it is counted), or something new (do not
   patch the checker; describe it in your notes with a minimal log). Report the
   final counts by category.

Scenario disputes from package B are being resolved by the scenario reviewers in
parallel; expect `.scn` files to change, re-run before finishing, and keep the
"known issue fails if it starts passing" guard.

Constraints as before: corpus 12,439 of 12,439; no Foundation in `Riichi` or
`RiichiMjai`; no third-party packages; never copy from `../3p/` or `AGPL/` (running
the checker and reading its README, NOTES and compare.py is fine); do not edit
`AGPL/` or `.scn` files; do not commit. Write `Docs/Notes/p3-CD.md`.
