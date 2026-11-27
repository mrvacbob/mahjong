:- module shanten.
:- interface.

:- import_module bag.
:- import_module list.
:- import_module maybe.
:- import_module set.
:- import_module tiles.

:- type shanten_result
    --->    shanten_result(
                std     :: int,
                chiitoi :: maybe(int),
                kokushi :: maybe(int),
                min_sh  :: int
            ).

:- type waits_result
    --->    waits_result(
                wait_shanten :: int,
                wait_tiles   :: list(tile_kind),
                wait_count   :: int
            ).

:- func compute_shanten(bag(tile_kind), list(meld)) = shanten_result.
:- func compute_waits(list(tile), list(meld)) = waits_result.
:- func structural_waits(bag(tile_kind), list(meld)) = set(tile_kind).

:- func format_shanten_response(shanten_result) = string.
:- func format_waits_response(waits_result) = string.

:- implementation.

:- import_module agari.
:- import_module assoc_list.
:- import_module bool.
:- import_module int.
:- import_module pair.
:- import_module string.

% For each suit, track the maximum taatsu achievable for 0, 1, 2, 3, 4 sets.
% -1 means that number of sets is not achievable in this suit.
:- type suit_best
    --->    suit_best(int, int, int, int, int).

:- func empty_suit_best = suit_best.
empty_suit_best = suit_best(-1, -1, -1, -1, -1).

:- func get_best(suit_best, int) = int.
get_best(suit_best(T0, T1, T2, T3, T4), S) =
    ( if S = 0 then T0
    else if S = 1 then T1
    else if S = 2 then T2
    else if S = 3 then T3
    else if S = 4 then T4
    else -1
    ).

:- func set_max_best(suit_best, int, int) = suit_best.
set_max_best(suit_best(T0, T1, T2, T3, T4), S, T) =
    ( if S = 0 then suit_best(int.max(T0, T), T1, T2, T3, T4)
    else if S = 1 then suit_best(T0, int.max(T1, T), T2, T3, T4)
    else if S = 2 then suit_best(T0, T1, int.max(T2, T), T3, T4)
    else if S = 3 then suit_best(T0, T1, T2, int.max(T3, T), T4)
    else if S = 4 then suit_best(T0, T1, T2, T3, int.max(T4, T))
    else suit_best(T0, T1, T2, T3, T4)
    ).

:- func max_suit_best(suit_best, suit_best) = suit_best.
max_suit_best(suit_best(A0, A1, A2, A3, A4), suit_best(B0, B1, B2, B3, B4)) =
    suit_best(
        int.max(A0, B0),
        int.max(A1, B1),
        int.max(A2, B2),
        int.max(A3, B3),
        int.max(A4, B4)
    ).

:- func combine_best(suit_best, suit_best) = suit_best.
combine_best(A, B) = Res :-
    combine_loop(A, B, 0, empty_suit_best, Res).

:- pred combine_loop(suit_best::in, suit_best::in, int::in,
    suit_best::in, suit_best::out) is det.

combine_loop(A, B, Sa, !Acc) :-
    ( if Sa > 4 then
        true
    else
        Ta = get_best(A, Sa),
        ( if Ta >= 0 then
            combine_inner(Ta, B, Sa, 0, !Acc)
        else
            true
        ),
        combine_loop(A, B, Sa + 1, !Acc)
    ).

:- pred combine_inner(int::in, suit_best::in, int::in, int::in,
    suit_best::in, suit_best::out) is det.

combine_inner(Ta, B, Sa, Sb, !Acc) :-
    S = Sa + Sb,
    ( if S > 4 then
        true
    else
        Tb = get_best(B, Sb),
        ( if Tb >= 0 then
            !:Acc = set_max_best(!.Acc, S, Ta + Tb)
        else
            true
        ),
        combine_inner(Ta, B, Sa, Sb + 1, !Acc)
    ).

:- func num_suit_counts(bag(tile_kind), num_suit) = list(int).
num_suit_counts(Bag, S) = [
    bag.count_value(Bag, num(S, 1)),
    bag.count_value(Bag, num(S, 2)),
    bag.count_value(Bag, num(S, 3)),
    bag.count_value(Bag, num(S, 4)),
    bag.count_value(Bag, num(S, 5)),
    bag.count_value(Bag, num(S, 6)),
    bag.count_value(Bag, num(S, 7)),
    bag.count_value(Bag, num(S, 8)),
    bag.count_value(Bag, num(S, 9))
].

:- func honor_counts(bag(tile_kind)) = list(int).
honor_counts(Bag) = [
    bag.count_value(Bag, wind(east)),
    bag.count_value(Bag, wind(south)),
    bag.count_value(Bag, wind(west)),
    bag.count_value(Bag, wind(north)),
    bag.count_value(Bag, dragon(haku)),
    bag.count_value(Bag, dragon(hatsu)),
    bag.count_value(Bag, dragon(chun))
].

:- pred eval_num_suit(list(int)::in, suit_best::out, suit_best::out) is det.

eval_num_suit(Counts, NoHead, WithHead) :-
    search_suit(Counts, 0, 0, empty_suit_best, NoHead),
    eval_num_suit_head(Counts, [], empty_suit_best, WithHead).

:- pred eval_num_suit_head(list(int)::in, list(int)::in,
    suit_best::in, suit_best::out) is det.

eval_num_suit_head([], _, !Best).
eval_num_suit_head([C | Cs], RevPrefix, !Best) :-
    ( if C >= 2 then
        list.reverse(RevPrefix, Prefix),
        NewCounts = Prefix ++ [C - 2 | Cs],
        search_suit(NewCounts, 0, 0, empty_suit_best, SubBest),
        !:Best = max_suit_best(!.Best, SubBest)
    else
        true
    ),
    eval_num_suit_head(Cs, [C | RevPrefix], !Best).

% Search all sets and taatsu in a numbered suit.
% Phase 1 at each rank: try triplets/sequences, then advance to Phase 2 (taatsu).
:- pred search_suit(list(int)::in, int::in, int::in,
    suit_best::in, suit_best::out) is det.

search_suit([], Sets, Taatsu, !Best) :-
    !:Best = set_max_best(!.Best, Sets, Taatsu).
search_suit([C | Cs], Sets, Taatsu, !Best) :-
    ( if C = 0 then
        search_suit(Cs, Sets, Taatsu, !Best)
    else
        % 1. Try triplet
        ( if C >= 3 then
            search_suit([C - 3 | Cs], Sets + 1, Taatsu, !Best)
        else
            true
        ),
        % 2. Try sequence
        ( if Cs = [C1, C2 | Rest], C >= 1, C1 >= 1, C2 >= 1 then
            search_suit([C - 1, C1 - 1, C2 - 1 | Rest],
                Sets + 1, Taatsu, !Best)
        else
            true
        ),
        % 3. No more sets starting at this rank; try taatsu starting here
        search_suit_taatsu([C | Cs], Sets, Taatsu, !Best)
    ).

:- pred search_suit_taatsu(list(int)::in, int::in, int::in,
    suit_best::in, suit_best::out) is det.

search_suit_taatsu([], Sets, Taatsu, !Best) :-
    !:Best = set_max_best(!.Best, Sets, Taatsu).
search_suit_taatsu([C | Cs], Sets, Taatsu, !Best) :-
    % 1. Pair taatsu
    ( if C >= 2 then
        search_suit_taatsu([C - 2 | Cs], Sets, Taatsu + 1, !Best)
    else
        true
    ),
    % 2. Adjacent taatsu (ryanmen/penchan)
    ( if Cs = [C1a | RestA], C >= 1, C1a >= 1 then
        search_suit_taatsu([C - 1, C1a - 1 | RestA], Sets, Taatsu + 1, !Best)
    else
        true
    ),
    % 3. Kanchan taatsu
    ( if Cs = [C1b, C2b | RestB], C >= 1, C2b >= 1 then
        search_suit_taatsu([C - 1, C1b, C2b - 1 | RestB],
            Sets, Taatsu + 1, !Best)
    else
        true
    ),
    % 4. Skip remaining copies at this rank
    search_suit(Cs, Sets, Taatsu, !Best).

:- pred eval_honors(list(int)::in, suit_best::out, suit_best::out) is det.

eval_honors(Counts, NoHead, WithHead) :-
    honor_sets_taatsu(Counts, 0, 0, S0, T0),
    NoHead = set_max_best(empty_suit_best, S0, T0),
    eval_honors_head(Counts, [], empty_suit_best, WithHead).

:- pred honor_sets_taatsu(list(int)::in, int::in, int::in,
    int::out, int::out) is det.

honor_sets_taatsu([], S, T, S, T).
honor_sets_taatsu([C | Cs], S0, T0, S, T) :-
    ( if C >= 3 then
        honor_sets_taatsu(Cs, S0 + 1, T0, S, T)
    else if C = 2 then
        honor_sets_taatsu(Cs, S0, T0 + 1, S, T)
    else
        honor_sets_taatsu(Cs, S0, T0, S, T)
    ).

:- pred eval_honors_head(list(int)::in, list(int)::in,
    suit_best::in, suit_best::out) is det.

eval_honors_head([], _, !Best).
eval_honors_head([C | Cs], RevPrefix, !Best) :-
    ( if C >= 2 then
        list.reverse(RevPrefix, Prefix),
        NewCounts = Prefix ++ [C - 2 | Cs],
        honor_sets_taatsu(NewCounts, 0, 0, S, T),
        !:Best = set_max_best(!.Best, S, T)
    else
        true
    ),
    eval_honors_head(Cs, [C | RevPrefix], !Best).

:- func std_shanten(bag(tile_kind), int) = int.

std_shanten(Bag, NumMelds) = BestShanten :-
    eval_num_suit(num_suit_counts(Bag, m), MNo, MHd),
    eval_num_suit(num_suit_counts(Bag, p), PNo, PHd),
    eval_num_suit(num_suit_counts(Bag, s), SNo, SHd),
    eval_honors(honor_counts(Bag), ZNo, ZHd),
    BestShanten = combine_four_suits(NumMelds, MNo, MHd, PNo, PHd,
        SNo, SHd, ZNo, ZHd).

:- func combine_four_suits(int, suit_best, suit_best, suit_best, suit_best,
    suit_best, suit_best, suit_best, suit_best) = int.

combine_four_suits(NumMelds, MNo, MHd, PNo, PHd, SNo, SHd, ZNo, ZHd) =
        BestShanten :-
    SZNo = combine_best(SNo, ZNo),
    PSZNo = combine_best(PNo, SZNo),
    TotalNo = combine_best(MNo, PSZNo),

    MPNo = combine_best(MNo, PNo),
    H1 = combine_best(MHd, PSZNo),
    H2 = combine_best(MNo, combine_best(PHd, SZNo)),
    H3 = combine_best(MPNo, combine_best(SHd, ZNo)),
    H4 = combine_best(MPNo, combine_best(SNo, ZHd)),
    TotalHd = max_suit_best(max_suit_best(H1, H2), max_suit_best(H3, H4)),

    MaxConcealedSets = 4 - NumMelds,
    min_shanten_from_table(TotalNo, NumMelds, MaxConcealedSets, 0, 0, 8, Sh1),
    min_shanten_from_table(TotalHd, NumMelds, MaxConcealedSets, 1, 0, Sh1,
        BestShanten).

:- pred min_shanten_from_table(suit_best::in, int::in, int::in, int::in,
    int::in, int::in, int::out) is det.

min_shanten_from_table(Table, NumMelds, MaxSets, Head, S, !Best) :-
    ( if S > MaxSets then
        true
    else
        T = get_best(Table, S),
        ( if T >= 0 then
            EffT = int.min(T, MaxSets - S),
            Sh = 8 - 2 * (NumMelds + S) - EffT - Head,
            !:Best = int.min(!.Best, Sh)
        else
            true
        ),
        min_shanten_from_table(Table, NumMelds, MaxSets, Head, S + 1, !Best)
    ).

:- func chiitoi_shanten(bag(tile_kind)) = int.

chiitoi_shanten(Bag) = 6 - Pairs + int.max(0, 7 - Kinds) :-
    Kinds = bag.count_unique(Bag),
    bag.to_assoc_list(Bag, Assoc),
    list.foldl(
        (pred((_ - C)::in, Acc0::in, Acc::out) is det :-
            ( if C >= 2 then Acc = Acc0 + 1 else Acc = Acc0 )
        ),
        Assoc, 0, Pairs).

:- func kokushi_shanten(bag(tile_kind)) = int.

kokushi_shanten(Bag) = 13 - YaoKinds - HasPair :-
    list.foldl2(
        (pred(K::in, KAcc0::in, KAcc::out, PAcc0::in, PAcc::out) is det :-
            C = bag.count_value(Bag, K),
            ( if C >= 1 then KAcc = KAcc0 + 1 else KAcc = KAcc0 ),
            ( if C >= 2 then PAcc = 1 else PAcc = PAcc0 )
        ),
        yaochuu_kinds, 0, YaoKinds, 0, HasPair).

compute_shanten(Bag, Melds) = Res :-
    NumMelds = list.length(Melds),
    Std = std_shanten(Bag, NumMelds),
    ( if Melds = [] then
        Chi = chiitoi_shanten(Bag),
        Kok = kokushi_shanten(Bag),
        Min = int.min(Std, int.min(Chi, Kok)),
        Res = shanten_result(Std, yes(Chi), yes(Kok), Min)
    else
        Res = shanten_result(Std, no, no, Std)
    ).

compute_waits(Hand, Melds) = waits_result(BaseSh, WaitKinds, TotalCount) :-
    HandBag = hand_to_kind_bag(Hand),
    AllBag = all_tiles_kind_bag(Hand, Melds),
    NumMelds = list.length(Melds),
    eval_num_suit(num_suit_counts(HandBag, m), MNo, MHd),
    eval_num_suit(num_suit_counts(HandBag, p), PNo, PHd),
    eval_num_suit(num_suit_counts(HandBag, s), SNo, SHd),
    eval_honors(honor_counts(HandBag), ZNo, ZHd),
    BaseStd = combine_four_suits(NumMelds, MNo, MHd, PNo, PHd,
        SNo, SHd, ZNo, ZHd),
    ( if Melds = [] then
        BaseChi = chiitoi_shanten(HandBag),
        BaseKok = kokushi_shanten(HandBag),
        BaseSh = int.min(BaseStd, int.min(BaseChi, BaseKok))
    else
        BaseSh = BaseStd
    ),
    list.foldl2(
        (pred(K::in, Ks0::in, Ks::out, Cnt0::in, Cnt::out) is det :-
            Rem = 4 - bag.count_value(AllBag, K),
            ( if Rem > 0 then
                Bag1 = bag.insert(HandBag, K),
                ( if BaseSh = 0 then
                    Improves = ( if agari.is_agari(Bag1, Melds) then yes else no )
                else
                    Std1 = std_shanten_with_added(K, Bag1, NumMelds,
                        MNo, MHd, PNo, PHd, SNo, SHd, ZNo, ZHd),
                    ( if Melds = [] then
                        Sh1 = int.min(Std1,
                            int.min(chiitoi_shanten(Bag1), kokushi_shanten(Bag1)))
                    else
                        Sh1 = Std1
                    ),
                    Improves = ( if Sh1 < BaseSh then yes else no )
                ),
                ( if Improves = yes then
                    Ks = [K | Ks0],
                    Cnt = Cnt0 + Rem
                else
                    Ks = Ks0,
                    Cnt = Cnt0
                )
            else
                Ks = Ks0,
                Cnt = Cnt0
            )
        ),
        all_tile_kinds, [], RevWaitKinds, 0, TotalCount),
    list.reverse(RevWaitKinds, WaitKinds).

:- func std_shanten_with_added(tile_kind, bag(tile_kind), int,
    suit_best, suit_best, suit_best, suit_best,
    suit_best, suit_best, suit_best, suit_best) = int.

std_shanten_with_added(num(m, _), Bag1, NumMelds,
        _, _, PNo, PHd, SNo, SHd, ZNo, ZHd) =
    combine_four_suits(NumMelds, MNo1, MHd1, PNo, PHd, SNo, SHd, ZNo, ZHd) :-
        eval_num_suit(num_suit_counts(Bag1, m), MNo1, MHd1).
std_shanten_with_added(num(p, _), Bag1, NumMelds,
        MNo, MHd, _, _, SNo, SHd, ZNo, ZHd) =
    combine_four_suits(NumMelds, MNo, MHd, PNo1, PHd1, SNo, SHd, ZNo, ZHd) :-
        eval_num_suit(num_suit_counts(Bag1, p), PNo1, PHd1).
std_shanten_with_added(num(s, _), Bag1, NumMelds,
        MNo, MHd, PNo, PHd, _, _, ZNo, ZHd) =
    combine_four_suits(NumMelds, MNo, MHd, PNo, PHd, SNo1, SHd1, ZNo, ZHd) :-
        eval_num_suit(num_suit_counts(Bag1, s), SNo1, SHd1).
std_shanten_with_added(wind(_), Bag1, NumMelds,
        MNo, MHd, PNo, PHd, SNo, SHd, _, _) =
    combine_four_suits(NumMelds, MNo, MHd, PNo, PHd, SNo, SHd, ZNo1, ZHd1) :-
        eval_honors(honor_counts(Bag1), ZNo1, ZHd1).
std_shanten_with_added(dragon(_), Bag1, NumMelds,
        MNo, MHd, PNo, PHd, SNo, SHd, _, _) =
    combine_four_suits(NumMelds, MNo, MHd, PNo, PHd, SNo, SHd, ZNo1, ZHd1) :-
        eval_honors(honor_counts(Bag1), ZNo1, ZHd1).

structural_waits(HandBag, Melds) = WaitSet :-
    list.foldl(
        (pred(K::in, Set0::in, Set1::out) is det :-
            Bag1 = bag.insert(HandBag, K),
            ( if agari.is_agari(Bag1, Melds) then
                Set1 = set.insert(Set0, K)
            else
                Set1 = Set0
            )
        ),
        all_tile_kinds, set.init, WaitSet).

format_shanten_response(shanten_result(Std, MaybeChi, MaybeKok, Min)) =
    "std=" ++ string.int_to_string(Std) ++
    " chiitoi=" ++ format_maybe_int(MaybeChi) ++
    " kokushi=" ++ format_maybe_int(MaybeKok) ++
    " min=" ++ string.int_to_string(Min).

:- func format_maybe_int(maybe(int)) = string.
format_maybe_int(yes(N)) = string.int_to_string(N).
format_maybe_int(no) = "x".

format_waits_response(waits_result(Sh, Tiles, Count)) =
    "shanten=" ++ string.int_to_string(Sh) ++
    " tiles=" ++ format_tile_kinds(Tiles) ++
    " count=" ++ string.int_to_string(Count).
