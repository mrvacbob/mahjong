# Language shootout: results

The same slice of a riichi mahjong engine (win detection, shanten, waits,
scoring, legal moves; `spec/formats.md`) was written in Swift, Mercury, Haskell
and Python by three models each. Twelve entries, all standard library only.

## Process

1. Spec and corpus first, reviewed by all three models (`docs/reviews/p1/`).
2. Twelve implementations in isolated worktrees, no access to reference code.
3. Every entry measured the same way, including 11,569 held-back cases generated
   after the entries were finished (`docs/reviews/p2/measurements.md`).
4. Each model reviewed the eight entries it did not write (`docs/reviews/p2/`).
5. One representative per language: Opus's entry in all four. Python, Haskell and
   Mercury by 2-of-3 reviewer votes. Swift was a three-way tie, broken toward
   Opus's so that one model wrote all four finalists and the comparison is about
   the languages.
6. Representatives had review-found bugs fixed and one `/simplify` pass, then
   were re-measured.

## Correctness

All twelve entries passed all 12,434 corpus cases and all 11,569 held-back cases.
Tested correctness did not separate the languages.

Bugs the tests missed, found by cross-review and now in `corpus/legal_review.txt`:

| Entry | Bug | Would a compiler have caught it? |
|---|---|---|
| Swift (opus) | Shanten cache key packed counts in base 5; a count of five collided with another hand and poisoned the cache for the rest of the process | No: the key was a plain `Int` |
| Mercury (opus) | Honor-tile shanten miscounted five copies, allowing an illegal riichi kan | No: arithmetic |
| Swift, Haskell (agy) | Decomposition ignored leftover tiles on over-long input | No |
| Python (codex), Swift, Haskell (agy) | Kokushi accepted 13 orphans plus any tile (caught by the corpus) | No |

No type system here caught a rules bug. What the compilers caught were type,
mode, determinism and exhaustiveness slips before the first run. What found the
real bugs was a second independent implementation disagreeing.

## The four representatives after finalization

Measured by the coordinator; median of three runs; requests per second including
process start-up. Lines are non-blank, non-comment source lines.

| | Swift | Mercury | Haskell | Python |
|---|---:|---:|---:|---:|
| Lines | 991 | 1,312 | 774 | 887 |
| Corpus (12,439) | all pass | all pass | all pass | all pass |
| Held-back (11,569) | all pass | all pass | all pass | all pass |
| agari req/s | 162,000 | 148,000 | 103,000 | 34,000 |
| shanten req/s | 179,000 | 32,000 | 46,000 | 27,000 |
| waits req/s | 44,000 | 8,600 | 4,400 | 4,200 |
| score req/s | 91,000 | 110,000 | 52,000 | 21,000 |
| legal req/s | 35,000 | 12,000 | 16,000 | 9,600 |
| Clean build | ~4 s | ~1 s | a few s | none |
| Failed builds before first pass (opus's log) | 2 | several, all compile-time | 3 warnings/errors | 0 |
| Bugs the corpus caught (opus's log) | 0 | 0 | 0 | 0 |

Across all twelve entries the pattern holds: every Swift entry runs waits at
38,000–50,000 req/s without tuning; no other entry in any language exceeds
15,000. Mercury matches or beats Swift on scoring. Haskell needed three rounds of
performance work to get waits from 60 to about 4,000 req/s.

## The same rule in each language (pinfu)

Mercury — one clause of the nondeterministic `yaku/4` relation, and the predicate it calls:

    yaku(C, I, "pinfu", 1) :-
        pinfu(C, I).

    pinfu(C, standard(P, Ms, ryanmen)) :-
        C ^ closed = yes,
        list.all_true((pred(M::in) is semidet :- M ^ shape = run), Ms),
        pair_fu(C, P) = 0.         % the pair is not a value tile

Swift — one row of a table keyed by an enum of yaku names:

    Yaku(.pinfu, closed: 1, open: nil) { $0.isPinfuShape },

    var isPinfuShape: Bool {
        menzen && runs.count == 4 && wait == .ryanmen && !(pair.map(isValue) ?? true)
    }

Haskell — one row of a list of predicates:

    , closedOnly "pinfu" 1 pinfu

Python — a decorated function with the rule as its docstring:

    @yaku("pinfu", closed=1)
    def pinfu(w: Win) -> bool:
        """Closed; 4 sequences, non-yakuhai pair, ryanmen wait."""
        return (len(w.seqs) == 4 and w.pair is not None and not is_yakuhai_kind(w, w.pair)
                and w.wait is Wait.RYANMEN)

Hand decomposition in Mercury is the piece no other language matches for
directness: remove the smallest tile from a bag, and it starts either a triplet
or a run.

    sets(B, []) :-
        bag.is_empty(B).
    sets(B0, [G | Gs]) :-
        bag.remove_smallest(K, B0, B1),
        (
            bag.remove_list([K, K], B1, B2),
            G = triplet(K)
        ;
            offset(K, 1, K1),
            offset(K, 2, K2),
            bag.remove_list([K1, K2], B1, B2),
            G = run(K)
        ),
        sets(B2, Gs).

On bag versus set: `bag` reads best for decomposition and dora counting and costs
nothing measurable there. It is the wrong shape for shanten, where every Mercury
entry dropped to per-suit count lists with `pragma memo`. `set` is right for wait
sets, kuikae kinds and yaku sets.

## Reviewer rankings for the full engine

All three reviewers, independently: **Swift, Mercury, Haskell, Python.**
(Gemini first ranked Haskell second without having read the Mercury entries, and
moved Mercury up after reading them.)

| | Swift | Mercury | Haskell | Python |
|---|---|---|---|---|
| Expressing rules | Good: enums with payloads, exhaustive switches, rule tables | Best: rules as clauses, nondeterministic search, modes and determinism checked | Good: pattern matching, list monad | Good to read, nothing checked |
| What the compiler proves | Types, exhaustiveness; concurrency checks were noise here | Types, modes, determinism | Types, exhaustiveness with `-Wall` | Syntax |
| Speed without tuning | Fastest everywhere | Fast on scoring, 4–10x slower on search | Slow until tuned, hard to predict | 4–12x slower than Swift |
| Agents writing it | No trouble | Worked for all three models; more compile cycles, all on library names and syntax | No trouble with correctness; performance took rounds | Easiest |
| JSON, protocol, tooling | Built in | No JSON in the standard library; small ecosystem | Fine once Hackage is allowed | Built in |
| Browser | Official WebAssembly SDK (not tested here) | No maintained route known; server-side only | GHC WebAssembly backend (not tested here) | Pyodide, heavy |

## Recommendation

**Write the engine in Swift, and keep the Mercury implementation alive as an
independent second implementation of the rules core.**

- Swift for the engine because Phase 3 onward is a state machine, a JSON
  protocol, bots calling shanten and waits millions of times, and eventually a
  browser. Swift was fastest with no tuning in all three models' hands, has JSON
  and a WebAssembly path, and its sum types fit the round state machine.
- Mercury kept because it is the clearest statement of the rules, it already
  exists and passes everything, and the one thing that found real bugs in this
  shootout was two independent implementations disagreeing. Running the Mercury
  core against the same corpus and fuzzing it against the Swift engine is cheap
  insurance, and it is where new rules can be worked out first.
- Mercury as the main engine is defensible if the engine only ever runs on a
  server: Opus's review says it "plausibly moves to first" in that case. The costs
  would be writing JSON handling, a 4–5x slower waits path for bots, and no
  browser build.

Not verified here, and worth a short spike before committing: that the Swift
entry builds to WebAssembly at an acceptable size, and what in-process (not
per-process) throughput looks like under a bot workload.
