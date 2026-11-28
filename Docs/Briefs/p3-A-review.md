# Brief: review package A

Review the Swift code in `Sources/Riichi/`, `Sources/mj/`, `Tests/RiichiTests/`,
plus `Spec/wall.md` and the `rules=` addition in `Spec/formats.md`, against
`Docs/Design/engine.md` §2–§3, `Spec/rules.md`, and the brief
`Docs/Briefs/p3-A-foundation.md`. The author's notes are `Docs/Notes/p3-A.md`.

Another agent is extending these files right now (adding the round state machine),
so you may see new files and work in progress; review what package A covers and
ignore `RoundState` and later.

Look for, most important first:

1. **Wrong rules.** Every `Rules` field: is the value for `.mahjongSoul` and
   `.tenhou` what `rules.md` says, and is the field actually consulted everywhere it
   should be (scoring, yaku, fu, legality, tenpai at a draw)? Anything still
   hard-coded to one ruleset?
2. **The wall.** Does the code do what `Spec/wall.md` says, is the spec complete
   enough to reimplement, is the bounded sampling unbiased, are the layout accessors
   right for each dealer? Reimplement it independently in Python from the spec
   alone and compare with the test vectors (note: the key derivation is being
   changed to `mix(seed) ^ mix(~hand)`; check whichever version is in the tree
   consistently).
3. **`TableMeld`**: kuikae, consumed tiles, added kan, red fives.
4. **Bugs** of any kind, thread safety, anything that depends on hash order,
   accidental Foundation use, API that will be awkward for a state machine or from
   WebAssembly.
5. **Tests**: what is not tested that should be.

Write `Docs/Reviews/p3/A-agy.md`: numbered findings with severity (blocker /
should-fix / suggestion), file and line, what is wrong, and the fix you propose.
Reproduce anything you call a bug with a concrete input where possible (the `mj`
line protocol is in `Spec/formats.md`; build with `./build.sh`, but do not leave
build products or edits behind other than your review file). Do not edit code. Do
not commit.
