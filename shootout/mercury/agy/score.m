:- module score.
:- interface.

:- import_module list.
:- import_module set.
:- import_module tiles.

:- type win_by
    --->    tsumo
    ;       ron.

:- type flag
    --->    flag_riichi
    ;       flag_double_riichi
    ;       flag_ippatsu
    ;       flag_haitei
    ;       flag_houtei
    ;       flag_rinshan
    ;       flag_chankan
    ;       flag_tenhou
    ;       flag_chiihou
    ;       flag_ankan_rob.

:- type score_context
    --->    score_context(
                seat  :: wind,
                round :: wind,
                dora  :: list(tile_kind),
                ura   :: list(tile_kind),
                honba :: int,
                flags :: set(flag)
            ).

:- type yaku_entry
    --->    yaku_entry(
                yaku_name :: string,
                yaku_val  :: int
            ).

:- type payment
    --->    pay_ron(int)
    ;       pay_all(int)
    ;       pay_tsumo(int, int).

:- type score_val
    --->    yakuman_score(
                ym_yaku  :: list(yaku_entry),
                ym_mult  :: int,
                ym_pay   :: payment,
                ym_total :: int
            )
    ;       ordinary_score(
                ord_yaku  :: list(yaku_entry),
                ord_han   :: int,
                ord_fu    :: int,
                ord_pay   :: payment,
                ord_total :: int
            ).

:- type score_outcome
    --->    score_ok(score_val)
    ;       score_not_agari
    ;       score_no_yaku.

:- pred parse_flag(string::in, flag::out) is semidet.
:- pred parse_flags(string::in, set(flag)::out) is semidet.
:- pred parse_win_by(string::in, win_by::out) is semidet.

:- pred eval_score(list(tile)::in, list(meld)::in, tile::in, win_by::in,
    score_context::in, score_outcome::out) is det.

:- pred can_win_with_yaku(list(tile)::in, list(meld)::in, tile::in, win_by::in,
    score_context::in) is semidet.

:- func format_score_outcome(score_outcome) = string.

:- implementation.

:- import_module agari.
:- import_module assoc_list.
:- import_module bag.
:- import_module bool.
:- import_module int.
:- import_module pair.
:- import_module solutions.
:- import_module string.

:- type is_open
    --->    open
    ;       closed.

:- type scored_group
    --->    sg_seq(num_suit, int, is_open)
    ;       sg_triplet(tile_kind, is_open)
    ;       sg_kan(tile_kind, is_open).

:- type wait_type
    --->    wait_ryanmen
    ;       wait_kanchan
    ;       wait_penchan
    ;       wait_tanki
    ;       wait_shanpon.

:- type hand_interp
    --->    interp_kokushi(bool)  % yes = 13-wait
    ;       interp_chiitoi
    ;       interp_std(tile_kind, list(scored_group), wait_type).

parse_flag("riichi", flag_riichi).
parse_flag("double_riichi", flag_double_riichi).
parse_flag("ippatsu", flag_ippatsu).
parse_flag("haitei", flag_haitei).
parse_flag("houtei", flag_houtei).
parse_flag("rinshan", flag_rinshan).
parse_flag("chankan", flag_chankan).
parse_flag("tenhou", flag_tenhou).
parse_flag("chiihou", flag_chiihou).
parse_flag("ankan_rob", flag_ankan_rob).

parse_flags(Str, FlagSet) :-
    ( if Str = "-" then
        FlagSet = set.init
    else
        Parts = string.split_at_char(',', Str),
        list.map(parse_flag, Parts, FlagList),
        FlagSet = set.list_to_set(FlagList)
    ).

parse_win_by("tsumo", tsumo).
parse_win_by("ron", ron).

can_win_with_yaku(Hand, Melds, WinTile, By, Ctx) :-
    eval_score(Hand, Melds, WinTile, By, Ctx, score_ok(_)).

eval_score(Hand, Melds, WinTile, By, Ctx, Outcome) :-
    FullHand = [WinTile | Hand],
    FullBag = hand_to_kind_bag(FullHand),
    ( if not agari.is_agari(FullBag, Melds) then
        Outcome = score_not_agari
    else
        AllPhys = all_physical_tiles(FullHand, Melds),
        AllBag = all_tiles_kind_bag(FullHand, Melds),
        solutions.solutions(
            (pred(SV::out) is nondet :-
                choose_win_split(Hand, WinTile, Ctx ^ flags, Hand13, Win1),
                enumerate_interp(Hand13, Melds, Win1, By, Interp),
                score_interp(Hand13, Melds, Win1, By, Ctx, AllPhys, AllBag,
                    Interp, SV)
            ),
            Scores),
        ( if Scores = [First | Rest] then
            Best = list.foldl(better_score, Rest, First),
            Outcome = score_ok(Best)
        else
            Outcome = score_no_yaku
        )
    ).

:- pred choose_win_split(list(tile)::in, tile::in, set(flag)::in,
    list(tile)::out, tile::out) is multi.

choose_win_split(Hand, WinTile, Flags, Hand13, Win1) :-
    ( if set.member(flag_tenhou, Flags) then
        FullHand = [WinTile | Hand],
        pick_distinct_kind_tile(FullHand, Win1, Hand13)
    else
        Hand13 = Hand,
        Win1 = WinTile
    ).

:- pred pick_distinct_kind_tile(list(tile)::in, tile::out, list(tile)::out)
    is multi.

pick_distinct_kind_tile(Tiles, Picked, Rest) :-
    Kinds = list.sort_and_remove_dups(list.map((func(T) = T ^ kind), Tiles)),
    ( if Kinds = [K0 | Ks] then
        ( K = K0 ; list.member(K, Ks) ),
        remove_one_of_kind(K, Tiles, Picked, Rest)
    else
        % Unreachable for 14-tile hands
        Picked = tile(wind(east), plain),
        Rest = []
    ).

:- pred remove_one_of_kind(tile_kind::in, list(tile)::in,
    tile::out, list(tile)::out) is det.

remove_one_of_kind(_, [], tile(wind(east), plain), []).
remove_one_of_kind(K, [T | Ts], Picked, Rest) :-
    ( if T ^ kind = K then
        Picked = T,
        Rest = Ts
    else
        remove_one_of_kind(K, Ts, Picked, Rest0),
        Rest = [T | Rest0]
    ).

:- pred enumerate_interp(list(tile)::in, list(meld)::in, tile::in, win_by::in,
    hand_interp::out) is nondet.

enumerate_interp(Hand13, Melds, WinTile, By, Interp) :-
    Hand13Bag = hand_to_kind_bag(Hand13),
    FullBag = bag.insert(Hand13Bag, WinTile ^ kind),
    (
        agari.is_kokushi(FullBag, Melds),
        Is13 = ( if bag.count_unique(Hand13Bag) = 13 then yes else no ),
        Interp = interp_kokushi(Is13)
    ;
        agari.is_chiitoi(FullBag, Melds),
        Interp = interp_chiitoi
    ;
        agari.decompose_std(FullBag, PairKind, ConcGroups),
        MeldGroups = list.map(meld_to_scored_group, Melds),
        assign_wait(PairKind, ConcGroups, WinTile ^ kind, By,
            ScoredConcGroups, WaitType),
        Interp = interp_std(PairKind, ScoredConcGroups ++ MeldGroups, WaitType)
    ).

:- func meld_to_scored_group(meld) = scored_group.

meld_to_scored_group(meld(MType, Tiles)) = SG :-
    Kinds = list.sort(list.map((func(T) = T ^ kind), Tiles)),
    ( if Kinds = [K0 | _] then
        (
            MType = chi,
            ( if K0 = num(S, N) then
                SG = sg_seq(S, N, open)
            else
                SG = sg_triplet(K0, open)
            )
        ;
            MType = pon,
            SG = sg_triplet(K0, open)
        ;
            MType = daiminkan,
            SG = sg_kan(K0, open)
        ;
            MType = shouminkan,
            SG = sg_kan(K0, open)
        ;
            MType = ankan,
            SG = sg_kan(K0, closed)
        )
    else
        SG = sg_triplet(wind(east), open)
    ).

:- pred assign_wait(tile_kind::in, list(concealed_group)::in, tile_kind::in,
    win_by::in, list(scored_group)::out, wait_type::out) is nondet.

assign_wait(PairKind, ConcGroups, WinKind, By, ScoredGroups, WaitType) :-
    (
        % 1. Tanki wait on pair
        PairKind = WinKind,
        WaitType = wait_tanki,
        ScoredGroups = list.map(concealed_to_closed_sg, ConcGroups)
    ;
        % 2. Wait on one of the concealed groups
        select_group(ConcGroups, Target, Others),
        OtherSGs = list.map(concealed_to_closed_sg, Others),
        (
            Target = triplet(K),
            K = WinKind,
            WaitType = wait_shanpon,
            Openness = ( if By = ron then open else closed ),
            ScoredGroups = [sg_triplet(K, Openness) | OtherSGs]
        ;
            Target = seq(S, Low),
            WinKind = num(S, R),
            R >= Low,
            R =< Low + 2,
            ( if R = Low + 1 then
                WaitType = wait_kanchan
            else if ( ( R = Low, Low = 7 ) ; ( R = Low + 2, Low = 1 ) ) then
                WaitType = wait_penchan
            else
                WaitType = wait_ryanmen
            ),
            ScoredGroups = [sg_seq(S, Low, closed) | OtherSGs]
        )
    ).

:- pred select_group(list(T)::in, T::out, list(T)::out) is nondet.

select_group([X | Xs], X, Xs).
select_group([X | Xs], Y, [X | Ys]) :-
    select_group(Xs, Y, Ys).

:- func concealed_to_closed_sg(concealed_group) = scored_group.

concealed_to_closed_sg(pair(K)) = sg_triplet(K, closed).
concealed_to_closed_sg(seq(S, N)) = sg_seq(S, N, closed).
concealed_to_closed_sg(triplet(K)) = sg_triplet(K, closed).

:- pred score_interp(list(tile)::in, list(meld)::in, tile::in, win_by::in,
    score_context::in, list(tile)::in, bag(tile_kind)::in,
    hand_interp::in, score_val::out) is semidet.

score_interp(Hand13, Melds, WinTile, By, Ctx, AllPhys, AllBag, Interp, SV) :-
    YakumanList = eval_yakuman(Hand13, Melds, WinTile, Ctx, AllBag, Interp),
    ( if YakumanList = [_ | _] then
        list.sort(compare_yaku, YakumanList, SortedYM),
        Mult = sum_yaku_vals(SortedYM),
        Basic = 8000 * Mult,
        compute_payment(Basic, Ctx ^ seat, By, Ctx ^ honba, Pay, Total),
        SV = yakuman_score(SortedYM, Mult, Pay, Total)
    else
        IsClosed = ( if is_closed_hand(Melds) then yes else no ),
        RealYaku = eval_standard_yaku(IsClosed, By, Ctx, AllBag, Interp),
        RealYaku = [_ | _],
        DoraYaku = eval_dora(Ctx, AllPhys, AllBag),
        AllYaku0 = RealYaku ++ DoraYaku,
        list.sort(compare_yaku, AllYaku0, AllYaku),
        Han = sum_yaku_vals(AllYaku),
        HasPinfu = ( if list.member(yaku_entry("pinfu", 1), RealYaku)
            then yes else no ),
        Fu = compute_fu(IsClosed, By, Ctx, Interp, HasPinfu),
        Basic = ordinary_basic_points(Han, Fu),
        compute_payment(Basic, Ctx ^ seat, By, Ctx ^ honba, Pay, Total),
        SV = ordinary_score(AllYaku, Han, Fu, Pay, Total)
    ).

% ============================================================================
% Yakuman
% ============================================================================

:- func eval_yakuman(list(tile), list(meld), tile, score_context,
    bag(tile_kind), hand_interp) = list(yaku_entry).

eval_yakuman(Hand13, Melds, WinTile, Ctx, AllBag, Interp) = YMs :-
    Flags = Ctx ^ flags,
    Sit =
        ( if set.member(flag_tenhou, Flags) then [yaku_entry("tenhou", 1)] else [] ) ++
        ( if set.member(flag_chiihou, Flags) then [yaku_entry("chiihou", 1)] else [] ),
    (
        Interp = interp_kokushi(Is13),
        FormYMs = ( if Is13 = yes then [yaku_entry("kokushi_13", 2)]
                    else [yaku_entry("kokushi", 1)] )
    ;
        Interp = interp_chiitoi,
        FormYMs = ( if all_kinds_satisfy(is_honor, AllBag)
                    then [yaku_entry("tsuuiisou", 1)] else [] )
    ;
        Interp = interp_std(Pair, Groups, Wait),
        ClosedTriplets = count_closed_triplets_or_kans(Groups),
        Suuankou =
            ( if ClosedTriplets = 4 then
                ( if Wait = wait_tanki then [yaku_entry("suuankou_tanki", 2)]
                  else [yaku_entry("suuankou", 1)] )
            else
                []
            ),
        Daisangen =
            ( if has_triplet_or_kan(Groups, dragon(haku)),
                 has_triplet_or_kan(Groups, dragon(hatsu)),
                 has_triplet_or_kan(Groups, dragon(chun))
            then [yaku_entry("daisangen", 1)] else [] ),
        WindSets = count_wind_triplets_or_kans(Groups),
        Suushii =
            ( if WindSets = 4 then [yaku_entry("daisuushii", 2)]
            else if WindSets = 3, is_wind(Pair) then [yaku_entry("shousuushii", 1)]
            else [] ),
        Tsuuiisou =
            ( if all_kinds_satisfy(is_honor, AllBag)
            then [yaku_entry("tsuuiisou", 1)] else [] ),
        Chinroutou =
            ( if all_kinds_satisfy(is_terminal, AllBag)
            then [yaku_entry("chinroutou", 1)] else [] ),
        Ryuuiisou =
            ( if all_kinds_satisfy(is_green, AllBag)
            then [yaku_entry("ryuuiisou", 1)] else [] ),
        Chuuren = eval_chuuren(Hand13, Melds, WinTile, AllBag),
        Suukantsu =
            ( if count_kans(Groups) = 4 then [yaku_entry("suukantsu", 1)] else [] ),
        FormYMs = Suuankou ++ Daisangen ++ Suushii ++ Tsuuiisou ++
                  Chinroutou ++ Ryuuiisou ++ Chuuren ++ Suukantsu
    ),
    YMs = Sit ++ FormYMs.

:- func eval_chuuren(list(tile), list(meld), tile, bag(tile_kind)) =
    list(yaku_entry).

eval_chuuren(Hand13, Melds, WinTile, AllBag) = Res :-
    ( if Melds = [],
         single_num_suit_only(AllBag, Suit),
         BaseBag = chuuren_base_bag(Suit),
         bag.is_subbag(BaseBag, AllBag)
    then
        Hand13Bag = hand_to_kind_bag(Hand13),
        ( if Hand13Bag = BaseBag, WinTile ^ kind = num(Suit, _) then
            Res = [yaku_entry("junsei_chuuren", 2)]
        else
            Res = [yaku_entry("chuuren", 1)]
        )
    else
        Res = []
    ).

:- func chuuren_base_bag(num_suit) = bag(tile_kind).

chuuren_base_bag(S) = bag.from_list([
    num(S, 1), num(S, 1), num(S, 1),
    num(S, 2), num(S, 3), num(S, 4), num(S, 5), num(S, 6), num(S, 7), num(S, 8),
    num(S, 9), num(S, 9), num(S, 9)
]).

% ============================================================================
% Standard Yaku
% ============================================================================

:- func eval_standard_yaku(bool, win_by, score_context, bag(tile_kind),
    hand_interp) = list(yaku_entry).

eval_standard_yaku(IsClosed, By, Ctx, AllBag, Interp) = Yaku :-
    Flags = Ctx ^ flags,
    Sit =
        ( if set.member(flag_double_riichi, Flags) then
            [yaku_entry("double_riichi", 2)]
        else if set.member(flag_riichi, Flags) then
            [yaku_entry("riichi", 1)]
        else [] ) ++
        ( if set.member(flag_ippatsu, Flags) then [yaku_entry("ippatsu", 1)] else [] ) ++
        ( if IsClosed = yes, By = tsumo then [yaku_entry("tsumo", 1)] else [] ) ++
        ( if set.member(flag_haitei, Flags) then [yaku_entry("haitei", 1)] else [] ) ++
        ( if set.member(flag_houtei, Flags) then [yaku_entry("houtei", 1)] else [] ) ++
        ( if set.member(flag_rinshan, Flags) then [yaku_entry("rinshan", 1)] else [] ) ++
        ( if set.member(flag_chankan, Flags) then [yaku_entry("chankan", 1)] else [] ),

    Tanyao = ( if all_kinds_satisfy(is_simple, AllBag)
               then [yaku_entry("tanyao", 1)] else [] ),
    Honroutou = ( if all_kinds_satisfy(is_yaochuu, AllBag)
                  then [yaku_entry("honroutou", 2)] else [] ),
    Flush = eval_flush(IsClosed, AllBag),

    (
        Interp = interp_kokushi(_),
        FormYaku = []
    ;
        Interp = interp_chiitoi,
        FormYaku = [yaku_entry("chiitoi", 2)] ++ Tanyao ++ Honroutou ++ Flush
    ;
        Interp = interp_std(Pair, Groups, Wait),
        Seat = Ctx ^ seat,
        Round = Ctx ^ round,
        Pinfu =
            ( if IsClosed = yes,
                 all_sequences(Groups),
                 pair_fu(Pair, Seat, Round) = 0,
                 Wait = wait_ryanmen
            then [yaku_entry("pinfu", 1)] else [] ),
        Peikou = eval_peikou(IsClosed, Groups),
        Yakuhai =
            ( if has_triplet_or_kan(Groups, dragon(haku)) then [yaku_entry("yakuhai_haku", 1)] else [] ) ++
            ( if has_triplet_or_kan(Groups, dragon(hatsu)) then [yaku_entry("yakuhai_hatsu", 1)] else [] ) ++
            ( if has_triplet_or_kan(Groups, dragon(chun)) then [yaku_entry("yakuhai_chun", 1)] else [] ) ++
            ( if has_triplet_or_kan(Groups, wind(Seat)) then [yaku_entry("yakuhai_seat", 1)] else [] ) ++
            ( if has_triplet_or_kan(Groups, wind(Round)) then [yaku_entry("yakuhai_round", 1)] else [] ),
        Toitoi = ( if count_sequences(Groups) = 0 then [yaku_entry("toitoi", 2)] else [] ),
        Sanankou = ( if count_closed_triplets_or_kans(Groups) >= 3
                     then [yaku_entry("sanankou", 2)] else [] ),
        Sanshoku =
            ( if has_sanshoku_doujun(Groups) then
                [yaku_entry("sanshoku", ( if IsClosed = yes then 2 else 1 ))]
            else [] ),
        SanshokuDoukou =
            ( if has_sanshoku_doukou(Groups) then
                [yaku_entry("sanshoku_doukou", 2)]
            else [] ),
        Ittsu =
            ( if has_ittsu(Groups) then
                [yaku_entry("ittsu", ( if IsClosed = yes then 2 else 1 ))]
            else [] ),
        Outside = eval_chanta_junchan(IsClosed, Pair, Groups, Honroutou),
        Shousangen =
            ( if count_dragon_triplets_or_kans(Groups) = 2, is_dragon(Pair)
            then [yaku_entry("shousangen", 2)] else [] ),
        Sankantsu =
            ( if count_kans(Groups) = 3 then [yaku_entry("sankantsu", 2)] else [] ),
        FormYaku = Pinfu ++ Tanyao ++ Peikou ++ Yakuhai ++ Toitoi ++ Sanankou ++
                   Sanshoku ++ SanshokuDoukou ++ Ittsu ++ Outside ++ Honroutou ++
                   Shousangen ++ Sankantsu ++ Flush
    ),
    Yaku = Sit ++ FormYaku.

:- func eval_flush(bool, bag(tile_kind)) = list(yaku_entry).

eval_flush(IsClosed, AllBag) = Res :-
    ( if single_num_suit_only(AllBag, _) then
        Res = [yaku_entry("chinitsu", ( if IsClosed = yes then 6 else 5 ))]
    else if single_num_suit_with_honors(AllBag) then
        Res = [yaku_entry("honitsu", ( if IsClosed = yes then 3 else 2 ))]
    else
        Res = []
    ).

:- func eval_peikou(bool, list(scored_group)) = list(yaku_entry).

eval_peikou(IsClosed, Groups) = Res :-
    ( if IsClosed = yes then
        list.filter_map(
            (pred(G::in, (S - N)::out) is semidet :- G = sg_seq(S, N, _)),
            Groups, Seqs),
        SeqBag = bag.from_list(Seqs),
        bag.to_assoc_list(SeqBag, Assoc),
        list.foldl(
            (pred((_ - C)::in, Acc0::in, Acc::out) is det :- Acc = Acc0 + C // 2),
            Assoc, 0, PairCount),
        ( if PairCount = 2 then
            Res = [yaku_entry("ryanpeikou", 3)]
        else if PairCount = 1 then
            Res = [yaku_entry("iipeikou", 1)]
        else
            Res = []
        )
    else
        Res = []
    ).

:- func eval_chanta_junchan(bool, tile_kind, list(scored_group),
    list(yaku_entry)) = list(yaku_entry).

eval_chanta_junchan(IsClosed, Pair, Groups, Honroutou) = Res :-
    ( if Honroutou = [], count_sequences(Groups) > 0 then
        ( if is_terminal(Pair),
             list.all_true(group_has_terminal, Groups)
        then
            Res = [yaku_entry("junchan", ( if IsClosed = yes then 3 else 2 ))]
        else if is_yaochuu(Pair),
                list.all_true(group_has_yaochuu, Groups)
        then
            Res = [yaku_entry("chanta", ( if IsClosed = yes then 2 else 1 ))]
        else
            Res = []
        )
    else
        Res = []
    ).

:- func eval_dora(score_context, list(tile), bag(tile_kind)) = list(yaku_entry).

eval_dora(Ctx, AllPhys, AllBag) = Res :-
    DoraCount = count_indicator_dora(Ctx ^ dora, AllBag),
    AkaCount = list.foldl(
        (func(T, Acc) = ( if T ^ is_red = red then Acc + 1 else Acc )),
        AllPhys, 0),
    Flags = Ctx ^ flags,
    UraCount =
        ( if ( set.member(flag_riichi, Flags) ; set.member(flag_double_riichi, Flags) )
        then count_indicator_dora(Ctx ^ ura, AllBag)
        else 0 ),
    Res =
        ( if DoraCount > 0 then [yaku_entry("dora", DoraCount)] else [] ) ++
        ( if AkaCount > 0 then [yaku_entry("aka", AkaCount)] else [] ) ++
        ( if UraCount > 0 then [yaku_entry("ura", UraCount)] else [] ).

:- func count_indicator_dora(list(tile_kind), bag(tile_kind)) = int.

count_indicator_dora(Indicators, AllBag) =
    list.foldl(
        (func(Ind, Acc) = Acc + bag.count_value(AllBag, next_dora(Ind))),
        Indicators, 0).

% ============================================================================
% Fu & Payment
% ============================================================================

:- func compute_fu(bool, win_by, score_context, hand_interp, bool) = int.

compute_fu(_, _, _, interp_kokushi(_), _) = 20.
compute_fu(_, _, _, interp_chiitoi, _) = 25.
compute_fu(IsClosed, By, Ctx, interp_std(Pair, Groups, Wait), HasPinfu) = Fu :-
    ( if HasPinfu = yes, By = tsumo then
        Fu = 20
    else
        GroupFu = list.foldl((func(G, Acc) = Acc + group_fu(G)), Groups, 0),
        PFu = pair_fu(Pair, Ctx ^ seat, Ctx ^ round),
        WFu = wait_fu(Wait),
        WinFu =
            ( if By = tsumo then 2
            else if IsClosed = yes then 10
            else 0
            ),
        ExtraFu = GroupFu + PFu + WFu + WinFu,
        ( if IsClosed = no, By = ron, ExtraFu = 0 then
            Fu = 30
        else
            RawFu = 20 + ExtraFu,
            Fu = ((RawFu + 9) // 10) * 10
        )
    ).

:- func group_fu(scored_group) = int.

group_fu(sg_seq(_, _, _)) = 0.
group_fu(sg_triplet(K, open)) = ( if is_yaochuu(K) then 4 else 2 ).
group_fu(sg_triplet(K, closed)) = ( if is_yaochuu(K) then 8 else 4 ).
group_fu(sg_kan(K, open)) = ( if is_yaochuu(K) then 16 else 8 ).
group_fu(sg_kan(K, closed)) = ( if is_yaochuu(K) then 32 else 16 ).

:- func pair_fu(tile_kind, wind, wind) = int.

pair_fu(num(_, _), _, _) = 0.
pair_fu(dragon(_), _, _) = 2.
pair_fu(wind(W), Seat, Round) =
    ( if W = Seat then 2 else 0 ) + ( if W = Round then 2 else 0 ).

:- func wait_fu(wait_type) = int.

wait_fu(wait_ryanmen) = 0.
wait_fu(wait_shanpon) = 0.
wait_fu(wait_kanchan) = 2.
wait_fu(wait_penchan) = 2.
wait_fu(wait_tanki) = 2.

:- func ordinary_basic_points(int, int) = int.

ordinary_basic_points(Han, Fu) = Basic :-
    ( if Han >= 13 then Basic = 8000
    else if Han >= 11 then Basic = 6000
    else if Han >= 8 then Basic = 4000
    else if Han >= 6 then Basic = 3000
    else if Han = 5 then Basic = 2000
    else
        Raw = Fu * (1 << (2 + Han)),
        Basic = int.min(2000, Raw)
    ).

:- func ceil100(int) = int.

ceil100(X) = ((X + 99) // 100) * 100.

:- pred compute_payment(int::in, wind::in, win_by::in, int::in,
    payment::out, int::out) is det.

compute_payment(Basic, Seat, By, Honba, Pay, Total) :-
    IsDealer = ( if Seat = east then yes else no ),
    (
        By = ron,
        Mult = ( if IsDealer = yes then 6 else 4 ),
        P = ceil100(Mult * Basic) + 300 * Honba,
        Pay = pay_ron(P),
        Total = P
    ;
        By = tsumo,
        (
            IsDealer = yes,
            Each = ceil100(2 * Basic) + 100 * Honba,
            Pay = pay_all(Each),
            Total = 3 * Each
        ;
            IsDealer = no,
            NonDealer = ceil100(Basic) + 100 * Honba,
            Dealer = ceil100(2 * Basic) + 100 * Honba,
            Pay = pay_tsumo(NonDealer, Dealer),
            Total = 2 * NonDealer + Dealer
        )
    ).

% ============================================================================
% Tie-breaking and Helpers
% ============================================================================

:- func better_score(score_val, score_val) = score_val.

better_score(A, B) = ( if score_beats(A, B) then A else B ).

:- pred score_beats(score_val::in, score_val::in) is semidet.

score_beats(A, B) :-
    TotA = score_total(A),
    TotB = score_total(B),
    ( if TotA \= TotB then
        TotA > TotB
    else
        YmA = is_real_yakuman_int(A),
        YmB = is_real_yakuman_int(B),
        ( if YmA \= YmB then
            YmA > YmB
        else
            HanA = score_han(A),
            HanB = score_han(B),
            ( if HanA \= HanB then
                HanA > HanB
            else
                FuA = score_fu(A),
                FuB = score_fu(B),
                ( if FuA \= FuB then
                    FuA > FuB
                else
                    StrA = format_yaku_list(score_yaku(A)),
                    StrB = format_yaku_list(score_yaku(B)),
                    compare((<), StrA, StrB)
                )
            )
        )
    ).

:- func score_total(score_val) = int.
score_total(yakuman_score(_, _, _, T)) = T.
score_total(ordinary_score(_, _, _, _, T)) = T.

:- func is_real_yakuman_int(score_val) = int.
is_real_yakuman_int(yakuman_score(_, _, _, _)) = 1.
is_real_yakuman_int(ordinary_score(_, _, _, _, _)) = 0.

:- func score_han(score_val) = int.
score_han(yakuman_score(_, _, _, _)) = 0.
score_han(ordinary_score(_, H, _, _, _)) = H.

:- func score_fu(score_val) = int.
score_fu(yakuman_score(_, _, _, _)) = 0.
score_fu(ordinary_score(_, _, F, _, _)) = F.

:- func score_yaku(score_val) = list(yaku_entry).
score_yaku(yakuman_score(Y, _, _, _)) = Y.
score_yaku(ordinary_score(Y, _, _, _, _)) = Y.

:- pred compare_yaku(yaku_entry::in, yaku_entry::in, comparison_result::out)
    is det.

compare_yaku(yaku_entry(N1, V1), yaku_entry(N2, V2), Res) :-
    compare(Res0, N1, N2),
    ( if Res0 = (=) then compare(Res, V1, V2) else Res = Res0 ).

:- func sum_yaku_vals(list(yaku_entry)) = int.
sum_yaku_vals(Ys) = list.foldl((func(Y, Acc) = Acc + Y ^ yaku_val), Ys, 0).

:- pred all_kinds_satisfy(pred(tile_kind)::in(pred(in) is semidet),
    bag(tile_kind)::in) is semidet.

all_kinds_satisfy(P, Bag) :-
    bag.to_assoc_list(Bag, Assoc),
    list.all_true((pred((K - _)::in) is semidet :- P(K)), Assoc).

:- pred single_num_suit_only(bag(tile_kind)::in, num_suit::out) is semidet.

single_num_suit_only(Bag, Suit) :-
    bag.to_assoc_list(Bag, Assoc),
    Assoc = [num(Suit, _) - _ | _],
    list.all_true((pred((K - _)::in) is semidet :- K = num(Suit, _)), Assoc).

:- pred single_num_suit_with_honors(bag(tile_kind)::in) is semidet.

single_num_suit_with_honors(Bag) :-
    bag.to_assoc_list(Bag, Assoc),
    list.filter_map(
        (pred((K - _)::in, S::out) is semidet :- K = num(S, _)),
        Assoc, Suits),
    Suits = [FirstSuit | _],
    list.all_true((pred(S::in) is semidet :- S = FirstSuit), Suits),
    list.any_true((pred((K - _)::in) is semidet :- is_honor(K)), Assoc).

:- pred all_sequences(list(scored_group)::in) is semidet.

all_sequences(Groups) :-
    list.all_true((pred(G::in) is semidet :- G = sg_seq(_, _, _)), Groups).

:- func count_sequences(list(scored_group)) = int.

count_sequences(Groups) = list.foldl(
    (func(G, Acc) = ( if G = sg_seq(_, _, _) then Acc + 1 else Acc )),
    Groups, 0).

:- func count_closed_triplets_or_kans(list(scored_group)) = int.

count_closed_triplets_or_kans(Groups) = list.foldl(
    (func(G, Acc) =
        ( if ( G = sg_triplet(_, closed) ; G = sg_kan(_, closed) )
        then Acc + 1 else Acc )),
    Groups, 0).

:- func count_kans(list(scored_group)) = int.

count_kans(Groups) = list.foldl(
    (func(G, Acc) = ( if G = sg_kan(_, _) then Acc + 1 else Acc )),
    Groups, 0).

:- pred has_triplet_or_kan(list(scored_group)::in, tile_kind::in) is semidet.

has_triplet_or_kan(Groups, K) :-
    list.any_true(
        (pred(G::in) is semidet :-
            ( G = sg_triplet(K, _) ; G = sg_kan(K, _) )
        ), Groups).

:- func count_wind_triplets_or_kans(list(scored_group)) = int.

count_wind_triplets_or_kans(Groups) = list.foldl(
    (func(G, Acc) =
        ( if ( G = sg_triplet(K, _) ; G = sg_kan(K, _) ), is_wind(K)
        then Acc + 1 else Acc )),
    Groups, 0).

:- func count_dragon_triplets_or_kans(list(scored_group)) = int.

count_dragon_triplets_or_kans(Groups) = list.foldl(
    (func(G, Acc) =
        ( if ( G = sg_triplet(K, _) ; G = sg_kan(K, _) ), is_dragon(K)
        then Acc + 1 else Acc )),
    Groups, 0).

:- pred has_sanshoku_doujun(list(scored_group)::in) is semidet.

has_sanshoku_doujun(Groups) :-
    list.member(sg_seq(m, N, _), Groups),
    list.any_true((pred(G::in) is semidet :- G = sg_seq(p, N, _)), Groups),
    list.any_true((pred(G::in) is semidet :- G = sg_seq(s, N, _)), Groups).

:- pred has_sanshoku_doukou(list(scored_group)::in) is semidet.

has_sanshoku_doukou(Groups) :-
    list.member(G0, Groups),
    ( G0 = sg_triplet(num(m, N), _) ; G0 = sg_kan(num(m, N), _) ),
    has_triplet_or_kan(Groups, num(p, N)),
    has_triplet_or_kan(Groups, num(s, N)).

:- pred has_ittsu(list(scored_group)::in) is semidet.

has_ittsu(Groups) :-
    ( S = m ; S = p ; S = s ),
    list.any_true((pred(G::in) is semidet :- G = sg_seq(S, 1, _)), Groups),
    list.any_true((pred(G::in) is semidet :- G = sg_seq(S, 4, _)), Groups),
    list.any_true((pred(G::in) is semidet :- G = sg_seq(S, 7, _)), Groups).

:- pred group_has_terminal(scored_group::in) is semidet.

group_has_terminal(sg_seq(_, N, _)) :- ( N = 1 ; N = 7 ).
group_has_terminal(sg_triplet(K, _)) :- is_terminal(K).
group_has_terminal(sg_kan(K, _)) :- is_terminal(K).

:- pred group_has_yaochuu(scored_group::in) is semidet.

group_has_yaochuu(sg_seq(_, N, _)) :- ( N = 1 ; N = 7 ).
group_has_yaochuu(sg_triplet(K, _)) :- is_yaochuu(K).
group_has_yaochuu(sg_kan(K, _)) :- is_yaochuu(K).

% ============================================================================
% Formatting
% ============================================================================

:- func format_yaku_list(list(yaku_entry)) = string.

format_yaku_list(Ys) =
    string.join_list(",",
        list.map((func(yaku_entry(N, V)) = N ++ ":" ++ string.int_to_string(V)),
            Ys)).

:- func format_payment(payment) = string.

format_payment(pay_ron(N)) = "ron:" ++ string.int_to_string(N).
format_payment(pay_all(N)) = "all:" ++ string.int_to_string(N).
format_payment(pay_tsumo(ND, D)) =
    "tsumo:" ++ string.int_to_string(ND) ++ "/" ++ string.int_to_string(D).

format_score_outcome(score_not_agari) = "error=not_agari".
format_score_outcome(score_no_yaku) = "error=no_yaku".
format_score_outcome(score_ok(yakuman_score(Ys, Mult, Pay, Total))) =
    "yaku=" ++ format_yaku_list(Ys) ++
    " yakuman=" ++ string.int_to_string(Mult) ++
    " pay=" ++ format_payment(Pay) ++
    " total=" ++ string.int_to_string(Total).
format_score_outcome(score_ok(ordinary_score(Ys, Han, Fu, Pay, Total))) =
    "yaku=" ++ format_yaku_list(Ys) ++
    " han=" ++ string.int_to_string(Han) ++
    " fu=" ++ string.int_to_string(Fu) ++
    " pay=" ++ format_payment(Pay) ++
    " total=" ++ string.int_to_string(Total).
