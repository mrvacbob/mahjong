:- module agari.
:- interface.

:- import_module bag.
:- import_module list.
:- import_module tiles.

:- type concealed_group
    --->    pair(tile_kind)
    ;       seq(num_suit, int)
    ;       triplet(tile_kind).

:- type agari_form
    --->    std_form(list(concealed_group))
    ;       chiitoi_form
    ;       kokushi_form.

:- pred decompose_std(bag(tile_kind)::in, tile_kind::out,
    list(concealed_group)::out) is nondet.

:- pred is_chiitoi(bag(tile_kind)::in, list(meld)::in) is semidet.
:- pred is_kokushi(bag(tile_kind)::in, list(meld)::in) is semidet.

:- pred is_agari(bag(tile_kind)::in, list(meld)::in) is semidet.

:- func all_agari_forms(bag(tile_kind), list(meld)) = list(agari_form).

:- func format_agari_response(bag(tile_kind), list(meld)) = string.

:- implementation.

:- import_module assoc_list.
:- import_module int.
:- import_module maybe.
:- import_module pair.
:- import_module solutions.
:- import_module string.

decompose_std(Bag, PairKind, Groups) :-
    bag.to_assoc_list(Bag, Assoc),
    list.member(PairKind - Count, Assoc),
    Count >= 2,
    bag.remove(PairKind, Bag, Bag1),
    bag.remove(PairKind, Bag1, Bag2),
    decompose_groups(Bag2, no, [], Groups).

:- pred decompose_groups(bag(tile_kind)::in, maybe(tile_kind)::in,
    list(concealed_group)::in, list(concealed_group)::out) is nondet.

decompose_groups(Bag, MaybeNoSeqKind, Acc, Groups) :-
    ( if bag.is_empty(Bag) then
        Groups = Acc
    else
        bag.remove_smallest(MinK, Bag, Bag1),
        (
            % Triplet of MinK
            bag.remove(MinK, Bag1, Bag2),
            bag.remove(MinK, Bag2, Bag3),
            decompose_groups(Bag3, yes(MinK), [triplet(MinK) | Acc], Groups)
        ;
            % Sequence starting at MinK
            MaybeNoSeqKind \= yes(MinK),
            MinK = num(S, N),
            N =< 7,
            bag.remove(num(S, N + 1), Bag1, Bag2),
            bag.remove(num(S, N + 2), Bag2, Bag3),
            decompose_groups(Bag3, MaybeNoSeqKind, [seq(S, N) | Acc], Groups)
        )
    ).

is_chiitoi(Bag, Melds) :-
    Melds = [],
    bag.count(Bag) = 14,
    bag.count_unique(Bag) = 7,
    bag.to_assoc_list(Bag, Assoc),
    list.all_true((pred((_ - C)::in) is semidet :- C = 2), Assoc).

is_kokushi(Bag, Melds) :-
    Melds = [],
    bag.count(Bag) = 14,
    bag.count_unique(Bag) = 13,
    list.all_true((pred(K::in) is semidet :- bag.contains(Bag, K)),
        yaochuu_kinds).

is_agari(Bag, Melds) :-
    ( if is_kokushi(Bag, Melds) then
        true
    else if is_chiitoi(Bag, Melds) then
        true
    else
        some [_P, _Gs] decompose_std(Bag, _P, _Gs)
    ).

all_agari_forms(Bag, Melds) = Forms :-
    solutions.solutions(
        (pred(F::out) is nondet :-
            decompose_std(Bag, PairKind, Groups),
            AllGroups = [pair(PairKind) | Groups],
            list.sort(compare_group, AllGroups, SortedGroups),
            F = std_form(SortedGroups)
        ),
        StdForms),
    ChiitoiForms = ( if is_chiitoi(Bag, Melds) then [chiitoi_form] else [] ),
    KokushiForms = ( if is_kokushi(Bag, Melds) then [kokushi_form] else [] ),
    Forms = StdForms ++ ChiitoiForms ++ KokushiForms.

:- pred compare_group(concealed_group::in, concealed_group::in,
    comparison_result::out) is det.

compare_group(G1, G2, Res) :-
    compare(Res0, group_first_kind(G1), group_first_kind(G2)),
    ( if Res0 = (=) then
        compare(Res, group_kind_rank(G1), group_kind_rank(G2))
    else
        Res = Res0
    ).

:- func group_first_kind(concealed_group) = tile_kind.

group_first_kind(pair(K)) = K.
group_first_kind(seq(S, N)) = num(S, N).
group_first_kind(triplet(K)) = K.

:- func group_kind_rank(concealed_group) = int.

group_kind_rank(pair(_)) = 0.
group_kind_rank(seq(_, _)) = 1.
group_kind_rank(triplet(_)) = 2.

:- func format_group(concealed_group) = string.

format_group(pair(K)) =
    string.from_char_list([D, D, S]) :-
        D = kind_digit_char(K),
        S = suit_char(K).
format_group(seq(Suit, N)) =
    string.from_char_list([D1, D2, D3, S]) :-
        D1 = kind_digit_char(num(Suit, N)),
        D2 = kind_digit_char(num(Suit, N + 1)),
        D3 = kind_digit_char(num(Suit, N + 2)),
        S = suit_char(num(Suit, N)).
format_group(triplet(K)) =
    string.from_char_list([D, D, D, S]) :-
        D = kind_digit_char(K),
        S = suit_char(K).

:- func format_form(agari_form) = string.

format_form(std_form(Groups)) =
    string.join_list(",", list.map(format_group, Groups)).
format_form(chiitoi_form) = "chiitoi".
format_form(kokushi_form) = "kokushi".

format_agari_response(Bag, Melds) = Resp :-
    Forms = all_agari_forms(Bag, Melds),
    ( if Forms = [] then
        Resp = "win=0"
    else
        FormStrs = list.sort_and_remove_dups(list.map(format_form, Forms)),
        Resp = "win=1 forms=" ++ string.join_list(";", FormStrs)
    ).
