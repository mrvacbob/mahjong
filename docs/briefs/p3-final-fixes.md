# Brief: fixes from the final Phase 3 reviews

Two final reviews are in: `docs/reviews/p3/final-codex.md` (reproductions in
`final-codex-repro/`) and `docs/reviews/p3/final-agy.md` (`final-agy-repro/`). Read
both in full, including their API, documentation-drift and test-audit sections.
Also new since your last session: five scenario changes (`declined_tsumo_*`,
`riichi_ankan_of_winning_tile`, `no_chiihou_after_own_daiminkan`; 138 scenarios).

1. **Fix or rebut every finding**, each with a test that fails before the fix. In
   particular:
   - Codex's blocker: the mjai adapter turns a legal ron during a chained kan into
     a pass with no substitution recorded. Fix the cause, not the instance: a reply
     must be bound to the prompt it answers (which event, which seat, which
     options), and any reply the adapter cannot bind or map is a counted
     substitution, never a silent pass.
   - Every trap reachable from outside the library (line protocol input, mjai
     input, `Rules` values, honba and timeout ranges, the public scorer): public
     entry points validate and return errors; `precondition` is for internal
     invariants only. On wasm a trap kills the whole instance.
   - `winRequest(for:)` honba on multi-ron, `Mjai.reply` missing fields,
     `Mjai.action` validation, the folded view's final scores and sticks,
     grandchild processes of a bot (process-group kill).
   - Tests that cannot fail (Gemini's test audit) and things asserted nowhere:
     make them real, including East-only games through `GameState` and
     `mj selfplay`, `openKanDoraBeforeRon == false`, `allLastTestAfterNagashi ==
     false`, and the scenario runner's silent pass for a seat the scenario did not
     list (an unlisted seat being asked should be a failure unless the scenario
     says otherwise; check all 138 still pass and report any that do not, with
     your working, without editing `.scn` files).
   - Documentation drift: make `docs/design/engine.md` describe what was built
     (rewrite stale passages, do not append corrections), and make `spec/rules.md`
     and `Rules.swift` agree field by field; list any row you changed.
2. **API for Phase 4 (bots) — the small, clearly needed part only.** Both reviewers
   ask for: `GameState.view(of:)`; on `PlayerView`, seat wind, closed-hand and
   riichi helpers, the seat's waits and furiten parts, and counts of tiles visible
   to that seat; a per-discard analysis (for each legal discard: resulting
   shanten, the tiles that improve it, and how many of those remain unseen from
   this seat's view); `ScoreRequest` accepting table melds; and basic defensive
   facts against a seat (genbutsu, suji, tiles with no copies left). Add these as
   pure functions with tests, no Foundation, nothing that needs the full
   `RoundState`. Do **not** build the JSON codecs for views, the versioned wasm
   boundary or a new decision-envelope protocol beyond what the blocker fix needs;
   those get their own design in Phase 5. Do not restructure `Round.swift` now;
   put your own assessment of the reviewers' restructuring suggestions in the
   notes.
3. **Re-verify**: corpus; `swift test` fully green with an empty known-issue list;
   1,000 eager and 1,000 random Tenhou games through `tools/libriichi_diff.sh`;
   the directed scenarios under both rulesets; `tools/mercury_diff.sh`; and the
   real-log slice (Tenhou 2024, Throne 2024, Jade 2024).

Constraints as before: no Foundation in `Riichi` or `RiichiMjai`; do not edit
`agpl/` or `.scn` files; no game data in the repository; do not commit. Write
`docs/notes/p3-final-fixes.md`: each finding and its outcome, the API added, and
the re-verification numbers.
