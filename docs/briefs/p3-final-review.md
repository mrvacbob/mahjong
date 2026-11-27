# Brief: final review of the Phase 3 engine

The engine is believed complete for Phase 3. Evidence so far: 134 scenarios;
109,400 Tenhou-rules self-play games against libriichi with no unexplained
difference; Mercury agreeing on millions of requests; 2.5M real Tenhou games and
4.1M real Mahjong Soul games replayed with every difference explained
(`docs/notes/p3-reallogs.md`, `docs/notes/p3-closeout.md`). Earlier reviews and
their outcomes are in `docs/reviews/p3/`. Your job is to find what all of that
missed, and to judge whether the code is fit to build bots, a benchmark and a
website on.

Review the whole of `Sources/` and `Tests/` at HEAD, with `docs/design/engine.md`,
`spec/rules.md`, `spec/formats.md` and `spec/wall.md`.

1. **Where the evidence is thin.** The checks above are strong on what real games
   and libriichi contain, and weak elsewhere. Go there: Mahjong Soul-only rules
   that libriichi cannot check and logs rarely show (composite pao, double
   yakuman combinations, kokushi robbing a closed kan, chained-kan dora);
   `Rules` fields in non-preset combinations; the player view and masked events;
   the mjai bot adapter under misbehaving bots; East-only games; anything the
   notes list as undecided. Construct cases and run them.
2. **Design and code quality**, as someone who must now build on it: is the public
   API of `Riichi` the right one for a bot (given a `PlayerView`, choose an
   action), for an LLM tool server (legal moves, shanten and ukeire, score a
   hypothetical hand, safe tiles), and for JavaScript through WebAssembly? What is
   missing, awkward or leaking internals? Is `Round.swift` maintainable, or should
   it be restructured before more is stacked on it? Name concrete refactorings
   worth doing now and ones to leave.
3. **Documentation drift.** Does `docs/design/engine.md` still describe what was
   built? Do `spec/rules.md` and `Rules.swift` agree field by field, value by
   value, for both presets? List every mismatch.
4. **Tests.** What is asserted nowhere? Which tests would still pass if the code
   were wrong?

Write `docs/reviews/p3/final-<you>.md` (`codex` or `agy`), writing early and
appending as you go: numbered findings with severity (blocker / should-fix /
suggestion), file and line, reproduction or why none, proposed fix; then a section
of API recommendations for Phase 4 and 5; then a verdict: ready to build on, or
not, and what must change first. Put reproductions in
`docs/reviews/p3/final-<you>-repro/`. Do not edit anything else. Do not commit.
