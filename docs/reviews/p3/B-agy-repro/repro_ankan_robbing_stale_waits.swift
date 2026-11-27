// Reproduction for Finding 2:
// announceClosedKan mutates hand and clears drawn without updating counts or waits,
// so waits(of:) and isFuriten(_:) return stale pre-ankan values while the robbing
// window (.robbing(.closed)) is open (and during the observe callback for .ankan).

import Riichi

func makeWall(hands: [String], draws: String = "", rinshan: String = "", dora: String = "3z") -> Wall {
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

@main struct ReproAnkanStaleWaits {
    static func main() throws {
        // Seat 0 holds 1111m 234p 567p 88s 4z (not tenpai: waits == []).
        // Seat 0 draws 8s, then declares ankan(1m).
        // Seat 0's concealed hand is now 234p 567p 888s 4z (tanki on 4z!).
        // Seat 1 holds kokushi waiting on 1m, so .robbing(.closed) opens.
        let wall = makeWall(
            hands: [
                "1111m234p567p88s4z",
                "99m19p19s1234567z",
                "234m567m234s567s2z",
                "345m678m345s678s2z",
            ],
            draws: "8s",
            rinshan: "7s"
        )
        var s = RoundState(rules: .mahjongSoul, wall: wall)
        assert(s.waits(of: Seat(0)).isEmpty)
        try s.apply(.ankan(Tile("1m")!.kind), by: Seat(0))
        guard case .robbing(let pk) = s.phase, pk.kind == .closed else {
            fatalError("Expected .robbing(.closed) phase")
        }
        let w = s.waits(of: Seat(0))
        print("During .robbing(.closed), Seat 0 hand = \(mpsz(s.hand(of: Seat(0)))), waits = \(w) (expected [4z])")
        precondition(w == [Tile("4z")!.kind], "BUG REPRODUCED: stale waits during .robbing(.closed): got \(w)")
    }
}
