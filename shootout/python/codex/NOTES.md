# Notes

## Result

The repository-root harness passed all 12,434 cases on Python 3.14, both
with and without `--time`. The timed run measured 77.3 ms startup.

| Op | Pass | Fail | Seconds | Requests/s | Requests/s excluding startup |
| --- | ---: | ---: | ---: | ---: | ---: |
| agari | 2190 | 0 | 0.114 | 19259.0 | 60156.9 |
| shanten | 2199 | 0 | 0.128 | 17203.7 | 43533.2 |
| waits | 1996 | 0 | 0.486 | 4106.2 | 4882.8 |
| score | 5291 | 0 | 0.237 | 22352.4 | 33193.1 |
| legal | 758 | 0 | 0.151 | 5024.1 | 10303.9 |

## Size

Counted nonblank, noncomment lines. Shebangs count as comments.

| File | Lines |
| --- | ---: |
| `actions.py` | 102 |
| `main.py` | 47 |
| `scoring.py` | 259 |
| `shapes.py` | 223 |
| `build.sh` | 15 |
| `mj` | 1 |
| **Total** | **547** |

Python modules account for 531 lines. The build script includes a Python
syntax-checking snippet.

## Log

- Read the brief, rules, protocol and corpus examples. Wrote the design before starting the implementation.
- Ran a path-limited status check in the initial command that read the brief, before seeing its prohibition on git commands. Used no further git commands.
- Implemented exact tile parsing, normalized form search and memoized suit profiles. Distinguished structural winning kinds from physically drawable ones in the interface.
- Added winning-group interpretations, rule predicates, fu and payment calculation. Scoring keeps ron group openness separate from hand closure.
- Connected legal actions and the runner. Added a build that checks syntax and starts the executable to check module loading.
- First build succeeded. The timed harness passed 12,425 cases and failed nine (five agari, two waits, two legal). The kokushi check accepted all thirteen orphans plus a simple tile. The latter four failures were consequences in wait enumeration and riichi action generation. Require the fourteenth tile to duplicate an orphan, then rerun.

- The second build and both harness runs passed. A direct runner smoke test also checked that a simple tile cannot complete thirteen orphans, a duplicate orphan scores double yakuman, a wrong-size input receives a protocol error, and agari can report both standard and seven-pairs forms.

## Language verdict

- Tuples and bounded memoization made the recursive searches straightforward.
  The suit profile uses `@lru_cache(maxsize=65536)` with a count tuple and a
  numbered-suit flag. Repeated improvement queries reused those profiles
  without any precomputed tables. Waits still had the lowest throughput.
  If it became a bottleneck, I would profile the profile merge and look at
  reusing the unchanged suits across each batch of candidate draws.
- Simple predicates made the scoring rules readable near their declared
  values. For example, `("daisangen", 1, DRAGONS <= f.triplets)` expresses
  complete coverage directly. A tuple sort key expressed the whole payment
  tie-break in one place.
- Annotations helped make the inputs to shape and action functions explicit.
  Python allowed the first kokushi predicate to compile because the error was
  in the hand invariant. The corpus exposed it across three operations. With
  more time I would give exact tiles and normalized kinds distinct static
  types and add focused invariant tests for shared shape predicates.

## Spec or corpus problems

No authoritative-spec conflict required a workaround. The cases in
`corpus/disputed.txt` follow the specified structural shanten formula and
exclude exhausted kinds from the reported improvements.

## Unfinished

All five operations passed the supplied corpus. No held-back cases were available.
