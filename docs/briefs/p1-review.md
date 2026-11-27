# Brief: Phase 1 gate review (spec + corpus)

Repo: /Users/astrange/Projects/mahjong/my_mahjong. Read-only review: write exactly
one file, `docs/reviews/p1/<your-name>.md`. No other writes, no git commands. Do not
read the other reviewers' files in `docs/reviews/p1/`.

Context: we are about to have three models each implement the same riichi mahjong
slice in Swift, Mercury, Python and Haskell, judged against a shared corpus. Errors
in the spec or corpus now become wasted work times twelve. Find them.

Review:
- `spec/rules.md` — Mahjong Soul ranked 4-player rules (written by one model from
  web research; riichi.wiki was unreachable at the time). You may use web search.
- `spec/formats.md` — text protocol, five ops, and its Decisions log.
- `corpus/*.txt` — expected answers. agari/shanten/waits/score come from a Python
  library and agree with an independent Rust reference (libriichi). `legal.txt` has
  ONE source (libriichi, a Tenhou-rules engine) and is the least trusted file.
- `tools/harness.py` if you want to run things:
  `python3.14 tools/harness.py corpus/rs/target/release/mj-rs corpus/*.txt`

Answer these specifically, each with a verdict and evidence:
1. Can chankan combine with ippatsu? rules.md says no (item 26) and the corpus
   avoids the combination. Is that right under Mahjong Soul rules?
2. Riichi ankan: formats.md requires that neither waits nor hand interpretation
   change. Is that Mahjong Soul's rule? Check the legal.txt cases that exercise it.
3. Kuikae: exactly which discards are forbidden after chi and pon; do the legal.txt
   cases match? Is "chi left out if every remaining discard would be kuikae" right?
4. Fu and scoring rulings in rules.md: double-wind pair 4 fu, rinshan tsumo fu,
   kazoe yakuman, the four double yakuman, yakuman stacking, pao. Any wrong?
5. Hand-check at least 25 `legal` cases and 25 `score` cases of your own choosing,
   biased toward the tricky ones. Derive the answer yourself before looking at the
   expected line. List every case you believe is wrong, with your derivation.
6. Ambiguities: places where two competent implementers would read formats.md
   differently and one would fail the corpus through no fault of their own.
7. Coverage: important behaviour inside the five ops that no corpus case tests.
8. Is the slice the right size and shape for comparing languages? Anything that
   mostly tests parsing or bookkeeping and should be cut, or anything missing that
   would separate the languages?

Format: findings ordered by severity, each with file/case id, what's wrong, and the
fix you propose. Say plainly what you did not check. No praise section.
