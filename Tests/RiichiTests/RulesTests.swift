// Rules threaded through scoring and legality.

import Testing
@testable import Riichi

@Suite struct RulesScoringTests {
    /// The four hands Mahjong Soul doubles: single yakuman under Tenhou rules.
    @Test(arguments: [
        ("19m19p19s1234567z", "-", "1m", "kokushi_13"),
        ("111m222p333s444z5p", "-", "5p", "suuankou_tanki"),
        ("1112345678999m", "-", "5m", "junsei_chuuren"),
        ("222333444z5m", "p111z", "5m", "daisuushii"),
    ])
    func doubleYakumanOnlyOnMahjongSoul(hand: String, melds: String, win: String, name: String) {
        let ms = scored(hand: hand, melds: melds, win: win, tsumo: false, rules: .mahjongSoul)
        let th = scored(hand: hand, melds: melds, win: win, tsumo: false, rules: .tenhou)
        #expect(ms.yaku == "\(name):2")
        #expect(ms.value == .yakuman(2))
        #expect(ms.total == 64_000)
        #expect(th.yaku == "\(name):1")
        #expect(th.value == .yakuman(1))
        #expect(th.total == 32_000)
    }

    @Test func otherYakumanStackTheSame() {
        // Daisangen + tsuuiisou is 2x under both.
        for rules in [Rules.mahjongSoul, .tenhou] {
            let r = scored(hand: "555666777z1122z", win: "2z", tsumo: false, rules: rules)
            #expect(r.value == .yakuman(2))
            #expect(r.yaku == "daisangen:1,tsuuiisou:1")
        }
        // Daisuushii + tsuuiisou: 3x on Mahjong Soul, 2x on Tenhou (rules.md §1).
        let hand = "222333444z5z", m = "p111z"
        #expect(scored(hand: hand, melds: m, win: "5z", tsumo: false, rules: .mahjongSoul).value == .yakuman(3))
        #expect(scored(hand: hand, melds: m, win: "5z", tsumo: false, rules: .tenhou).value == .yakuman(2))
    }

    @Test func tenhouIsNotUpgradedUnderTenhouRules() {
        // Dealer's opening 14: kokushi with a 1m pair, 9m drawn last.
        let hand = "11m19p19s1234567z"
        let ms = scored(hand: hand, win: "9m", tsumo: true, seat: .east, flags: [.tenhou],
                        rules: .mahjongSoul)
        let th = scored(hand: hand, win: "9m", tsumo: true, seat: .east, flags: [.tenhou],
                        rules: .tenhou)
        // Mahjong Soul takes the best winning tile, which makes the 13-sided form.
        #expect(ms.yaku == "kokushi_13:2,tenhou:1")
        #expect(ms.total == 3 * 48_000)
        // Tenhou scores the tile actually drawn: a single wait on 9m.
        #expect(th.yaku == "kokushi:1,tenhou:1")
        #expect(th.total == 2 * 48_000)
    }

    @Test func tenhouSuuankouOnTenhouRules() {
        // Four concealed triplets and a pair, drawn tile completing a triplet: Mahjong
        // Soul reads it as the tanki form; Tenhou keeps the drawn tile, both 1x there.
        let hand = "111m222p333s44z55z"
        let ms = scored(hand: hand, win: "5z", tsumo: true, seat: .east, flags: [.tenhou],
                        rules: .mahjongSoul)
        let th = scored(hand: hand, win: "5z", tsumo: true, seat: .east, flags: [.tenhou],
                        rules: .tenhou)
        #expect(ms.yaku == "suuankou_tanki:2,tenhou:1")
        #expect(th.yaku == "suuankou:1,tenhou:1")
        #expect(th.value == .yakuman(2))
    }

    @Test func kuitan() {
        var noKuitan = Rules.mahjongSoul
        noKuitan.kuitan = false
        let open = (hand: "234m567p678s8s", melds: "c234s", win: "8s")
        let on = scored(hand: open.hand, melds: open.melds, win: open.win, tsumo: false,
                        rules: .mahjongSoul)
        #expect(on.yaku == "tanyao:1")
        #expect(on.total == 1_000)
        let off = scored(hand: open.hand, melds: open.melds, win: open.win, tsumo: false,
                         rules: noKuitan)
        #expect(off.error == .noYaku)
        // Closed tanyao is unaffected.
        let closed = scored(hand: "234m567p234678s8s", win: "8s", tsumo: false, rules: noKuitan)
        #expect(closed.yaku == "pinfu:1,tanyao:1")
    }

    @Test func doubleWindPairFu() {
        // Dealer, East round: EE pair, closed 111m, riichi ron on a two-sided wait.
        // 20 + 10 (closed ron) + 8 (closed terminal triplet) + pair.
        let hand = "111m234p34567s11z", win = "5s"
        let four = scored(hand: hand, win: win, tsumo: false, seat: .east, flags: [.riichi],
                          rules: .mahjongSoul)
        #expect(four.value == .ordinary(han: 1, fu: 50))  // 42 -> 50
        #expect(four.total == 2_400)
        var two = Rules.mahjongSoul
        two.doubleWindPairFu = 2
        let r = scored(hand: hand, win: win, tsumo: false, seat: .east, flags: [.riichi], rules: two)
        #expect(r.value == .ordinary(han: 1, fu: 40))  // 40
        #expect(r.total == 2_000)
        // A single-wind pair is 2 fu whatever the field says.
        let south = scored(hand: "111m234p34567s22z", win: win, tsumo: false, seat: .south,
                           flags: [.riichi], rules: two)
        #expect(south.value == .ordinary(han: 1, fu: 40))
    }

    @Test func presetsDifferWhereRulesMdSaysTheyDo() {
        let ms = Rules.mahjongSoul, th = Rules.tenhou
        #expect(ms.oka == 0 && th.oka == 20_000)
        #expect(ms.doubleYakuman && !th.doubleYakuman)
        #expect(!ms.tripleRonAborts && th.tripleRonAborts)
        #expect(ms.kokushiRobsClosedKan && !th.kokushiRobsClosedKan)
        #expect(!ms.paoCoversWholeHand && th.paoCoversWholeHand)
        #expect(!ms.openKanDoraBeforeRon && th.openKanDoraBeforeRon)
        #expect(!ms.fifthCopyTenpaiAtDraw && th.fifthCopyTenpaiAtDraw)
        #expect(ms.tenhouAnyWinningTile && !th.tenhouAnyWinningTile)
        #expect(ms.uma.reduce(0, +) == 0 && th.uma.reduce(0, +) == 0)
    }
}

@Suite struct RulesLegalTests {
    func actions(_ hand: String, melds m: String = "-", _ situation: Situation,
                 flags: Set<Flag> = [], rules: Rules) -> [String] {
        LegalRequest(hand: t(hand), melds: melds(m), situation: situation, flags: flags,
                     rules: rules).actions
    }

    @Test func robbingAClosedKan() {
        // Single-wait kokushi on 1m; another seat declares a closed kan of 1m.
        let hand = "9m19p19s1234567z7z"
        let rob = Situation.discard(t1("1m"), fromKamicha: false)
        #expect(actions(hand, rob, flags: [.ankan_rob], rules: .mahjongSoul) == ["pass", "ron"])
        #expect(actions(hand, rob, flags: [.ankan_rob], rules: .tenhou) == ["pass"])
        // An added kan can be robbed under both.
        #expect(actions(hand, rob, flags: [.chankan], rules: .tenhou) == ["pass", "ron"])
    }

    @Test func riichiOnFifthCopyWait() {
        // Discarding 9p leaves 234567789m1111z, whose only wait is a fifth 1z.
        let draw = Situation.draw(t1("1z"))
        let hand = "234567789m9p111z"
        #expect(!actions(hand, draw, rules: .mahjongSoul).contains("riichi:9p"))
        #expect(!actions(hand, draw, rules: .tenhou).contains("riichi:9p"))
        var loose = Rules.mahjongSoul
        loose.riichiOnFifthCopyWait = true
        #expect(actions(hand, draw, rules: loose).contains("riichi:9p"))
    }

    @Test func kuitanReachesRon() {
        var noKuitan = Rules.mahjongSoul
        noKuitan.kuitan = false
        let ron = Situation.discard(t1("8s"), fromKamicha: false)
        #expect(actions("234m567p678s8s", melds: "c234s", ron, rules: .mahjongSoul).contains("ron"))
        #expect(!actions("234m567p678s8s", melds: "c234s", ron, rules: noKuitan).contains("ron"))
    }

    @Test func formalTenpaiAtDraw() {
        // Only wait a fifth 1m; three copies are in chis, one concealed.
        let open = (Counts(t("1m234p")), melds("c123m,c123m,c123m"))
        #expect(!isTenpaiAtDraw(open.0, melds: open.1, rules: .mahjongSoul))
        #expect(isTenpaiAtDraw(open.0, melds: open.1, rules: .tenhou))
        // All four copies concealed: noten under both.
        let closed = Counts(t("234567789m1111z"))
        #expect(!isTenpaiAtDraw(closed, melds: [], rules: .mahjongSoul))
        #expect(!isTenpaiAtDraw(closed, melds: [], rules: .tenhou))
        // An ordinary wait is tenpai under both; an iishanten hand under neither.
        #expect(isTenpaiAtDraw(Counts(t("123m456p789s1122z")), melds: [], rules: .mahjongSoul))
        #expect(isTenpaiAtDraw(Counts(t("123m456p789s1122z")), melds: [], rules: .tenhou))
        #expect(!isTenpaiAtDraw(Counts(t("123m456p789s1257z")), melds: [], rules: .tenhou))
    }
}
