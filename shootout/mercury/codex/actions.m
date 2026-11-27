:- module actions.
:- interface.

:- import_module list, tiles.

:- type source ---> left ; across ; right.
:- type turn ---> drew(tile) ; discarded(tile, source) ; called(meld, tile).
:- type table ---> table(
    riichi :: bool_riichi,
    furiten :: bool_furiten,
    first :: bool_first,
    wall :: int,
    table_kans :: int
).
:- type bool_riichi ---> in_riichi ; free.
:- type bool_furiten ---> furiten ; clear.
:- type bool_first ---> first_turn ; later.

:- func legal(list(tile), list(meld), turn, table, context) = list(string).

:- implementation.
:- import_module int, scoring, set, shape, solutions, string.

legal(Hand, Melds, Turn, Table, C) = Actions :-
    Context = (if Table ^ riichi = in_riichi then
        C ^ flags := set.insert(C ^ flags, "riichi") else C),
    solutions(action(Hand, Melds, Turn, Table, Context), Actions).

:- pred action(list(tile)::in, list(meld)::in, turn::in, table::in,
    context::in, string::out) is nondet.
action(Hand, Melds, drew(Draw), Table, C, Action) :-
    Full = [Draw | Hand],
    ( ( if Table ^ riichi = in_riichi then T = Draw else list.member(T, Full) ),
        Action = "discard:" ++ render_tiles([T])
    ; Table ^ riichi = free, Table ^ wall >= 4, closed(Melds),
        list.delete(Full, T, Rest), live_tenpai(Rest, Melds),
        Action = "riichi:" ++ render_tiles([T])
    ; can_win(Hand, Melds, Draw, tsumo, C), Action = "tsumo"
    ; Table ^ first = first_turn,
        list.length(list.sort_and_remove_dups(list.filter(outside, kinds(Full)))) >= 9,
        Action = "kyuushu"
    ; can_kan(Table),
        list.member(K, list.sort_and_remove_dups(kinds(Full))),
        Quad = list.filter((pred(U::in) is semidet :- kind_of(U) = K), Full),
        list.length(Quad) = 4,
        ( if Table ^ riichi = in_riichi then
            K = kind_of(Draw),
            Rest = list.filter((pred(U::in) is semidet :- kind_of(U) \= K), Full),
            N = list.length(Melds),
            structural_waits(kinds(Hand), N) = structural_waits(kinds(Rest), N + 1)
          else true
        ),
        Action = "ankan:" ++ render_kind(K)
    ; can_kan(Table), Table ^ riichi = free,
        list.member(meld(pon, [P | _]), Melds),
        list.member(T, Full), kind_of(T) = kind_of(P),
        Action = "kakan:" ++ render_tiles([T])
    ).
action(Hand, Melds, discarded(Took, From), Table, C, Action) :-
    K = kind_of(Took),
    ( Action = "pass"
    ; Table ^ furiten = clear,
        ( if has_flag(C, "ankan_rob") then
            Melds = [], is_kokushi(kinds([Took | Hand]))
          else can_win(Hand, Melds, Took, ron, C)
        ),
        Action = "ron"
    ; Table ^ riichi = free, Table ^ wall >= 1,
        not has_flag(C, "chankan"), not has_flag(C, "ankan_rob"),
        ( take_kind(K, Hand, A, Tail), take_kind(K, Tail, B, Rest),
            has_discard(pon, K, K, Rest),
            Action = "pon:" ++ render_tiles([A, B])
        ; can_kan(Table),
            list.length(list.filter((pred(T::in) is semidet :- kind_of(T) = K),
                Hand)) = 3,
            Action = "kan:" ++ render_kind(K)
        ; From = left, not honor(K),
            SuitStart = K - rank(K) + 1,
            list.member(Start, int.max(SuitStart, K - 2) .. K),
            rank(Start) =< 7,
            list.delete([Start, Start + 1, Start + 2], K, [X, Y]),
            take_kind(X, Hand, A, Tail), take_kind(Y, Tail, B, Rest),
            has_discard(chi, K, Start, Rest),
            Action = "chi:" ++ render_tiles([A, B])
        )
    ).
action(Hand, _, called(Meld, Took), _, _, Action) :-
    Meld = meld(Call, _),
    meld_group(Meld) = group(Start, _, _),
    list.member(T, Hand),
    allowed_discard(Call, kind_of(Took), Start, T),
    Action = "discard:" ++ render_tiles([T]).

:- pred can_kan(table::in) is semidet.
can_kan(T) :- T ^ wall >= 1, T ^ table_kans < 4.

:- pred take_kind(kind::in, list(tile)::in, tile::out, list(tile)::out) is nondet.
take_kind(K, Ts, T, Rest) :- list.delete(Ts, T, Rest), kind_of(T) = K.

:- pred has_discard(call::in, kind::in, kind::in, list(tile)::in) is semidet.
has_discard(Call, Took, Start, Ts) :-
    list.find_first_match(allowed_discard(Call, Took, Start), Ts, _).

:- pred allowed_discard(call::in, kind::in, kind::in, tile::in) is semidet.
allowed_discard(Call, Took, Start, T) :-
    K = kind_of(T),
    K \= Took,
    not ( Call = chi, suit(K) = suit(Took),
        ( Took = Start, K = Start + 3
        ; Took = Start + 2, K = Start - 1
        )
    ).
