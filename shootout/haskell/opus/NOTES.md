# NOTES: Haskell entry (opus)

## Result

`python3.14 tools/harness.py shootout/haskell/opus/mj corpus/*.txt`:

| op | pass | fail |
|---|---|---|
| agari | 2190 | 0 |
| legal | 758 | 0 |
| score | 5291 | 0 |
| shanten | 2199 | 0 |
| waits | 1996 | 0 |
| total | 12434 | 0 |

`--time` (final build, `-O2`, Apple Silicon; start-up of an empty run is about 10 ms
when run by hand, and the harness reported 20 to 75 ms across runs, so the "excl.
start-up" column is noisy):

| op | requests | seconds | req/s |
|---|---|---|---|
| agari | 2190 | 0.038 | 56,900 |
| shanten | 2199 | 0.083 | 26,500 |
| waits | 1996 | 0.560 | 3,570 |
| score | 5291 | 0.094 | 56,500 |
| legal | 758 | 0.075 | 10,100 |

## Size

Lines of code without blank lines and without lines that are only a comment:

| file | LoC |
|---|---|
| src/Tile.hs | 82 |
| src/Meld.hs | 56 |
| src/Hand.hs | 117 |
| src/Score.hs | 309 |
| src/Legal.hs | 106 |
| src/Main.hs | 124 |
| build.sh | 4 |
| total | 798 |

## Log

- Read the brief, spec/formats.md, spec/rules.md, corpus/handwritten.txt,
  legal_handwritten.txt and disputed.txt. Wrote DESIGN.md before any code. Build tool is
  plain `ghc --make -O2 -Wall` (base, containers, mtl only). I didn't use cabal: it
  adds nothing for a single executable built from boot packages.
- Before compiling I rewrote my first `parseMeld`. It had grown a dead `where` binding
  and used `Data.List.NonEmpty` just to get a safe `head`. The rewrite uses a
  pattern bind in the `Maybe` monad (`ks@(k0 : _) <- Just (sort ...)`). A failed match
  goes to `MonadFail`, so it returns `Nothing`.
- **Build 1: failed.** Type error in `Main.respond`: the first `case` branch was a
  `do` block in `IO`, and the two fallback branches returned plain `String`. Fixed by
  wrapping them in `pure`. The compiler caught it. Warnings in the same build:
  `-Wx-partial` on `head` in `showTiles` (replaced with a pattern match), an unused
  `foldl'` import, and `-Wname-shadowing` on a comprehension variable `k` that shadowed
  the meld count `k` in `Legal.ownTurn`. The shadowing was harmless there, but I renamed
  it, because a shadowed `k` in that function could have been a real bug.
- **Build 2: compiled.** No further warnings under `-Wall`.
- **Harness run 1: every case passed (12434/12434).** No corpus-only bugs to report. The
  type split between `Kind` and `Tile` meant no red-five mistakes reached the harness.
  `Ord Tile` puts 0 before 5, and the shape code only sees `Kind`.
- **`--time` run 1: correct but slow.** `waits` ran at 60 req/s and `shanten` at 1.8k
  req/s, with 33 s for the waits file. Cause: the per-suit partial-set search had a
  "leave one tile isolated and stay at this number" branch. It reaches the same
  sub-state by many orders, so the search was exponential, and the per-node `prune`
  (a `Map` dedup plus an O(n²) dominance check) made each node expensive.
  - Fix 1: replace that branch with "give up on this number" (`go xs`). It is still
    complete, because all groups starting at a number are tried before moving on.
    waits went to 150 req/s.
  - Fix 2: split the search into a pure `moves` list (the rule: which partial or
    complete groups can come off the lowest number) and a search that memoises on the
    remaining counts in `Control.Monad.State.Strict` with a `Data.Map`. waits went to
    2,000 req/s and shanten to 28k req/s. A boot-package State monad was enough;
    `unsafePerformIO` wasn't needed.
  - Fix 3: in `improving` (waits), drawing a kind only changes that kind's suit, so the
    other three suits' outcome tables are reused. waits went to 3,500 req/s.
  - After each step I re-ran the full corpus: still 12434/12434.
- **Build: warning** `foldl'` import redundant. In base-4.22, `foldl'` comes from the
  Prelude. I expected to need the `Data.List` import, and `-Wall` said otherwise.
- Made `score` without a `win=` key answer `error=bad_win`. Before this it scored with a
  dummy tile. The corpus doesn't test malformed input. Checked by hand that bad input
  gives `error=...` lines, not a crash (`respond` also catches any exception as
  `error=internal`).
- Spot-checked the rules.md item 14 riichi-ankan examples, the item 6 ambiguous wait,
  a tenhou with daisuushii, suuankou_tanki and tsuuiisou (6x), and the rules.md item 13
  dead-end chi. All match the rule text.

APIs I expected and didn't find: none in the end. `Data.List` has no `splitOn` (that
is in the `split` package), so I wrote a three-line `splitOn` twice, in `Meld` and
`Main`. I should have put one copy in `Tile`.

## Language verdict

**Easy:**

- *Shape search as list pattern matching.* The rules for taking a group off the
  lowest number of a suit read almost like the rule text. This is the whole of the
  partial-set rule for shanten:

  ```haskell
  moves honor (c : xs) = concat
    [ [((1, 0, 0), c - 3 : xs) | c >= 3]                                          -- triplet
    , [((1, 0, 0), c - 1 : b - 1 : d - 1 : ys) | not honor, b : d : ys <- [xs], b > 0, d > 0] -- run
    , [((0, 0, 1), c - 2 : xs) | c >= 2]                                          -- pair as head
    , [((0, 1, 0), c - 2 : xs) | c >= 2]                                          -- pair as partial
    , [((0, 1, 0), c - 1 : b - 1 : ys) | not honor, b : ys <- [xs], b > 0]        -- 34
    , [((0, 1, 0), c - 1 : b : d - 1 : ys) | not honor, b : d : ys <- [xs], d > 0] -- 35
    , [((0, 0, 0), xs)] ]                                                         -- give up on c
  ```

  Combining suits is the list monad (`concat <$> mapM perSuit suits`). Choosing the
  best interpretation is `maximumBy (comparing key)` over a tuple key. The spec's
  tie-break order is just the tuple order:
  `(total, isYakuman, han, fu, Down yakuString)`.
- *Yaku as a data table of predicates.* Each yaku is one line, and its predicate
  states the rule directly. Exclusions come from the definitions themselves, with no
  cancel table:

  ```haskell
  , closedOnly "iipeikou" 1 $ std $ \gs -> peikou gs == 1
  , closedOnly "ryanpeikou" 3 $ std $ \gs -> peikou gs == 2
  , yaku "chanta" 2 1 $ std $ \gs -> all hasYaochu gs && not (null (runs gs)) && any (isHonor . gbase) gs
  , yaku "honitsu" 3 2 $ \w -> oneSuit (tiles w) && any isHonor (tiles w)
  ```

  `std` lifts a predicate over the groups of a standard reading and is `False` for
  chiitoi and kokushi. So `all hasTerminal []` can't make a seven-pairs hand junchan.
  The type forces that question to be answered once.
- *One `Group` type for melds and concealed groups,* with an `gopen` flag. "Ron on a
  shanpon makes the triplet open" is one record update (`g { gopen = True }`), and fu
  and sanankou/suuankou read the same field.
- *`legal` reuse:* `tsumo`/`ron` are `isRight (score s { winTile = w, byTsumo = t, ... })`.
  The riichi test is the `waits` function. Record update syntax makes "the same
  situation, but ron on this tile" a single expression.
- *What the compiler caught:* the IO/String mismatch, a shadowed variable in exactly
  the function where one-letter names are risky, and partial `head`. Exhaustive
  pattern warnings meant every `Wait`/`Form`/`MeldType` case in fu and waits was
  handled. No logic bug reached the corpus, though the corpus would have caught them.

**Hard / awkward:**

- *Performance is not where the code says it is.* The first shanten search looked fine
  and ran at 60 waits/s. Laziness and lists hide the cost model, so you only find
  out by timing. Memoisation needs a State monad (or an unsafe global). Adding
  it was easy because the search was already a pure function of the remaining counts,
  but it changed the code from expressions to `do` blocks.
- *`String` everywhere.* The protocol is tiny, so `String` was fine here (score runs at
  56k req/s), but in a real engine I'd switch to `ByteString`/`Text`, and that spreads
  through every printer.
- *Small missing stdlib pieces:* no `splitOn`, and `Data.List.NonEmpty` is clumsy for
  the "a meld has at least one tile" case. A pattern bind in `Maybe` was nicer.
- *Records:* field names are global per module (`hand`, `melds`, `flags`), which
  forced names like `kansMade`, `inRiichi`, and `head'`.

**What I would do differently:** represent per-suit counts as a packed `Int` (base-8
digits) instead of `[Int]`. That gives a cheap `Map Int` memo key, or a global lazy
table for honors. It would probably make waits 5 to 10 times faster. I would also
share `splitOn`.

## Spec or corpus problems

None found. I implemented the spec as written, and every corpus case agreed with it.
I relied on two points that the spec states but that are easy to miss:
- In `agari` forms a run sorts before a triplet with the same first tile (`234m,222m`).
  The formats.md body says so.
- The riichi-ankan comparison uses structural waits (fifth copies count). I compared
  `improving` lists without the availability filter, as formats.md says ("structural,
  as in `shanten`").

## Unfinished

Nothing failing or skipped. Malformed input gets `error=<reason>`, with reasons I
chose (`bad_hand`, `bad_melds`, `no_prompt`, `unknown_op`, `internal`, ...). These are
untested by the corpus.

## Finalization

### Bugs and reviewer fixes

No corpus case failed before finalization: the clean build passed all 12,439 cases,
including the five in `corpus/legal_review.txt`. The riichi-ankan check was already
right about fifth copies. It compared `improving` lists, which come from shanten with
no availability filter, and the shanten memo is keyed on the whole `[Int]` count list.
A count of five is just `5` in that list, so it can't alias a carry into the next kind
the way a packed base-5 key would (r2/r3/r5). Before the draw, `122233344m1111z` still
shows `1z` as a wait (r4).

The reviewers asked for completion-based structural waits instead of shanten, and I
agree: the rule says "the set of wait kinds", and a wait is a tile that completes the
hand. Changes:

- **`Hand.structuralWaits`**: the kinds `k` such that hand+`k` decomposes, or is
  chiitoi or kokushi. It has no availability filter, so the fifth copy is there by
  construction. `legal` now uses it for both the riichi-ankan comparison and the riichi
  tenpai test ("some structural wait has a copy left"). The meld count disappeared from
  these calls: chiitoi and kokushi need 14 concealed tiles, so they can't arise with a
  meld anyway. `legal` went from about 10k to 16k req/s.
- **Partial `head'` removed** (agy). Kakan reads the pon's kind as `gbase (meldGroup m)`.
- **One `splitOn`** (agy). Main's private copy is gone.
- **Request validation** (codex). A `legal` request with more than one of
  `draw`/`discard`/`called` now answers `error=bad_prompt`. It used to take the first
  one silently. Counts must be non-negative and 0/1 flags must be 0 or 1. `legal` no
  longer parses `win=`: the prompt tile is the win candidate.
- **Extreme honba** (codex). Payments are `type Points = Integer`, so
  `honba=9223372036854775807` gives the exact payment. It used to wrap to 3600.

Reviewer items I did not take:

- *Yaku names as a sum type* (agy). The names are the protocol output, and a sum type
  would need a second table to print them. The only place code compared against a name
  (`"pinfu" `elem` ...` in `fu`) now calls the `pinfu` predicate, so no string is
  compared anywhere.
- *Packed `Int` memo keys* (agy, and my own earlier note). That trades readability for
  speed, which the brief rules out. It is also the change that would bring back the
  fifth-copy aliasing risk.
- *Separate decomposition and scoring group types with an explicit pair* (codex). That
  changes the design wholesale. `agari` prints decompositions as one sorted list with
  the pair in place, `std` already keeps standard-only predicates off chiitoi and kokushi,
  and `gopen` is `False` for every decomposed group until a reading sets it.

### What the simplify pass changed

Four review angles (reuse, simplification, efficiency, altitude). Applied:

- **Rules stated once.**
  - `pairFu` (dragon, seat wind, round wind) serves both pair fu and pinfu's "no-fu pair".
  - `outside` serves both chanta and junchan, so `hasTerminal` is gone.
  - `runAt` is the run counterpart of `setOf`, used by sanshoku and ittsu.
  - `graded single double base stricter` gives each yakuman/double pair one entry
    (kokushi/13, suuankou/tanki, chuuren/junsei) instead of a predicate written twice.
  - One `kuikae` function serves both the call filter and the after-call discards, where
    there used to be two forbidden-list constructions.
  - One `count`/`countOf` in `Tile` replaced three local `length . filter` helpers.
  - One `meldKinds` replaced three spellings of the same expression.
  - One `closedHand`, now also used by `meldGroup`.
  - `numbers`/`offset`/`winds`/`dragons`/`east` in `Tile` replaced hard-coded ranges and
    `k { num = num k + 1 }`.
  - `parseMeld` checks the tiles against `groupKinds (meldGroup m)` instead of
    re-deriving runs and sets.
- **Types carry distinctions.**
  - `Kokushi KokushiWait` replaces `Thirteen Bool`.
  - `Value = Ordinary han fu | Yakuman n` derives `Ord`, so the tie-break key is
    `(total, value, Down yakuString)`. This removed eight lines of accessors.
  - `Shanten` is a record with `Maybe` chiitoi and kokushi fields.
  - `Split` has named fields.
  - `moves`/`suitPartials` take the `Suit`, not an `honor` Bool.
  - `hanFor` names the closed/open han choice.
- **Dead code removed:** `kindsOf`, `parseKind`, `isKan`, `defaultSituation`, Legal's
  unreachable `AnkanRob` deletion, redundant `null melds` guards next to 14-tile checks,
  `unwords . pure`, the `const "" (e :: SomeException)` trick (now
  `try @SomeException`), and the score-only `M.notMember "win"` guard (`tileArg`
  already answers `bad_win`).
- **Wasted work removed:**
  - The `shanten` op ran the standard search twice. It now runs it once.
  - `waits` ran the four-suit search three times. It now runs it once, and skips the
    re-search for kinds with no copy left.
  - Riichi tenpai is tested once per discard kind, not once per physical tile.
  - Bonus han (dora/aka/ura) is computed once per request, not per reading.
  - `suitGroups` threads a "pair taken" Bool instead of re-counting pairs at each level.
  - The `fu` 20→30 exception is `max 30`, with the comment above the rule.
  - `parseTiles` uses `span isDigit` instead of a `++ [d]` accumulator.

Left alone:

- Tenhou decomposes the same 14 tiles once per winning kind. It is rare, and sharing
  the work would split `readingsWith`.
- `LineBuffering` stays. A reviewer confirmed that answering with stdin still open
  matters for interactive clients.
- The fresh per-call memo `Map`s and the packed-key idea stay out, as above.
- `improving`-style waits for `waits` (shanten-lowering kinds, needed for non-tenpai
  hands) and `structuralWaits` (completion) both remain. They agree on tenpai hands,
  and each is the definition its rule text uses.

### Numbers

Lines of code (non-blank, non-comment): **798 before, 778 after**.

| file | before | after |
|---|---|---|
| src/Tile.hs | 82 | 89 |
| src/Meld.hs | 56 | 55 |
| src/Hand.hs | 117 | 111 |
| src/Score.hs | 309 | 304 |
| src/Legal.hs | 106 | 95 |
| src/Main.hs | 124 | 120 |
| build.sh | 4 | 4 |

`--time`, req/s including start-up, typical of three runs each (start-up 22 to 25 ms):

| op | before | after |
|---|---|---|
| agari | 60k to 98k | 56k to 105k |
| shanten | 24k to 27k | 41k to 46k |
| waits | 3.5k to 3.7k | 4.3k to 4.5k |
| score | 48k to 56k | 51k to 52k |
| legal | 9.7k to 12k | 15.6k to 16.1k |

Corpus after a clean `./build.sh`: 12,439/12,439. Clean build under `-Wall` with no
warnings.

### What got in the way

- *Constructor and type names share a module namespace across declarations.* Naming
  the `Value` constructor `Yakuman` forced the yakuman table record to become
  `YakumanRule`. The old code had used a primed `Yakuman'` to dodge the same clash.
- *Record field names are module-global.* `Shanten`'s fields had to be `stdShanten`,
  and so on, because `std` and `shanten` were taken. Main's op printers became
  `showShanten` and friends.
- *Fixed-width `Int` wraps silently.* Nothing in the types warned that `300 * honba`
  could overflow. The fix was easy (`Integer`), but only because a reviewer probed it.
