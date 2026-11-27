# Result

GHC 9.14.1, `-O2`, plain GHC build with only `base` and `containers`.
Both the normal harness and the final `--time` run passed.

| Op | Pass | Fail | Seconds | Requests/s | Requests/s excluding startup |
| --- | ---: | ---: | ---: | ---: | ---: |
| agari | 2,190 | 0 | 0.038 | 58,290.0 | 122,053.7 |
| shanten | 2,199 | 0 | 0.562 | 3,910.0 | 4,051.4 |
| waits | 1,996 | 0 | 0.872 | 2,289.2 | 2,341.9 |
| score | 5,291 | 0 | 0.080 | 65,731.8 | 86,928.8 |
| legal | 758 | 0 | 0.030 | 25,207.9 | 72,590.9 |
| Total | 12,434 | 0 | | | |

The harness measured 19.6 ms startup with empty input. The startup-adjusted
rates for the short batches are sensitive to that single measurement. The
first run measured 71.6 ms startup, longer than its entire agari or legal
batch, so the harness reported infinity for those two adjusted rates.

# Size

Counts exclude blanks, comments and the shell shebang.

| File | Lines |
| --- | ---: |
| Main.hs | 95 |
| Tiles.hs | 95 |
| Shape.hs | 122 |
| Score.hs | 242 |
| Legal.hs | 72 |
| build.sh | 4 |
| Total | 630 |

# Log

- Read the protocol and ranked rules, including the hand-derived fifth-copy
  and legal cases. Wrote the design before implementation.
- First GHC 9.14.1 build linked successfully. GHC flagged two partial
  `head` calls, an incomplete pattern for suit replacement, a redundant
  import (`foldl'` is in Prelude), and an unused record selector. The linker
  reported a missing SDK library search path.
- First timed harness run passed all 12,434 cases. Replaced the partial
  bindings with comprehension patterns and paired suit profiles with their
  inputs via `zip3`. Made both package dependencies explicit.
- Rebuilt after deleting the generated executable and compiler output.
  GHC emitted no source warnings. The linker repeated the SDK path warning
  and produced the executable. The normal and timed harness runs both
  passed. A three-line stdin smoke test returned a malformed-input error
  and continued with two valid answers in order.
- No compile failures or corpus failures occurred. The first build's
  partiality warnings were the main compiler feedback.

# Language verdict

1. Sum types and comprehensions fit the search. For example,
   `data Shape = Standard [Group] | SevenPairs | Orphans` lets scoring
   dispatch by shape, and `[k | k <- kinds, ...]` expresses the wait
   search directly. The same completion search handles legal wins and
   structural waits, including hypothetical fifth copies.
2. Scoring reads like the rules. A rule can be written as
   `("sanshoku", openReduced 2, acrossSuits runs)` and the winner is a
   lexicographic maximum over
   `(total r, multiple r > 0, han r, minipoints r, Down (names r))`.
   Most of the work was deciding which facts belong to the tiles, the
   decomposition, or the group completed by the winning tile. GHC's
   warnings also highlighted invariants the initial types did not capture.
   I would encode the single head directly in the standard shape if this
   model grew further.
3. Shanten is the performance cost. Describing suit profiles as lists of
   possible triples makes composition short, but the recursive search
   revisits residual counts and the joins allocate tuples and sets. The
   waits scan reuses the unchanged suit profiles, yet waits and shanten
   still lead the measured runtime. For a larger workload I would profile
   that search and try memoizing by packed suit counts.

# Spec or corpus problems

No new discrepancies found. The fifth-copy cases in `disputed.txt` follow
the authoritative structural shanten rule and pass with zero live copies.

# Unfinished

No failing or skipped corpus cases. The macOS linker emitted an SDK
search-path warning during both builds. The executable linked and ran.
