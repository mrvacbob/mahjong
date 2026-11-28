# Brief: Phase 3 package A — foundation

Read `Docs/Design/engine.md` (draft 2) in full, then `Spec/rules.md`,
`Spec/formats.md`, and the existing code in `Sources/mj/`. You are implementing
package A only. Packages B–D (the round state machine, game flow, mjai) come later
and will be yours too, so shape A for them.

Deliver:

1. **Library split** as in design §2: `Sources/Riichi/` (library, no imports at all),
   `Sources/mj/` (executable: the line protocol), `Tests/RiichiTests/`
   (swift-testing). `Sources/RiichiMjai/` is not part of A. Declare `public`
   deliberately. `./build.sh` must still produce `./mj`.
2. **`Rules`** with `.mahjongSoul` and `.tenhou`: a field for every row of
   `rules.md` §1 where the two differ or the row is marked unverified, plus the
   fields design §4.2 and §5 name. Thread it through scoring, the yaku tables and
   the legality code. The line protocol keeps Mahjong Soul as its default and gains
   an optional `rules=tenhou` key on `score` and `legal` (add it to
   `Spec/formats.md`).
3. **`Seat`, `TableMeld`** (design §3), with the analysis `Meld` derived from it.
4. **`Wall`**: validated explicit init, the layout of design §3, and the seeded
   shuffle exactly as specified there. Write the algorithm out in a new
   `Spec/wall.md` precisely enough for another language to reproduce it, with three
   test vectors (seed, hand, full 136-tile wall).
5. **Thread safety**: `ShantenCalculator` usable from several threads; the package
   builds in Swift 6 language mode with no concurrency warnings.
6. **`Counts` in fixed inline storage** if it is a contained change; otherwise leave
   a note.
7. Unit tests for the above, including Tenhou-rules scoring cases (single yakuman
   for the four hands Mahjong Soul doubles; tenhou not upgraded).

Constraints:

- `python3.14 Tools/harness.py ./mj Corpus/*.txt` must stay at 12,439 of 12,439.
  Run it before you finish and report the number.
- Also confirm `sh Sources/Mercury/build.sh` is unaffected (do not edit it).
- No Foundation in `Riichi`. No third-party packages.
- Never copy code from `../3p/` or `AGPL/`.
- Do not touch `AGPL/`, `Scenarios/`, `Tools/scenario*`, `shootout/`, `Corpus/`.
  Other agents are working in the first three at the same time.
- Do not commit. Write `Docs/Notes/p3-A.md`: what you did, every decision the design
  left open and how you settled it, anything in the design you think is wrong, and
  throughput before and after (harness `--time`).
