:- module tiles.
:- interface.

:- import_module bag.
:- import_module char.
:- import_module list.

:- type num_suit
    --->    m
    ;       p
    ;       s.

:- type wind
    --->    east
    ;       south
    ;       west
    ;       north.

:- type dragon
    --->    haku
    ;       hatsu
    ;       chun.

:- type tile_kind
    --->    num(num_suit, int)
    ;       wind(wind)
    ;       dragon(dragon).

:- type is_red
    --->    red
    ;       plain.

:- type tile
    --->    tile(
                kind   :: tile_kind,
                is_red :: is_red
            ).

:- type meld_type
    --->    chi
    ;       pon
    ;       daiminkan
    ;       shouminkan
    ;       ankan.

:- type meld
    --->    meld(
                meld_type  :: meld_type,
                meld_tiles :: list(tile)
            ).

:- func all_tile_kinds = list(tile_kind).
:- func yaochuu_kinds = list(tile_kind).

:- pred parse_tile(string::in, tile::out) is semidet.
:- pred parse_tile_list(string::in, list(tile)::out) is semidet.
:- pred parse_meld(string::in, meld::out) is semidet.
:- pred parse_melds(string::in, list(meld)::out) is semidet.
:- pred parse_wind(string::in, wind::out) is semidet.

:- func format_tile(tile) = string.
:- func format_tile_kind(tile_kind) = string.
:- func format_tiles(list(tile)) = string.
:- func format_tile_kinds(list(tile_kind)) = string.

:- func next_dora(tile_kind) = tile_kind.

:- pred is_terminal(tile_kind::in) is semidet.
:- pred is_honor(tile_kind::in) is semidet.
:- pred is_yaochuu(tile_kind::in) is semidet.
:- pred is_simple(tile_kind::in) is semidet.
:- pred is_green(tile_kind::in) is semidet.
:- pred is_dragon(tile_kind::in) is semidet.
:- pred is_wind(tile_kind::in) is semidet.

:- pred is_closed_hand(list(meld)::in) is semidet.
:- pred is_kan_meld(meld::in) is semidet.

:- func hand_to_kind_bag(list(tile)) = bag(tile_kind).
:- func all_tiles_kind_bag(list(tile), list(meld)) = bag(tile_kind).
:- func all_physical_tiles(list(tile), list(meld)) = list(tile).

:- func suit_char(tile_kind) = char.
:- func kind_digit_char(tile_kind) = char.

:- implementation.

:- import_module int.
:- import_module string.

all_tile_kinds = [
    num(m, 1), num(m, 2), num(m, 3), num(m, 4), num(m, 5),
    num(m, 6), num(m, 7), num(m, 8), num(m, 9),
    num(p, 1), num(p, 2), num(p, 3), num(p, 4), num(p, 5),
    num(p, 6), num(p, 7), num(p, 8), num(p, 9),
    num(s, 1), num(s, 2), num(s, 3), num(s, 4), num(s, 5),
    num(s, 6), num(s, 7), num(s, 8), num(s, 9),
    wind(east), wind(south), wind(west), wind(north),
    dragon(haku), dragon(hatsu), dragon(chun)
].

yaochuu_kinds = [
    num(m, 1), num(m, 9),
    num(p, 1), num(p, 9),
    num(s, 1), num(s, 9),
    wind(east), wind(south), wind(west), wind(north),
    dragon(haku), dragon(hatsu), dragon(chun)
].

parse_tile(Str, Tile) :-
    string.to_char_list(Str, [DigitChar, SuitChar]),
    make_tile(DigitChar, SuitChar, Tile).

:- pred make_tile(char::in, char::in, tile::out) is semidet.

make_tile(DigitChar, SuitChar, Tile) :-
    ( if SuitChar = 'm' then
        make_num_tile(m, DigitChar, Tile)
    else if SuitChar = 'p' then
        make_num_tile(p, DigitChar, Tile)
    else if SuitChar = 's' then
        make_num_tile(s, DigitChar, Tile)
    else if SuitChar = 'z' then
        make_honor_tile(DigitChar, Tile)
    else
        fail
    ).

:- pred make_num_tile(num_suit::in, char::in, tile::out) is semidet.

make_num_tile(Suit, DigitChar, Tile) :-
    ( if DigitChar = '0' then
        Tile = tile(num(Suit, 5), red)
    else
        char_to_rank(DigitChar, D),
        Tile = tile(num(Suit, D), plain)
    ).

:- pred char_to_rank(char::in, int::out) is semidet.

char_to_rank('1', 1).
char_to_rank('2', 2).
char_to_rank('3', 3).
char_to_rank('4', 4).
char_to_rank('5', 5).
char_to_rank('6', 6).
char_to_rank('7', 7).
char_to_rank('8', 8).
char_to_rank('9', 9).

:- pred make_honor_tile(char::in, tile::out) is semidet.

make_honor_tile('1', tile(wind(east), plain)).
make_honor_tile('2', tile(wind(south), plain)).
make_honor_tile('3', tile(wind(west), plain)).
make_honor_tile('4', tile(wind(north), plain)).
make_honor_tile('5', tile(dragon(haku), plain)).
make_honor_tile('6', tile(dragon(hatsu), plain)).
make_honor_tile('7', tile(dragon(chun), plain)).

parse_tile_list(Str, Tiles) :-
    ( if Str = "-" then
        Tiles = []
    else
        string.to_char_list(Str, Chars),
        parse_tile_chars(Chars, [], RevTiles),
        list.reverse(RevTiles, Tiles)
    ).

:- pred parse_tile_chars(list(char)::in, list(char)::in, list(tile)::out)
    is semidet.

parse_tile_chars([], PendingDigits, []) :-
    PendingDigits = [].
parse_tile_chars([C | Cs], PendingDigits, RevTiles) :-
    ( if ( C = 'm' ; C = 'p' ; C = 's' ; C = 'z' ) then
        PendingDigits = [_ | _],
        list.reverse(PendingDigits, Digits),
        list.map(make_tile_for_suit(C), Digits, GroupTiles),
        parse_tile_chars(Cs, [], RestRevTiles),
        list.reverse(GroupTiles, RevGroupTiles),
        list.append(RestRevTiles, RevGroupTiles, RevTiles)
    else if char.is_digit(C) then
        parse_tile_chars(Cs, [C | PendingDigits], RevTiles)
    else
        fail
    ).

:- pred make_tile_for_suit(char::in, char::in, tile::out) is semidet.

make_tile_for_suit(SuitChar, DigitChar, Tile) :-
    make_tile(DigitChar, SuitChar, Tile).

parse_meld(Str, meld(MType, Tiles)) :-
    string.first_char(Str, Prefix, Rest),
    parse_meld_type(Prefix, MType),
    parse_tile_list(Rest, Tiles),
    Tiles = [_ | _].

:- pred parse_meld_type(char::in, meld_type::out) is semidet.

parse_meld_type('c', chi).
parse_meld_type('p', pon).
parse_meld_type('k', daiminkan).
parse_meld_type('s', shouminkan).
parse_meld_type('a', ankan).

parse_melds(Str, Melds) :-
    ( if Str = "-" then
        Melds = []
    else
        Parts = string.split_at_char(',', Str),
        list.map(parse_meld, Parts, Melds)
    ).

parse_wind("E", east).
parse_wind("S", south).
parse_wind("W", west).
parse_wind("N", north).

suit_char(num(m, _)) = 'm'.
suit_char(num(p, _)) = 'p'.
suit_char(num(s, _)) = 's'.
suit_char(wind(_)) = 'z'.
suit_char(dragon(_)) = 'z'.

kind_digit_char(num(_, N)) =
    ( if N = 1 then '1'
    else if N = 2 then '2'
    else if N = 3 then '3'
    else if N = 4 then '4'
    else if N = 5 then '5'
    else if N = 6 then '6'
    else if N = 7 then '7'
    else if N = 8 then '8'
    else '9'
    ).
kind_digit_char(wind(east)) = '1'.
kind_digit_char(wind(south)) = '2'.
kind_digit_char(wind(west)) = '3'.
kind_digit_char(wind(north)) = '4'.
kind_digit_char(dragon(haku)) = '5'.
kind_digit_char(dragon(hatsu)) = '6'.
kind_digit_char(dragon(chun)) = '7'.

:- func tile_digit_char(tile) = char.

tile_digit_char(tile(K, IsRed)) =
    ( if IsRed = red then '0' else kind_digit_char(K) ).

format_tile(Tile) =
    string.from_char_list([tile_digit_char(Tile), suit_char(Tile ^ kind)]).

format_tile_kind(K) =
    string.from_char_list([kind_digit_char(K), suit_char(K)]).

format_tiles(Tiles) = Str :-
    ( if Tiles = [] then
        Str = "-"
    else
        list.sort(Tiles, Sorted),
        format_sorted_tiles(Sorted, Chars),
        Str = string.from_char_list(Chars)
    ).

:- pred format_sorted_tiles(list(tile)::in, list(char)::out) is det.

format_sorted_tiles([], []).
format_sorted_tiles([T | Ts], Chars) :-
    S = suit_char(T ^ kind),
    take_same_suit_tiles(S, Ts, SameSuit, Rest),
    Digits = list.map(tile_digit_char, [T | SameSuit]),
    format_sorted_tiles(Rest, RestChars),
    list.append(Digits, [S | RestChars], Chars).

:- pred take_same_suit_tiles(char::in, list(tile)::in,
    list(tile)::out, list(tile)::out) is det.

take_same_suit_tiles(_, [], [], []).
take_same_suit_tiles(S, [T | Ts], Same, Rest) :-
    ( if suit_char(T ^ kind) = S then
        take_same_suit_tiles(S, Ts, Same0, Rest),
        Same = [T | Same0]
    else
        Same = [],
        Rest = [T | Ts]
    ).

format_tile_kinds(Kinds) = Str :-
    ( if Kinds = [] then
        Str = "-"
    else
        list.sort(Kinds, Sorted),
        Tiles = list.map((func(K) = tile(K, plain)), Sorted),
        format_sorted_tiles(Tiles, Chars),
        Str = string.from_char_list(Chars)
    ).

next_dora(num(S, N)) = num(S, ( if N = 9 then 1 else N + 1 )).
next_dora(wind(east)) = wind(south).
next_dora(wind(south)) = wind(west).
next_dora(wind(west)) = wind(north).
next_dora(wind(north)) = wind(east).
next_dora(dragon(haku)) = dragon(hatsu).
next_dora(dragon(hatsu)) = dragon(chun).
next_dora(dragon(chun)) = dragon(haku).

is_terminal(num(_, 1)).
is_terminal(num(_, 9)).

is_honor(wind(_)).
is_honor(dragon(_)).

is_yaochuu(K) :-
    ( is_terminal(K) ; is_honor(K) ).

is_simple(num(_, N)) :-
    N >= 2,
    N =< 8.

is_green(num(s, 2)).
is_green(num(s, 3)).
is_green(num(s, 4)).
is_green(num(s, 6)).
is_green(num(s, 8)).
is_green(dragon(hatsu)).

is_dragon(dragon(_)).

is_wind(wind(_)).

is_closed_hand([]).
is_closed_hand([M | Ms]) :-
    M ^ meld_type = ankan,
    is_closed_hand(Ms).

is_kan_meld(M) :-
    MT = M ^ meld_type,
    ( MT = daiminkan ; MT = shouminkan ; MT = ankan ).

hand_to_kind_bag(Tiles) =
    bag.from_list(list.map((func(T) = T ^ kind), Tiles)).

all_tiles_kind_bag(Hand, Melds) =
    hand_to_kind_bag(all_physical_tiles(Hand, Melds)).

all_physical_tiles(Hand, Melds) =
    list.append(Hand, list.condense(list.map((func(M) = M ^ meld_tiles), Melds))).
