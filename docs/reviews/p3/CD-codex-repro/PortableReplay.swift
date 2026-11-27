import Riichi

@main struct PortableReplay {
    static func main() throws {
        for rules in [Rules.tenhou, .mahjongSoul] {
            for seed in [UInt64(0), 51, 123456, UInt64.max] {
                let kind: BotKind = seed.isMultiple(of: 2) ? .eager : .random
                let names = Array(repeating: kind.rawValue, count: 4)
                let label = names.joined(separator: ",")
                var bots: [any Player] = Seat.all.map { seat in
                    BuiltinBot(kind: kind, rng: BotRNG(state: seed &+ UInt64(seat.index)))
                }
                let legality = LegalityRows(file: "portable.jsonl")
                let first = try playGame(rules: rules, seed: seed, players: &bots, names: names,
                                         observers: [legality], botsLabel: label)
                let trace = try parseTrace(first.trace)
                let decisions = Decisions(trace.decisions)
                var replay: [any Player] = Seat.all.map { TracePlayer(seat: $0, queue: decisions) }
                let second = try playGame(rules: trace.rules, seed: trace.seed, players: &replay,
                                          names: names, observers: [], botsLabel: trace.bots)
                precondition(decisions.mismatch == nil && decisions.i == decisions.items.count)
                precondition(first.log.utf8.elementsEqual(second.log.utf8))
                print(first.trace, terminator: "")
                print(first.log, terminator: "")
                print(legality.text, terminator: "")
            }
        }
    }
}
