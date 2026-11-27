# Python riichi slice

## Tiles and shapes

Tile kinds are consecutive integers in mpsz order. Three additional integers
represent red fives. The protocol and call generator retain those exact tiles.
Shape calculations normalize them into a 34-count tuple. A meld retains its
original tiles and its call type. Its normalized group carries the first kind
and whether it is a sequence, triplet or kan. A closed kan takes a meld slot
while preserving the closed status of the hand.

Complete hands use a recursive partition of the concealed counts. Take the
lowest remaining tile and branch over the groups it can start. A recursive
state carries the remaining number of sets and whether the head is still owed.
Canonical sorting is done when rendering. Seven pairs and thirteen orphans
are independent checks and can be returned alongside standard forms.

Standard shanten partitions by suit and honors. Each local count vector yields
a profile of possible set and head counts with the maximum number of partial
sets for each combination. Compute profiles by removing a candidate group or
skipping a tile, and cache them with a bounded standard-library cache. Merge
the four profiles and evaluate the formula with the global four-slot cap.
Special shanten uses distinct-kind and pair counts. For tenpai, the
improvement test can use complete shape detection directly. Check availability
after shape calculations, with counts from both the concealed hand and melds.

## Scoring

An interpretation combines a complete form with the concealed group containing
the winning tile. Try every distinct such group, and every possible winning
kind for tenhou. Classify the wait from the chosen group. Combine the groups
with declared melds, tracking openness per group independently of overall hand
closure. A ron-completed triplet is open for fu and concealed-triplet yaku.

The scoring functions declare each yaku as a name, value and condition over the
interpretation. Shared facts such as pair fu, number of concealed triplets and
number of duplicate sequence pairs keep those conditions close to their rule
text. Exceptional forms and situational rules use the same scoring path.
Evaluate natural yakuman first, then ordinary yaku and finally bonuses when
at least one ordinary yaku is present.

Fu adds pair, wait, group and win-method components, with fixed fu for seven
pairs and pinfu tsumo. Compute the rounded payments including honba and choose
the interpretation by total, real yakuman status, han, fu and canonical yaku
string in the specified order.

## Actions and protocol

The runner dispatches parsed requests to the five operations. Legal win
actions call scoring with the supplied context. Ankan robbery checks the
kokushi shape directly. Riichi tests for a complete shape after a hypothetical
discard and a drawable kind, while riichi ankan compares structural wait sets
before and after. Chi and pon enumerate exact tile pairs and use the same
kuikae discard test as the post-call phase. Output sorting is independent of
generation order.
