// Standalone reproduction for Finding 1:
// Declining a self-drawn win outside riichi under Tenhou rules does not set
// temporary furiten (docs/design/engine.md §4.2).
//
// Run with a SwiftPM package depending on this repo's Riichi library.

import Riichi

func makeWall(hands: [String], draws: String) -> Wall {
    var pool = Wall.sorted
    func take(_ t: Tile) -> Tile {
        let i = pool.firstIndex(of: t)!
        pool.remove(at: i)
        return t
    }
    var slots = [Tile?](repeating: nil, count: 136)
    let hs = hands.map { parseTiles(Substring($0))! }
    var cursor = [0, 0, 0, 0], w = 0
    for round in 0..<4 {
        for s in 0..<4 {
            for _ in 0..<(round < 3 ? 4 : 1) {
                slots[w] = take(hs[s][cursor[s]]); cursor[s] += 1; w += 1
            }
        }
    }
    for (i, x) in parseTiles(Substring(draws))!.enumerated() { slots[52 + i] = take(x) }
    var rest = pool.makeIterator()
    return Wall(tiles: slots.map { $0 ?? rest.next()! })!
}

@main struct Repro {
    static func main() throws {
        // Seat 0 holds 234m 678m 234p 4567s (waits: 4s, 7s), draws 4s, discards 7s
        // (now tanki on 4s; 4s is not in Seat 0's pond). Seat 1 then discards 4s.
        let wall = makeWall(
            hands: [
                "234m678m234p4567s",
                "4s1199m1199p1122z",
                "147m147p258s2345z",
                "3344m5588p6688s6z",
            ],
            draws: "4s7z5z5z3z"
        )
        var s = RoundState(rules: .tenhou, wall: wall)
        assert(s.legalActions(for: Seat(0)).contains(.tsumo))
        try s.apply(.discard(Tile("7s")!, tsumogiri: false), by: Seat(0))
        print("After Seat 0 declines tsumo 4s and discards 7s (Tenhou rules):")
        print("  Seat 0 waits: \(s.waits(of: Seat(0)))")
        print("  Seat 0 isFuriten: \(s.isFuriten(Seat(0))) (expected: true)")
        // Seat 1 discards 4s
        try s.apply(.discard(Tile("4s")!, tsumogiri: false), by: Seat(1))
        print("After Seat 1 discards 4s:")
        print("  Seat 0 legalActions: \(s.legalActions(for: Seat(0))) (expected: [])")
        assert(s.isFuriten(Seat(0)), "BUG REPRODUCED: Seat 0 should be temporarily furiten under Tenhou")
    }
}
