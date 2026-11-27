%---------------------------------------------------------------------------%
% mj.m: the runner.  One request per line on stdin, one response per line.
%---------------------------------------------------------------------------%
:- module mj.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is cc_multi.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module hand.
:- import_module legal.
:- import_module score.
:- import_module tile.
:- import_module bag.
:- import_module bool.
:- import_module exception.
:- import_module int.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module string.

main(!IO) :-
    io.read_line_as_string(Res, !IO),
    (
        Res = ok(Line0),
        Line = string.rstrip(Line0),
        ( if Line = "" then
            true
        else
            respond(Line, Out),
            io.write_string(Out, !IO),
            io.nl(!IO)
        ),
        main(!IO)
    ;
        Res = eof
    ;
        Res = error(_)
    ).

    % Never crash: an exception inside an op becomes an error answer.
:- pred respond(string::in, string::out) is cc_multi.
respond(Line, Out) :-
    Words = string.split_at_char(' ', Line),
    ( if Words = [Id0 | _] then Id = Id0 else Id = "?" ),
    try((pred(Body0::out) is det :- Body0 = handle(Words)), Result),
    (
        Result = succeeded(Body)
    ;
        Result = exception(_),
        Body = "error=internal"
    ),
    Out = Id ++ " " ++ Body.

:- type request == map(string, string).

:- func handle(list(string)) = string.
handle(Words) = Body :-
    ( if
        Words = [_, Op | KVs],
        list.map(parse_kv, KVs, Pairs),
        list.foldl((pred(K - V::in, M0::in, M::out) is semidet :-
            map.insert(K, V, M0, M)), Pairs, map.init, Req),  % no repeats
        dispatch(Op, Req, Body0)
    then
        Body = Body0
    else
        Body = "error=bad_input"
    ).

:- pred parse_kv(string::in, pair(string, string)::out) is semidet.
parse_kv(S, K - V) :-
    string.split_at_char('=', S) = [K, V].

    % Each op checks its input here, at the boundary: hand size, tiles
    % that can exist, numbers in range, exactly one legal trigger.  The
    % core then assumes a well-formed request.
:- pred dispatch(string::in, request::in, string::out) is semidet.
dispatch("agari", R, Body) :-
    concealed_and_melds(R, [14], [], Hand, Melds),
    Forms = agari_forms(kind_bag(Hand), list.length(Melds)),
    (
        Forms = [],
        Body = "win=0"
    ;
        Forms = [_ | _],
        Body = "win=1 forms=" ++ string.join_list(";", Forms)
    ).
dispatch("shanten", R, Body) :-
    concealed_and_melds(R, [13, 14], [], Hand, Melds),
    S = shanten(kind_bag(Hand), list.length(Melds)),
    (
        S = with_melds(_),
        C = "x",
        K = "x"
    ;
        S = no_melds(_, Chiitoi, Kokushi),
        C = int_to_string(Chiitoi),
        K = int_to_string(Kokushi)
    ),
    Body = string.format("std=%d chiitoi=%s kokushi=%s min=%d",
        [i(std(S)), s(C), s(K), i(min_of(S))]).
dispatch("waits", R, Body) :-
    concealed_and_melds(R, [13], [], Hand, Melds),
    B = kind_bag(Hand),
    Visible = bag.union(B, kind_bag(meld_tiles(Melds))),
    waits(S, Tiles, Count) = waits(B, Visible, list.length(Melds)),
    Body = string.format("shanten=%d tiles=%s count=%d",
        [i(S), s(kinds_to_string(Tiles)), i(Count)]).
dispatch("score", R, Body) :-
    tile_key(R, "win", Win),
    concealed_and_melds(R, [13], [Win], Hand, Melds),
    map.search(R, "by", ByS),
    ( ByS = "tsumo", By = tsumo
    ; ByS = "ron", By = ron
    ),
    situation(R, Sit),
    Body = outcome_to_string(evaluate(score_request(Hand, Melds, Win, By,
        Sit))).
dispatch("legal", R, Body) :-
    list.filter(map.contains(R), ["draw", "discard", "called"], [Key]),
    (
        Key = "draw",
        tile_key(R, "draw", Draw),
        concealed_and_melds(R, [13], [Draw], Hand, Melds),
        Trigger = draw(Draw)
    ;
        Key = "discard",
        tile_key(R, "discard", Disc),
        map.search(R, "from", FromS),
        parse_from(FromS, From),
        concealed_and_melds(R, [13], [Disc], Hand, Melds),
        Trigger = discard(Disc, From)
    ;
        Key = "called",
        map.search(R, "called", CalledS),
        parse_meld(CalledS, Called),
        tile_key(R, "took", Took),
        concealed_and_melds(R, [14], [], Hand, Melds),
        list.member(Called, Melds),
        list.member(Took, Called ^ mtiles),
        Trigger = called(Called, Took)
    ),
    situation(R, Sit),
    int_key(R, "wall", 70, 0, 70, Wall),
    int_key(R, "kans", 0, 0, 4, Kans),
    bool_key(R, "riichi", InRiichi),
    bool_key(R, "furiten", Furiten),
    bool_key(R, "first", First),
    Actions = actions(legal_request(Hand, Melds, Trigger, Sit, InRiichi,
        Furiten, Wall, First, Kans)),
    Body = "actions=" ++ string.join_list(",", Actions).

    % The hand and melds, with Sizes the allowed hand sizes for no melds
    % (each meld takes three).  Extra tiles (a win or draw) must exist
    % alongside them.
:- pred concealed_and_melds(request::in, list(int)::in, list(tile)::in,
    list(tile)::out, list(meld)::out) is semidet.
concealed_and_melds(R, Sizes, Extra, Hand, Melds) :-
    map.search(R, "hand", HandS),
    parse_tiles(HandS, Hand),
    ( if map.search(R, "melds", MeldsS) then
        parse_melds(MeldsS, Melds)
    else
        Melds = []
    ),
    list.member(list.length(Hand) + 3 * list.length(Melds), Sizes),
    physically_possible(Extra ++ Hand ++ meld_tiles(Melds)).

:- pred tile_key(request::in, string::in, tile::out) is semidet.
tile_key(R, Key, T) :-
    map.search(R, Key, S),
    parse_tile(S, T).

:- pred situation(request::in, situation::out) is semidet.
situation(R, situation(Seat, Round, Dora, Ura, Honba, Flags)) :-
    wind_key(R, "seat", Seat),
    wind_key(R, "round", Round),
    tiles_key(R, "dora", Dora),
    tiles_key(R, "ura", Ura),
    int_key(R, "honba", 0, 0, 999, Honba),
    ( if map.search(R, "flags", FlagsS), FlagsS \= "-" then
        list.map(parse_flag,
            list.negated_filter(unify(""), string.split_at_char(',', FlagsS)),
            Flags)
    else
        Flags = []
    ).

:- pred wind_key(request::in, string::in, kind::out) is semidet.
wind_key(R, Key, Wind) :-
    ( if map.search(R, Key, S) then parse_wind(S, Wind) else Wind = east ).

:- pred tiles_key(request::in, string::in, list(tile)::out) is semidet.
tiles_key(R, Key, Tiles) :-
    ( if map.search(R, Key, S) then parse_tiles(S, Tiles) else Tiles = [] ).

    % int_key(R, Key, Default, Min, Max, N)
:- pred int_key(request::in, string::in, int::in, int::in, int::in, int::out)
    is semidet.
int_key(R, Key, Default, Min, Max, N) :-
    ( if map.search(R, Key, S) then string.to_int(S, N) else N = Default ),
    Min =< N, N =< Max.

:- pred bool_key(request::in, string::in, bool::out) is semidet.
bool_key(R, Key, B) :-
    ( if map.search(R, Key, S) then
        ( S = "1", B = yes
        ; S = "0", B = no
        )
    else
        B = no
    ).

:- pred parse_from(string::in, from::out) is semidet.
parse_from("kamicha", kamicha).
parse_from("toimen", toimen).
parse_from("shimocha", shimocha).

%---------------------------------------------------------------------------%
:- end_module mj.
%---------------------------------------------------------------------------%
