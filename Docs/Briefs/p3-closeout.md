# Brief: Phase 3 close-out

State: all 134 scenarios pass with no known issues; the corpus is 12,439 of 12,439;
the libriichi board replay and the Mercury cross-check were re-run clean after the
real-log rule changes. Three things stand between here and the Phase 3 gate in
`Docs/Design/engine.md` §9.

1. **The unexplained real-log cases** in `Docs/Notes/p3-reallogs.md` (game ids are
   in `/Volumes/Psyche/mahjong/work/reallogs/cases.md`; the logs are private
   third-party data and stay out of the repository): the Jade shousangen hand
   recorded as 5,200 against our 8,000; the two Tenhou kuikae discards (2012,
   2013); the two unpaid dealer nagashi hands (2019, 2021); and the four Tenhou
   hands where a seat that declined a tsumo by declaring a kan was later able to
   ron. For each, work out by hand what happened and decide: engine bug, rule we
   have wrong, rule that changed on a known date, or defective record. For the
   declined-tsumo case, settle `temporaryFuritenOnDeclinedTsumo` and its
   "survives the kan" detail from the evidence, looking for more discriminating
   hands across all years on both sites. Fix what is ours, with tests; write a new
   scenario description (as prose in your notes, not a `.scn` file) for anything
   the scenario writers should add.
2. **Directed coverage.** Random and eager self-play never reach: four winds, four
   riichi, triple ron, a robbed closed kan, pao by tsumo / by third-party ron / by
   ron from the liable seat, nagashi, four kans by one seat, and several
   end-of-game branches. Add a way to reach each on purpose in bulk: scripted bots
   with goals (for example "collect dragons and call everything", "discard only
   terminals and honors", "kan everything") and, where bots alone cannot get
   there, walls arranged for the purpose and then perturbed at random so that many
   distinct games exercise the branch. Run them with the invariants on, through
   the libriichi differential under Tenhou rules (`Tools/libriichi_diff.sh`), and
   through the Mercury dump under Mahjong Soul rules. The coverage report must show
   every listed branch reached at least a few hundred times, or say why a branch
   cannot be reached that way. Investigate every difference as before.
3. **The gate numbers.** With everything fixed, run the design's gate: 50,000 eager
   and 50,000 random Tenhou-rules games against libriichi (board replay and
   classified legality rows), plus the directed games, and report totals.

Also re-run a slice of the real-log campaign (Tenhou 2024, Throne 2024, Jade 2024)
with the final binary to confirm nothing regressed.

Constraints as before: corpus and `swift test` green; no Foundation in `Riichi` or
`RiichiMjai`; do not edit `AGPL/` or `.scn` files; no game data in the repository;
do not commit. Write `Docs/Notes/p3-closeout.md`.
