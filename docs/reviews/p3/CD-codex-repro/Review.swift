import Riichi
import RiichiMjai

struct Batch: Equatable {
    var events: [MaskedEvent]
    var view: PlayerView?
}

struct Observation {
    var batches: [Batch] = []
    var stream: [MaskedEvent] { batches.flatMap(\.events) }
    var wire: [[UInt8]] { stream.map { Array(Mjai.encode($0).utf8) } }
    // Compare the whole view at each decision, keyed by its preceding event.
    var decisions: [Int: PlayerView] {
        var offset = 0
        var result: [Int: PlayerView] = [:]
        for batch in batches {
            offset += batch.events.count
            if let view = batch.view { result[offset] = view }
        }
        return result
    }
}

func play(_ seed: UInt64, _ rules: Rules, _ observer: Seat, _ wall: Wall,
          openingAbort: Bool = false) throws -> (Observation, firstKans: Int) {
    var events: [Event] = []
    let position = GamePosition(scores: Array(repeating: rules.startingPoints, count: 4))
    var game = GameState(rules: rules, seed: seed, position: position, wall: wall, events: &events)
    var bots = Seat.all.map { seat in
        BuiltinBot(kind: seed.isMultiple(of: 2) ? .eager : .random,
                   rng: BotRNG(state: seed &* 0x2545_F491_4F6C_DD1D &+ UInt64(seat.index + 1)))
    }
    var seen = Observation()
    var firstKans = 0
    while true {
        let masked = events.map { $0.masked(for: observer) }
        let view = game.legalActions(for: observer).isEmpty ? nil : game.round.view(of: observer)
        seen.batches.append(Batch(events: masked, view: view))
        if game.isOver { break }
        if game.handsDealt == 1 { firstKans = max(firstKans, game.round.kanCount) }
        let isOpening = seen.batches.count == 1
        events = []
        if case .turn(let seat, _) = game.phase {
            let action: Action
            if openingAbort && isOpening {
                precondition(game.legalActions(for: seat).contains(.kyuushu))
                action = .kyuushu
            } else {
                action = bots[seat.index].receive([], view: game.round.view(of: seat))!
            }
            try game.apply(action, by: seat, events: &events)
        } else {
            var answers = Answers()
            for seat in game.seatsToAnswer {
                answers[seat] = bots[seat.index].receive([], view: game.round.view(of: seat))!
            }
            try game.resolve(answers, events: &events)
        }
    }
    return (seen, firstKans)
}

func swapping(_ wall: Wall, _ lhs: Int, _ rhs: Int) -> Wall {
    var tiles = wall.tiles
    precondition(tiles[lhs] != tiles[rhs])
    tiles.swapAt(lhs, rhs)
    return Wall(tiles: tiles)!
}

func assertSame(_ a: Observation, _ b: Observation) {
    precondition(a.stream == b.stream)
    precondition(a.wire == b.wire)
    precondition(a.decisions == b.decisions)
    precondition(a.batches == b.batches)
}

func selfPlay() throws {
    var deadSwaps = 0
    var concealedSwaps = 0
    for seed in UInt64(0)..<256 {
        let rules: Rules = seed.isMultiple(of: 2) ? .tenhou : .mahjongSoul
        let seat = Seat(Int((seed / 2) % 4))
        let wall = Wall(seed: seed, hand: 0)
        let (baseline, kans) = try play(seed, rules, seat, wall)
        // These slots are never exposed unless the first hand has a fourth kan.
        if kans < 4 && wall.tiles[130] != wall.tiles[135] {
            let (other, _) = try play(seed, rules, seat, swapping(wall, 130, 135))
            assertSame(baseline, other)
            deadSwaps += 1
        }
    }
    // Force a public nine-terminals abort so the two opponent deals can stay
    // concealed for the entire first hand. Play the rest with the ordinary bots.
    for seed in UInt64(0)..<64 {
        let rules: Rules = seed.isMultiple(of: 2) ? .tenhou : .mahjongSoul
        let seat = Seat(1)
        var tiles = Wall(seed: seed, hand: 0).tiles
        let dealerSlots = [0, 1, 2, 3, 16, 17, 18, 19, 32]
        for (i, slot) in dealerSlots.enumerated() {
            let kind = Kind.yaochu[i]
            let src = tiles.indices.first {
                !dealerSlots.prefix(i).contains($0) && tiles[$0].kind == kind
            }!
            tiles.swapAt(slot, src)
        }
        let wall = Wall(tiles: tiles)!
        if wall.tiles[8] == wall.tiles[12] || wall.tiles[52 + 69] == wall.tiles[125] { continue }
        let (a, _) = try play(seed, rules, seat, wall, openingAbort: true)
        let (b, _) = try play(seed, rules, seat, swapping(wall, 8, 12), openingAbort: true)
        assertSame(a, b)
        let (c, _) = try play(seed, rules, seat, swapping(wall, 52 + 69, 125), openingAbort: true)
        assertSame(a, c)
        concealedSwaps += 1
        if concealedSwaps == 24 { break }
    }
    precondition(deadSwaps >= 230 && concealedSwaps == 24)
    print("Identical full streams, wire bytes, callback batches and decision views: \(deadSwaps) dead-wall pairs, \(concealedSwaps) concealed-deal pairs and \(concealedSwaps) undrawn live/replacement pairs")
}

func batchingLeak() throws {
    let dealer = Seat(0)
    let observer = Seat(3)
    let position = GamePosition(scores: [25000, 25000, 25000, 25000])
    let rules = Rules.tenhou
    func probe(_ wall: Wall) throws -> (steps: [Batch], asked: [Seat],
                                        afterDiscard: PlayerView, final: PlayerView) {
        var events: [Event] = []
        var game = GameState(rules: rules, seed: 0, position: position, wall: wall, events: &events)
        var steps = [Batch(events: events.map { $0.masked(for: observer) }, view: nil)]
        events = []
        try game.apply(.discard(wall.liveDraw(0), tsumogiri: true), by: dealer, events: &events)
        steps.append(Batch(events: events.map { $0.masked(for: observer) }, view: nil))
        let asked = game.seatsToAnswer
        let afterDiscard = game.round.view(of: observer)
        if case .reactions = game.phase {
            precondition(!asked.isEmpty)
            if asked.contains(observer) { return (steps, asked, afterDiscard, game.round.view(of: observer)) }
            var answers = Answers()
            for seat in asked { answers[seat] = .pass }
            events = []
            try game.resolve(answers, events: &events)
            steps.append(Batch(events: events.map { $0.masked(for: observer) }, view: nil))
            return (steps, asked, afterDiscard, game.round.view(of: observer))
        }
        return (steps, [], afterDiscard, game.round.view(of: observer))
    }
    for seed in UInt64(0)..<500 {
        let wall = Wall(seed: seed, hand: 0)
        let a = try probe(wall)
        guard a.asked.isEmpty else { continue }
        for slot in 4..<12 where wall.tiles[slot] != wall.tiles[135] {
            let b = try probe(swapping(wall, slot, 135))
            guard !b.asked.isEmpty && !b.asked.contains(observer) else { continue }
            precondition(a.steps.flatMap(\.events) == b.steps.flatMap(\.events))
            precondition(a.final == b.final)
            precondition(a.steps != b.steps)
            precondition(a.afterDiscard.legalActions.isEmpty && b.afterDiscard.legalActions.isEmpty)
            precondition(a.afterDiscard.table.reacting == nil && b.afterDiscard.table.reacting != nil)
            let beforeOffer = wall.tiles[slot]
            let afterOffer = wall.tiles[135]
            print("Batch leak seed \(seed), wall slots \(slot)/135 (\(beforeOffer)/\(afterOffer)), discard \(wall.liveDraw(0)), asked \(b.asked), batch sizes \(a.steps.map { $0.events.count }) vs \(b.steps.map { $0.events.count })")
            return
        }
    }
    preconditionFailure("missing batching counterexample")
}

func customTrace() throws {
    var rules = Rules.tenhou
    rules.length = .east
    let names = Array(repeating: "eager", count: 4)
    let label = names.joined(separator: ",")
    for seed in UInt64(0)..<20 {
        var bots: [any Player] = Seat.all.map {
            BuiltinBot(kind: .eager, rng: BotRNG(state: seed &+ UInt64($0.index)))
        }
        let record = try playGame(rules: rules, seed: seed, players: &bots, names: names,
                                  observers: [], botsLabel: label)
        let trace = try parseTrace(record.trace)
        precondition(trace.rules == .mahjongSoul)
        let queue = Decisions(trace.decisions)
        var replay: [any Player] = Seat.all.map { TracePlayer(seat: $0, queue: queue) }
        do {
            let result = try playGame(rules: trace.rules, seed: trace.seed, players: &replay,
                                      names: names, observers: [], botsLabel: trace.bots)
            if result.log == record.log { continue }
            print("Custom East-only Tenhou trace seed \(seed): replay log differs")
        } catch {
            print("Custom East-only Tenhou trace seed \(seed): replay failed: \(error)")
        }
        return
    }
    preconditionFailure("missing custom trace counterexample")
}

@main struct Review {
    static func main() throws {
        try batchingLeak()
        try selfPlay()
        try customTrace()
    }
}
