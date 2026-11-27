// Compile into the Riichi module to construct exact RoundResult fixtures.
func outcome(_ p: GamePosition, _ scores: [Int], _ repeats: Bool,
             _ kind: RoundResult.Outcome = .exhaustiveDraw(tenpai: [], nagashi: []),
             sticks: Int = 0) -> RoundResult {
    RoundResult(outcome: kind, deltas: zip(scores, p.scores).map(-), scores: scores,
                sticks: sticks, dealer: p.dealer, dealerRepeats: repeats)
}

func transitionMatrix() {
    let even = [25000, 25000, 25000, 25000]
    for preset in [Rules.tenhou, .mahjongSoul] {
        for length in [GameLength.east, .south] {
            var rules = preset
            rules.length = length
            let last: Wind = length == .east ? .east : .south
            let p = GamePosition(roundWind: last, kyoku: 4, honba: 2, scores: even)
            let ext = GamePosition(roundWind: last.next, kyoku: 4, honba: 2, scores: even)
            let early = GamePosition(roundWind: last, kyoku: 3, scores: even)
            func step(_ at: GamePosition, _ scores: [Int], _ repeats: Bool,
                      _ kind: RoundResult.Outcome = .exhaustiveDraw(tenpai: [], nagashi: []),
                      sticks: Int = 0, test: [Int]? = nil) -> (GamePosition?, GameTransition) {
                GameFlow.next(after: outcome(at, scores, repeats, kind, sticks: sticks),
                              at: at, rules: rules, testScores: test)
            }
            precondition(step(early, [30000, 25000, 25000, 20000], false).1 == .ordinary)
            precondition(step(p, [0, 29000, 29000, 29000], false).1 == .allLastAdvance)
            precondition(step(p, [-100, 29000, 29000, 29000], true).1 == .ends(.belowZero))
            let extensionStart = step(p, [29000, 23000, 23000, 23000], false, sticks: 2)
            precondition(extensionStart.0 == GamePosition(roundWind: last.next, kyoku: 1,
                         honba: 3, sticks: 2, scores: [29000, 23000, 23000, 23000]))
            precondition(step(ext, even, false).1 == .ends(.extensionOver))
            precondition(step(ext, even, true, .abortiveDraw(.kyuushu)).0?.honba == 3)
            precondition(step(ext, [30000, 20000, 20000, 30000], true).1 == .allLastRepeat)
            precondition(step(ext, [29900, 20100, 20000, 30000], true).1 == .ends(.dealerFirst))
            precondition(step(ext, [30000, 25000, 25000, 20000], false).1 == .ends(.target))
            let firstExtension = extensionStart.0!
            precondition(step(firstExtension, [30000, 30000, 20000, 20000], true).1 == .ends(.dealerFirst))
            let final = GameFlow.result(scores: [30000, 30000, 20000, 18000], sticks: 2,
                                        rules: rules, end: .target)
            precondition(final.ranks == Seat.all && final.scores == [32000, 30000, 20000, 18000])
            precondition(final.adjusted == (preset == .tenhou
                         ? [42000, 10000, -20000, -32000] : [22000, 10000, -10000, -22000]))
            let after = [38000, 23000, 23000, 16000]
            let before = [26000, 27000, 27000, 20000]
            let nagashi = RoundResult.Outcome.exhaustiveDraw(tenpai: [p.dealer], nagashi: [Seat(0)])
            precondition(step(p, after, true, nagashi, test: before).1 == .allLastRepeat)
            rules.dealerRepeatBeforeTarget = false
            precondition(step(p, after, true, nagashi).1 == .ends(.target))
        }
    }
    let scored = Scored(yaku: [], value: .ordinary(han: 1, fu: 30), payment: .ron(1000))
    func win(_ winner: Int) -> Win {
        Win(winner: Seat(winner), from: Seat(2), tile: Tile(Kind(.man, 1)), scored: scored,
            doraIndicators: [], uraIndicators: [], deltas: [0, 0, 0, 0], liable: nil, robbedKan: nil)
    }
    let p = GamePosition(honba: 2, scores: even)
    precondition(outcome(p, even, false, .wins([win(1), win(3)])).nextHonba(after: 2) == 0)
    precondition(outcome(p, even, true, .wins([win(3), win(0)])).nextHonba(after: 2) == 3)
    print("Both presets × both lengths: transition and settlement controls passed")
}

func playFirstHand(_ game: inout GameState) throws {
    while game.handsDealt == 1 && !game.isOver {
        if case .turn(let seat, _) = game.phase {
            try game.apply(.discard(game.round.drawnTile(of: seat)!, tsumogiri: true), by: seat)
        } else {
            var answers = Answers()
            for seat in game.seatsToAnswer { answers[seat] = .pass }
            try game.resolve(answers)
        }
    }
}

func nagashiToggle() throws {
    // Taken from scenarios/endgame_nagashi_pushes_dealer_out_of_first.scn.
    let hands = ["2233m4455p2234s7z", "4455m6677p4456s7z", "6677m2233p6678s7z",
                 "234678m234p56s88p"]
    let nagashiDraws = ["1m", "1m", "9m", "9m", "1p", "1p", "9p", "9p", "1s",
                        "1s", "9s", "9s", "1z", "2z", "3z", "4z", "5z", "6z"]
    let p = GamePosition(roundWind: .south, kyoku: 4, scores: [25000, 25000, 19000, 31000])
    var tiles = [Tile?](repeating: nil, count: Wall.count)
    for seat in Seat.all {
        let offset = seat.distance(from: p.dealer)
        let slots = [0, 16, 32].flatMap { first in (0..<4).map { first + offset * 4 + $0 } }
                  + [48 + offset]
        for (slot, tile) in zip(slots, parseTiles(hands[seat.index][...])!) { tiles[slot] = tile }
    }
    for (i, tile) in nagashiDraws.enumerated() { tiles[52 + 1 + 4 * i] = parseTiles(tile[...])![0] }
    for (slot, tile) in [(52, "5p"), (54, "0s"), (55, "8m"), (126, "5m")] {
        tiles[slot] = parseTiles(tile[...])![0]
    }
    var pool = Wall.sorted
    for tile in tiles.compactMap({ $0 }) { pool.remove(at: pool.firstIndex(of: tile)!) }
    var remaining = pool.makeIterator()
    let wall = Wall(tiles: tiles.map { $0 ?? remaining.next()! })!
    for after in [true, false] {
        var rules = Rules.mahjongSoul
        rules.allLastTestAfterNagashi = after
        var events: [Event] = []
        var game = GameState(rules: rules, seed: 0, position: p, wall: wall, events: &events)
        try playFirstHand(&game)
        let last = game.lastRound!
        precondition(last.result.scores == [33000, 23000, 17000, 27000])
        precondition(last.result.outcome == .exhaustiveDraw(tenpai: [Seat(3)], nagashi: [Seat(0)]))
        precondition(last.transition == (after ? .allLastRepeat : .ends(.dealerFirst)))
        precondition(game.isOver == !after)
    }
    print("Nagashi score-timing toggle passed on an actual South 4.")
}

func northFour() throws {
    let initial = GamePosition(roundWind: .north, kyoku: 4, scores: [25000, 25000, 25000, 25000])
    for seed in UInt64(0)..<32 {
        var events: [Event] = []
        var game = GameState(rules: .tenhou, seed: seed, position: initial, events: &events)
        try playFirstHand(&game)
        guard let last = game.lastRound, !last.result.dealerRepeats,
              last.result.scores.allSatisfy({ $0 >= 0 && $0 < 30000 }) else { continue }
        precondition(last.result.outcome == .exhaustiveDraw(tenpai: [], nagashi: []))
        precondition(game.position.roundWind == .east && game.position.kyoku == 1 && !game.isOver)
        print("North 4 seed \(seed), scores \(last.result.scores): \(last.transition) to East 1")
        return
    }
    preconditionFailure("missing North 4 counterexample")
}

@main struct Flow {
    static func main() throws {
        if CommandLine.arguments.contains("overflow") {
            var rules = Rules.tenhou
            rules.returnPoints = 600_025_000
            print(GameFlow.result(scores: [30000, 30000, 20000, 20000],
                                  sticks: 0, rules: rules, end: .target).adjusted)
            return
        }
        transitionMatrix()
        try northFour()
        try nagashiToggle()
        for seed in [UInt64(0), 123456, UInt64.max] {
            print(Wall(seed: seed, hand: 7).tiles.map(\.description).joined(separator: " "))
        }
    }
}
