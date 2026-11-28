// The final Phase 3 reviews (Docs/Reviews/p3/final-codex.md, final-agy.md): input
// checked at every public entry point, the running game's counters, the scorer's
// requests, `winRequest(for:)` honba, the terminal view, East-only games.

import Testing
@testable import Riichi

@Suite struct InputCheckTests {
    /// Codex final finding 2: a game started at the largest honba it admits plays
    /// on past it (the dealer's nine terminals repeats the hand with one more).
    @Test func gameAdvancesFromTheLargestAdmittedHonba() throws {
        let wall = makeWall(hands: ["19m19p19s1234567z"] + quietHands, draws: "5z")
        var events: [Event] = []
        var game = try GameState(rules: .mahjongSoul, seed: 0,
                                 position: try GamePosition(honba: RoundState.maxCount, sticks: RoundState.maxCount,
                                                            scores: [25_000, 25_000, 25_000, 25_000]),
                                 wall: wall, events: &events)
        #expect(game.legalActions(for: Seat(0)).contains(.kyuushu))
        try game.apply(.kyuushu, by: Seat(0))
        #expect(!game.isOver && game.position.honba == RoundState.maxCount + 1 && game.round.honba == RoundState.maxCount + 1)
        // Past the admission bound a position is refused from outside...
        #expect(throws: InputError.self) {
            try GameState(rules: .mahjongSoul, seed: 0, position: game.position, events: &events)
        }
        #expect(throws: InputError.self) { try RoundState(rules: .mahjongSoul, wall: wall, honba: RoundState.maxCount + 1) }
        // ... and the game itself ends rather than pass the running bound.
        let atLimit = try GamePosition(honba: RoundState.maxRunningHonba, scores: [25_000, 25_000, 25_000, 25_000])
        let r = try #require(game.lastRound?.result)
        let (next, transition) = try GameFlow.next(after: r, at: atLimit, rules: .mahjongSoul)
        #expect(next == nil && transition == .ends(.counterLimit))
    }

    @Test func positionsAndRulesOutOfRangeAreErrors() throws {
        let wall = Wall(seed: 1, hand: 0)
        let even = [25_000, 25_000, 25_000, 25_000]
        #expect(throws: InputError.self) { try GamePosition(kyoku: 5, scores: even) }
        #expect(throws: InputError.self) { try GamePosition(scores: [25_000, 25_000, 25_000]) }
        #expect(throws: InputError.self) { try GamePosition(honba: -1, scores: even) }
        #expect(throws: InputError.self) { try GamePosition(sticks: GamePosition.maxSticks + 1, scores: even) }
        #expect(throws: InputError.self) { try RoundState(rules: .tenhou, wall: wall, kyoku: 0) }
        #expect(throws: InputError.self) { try RoundState(rules: .tenhou, wall: wall, scores: [1, 2]) }
        #expect(throws: InputError.self) { try RoundState(rules: .tenhou, wall: wall, scores: [RoundState.maxScore + 1, 0, 0, 0]) }
        #expect(throws: InputError.self) {
            var ev: [Event] = []
            _ = try GameState(rules: .tenhou, seed: 0, position: try GamePosition(scores: even), handsDealt: -1, events: &ev)
        }
        // A ruleset with three uma entries can be made (no trap on assignment) and is
        // refused wherever it is used.
        var r = Rules.tenhou
        r.uma = [1, 2, 3]
        #expect(!r.isValid)
        #expect(throws: InputError.self) { try r.validate() }
        #expect(throws: InputError.self) { try GameState(rules: r, seed: 0) }
        #expect(throws: InputError.self) { try RoundState(rules: r, wall: wall) }
        #expect(throws: InputError.self) { try GameFlow.result(scores: even, sticks: 0, rules: r, end: .target) }
        #expect(throws: InputError.self) { try GameFlow.result(scores: [1], sticks: 0, rules: .tenhou, end: .target) }
        #expect(throws: InputError.self) { try GameFlow.ranking([1, 2]) }
        // The memberwise initializer has every field, `owedDoraAtChainedAddedKan`
        // included (Codex final audit), so copying the presets' arguments gives them.
        let copy = Rules(startingPoints: 25_000, returnPoints: 25_000, uma: [15_000, 5_000, -5_000, -15_000],
                         targetPoints: 30_000, length: .south, dealerRepeatBeforeTarget: true,
                         allLastTestAfterNagashi: true, doubleYakuman: true, tenhouAnyWinningTile: true,
                         kuitan: true, doubleWindPairFu: 4, tripleRonAborts: false, honbaToEveryRonWinner: false,
                         kokushiRobsClosedKan: true, openKanDoraBeforeRon: true, owedDoraAtChainedAddedKan: true,
                         paoCoversWholeHand: false, riichiOnFifthCopyWait: true, fifthCopyTenpaiAtDraw: true,
                         fourWindsRiichiStickPaid: true, temporaryFuritenEndsOnCall: true,
                         temporaryFuritenOnDeclinedTsumo: false)
        #expect(copy == .mahjongSoul)
    }

    /// Gemini final finding 1: only ASCII digits are digits.
    @Test func tileTextIsAscii() {
        for bad in ["⑽m", "１m", "Ⅻp", "٣s", "1⑽m"] { #expect(parseTiles(Substring(bad)) == nil, "\(bad)") }
        #expect(parseTiles("19m0p7z") == t("19m0p7z"))
        #expect(isPossibleTileSet(t("1111m055p")) && !isPossibleTileSet(t("11111m")) && !isPossibleTileSet(t("00m")))
        #expect(Meld(kind: .pon, tiles: t("111m"))!.kuikaeForbidden(took: Kind(.man, 2)).isEmpty)
    }

    /// Codex final finding 3: the public scorer checks its request.
    @Test func scoreRequestsAreChecked() throws {
        var req = ScoreRequest(hand: t("123456m789p23s99s"), melds: [], win: t1("1s"), context: WinContext(tsumo: false))
        #expect(try score(req, rules: .mahjongSoul).payment == .ron(1500))
        func error(_ r: ScoreRequest, _ rules: Rules = .mahjongSoul) -> ScoreError? {
            do { _ = try score(r, rules: rules); return nil } catch { return error }
        }
        var bad = req
        bad.honba = Int.max
        #expect(error(bad) == .badHonba)
        bad.honba = -1
        #expect(error(bad) == .badHonba)
        bad = req
        bad.hand = t("123456m789p23s9s")
        #expect(error(bad) == .badHandSize)
        bad.hand = t("1111m23456m789p3s")  // and a fifth 1m wins
        bad.win = t1("1m")
        #expect(error(bad) == .impossibleTiles)
        bad = req
        bad.dora = t("9s")  // 9s9s in hand + indicator: three, fine
        #expect(error(bad) == nil)
        bad.dora = t("9s9s9s")  // five 9s
        #expect(error(bad) == .impossibleTiles)
        bad.dora = t("1z2z3z4z5z6z")  // six indicators: not checked (the corpus has eight)
        #expect(error(bad) == nil)
        var rules = Rules.mahjongSoul
        rules.doubleWindPairFu = 3
        #expect(error(req, rules) == .badRules)
        req.melds = [Meld(kind: .pon, tiles: t("111z"))!, Meld(kind: .pon, tiles: t("222z"))!, Meld(kind: .pon, tiles: t("333z"))!,
                     Meld(kind: .pon, tiles: t("444z"))!, Meld(kind: .pon, tiles: t("555z"))!]
        #expect(error(req) == .badHandSize)
    }

    /// `LegalRequest.actions` checks its request (Codex final finding 3, the same
    /// for the other hypothetical entry point).
    @Test func legalRequestsAreChecked() {
        let draw = Situation.draw(t1("1m"))
        #expect(throws: InputError.self) { try LegalRequest(hand: t("1m"), melds: [], situation: draw, rules: .tenhou).actions }
        #expect(throws: InputError.self) {
            try LegalRequest(hand: t("1111m23456789p"), melds: [], situation: draw, rules: .tenhou).actions
        }
        #expect(throws: InputError.self) {
            try LegalRequest(hand: t("123456789m1234p"), melds: [], situation: draw, wall: 71, rules: .tenhou).actions
        }
        #expect((try? LegalRequest(hand: t("123456789m1234p"), melds: [], situation: draw, rules: .tenhou).actions) != nil)
    }
}

@Suite struct WinRequestTests {
    /// Gemini final finding 2 (its reproduction): seats 1 and 2 both may ron seat
    /// 0's 4s with two honba.
    static let wall = makeWall(hands: ["1m4m7m1p4p7p2s5s8s1z2z3z4z", "234m567p234s56s88p",
                                       "234m567p234s56s88m", "3m6m9m3p6p9p1s9s1z2z3z4z6z"], draws: "4s")

    @Test func honbaFollowTheAnswers() throws {
        var s = try RoundState(rules: .mahjongSoul, wall: Self.wall, honba: 2)
        try s.apply(.discard(t1("4s"), tsumogiri: true), by: Seat(0))
        #expect(s.seatsToAnswer == [Seat(1), Seat(2)])
        func answers(_ a1: Action, _ a2: Action) -> Answers {
            var a = Answers(); a[Seat(1)] = a1; a[Seat(2)] = a2; return a
        }
        // Seat 2 alone wins: it is paid the honba (the old request said 0).
        #expect(s.winRequest(for: Seat(2), answers: answers(.pass, .ron))?.honba == 2)
        #expect(s.winRequest(for: Seat(2))?.honba == 2)
        // Both win: the nearest (seat 1) takes them.
        #expect(s.winRequest(for: Seat(1), answers: answers(.ron, .ron))?.honba == 2)
        #expect(s.winRequest(for: Seat(2), answers: answers(.ron, .ron))?.honba == 0)
        #expect(s.winRequest(for: Seat(2), answers: answers(.ron, .pass)) == nil)
        // The request scores what settlement pays: 2000 + 600.
        var paid = s
        try paid.resolve(answers(.pass, .ron))
        let req = try #require(s.winRequest(for: Seat(2), answers: answers(.pass, .ron)))
        #expect(try score(req, rules: .mahjongSoul).payment.total == paid.result!.deltas[2])
        // Every winner collects under `honbaToEveryRonWinner`.
        var every = Rules.mahjongSoul
        every.honbaToEveryRonWinner = true
        var e = try RoundState(rules: every, wall: Self.wall, honba: 2)
        try e.apply(.discard(t1("4s"), tsumogiri: true), by: Seat(0))
        #expect(e.winRequest(for: Seat(2), answers: answers(.ron, .ron))?.honba == 2)
    }
}

@Suite struct EastGameTests {
    /// Codex final finding 4 (its probe): an East-only game with two sticks carried
    /// in and an unreachable target plays East and South and ends at
    /// `extensionOver`; the sticks go to first place, and both the seat's folded
    /// table and `GameState.view(of:)` show the final scores and no sticks.
    @Test func terminalViewHasTheFinalScores() throws {
        var rules = Rules.mahjongSoul
        rules.length = .east
        rules.targetPoints = 1_000_000
        var events: [Event] = []
        var game = try GameState(rules: rules, seed: 0,
                                 position: try GamePosition(sticks: 2, scores: [25_000, 25_000, 25_000, 25_000]),
                                 events: &events)
        var folders = Seat.all.map(ViewFolder.init)
        func fold() { for s in Seat.all { for e in events { folders[s.index].apply(e.masked(for: s)) } } }
        fold()
        var winds: Set<Wind> = []
        while !game.isOver {
            winds.insert(game.position.roundWind)
            events = []
            if case .turn(let seat, _) = game.phase {
                try game.apply(game.legalActions(for: seat).first { if case .discard(_, true) = $0 { true } else { false } }!,
                               by: seat, events: &events)
            } else {
                var answers = Answers()
                for seat in game.seatsToAnswer { answers[seat] = .pass }
                try game.resolve(answers, events: &events)
            }
            fold()
        }
        let result = try #require(game.result)
        #expect(winds == [.east, .south] && result.end == .extensionOver && result.sticksAwarded >= 2)
        for s in Seat.all {
            let v = game.view(of: s)
            #expect(v.table.scores == result.scores && v.table.sticks == 0 && v.legalActions.isEmpty)
            #expect(folders[s.index].table == v.table)
        }
    }

    /// Gemini final finding 8: whole East-only games through `GameState` with the
    /// test bots: only East and South are played, South only as the extension, and
    /// every game ends by a rule of design §5.
    @Test(arguments: [Bot.eager, .random]) func wholeEastGames(_ bot: Bot) throws {
        for ruleset in [Rules.mahjongSoul, .tenhou] {
            var rules = ruleset
            rules.length = .east
            var ends: [GameEnd: Int] = [:]
            var reachedSouth = 0
            for seed in 0..<40 as Range<UInt64> {
                var rng = TestRNG(state: seed &+ 500)
                var events: [Event] = []
                var g = try GameState(rules: rules, seed: seed, events: &events)
                var winds: Set<Wind> = []
                var n = 0
                while !g.isOver && n < 20_000 {
                    n += 1
                    winds.insert(g.position.roundWind)
                    if case .turn(let s, _) = g.phase {
                        try g.apply(bot.choose(g.round, s, &rng), by: s)
                    } else {
                        var a = Answers()
                        for s in g.seatsToAnswer { a[s] = bot.choose(g.round, s, &rng) }
                        try g.resolve(a)
                    }
                }
                let r = try #require(g.result)
                ends[r.end, default: 0] += 1
                #expect(winds.isSubset(of: [.east, .south]))
                if winds.contains(.south) { reachedSouth += 1 }
                #expect(r.scores.reduce(0, +) == 4 * rules.startingPoints)
            }
            #expect(reachedSouth > 0, "\(bot): no game went into the South extension")
            #expect(ends[.extensionOver, default: 0] + ends[.target, default: 0] + ends[.dealerFirst, default: 0]
                    + ends[.belowZero, default: 0] == 40)
        }
    }
}

@Suite struct PaoTransactionTests {
    /// Codex final review, test strength: exact payments for a composite yakuman
    /// under pao, by `paoCoversWholeHand`, on a ron from a third seat and on a tsumo.
    /// The dealer (seat 0) wins daisangen + tsuuiisou (96,000) with two honba; seat 2
    /// fed the third dragon. The liable seat pays the honba.
    @Test(arguments: [false, true]) func compositeYakuman(_ whole: Bool) throws {
        let wall = makeWall(hands: ["234m1112556677z", "147m147p258s2356z", "258m258p369s2347z", "369m369p147s1344z"],
                            draws: "8p8s9s5p6p6s8m7s2z")
        for tsumo in [false, true] {
            var rules = Rules.mahjongSoul
            rules.paoCoversWholeHand = whole
            var events: [Event] = []
            var round = try RoundState(rules: rules, wall: wall, honba: 2)
            try round.tsumogiri(0, events: &events)
            for (index, dragon) in ["5z", "6z", "7z"].enumerated() {
                let from = index == 2 ? 2 : 1
                if index == 2 {
                    try round.tsumogiri(1, events: &events)
                    if !round.seatsToAnswer.isEmpty { try round.answer(events: &events) }
                }
                try round.apply(.discard(t1(dragon), tsumogiri: false), by: Seat(from))
                try round.answer([0: .pon(t1(dragon), t1(dragon))], events: &events)
                try round.apply(.discard(t1(["2m", "3m", "4m"][index]), tsumogiri: false), by: Seat(0))
                if !round.seatsToAnswer.isEmpty { try round.answer(events: &events) }
            }
            if tsumo {
                for index in 1...3 {
                    try round.tsumogiri(index, events: &events)
                    if !round.seatsToAnswer.isEmpty { try round.answer(events: &events) }
                }
                try round.apply(.tsumo, by: Seat(0))
            } else {
                try round.apply(.discard(t1("2z"), tsumogiri: false), by: Seat(1))
                try round.answer([0: .ron], events: &events)
            }
            let win = try #require(round.result?.wins.first)
            #expect(win.scored.value == .yakuman(2) && win.liable == Seat(2))
            let want = tsumo
                ? (whole ? [96_600, 0, -96_600, 0] : [96_600, -16_000, -64_600, -16_000])
                : (whole ? [96_600, -48_000, -48_600, 0] : [96_600, -72_000, -24_600, 0])
            #expect(win.deltas == want, "whole \(whole) tsumo \(tsumo)")
        }
    }
}
