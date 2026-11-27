:- module mj.
:- interface.
:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.
:- import_module actions, char, int, list, map, scoring, set, shape, string, tiles.

:- type fields == map(string, string).

main(!IO) :- serve(!IO).

:- pred serve(io::di, io::uo) is det.
serve(!IO) :-
    io.read_line_as_string(Read, !IO),
    ( Read = ok(Line),
        io.write_string(response(string.strip(Line)) ++ "\n", !IO),
        serve(!IO)
    ; Read = eof
    ; Read = error(_), io.set_exit_status(1, !IO)
    ).

:- func response(string) = string.
response(Line) = Response :-
    ( if string.split_at_char(' ', Line) = [Id | Tail], Id \= "" then
        ( if Tail = [Op | Tokens],
            list.foldl(field, Tokens, map.init, Fields),
            map.search(Fields, "hand", HandText), parse_tiles(HandText, Hand),
            parse_melds(get(Fields, "melds", "-"), Melds),
            list.length(Melds) =< 4,
            run(Op, Fields, Hand, Melds, Body)
          then Response = Id ++ " " ++ Body
          else Response = Id ++ " error=bad_input"
        )
      else Response = "? error=bad_input"
    ).

:- pred field(string::in, fields::in, fields::out) is semidet.
field(Token, Map, Out) :-
    string.split_at_char('=', Token) = [Key, Value],
    map.insert(Key, Value, Map, Out).

:- func get(fields, string, string) = string.
get(Fs, K, Default) = (if map.search(Fs, K, V) then V else Default).

:- pred run(string::in, fields::in, list(tile)::in, list(meld)::in, string::out)
    is semidet.
run("agari", _, Hand, Melds, Body) :-
    Forms = forms(kinds(Hand), list.length(Melds)),
    ( if Forms = [] then Body = "win=0"
      else
        Printed = list.sort_and_remove_dups(list.map(render_form, Forms)),
        Body = "win=1 forms=" ++ string.join_list(";", Printed)
    ).
run("shanten", _, Hand, Melds, Body) :-
    N = list.length(Melds),
    Size = list.length(Hand),
    (Size = 13 - 3 * N ; Size = 14 - 3 * N),
    shanten(kinds(Hand), N) = distances(Std, Pairs, Orphans, Min),
    Body = "std=" ++ int_to_string(Std) ++
        " chiitoi=" ++ (if Melds = [] then int_to_string(Pairs) else "x") ++
        " kokushi=" ++ (if Melds = [] then int_to_string(Orphans) else "x") ++
        " min=" ++ int_to_string(Min).
run("waits", _, Hand, Melds, Body) :-
    list.length(Hand) = 13 - 3 * list.length(Melds),
    improvements(Hand, Melds, Dist, Waits, Count),
    Body = "shanten=" ++ int_to_string(Dist) ++
        " tiles=" ++ render_tiles(list.map((func(K) = tile(K, plain)), Waits)) ++
        " count=" ++ int_to_string(Count).
run("score", Fs, Hand, Melds, Body) :-
    parse_context(Fs, C),
    map.search(Fs, "win", WinText), parse_tile(WinText, Win),
    map.search(Fs, "by", Method), parse_method(Method, By),
    Body = render_score(score(Hand, Melds, Win, By, C)).
run("legal", Fs, Hand, Melds, Body) :-
    parse_context(Fs, C), parse_turn(Fs, Turn),
    DrawSize = (if Turn = called(_, _) then 14 else 13),
    list.length(Hand) = DrawSize - 3 * list.length(Melds),
    string.to_int(get(Fs, "wall", "70"), Wall),
    string.to_int(get(Fs, "kans", "0"), Kans),
    Riichi = (if get(Fs, "riichi", "0") = "1" then in_riichi else free),
    Furiten = (if get(Fs, "furiten", "0") = "1" then furiten else clear),
    First = (if get(Fs, "first", "0") = "1" then first_turn else later),
    Actions = legal(Hand, Melds, Turn, table(Riichi, Furiten, First, Wall, Kans), C),
    Actions = [_ | _],
    Body = "actions=" ++ string.join_list(",", Actions).

:- pred parse_context(fields::in, context::out) is semidet.
parse_context(Fs, context(Seat, Round, Flags, kinds(Dora), kinds(Ura), Honba)) :-
    parse_wind(get(Fs, "seat", "E"), Seat),
    parse_wind(get(Fs, "round", "E"), Round),
    FlagText = get(Fs, "flags", "-"),
    Flags = (if FlagText = "-" then set.init
        else set.from_list(string.split_at_char(',', FlagText))),
    parse_tiles(get(Fs, "dora", "-"), Dora),
    parse_tiles(get(Fs, "ura", "-"), Ura),
    string.to_int(get(Fs, "honba", "0"), Honba).

:- pred parse_method(string::in, method::out) is semidet.
parse_method("ron", ron).
parse_method("tsumo", tsumo).

:- pred parse_turn(fields::in, turn::out) is semidet.
parse_turn(Fs, Turn) :-
    ( if map.search(Fs, "draw", Draw) then
        parse_tile(Draw, Tile), Turn = drew(Tile)
      else if map.search(Fs, "discard", Discard) then
        parse_tile(Discard, Tile),
        map.search(Fs, "from", FromText), parse_source(FromText, From),
        Turn = discarded(Tile, From)
      else
        map.search(Fs, "called", Call), parse_meld(Call, Meld),
        map.search(Fs, "took", Took), parse_tile(Took, Tile),
        Turn = called(Meld, Tile)
    ).

:- pred parse_source(string::in, source::out) is semidet.
parse_source("kamicha", left).
parse_source("toimen", across).
parse_source("shimocha", right).
