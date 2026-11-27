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
        map.from_assoc_list(Pairs, Req)
    then
        ( if dispatch(Op, Req, Body0) then
            Body = Body0
        else
            Body = "error=bad_input"
        )
    else
        Body = "error=bad_input"
    ).

:- pred parse_kv(string::in, pair(string, string)::out) is semidet.
parse_kv(S, K - V) :-
    string.sub_string_search(S, "=", I),
    string.split(S, I, K, EqV),
    string.remove_prefix("=", EqV, V).

:- pred dispatch(string::in, request::in, string::out) is semidet.
dispatch("agari", R, Body) :-
    concealed_and_melds(R, Hand, Melds),
    Forms = agari_forms(kind_bag(Hand), list.length(Melds)),
    (
        Forms = [],
        Body = "win=0"
    ;
        Forms = [_ | _],
        Body = "win=1 forms=" ++ string.join_list(";", Forms)
    ).
dispatch("shanten", R, Body) :-
    concealed_and_melds(R, Hand, Melds),
    N = list.length(Melds),
    shanten(Std, Chiitoi, Kokushi) = shanten(kind_bag(Hand), N),
    ( if N = 0 then
        Min = int.min(Std, int.min(Chiitoi, Kokushi)),
        C = int_to_string(Chiitoi),
        K = int_to_string(Kokushi)
    else
        Min = Std,
        C = "x",
        K = "x"
    ),
    Body = string.format("std=%d chiitoi=%s kokushi=%s min=%d",
        [i(Std), s(C), s(K), i(Min)]).
dispatch("waits", R, Body) :-
    concealed_and_melds(R, Hand, Melds),
    B = kind_bag(Hand),
    Visible = bag.union(B,
        bag.from_list(list.condense(list.map(meld_kinds, Melds)))),
    waits(S, Tiles, Count) = waits(B, Visible, list.length(Melds)),
    Body = string.format("shanten=%d tiles=%s count=%d",
        [i(S), s(kinds_to_string(Tiles)), i(Count)]).
dispatch("score", R, Body) :-
    concealed_and_melds(R, Hand, Melds),
    map.search(R, "win", WinS), parse_tile(WinS, Win),
    map.search(R, "by", ByS),
    ( ByS = "tsumo", By = tsumo
    ; ByS = "ron", By = ron
    ),
    situation(R, Sit),
    Body = outcome_to_string(evaluate(score_request(Hand, Melds, Win, By,
        Sit))).
dispatch("legal", R, Body) :-
    concealed_and_melds(R, Hand, Melds),
    situation(R, Sit),
    ( if map.search(R, "draw", DrawS) then
        parse_tile(DrawS, Draw),
        Event = draw(Draw)
    else if map.search(R, "discard", DiscS) then
        parse_tile(DiscS, Disc),
        map.search(R, "from", FromS),
        parse_from(FromS, From),
        Event = discard(Disc, From)
    else
        map.search(R, "called", CalledS),
        parse_meld(CalledS, Called),
        map.search(R, "took", TookS),
        parse_tile(TookS, Took),
        Event = called(Called, Took)
    ),
    int_key(R, "wall", 70, Wall),
    int_key(R, "kans", 0, Kans),
    bool_key(R, "riichi", InRiichi),
    bool_key(R, "furiten", Furiten),
    bool_key(R, "first", First),
    Actions = actions(legal_request(Hand, Melds, Event, Sit, InRiichi,
        Furiten, Wall, First, Kans)),
    Body = "actions=" ++ string.join_list(",", Actions).

:- pred concealed_and_melds(request::in, list(tile)::out, list(meld)::out)
    is semidet.
concealed_and_melds(R, Hand, Melds) :-
    map.search(R, "hand", HandS),
    parse_tiles(HandS, Hand),
    ( if map.search(R, "melds", MeldsS) then
        parse_melds(MeldsS, Melds)
    else
        Melds = []
    ).

:- pred situation(request::in, situation::out) is semidet.
situation(R, situation(Seat, Round, Dora, Ura, Honba, Flags)) :-
    wind_key(R, "seat", Seat),
    wind_key(R, "round", Round),
    tiles_key(R, "dora", Dora),
    tiles_key(R, "ura", Ura),
    int_key(R, "honba", 0, Honba),
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

:- pred int_key(request::in, string::in, int::in, int::out) is semidet.
int_key(R, Key, Default, N) :-
    ( if map.search(R, Key, S) then string.to_int(S, N) else N = Default ).

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
