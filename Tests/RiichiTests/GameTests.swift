// Package C (GameState, the after-round transition, GameResult) and the parts of
// package D that live in Riichi (masked events, PlayerView and its fold).

import Testing
@testable import Riichi

/// Plays whole games through `GameState` with the test bots.
func playGame(rules: Rules, seed: UInt64, bot: Bot, rng: inout TestRNG,
              step: (GameState, [Event]) throws -> Void = { _, _ in }) throws -> (GameState, [Event]) {
    var events: [Event] = []
    var g = GameState(rules: rules, seed: seed, events: &events)
    var all = events
    try step(g, events)
    var n = 0
    while !g.isOver {
        n += 1
        if n > 20_000 { Issue.record("game does not end"); break }
        events = []
        if case .turn(let s, _) = g.phase {
            try g.apply(bot.choose(g.round, s, &rng), by: s, events: &events)
        } else {
            var a = Answers()
            for s in g.seatsToAnswer { a[s] = bot.choose(g.round, s, &rng) }
            try g.resolve(a, events: &events)
        }
        all += events
        try step(g, events)
    }
    return (g, all)
}

@Suite struct GameTests {
    @Test(arguments: [(Bot.eager, "mahjongsoul"), (.eager, "tenhou"), (.random, "tenhou")])
    func wholeGames(_ bot: Bot, _ ruleset: String) throws {
        let rules: Rules = ruleset == "tenhou" ? .tenhou : .mahjongSoul
        var ends: [GameEnd: Int] = [:]
        for seed in 0..<40 as Range<UInt64> {
            var rng = TestRNG(state: seed)
            let (g, events) = try playGame(rules: rules, seed: seed, bot: bot, rng: &rng)
            let r = try #require(g.result)
            ends[r.end, default: 0] += 1
            // Points: final scores carry every point; adjusted scores sum to zero.
            #expect(r.scores.reduce(0, +) == 4 * rules.startingPoints)
            #expect(r.adjusted.reduce(0, +) == 0)
            #expect(r.ranks.map { r.scores[$0.index] } == r.ranks.map { r.scores[$0.index] }.sorted(by: >))
            // One start_game, one end_game last, carrying the final scores.
            #expect(events.first == .startGame)
            #expect(events.last == .endGame(scores: r.scores))
            #expect(events.count(where: { $0 == .startGame }) == 1)
            // Each hand's header follows from the last.
            let starts = events.compactMap { e -> GamePosition? in
                if case .startKyoku(let b, let k, let h, let s, let o, _, let sc, _) = e {
                    #expect(o.index == k - 1)
                    return GamePosition(roundWind: b, kyoku: k, honba: h, sticks: s, scores: sc)
                }
                return nil
            }
            #expect(starts.count == g.handsDealt)
            #expect(starts.first == GamePosition(scores: Array(repeating: rules.startingPoints, count: 4)))
        }
        print("game ends \(bot) \(ruleset): \(ends)")
    }

    @Test func transitions() {
        let rules = Rules.mahjongSoul
        func result(_ scores: [Int], dealer: Int, repeats: Bool, outcome: RoundResult.Outcome = .exhaustiveDraw(tenpai: [], nagashi: []),
                    sticks: Int = 0) -> RoundResult {
            RoundResult(outcome: outcome, deltas: [0, 0, 0, 0], scores: scores, sticks: sticks, dealer: Seat(dealer),
                        dealerRepeats: repeats)
        }
        let even = [25_000, 25_000, 25_000, 25_000]
        // Ordinary: the deal passes, honba +1 after a draw.
        var (n, t) = GameFlow.next(after: result(even, dealer: 0, repeats: false), at: GamePosition(scores: even), rules: rules)
        #expect(t == .ordinary && n == GamePosition(roundWind: .east, kyoku: 2, honba: 1, scores: even))
        // East 4 to South 1.
        (n, t) = GameFlow.next(after: result(even, dealer: 3, repeats: false), at: GamePosition(kyoku: 4, scores: even), rules: rules)
        #expect(n?.roundWind == .south && n?.kyoku == 1)
        // Below zero ends at once, even with a dealer repeat; zero continues.
        (n, t) = GameFlow.next(after: result([-100, 25_100, 50_000, 25_000], dealer: 0, repeats: true), at: GamePosition(scores: even), rules: rules)
        #expect(n == nil && t == .ends(.belowZero))
        (n, t) = GameFlow.next(after: result([0, 25_000, 50_000, 25_000], dealer: 0, repeats: true), at: GamePosition(scores: even), rules: rules)
        #expect(n != nil)
        // All last, the dealer tied for first is not first (seat-order tie-break).
        let s4 = GamePosition(roundWind: .south, kyoku: 4, scores: even)
        (n, t) = GameFlow.next(after: result([31_000, 20_000, 18_000, 31_000], dealer: 3, repeats: true), at: s4, rules: rules)
        #expect(t == .allLastRepeat && n?.kyoku == 4)
        (n, t) = GameFlow.next(after: result([30_000, 20_000, 18_000, 32_000], dealer: 3, repeats: true), at: s4, rules: rules)
        #expect(t == .ends(.dealerFirst))
        // An abortive draw repeats even for a dealer first on 30,000.
        (n, t) = GameFlow.next(after: result([20_000, 20_000, 20_000, 40_000], dealer: 3, repeats: true, outcome: .abortiveDraw(.kyuushu)), at: s4, rules: rules)
        #expect(t == .allLastRepeat)
        // Nobody on 30,000: into West; in West 4, beyond it the game ends.
        (n, t) = GameFlow.next(after: result([29_000, 21_000, 25_000, 25_000], dealer: 3, repeats: false), at: s4, rules: rules)
        #expect(t == .allLastAdvance && n?.roundWind == .west && n?.kyoku == 1)
        (n, t) = GameFlow.next(after: result([29_000, 21_000, 25_000, 25_000], dealer: 3, repeats: false),
                               at: GamePosition(roundWind: .west, kyoku: 4, scores: even), rules: rules)
        #expect(t == .ends(.extensionOver))
        // A non-dealer on 30,000 while the dealer repeats: the repeat wins unless the
        // Rules field says otherwise.
        (n, t) = GameFlow.next(after: result([31_000, 21_000, 25_000, 23_000], dealer: 3, repeats: true), at: s4, rules: rules)
        #expect(t == .allLastRepeat)
        var r2 = rules
        r2.dealerRepeatBeforeTarget = false
        (n, t) = GameFlow.next(after: result([31_000, 21_000, 25_000, 23_000], dealer: 3, repeats: true), at: s4, rules: r2)
        #expect(t == .ends(.target))
        // East game: East 4 is all last, South is the extension.
        var east = rules
        east.length = .east
        (n, t) = GameFlow.next(after: result([29_000, 21_000, 25_000, 25_000], dealer: 3, repeats: false),
                               at: GamePosition(kyoku: 4, scores: even), rules: east)
        #expect(t == .allLastAdvance && n?.roundWind == .south)
        // Final result: sticks to first, uma and oka (Tenhou).
        let g = GameFlow.result(scores: [30_000, 30_000, 20_000, 18_000], sticks: 2, rules: .tenhou, end: .target)
        #expect(g.ranks == [Seat(0), Seat(1), Seat(2), Seat(3)])
        #expect(g.scores == [32_000, 30_000, 20_000, 18_000])
        #expect(g.adjusted == [32_000 - 30_000 + 20_000 + 20_000, 30_000 - 30_000 + 10_000, 20_000 - 30_000 - 10_000, 18_000 - 30_000 - 20_000])
    }

    /// Folding each seat's masked events rebuilds its view at every point where the
    /// game rests (design §8 layer 4); masked events show no other hand or draw.
    @Test(arguments: [Bot.eager, .random]) func viewsFoldFromMaskedEvents(_ bot: Bot) throws {
        for seed in 0..<12 as Range<UInt64> {
            var rng = TestRNG(state: seed &+ 77)
            var folders = Seat.all.map(ViewFolder.init)
            let rules: Rules = seed % 2 == 0 ? .tenhou : .mahjongSoul
            _ = try playGame(rules: rules, seed: seed, bot: bot, rng: &rng) { g, events in
                for seat in Seat.all {
                    for e in events {
                        let m = e.masked(for: seat)
                        switch m {
                        case .tsumo(let a, let t): #expect((t == nil) == (a != seat))
                        case .startKyoku(_, _, _, _, _, _, _, let th):
                            for (i, h) in th.enumerated() { #expect(h.allSatisfy { ($0 == nil) == (i != seat.index) }) }
                        default: break
                        }
                        folders[seat.index].apply(m)
                    }
                    guard !g.isOver else { continue }
                    let v = g.round.view(of: seat)
                    #expect(folders[seat.index].table == v.table, "seed \(seed) seat \(seat)")
                    #expect(v.legalActions == g.legalActions(for: seat))
                }
            }
        }
    }
}
