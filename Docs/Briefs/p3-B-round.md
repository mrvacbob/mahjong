# Brief: Phase 3 package B — the round state machine

Read `Docs/Design/engine.md` (current version; it changed slightly since package A),
`Spec/rules.md`, your own `Docs/Notes/p3-A.md`, and `Scenarios/FORMAT.md`.

First, two follow-ups from package A:

- **Wall key.** The design now says the generator key is
  `mix(seed) ^ mix(~UInt64(hand))` (one SplitMix64 output step each), replacing the
  linear key that could collide. Change `Wall`, `Spec/wall.md` and the test vectors
  (regenerate them from your independent Python implementation).
- **Temporary furiten.** `rules.md` now agrees with the design for both rulesets
  (ends at the next own draw; a call does not clear it), keeping your `Rules` field.

Then package B, as in design §4 and §6:

1. `RoundState` with the phases, `legalActions(for:)`, `apply`, `resolve`, the
   resolution table of §4.1, furiten from waits, every rule in §4.2, `RoundResult`
   with point changes (including pao redistribution, multi-ron, exhaustive-draw and
   nagashi payments), and the hot-path choices of §4.4.
2. `Event` (unmasked) with the fields of §6, emitted in the order §4.2 and §6 give.
   The mjai JSON codec is package D; here `Event` is a Swift type. Add a plain,
   stable text rendering of an event's type and actor (for example `pon(1)`) for
   tests.
3. A **scenario runner** in `Tests/RiichiTests`: loads the JSON that
   `python3.14 Tools/scenario.py` produces from `Scenarios/*.scn` (run the tool to
   see its output; read `FORMAT.md`; you may add a `--json-dir` or similar
   convenience to the tool if needed, but do not change scenario semantics) and runs
   every scenario whose expectations are about a single round. Scenarios about game
   end (`endgame_*`) wait for package C; skip them by name, visibly.
   Tests may use Foundation for JSON; the library may not.
4. **Do not edit the `.scn` files.** When a scenario fails, decide who is wrong. If
   the engine is wrong, fix the engine. If you believe the scenario is wrong (bad
   arithmetic, impossible tiles, contradicts `rules.md`), leave it failing, mark it
   as an expected failure in the runner with a one-line reason, and list it in
   `Docs/Notes/p3-B.md` with your working. A reviewer is checking the scenarios
   independently at the same time and may change some; re-run before you finish.
5. Unit tests of your own for anything the scenarios do not reach, and the
   invariants of design §8 layer 4 that apply to one round, run over a few thousand
   rounds of random and "eager" play (design §7 describes eager) driven directly
   through the API.
6. An in-process benchmark (a test or a hidden `mj` subcommand): rounds per second
   with random play, with and without event collection. Report it.

Constraints: corpus stays at 12,439 of 12,439; no Foundation in `Riichi`; no
third-party packages; never copy from `../3p/` or `AGPL/`; do not touch `AGPL/`,
`Scenarios/*.scn`, `shootout/`, `Corpus/`; do not commit. Write `Docs/Notes/p3-B.md`:
what you built, decisions the design left open, scenario disputes, anything in the
design or rules you now think is wrong, and the benchmark.
