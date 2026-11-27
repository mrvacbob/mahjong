# Mercury engine design

Kinds are consecutive integers in suit and rank order. Exact tiles carry a kind
and a red-five flag. Melds carry a typed call category and exact tiles. Scoring
converts melds into groups with typed roles (pair, sequence, triplet or kan) and
an openness flag. The interpretation separately records the exposure of the
hand as a whole, so a ron-completed triplet cannot open the hand for closed yaku.

Shape search uses a sorted list as a small multiset. Its first item gives a
canonical pivot and exposes duplicate runs without a separate lookup. The
standard library's bag is used for availability counts across hand and melds
and for counting repeated indicators against the winning hand. These counts
must preserve multiplicity. Sets represent flags and collections with unique
membership, such as the kinds compared for a riichi ankan.

`forms/2` is a det function collecting a nondet standard decomposition
relation. The relation consumes the smallest kind as a pair, sequence or
triplet and recurs. It may use the pair only once. Seven pairs and thirteen
orphans have separate checks. Shanten explores the same pivot with the
additional choices of an incomplete group or an unused tile. It minimizes over
these partitions with the four-group bound. Waits project candidate draws
through this machinery and apply the four-copy availability limit separately
from structural completion.

Scoring enumerates a decomposition and a concealed group containing the
winning kind. An interpretation records the wait, pair, and melds after
applying shanpon ron openness to the completed triplet. The nondet `ordinary/5` and `natural/6` relations declare yaku with the
protocol name and value at the head and principally semidet conditions in
the body. `solutions` collects the applicable entries. Yakuman replace
ordinary yaku and dora for that interpretation. Fu is computed from the same
groups and wait, with explicit branches for fixed-fu cases. The det scoring
operation folds over candidates ranked by payment and the protocol tie-break keys.

`action/6` is nondet and `legal/5` is det, producing the sorted action list.
`can_win/5` is semidet and shares the same interpretation and yaku relations as
`score/5`. Riichi requires a structural
completion with an available tile after the candidate discard. Riichi ankan
compares structural completion sets before and after the change. Chi and
post-call discard share a kuikae test. Call material and discard candidates
retain red identity until after the action has been chosen.
