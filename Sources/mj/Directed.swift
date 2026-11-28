// Directed self-play: games that reach rare branches on
// purpose and in bulk. A `Scenario` arranges some hands' walls for one branch
// (perturbed at random from the game seed and hand number, so every game is
// different) and gives each seat a scripted goal for those hands; the other hands
// are ordinary seeded walls played by eager bots. `endgame` instead starts every
// game at a random all-last position (or, in some games, earlier with a seat on
// 1,000 or 2,000 points). Everything is a pure function of (scenario,
// seed, hand), so a trace that names the scenario replays exactly.
//
//   mj selfplay --scenario NAME [--seed N --games K --rules R ...]

import Riichi

/// What a directed seat tries to do in an arranged hand.
struct Goal: Sendable {
    enum Win: Sendable { case always, never, eager }
    enum Calls: Sendable { case never, eager, all, eagerNoKan }
    enum Discards: Sendable { case shanten, yaochu }
    /// Discard these kinds first, in order, while it holds them.
    var first: [Kind] = []
    var win = Win.eager
    var riichi = true
    var calls = Calls.eager
    /// Declare every kan offered.
    var kans = false
    var discards = Discards.shanten
    /// Never discard these kinds while another discard is legal.
    var keep: Set<Kind> = []
    var kyuushuPercent = 50

    static let eager = Goal()
}

/// One hand's arrangement: a goal per dealer offset (0 is the dealer), or none for
/// an ordinary seeded hand.
struct HandPlan: Sendable {
    var goals: [Goal]?
}

enum Scenario: String, CaseIterable, Sendable {
    case fourwinds, fourriichi, tripleron, robkan, pao, nagashi, fourkans, endgame

    /// The plan RNG for a hand (`hand` −1: the starting position).
    static func rng(_ seed: UInt64, _ hand: Int, _ salt: UInt64) -> BotRNG {
        BotRNG(state: mix64(seed ^ mix64(UInt64(bitPattern: Int64(hand)) &+ salt)))
    }

    /// Share of hands arranged (abort branches leave room for the game to move on).
    var share: Int {
        switch self {
        case .fourwinds, .fourriichi, .tripleron: 50
        case .endgame: 0
        default: 70
        }
    }

    /// The game's first position (nil: a new game).
    func position(seed: UInt64) -> GamePosition? { start(seed: seed)?.0 }

    /// `endgame`: the first position, and the seat placed on 1,000 or 2,000 points
    /// in a game started before all last (a riichi, a 1,000-point ron or a noten
    /// payment can leave it on exactly zero).
    func start(seed: UInt64) -> (GamePosition, zero: Int?)? {
        guard self == .endgame else { return nil }
        var r = Scenario.rng(seed, -1, 0xE0D)
        let variant = r.below(12)
        let west = r.chance(35)
        var wind: Wind = west ? .west : .south
        var kyoku = west ? (r.chance(50) ? 4 : 1 + r.below(3)) : 4
        if variant >= 7 {
            // A seat on 1,000 or 2,000 before all last: a riichi or a noten payment
            // can leave it on exactly zero, and the game goes on.
            wind = r.chance(50) ? .east : .south
            kyoku = 1 + r.below(wind == .south ? 3 : 4)
        }
        let honba = r.below(4), sticks = r.below(3)
        let total = 100_000 - 1000 * sticks
        var zero: Int? = nil
        let dealer = kyoku - 1
        var scores = [0, 0, 0, 0]
        func fill(_ fixed: [Int: Int]) {
            // The seats not fixed share the rest at random, in hundreds.
            var rest = total - fixed.values.reduce(0, +)
            let free = (0..<4).filter { fixed[$0] == nil }
            for (i, s) in free.enumerated() {
                if i == free.count - 1 { scores[s] = rest; break }
                let share = rest / (free.count - i)
                let v = max(0, share + 100 * (r.below(121) - 60))
                scores[s] = v
                rest -= v
            }
            for (s, v) in fixed { scores[s] = v }
        }
        switch variant {
        case 0: fill([dealer: 30_000 + 100 * r.below(150)])                   // dealer leads past the target
        case 1: fill([dealer: 20_000 + 100 * r.below(95), (dealer + 1 + r.below(3)) % 4: 30_000 + 100 * r.below(80)])
        case 2, 6:                                                              // nobody near the target
            let each = total / 4
            for s in 0..<4 { scores[s] = each }
            for _ in 0..<6 {
                let a = r.below(4), b = r.below(4), d = 100 * r.below(r.chance(50) ? 15 : 40)
                if scores[b] - d >= 0 && scores[a] + d < 30_000 { scores[a] += d; scores[b] -= d }
            }
        case 3: fill([(dealer + r.below(4)) % 4: [0, 1000, 1500, 2000, 3900][r.below(5)]])  // near zero
        case 4: fill([dealer: 29_000 + 100 * r.below(20)])                    // dealer just below
        case 7...11:                                                            // zero continues
            zero = r.below(4)
            fill([zero!: r.chance(70) ? 1000 : 2000])
        default:                                                                // a tie for first
            let v = 30_000 + 100 * r.below(30)
            let a = r.below(4), b = (a + 1 + r.below(3)) % 4
            fill([a: v, b: v])
        }
        // In range by construction.
        return (try! GamePosition(roundWind: wind, kyoku: kyoku, honba: honba, sticks: sticks, scores: scores), zero)
    }

    /// Whether the hand is arranged.
    func arranged(seed: UInt64, hand: Int) -> Bool {
        if self == .endgame { return false }
        var r = Scenario.rng(seed, hand, 0x91A)
        return r.chance(share)
    }

    func plan(seed: UInt64, hand: Int) -> HandPlan {
        guard arranged(seed: seed, hand: hand) else { return HandPlan(goals: nil) }
        var b = WallBuilder(seed: seed, hand: hand)
        return build(&b, seed: seed).0
    }

    func wall(seed: UInt64, hand: Int) -> Wall {
        guard arranged(seed: seed, hand: hand) else { return Wall(seed: seed, hand: hand) }
        var b = WallBuilder(seed: seed, hand: hand)
        return build(&b, seed: seed).1
    }

    /// The arrangement of one hand: goals by dealer offset and the wall.
    func build(_ b: inout WallBuilder, seed: UInt64) -> (HandPlan, Wall) {
        var goals = Array(repeating: Goal.eager, count: 4)
        switch self {
        case .fourwinds:
            let w = Kind(.honor, 1 + b.rng.below(4))
            var g = Goal(); g.first = [w]; g.kyuushuPercent = 0
            goals = Array(repeating: g, count: 4)
            let riichi = b.rng.chance(30)
            for o in 0..<4 {
                if riichi && o == 3 {
                    // Riichi on the fourth wind: 12 of a tenpai hand and the wind; the
                    // first draw is the hand's 13th tile.
                    var t = b.tenpai(avoid: [w])
                    let last = t.remove(at: b.rng.below(t.count))
                    b.deal(o, t + [b.take(w)!])
                    b.live(3, last)
                } else {
                    b.deal(o, [b.take(w)!] + b.random(12, avoid: [w]))
                }
            }
        case .fourriichi:
            var g = Goal(); g.win = .never; g.calls = .never; g.kyuushuPercent = 0
            goals = Array(repeating: g, count: 4)
            let late = b.rng.chance(30) ? b.rng.below(4) : -1
            for o in 0..<4 {
                if o == late { b.deal(o, b.random(13)) } else { b.deal(o, b.tenpai()) }
            }
        case .tripleron:
            let k = Kind(Suit(rawValue: b.rng.below(3))!, 4 + b.rng.below(3))
            var feeder = Goal(); feeder.first = [k]; feeder.win = .never; feeder.riichi = false; feeder.kyuushuPercent = 0
            var winner = Goal(); winner.win = .always; winner.kyuushuPercent = 0
            goals = [feeder, winner, winner, winner]
            var shapes = [[-2, -1], [1, 2], [-1, 1]]
            for i in stride(from: 2, to: 0, by: -1) { shapes.swapAt(i, b.rng.below(i + 1)) }
            // The wait shapes first (two seats share a neighbour of k), then the rest.
            let waits = shapes.map { $0.map { b.take(k.shifted($0)!)! } }
            for o in 1...3 {
                b.deal(o, waits[o - 1] + b.complete(sets: 3, pair: true, simples: true, avoid: [k]))
            }
            b.deal(0, [b.take(k)!] + b.random(12))
        case .robkan:
            let x = Kind.yaochu[b.rng.below(13)]
            let kanSeat = b.rng.below(4), kokushi = (kanSeat + 1 + b.rng.below(3)) % 4
            var kanner = Goal(); kanner.kans = true; kanner.kyuushuPercent = 0
            var robber = Goal(); robber.win = .always; robber.kyuushuPercent = 0; robber.calls = .never
            goals[kanSeat] = kanner
            goals[kokushi] = robber
            let rest = Kind.yaochu.filter { $0 != x }
            let pair = rest[b.rng.below(rest.count)]
            b.deal(kokushi, (rest + [pair]).map { b.take($0)! })
            b.deal(kanSeat, (0..<4).map { _ in b.take(x)! } + b.random(9, avoid: Set(Kind.yaochu)))
        case .pao:
            let w = b.rng.below(4)
            var collector = Goal(); collector.calls = .all; collector.win = .always; collector.kyuushuPercent = 0
            collector.keep = [Kind.haku, Kind.hatsu, Kind.chun]
            goals[w] = collector
            let dragons = [Kind.haku, Kind.hatsu, Kind.chun]
            b.deal(w, dragons.flatMap { d in [b.take(d)!, b.take(d)!] } + b.random(7, avoid: Set(dragons)))
            var others = (1...3).map { (w + $0) % 4 }
            for i in stride(from: 2, to: 0, by: -1) { others.swapAt(i, b.rng.below(i + 1)) }
            for (i, o) in others.enumerated() {
                let mine = [dragons[i], dragons[(i + 1) % 3]]
                var g = Goal(); g.first = mine; g.win = .never; g.calls = .never; g.riichi = false
                g.kyuushuPercent = 0
                goals[o] = g
                b.deal(o, mine.map { b.take($0)! } + b.random(11, avoid: Set(dragons)))
            }
        case .nagashi:
            let n = b.rng.below(4)
            let second = b.rng.chance(15) ? (n + 1 + b.rng.below(3)) % 4 : -1
            var passive = Goal(); passive.win = .never; passive.calls = .never; passive.kyuushuPercent = 0
            passive.riichi = b.rng.chance(50)
            var ns = Goal(); ns.win = .never; ns.calls = .never; ns.riichi = false; ns.kyuushuPercent = 0
            ns.discards = .yaochu
            goals = Array(repeating: passive, count: 4)
            for o in [n, second] where o >= 0 {
                goals[o] = ns
                b.deal(o, b.yaochu(13))
                for d in 0..<17 where b.rng.chance(45) {
                    if let t = b.yaochu(1).first { b.live(4 * d + o, t) }
                }
            }
        case .fourkans:
            let k = b.rng.below(4)
            var kinds = Kind.all
            for i in stride(from: kinds.count - 1, to: 0, by: -1) { kinds.swapAt(i, b.rng.below(i + 1)) }
            let (a, bb, c, d) = (kinds[0], kinds[1], kinds[2], kinds[3])
            var kanner = Goal(); kanner.kans = true; kanner.win = .always; kanner.kyuushuPercent = 0
            kanner.keep = [a, bb, c, d]
            var other = Goal(); other.calls = .eagerNoKan
            goals = Array(repeating: other, count: 4)
            goals[k] = kanner
            let open = b.rng.chance(40)
            var mine = [bb, bb, bb, bb, c, c, c, c, d].map { b.take($0)! }
            mine += (0..<(open ? 3 : 4)).map { _ in b.take(a)! }
            if open {
                // The fourth `a` comes from another seat, discarded first: an open kan.
                let f = (k + 1 + b.rng.below(3)) % 4
                var feeder = other; feeder.first = [a]
                goals[f] = feeder
                b.deal(f, [b.take(a)!] + b.random(12, avoid: [a, bb, c, d]))
                mine += b.random(1, avoid: [a, bb, c, d])
            }
            b.deal(k, mine)
            for i in 0..<3 { b.replacement(i, b.take(d)!) }
        case .endgame:
            break
        }
        return (HandPlan(goals: goals), b.finish())
    }
}

/// Builds an arranged wall: chosen tiles in chosen slots, the rest shuffled in.
struct WallBuilder {
    var rng: BotRNG
    var pool: [Tile] = Wall.sorted
    var slots = [Tile?](repeating: nil, count: Wall.count)

    init(seed: UInt64, hand: Int) {
        rng = Scenario.rng(seed, hand, 0x3A11)
        for i in stride(from: pool.count - 1, to: 0, by: -1) { pool.swapAt(i, rng.below(i + 1)) }
    }

    func left(_ k: Kind) -> Int { pool.count { $0.kind == k } }

    /// A copy of `k` from the pool (a random one: the pool is shuffled).
    mutating func take(_ k: Kind) -> Tile? {
        guard let i = pool.firstIndex(where: { $0.kind == k }) else { return nil }
        return pool.remove(at: i)
    }

    /// `n` random tiles from the pool, none of a kind in `avoid`.
    mutating func random(_ n: Int, avoid: Set<Kind> = []) -> [Tile] {
        var out: [Tile] = []
        var i = 0
        while out.count < n && i < pool.count {
            if avoid.contains(pool[i].kind) { i += 1 } else { out.append(pool.remove(at: i)) }
        }
        return out
    }

    /// `n` random terminal or honor tiles.
    mutating func yaochu(_ n: Int) -> [Tile] {
        random(n, avoid: Set(Kind.all.filter { !$0.isYaochu }))
    }

    /// Tiles for `sets` random sets (sequences or triplets) and, if `pair`, a pair;
    /// simples only if asked, never a kind in `avoid`.
    mutating func complete(sets: Int, pair: Bool, simples: Bool = false, avoid: Set<Kind> = []) -> [Tile] {
        while true {
            var kinds: [Kind] = []
            var counts = [Int](repeating: 0, count: 34)
            func ok(_ ks: [Kind]) -> Bool {
                var c = counts
                for k in ks {
                    if avoid.contains(k) || (simples && !k.isSimple) { return false }
                    c[k.index] += 1
                    if c[k.index] > left(k) { return false }
                }
                return true
            }
            var tries = 0
            while kinds.count < 3 * sets && tries < 200 {
                tries += 1
                let ks: [Kind]
                if rng.chance(70) {
                    let s = Suit(rawValue: rng.below(3))!
                    let lo = simples ? 2 + rng.below(5) : 1 + rng.below(7)
                    ks = [Kind(s, lo), Kind(s, lo + 1), Kind(s, lo + 2)]
                } else {
                    let k = Kind(rng.below(34))
                    ks = [k, k, k]
                }
                if ok(ks) { kinds += ks; for k in ks { counts[k.index] += 1 } }
            }
            while pair && kinds.count == 3 * sets && tries < 400 {
                tries += 1
                let k = Kind(rng.below(34))
                if ok([k, k]) { kinds += [k, k]; break }
            }
            guard kinds.count == 3 * sets + (pair ? 2 : 0) else { continue }
            return kinds.map { take($0)! }
        }
    }

    /// A random closed tenpai hand of 13 tiles: four sets and a pair less one tile
    /// (kept back in the pool, so the wait is live).
    mutating func tenpai(avoid: Set<Kind> = []) -> [Tile] {
        var t = complete(sets: 4, pair: true, avoid: avoid)
        let out = t.remove(at: rng.below(t.count))
        pool.insert(out, at: rng.below(pool.count + 1))
        return t
    }

    /// The tiles dealt to the seat `offset` places after the dealer (13, or fewer:
    /// the rest are filled at random).
    mutating func deal(_ offset: Int, _ tiles: [Tile]) {
        precondition(tiles.count <= 13)
        var idx: [Int] = []
        for r in 0..<3 { for x in 0..<4 { idx.append(16 * r + 4 * offset + x) } }
        idx.append(48 + offset)
        for (i, t) in tiles.enumerated() { slots[idx[i]] = t }
    }

    /// The `i`th live draw (in turn order with no calls: draw `4n + offset` is the
    /// seat's `n`th).
    mutating func live(_ i: Int, _ t: Tile) {
        if slots[52 + i] == nil { slots[52 + i] = t } else { pool.append(t) }
    }

    mutating func replacement(_ i: Int, _ t: Tile) { slots[122 + i] = t }

    mutating func finish() -> Wall {
        var rest = pool.makeIterator()
        return Wall(tiles: slots.map { $0 ?? rest.next()! })!
    }
}

/// A seat in a directed game: follows its goal in arranged hands, plays eager in
/// the others. It sees only its masked events and its view.
struct DirectedBot: Player {
    let scenario: Scenario
    let seed: UInt64
    let seat: Seat
    var eager: BuiltinBot
    var hand = -1
    var goal: Goal? = nil

    init(scenario: Scenario, seed: UInt64, seat: Seat, rng: BotRNG) {
        self.scenario = scenario
        self.seed = seed
        self.seat = seat
        eager = BuiltinBot(kind: .eager, rng: rng)
    }

    mutating func receive(_ e: MaskedEvent, prompt: PlayerView?) {
        if case .startKyoku(_, _, _, _, let oya, _, _, _) = e {
            hand += 1
            goal = scenario.plan(seed: seed, hand: hand).goals?[seat.distance(from: oya)]
        }
    }

    mutating func decision(_ view: PlayerView) -> Action? {
        guard let goal else { return eager.eager(view) }
        return decide(view, goal)
    }

    mutating func decide(_ v: PlayerView, _ g: Goal) -> Action {
        let legal = v.legalActions
        func has(_ a: Action) -> Bool { legal.contains(a) }
        switch g.win {
        case .always:
            if has(.tsumo) { return .tsumo }
            if has(.ron) { return .ron }
        case .eager:
            if has(.tsumo) { return .tsumo }
            if has(.ron) && !eager.rng.chance(10) { return .ron }
        case .never: break
        }
        if g.kans, let k = legal.first(where: {
            switch $0 { case .ankan, .kakan, .daiminkan: true; default: false }
        }) { return k }
        if g.riichi && has(.riichi) { return .riichi }
        if has(.kyuushu) && eager.rng.chance(g.kyuushuPercent) { return .kyuushu }
        let calls = legal.filter { a in
            switch a {
            case .pon, .chi: g.calls != .never
            case .daiminkan, .ankan, .kakan: g.calls == .eager || g.calls == .all
            default: false
            }
        }
        if !calls.isEmpty && (g.calls == .all || eager.rng.chance(60)) { return calls[eager.rng.below(calls.count)] }
        let discards = legal.compactMap { a -> (Action, Tile)? in
            if case .discard(let t, _) = a { (a, t) } else { nil }
        }
        if discards.isEmpty { return has(.pass) ? .pass : legal[0] }
        for k in g.first { if let d = discards.first(where: { $0.1.kind == k }) { return d.0 } }
        var pick = discards.filter { !g.keep.contains($0.1.kind) }
        if pick.isEmpty { pick = discards }
        if g.discards == .yaochu {
            let y = pick.filter { $0.1.kind.isYaochu }
            if !y.isEmpty {
                // The drawn tile if it is one (so the hand keeps its shape), else any.
                return (y.first { if case .discard(_, true) = $0.0 { true } else { false } } ?? y[eager.rng.below(y.count)]).0
            }
        }
        let scored = pick.map { ($0.0, BuiltinBot.shantenAfter(v, removing: $0.1)) }
        let best = scored.map(\.1).min()!
        let top = scored.filter { $0.1 == best }.map(\.0)
        return top[eager.rng.below(top.count)]
    }
}
