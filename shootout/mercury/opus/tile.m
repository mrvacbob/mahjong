%---------------------------------------------------------------------------%
% tile.m: tiles, kinds, melds and their mpsz text form.
%---------------------------------------------------------------------------%
:- module tile.
:- interface.

:- import_module bag.
:- import_module list.

    % Constructor order is significant: the built-in structural ordering of
    % these types is the canonical mpsz order (m < p < s < z, ascending,
    % red five immediately before the plain five).
:- type suit
    --->    man
    ;       pin
    ;       sou
    ;       honor.

:- type kind
    --->    kind(suit :: suit, num :: int).

:- type colour
    --->    red
    ;       plain.

:- type tile
    --->    tile(tkind :: kind, colour :: colour).

:- type meld_kind
    --->    chi
    ;       pon
    ;       daiminkan
    ;       shouminkan
    ;       ankan.

:- type meld
    --->    meld(mkind :: meld_kind, mtiles :: list(tile)).

%---------------------------------------------------------------------------%

:- pred parse_tile(string::in, tile::out) is semidet.
:- pred parse_tiles(string::in, list(tile)::out) is semidet.
:- pred parse_meld(string::in, meld::out) is semidet.
:- pred parse_melds(string::in, list(meld)::out) is semidet.
:- pred parse_wind(string::in, kind::out) is semidet.

    % Canonical text; the list is sorted first.  "-" for the empty list.
:- func tiles_to_string(list(tile)) = string.
:- func tile_to_string(tile) = string.
    % Kinds print with 5 for a red five.
:- func kinds_to_string(list(kind)) = string.
:- func kind_to_string(kind) = string.

:- func kind_of(tile) = kind.
:- func kinds_of(list(tile)) = list(kind).
:- func kind_bag(list(tile)) = bag(kind).

    % The 34 kinds in canonical order.
:- func all_kinds = list(kind).

    % dora_of(Indicator) = Dora.
:- func dora_of(kind) = kind.

:- pred is_number(kind::in) is semidet.
:- pred is_honor(kind::in) is semidet.
:- pred is_terminal(kind::in) is semidet.
:- pred is_yaochu(kind::in) is semidet.
:- pred is_simple(kind::in) is semidet.
:- pred is_dragon(kind::in) is semidet.
:- pred is_wind(kind::in) is semidet.

    % The kind N steps up in the same number suit, if it exists.
:- pred offset(kind::in, int::in, kind::out) is semidet.

:- pred is_open_meld(meld::in) is semidet.
:- func meld_kinds(meld) = list(kind).

:- func east = kind.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module char.
:- import_module int.
:- import_module string.

parse_tile(S, T) :-
    parse_tiles(S, [T]).

parse_tiles(S, Tiles) :-
    ( if S = "-" then
        Tiles = []
    else
        string.to_char_list(S, Cs),
        Cs \= [],
        parse_groups(Cs, [], Tiles)
    ).

    % Digits accumulate until a suit letter assigns them a suit.
:- pred parse_groups(list(char)::in, list(int)::in, list(tile)::out) is semidet.
parse_groups([], [], []).
parse_groups([C | Cs], Digits, Tiles) :-
    ( if char.decimal_digit_to_int(C, D) then
        parse_groups(Cs, [D | Digits], Tiles)
    else
        suit_char(C, Suit),
        Digits \= [],
        list.map(make_tile(Suit), list.reverse(Digits), These),
        parse_groups(Cs, [], Rest),
        Tiles = These ++ Rest
    ).

:- pred make_tile(suit::in, int::in, tile::out) is semidet.
make_tile(Suit, D, T) :-
    ( if D = 0 then
        Suit \= honor,
        T = tile(kind(Suit, 5), red)
    else
        D >= 1,
        ( if Suit = honor then D =< 7 else D =< 9 ),
        T = tile(kind(Suit, D), plain)
    ).

:- pred suit_char(char, suit).
:- mode suit_char(in, out) is semidet.
:- mode suit_char(out, in) is det.
suit_char('m', man).
suit_char('p', pin).
suit_char('s', sou).
suit_char('z', honor).

parse_meld(S, meld(MK, Tiles)) :-
    string.first_char(S, C, Rest),
    meld_char(C, MK),
    parse_tiles(Rest, Tiles0),
    list.sort(Tiles0, Tiles),
    list.length(Tiles, N),
    Ks = kinds_of(Tiles),
    ( MK = chi,
        N = 3,
        Ks = [K1, K2, K3],
        offset(K1, 1, K2),
        offset(K1, 2, K3)
    ; MK = pon,
        N = 3,
        list.all_same(Ks)
    ; ( MK = daiminkan ; MK = shouminkan ; MK = ankan ),
        N = 4,
        list.all_same(Ks)
    ).

:- pred meld_char(char::in, meld_kind::out) is semidet.
meld_char('c', chi).
meld_char('p', pon).
meld_char('k', daiminkan).
meld_char('s', shouminkan).
meld_char('a', ankan).

parse_melds(S, Melds) :-
    ( if S = "-" then
        Melds = []
    else
        list.map(parse_meld, string.split_at_char(',', S), Melds)
    ).

parse_wind("E", kind(honor, 1)).
parse_wind("S", kind(honor, 2)).
parse_wind("W", kind(honor, 3)).
parse_wind("N", kind(honor, 4)).

%---------------------------------------------------------------------------%

tiles_to_string(Tiles0) = Str :-
    ( if Tiles0 = [] then
        Str = "-"
    else
        list.sort(Tiles0, Tiles),
        Str = string.append_list(print_runs(Tiles))
    ).

    % Print the digits of a sorted list, a suit letter after each suit's run.
:- func print_runs(list(tile)) = list(string).
print_runs([]) = [].
print_runs([T | Ts]) = Strs :-
    Suit = T ^ tkind ^ suit,
    list.take_while(same_suit(Suit), [T | Ts], Here, Rest),
    suit_char(C, Suit),
    Strs = list.map(tile_digit, Here) ++ [char_to_string(C)]
        ++ print_runs(Rest).

:- pred same_suit(suit::in, tile::in) is semidet.
same_suit(S, tile(kind(S, _), _)).

:- func tile_digit(tile) = string.
tile_digit(tile(kind(_, N), Colour)) =
    ( if Colour = red then "0" else int_to_string(N) ).

tile_to_string(T) = tiles_to_string([T]).

kinds_to_string(Ks) =
    tiles_to_string(list.map((func(K) = tile(K, plain)), Ks)).

kind_to_string(K) = kinds_to_string([K]).

%---------------------------------------------------------------------------%

kind_of(T) = T ^ tkind.
kinds_of(Ts) = list.map(kind_of, Ts).
kind_bag(Ts) = bag.from_list(kinds_of(Ts)).

all_kinds =
    list.condense(list.map(
        (func(S) = list.map((func(N) = kind(S, N)), 1 .. 9)),
        [man, pin, sou])) ++
    list.map((func(N) = kind(honor, N)), 1 .. 7).

dora_of(kind(S, N)) = kind(S, M) :-
    ( if S = honor then
        ( if N =< 4 then
            M = N mod 4 + 1
        else
            M = (N - 5 + 1) mod 3 + 5
        )
    else
        M = N mod 9 + 1
    ).

is_number(kind(S, _)) :- S \= honor.
is_honor(kind(honor, _)).
is_terminal(kind(S, N)) :- S \= honor, ( N = 1 ; N = 9 ).
is_yaochu(K) :- ( is_honor(K) ; is_terminal(K) ).
is_simple(K) :- not is_yaochu(K).
is_dragon(kind(honor, N)) :- N >= 5.
is_wind(kind(honor, N)) :- N =< 4.

offset(kind(S, N), D, kind(S, N + D)) :-
    S \= honor,
    N + D >= 1,
    N + D =< 9.

is_open_meld(meld(MK, _)) :- MK \= ankan.

meld_kinds(M) = kinds_of(M ^ mtiles).

east = kind(honor, 1).

%---------------------------------------------------------------------------%
:- end_module tile.
%---------------------------------------------------------------------------%
