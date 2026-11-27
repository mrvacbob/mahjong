# Design: Haskell entry

Written before the code. Plain `ghc --make`, packages `base`, `containers` and `mtl` (all ship with GHC).

## Modules

| Module | Contents |
|---|---|
| `Tile` | `Suit`, `Kind`, `Tile`, mpsz parsing/printing, dora successor, tile predicates |
| `Meld` | `Meld` (chi/pon/daiminkan/shouminkan/ankan), parsing, meld → `Group` |
| `Hand` | per-suit decomposition into complete groups (agari) and per-suit partial search (shanten), waits |
| `Score` | readings (interpretations), yaku and yakuman tables, fu, payment, tie-break |
| `Legal` | the `legal` op, written against `Hand` and `Score` |
| `Main` | request parsing, op dispatch, response printing, error capture |

## Tiles, hands, melds

```haskell
data Suit = Man | Pin | Sou | Honor            deriving (Eq, Ord, Enum, Bounded)
data Kind = Kind { suit :: !Suit, num :: !Int } deriving (Eq, Ord)   -- num 1..9 / 1..7
data Tile = Tile { kind :: !Kind, red :: !Bool }                     -- red only on 5s
```

`Kind` is what the rules talk about (yaku, shapes, waits); `Tile` is what the protocol
talks about (aka dora, `discard:0m` vs `discard:5m`). `Tile`'s `Ord` instance puts a red
five just before the plain five, so `sort` gives canonical order and printing a sorted
list is the canonical tile-list format.

A hand is a `[Tile]`. For shape work it is turned into counts per suit: a list of 9 (or 7)
`Int`s. Shape searches pattern-match on the head of that list (`n : b : c : rest`), which
is the most direct way I know to say "a run starts here" in Haskell.

A meld is `Meld { mtype :: MeldType, mtiles :: [Tile] }`. For scoring, melds and
concealed groups are unified into one type:

```haskell
data Form  = Pair | Run | Triplet | Quad          -- constructor order = print order
data Group = Group { gform :: Form, gbase :: Kind, gopen :: Bool }
```

so a chi is `Group Run k True`, an ankan `Group Quad k False`, and a shanpon triplet
completed by ron is just a concealed triplet with `opened = True`. Fu and the
"concealed triplet" yaku then read one field, with no special case.

## Hand decomposition

Each suit is decomposed independently, then the suits are combined with the list monad
and filtered for exactly one pair. Within a suit:

```haskell
suitGroups :: Suit -> Int -> [Int] -> [[Group]]   -- suit, number of first slot, counts
```

tries triplet / run / pair at the first non-empty slot. Because each suit is enumerated
in increasing order and suits are concatenated in m,p,s,z order, the output order of the
`agari` op falls out with one `sortOn` per form for the pair<run<triplet tie.

Shanten uses the same per-suit idea with partial groups: each suit yields the set of
reachable `(sets, partials, pair)` triples, Pareto-pruned (separately for pair 0/1), and
the suits are combined to maximise `2·sets + min(partials, 4−sets) + pair`. Melds count as
sets. Chiitoi and kokushi shanten are closed formulas over the counts.

*(Changed during the work:)* the partial search is split into a pure `moves` list (which
groups can come off the lowest number, including "give up on this number") and a search
memoised on the remaining counts with `State (Map [Int] [Partial])`; `improving` reuses
the outcome tables of the three suits a draw does not touch. See NOTES.md Log.

Waits = kinds whose addition lowers `min` shanten; the `waits` op filters them by copies
left; `legal`'s riichi-ankan check uses the unfiltered (structural) list.

## Yaku declaration

A yaku is a record with its name, closed han, open han (`Nothing` = closed only), and a
predicate on a `Win` (context + one reading):

```haskell
data Yaku = Yaku { yName :: String, closedHan :: Int, openHan :: Maybe Int, holds :: Win -> Bool }

yaku "toitoi"  2 2 $ std $ \gs -> count isSetLike gs == 4
yaku "ittsu"   2 1 $ std $ \gs -> any (\s -> all (\n -> any ((== Kind s n) . gbase) (runs gs)) [1, 4, 7]) numberSuits
```

The predicates are written so mutually exclusive yaku exclude each other by their own
definition, as the rule text does (iipeikou = exactly one peikou, ryanpeikou = two; chanta
needs an honor, junchan forbids one; honitsu needs honors, chinitsu forbids them). There is
no separate "upgrade/cancel" table. Yakuman are a second table of `(name, multiplier,
predicate)`. Situational yaku are entries whose predicate looks at the flag set.

`std` lifts a predicate over the five groups of a standard reading and is `False` for
chiitoi and kokushi readings, so a predicate like `all hasTerminal` can't succeed
vacuously on a seven-pairs hand.

## Fu and interpretation choice

`readings :: Ctx -> [Reading]` lists every interpretation: each standard decomposition
× each distinct group the winning tile could have completed (which fixes the wait:
ryanmen/kanchan/penchan/shanpon/tanki), plus chiitoi and kokushi. For `tenhou`, each
distinct kind in the 14 is tried as the winning tile. Each reading is scored
independently (yakuman → yakuman form; else yaku, dora, fu, han, limit), and the best is
chosen with one `maximumBy` over a key `(total, realYakuman, han, fu, Down yakuString)`.
Fu is a sum over groups plus base/menzen/tsumo/wait, then the three fixed exceptions
(pinfu tsumo 20, chiitoi 25, open 20 → 30).

## `legal`

`legal` asks the other ops: `tsumo`/`ron` call the `score` evaluator with a constructed
context (riichi=1 adds the `riichi` flag) and test for a non-error result; `riichi:` calls
`waits` on the hand after each discard and checks `shanten == 0 && count > 0`; the riichi
ankan check compares structural wait lists before the draw and after the kan; kokushi-only
robbing checks the reading list for a kokushi reading. Call enumeration (chi/pon/kan) and
kuikae are the only logic local to `Legal`.
