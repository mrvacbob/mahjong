:- module shape.
:- interface.

:- import_module list, set, tiles.

:- type form ---> standard(list(group)) ; chiitoi ; kokushi.
:- type distances ---> distances(int, int, int, int).

:- func forms(list(kind), int) = list(form).
:- pred complete(list(kind)::in, int::in) is semidet.
:- pred is_kokushi(list(kind)::in) is semidet.
:- func render_form(form) = string.
:- func shanten(list(kind), int) = distances.
:- func minimum(distances) = int.
:- func structural_waits(list(kind), int) = set(kind).
:- pred live_tenpai(list(tile)::in, list(meld)::in) is semidet.
:- pred improvements(list(tile)::in, list(meld)::in, int::out,
    list(kind)::out, int::out) is det.
:- pred remove_kind(kind::in, list(kind)::in, list(kind)::out) is semidet.
:- func add_kind(kind, list(kind)) = list(kind).

:- implementation.
:- import_module bag, int, solutions, string.

:- type head_use ---> need_head ; have_head.

forms(Ks, MeldCount) = Fs :-
    ( if list.length(Ks) = 14 - 3 * MeldCount then
        solutions(form_for(Ks, MeldCount), Fs)
      else Fs = []
    ).

:- pred form_for(list(kind)::in, int::in, form::out) is nondet.
form_for(Ks, MeldCount, Form) :-
    ( standard_groups(Ks, need_head, Gs), Form = standard(Gs)
    ; MeldCount = 0,
        ( is_chiitoi(Ks), Form = chiitoi
        ; is_kokushi(Ks), Form = kokushi
        )
    ).

complete(Ks, MeldCount) :-
    list.length(Ks) = 14 - 3 * MeldCount,
    ( if standard_groups(Ks, need_head, _) then true
      else MeldCount = 0, (if is_chiitoi(Ks) then true else is_kokushi(Ks))
    ).

:- pred standard_groups(list(kind)::in, head_use::in, list(group)::out)
    is nondet.
standard_groups([], have_head, []).
standard_groups([K | Ks], Head, [group(K, Role, concealed) | Gs]) :-
    ( Head = need_head, Ks = [K | Rest], Role = pair, NextHead = have_head
    ; take_set(K, Ks, Role, Rest), NextHead = Head
    ),
    standard_groups(Rest, NextHead, Gs).

:- pred take_set(kind::in, list(kind)::in, role::out, list(kind)::out)
    is nondet.
take_set(K, [K, K | Rest], triplet, Rest).
take_set(K, Ks, sequence, Rest) :-
    not honor(K), rank(K) =< 7,
    remove_kind(K + 1, Ks, Tail),
    remove_kind(K + 2, Tail, Rest).

remove_kind(K, [X | Xs], Rest) :-
    ( if K = X then Rest = Xs
      else K > X, remove_kind(K, Xs, Tail), Rest = [X | Tail]
    ).

add_kind(K, []) = [K].
add_kind(K, [X | Xs]) =
    (if K =< X then [K, X | Xs] else [X | add_kind(K, Xs)]).

:- pred is_chiitoi(list(kind)::in) is semidet.
is_chiitoi(Ks) :- distinct_pairs(Ks, -1, 7).

:- pred distinct_pairs(list(kind)::in, kind::in, int::in) is semidet.
distinct_pairs([], _, 0).
distinct_pairs([K, K | Ks], Prev, N) :-
    K > Prev, distinct_pairs(Ks, K, N - 1).

is_kokushi(Ks) :-
    list.length(Ks) = 14,
    list.sort_and_remove_dups(Ks) = orphan_kinds.

render_form(standard(Gs)) =
    string.join_list(",", list.map(render_group, list.sort(Gs))).
render_form(chiitoi) = "chiitoi".
render_form(kokushi) = "kokushi".

shanten(Ks, MeldCount) = distances(Std, Pairs, Orphans, Min) :-
    Std = 8 - best_partition(Ks, MeldCount, 0, 0),
    ( if MeldCount = 0 then
        kind_counts(Ks, Distinct, PairCount, OrphanCount, OrphanPair),
        Pairs = 6 - PairCount + int.max(0, 7 - Distinct),
        Orphans = 13 - OrphanCount - OrphanPair,
        Min = int.min(Std, int.min(Pairs, Orphans))
      else
        Pairs = 0, Orphans = 0, Min = Std
    ).

minimum(distances(_, _, _, Min)) = Min.

:- pred kind_counts(list(kind)::in, int::out, int::out, int::out, int::out)
    is det.
kind_counts([], 0, 0, 0, 0).
kind_counts([K | Ks], Distinct, Pairs, Orphans, OrphanPair) :-
    list.take_while((pred(X::in) is semidet :- X = K), Ks, Same, Rest),
    kind_counts(Rest, D, P, O, OP),
    Distinct = D + 1,
    Pair = (if Same = [_ | _] then 1 else 0),
    Pairs = P + Pair,
    ( if outside(K) then
        Orphans = O + 1, OrphanPair = int.max(Pair, OP)
      else Orphans = O, OrphanPair = OP
    ).

% Extra partial groups can be skipped. Any later complete group is still
% worth taking even when it pushes earlier partials over the final cap.
:- func best_partition(list(kind), int, int, int) = int.
best_partition([], Sets, Partials, Head) = partition_value(Sets, Partials, Head).
best_partition([K | Ks], Sets, Partials, Head) = Best :-
    ( if Sets = 4, Head = 1 then Best = 9
      else
        Skipped = best_partition(Ks, Sets, Partials, Head),
        ( if Ks = [K | PairRest] then
            HeadValue = (if Head = 0 then
                best_partition(PairRest, Sets, Partials, 1) else Skipped),
            PartialPair = (if Sets + Partials < 4 then
                best_partition(PairRest, Sets, Partials + 1, Head) else Skipped),
            Triplet = (if Sets < 4, PairRest = [K | TripRest] then
                best_partition(TripRest, Sets + 1, Partials, Head) else Skipped),
            DuplicateBest = int.max(HeadValue, int.max(PartialPair, Triplet))
          else DuplicateBest = Skipped
        ),
        Baseline = int.max(Skipped, DuplicateBest),
        ( if not honor(K), rank(K) =< 8, remove_kind(K + 1, Ks, AdjRest)
          then
            Adjacent = (if Sets + Partials < 4 then
                best_partition(AdjRest, Sets, Partials + 1, Head) else Baseline),
            Run = (if Sets < 4, rank(K) =< 7,
                remove_kind(K + 2, AdjRest, RunRest) then
                best_partition(RunRest, Sets + 1, Partials, Head) else Baseline),
            AdjBest = int.max(Baseline, int.max(Adjacent, Run))
          else AdjBest = Baseline
        ),
        ( if Sets + Partials < 4, not honor(K), rank(K) =< 7,
            remove_kind(K + 2, Ks, GapRest)
          then Best = int.max(AdjBest, best_partition(GapRest, Sets, Partials + 1, Head))
          else Best = AdjBest
        )
    ).

:- func partition_value(int, int, int) = int.
partition_value(Sets, Partials, Head) =
    2 * Sets + int.min(4 - Sets, Partials) + Head.

structural_waits(Ks, N) = set.from_list(list.filter(
    (pred(K::in) is semidet :- complete(add_kind(K, Ks), N)), all_kinds)).

live_tenpai(Ts, Ms) :-
    Ks = kinds(Ts),
    N = list.length(Ms),
    Bag = owned(Ts, Ms),
    list.find_first_match(
        (pred(K::in) is semidet :-
            bag.count_value(Bag, K) < 4, complete(add_kind(K, Ks), N)), all_kinds, _).

improvements(Ts, Ms, Before, Waits, Count) :-
    Ks = kinds(Ts),
    N = list.length(Ms),
    Bag = owned(Ts, Ms),
    Before = minimum(shanten(Ks, N)),
    Waits = list.filter(
        (pred(K::in) is semidet :-
            bag.count_value(Bag, K) < 4,
            Drawn = add_kind(K, Ks),
            ( if Before = 0 then complete(Drawn, N)
              else minimum(shanten(Drawn, N)) < Before
            )
        ), all_kinds),
    Count = list.foldl((func(K, Sum) = Sum + 4 - bag.count_value(Bag, K)), Waits, 0).

:- func owned(list(tile), list(meld)) = bag(kind).
owned(Ts, Ms) = bag.from_list(kinds(Ts ++ list.condense(list.map(meld_tiles, Ms)))).
