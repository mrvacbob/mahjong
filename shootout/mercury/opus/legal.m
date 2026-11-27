%---------------------------------------------------------------------------%
% legal.m: the actions a seat may take, built from hand and score.
%---------------------------------------------------------------------------%
:- module legal.
:- interface.

:- import_module score.
:- import_module tile.
:- import_module bool.
:- import_module list.

:- type from
    --->    kamicha
    ;       toimen
    ;       shimocha.

:- type trigger
    --->    draw(tile)
    ;       discard(tile, from)
    ;       called(meld, tile).

:- type legal_request
    --->    legal_request(
                hand        :: list(tile),
                melds       :: list(meld),
                trigger     :: trigger,
                sit         :: situation,
                in_riichi   :: bool,
                furiten     :: bool,
                wall        :: int,
                first       :: bool,
                kans        :: int
            ).

    % Sorted as strings, no duplicates.
:- func actions(legal_request) = list(string).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module hand.
:- import_module bag.
:- import_module int.
:- import_module set.
:- import_module string.

actions(R) = set.to_sorted_list(set.from_list(As)) :-
    (
        R ^ trigger = draw(D),
        As = draw_actions(R, D)
    ;
        R ^ trigger = discard(T, From),
        As = ["pass" | discard_actions(R, T, From)]
    ;
        R ^ trigger = called(M, Took),
        Forbidden = kuikae(M ^ mkind, kind_of(Took),
            list.delete_all(meld_kinds(M), kind_of(Took))),
        As = list.map(discard_action, allowed_discards(R ^ hand, Forbidden))
    ).

:- func discard_action(tile) = string.
discard_action(T) = "discard:" ++ tile_to_string(T).

:- func distinct(list(tile)) = list(tile).
distinct(Ts) = set.to_sorted_list(set.from_list(Ts)).

:- func num_melds(legal_request) = int.
num_melds(R) = list.length(R ^ melds).

:- pred closed_hand(legal_request::in) is semidet.
closed_hand(R) :-
    not list.any_true(is_open_meld, R ^ melds).

:- pred kan_allowed(legal_request::in) is semidet.
kan_allowed(R) :-
    R ^ wall >= 1,
    R ^ kans < 4.

    % Does this tile complete the hand with a yaku?  The riichi yaku comes
    % from riichi=1; everything else from the flags.
:- pred wins(legal_request::in, tile::in, win_by::in) is semidet.
wins(R, T, By) :-
    Sit0 = R ^ sit,
    ( if R ^ in_riichi = yes, not list.member(double_riichi, Sit0 ^ flags)
    then
        Sit = Sit0 ^ flags := [riichi | Sit0 ^ flags]
    else
        Sit = Sit0
    ),
    evaluate(score_request(R ^ hand, R ^ melds, T, By, Sit)) = scored(_).

%---------------------------------------------------------------------------%
% Own draw

:- func draw_actions(legal_request, tile) = list(string).
draw_actions(R, D) = Discards ++ Tsumo ++ Riichi ++ Ankan ++ Kakan ++ Kyuushu
        :-
    Hand = R ^ hand,
    All = [D | Hand],
    AllBag = kind_bag(All),
    InRiichi = R ^ in_riichi,
    ( if InRiichi = yes then
        Discards = [discard_action(D)]
    else
        Discards = list.map(discard_action, distinct(All))
    ),
    Tsumo = ( if wins(R, D, tsumo) then ["tsumo"] else [] ),
    ( if InRiichi = no, closed_hand(R), R ^ wall >= 4 then
        Riichi = list.filter_map(
            (func(T) = "riichi:" ++ tile_to_string(T) is semidet :-
                list.delete_first(All, T, Rest),
                RestBag = kind_bag(Rest),
                Waits = waits(RestBag,
                    bag.union(RestBag, meld_bag(R)), num_melds(R)),
                Waits ^ w_shanten = 0,
                Waits ^ w_count > 0),
            distinct(All))
    else
        Riichi = []
    ),
    Quads = list.filter((pred(K::in) is semidet :-
        bag.count_value(AllBag, K) = 4), bag.to_list_without_duplicates(AllBag)),
    ( if kan_allowed(R) then
        Ankan = list.filter_map(
            (func(K) = "ankan:" ++ kind_to_string(K) is semidet :-
                InRiichi = yes =>
                    riichi_kan_keeps_waits(R, AllBag, kind_of(D), K)),
            Quads),
        ( if InRiichi = no then
            Kakan = list.filter_map(
                (func(T) = "kakan:" ++ tile_to_string(T) is semidet :-
                    has_pon_of(R ^ melds, kind_of(T))),
                distinct(All))
        else
            Kakan = []
        )
    else
        Ankan = [],
        Kakan = []
    ),
    ( if
        R ^ first = yes,
        list.length(list.filter(is_yaochu,
            bag.to_list_without_duplicates(AllBag))) >= 9
    then
        Kyuushu = ["kyuushu"]
    else
        Kyuushu = []
    ).

:- pred has_pon_of(list(meld)::in, kind::in) is semidet.
has_pon_of(Melds, K) :-
    list.member(meld(pon, [T | _]), Melds),
    kind_of(T) = K.

:- func meld_bag(legal_request) = bag(kind).
meld_bag(R) = bag.from_list(list.condense(list.map(meld_kinds, R ^ melds))).

    % In riichi: the kan must use the drawn tile, and the wait kinds after
    % the kan must equal those before the draw.
:- pred riichi_kan_keeps_waits(legal_request::in, bag(kind)::in, kind::in,
    kind::in) is semidet.
riichi_kan_keeps_waits(R, AllBag, Drawn, K) :-
    K = Drawn,
    N = num_melds(R),
    Before = wait_kinds(kind_bag(R ^ hand), N),
    bag.remove_all(K, AllBag, After),
    Before = wait_kinds(After, N + 1).

%---------------------------------------------------------------------------%
% Another seat's discard, or a kan being robbed

:- func discard_actions(legal_request, tile, from) = list(string).
discard_actions(R, T, From) = Actions :-
    Flags = R ^ sit ^ flags,
    Hand = R ^ hand,
    TK = kind_of(T),
    ( if list.member(ankan_rob, Flags) then
        ( if
            R ^ furiten = no,
            is_kokushi(kind_bag([T | Hand]), _)
        then
            Actions = ["ron"]
        else
            Actions = []
        )
    else
        Ron = ( if R ^ furiten = no, wins(R, T, ron) then ["ron"] else [] ),
        ( if
            not list.member(chankan, Flags),
            R ^ in_riichi = no,
            R ^ wall >= 1
        then
            ( if From = kamicha then
                Chi = chi_actions(Hand, TK)
            else
                Chi = []
            ),
            Same = list.filter((pred(X::in) is semidet :- kind_of(X) = TK),
                Hand),
            Pon = list.filter_map(
                (func(Two) = "pon:" ++ tiles_to_string(Two) is semidet :-
                    Two = [A, B],
                    list.delete_first(Hand, A, H1),
                    list.delete_first(H1, B, H2),
                    allowed_discards(H2, [TK]) \= []),
                two_of(Same)),
            ( if list.length(Same) = 3, R ^ kans < 4 then
                Kan = ["kan:" ++ kind_to_string(TK)]
            else
                Kan = []
            ),
            Actions = Ron ++ Chi ++ Pon ++ Kan
        else
            Actions = Ron
        )
    ).

    % The distinct two-tile choices from a list, each sorted.
:- func two_of(list(tile)) = list(list(tile)).
two_of(Ts) = set.to_sorted_list(set.from_list(solutions_two(Ts))).

:- func solutions_two(list(tile)) = list(list(tile)).
solutions_two([]) = [].
solutions_two([T | Ts]) =
    list.map((func(U) = list.sort([T, U])), Ts) ++ solutions_two(Ts).

:- func chi_actions(list(tile), kind) = list(string).
chi_actions(Hand, TK) = list.condense(list.map(
    (func({A, B}) = Strs :-
        ( if offset(TK, A, KA), offset(TK, B, KB) then
            TAs = distinct(list.filter(is_kind(KA), Hand)),
            TBs = distinct(list.filter(is_kind(KB), Hand)),
            Strs = list.filter_map(
                (func({TA, TB}) = "chi:" ++ tiles_to_string([TA, TB])
                        is semidet :-
                    list.delete_first(Hand, TA, H1),
                    list.delete_first(H1, TB, H2),
                    allowed_discards(H2, kuikae(chi, TK, [KA, KB])) \= []),
                list.condense(list.map(
                    (func(TA) = list.map((func(TB) = {TA, TB}), TBs)),
                    TAs)))
        else
            Strs = []
        )),
    [{-2, -1}, {-1, 1}, {1, 2}])).

:- pred is_kind(kind::in, tile::in) is semidet.
is_kind(K, T) :- kind_of(T) = K.

%---------------------------------------------------------------------------%
% Kuikae

    % kuikae(MeldKind, Took, UsedFromHand) = kinds that may not be discarded.
:- func kuikae(meld_kind, kind, list(kind)) = list(kind).
kuikae(MK, Took, Used) = [Took | Suji] :-
    ( if
        MK = chi,
        list.sort(Used, [X, Y]),
        offset(X, 1, Y)
    then
        ( if compare((<), Took, X), offset(Y, 1, Z) then
            Suji = [Z]
        else if compare((>), Took, Y), offset(X, -1, Z) then
            Suji = [Z]
        else
            Suji = []
        )
    else
        Suji = []
    ).

:- func allowed_discards(list(tile), list(kind)) = list(tile).
allowed_discards(Hand, Forbidden) = distinct(list.filter(
    (pred(T::in) is semidet :- not list.member(kind_of(T), Forbidden)),
    Hand)).

%---------------------------------------------------------------------------%
:- end_module legal.
%---------------------------------------------------------------------------%
