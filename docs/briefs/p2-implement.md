# Brief: shootout implementation

You are writing one entry in a language shootout: the same riichi mahjong slice
implemented in Swift, Mercury, Python and Haskell by three different models. The
purpose is to compare the LANGUAGES for writing a mahjong engine: how directly the
rules can be expressed, what the compiler catches, how it performs, how painful it
was. Write the code you would want to maintain, idiomatic for the language, not a
transliteration of another language's solution.

Your language and your entry directory are given in the task message:
`shootout/<language>/<model>/`. Write only inside that directory. No git commands.

## Read first

- `spec/formats.md` — the protocol and the five ops (`agari`, `shanten`, `waits`,
  `score`, `legal`). Its body is authoritative.
- `spec/rules.md` — the rules (Mahjong Soul ranked, 4 players).
- `corpus/*.txt` — test cases: a request line, then `= ` and the expected response.
  `# ` comment lines often explain the derivation. `corpus/disputed.txt` and
  `corpus/legal_handwritten.txt` are good reading for the subtle rules.

## Rules of the contest

- Standard library only. Swift: Foundation allowed. Haskell: only packages that
  ship with GHC 9.14 (base, containers, array, text, bytestring, mtl, ...), built
  with cabal or plain ghc. Mercury 22.01: the standard library, built with
  `mmc --make`. Python: 3.14 stdlib, type-annotated.
- Do not read or search for other mahjong implementations: nothing under `3p/`,
  `agpl/`, `tools/oracle_mj.py`, `tools/gen/`, other entries in `shootout/`, or the
  web. Language and standard-library documentation is fine. Derive the logic from
  the spec.
- Your program must compute answers. It must not read the corpus at run time or
  embed expected answers or lookup tables derived from them. It will also be run
  on held-back cases you have not seen.
- Don't change anything outside your directory. If you think the spec or a corpus
  case is wrong, don't code around it silently: implement what the corpus expects
  and record it in your NOTES.md under "Spec or corpus problems".

## Deliverables, all in your entry directory

1. `DESIGN.md`, written BEFORE the code (update it at the end if the design moved):
   data representation for tiles/hands/melds; how hand decomposition is expressed;
   how yaku are declared and how a yaku's code relates to its rule text; how fu and
   interpretation choice work; how `legal` reuses the rest. One or two pages.
   Mercury entries: say where you use `bag` (multiset) versus `set` and why, and
   give determinism declarations for the main predicates.
2. The implementation, and `build.sh` (builds from clean; exits non-zero on failure)
   producing an executable `./mj` in your directory (a wrapper script is fine)
   that follows the runner contract in the spec.
3. Pass the corpus:
   `python3.14 tools/harness.py shootout/<language>/<model>/mj corpus/*.txt`
   (run from the repository root). Aim for 100%. Add `--time` for throughput.
4. `NOTES.md` with these sections, filled in honestly; this is data for the
   comparison, so do not tidy it up:
   - **Result**: harness pass/fail counts per op, and `--time` numbers.
   - **Size**: lines of code excluding blanks and comments, per file.
   - **Log**: a running record kept as you work (not reconstructed afterwards):
     each build-test cycle that failed, what the compiler or test said, and what
     the cause was. Note especially errors that took more than one attempt, APIs
     you expected that did not exist, and bugs the compiler caught for you versus
     bugs only the corpus caught.
   - **Language verdict**: what this language made easy and hard for this problem,
     with short code excerpts. What you would do differently.
   - **Spec or corpus problems**.
   - **Unfinished**: anything failing, skipped or hacked.

Stop when the corpus passes and the notes are complete, or when you are stuck:
in that case say exactly where and why in NOTES.md and in your final report.

Final report: pass counts, lines of code, the three most notable things about
doing this in this language.
