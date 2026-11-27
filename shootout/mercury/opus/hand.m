%---------------------------------------------------------------------------%
% hand.m: decomposition of concealed tiles, agari forms, shanten, waits.
%---------------------------------------------------------------------------%
:- module hand.
:- interface.

:- import_module tile.
:- import_module bag.
:- import_module list.
:- import_module set.

    % A set of concealed tiles; the kind is the lowest tile.
:- type group
    --->    run(kind)
    ;       triplet(kind).

    % Every way of splitting the bag into runs and triplets.
:- pred sets(bag(kind)::in, list(group)::out) is nondet.

    % A pair plus sets.
:- pred standard_form(bag(kind)::in, kind::out, list(group)::out) is nondet.

:- pred is_chiitoi(bag(kind)::in) is semidet.
    % Succeeds with the kind that forms the pair.
:- pred is_kokushi(bag(kind)::in, kind::out) is semidet.

:- func group_kinds(group) = list(kind).

    % The nine counts of a number suit.
:- func suit_counts(bag(kind), suit) = list(int).

    % The printed forms of a complete hand of concealed tiles, given the
    % number of melds, sorted, without duplicates.  [] if not complete.
:- func agari_forms(bag(kind), int) = list(string).

:- type shanten
    --->    shanten(std :: int, chiitoi :: int, kokushi :: int).

    % shanten(Concealed, NumMelds).  chiitoi and kokushi are only
    % meaningful when NumMelds = 0.
:- func shanten(bag(kind), int) = shanten.
:- func min_shanten(bag(kind), int) = int.

:- type waits
    --->    waits(w_shanten :: int, w_tiles :: list(kind), w_count :: int).

    % waits(Concealed, Visible, NumMelds): Visible is every tile of this
    % seat (hand and melds), for counting copies left.
:- func waits(bag(kind), bag(kind), int) = waits.

    % The kinds that would complete the hand, ignoring availability.
:- func wait_kinds(bag(kind), int) = set(kind).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module int.
:- import_module pair.
:- import_module solutions.
:- import_module string.

%---------------------------------------------------------------------------%
% Decomposition

sets(B, []) :-
    bag.is_empty(B).
sets(B0, [G | Gs]) :-
    bag.remove_smallest(K, B0, B1),
    (
        bag.remove(K, B1, B2a),
        bag.remove(K, B2a, B2),
        G = triplet(K)
    ;
        offset(K, 1, K1),
        offset(K, 2, K2),
        bag.remove(K1, B1, B2a),
        bag.remove(K2, B2a, B2),
        G = run(K)
    ),
    sets(B2, Gs).

standard_form(B0, P, Sets) :-
    bag.to_list_without_duplicates(B0, Kinds),
    list.member(P, Kinds),
    bag.remove(P, B0, B1),
    bag.remove(P, B1, B2),
    sets(B2, Sets).

is_chiitoi(B) :-
    bag.count(B) = 14,
    bag.to_assoc_list(B, KCs),
    list.length(KCs) = 7,
    list.all_true((pred(_ - C::in) is semidet :- C = 2), KCs).

is_kokushi(B, Pair) :-
    bag.count(B) = 14,
    bag.to_assoc_list(B, KCs),
    list.length(KCs) = 13,
    list.all_true((pred(K - _::in) is semidet :- is_yaochu(K)), KCs),
    list.find_first_match((pred(_ - C::in) is semidet :- C = 2), KCs,
        Pair - _).

group_kinds(triplet(K)) = [K, K, K].
group_kinds(run(K)) = [K, K1, K2] :-
    ( if offset(K, 1, K1P), offset(K, 2, K2P) then
        K1 = K1P, K2 = K2P
    else
        K1 = K, K2 = K      % cannot happen: runs are built by offset
    ).

agari_forms(B, NumMelds) = Forms :-
    Standard = solutions(
        (pred(S::out) is nondet :-
            standard_form(B, P, Sets),
            S = form_string(P, Sets))),
    ( if NumMelds = 0, is_chiitoi(B) then
        Chiitoi = ["chiitoi"]
    else
        Chiitoi = []
    ),
    ( if NumMelds = 0, is_kokushi(B, _) then
        Kokushi = ["kokushi"]
    else
        Kokushi = []
    ),
    Forms = list.sort_and_remove_dups(Standard ++ Chiitoi ++ Kokushi).

    % Groups print sorted by first kind, then pair < run < triplet.
:- func form_string(kind, list(group)) = string.
form_string(Pair, Sets) = string.join_list(",",
    list.map((func({_, _, Str}) = Str),
        list.sort([{Pair, 0, kinds_to_string([Pair, Pair])} |
            list.map(print_key, Sets)]))).

:- func print_key(group) = {kind, int, string}.
print_key(G) = {K, Rank, kinds_to_string(group_kinds(G))} :-
    ( G = run(K), Rank = 1
    ; G = triplet(K), Rank = 2
    ).

%---------------------------------------------------------------------------%
% Shanten

    % Sets, partial sets (taatsu, including spare pairs) and head (0 or 1)
    % found in one block of tiles.
:- type partial
    --->    partial(p_sets :: int, p_taatsu :: int, p_head :: int).

    % One step of reading a block given as a list of counts: the lowest
    % kind is either used in a group starting there, or all its copies are
    % left isolated.  Returns the counts left and what the step added.
:- pred step(int::in, list(int)::in, list(int)::out, partial::out) is multi.
step(C0, Cs, Next, Added) :-
    (
        C0 >= 3,
        Next = [C0 - 3 | Cs], Added = partial(1, 0, 0)
    ;
        Cs = [C1, C2 | Rest], C1 >= 1, C2 >= 1,
        Next = [C0 - 1, C1 - 1, C2 - 1 | Rest], Added = partial(1, 0, 0)
    ;
        C0 >= 2,
        Next = [C0 - 2 | Cs], Added = partial(0, 0, 1)
    ;
        C0 >= 2,
        Next = [C0 - 2 | Cs], Added = partial(0, 1, 0)
    ;
        Cs = [C1 | Rest], C1 >= 1,
        Next = [C0 - 1, C1 - 1 | Rest], Added = partial(0, 1, 0)
    ;
        Cs = [C1, C2 | Rest], C2 >= 1,
        Next = [C0 - 1, C1, C2 - 1 | Rest], Added = partial(0, 1, 0)
    ;
        Next = Cs, Added = partial(0, 0, 0)
    ).

    % The Pareto-best readings of a block of counts, by dynamic programming
    % over the counts that remain.  Memoised: the same suffixes recur within
    % one search and across requests (waits asks 35 times per request).
:- func block_best(list(int)) = list(partial).
:- pragma memo(block_best/1).
block_best([]) = [partial(0, 0, 0)].
block_best([C0 | Cs]) = Best :-
    ( if C0 = 0 then
        Best = block_best(Cs)
    else
        Best = pareto(solutions(
            (pred(P::out) is nondet :-
                step(C0, Cs, Next, partial(M0, T0, H0)),
                list.member(partial(M, T, H), block_best(Next)),
                H + H0 =< 1,
                P = partial(M + M0, T + T0, H + H0))))
    ).

:- func pareto(list(partial)) = list(partial).
pareto(Ps) = list.filter((pred(P::in) is semidet :-
        not (list.member(Q, Ps), Q \= P, dominates(Q, P))), Ps).

:- pred dominates(partial::in, partial::in) is semidet.
dominates(partial(M1, T1, H1), partial(M2, T2, H2)) :-
    M1 >= M2, T1 >= T2, H1 >= H2.

suit_counts(B, S) = list.map((func(N) = bag.count_value(B, kind(S, N))),
    1 .. 9).

    % Honors form no runs or taatsu, so their readings are a closed form:
    % every triplet is a set, every pair is a taatsu or the head.
:- func honor_best(list(pair(kind, int))) = list(partial).
honor_best(KCs) = Options :-
    Honors = list.filter((pred(K - _::in) is semidet :- is_honor(K)), KCs),
    Sets = list.length(list.filter((pred(_ - C::in) is semidet :- C >= 3),
        Honors)),
    Pairs = list.length(list.filter((pred(_ - C::in) is semidet :- C = 2),
        Honors)),
    Options = [partial(Sets, Pairs, 0) |
        ( if Pairs >= 1 then [partial(Sets, Pairs - 1, 1)] else [] )].

    % The best standard shanten over one reading per block, with at most
    % one head and sets + taatsu =< 4.
:- func best_std(list(list(partial)), int, int, int) = int.
best_std([], M, T, H) = 8 - 2 * M - int.min(T, 4 - M) - H.
best_std([Opts | Blocks], M, T, H) = list.foldl(
    (func(partial(M1, T1, H1), Acc) =
        ( if H + H1 =< 1 then
            int.min(Acc, best_std(Blocks, M + M1, T + T1, H + H1))
        else
            Acc
        )),
    Opts, 8).

shanten(B, NumMelds) = shanten(Std, Chiitoi, Kokushi) :-
    bag.to_assoc_list(B, KCs),
    Std = best_std([block_best(suit_counts(B, man)),
        block_best(suit_counts(B, pin)), block_best(suit_counts(B, sou)),
        honor_best(KCs)], NumMelds, 0, 0),
    Pairs = list.length(list.filter((pred(_ - C::in) is semidet :- C >= 2),
        KCs)),
    Kinds = list.length(KCs),
    Chiitoi = 6 - Pairs + int.max(0, 7 - Kinds),
    Yaochu = list.filter((pred(K - _::in) is semidet :- is_yaochu(K)), KCs),
    ( if list.member(_ - YC, Yaochu), YC >= 2 then
        YPair = 1
    else
        YPair = 0
    ),
    Kokushi = 13 - list.length(Yaochu) - YPair.

min_shanten(B, NumMelds) = Min :-
    shanten(Std, Chiitoi, Kokushi) = shanten(B, NumMelds),
    ( if NumMelds = 0 then
        Min = int.min(Std, int.min(Chiitoi, Kokushi))
    else
        Min = Std
    ).

waits(B, Visible, NumMelds) = waits(S, Tiles, Count) :-
    S = min_shanten(B, NumMelds),
    Tiles = list.filter(
        (pred(K::in) is semidet :-
            bag.count_value(Visible, K) < 4,
            min_shanten(bag.insert(B, K), NumMelds) < S),
        all_kinds),
    Count = list.foldl(
        (func(K, Acc) = Acc + 4 - bag.count_value(Visible, K)), Tiles, 0).

wait_kinds(B, NumMelds) = set.from_list(list.filter(
    (pred(K::in) is semidet :- min_shanten(bag.insert(B, K), NumMelds) = -1),
    all_kinds)).

%---------------------------------------------------------------------------%
:- end_module hand.
%---------------------------------------------------------------------------%
