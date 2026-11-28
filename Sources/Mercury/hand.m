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

    % complete(Concealed, NumMelds): the tiles are a whole hand (14 - 3k of
    % them) in standard form, or, with no melds, chiitoi or kokushi.
:- pred complete(bag(kind)::in, int::in) is semidet.

    % The printed forms of a complete hand of concealed tiles, given the
    % number of melds, sorted, without duplicates.  [] if not complete.
:- func agari_forms(bag(kind), int) = list(string).

    % Chiitoi and kokushi exist only for a hand with no melds.
:- type shanten
    --->    with_melds(int)
    ;       no_melds(int, int, int).    % std, chiitoi, kokushi

    % shanten(Concealed, NumMelds).
:- func shanten(bag(kind), int) = shanten.
:- func std(shanten) = int.
:- func min_of(shanten) = int.

:- type waits
    --->    waits(w_shanten :: int, w_tiles :: list(kind), w_count :: int).

    % waits(Concealed, Visible, NumMelds): Visible is every tile of this
    % seat (hand and melds), for counting copies left.
:- func waits(bag(kind), bag(kind), int) = waits.

    % completes(Concealed, NumMelds, K): drawing K makes the hand complete.
:- pred completes(bag(kind)::in, int::in, kind::in) is semidet.

    % Tenpai on at least one kind with a copy this seat cannot see.
:- pred live_tenpai(bag(kind)::in, bag(kind)::in, int::in) is semidet.

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
        bag.remove_list([K, K], B1, B2),
        G = triplet(K)
    ;
        offset(K, 1, K1),
        offset(K, 2, K2),
        bag.remove_list([K1, K2], B1, B2),
        G = run(K)
    ),
    sets(B2, Gs).

standard_form(B0, P, Sets) :-
    list.member(P, bag.to_list_only_duplicates(B0)),
    bag.remove_list([P, P], B0, B1),
    sets(B1, Sets).

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
group_kinds(run(kind(S, N))) = [kind(S, N), kind(S, N + 1), kind(S, N + 2)].

complete(B, NumMelds) :-
    agari_form(B, NumMelds, _).

agari_forms(B, NumMelds) = solutions(agari_form(B, NumMelds)).

:- pred agari_form(bag(kind)::in, int::in, string::out) is nondet.
agari_form(B, NumMelds, Form) :-
    bag.count(B) = 14 - 3 * NumMelds,
    (
        standard_form(B, P, Sets),
        Form = form_string(P, Sets)
    ;
        NumMelds = 0, is_chiitoi(B), Form = "chiitoi"
    ;
        NumMelds = 0, is_kokushi(B, _), Form = "kokushi"
    ).

    % Groups print sorted by first kind, then pair < run < triplet: the
    % constructor order of `piece'.
:- type piece
    --->    pair(kind)
    ;       group(group).

:- func form_string(kind, list(group)) = string.
form_string(Pair, Sets) = string.join_list(",",
    list.map(piece_string, list.sort(list.map(keyed,
        [pair(Pair) | list.map((func(G) = group(G)), Sets)])))).

:- func keyed(piece) = {kind, piece}.
keyed(P @ pair(K)) = {K, P}.
keyed(P @ group(run(K))) = {K, P}.
keyed(P @ group(triplet(K))) = {K, P}.

:- func piece_string({kind, piece}) = string.
piece_string({K, pair(_)}) = kinds_to_string([K, K]).
piece_string({_, group(G)}) = kinds_to_string(group_kinds(G)).

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
    % every three copies are a set, two left over are a taatsu or the head.
    % (Five copies occur when a wait is a fifth copy: 11111z is 111z + 11z.)
:- func honor_best(list(pair(kind, int))) = list(partial).
honor_best(KCs) = Options :-
    Honors = list.filter((pred(K - _::in) is semidet :- is_honor(K)), KCs),
    Sets = list.foldl((func(_ - C, A) = A + C // 3), Honors, 0),
    Pairs = list.length(list.filter(
        (pred(_ - C::in) is semidet :- C mod 3 = 2), Honors)),
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

shanten(B, NumMelds) = Shanten :-
    bag.to_assoc_list(B, KCs),
    Std = best_std([block_best(suit_counts(B, man)),
        block_best(suit_counts(B, pin)), block_best(suit_counts(B, sou)),
        honor_best(KCs)], NumMelds, 0, 0),
    ( if NumMelds = 0 then
        Pairs = list.length(list.filter(
            (pred(_ - C::in) is semidet :- C >= 2), KCs)),
        Chiitoi = 6 - Pairs + int.max(0, 7 - list.length(KCs)),
        Yaochu = list.filter((pred(K - _::in) is semidet :- is_yaochu(K)),
            KCs),
        YPair = ( if list.member(_ - YC, Yaochu), YC >= 2 then 1 else 0 ),
        Kokushi = 13 - list.length(Yaochu) - YPair,
        Shanten = no_melds(Std, Chiitoi, Kokushi)
    else
        Shanten = with_melds(Std)
    ).

std(with_melds(Std)) = Std.
std(no_melds(Std, _, _)) = Std.

min_of(with_melds(Std)) = Std.
min_of(no_melds(Std, Chiitoi, Kokushi)) =
    int.min(Std, int.min(Chiitoi, Kokushi)).

:- func min_shanten(bag(kind), int) = int.
min_shanten(B, NumMelds) = min_of(shanten(B, NumMelds)).

waits(B, Visible, NumMelds) = waits(S, Tiles, Count) :-
    S = min_shanten(B, NumMelds),
    Tiles = list.filter((pred(K::in) is semidet :-
            copies_left(Visible, K) > 0,
            lowers_shanten(B, NumMelds, S, K)),
        all_kinds),
    Count = list.foldl((func(K, Acc) = Acc + copies_left(Visible, K)),
        Tiles, 0).

    % Drawing K lowers the shanten S.  From tenpai that means completing
    % the hand, which is tested directly: the same rule, and much cheaper
    % than a shanten evaluation.
:- pred lowers_shanten(bag(kind)::in, int::in, int::in, kind::in) is semidet.
lowers_shanten(B, NumMelds, S, K) :-
    ( if S = 0 then
        completes(B, NumMelds, K)
    else
        min_shanten(bag.insert(B, K), NumMelds) < S
    ).

:- func copies_left(bag(kind), kind) = int.
copies_left(Visible, K) = 4 - bag.count_value(Visible, K).

completes(B, NumMelds, K) :-
    complete(bag.insert(B, K), NumMelds).

live_tenpai(B, Visible, NumMelds) :-
    list.member(K, all_kinds),
    copies_left(Visible, K) > 0,
    completes(B, NumMelds, K).

wait_kinds(B, NumMelds) = set.from_list(list.filter(completes(B, NumMelds),
    all_kinds)).

%---------------------------------------------------------------------------%
:- end_module hand.
%---------------------------------------------------------------------------%
