# Haskell entry design

## Tiles and shapes

Kinds are indexed in suit order from 0 to 33. Physical tiles also carry an
aka bit. Normalized kinds drive shape, dora matching and kuikae. Physical
tiles drive action spelling, multiset subtraction for calls and aka counting.
Declared melds retain their call type and source tiles so a closed kan can
count as one set for shape, four tiles for dora and a concealed kan for fu.

The standard decomposition search consumes the least remaining kind.
A group using that tile must be a pair, a triplet, or a sequence starting
there. Each recursive branch removes exactly that group's tiles. A standard
form uses one pair and the number of sets still owed after declared melds.
Seven pairs and thirteen orphans are additional shapes. They have their own
constructors and do not require fabricating standard groups.

Standard shanten uses a related search with incomplete groups and skipped
tiles. Each suit produces possible combinations of complete sets, incomplete
sets and allocated heads. Suits combine because neither a complete group nor
a partial group spans suits. The final calculation caps partial sets at the
remaining set slots. Kinds with four copies require no special penalty.
Improving draws check physical availability separately from this calculation.

## Scoring and actions

Each standard form produces an interpretation for each concealed group
that could contain the winning kind. This determines wait fu and makes a
ron-completed triplet open for fu and concealed triplet yaku. Tenhou extends
this enumeration to every distinct kind in the finished hand. Seven pairs
has fixed fu and kokushi decides its variant from the hand before the win.

Yaku are written as named predicates paired with their han or yakuman value.
Ordinary and yakuman tables read facts about one interpretation, such as
sequence starts, concealed triplets, pair kind and the complete tile list.
The tables express mutually exclusive upgrades with guards, such as
Ryanpeikou versus Iipeikou. Dora is computed after checking the ordinary
yaku minimum. Fu is the sum of independently calculated set, pair, wait and
win-method contributions, with fixed-fu exceptions evaluated first.

Calculate payment for each interpretation. Select by total, real yakuman
status, han, fu, then ascending serialized yaku. Round each payer's amount
individually before adding honba.

Legal win actions use the scorer's interpretations and yaku predicates.
They stop once a yaku is found. Riichi checks for an available completion
after each possible discard. Riichi ankan compares structural completions
before and after the kan, so availability does not enter that comparison.
Call actions consume physical tiles from the concealed hand and chi reuses
the post-call kuikae predicate to check that a discard remains possible.
