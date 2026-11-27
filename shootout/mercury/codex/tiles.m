:- module tiles.
:- interface.

:- import_module list, set.

:- type kind == int.
:- type tile ---> tile(kind, bool_red).
:- type bool_red ---> plain ; red.
:- type call ---> chi ; pon ; open_kan ; added_kan ; closed_kan.
:- type meld ---> meld(call, list(tile)).
:- type role ---> pair ; sequence ; triplet ; quad.
:- type exposure ---> concealed ; exposed.
:- type group ---> group(kind, role, exposure).
:- type method ---> ron ; tsumo.
:- type context ---> context(
    seat :: kind,
    round_wind :: kind,
    flags :: set(string),
    indicators :: list(kind),
    hidden_indicators :: list(kind),
    honba :: int
).

:- pred parse_tiles(string::in, list(tile)::out) is semidet.
:- pred parse_tile(string::in, tile::out) is semidet.
:- pred parse_melds(string::in, list(meld)::out) is semidet.
:- pred parse_meld(string::in, meld::out) is semidet.
:- pred parse_wind(string::in, kind::out) is semidet.
:- func kind_of(tile) = kind.
:- func kinds(list(tile)) = list(kind).
:- func meld_tiles(meld) = list(tile).
:- func meld_group(meld) = group.
:- pred closed(list(meld)::in) is semidet.
:- func suit(kind) = int.
:- func rank(kind) = int.
:- pred honor(kind::in) is semidet.
:- pred terminal(kind::in) is semidet.
:- pred outside(kind::in) is semidet.
:- func all_kinds = list(kind).
:- func orphan_kinds = list(kind).
:- func render_tiles(list(tile)) = string.
:- func render_kind(kind) = string.
:- func render_group(group) = string.
:- func group_kinds(group) = list(kind).
:- func successor(kind) = kind.
:- pred has_flag(context::in, string::in) is semidet.

:- implementation.
:- import_module char, int, string.

parse_tiles(S, Tiles) :-
    ( if S = "-" then Tiles = []
      else parse_suits(string.to_char_list(S), [], -1, Tiles)
    ).

:- pred parse_suits(list(char)::in, list(int)::in, int::in, list(tile)::out)
    is semidet.
parse_suits([], [], _, []).
parse_suits([C | Cs], Digits, Prev, Tiles) :-
    ( if char.decimal_digit_to_int(C, N) then
        parse_suits(Cs, [N | Digits], Prev, Tiles)
      else
        suit_char(C, Suit),
        Suit > Prev,
        Digits = [_ | _],
        list.map(make_tile(Suit), list.reverse(Digits), Block),
        parse_suits(Cs, [], Suit, Rest),
        Tiles = Block ++ Rest
    ).

:- pred suit_char(char, int).
:- mode suit_char(in, out) is semidet.
:- mode suit_char(out, in) is semidet.
suit_char('m', 0).
suit_char('p', 1).
suit_char('s', 2).
suit_char('z', 3).

:- pred make_tile(int::in, int::in, tile::out) is semidet.
make_tile(S, D, T) :-
    ( if D = 0 then S < 3, T = tile(S * 9 + 4, red)
      else
        ( if S = 3 then D =< 7 else true ),
        T = tile(S * 9 + D - 1, plain)
    ).

parse_tile(S, T) :- parse_tiles(S, [T]).

parse_melds(S, Ms) :-
    ( if S = "-" then Ms = []
      else list.map(parse_meld, string.split_at_char(',', S), Ms)
    ).

parse_meld(S, meld(Call, Ts)) :-
    string.to_char_list(S) = [C | Cs],
    call_char(C, Call),
    parse_tiles(string.from_char_list(Cs), Ts),
    ( Call = chi, kinds(Ts) = [A, B, D],
        not honor(A), suit(A) = suit(D), B = A + 1, D = A + 2
    ; Call = pon, kinds(Ts) = [A, A, A]
    ; (Call = open_kan ; Call = added_kan ; Call = closed_kan),
        kinds(Ts) = [A, A, A, A]
    ).

:- pred call_char(char::in, call::out) is semidet.
call_char('c', chi).
call_char('p', pon).
call_char('k', open_kan).
call_char('s', added_kan).
call_char('a', closed_kan).

parse_wind("E", 27).
parse_wind("S", 28).
parse_wind("W", 29).
parse_wind("N", 30).

kind_of(tile(K, _)) = K.
kinds(Ts) = list.sort(list.map(kind_of, Ts)).
meld_tiles(meld(_, Ts)) = Ts.

meld_group(meld(Call, Ts)) = group(K, Role, Exposure) :-
    K = list.foldl((func(T, Min) = int.min(kind_of(T), Min)), Ts, 34),
    ( Call = chi, Role = sequence, Exposure = exposed
    ; Call = pon, Role = triplet, Exposure = exposed
    ; (Call = open_kan ; Call = added_kan), Role = quad, Exposure = exposed
    ; Call = closed_kan, Role = quad, Exposure = concealed
    ).

closed(Ms) :- list.all_true((pred(M::in) is semidet :- M = meld(closed_kan, _)), Ms).
suit(K) = K // 9.
rank(K) = K mod 9 + 1.
honor(K) :- K >= 27.
terminal(K) :- K < 27, (rank(K) = 1 ; rank(K) = 9).
outside(K) :- ( if honor(K) then true else terminal(K) ).
all_kinds = 0 .. 33.
orphan_kinds = list.filter(outside, all_kinds).

render_tiles(Tiles) =
    ( if Tiles = [] then "-" else
        string.append_list(list.map(render_suit(Tiles), 0 .. 3))
    ).

:- func render_suit(list(tile), int) = string.
render_suit(Tiles, S) = Out :-
    Block = list.filter((pred(T::in) is semidet :- suit(kind_of(T)) = S), Tiles),
    Digits = list.sort(list.map(tile_order, Block)),
    ( if Digits = [] then Out = ""
      else
        Suffix = (if suit_char(C, S) then string.from_char(C) else ""),
        Out = string.append_list(list.map((func(D) =
            int_to_string((if D = 9 then 0 else D // 2))), Digits)) ++ Suffix
    ).

:- func tile_order(tile) = int.
tile_order(tile(K, R)) = (if R = red then 9 else rank(K) * 2).

render_kind(K) = render_tiles([tile(K, plain)]).
render_group(G) = render_tiles(list.map((func(K) = tile(K, plain)), group_kinds(G))).
group_kinds(group(K, R, _)) = Ks :-
    ( R = pair, Ks = [K, K]
    ; R = sequence, Ks = [K, K + 1, K + 2]
    ; R = triplet, Ks = [K, K, K]
    ; R = quad, Ks = [K, K, K, K]
    ).

successor(K) =
    ( if K < 27 then (if rank(K) = 9 then K - 8 else K + 1)
      else if K = 30 then 27
      else if K = 33 then 31
      else K + 1
    ).

has_flag(C, Flag) :- set.contains(C ^ flags, Flag).
