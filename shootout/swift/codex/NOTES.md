# Result

Apple Swift 6.4.4, arm64, compiled with `swiftc -swift-version 6 -O`.
Ran `python3.14 tools/harness.py shootout/swift/codex/mj corpus/*.txt --time`
from the repository root. Empty-input startup was 6.7 ms.

| Op | Pass | Fail | Seconds | Requests/s | Requests/s excluding startup |
| --- | ---: | ---: | ---: | ---: | ---: |
| agari | 2,190 | 0 | 0.013 | 172,983.5 | 366,111.0 |
| shanten | 2,199 | 0 | 0.018 | 119,781.6 | 188,269.9 |
| waits | 1,996 | 0 | 0.042 | 47,163.6 | 56,000.7 |
| score | 5,291 | 0 | 0.047 | 112,341.6 | 130,903.6 |
| legal | 758 | 0 | 0.012 | 63,032.3 | 141,756.2 |
| **Total** | **12,434** | **0** | | | |

# Size

Nonblank, noncomment source lines. The shell count excludes the shebang.

| File | Lines |
| --- | ---: |
| Tiles.swift | 109 |
| Shape.swift | 171 |
| Score.swift | 262 |
| Legal.swift | 120 |
| main.swift | 108 |
| build.sh | 5 |
| **Total** | **775** |

# Log

- Read the protocol, scoring tables, and examples before drafting the design.
  The fifth-copy examples led to a separate structural completion check for
  riichi ankan, with availability applied only to live waits.
- Wrote the count search with a per-request memo. Scoring treats the winning
  group as an independent choice so a ron triplet can be open for fu without
  opening the hand for menzen yaku.
- Wired legal actions and the line runner. The first clean optimized build
  exited successfully with no compiler diagnostics. The first timed harness
  run passed all five ops. No failed build-test cycles or missing APIs so far.
  Exhaustive switches provide a compile-time check on new enum cases. Neither
  the compiler nor the corpus surfaced an implementation bug on this run.

# Language verdict

- An enum with associated values makes decomposition and turn context direct.
  `case standard([Group])` carries groups into scoring, and
  `case afterCall(Meld, took: Tile)` carries exactly what kuikae needs. Swift
  checks that each switch covers every case. I would use the same representation
  again.
- Swift's arrays and nested functions let the search keep its state local.
  `remaining[kind] -= 3`, `search(from: kind)`, and `remaining[kind] += 3`
  describe a branch without explicitly copying the count vector. The restore
  step still needs review because Swift cannot check backtracking invariants.
  Next time I would measure the suit memo against a simpler whole-hand search
  before choosing the bit packing.
- Tuple comparison expresses nearly all of the score precedence in one place
  with `(total, yakuman > 0 ? 1 : 0, han, fu)`. A dictionary makes adding a
  yaku as direct as `yaku["sanankou"] = 2`, but Swift cannot check protocol
  spellings in string keys. I would use a raw-value yaku enum if the scorer
  grew beyond this slice.

# Spec or corpus problems

The three fifth-copy disputes in `corpus/disputed.txt` agree with the
authoritative protocol body. The search reports structural tenpai, and the
availability filter produces zero live waits. The formats document's
historical decisions log contains superseded rulings. The implementation follows
the body for tenhou, ippatsu with chankan, tie-breaking, and uncapped natural
yakuman stacking. The corpus passed without case-specific workarounds.

# Unfinished

No requested operation is skipped or failing in the published corpus. Held-back
cases were unavailable.
