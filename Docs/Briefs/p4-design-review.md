# Brief: review the Phase 4 design (bots and arena)

Review `Docs/Design/bots.md`. Context: `Docs/Design/engine.md` (the engine it builds
on, especially §6 and §6.1), the public API in `Sources/Riichi/View.swift` and
`Analysis.swift`, the existing bots and driver in `Sources/mj/Bots.swift` and
`Driver.swift`, and the roadmap's intent: a ladder of bots of increasing strength,
used later as opponents for LLM players and for a teaching website.

Write `Docs/Reviews/p4/design-<you>.md` (`opus`, `codex` or `agy`). Do not edit
anything else. Do not commit. Numbered findings with severity (blocker /
should-fix / suggestion), the section, what is wrong, the change you propose. Then
your answer to each open question in §7, and a verdict.

Look hardest at:

1. **The ladder (§3).** Is each level a real, separable step? Is anything in the
   wrong order, missing (for example: tenpai and wait quality, defence against
   open hands, placement awareness in the last hands, riichi versus damaten), or
   so vague that two writers would build different bots? Propose precise
   definitions where the text is hand-waving, especially levels 3, 4 and
   `digital`.
2. **The arena's statistics (§4).** Seat rotation and seed blocking, what a block
   is for each format, whether the interval method is right for placement data,
   how many games the ladder gate needs to resolve realistic differences (give
   numbers), the rating fit, and anything that would let a difference appear that
   is not there.
3. **The `Bot` protocol (§2).** Sufficient for every level, for an mjai wrapper and
   for WebAssembly? What must a bot be able to see that `PlayerView` plus masked
   events do not give it?
4. **Mortal and akochan (§5).** What will actually go wrong building and running
   them on macOS arm64 with the checkout in `../3p/`, what the mjai dialect
   differences are, and whether the measurement plan is sound.
5. **The human-agreement yardstick**: is it meaningful, and what are its traps?
6. **Determinism and hidden information** for bots and the arena.
