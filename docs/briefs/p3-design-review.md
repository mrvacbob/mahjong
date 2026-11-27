# Brief: review the Phase 3 engine design

You are one of three independent reviewers (Claude Opus, Codex, Gemini). Review
`docs/design/engine.md` in this repository: the design for a full riichi mahjong game
engine in Swift (round state machine, game flow, mjai events, player view,
validation plan). Nothing is implemented yet; finding problems now is cheap.

Read first: `docs/design/engine.md`, `spec/rules.md` (the rules; Mahjong Soul ranked
is the default, Tenhou second), `spec/formats.md` (existing line protocol),
`Sources/mj/` (existing hand-analysis code the engine builds on),
`docs/design/wasm-spike.md`. For the mjai protocol as Mortal speaks it you may read
`../3p/Mortal/docs` and `../3p/Mortal/libriichi/src/mjai` and `.../state` and
`.../arena` (AGPL: read to learn the protocol and behaviour, quote nothing longer
than a line or two).

Write your review to `docs/reviews/p3/design-<you>.md` (`opus`, `codex` or `agy`).
Do not edit any other file. Do not commit.

What to look for, most important first:

1. **Rule errors.** Anything in the design that contradicts `rules.md`, or anything
   in either that you believe is wrong for Mahjong Soul ranked or Tenhou. Give a
   source. In particular check section 4.1 (resolution of simultaneous answers,
   furiten when a call or pass loses to another seat's ron, furiten when a seat is
   not asked) and every bullet of 4.2.
2. **State the machine cannot represent, or sequences it gets wrong.** Walk real
   sequences through the phases: riichi discard ronned; added kan robbed; closed kan
   then rinshan tsumo; open kan, replacement draw, another kan, discard; fourth kan;
   pon then kuikae; last-tile discard; double ron with a riichi stick on the table;
   nine-terminals abort; four-winds abort. Say where the design is silent or wrong.
3. **mjai fidelity.** Event names, fields and ORDER versus Mortal's dialect,
   especially around reach / reach_accepted, kans and the `dora` event, hora and
   ryukyoku fields (deltas, ura markers), and what is masked for other seats.
   Will libriichi's player state accept our logs event for event?
4. **The validation plan (section 8).** Is the libriichi differential feasible as
   described? What does libriichi expose (legal-action flags, scoring, a full
   arena)? What will it NOT catch? Suggest additional cheap checks. Is there a
   lawful, practical source of real game logs in mjai form?
5. **API and Swift design.** Value-type state and copying cost, the `Player`
   protocol, `PlayerView` isolation, no-Foundation constraint, performance target,
   anything that will be awkward from WebAssembly/JavaScript later.
6. **The open questions in section 10.** Give your answer to each, briefly.
7. Anything missing that a full engine needs.

Format: a numbered list of findings, each with severity (blocker / should-fix /
suggestion), the section it concerns, what is wrong, and the change you propose.
Be concrete; prefer ten sharp findings to thirty vague ones. Mark anything you are
unsure of as unsure. End with a one-paragraph overall verdict.
