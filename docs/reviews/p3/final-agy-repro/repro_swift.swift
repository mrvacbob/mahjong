// Reproduces Findings 2, 3, and 5 against Riichi and RiichiMjai.
import Riichi
import RiichiMjai

func t(_ s: String) -> [Tile] { parseTiles(Substring(s))! }
func t1(_ s: String) -> Tile { Tile(Substring(s))! }

func makeWall(hands: [String], draws: String = "", dora: String = "1z") -> Wall {
    var pool = Wall.sorted
    func take(_ tile: Tile) -> Tile {
        let i = pool.firstIndex(of: tile)!
        pool.remove(at: i)
        return tile
    }
    var slots = [Tile?](repeating: nil, count: 136)
    let hs = hands.map(t)
    var cursor = [0, 0, 0, 0], w = 0
    for round in 0..<4 {
        for s in 0..<4 {
            for _ in 0..<(round < 3 ? 4 : 1) {
                slots[w] = take(hs[s][cursor[s]]); cursor[s] += 1; w += 1
            }
        }
    }
    for (i, x) in t(draws).enumerated() { slots[52 + i] = take(x) }
    for (i, x) in t(dora).enumerated() { slots[126 + i] = take(x) }
    var rest = pool.makeIterator()
    return Wall(tiles: slots.map { $0 ?? rest.next()! })!
}

// --- Finding 2: winRequest(for:) wrong honba ---
do {
    let wall = makeWall(
        hands: [
            "1m4m7m1p4p7p2s5s8s1z2z3z4z",
            "234m567p234s56s88p",  // waits 4s/7s (tanyao)
            "234m567p234s56s88m",  // waits 4s/7s (tanyao)
            "3m6m9m3p6p9p1s9s1z2z3z4z6z",
        ],
        draws: "4s"
    )
    var r = Rules.mahjongSoul
    r.honbaToEveryRonWinner = true
    var s1 = RoundState(rules: r, wall: wall, honba: 2)
    try! s1.apply(.discard(t1("4s"), tsumogiri: true), by: Seat(0))
    let req2HonbaAll = s1.winRequest(for: Seat(2))!
    print("[Finding 2a] honbaToEveryRonWinner=true, seat 2 winRequest.honba = \(req2HonbaAll.honba) (expected 2)")

    var s2 = RoundState(rules: .mahjongSoul, wall: wall, honba: 2)
    try! s2.apply(.discard(t1("4s"), tsumogiri: true), by: Seat(0))
    let req2Default = s2.winRequest(for: Seat(2))!
    var ans = Answers()
    ans[Seat(1)] = .pass
    ans[Seat(2)] = .ron
    try! s2.resolve(ans)
    let actualDelta = s2.result!.deltas[2]
    print("[Finding 2b] seat 1 passes, seat 2 rons: winRequest.honba = \(req2Default.honba), actual seat 2 delta = \(actualDelta) (includes 600 honba)")
}

// --- Finding 3: Mjai.action accepts bogus hora target/pai and impossible red-five consumed ---
do {
    let offered = (tile: t1("4s"), from: Seat(1))
    let bogusHora = try! Mjai.decode(#"{"type":"hora","actor":0,"target":3,"pai":"9p"}"#)
    let act1 = Mjai.action(bogusHora, seat: Seat(0), legal: [.ron, .pass], offered: offered)
    print("[Finding 3a] bogus hora (wrong target=3, pai=9p) -> \(String(describing: act1)) (expected nil)")

    let fourReds = try! Mjai.decode(#"{"type":"ankan","actor":0,"consumed":["5mr","5mr","5mr","5mr"]}"#)
    let act2 = Mjai.action(fourReds, seat: Seat(0), legal: [.ankan(Kind(.man, 5))])
    print("[Finding 3b] ankan with 4 red fives -> \(String(describing: act2)) (expected nil)")

    let threeReds = try! Mjai.decode(#"{"type":"daiminkan","actor":0,"target":1,"pai":"5m","consumed":["5mr","5mr","5mr"]}"#)
    let act3 = Mjai.action(threeReds, seat: Seat(0), legal: [.daiminkan, .pass], offered: (t1("5m"), Seat(1)))
    print("[Finding 3c] daiminkan with 3 red fives -> \(String(describing: act3)) (expected nil)")
}

// --- Finding 5: Mjai.reply omits target on pon/chi/daiminkan and pai on daiminkan ---
do {
    let ponReply = Mjai.reply(.pon(t1("5m"), t1("5m")), seat: Seat(0), target: Seat(1), tile: t1("5m"))
    let dmkReply = Mjai.reply(.daiminkan, seat: Seat(0), target: Seat(1), tile: t1("5m"), consumed: t("055m"))
    print("[Finding 5a] pon reply: \(ponReply)")
    print("[Finding 5b] daiminkan reply: \(dmkReply)")
}
