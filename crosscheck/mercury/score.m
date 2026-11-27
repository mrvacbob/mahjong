%---------------------------------------------------------------------------%
% score.m: interpretations of a winning hand, yaku, fu and payment.
%---------------------------------------------------------------------------%
:- module score.
:- interface.

:- import_module tile.
:- import_module list.
:- import_module pair.

:- type flag
    --->    riichi
    ;       double_riichi
    ;       ippatsu
    ;       haitei
    ;       houtei
    ;       rinshan
    ;       chankan
    ;       tenhou
    ;       chiihou
    ;       ankan_rob.

:- pred parse_flag(string::in, flag::out) is semidet.

:- type win_by
    --->    tsumo
    ;       ron.

:- type situation
    --->    situation(
                seat        :: kind,
                round       :: kind,
                dora        :: list(tile),      % indicators
                ura         :: list(tile),      % indicators
                honba       :: int,
                flags       :: list(flag)
            ).

:- type score_request
    --->    score_request(
                hand        :: list(tile),      % excluding the winning tile
                melds       :: list(meld),
                win         :: tile,
                by          :: win_by,
                sit         :: situation
            ).

:- type value
    --->    ordinary(han :: int, fu :: int)
    ;       yakuman(multiple :: int).

:- type payment
    --->    ron_pay(int)                    % the discarder pays
    ;       dealer_tsumo(int)               % each other seat pays
    ;       child_tsumo(child :: int, dealer :: int).

:- type result
    --->    result(
                yaku        :: list(pair(string, int)),
                value       :: value,
                pay         :: payment
            ).

:- func total(result) = int.

:- type outcome
    --->    not_agari
    ;       no_yaku
    ;       scored(result).

:- func evaluate(score_request) = outcome.
:- func outcome_to_string(outcome) = string.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module hand.
:- import_module bag.
:- import_module bool.
:- import_module int.
:- import_module solutions.
:- import_module string.

parse_flag("riichi", riichi).
parse_flag("double_riichi", double_riichi).
parse_flag("ippatsu", ippatsu).
parse_flag("haitei", haitei).
parse_flag("houtei", houtei).
parse_flag("rinshan", rinshan).
parse_flag("chankan", chankan).
parse_flag("tenhou", tenhou).
parse_flag("chiihou", chiihou).
parse_flag("ankan_rob", ankan_rob).

%---------------------------------------------------------------------------%
% Interpretations

:- type shape
    --->    run
    ;       triplet
    ;       kan.

:- type concealment
    --->    concealed
    ;       open.

:- type mentsu
    --->    mentsu(shape :: shape, mkind :: kind, conc :: concealment).

:- type wait
    --->    ryanmen
    ;       kanchan
    ;       penchan
    ;       tanki
    ;       shanpon.

:- type interp
    --->    standard(pair :: kind, mentsu :: list(mentsu), wait :: wait)
    ;       chiitoi
    ;       kokushi(kokushi_pair :: kind).

    % Everything about the hand that does not depend on how it is read.
:- type ctx
    --->    ctx(
                req         :: score_request,
                concealed   :: bag(kind),       % with the winning tile
                win_kind    :: kind,
                closed      :: bool,
                meld_mentsu :: list(mentsu),
                tiles       :: list(tile),      % every tile, melds included
                kinds       :: list(kind)       % their kinds
            ).

:- pred interpretation(ctx::in, interp::out) is nondet.
interpretation(C, standard(P, Ms ++ C ^ meld_mentsu, Wait)) :-
    standard_form(C ^ concealed, P, Groups),
    (
        P = C ^ win_kind,
        Wait = tanki,
        Ms = list.map(concealed_mentsu, Groups)
    ;
        list.delete(Groups, G, Others),
        completed_by_win(C, G, Wait, M),
        Ms = [M | list.map(concealed_mentsu, Others)]
    ).
interpretation(C, chiitoi) :-
    C ^ req ^ melds = [],
    is_chiitoi(C ^ concealed).
interpretation(C, kokushi(P)) :-
    C ^ req ^ melds = [],
    is_kokushi(C ^ concealed, P).

    % The winning tile went into this group: which wait was it?
    % A triplet completed by ron counts as open.
:- pred completed_by_win(ctx::in, group::in, wait::out, mentsu::out)
    is semidet.
completed_by_win(C, run(K), Wait, mentsu(run, K, concealed)) :-
    W = C ^ win_kind,
    K = kind(S, N),
    W = kind(S, WN),
    D = WN - N,
    ( D = 1, Wait = kanchan
    ; D = 0, Wait = ( if N = 7 then penchan else ryanmen )
    ; D = 2, Wait = ( if N = 1 then penchan else ryanmen )
    ).
completed_by_win(C, triplet(K), shanpon, mentsu(triplet, K, Conc)) :-
    K = C ^ win_kind,
    Conc = ( if C ^ req ^ by = ron then open else concealed ).

:- func concealed_mentsu(group) = mentsu.
concealed_mentsu(run(K)) = mentsu(run, K, concealed).
concealed_mentsu(triplet(K)) = mentsu(triplet, K, concealed).

:- func mentsu_of_meld(meld) = mentsu.
mentsu_of_meld(M) = mentsu(meld_shape(M ^ mkind), K, Conc) :-
    K = list.det_head(meld_kinds(M)),      % meld tiles are sorted
    Conc = ( if is_open_meld(M) then open else concealed ).

:- func meld_shape(meld_kind) = shape.
meld_shape(chi) = run.
meld_shape(pon) = triplet.
meld_shape(daiminkan) = kan.
meld_shape(shouminkan) = kan.
meld_shape(ankan) = kan.

%---------------------------------------------------------------------------%
% Queries used by the yaku clauses

:- pred has_flag(ctx::in, flag::in) is semidet.
has_flag(C, F) :-
    list.member(F, C ^ req ^ sit ^ flags).

:- func closed_open(ctx, int, int) = int.
closed_open(C, Closed, Open) = ( if C ^ closed = yes then Closed else Open ).

:- pred all_kinds_are(ctx::in, pred(kind)::in(pred(in) is semidet))
    is semidet.
all_kinds_are(C, P) :-
    list.all_true(P, C ^ kinds).

:- pred has_honor(ctx::in) is semidet.
has_honor(C) :-
    list.any_true(is_honor, C ^ kinds).

:- func mentsu_of(interp) = list(mentsu).
mentsu_of(I) = ( if I = standard(_, Ms, _) then Ms else [] ).

:- pred is_triplet_like(mentsu::in) is semidet.
is_triplet_like(mentsu(S, _, _)) :- ( S = triplet ; S = kan ).

    % The kinds of the triplets and kans.
:- func triplet_kinds(interp) = list(kind).
triplet_kinds(I) = list.filter_map(
    (func(M) = M ^ mkind is semidet :- is_triplet_like(M)), mentsu_of(I)).

:- pred has_triplet(interp::in, kind::in) is semidet.
has_triplet(I, K) :-
    list.member(K, triplet_kinds(I)).

:- func count_mentsu(interp, pred(mentsu)) = int.
:- mode count_mentsu(in, in(pred(in) is semidet)) = out is det.
count_mentsu(I, P) = list.length(list.filter(P, mentsu_of(I))).

:- func concealed_triplets(interp) = int.
concealed_triplets(I) = count_mentsu(I,
    (pred(M::in) is semidet :- is_triplet_like(M), M ^ conc = concealed)).

:- func kans(interp) = int.
kans(I) = count_mentsu(I, (pred(M::in) is semidet :- M ^ shape = kan)).

:- func triplets_where(interp, pred(kind)) = int.
:- mode triplets_where(in, in(pred(in) is semidet)) = out is det.
triplets_where(I, P) = list.length(list.filter(P, triplet_kinds(I))).

:- func runs(interp) = list(kind).
runs(I) = list.filter_map(
    (func(mentsu(run, K, _)) = K is semidet), mentsu_of(I)).

    % Pairs of identical runs (closed hands only ask).
:- func peikou(interp) = int.
peikou(I) = list.foldl(
    (func(_ - N, Acc) = Acc + N // 2),
    bag.to_assoc_list(bag.from_list(runs(I))), 0).

:- pred same_number_in_three_suits(list(kind)::in) is semidet.
same_number_in_three_suits(Ks) :-
    list.member(kind(man, N), Ks),
    list.member(kind(pin, N), Ks),
    list.member(kind(sou, N), Ks).

    % Every group, pair included, contains a terminal or honor.
:- pred all_groups_outside(interp::in) is semidet.
all_groups_outside(standard(P, Ms, _)) :-
    is_yaochu(P),
    list.all_true(
        (pred(mentsu(S, K, _)::in) is semidet :-
            ( if S = run then
                ( K ^ num = 1 ; K ^ num = 7 )
            else
                is_yaochu(K)
            )),
        Ms).

:- pred one_number_suit(ctx::in, suit::out) is semidet.
one_number_suit(C, S) :-
    list.filter(is_number, C ^ kinds, Numbers),
    Numbers = [kind(S, _) | _],
    list.all_true((pred(kind(S1, _)::in) is semidet :- S1 = S), Numbers).

:- pred pinfu(ctx::in, interp::in) is semidet.
pinfu(C, standard(P, Ms, ryanmen)) :-
    C ^ closed = yes,
    list.all_true((pred(M::in) is semidet :- M ^ shape = run), Ms),
    pair_fu(C, P) = 0.         % the pair is not a value tile

:- pred is_green(kind::in) is semidet.
is_green(kind(sou, N)) :- ( N = 2 ; N = 3 ; N = 4 ; N = 6 ; N = 8 ).
is_green(kind(honor, 6)).

%---------------------------------------------------------------------------%
% Yaku.  One clause per yaku, in the order of spec/rules.md section 2.1.

:- pred yaku(ctx::in, interp::in, string::out, int::out) is nondet.
yaku(C, _, "riichi", 1) :-
    has_flag(C, riichi).
yaku(C, _, "ippatsu", 1) :-
    has_flag(C, ippatsu).
yaku(C, _, "tsumo", 1) :-
    C ^ closed = yes,
    C ^ req ^ by = tsumo.
yaku(C, I, "pinfu", 1) :-
    pinfu(C, I).
yaku(C, _, "tanyao", 1) :-
    all_kinds_are(C, is_simple).
yaku(C, I, "iipeikou", 1) :-
    C ^ closed = yes,
    peikou(I) = 1.
yaku(_, I, "yakuhai_haku", 1) :-
    has_triplet(I, kind(honor, 5)).
yaku(_, I, "yakuhai_hatsu", 1) :-
    has_triplet(I, kind(honor, 6)).
yaku(_, I, "yakuhai_chun", 1) :-
    has_triplet(I, kind(honor, 7)).
yaku(C, I, "yakuhai_seat", 1) :-
    has_triplet(I, C ^ req ^ sit ^ seat).
yaku(C, I, "yakuhai_round", 1) :-
    has_triplet(I, C ^ req ^ sit ^ round).
yaku(C, _, "rinshan", 1) :-
    has_flag(C, rinshan).
yaku(C, _, "chankan", 1) :-
    has_flag(C, chankan).
yaku(C, _, "haitei", 1) :-
    has_flag(C, haitei).
yaku(C, _, "houtei", 1) :-
    has_flag(C, houtei).
yaku(C, _, "double_riichi", 2) :-
    has_flag(C, double_riichi).
yaku(C, I, "sanshoku", closed_open(C, 2, 1)) :-
    same_number_in_three_suits(runs(I)).
yaku(_, I, "sanshoku_doukou", 2) :-
    same_number_in_three_suits(triplet_kinds(I)).
yaku(_, I, "sanankou", 2) :-
    concealed_triplets(I) = 3.
yaku(C, I, "ittsu", closed_open(C, 2, 1)) :-
    Runs = runs(I),
    list.member(kind(S, 1), Runs),
    list.member(kind(S, 4), Runs),
    list.member(kind(S, 7), Runs).
yaku(_, chiitoi, "chiitoi", 2).
yaku(_, I, "toitoi", 2) :-
    I = standard(_, Ms, _),
    list.all_true(is_triplet_like, Ms).
yaku(C, I, "chanta", closed_open(C, 2, 1)) :-
    all_groups_outside(I),
    runs(I) \= [],
    has_honor(C).
yaku(_, I, "sankantsu", 2) :-
    kans(I) = 3.
yaku(C, _, "honroutou", 2) :-
    all_kinds_are(C, is_yaochu).
yaku(_, I, "shousangen", 2) :-
    triplets_where(I, is_dragon) = 2,
    is_dragon(I ^ pair).
yaku(C, _, "honitsu", closed_open(C, 3, 2)) :-
    one_number_suit(C, _),
    has_honor(C).
yaku(C, I, "junchan", closed_open(C, 3, 2)) :-
    all_groups_outside(I),
    runs(I) \= [],
    not has_honor(C).
yaku(C, I, "ryanpeikou", 3) :-
    C ^ closed = yes,
    peikou(I) = 2.
yaku(C, _, "chinitsu", closed_open(C, 6, 5)) :-
    one_number_suit(C, _),
    not has_honor(C).

%---------------------------------------------------------------------------%
% Yakuman, with the multiple each contributes (spec/rules.md section 2.2).

:- pred yakuman(ctx::in, interp::in, string::out, int::out) is nondet.
yakuman(C, _, "tenhou", 1) :-
    has_flag(C, tenhou).
yakuman(C, _, "chiihou", 1) :-
    has_flag(C, chiihou).
yakuman(C, kokushi(P), Name, Mult) :-
    ( if P = C ^ win_kind then
        Name = "kokushi_13", Mult = 2
    else
        Name = "kokushi", Mult = 1
    ).
yakuman(_, I, Name, Mult) :-
    concealed_triplets(I) = 4,
    ( if I ^ wait = tanki then
        Name = "suuankou_tanki", Mult = 2
    else
        Name = "suuankou", Mult = 1
    ).
yakuman(_, I, "daisangen", 1) :-
    triplets_where(I, is_dragon) = 3.
yakuman(_, I, "shousuushii", 1) :-
    triplets_where(I, is_wind) = 3,
    is_wind(I ^ pair).
yakuman(_, I, "daisuushii", 2) :-
    triplets_where(I, is_wind) = 4.
yakuman(C, _, "tsuuiisou", 1) :-
    all_kinds_are(C, is_honor).
yakuman(C, _, "chinroutou", 1) :-
    all_kinds_are(C, is_terminal).
yakuman(C, _, "ryuuiisou", 1) :-
    all_kinds_are(C, is_green).
yakuman(C, _, Name, Mult) :-
    C ^ req ^ melds = [],
    one_number_suit(C, S),
    not has_honor(C),
    Counts = suit_counts(C ^ concealed, S),
    list.all_true_corresponding((pred(Have::in, Need::in) is semidet :-
        Have >= Need), Counts, chuuren),
    Without = bag.det_remove(C ^ concealed, C ^ win_kind),
    ( if
        suit_counts(Without, S) = chuuren
    then
        Name = "junsei_chuuren", Mult = 2
    else
        Name = "chuuren", Mult = 1
    ).
yakuman(_, I, "suukantsu", 1) :-
    kans(I) = 4.

:- func chuuren = list(int).
chuuren = [3, 1, 1, 1, 1, 1, 1, 1, 3].

%---------------------------------------------------------------------------%
% Fu

:- func fu(ctx, interp) = int.
fu(C, I) = Fu :-
    (
        I = chiitoi,
        Fu = 25
    ;
        I = kokushi(_),
        Fu = 30         % never printed: kokushi is a yakuman
    ;
        I = standard(P, Ms, Wait),
        By = C ^ req ^ by,
        ( if pinfu(C, I), By = tsumo then
            Fu = 20
        else
            MenzenRon = ( if C ^ closed = yes, By = ron then 10 else 0 ),
            TsumoFu = ( if By = tsumo then 2 else 0 ),
            Raw = 20 + MenzenRon + TsumoFu
                + list.foldl((func(M, A) = A + mentsu_fu(M)), Ms, 0)
                + pair_fu(C, P) + wait_fu(Wait),
            Rounded = (Raw + 9) // 10 * 10,
            ( if C ^ closed = no, Rounded = 20 then
                Fu = 30
            else
                Fu = Rounded
            )
        )
    ).

:- func mentsu_fu(mentsu) = int.
mentsu_fu(mentsu(run, _, _)) = 0.
mentsu_fu(mentsu(triplet, K, Conc)) = yaochu_double(K, conc_double(Conc, 2)).
mentsu_fu(mentsu(kan, K, Conc)) = yaochu_double(K, conc_double(Conc, 8)).

:- func conc_double(concealment, int) = int.
conc_double(concealed, F) = 2 * F.
conc_double(open, F) = F.

:- func yaochu_double(kind, int) = int.
yaochu_double(K, F) = ( if is_yaochu(K) then 2 * F else F ).

:- func pair_fu(ctx, kind) = int.
pair_fu(C, K) =
    ( if is_dragon(K) then 2 else 0 ) +
    ( if K = C ^ req ^ sit ^ seat then 2 else 0 ) +
    ( if K = C ^ req ^ sit ^ round then 2 else 0 ).

:- func wait_fu(wait) = int.
wait_fu(ryanmen) = 0.
wait_fu(shanpon) = 0.
wait_fu(kanchan) = 2.
wait_fu(penchan) = 2.
wait_fu(tanki) = 2.

%---------------------------------------------------------------------------%
% Scoring one interpretation

:- func score_interp(ctx, interp) = outcome.
score_interp(C, I) = Outcome :-
    Yakuman = solutions(
        (pred(N - M::out) is nondet :- yakuman(C, I, N, M))),
    ( if Yakuman = [_ | _] then
        Mult = sum_values(Yakuman),
        Outcome = scored(paid(C, Yakuman, yakuman(Mult), 8000 * Mult))
    else
        Yaku = solutions((pred(N - H::out) is nondet :- yaku(C, I, N, H))),
        (
            Yaku = [],
            Outcome = no_yaku
        ;
            Yaku = [_ | _],
            All = list.sort(Yaku ++ dora_yaku(C)),
            Han = sum_values(All),
            Fu = fu(C, I),
            Outcome = scored(paid(C, All, ordinary(Han, Fu),
                basic_points(Han, Fu)))
        )
    ).

:- func sum_values(list(pair(string, int))) = int.
sum_values(Ps) = list.foldl((func(_ - N, A) = A + N), Ps, 0).

:- func dora_yaku(ctx) = list(pair(string, int)).
dora_yaku(C) = list.filter((pred(_ - N::in) is semidet :- N > 0),
        ["dora" - Dora, "aka" - Aka, "ura" - Ura]) :-
    Sit = C ^ req ^ sit,
    Kinds = bag.from_list(C ^ kinds),
    Dora = count_dora(Kinds, Sit ^ dora),
    ( if ( has_flag(C, riichi) ; has_flag(C, double_riichi) ) then
        Ura = count_dora(Kinds, Sit ^ ura)
    else
        Ura = 0
    ),
    Aka = list.length(list.filter((pred(T::in) is semidet :-
        T ^ colour = red), C ^ tiles)).

:- func count_dora(bag(kind), list(tile)) = int.
count_dora(Kinds, Indicators) = list.foldl(
    (func(Ind, Acc) = Acc + bag.count_value(Kinds, dora_of(kind_of(Ind)))),
    Indicators, 0).

:- func basic_points(int, int) = int.
basic_points(Han, Fu) =
    ( if Han >= 13 then 8000
    else if Han >= 11 then 6000
    else if Han >= 8 then 4000
    else if Han >= 6 then 3000
    else if Han >= 5 then 2000
    else int.min(2000, Fu * int.pow(2, 2 + Han))
    ).

:- func paid(ctx, list(pair(string, int)), value, int) = result.
paid(C, Yaku, Value, Basic) = result(Yaku, Value, Pay) :-
    Req = C ^ req,
    Honba = Req ^ sit ^ honba,
    Dealer = ( if Req ^ sit ^ seat = east then yes else no ),
    (
        Req ^ by = ron,
        Pay = ron_pay(ceil100(Basic * ( if Dealer = yes then 6 else 4 ))
            + 300 * Honba)
    ;
        Req ^ by = tsumo,
        (
            Dealer = yes,
            Pay = dealer_tsumo(ceil100(2 * Basic) + 100 * Honba)
        ;
            Dealer = no,
            Pay = child_tsumo(ceil100(Basic) + 100 * Honba,
                ceil100(2 * Basic) + 100 * Honba)
        )
    ).

total(R) = Total :-
    ( R ^ pay = ron_pay(Total)
    ; R ^ pay = dealer_tsumo(Each), Total = 3 * Each
    ; R ^ pay = child_tsumo(Child, Dealer), Total = 2 * Child + Dealer
    ).

:- func payment_to_string(payment) = string.
payment_to_string(ron_pay(N)) = "ron:" ++ int_to_string(N).
payment_to_string(dealer_tsumo(N)) = "all:" ++ int_to_string(N).
payment_to_string(child_tsumo(Child, Dealer)) =
    "tsumo:" ++ int_to_string(Child) ++ "/" ++ int_to_string(Dealer).

:- func ceil100(int) = int.
ceil100(N) = (N + 99) // 100 * 100.

%---------------------------------------------------------------------------%
% Choosing the best interpretation

evaluate(Req) = Outcome :-
    Hand = [Req ^ win | Req ^ hand],
    Concealed = kind_bag(Hand),
    Melds = Req ^ melds,
    Closed = ( if all_closed(Melds) then yes else no ),
    MeldMentsu = list.map(mentsu_of_meld, Melds),
    Tiles = Hand ++ meld_tiles(Melds),
    ( if list.member(tenhou, Req ^ sit ^ flags) then
        WinKinds = bag.to_list_without_duplicates(Concealed)
    else
        WinKinds = [kind_of(Req ^ win)]
    ),
    % Identical groups give the same reading more than once: collect the
    % distinct readings before scoring them.
    Readings = solutions(
        (pred({C, I}::out) is nondet :-
            list.member(W, WinKinds),
            C = ctx(Req, Concealed, W, Closed, MeldMentsu, Tiles,
                kinds_of(Tiles)),
            interpretation(C, I))),
    Scored = list.filter_map(
        (func({C, I}) = R is semidet :- score_interp(C, I) = scored(R)),
        Readings),
    ( if Readings = [] then
        Outcome = not_agari
    else if Scored = [First | Rest] then
        Outcome = scored(list.foldl(better, Rest, First))
    else
        Outcome = no_yaku
    ).

:- func better(result, result) = result.
better(A, B) = ( if worse(A, B) then B else A ).

    % worse(A, B): B is preferred.  Higher total, then a real yakuman over
    % kazoe, then han, then fu; last, the yaku string that sorts first.
:- pred worse(result::in, result::in) is semidet.
worse(A, B) :-
    compare(R, rank(A), rank(B)),
    (
        R = (<)
    ;
        R = (=),
        compare((<), yaku_string(B ^ yaku), yaku_string(A ^ yaku))
    ).

:- func rank(result) = {int, int, int, int}.
rank(R) = {total(R), Real, Han, Fu} :-
    (
        R ^ value = yakuman(_),
        Real = 1, Han = 0, Fu = 0
    ;
        R ^ value = ordinary(Han, Fu),
        Real = 0
    ).

:- func yaku_string(list(pair(string, int))) = string.
yaku_string(Yaku) = string.join_list(",",
    list.map((func(N - H) = N ++ ":" ++ int_to_string(H)), Yaku)).

outcome_to_string(not_agari) = "error=not_agari".
outcome_to_string(no_yaku) = "error=no_yaku".
outcome_to_string(scored(R)) = string.join_list(" ", Fields) :-
    Yaku = "yaku=" ++ yaku_string(R ^ yaku),
    (
        R ^ value = ordinary(Han, Fu),
        Middle = ["han=" ++ int_to_string(Han), "fu=" ++ int_to_string(Fu)]
    ;
        R ^ value = yakuman(M),
        Middle = ["yakuman=" ++ int_to_string(M)]
    ),
    Fields = [Yaku | Middle] ++
        ["pay=" ++ payment_to_string(R ^ pay),
            "total=" ++ int_to_string(total(R))].

%---------------------------------------------------------------------------%
:- end_module score.
%---------------------------------------------------------------------------%
