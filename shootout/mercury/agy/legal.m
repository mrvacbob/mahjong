:- module legal.
:- interface.

:- import_module bool.
:- import_module list.
:- import_module score.
:- import_module tiles.

:- type seat_rel
    --->    kamicha
    ;       toimen
    ;       shimocha.

:- type turn_state
    --->    turn_draw(tile)
    ;       turn_discard(tile, seat_rel)
    ;       turn_called(meld, tile).

:- type legal_req
    --->    legal_req(
                l_hand    :: list(tile),
                l_melds   :: list(meld),
                l_ctx     :: score_context,
                l_turn    :: turn_state,
                l_riichi  :: bool,
                l_furiten :: bool,
                l_wall    :: int,
                l_first   :: bool,
                l_kans    :: int
            ).

:- pred parse_seat_rel(string::in, seat_rel::out) is semidet.

:- func legal_actions(legal_req) = list(string).
:- func format_legal_response(legal_req) = string.

:- implementation.

:- import_module agari.
:- import_module assoc_list.
:- import_module bag.
:- import_module int.
:- import_module pair.
:- import_module set.
:- import_module shanten.
:- import_module string.

parse_seat_rel("kamicha", kamicha).
parse_seat_rel("toimen", toimen).
parse_seat_rel("shimocha", shimocha).

format_legal_response(Req) =
    "actions=" ++ string.join_list(",", legal_actions(Req)).

legal_actions(Req) = Actions :-
    Turn = Req ^ l_turn,
    (
        Turn = turn_called(CalledMeld, TookTile),
        RawActions = called_actions(Req ^ l_hand, CalledMeld, TookTile)
    ;
        Turn = turn_draw(DrawTile),
        RawActions = draw_actions(Req, DrawTile)
    ;
        Turn = turn_discard(DiscTile, From),
        RawActions = discard_actions(Req, DiscTile, From)
    ),
    Actions = list.sort_and_remove_dups(RawActions).

% ============================================================================
% Kuikae
% ============================================================================

:- func kuikae_forbidden(meld, tile_kind) = set(tile_kind).

kuikae_forbidden(meld(MType, Tiles), TookKind) = Forbid :-
    ( if MType = chi then
        Kinds = list.sort(list.map((func(T) = T ^ kind), Tiles)),
        ( if Kinds = [num(S, R1), num(S, R2), num(S, R3)] then
            ( if TookKind = num(S, R1), R1 + 3 =< 9 then
                Forbid = set.list_to_set([TookKind, num(S, R1 + 3)])
            else if TookKind = num(S, R3), R3 - 3 >= 1 then
                Forbid = set.list_to_set([TookKind, num(S, R3 - 3)])
            else if TookKind = num(S, R2) then
                Forbid = set.make_singleton_set(TookKind)
            else
                Forbid = set.make_singleton_set(TookKind)
            )
        else
            Forbid = set.make_singleton_set(TookKind)
        )
    else
        Forbid = set.make_singleton_set(TookKind)
    ).

:- func called_actions(list(tile), meld, tile) = list(string).

called_actions(Hand, CalledMeld, TookTile) = Actions :-
    Forbid = kuikae_forbidden(CalledMeld, TookTile ^ kind),
    DistinctTiles = list.sort_and_remove_dups(Hand),
    list.filter_map(
        (pred(T::in, Act::out) is semidet :-
            not set.member(T ^ kind, Forbid),
            Act = "discard:" ++ format_tile(T)
        ),
        DistinctTiles, Actions).

% ============================================================================
% Own Draw
% ============================================================================

:- func draw_actions(legal_req, tile) = list(string).

draw_actions(Req, DrawTile) = Actions :-
    Hand = Req ^ l_hand,
    Melds = Req ^ l_melds,
    Riichi = Req ^ l_riichi,
    Wall = Req ^ l_wall,
    First = Req ^ l_first,
    Kans = Req ^ l_kans,
    FullHand = [DrawTile | Hand],
    DistinctFull = list.sort_and_remove_dups(FullHand),
    Ctx = ctx_with_riichi(Req ^ l_ctx, Riichi),

    % 1. Discards
    Discards =
        ( if Riichi = yes then
            ["discard:" ++ format_tile(DrawTile)]
        else
            list.map((func(T) = "discard:" ++ format_tile(T)), DistinctFull)
        ),

    % 2. Tsumo
    Tsumo =
        ( if score.can_win_with_yaku(Hand, Melds, DrawTile, tsumo, Ctx) then
            ["tsumo"]
        else
            []
        ),

    % 3. Riichi
    ( if Riichi = no, is_closed_hand(Melds), Wall >= 4 then
        list.filter_map(
            (pred(T::in, Act::out) is semidet :-
                list.delete_first(FullHand, T, RemHand),
                W = shanten.compute_waits(RemHand, Melds),
                W ^ wait_shanten = 0,
                W ^ wait_count > 0,
                Act = "riichi:" ++ format_tile(T)
            ),
            DistinctFull, RiichiActs)
    else
        RiichiActs = []
    ),

    % 4. Ankan
    ( if Wall >= 1, Kans < 4 then
        FullBag = hand_to_kind_bag(FullHand),
        bag.to_assoc_list(FullBag, Assoc),
        list.filter_map(
            (pred((K - C)::in, Act::out) is semidet :-
                C = 4,
                ( if Riichi = yes then
                    K = DrawTile ^ kind,
                    WaitsBefore = shanten.structural_waits(
                        hand_to_kind_bag(Hand), Melds),
                    BagAfter = bag.delete_all(FullBag, K),
                    AnkanMeld = meld(ankan, [
                        tile(K, plain), tile(K, plain),
                        tile(K, plain), tile(K, plain)]),
                    WaitsAfter = shanten.structural_waits(
                        BagAfter, [AnkanMeld | Melds]),
                    WaitsBefore = WaitsAfter
                else
                    true
                ),
                Act = "ankan:" ++ format_tile_kind(K)
            ),
            Assoc, AnkanActs)
    else
        AnkanActs = []
    ),

    % 5. Kakan
    ( if Riichi = no, Wall >= 1, Kans < 4 then
        list.filter_map(
            (pred(M::in, K::out) is semidet :-
                M ^ meld_type = pon,
                M ^ meld_tiles = [T0 | _],
                K = T0 ^ kind
            ), Melds, PonKindList),
        PonKinds = set.list_to_set(PonKindList),
        list.filter_map(
            (pred(T::in, Act::out) is semidet :-
                set.member(T ^ kind, PonKinds),
                Act = "kakan:" ++ format_tile(T)
            ),
            DistinctFull, KakanActs)
    else
        KakanActs = []
    ),

    % 6. Kyuushu
    ( if First = yes then
        list.filter_map(
            (pred(T::in, K::out) is semidet :-
                K = T ^ kind,
                is_yaochuu(K)
            ), FullHand, YaoList),
        YaoSet = set.list_to_set(YaoList),
        ( if set.count(YaoSet) >= 9 then
            KyuushuActs = ["kyuushu"]
        else
            KyuushuActs = []
        )
    else
        KyuushuActs = []
    ),

    Actions = Discards ++ Tsumo ++ RiichiActs ++ AnkanActs ++ KakanActs ++
              KyuushuActs.

% ============================================================================
% Opponent Discard / Robbing Kan
% ============================================================================

:- func discard_actions(legal_req, tile, seat_rel) = list(string).

discard_actions(Req, DiscTile, From) = Actions :-
    Hand = Req ^ l_hand,
    Melds = Req ^ l_melds,
    Riichi = Req ^ l_riichi,
    Furiten = Req ^ l_furiten,
    Wall = Req ^ l_wall,
    Kans = Req ^ l_kans,
    Ctx = ctx_with_riichi(Req ^ l_ctx, Riichi),
    Flags = Ctx ^ flags,

    ( if set.member(flag_ankan_rob, Flags) then
        Ron =
            ( if Furiten = no,
                 FullBag = bag.insert(hand_to_kind_bag(Hand), DiscTile ^ kind),
                 agari.is_kokushi(FullBag, Melds)
            then ["ron"] else [] ),
        Actions = ["pass" | Ron]
    else if set.member(flag_chankan, Flags) then
        Ron =
            ( if Furiten = no,
                 score.can_win_with_yaku(Hand, Melds, DiscTile, ron, Ctx)
            then ["ron"] else [] ),
        Actions = ["pass" | Ron]
    else
        Ron =
            ( if Furiten = no,
                 score.can_win_with_yaku(Hand, Melds, DiscTile, ron, Ctx)
            then ["ron"] else [] ),
        ( if Riichi = no, Wall >= 1 then
            PonActs = pon_actions(Hand, DiscTile ^ kind),
            KanActs = kan_actions(Hand, DiscTile ^ kind, Kans),
            ChiActs = ( if From = kamicha then chi_actions(Hand, DiscTile) else [] ),
            Calls = PonActs ++ KanActs ++ ChiActs
        else
            Calls = []
        ),
        Actions = ["pass" | Ron ++ Calls]
    ).

:- func pon_actions(list(tile), tile_kind) = list(string).

pon_actions(Hand, K) = Acts :-
    Matching = list.filter((pred(T::in) is semidet :- T ^ kind = K), Hand),
    Reds = list.filter((pred(T::in) is semidet :- T ^ is_red = red), Matching),
    Plains = list.filter((pred(T::in) is semidet :- T ^ is_red = plain), Matching),
    RedAct =
        ( if Reds = [R | _], Plains = [P | _] then
            ["pon:" ++ format_tiles([R, P])]
        else [] ),
    PlainAct =
        ( if Plains = [P1, P2 | _] then
            ["pon:" ++ format_tiles([P1, P2])]
        else [] ),
    Acts = RedAct ++ PlainAct.

:- func kan_actions(list(tile), tile_kind, int) = list(string).

kan_actions(Hand, K, Kans) = Acts :-
    ( if Kans < 4,
         Matching = list.filter((pred(T::in) is semidet :- T ^ kind = K), Hand),
         list.length(Matching) = 3
    then
        Acts = ["kan:" ++ format_tile_kind(K)]
    else
        Acts = []
    ).

:- func chi_actions(list(tile), tile) = list(string).

chi_actions(Hand, DiscTile) = Acts :-
    ( if DiscTile ^ kind = num(S, D) then
        Windows = [
            {D - 2, D - 1},
            {D - 1, D + 1},
            {D + 1, D + 2}
        ],
        list.foldl(
            (pred({R1, R2}::in, Acc0::in, Acc::out) is det :-
                ( if R1 >= 1, R1 =< 9, R2 >= 1, R2 =< 9 then
                    Ts1 = distinct_tiles_of_kind(Hand, num(S, R1)),
                    Ts2 = distinct_tiles_of_kind(Hand, num(S, R2)),
                    PairActs = chi_pair_actions(Hand, DiscTile, Ts1, Ts2),
                    Acc = Acc0 ++ PairActs
                else
                    Acc = Acc0
                )
            ),
            Windows, [], Acts)
    else
        Acts = []
    ).

:- func distinct_tiles_of_kind(list(tile), tile_kind) = list(tile).

distinct_tiles_of_kind(Hand, K) =
    list.sort_and_remove_dups(
        list.filter((pred(T::in) is semidet :- T ^ kind = K), Hand)).

:- func chi_pair_actions(list(tile), tile, list(tile), list(tile)) = list(string).

chi_pair_actions(Hand, DiscTile, Ts1, Ts2) =
    list.condense(list.map(
        (func(T1) = Acts1 :-
            list.filter_map(
                (pred(T2::in, Act::out) is semidet :-
                    list.delete_first(Hand, T1, Hand1),
                    list.delete_first(Hand1, T2, RemHand),
                    ChiMeld = meld(chi, [DiscTile, T1, T2]),
                    Forbid = kuikae_forbidden(ChiMeld, DiscTile ^ kind),
                    list.any_true(
                        (pred(U::in) is semidet :- not set.member(U ^ kind, Forbid)),
                        RemHand),
                    Act = "chi:" ++ format_tiles([T1, T2])
                ), Ts2, Acts1)
        ),
        Ts1)).

:- func ctx_with_riichi(score_context, bool) = score_context.

ctx_with_riichi(Ctx, Riichi) =
    ( if Riichi = yes then
        Ctx ^ flags := set.insert(Ctx ^ flags, flag_riichi)
    else
        Ctx
    ).
