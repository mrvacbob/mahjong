# Result

Mercury 22.01.9, `mmc --make`, `hlc.gc`, optimization level 4. A clean build
passed both the mixed-op harness and the per-op timing harness.

| Op | Pass | Fail | Seconds | Requests/s | Requests/s excluding startup |
| --- | ---: | ---: | ---: | ---: | ---: |
| agari | 2,190 | 0 | 0.015 | 146,526.7 | 576,094.8 |
| legal | 758 | 0 | 0.060 | 12,719.0 | 15,644.7 |
| score | 5,291 | 0 | 0.047 | 112,011.7 | 146,599.6 |
| shanten | 2,199 | 0 | 0.080 | 27,364.9 | 31,771.1 |
| waits | 1,996 | 0 | 0.338 | 5,905.6 | 6,107.0 |
| Total | 12,434 | 0 | | | |

Empty-process startup was 11.1 ms. The estimate excluding startup is especially
sensitive to timing variation for agari.

# Size

| File | Lines excluding blanks and comments |
| --- | ---: |
| actions.m | 102 |
| mj.m | 108 |
| scoring.m | 313 |
| shape.m | 158 |
| tiles.m | 151 |
| build.sh | 3 |
| Total | 835 |

# Log

- I included a read-only `git status --short` in the command that first opened
  the brief, before seeing its prohibition on git commands. It printed no
  status entries. I used no further git commands.

- Read the protocol and ranked rules, then reviewed corpus coverage and the
  hand-derived structural-wait and legal cases before writing the design.

- Build 1 stopped in actions.m because only the list overload of `++` was
  imported. Added the string module.

- Build 2 rejected `bag.count/2`. The installed interface calls the
  multiplicity function `bag.count_value/2`.

- Build 3 linked successfully. The first mixed-op harness run passed all
  12,434 cases. The corpus did not expose a scoring or shape bug.

- The first timed run passed too. During review, I made hand exposure explicit
  in scoring, bounded chi starts to their suit, and added size checks before
  shanten, waits and legal. Build 4 and the mixed-op harness passed after these
  changes.

- Build 5 started with generated files and the previous executable removed.
  It linked successfully and both final harness runs passed.

# Language verdict

- Nondeterminism fit decomposition, win interpretations, yaku, and legal
  actions. For example, `solutions(form_for(Ks, MeldCount), Fs)` turns a
  relation into a sorted set of answers. The same shape search supports
  `complete/2` as an existential test, which fits the many probes in waits
  and legal.
- Modes and determinism make the boundaries clear, from
  `remove_kind(kind::in, list(kind)::in, list(kind)::out) is semidet` to
  `main(io::di, io::uo) is det`. Higher-order calls still take some care.
  A rule such as `ordinary(F, tsumo, _, "tsumo", 1)` reads locally, but the
  existential test over that nondet relation in `can_win/5` requires
  `promise_equivalent_solutions []` to commit to the first witness. Its empty
  output list is deliberate because win legality has no binding to return.
- Representation still determines how fast the search runs. The sorted-list
  pivot is simple and allocates tails when removing runs. The standard-library
  bag worked well for bookkeeping, once I found `bag.count_value(Bag, K)`.
  Waits dominated elapsed time. If profiling warranted more work, I would
  try caching standard-shanten partitions by suit and measure the allocation
  and throughput differences.

# Spec or corpus problems

I found no cases requiring a corpus-specific workaround. The fifth-copy
examples in disputed.txt follow the protocol's availability-independent shanten
formula. The corresponding waits output applies a separate availability check.

# Unfinished

No corpus failures or skipped operations. Malformed-input validation covers
parsing and the sizes needed to bound the searches. Full physical and contextual
validation is outside the corpus contract.
