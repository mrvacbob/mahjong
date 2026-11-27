:- module mj.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- import_module agari.
:- import_module bool.
:- import_module legal.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module score.
:- import_module set.
:- import_module shanten.
:- import_module string.
:- import_module tiles.

main(!IO) :-
    loop(!IO).

:- pred loop(io::di, io::uo) is det.

loop(!IO) :-
    io.read_line_as_string(Res, !IO),
    (
        Res = eof
    ;
        Res = error(_)
    ;
        Res = ok(RawLine),
        Line = string.strip(RawLine),
        ( if Line = "" then
            true
        else
            Resp = handle_line(Line),
            io.write_string(Resp, !IO),
            io.nl(!IO)
        ),
        loop(!IO)
    ).

:- func handle_line(string) = string.

handle_line(Line) = Resp :-
    Tokens = string.words(Line),
    ( if Tokens = [Id, Op | KVs] then
        ( if parse_kvs(KVs, map.init, KVMap) then
            Body = dispatch(Op, KVMap),
            Resp = Id ++ " " ++ Body
        else
            Resp = Id ++ " error=bad_input"
        )
    else if Tokens = [Id] then
        Resp = Id ++ " error=bad_input"
    else
        Resp = "? error=bad_input"
    ).

:- pred parse_kvs(list(string)::in, map(string, string)::in,
    map(string, string)::out) is semidet.

parse_kvs([], !Map).
parse_kvs([Tok | Toks], !Map) :-
    string.sub_string_search(Tok, "=", Idx),
    string.split(Tok, Idx, Key, Rest),
    string.first_char(Rest, '=', Val),
    map.set(Key, Val, !Map),
    parse_kvs(Toks, !Map).

:- func dispatch(string, map(string, string)) = string.

dispatch(Op, KV) = Body :-
    ( if Op = "agari" then
        ( if parse_hand_melds(KV, Hand, Melds) then
            Body = agari.format_agari_response(hand_to_kind_bag(Hand), Melds)
        else
            Body = "error=bad_input"
        )
    else if Op = "shanten" then
        ( if parse_hand_melds(KV, Hand, Melds) then
            Sh = shanten.compute_shanten(hand_to_kind_bag(Hand), Melds),
            Body = shanten.format_shanten_response(Sh)
        else
            Body = "error=bad_input"
        )
    else if Op = "waits" then
        ( if parse_hand_melds(KV, Hand, Melds) then
            W = shanten.compute_waits(Hand, Melds),
            Body = shanten.format_waits_response(W)
        else
            Body = "error=bad_input"
        )
    else if Op = "score" then
        ( if parse_hand_melds(KV, Hand, Melds),
             map.search(KV, "win", WinStr),
             parse_tile(WinStr, WinTile),
             map.search(KV, "by", ByStr),
             parse_win_by(ByStr, By),
             parse_context(KV, Ctx)
        then
            score.eval_score(Hand, Melds, WinTile, By, Ctx, Outcome),
            Body = score.format_score_outcome(Outcome)
        else
            Body = "error=bad_input"
        )
    else if Op = "legal" then
        ( if parse_legal_req(KV, Req) then
            Body = legal.format_legal_response(Req)
        else
            Body = "error=bad_input"
        )
    else
        Body = "error=unknown_op"
    ).

:- pred parse_hand_melds(map(string, string)::in, list(tile)::out,
    list(meld)::out) is semidet.

parse_hand_melds(KV, Hand, Melds) :-
    map.search(KV, "hand", HandStr),
    parse_tile_list(HandStr, Hand),
    ( if map.search(KV, "melds", MeldsStr) then
        parse_melds(MeldsStr, Melds)
    else
        Melds = []
    ).

:- pred parse_context(map(string, string)::in, score_context::out) is semidet.

parse_context(KV, score_context(Seat, Round, Dora, Ura, Honba, Flags)) :-
    ( if map.search(KV, "seat", SeatStr) then
        parse_wind(SeatStr, Seat)
    else
        Seat = east
    ),
    ( if map.search(KV, "round", RoundStr) then
        parse_wind(RoundStr, Round)
    else
        Round = east
    ),
    ( if map.search(KV, "dora", DoraStr) then
        parse_tile_list(DoraStr, DoraTiles),
        Dora = list.map((func(T) = T ^ kind), DoraTiles)
    else
        Dora = []
    ),
    ( if map.search(KV, "ura", UraStr) then
        parse_tile_list(UraStr, UraTiles),
        Ura = list.map((func(T) = T ^ kind), UraTiles)
    else
        Ura = []
    ),
    ( if map.search(KV, "honba", HonbaStr) then
        string.to_int(HonbaStr, Honba)
    else
        Honba = 0
    ),
    ( if map.search(KV, "flags", FlagsStr) then
        parse_flags(FlagsStr, Flags)
    else
        Flags = set.init
    ).

:- pred parse_bool_key(map(string, string)::in, string::in, bool::in,
    bool::out) is semidet.

parse_bool_key(KV, Key, Default, Val) :-
    ( if map.search(KV, Key, Str) then
        ( if Str = "1" then Val = yes
        else if Str = "0" then Val = no
        else fail
        )
    else
        Val = Default
    ).

:- pred parse_int_key(map(string, string)::in, string::in, int::in,
    int::out) is semidet.

parse_int_key(KV, Key, Default, Val) :-
    ( if map.search(KV, Key, Str) then
        string.to_int(Str, Val)
    else
        Val = Default
    ).

:- pred parse_legal_req(map(string, string)::in, legal_req::out) is semidet.

parse_legal_req(KV, Req) :-
    parse_hand_melds(KV, Hand, Melds),
    parse_context(KV, Ctx),
    parse_bool_key(KV, "riichi", no, Riichi),
    parse_bool_key(KV, "furiten", no, Furiten),
    parse_int_key(KV, "wall", 70, Wall),
    parse_bool_key(KV, "first", no, First),
    parse_int_key(KV, "kans", 0, Kans),
    ( if map.search(KV, "draw", DrawStr) then
        parse_tile(DrawStr, DrawTile),
        Turn = turn_draw(DrawTile)
    else if map.search(KV, "discard", DiscStr),
            map.search(KV, "from", FromStr) then
        parse_tile(DiscStr, DiscTile),
        parse_seat_rel(FromStr, From),
        Turn = turn_discard(DiscTile, From)
    else if map.search(KV, "called", CalledStr),
            map.search(KV, "took", TookStr) then
        parse_meld(CalledStr, CalledMeld),
        parse_tile(TookStr, TookTile),
        Turn = turn_called(CalledMeld, TookTile)
    else
        fail
    ),
    Req = legal_req(Hand, Melds, Ctx, Turn, Riichi, Furiten, Wall, First, Kans).
