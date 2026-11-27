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
:- import_module solutions.
:- import_module string.

    % One clause group per trigger; solutions/2 sorts the action strings and
    % drops duplicates (a red and a plain five give the same kan, say).
actions(R) = solutions(action(R)).

:- pred action(legal_request::in, string::out) is nondet.
action(R, A) :-
    R ^ trigger = draw(D),
    on_draw(R, D, [D | R ^ hand], A).
action(R, A) :-
    R ^ trigger = discard(T, From),
    on_discard(R, T, From, A).
action(R, discarding(T)) :-
    R ^ trigger = called(M, Took),
    TK = kind_of(Took),
    allowed_discard(R ^ hand,
        kuikae(M ^ mkind, TK, list.delete_all(meld_kinds(M), TK)), T).

:- func discarding(tile) = string.
discarding(T) = "discard:" ++ tile_to_string(T).

:- func num_melds(legal_request) = int.
num_melds(R) = list.length(R ^ melds).

:- pred has_flag(legal_request::in, flag::in) is semidet.
has_flag(R, F) :-
    list.member(F, R ^ sit ^ flags).

:- pred kan_allowed(legal_request::in) is semidet.
kan_allowed(R) :-
    R ^ wall >= 1,
    R ^ kans < 4.

    % Does this tile complete the hand with a yaku?  The riichi yaku comes
    % from riichi=1; everything else from the flags.
:- pred wins(legal_request::in, tile::in, win_by::in) is semidet.
wins(R, T, By) :-
    Sit0 = R ^ sit,
    ( if
        R ^ in_riichi = yes,
        not has_flag(R, riichi),
        not has_flag(R, double_riichi)
    then
        Sit = Sit0 ^ flags := [riichi | Sit0 ^ flags]
    else
        Sit = Sit0
    ),
    evaluate(score_request(R ^ hand, R ^ melds, T, By, Sit)) = scored(_).

%---------------------------------------------------------------------------%
% Own draw.  All is the hand with the drawn tile.

:- pred on_draw(legal_request::in, tile::in, list(tile)::in, string::out)
    is nondet.
on_draw(R, D, All, discarding(T)) :-
    ( if R ^ in_riichi = yes then T = D else list.member(T, All) ).
on_draw(R, D, _, "tsumo") :-
    wins(R, D, tsumo).
on_draw(R, _, All, A) :-
    R ^ in_riichi = no,
    all_closed(R ^ melds),
    R ^ wall >= 4,
    MeldBag = kind_bag(meld_tiles(R ^ melds)),
    list.member(T, list.sort_and_remove_dups(All)),
    list.delete_first(All, T, Rest),
    RestBag = kind_bag(Rest),
    live_tenpai(RestBag, bag.union(RestBag, MeldBag), num_melds(R)),
    A = "riichi:" ++ tile_to_string(T).
on_draw(R, D, All, A) :-
    kan_allowed(R),
    AllBag = kind_bag(All),
    list.member(K, bag.to_list_without_duplicates(AllBag)),
    bag.count_value(AllBag, K) = 4,
    ( R ^ in_riichi = yes => riichi_kan_keeps_waits(R, AllBag, kind_of(D), K) ),
    A = "ankan:" ++ kind_to_string(K).
on_draw(R, _, All, A) :-
    R ^ in_riichi = no,
    kan_allowed(R),
    list.member(T, All),
    list.member(meld(pon, [P | _]), R ^ melds),
    kind_of(P) = kind_of(T),
    A = "kakan:" ++ tile_to_string(T).
on_draw(R, _, All, "kyuushu") :-
    R ^ first = yes,
    list.length(list.filter(is_yaochu,
        list.sort_and_remove_dups(kinds_of(All)))) >= 9.

    % In riichi: the kan must use the drawn tile, and the wait kinds after
    % the kan must equal those before the draw.
:- pred riichi_kan_keeps_waits(legal_request::in, bag(kind)::in, kind::in,
    kind::in) is semidet.
riichi_kan_keeps_waits(R, AllBag, Drawn, K) :-
    K = Drawn,
    N = num_melds(R),
    bag.remove_all(K, AllBag, After),
    wait_kinds(kind_bag(R ^ hand), N) = wait_kinds(After, N + 1).

%---------------------------------------------------------------------------%
% Another seat's discard, or a kan being robbed

:- pred on_discard(legal_request::in, tile::in, from::in, string::out)
    is multi.
on_discard(_, _, _, "pass").
on_discard(R, T, _, "ron") :-
    R ^ furiten = no,
    ( if has_flag(R, ankan_rob) then
        is_kokushi(kind_bag([T | R ^ hand]), _)
    else
        wins(R, T, ron)
    ).
on_discard(R, T, From, A) :-
    not has_flag(R, ankan_rob),
    not has_flag(R, chankan),
    R ^ in_riichi = no,
    R ^ wall >= 1,
    call_on(R ^ hand, kind_of(T), From, R, A).

    % Calls on a discard of kind TK.  Each leaves the hand at least one
    % discard that is not kuikae.
:- pred call_on(list(tile)::in, kind::in, from::in, legal_request::in,
    string::out) is nondet.
call_on(Hand, TK, kamicha, _, A) :-
    list.member({DA, DB}, [{-2, -1}, {-1, 1}, {1, 2}]),
    offset(TK, DA, KA),
    offset(TK, DB, KB),
    take(KA, Hand, TA, H1),
    take(KB, H1, TB, H2),
    leaves_discard(H2, kuikae(chi, TK, [KA, KB])),
    A = "chi:" ++ tiles_to_string([TA, TB]).
call_on(Hand, TK, _, _, A) :-
    take(TK, Hand, TA, H1),
    take(TK, H1, TB, H2),
    leaves_discard(H2, kuikae(pon, TK, [TK, TK])),
    A = "pon:" ++ tiles_to_string([TA, TB]).
call_on(Hand, TK, _, R, "kan:" ++ kind_to_string(TK)) :-
    kan_allowed(R),
    list.length(list.filter((pred(T::in) is semidet :- kind_of(T) = TK),
        Hand)) = 3.

    % take(K, Hand, T, Rest): T is a tile of kind K from Hand.
:- pred take(kind::in, list(tile)::in, tile::out, list(tile)::out) is nondet.
take(K, Hand, T, Rest) :-
    list.delete(Hand, T, Rest),
    kind_of(T) = K.

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

:- pred allowed_discard(list(tile)::in, list(kind)::in, tile::out) is nondet.
allowed_discard(Hand, Forbidden, T) :-
    list.member(T, Hand),
    not list.member(kind_of(T), Forbidden).

:- pred leaves_discard(list(tile)::in, list(kind)::in) is semidet.
leaves_discard(Hand, Forbidden) :-
    allowed_discard(Hand, Forbidden, _).

%---------------------------------------------------------------------------%
:- end_module legal.
%---------------------------------------------------------------------------%
