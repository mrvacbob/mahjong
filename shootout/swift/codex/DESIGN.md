# Swift shootout design

A physical tile is a value with a normalized kind and a red bit. Kinds are
indexed in suit and rank order, so neighboring indices express sequences after a
suit-boundary check. Shape algorithms work on 34 counts. Melds keep their
declared type and physical tiles, and supply a sequence, triplet, or kan for
scoring. An ankan consumes a set slot without opening the hand.

## Shape

For a standard win, choose a head and recursively consume the first remaining
kind as a triplet or as the start of a sequence. Each branch removes tiles and
restores the counts on return. The two special shapes are separate cases of a
form enum. At the protocol boundary, sort the groups by the specified kind and
group-type order, then deduplicate and sort the rendered forms.

For shanten, enumerate disjoint sets, partial sets, and an optional head.
Suit-local profiles retain the maximum partial sets for each number of complete
sets and each head state. Skip unmatched tiles and take the maximum across
branches. Memoize profiles by local counts within one request and combine suits
under the four-set cap. Special shanten uses counts of distinct kinds and pairs.
Draw probes share the same cache. Structural winning-kind comparison can use
the completion search directly, including a hypothetical fifth copy. Live waits
apply the physical copy limit across concealed tiles and melds.

## Scoring

Apply each possible winning kind to each matching concealed group in a standard
form. Special forms carry their own interpretation. For tenhou, enumerate all
distinct kinds in the completed hand as candidates. A standard interpretation
records wait type and marks the ron-completed triplet as open for triplet fu and
concealed-triplet yaku, separately from whether the hand is menzen.

Yaku appear as named condition checks, with closely related mutually exclusive
rules next to one another. Shared facts include suited kinds, honors, sequence
starts, triplet kinds, the value-pair fu, and the number of concealed triplets
and kans. Evaluate natural yakuman first and stack their multiples. Otherwise
require ordinary yaku before adding dora. Fu is the sum of contributions of the
interpreted groups, pair, wait, and win method, subject to the fixed-fu rules.
Calculate the actual rounded payments for each candidate and compare total,
natural yakuman status, han, fu, and finally the serialized yaku string.

## Legal actions

Use scoring for wins and the same shape routines for riichi and riichi ankan.
Closed-kan robbery uses only the kokushi form. Generate exact physical discards
and two-tile call choices from the concealed hand. A single kuikae predicate
serves both post-call discards and call feasibility. Furiten, wall size, kan
count, seat direction, and the current turn type filter actions before they are
serialized in lexical order.
