:- module scoring.
:- interface.

:- import_module list, tiles.

:- type score_result
    ---> not_agari
    ;    no_yaku
    ;    scored(string, int, int, int, string, int).
    % yaku, yakuman multiplier, han, fu, payment, total

:- func score(list(tile), list(meld), tile, method, context) = score_result.
:- pred can_win(list(tile)::in, list(meld)::in, tile::in, method::in,
    context::in) is semidet.
:- func render_score(score_result) = string.

:- implementation.
:- import_module bag, int, pair, shape, solutions, string.

:- type wait ---> single ; dual_pon ; inside ; edge ; two_sided ; special.
:- type reading ---> reading(form, wait, kind, list(group)).
    % The pair kind is -1 for special forms.
:- type facts ---> facts(
    form :: form,
    hand_exposure :: exposure,
    wait :: wait,
    head :: kind,
    groups :: list(group),
    all_tiles :: list(kind),
    runs :: list(kind),
    pungs :: list(kind),
    concealed_pungs :: int,
    kans :: int,
    dragons :: int,
    winds :: int,
    numbered_suits :: list(int)
).

score(Hand, Melds, Win, By, C) = Result :-
    Tiles = [Win | Hand] ++ list.condense(list.map(meld_tiles, Melds)),
    Ks = kinds([Win | Hand]),
    Forms = forms(Ks, list.length(Melds)),
    ( if Forms = [] then Result = not_agari
      else
        solutions(candidate(Forms, Ks, Melds, kind_of(Win), By, C, Tiles), Scores),
        ( if Scores = [First | Rest] then Result = list.foldl(prefer, Rest, First)
          else Result = no_yaku
        )
    ).

can_win(Hand, Melds, Win, By, C) :-
    Ks = kinds([Win | Hand]),
    Fs = forms(Ks, list.length(Melds)),
    All = kinds([Win | Hand] ++ list.condense(list.map(meld_tiles, Melds))),
    promise_equivalent_solutions [] (
        list.member(Form, Fs),
        interpret(Form, Melds, kind_of(Win), By, Reading),
        F = facts_for(Reading, Melds, All),
        ( if natural(F, Ks, kind_of(Win), C, _, _) then true
          else ordinary(F, By, C, _, _)
        )
    ).

:- pred candidate(list(form)::in, list(kind)::in, list(meld)::in,
    kind::in, method::in, context::in, list(tile)::in, score_result::out)
    is nondet.
candidate(Forms, Ks, Melds, Win, By, C, Tiles, Result) :-
    list.member(Form, Forms),
    ( if has_flag(C, "tenhou") then list.member(K, list.sort_and_remove_dups(Ks))
      else K = Win
    ),
    interpret(Form, Melds, K, By, Reading),
    F = facts_for(Reading, Melds, kinds(Tiles)),
    solutions((pred(Y::out) is nondet :- natural(F, Ks, K, C, Name, Value),
        Y = Name - Value), Yakuman),
    ( if Yakuman = [_ | _] then
        Mult = yaku_sum(Yakuman),
        payment(8000 * Mult, By, C, Pay, Total),
        Result = scored(yaku_string(Yakuman), Mult, 0, 0, Pay, Total)
      else
        solutions((pred(Y::out) is nondet :- ordinary(F, By, C, Name, Value),
            Y = Name - Value), Regular),
        Regular = [_ | _],
        Yaku = list.sort(Regular ++ bonuses(Tiles, C)),
        Han = yaku_sum(Yaku),
        Fu = fu(F, By, C),
        payment(basic(Han, Fu), By, C, Pay, Total),
        Result = scored(yaku_string(Yaku), 0, Han, Fu, Pay, Total)
    ).

:- pred interpret(form::in, list(meld)::in, kind::in, method::in,
    reading::out) is nondet.
interpret(chiitoi, _, _, _, reading(chiitoi, special, -1, [])).
interpret(kokushi, _, _, _, reading(kokushi, special, -1, [])).
interpret(Form @ standard(Groups), Melds, Win, By, Reading) :-
    list.delete(Groups, Winner, Rest),
    list.member(Win, group_kinds(Winner)),
    Winner = group(K, Role, _),
    ( Role = pair, W = single
    ; Role = triplet, W = dual_pon
    ; Role = sequence,
        ( if Win = K + 1 then W = inside
          else if (rank(K) = 1, Win = K + 2 ; rank(K) = 7, Win = K)
            then W = edge
          else W = two_sided
        )
    ),
    ( if W = dual_pon, By = ron then Group = group(K, Role, exposed)
      else Group = Winner
    ),
    All = [Group | Rest] ++ list.map(meld_group, Melds),
    list.find_first_match((pred(G::in) is semidet :- G = group(_, pair, _)),
        All, group(Head, _, _)),
    Reading = reading(Form, W, Head, All).

:- func facts_for(reading, list(meld), list(kind)) = facts.
facts_for(reading(Form, W, Head, Groups), Melds, Ks) =
    facts(Form, Exposure, W, Head, Groups, Ks, Runs, Pungs, Concealed, Kans,
        Dragons, Winds, Suits) :-
    Exposure = (if closed(Melds) then concealed else exposed),
    list.filter_map((pred(group(K, R, _)::in, X::out) is semidet :-
        R = sequence, X = K), Groups, Runs),
    list.filter_map((pred(group(K, R, _)::in, X::out) is semidet :-
        pung(R), X = K), Groups, Pungs),
    Concealed = list.length(list.filter(
        (pred(group(_, R, E)::in) is semidet :- E = concealed, pung(R)), Groups)),
    Kans = list.length(list.filter(
        (pred(group(_, R, _)::in) is semidet :- R = quad), Groups)),
    Dragons = list.length(list.filter(is_dragon, Pungs)),
    Winds = list.length(list.filter(is_wind, Pungs)),
    Suits = list.sort_and_remove_dups(list.map(suit, list.filter(
        (pred(K::in) is semidet :- K < 27), Ks))).

:- pred pung(role::in) is semidet.
pung(triplet).
pung(quad).

:- pred is_dragon(kind::in) is semidet.
is_dragon(K) :- K >= 31.

:- pred is_wind(kind::in) is semidet.
is_wind(K) :- K >= 27, K =< 30.

:- pred has_honors(facts::in) is semidet.
has_honors(F) :- list.find_first_match(honor, F ^ all_tiles, _).

:- pred natural(facts::in, list(kind)::in, kind::in, context::in,
    string::out, int::out) is nondet.
natural(F, Ks, Win, _, Name, Mult) :-
    F ^ form = kokushi,
    ( if remove_kind(Win, Ks, orphan_kinds) then Name = "kokushi_13", Mult = 2
      else Name = "kokushi", Mult = 1
    ).
natural(F, _, _, _, Name, Mult) :-
    F ^ concealed_pungs = 4,
    ( if F ^ wait = single then Name = "suuankou_tanki", Mult = 2
      else Name = "suuankou", Mult = 1
    ).
natural(F, _, _, _, "daisangen", 1) :- F ^ dragons = 3.
natural(F, _, _, _, "shousuushii", 1) :- F ^ winds = 3, is_wind(F ^ head).
natural(F, _, _, _, "daisuushii", 2) :- F ^ winds = 4.
natural(F, _, _, _, "tsuuiisou", 1) :- list.all_true(honor, F ^ all_tiles).
natural(F, _, _, _, "chinroutou", 1) :- list.all_true(terminal, F ^ all_tiles).
natural(F, _, _, _, "ryuuiisou", 1) :-
    list.all_true((pred(K::in) is semidet :-
        list.member(K, [19, 20, 21, 23, 25, 32])), F ^ all_tiles).
natural(F, Ks, Win, _, Name, Mult) :-
    F ^ numbered_suits = [S],
    Base = S * 9,
    Gates = [Base, Base, Base] ++ (Base + 1 .. Base + 7) ++
        [Base + 8, Base + 8, Base + 8],
    list.length(Ks) = 14,
    contains_sorted(Ks, Gates),
    ( if remove_kind(Win, Ks, Gates) then Name = "junsei_chuuren", Mult = 2
      else Name = "chuuren", Mult = 1
    ).
natural(F, _, _, _, "suukantsu", 1) :- F ^ kans = 4.
natural(_, _, _, C, "tenhou", 1) :- has_flag(C, "tenhou").
natural(_, _, _, C, "chiihou", 1) :- has_flag(C, "chiihou").

:- pred contains_sorted(list(kind)::in, list(kind)::in) is semidet.
contains_sorted(Ks, Needed) :-
    ( Needed = []
    ; Needed = [N | Ns], remove_kind(N, Ks, Rest), contains_sorted(Rest, Ns)
    ).

:- pred ordinary(facts::in, method::in, context::in, string::out, int::out)
    is nondet.
ordinary(F, _, C, "riichi", 1) :-
    F ^ hand_exposure = concealed, has_flag(C, "riichi"), not has_flag(C, "double_riichi").
ordinary(F, _, C, "double_riichi", 2) :-
    F ^ hand_exposure = concealed, has_flag(C, "double_riichi").
ordinary(F, _, C, "ippatsu", 1) :- F ^ hand_exposure = concealed, has_flag(C, "ippatsu").
ordinary(F, tsumo, _, "tsumo", 1) :- F ^ hand_exposure = concealed.
ordinary(F, _, C, "pinfu", 1) :- pinfu(F, C).
ordinary(F, _, _, "tanyao", 1) :-
    list.all_true((pred(K::in) is semidet :- not outside(K)), F ^ all_tiles).
ordinary(F, _, _, Name, Value) :-
    F ^ hand_exposure = concealed,
    Doubles = sequence_pairs(list.sort(F ^ runs)),
    ( Doubles = 1, Name = "iipeikou", Value = 1
    ; Doubles = 2, Name = "ryanpeikou", Value = 3
    ).
ordinary(F, _, _, "yakuhai_haku", 1) :- list.member(31, F ^ pungs).
ordinary(F, _, _, "yakuhai_hatsu", 1) :- list.member(32, F ^ pungs).
ordinary(F, _, _, "yakuhai_chun", 1) :- list.member(33, F ^ pungs).
ordinary(F, _, C, "yakuhai_seat", 1) :- list.member(C ^ seat, F ^ pungs).
ordinary(F, _, C, "yakuhai_round", 1) :- list.member(C ^ round_wind, F ^ pungs).
ordinary(_, tsumo, C, "haitei", 1) :- has_flag(C, "haitei").
ordinary(_, ron, C, "houtei", 1) :- has_flag(C, "houtei").
ordinary(_, tsumo, C, "rinshan", 1) :- has_flag(C, "rinshan").
ordinary(_, ron, C, "chankan", 1) :- has_flag(C, "chankan").
ordinary(F, _, _, "chiitoi", 2) :- F ^ form = chiitoi.
ordinary(F, _, _, "toitoi", 2) :- list.length(F ^ pungs) = 4.
ordinary(F, _, _, "sanankou", 2) :- F ^ concealed_pungs = 3.
ordinary(F, _, _, "sanshoku", Han) :-
    mixed_triple(F ^ runs), Han = open_reduction(F, 2).
ordinary(F, _, _, "sanshoku_doukou", 2) :- mixed_triple(F ^ pungs).
ordinary(F, _, _, "ittsu", Han) :-
    list.find_first_match((pred(K::in) is semidet :-
        rank(K) = 1, list.member(K + 3, F ^ runs), list.member(K + 6, F ^ runs)),
        F ^ runs, _),
    Han = open_reduction(F, 2).
ordinary(F, _, _, Name, Han) :-
    F ^ runs = [_ | _],
    list.all_true((pred(G::in) is semidet :-
        list.find_first_match(outside, group_kinds(G), _)), F ^ groups),
    ( if has_honors(F) then Name = "chanta", Han = open_reduction(F, 2)
      else Name = "junchan", Han = open_reduction(F, 3)
    ).
ordinary(F, _, _, "honroutou", 2) :- list.all_true(outside, F ^ all_tiles).
ordinary(F, _, _, "shousangen", 2) :- F ^ dragons = 2, is_dragon(F ^ head).
ordinary(F, _, _, "sankantsu", 2) :- F ^ kans = 3.
ordinary(F, _, _, Name, Han) :-
    F ^ numbered_suits = [_],
    ( if has_honors(F) then Name = "honitsu", Han = open_reduction(F, 3)
      else Name = "chinitsu", Han = open_reduction(F, 6)
    ).

:- func open_reduction(facts, int) = int.
open_reduction(F, Closed) = (if F ^ hand_exposure = concealed then Closed else Closed - 1).

:- pred mixed_triple(list(kind)::in) is semidet.
mixed_triple(Ks) :-
    list.find_first_match((pred(K::in) is semidet :-
        K < 9, list.member(K + 9, Ks), list.member(K + 18, Ks)), Ks, _).

:- func sequence_pairs(list(kind)) = int.
sequence_pairs([]) = 0.
sequence_pairs([K | Ks]) =
    (if Ks = [K | Rest] then 1 + sequence_pairs(Rest) else sequence_pairs(Ks)).

:- pred pinfu(facts::in, context::in) is semidet.
pinfu(F, C) :-
    F ^ wait = two_sided, list.length(F ^ runs) = 4,
    F ^ hand_exposure = concealed, pair_fu(F ^ head, C) = 0.

:- func pair_fu(kind, context) = int.
pair_fu(K, C) =
    (if is_dragon(K) then 2 else
        (if K = C ^ seat then 2 else 0) + (if K = C ^ round_wind then 2 else 0)).

:- func fu(facts, method, context) = int.
fu(F, By, C) = Fu :-
    ( if F ^ form = chiitoi then Fu = 25
      else if By = tsumo, pinfu(F, C) then Fu = 20
      else
        Base = (if By = tsumo then 22 else if F ^ hand_exposure = concealed then 30 else 20),
        Wait = F ^ wait,
        WaitFu = (if (Wait = single ; Wait = inside ; Wait = edge) then 2 else 0),
        Raw = list.foldl((func(G, Sum) = Sum + group_fu(G)), F ^ groups,
            Base + pair_fu(F ^ head, C) + WaitFu),
        Fu = int.max(30, round_up(Raw, 10))
    ).

:- func group_fu(group) = int.
group_fu(group(K, R, E)) = N :-
    ( if pung(R) then
        N = (if R = quad then 8 else 2) *
            (if E = concealed then 2 else 1) *
            (if outside(K) then 2 else 1)
      else N = 0
    ).

:- func bonuses(list(tile), context) = list(pair(string, int)).
bonuses(Ts, C) = list.filter((pred(Y::in) is semidet :- Y = _ - N, N > 0),
    ["aka" - Aka, "dora" - Dora, "ura" - Ura]) :-
    Bag = bag.from_list(kinds(Ts)),
    Count = (func(I, Sum) = Sum + bag.count_value(Bag, successor(I))),
    Aka = list.length(list.filter((pred(T::in) is semidet :- T = tile(_, red)), Ts)),
    Dora = list.foldl(Count, C ^ indicators, 0),
    Ura = (if (has_flag(C, "riichi") ; has_flag(C, "double_riichi"))
        then list.foldl(Count, C ^ hidden_indicators, 0) else 0).

:- func yaku_sum(list(pair(string, int))) = int.
yaku_sum(Ys) = list.foldl((func(_ - Han, Sum) = Sum + Han), Ys, 0).

:- func yaku_string(list(pair(string, int))) = string.
yaku_string(Ys) = string.join_list(",", list.map(
    (func(Name - N) = Name ++ ":" ++ int_to_string(N)), Ys)).

:- func basic(int, int) = int.
basic(Han, Fu) =
    ( if Han >= 13 then 8000
      else if Han >= 11 then 6000
      else if Han >= 8 then 4000
      else if Han >= 6 then 3000
      else int.min(2000, Fu * (1 << (Han + 2)))
    ).

:- func round_up(int, int) = int.
round_up(N, Unit) = ((N + Unit - 1) // Unit) * Unit.

:- pred payment(int::in, method::in, context::in, string::out, int::out) is det.
payment(Base, By, C, Pay, Total) :-
    Extra = C ^ honba * 100,
    DealerShare = round_up(2 * Base, 100) + Extra,
    ( By = ron,
        Factor = (if C ^ seat = 27 then 6 else 4),
        Total = round_up(Factor * Base, 100) + 3 * Extra,
        Pay = "ron:" ++ int_to_string(Total)
    ; By = tsumo,
        ( if C ^ seat = 27 then
            Total = 3 * DealerShare, Pay = "all:" ++ int_to_string(DealerShare)
          else
            Share = round_up(Base, 100) + Extra,
            Total = 2 * Share + DealerShare,
            Pay = "tsumo:" ++ int_to_string(Share) ++ "/" ++ int_to_string(DealerShare)
        )
    ).

:- func prefer(score_result, score_result) = score_result.
prefer(A, B) =
    (if ranking(A) @< ranking(B) then A else B).

:- func ranking(score_result) = {int, int, int, int, string}.
ranking(scored(Ys, Mult, Han, Fu, _, Total)) =
    {-Total, (if Mult > 0 then -1 else 0), -Han, -Fu, Ys}.
ranking(not_agari) = {0, 0, 0, 0, ""}.
ranking(no_yaku) = {0, 0, 0, 0, ""}.

render_score(not_agari) = "error=not_agari".
render_score(no_yaku) = "error=no_yaku".
render_score(scored(Ys, Mult, Han, Fu, Pay, Total)) =
    "yaku=" ++ Ys ++
    (if Mult > 0 then " yakuman=" ++ int_to_string(Mult)
      else " han=" ++ int_to_string(Han) ++ " fu=" ++ int_to_string(Fu)) ++
    " pay=" ++ Pay ++ " total=" ++ int_to_string(Total).
