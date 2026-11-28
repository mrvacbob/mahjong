// Reproduction for Finding 1:
// Triple kokushi ron (sanchahou) robbing a closed kan (ankan) when both
// Rules.kokushiRobsClosedKan and Rules.tripleRonAborts are true drops one of the
// four kan tiles from RoundState, violating tile conservation (135 tiles in play
// instead of 136).

import Riichi

func makeWall(hands: [String], draws: String = "", rinshan: String = "", dora: String = "2m") -> Wall {
    var pool = Wall.sorted
    func take(_ t: Tile) -> Tile {
        guard let i = pool.firstIndex(of: t) else { fatalError("tile \(t) over-allocated") }
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
    for (i, x) in parseTiles(Substring(rinshan))!.enumerated() { slots[122 + i] = take(x) }
    for (i, x) in parseTiles(Substring(dora))!.enumerated() { slots[126 + i] = take(x) }
    var rest = pool.makeIterator()
    return Wall(tiles: slots.map { $0 ?? rest.next()! })!
}

@main struct ReproSanchahouAnkan {
    static func main() throws {
        // Seat 0 holds 1111m (declares ankan 1m).
        // Seats 1, 2, 3 each hold single-wait kokushi on 1m (4 copies of 9m, 1p, 1s;
        // 3 copies of 9p, 9s, 1z..7z — all within the 136-tile set).
        let wall = makeWall(
            hands: [
                "1111m234p567p234s",
                "99m19p19s1234567z",
                "9m119p19s1234567z",
                "9m19p119s1234567z",
            ],
            draws: "5s",
            rinshan: "6s"
        )
        var rules = Rules.tenhou
        rules.kokushiRobsClosedKan = true  // Tenhou + kokushi robs closed kan (tripleRonAborts == true)

        var s = RoundState(rules: rules, wall: wall)
        try s.apply(.ankan(Tile("1m")!.kind), by: Seat(0))
        assert(s.seatsToAnswer == [Seat(1), Seat(2), Seat(3)])

        var answers = Answers()
        answers[Seat(1)] = .ron
        answers[Seat(2)] = .ron
        answers[Seat(3)] = .ron
        try s.resolve(answers)

        assert(s.result?.outcome == .abortiveDraw(.sanchahou))
        var inPlay: [Tile] = []
        for seat in Seat.all {
            inPlay += s.hand(of: seat)
            if let d = s.drawnTile(of: seat) { inPlay.append(d) }
            inPlay += s.melds(of: seat).flatMap(\.tiles)
            inPlay += s.pond(of: seat).filter { !$0.calledAway }.map(\.tile)
        }
        let expectedCount = 52 + 1  // 52 dealt + 1 live draw
        print("After triple-ron sanchahou on ankan(1m):")
        print("  Seat 0 hand count: \(s.hand(of: Seat(0)).count), drawn: \(String(describing: s.drawnTile(of: Seat(0))))")
        print("  Seat 0 1m count:   \(s.hand(of: Seat(0)).count(where: { $0 == Tile("1m")! })) (expected 4 total across hand+drawn)")
        print("  Total tiles in play: \(inPlay.count) (expected \(expectedCount))")
        precondition(inPlay.count == expectedCount, "BUG REPRODUCED: 1m tile lost on sanchahou robbing ankan (\(inPlay.count) != \(expectedCount))")
    }
}
