// Invariants of design §8 layer 4 that apply to one round, over thousands of rounds
// of random and eager play driven directly through the step API.

import Testing
@testable import Riichi

/// A small deterministic generator for test decisions (SplitMix64).
struct TestRNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
}

enum Bot {
    case random, eager

    /// Shanten of `seat`'s concealed tiles (with the drawn tile) after removing `t`.
    static func shantenAfter(_ s: RoundState, _ seat: Seat, removing t: Tile?) -> Int {
        var tiles = s.hand(of: seat)
        if let d = s.drawnTile(of: seat) { tiles.append(d) }
        if let t, let i = tiles.firstIndex(of: t) { tiles.remove(at: i) }
        return shanten(Counts(tiles), meldCount: s.melds(of: seat).count).min
    }

    func choose(_ s: RoundState, _ seat: Seat, _ rng: inout TestRNG) -> Action {
        let legal = s.legalActions(for: seat)
        switch self {
        case .random:
            return legal[rng.below(legal.count)]
        case .eager:
            if legal.contains(.tsumo) { return .tsumo }
            if legal.contains(.ron) && !rng.chance(10) { return .ron }
            if legal.contains(.riichi) { return .riichi }
            if legal.contains(.kyuushu) && rng.chance(50) { return .kyuushu }
            let calls = legal.filter {
                switch $0 {
                case .pon, .chi, .daiminkan, .ankan, .kakan: true
                default: false
                }
            }
            if !calls.isEmpty && rng.chance(60) { return calls[rng.below(calls.count)] }
            let discards = legal.filter { if case .discard = $0 { true } else { false } }
            if discards.isEmpty { return legal.contains(.pass) ? .pass : legal[rng.below(legal.count)] }
            // Greedy: a discard that leaves the lowest shanten, ties at random.
            let scored = discards.map { a -> (Action, Int) in
                guard case .discard(let t, _) = a else { return (a, 99) }
                return (a, Bot.shantenAfter(s, seat, removing: t))
            }
            let best = scored.map(\.1).min()!
            let top = scored.filter { $0.1 == best }.map(\.0)
            return top[rng.below(top.count)]
        }
    }

    func choose(_ legal: [Action], _ rng: inout TestRNG) -> Action {
        switch self {
        case .random:
            return legal[rng.below(legal.count)]
        case .eager:
            // Always win, except sometimes pass a ron; riichi when legal; call and kan
            // with high probability; otherwise a random discard.
            if legal.contains(.tsumo) { return .tsumo }
            if legal.contains(.ron) && !rng.chance(10) { return .ron }
            if legal.contains(.riichi) { return .riichi }
            let calls = legal.filter {
                switch $0 {
                case .pon, .chi, .daiminkan, .ankan, .kakan: true
                default: false
                }
            }
            if !calls.isEmpty && rng.chance(75) { return calls[rng.below(calls.count)] }
            if legal.contains(.kyuushu) && rng.chance(50) { return .kyuushu }
            let rest = legal.filter {
                switch $0 {
                case .discard, .pass: true
                default: false
                }
            }
            return (rest.isEmpty ? legal : rest)[rng.below(rest.isEmpty ? legal.count : rest.count)]
        }
    }
}

/// Counts of rare branches reached, for the coverage report.
struct Coverage: CustomStringConvertible {
    var counts: [String: Int] = [:]
    mutating func hit(_ k: String) { counts[k, default: 0] += 1 }
    var description: String {
        counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }
}

/// Plays one round to the end, checking invariants after every step.
/// `record` collects every decision (seat, action) for replay.
@discardableResult
func playRound(rules: Rules, seed: UInt64, hand: Int, bot: Bot, rng: inout TestRNG,
               coverage: inout Coverage, check: Bool = true,
               decisions: inout [(Seat, Action)]) throws -> (RoundState, [Event]) {
    let wall = Wall(seed: seed, hand: hand)
    var scores = [25_000, 25_000, 25_000, 25_000]
    // Vary scores a little so that riichi with < 1000 points and similar arise.
    if rng.chance(20) {
        let s = rng.below(4)
        scores[s] = 500 + 100 * rng.below(10)
        scores[(s + 1) % 4] += 25_000 - scores[s]
    }
    let sticks = rng.chance(30) ? rng.below(3) : 0
    let honba = rng.chance(30) ? rng.below(3) : 0
    let dealer = Seat(rng.below(4))
    var events: [Event] = []
    var state = RoundState(rules: rules, wall: wall, roundWind: rng.chance(50) ? .east : .south,
                           kyoku: dealer.index + 1, honba: honba, sticks: sticks, dealer: dealer,
                           scores: scores, events: &events)
    let total = scores.reduce(0, +) + 1000 * sticks
    var steps = 0
    while state.result == nil {
        steps += 1
        #expect(steps < 1000, "round does not end")
        if steps >= 1000 { break }
        if check { try checkInvariants(state, total: total) }
        switch state.phase {
        case .turn(let seat, _):
            let legal = state.legalActions(for: seat)
            #expect(!legal.isEmpty, "seat to act has no legal action")
            if check { try checkEveryLegalApplies(state, seat, legal) }
            for other in Seat.all where other != seat { #expect(state.legalActions(for: other).isEmpty) }
            let a = bot.choose(state, seat, &rng)
            decisions.append((seat, a))
            if case .ankan = a { coverage.hit("ankan") }
            if case .kakan = a { coverage.hit("kakan") }
            if a == .riichi { coverage.hit("riichi") }
            if case .ankan = a, state.riichiStatus(of: seat) == .accepted { coverage.hit("riichi_ankan") }
            try state.apply(a, by: seat, events: &events)
        case .reactions, .robbing:
            let asked = state.seatsToAnswer
            #expect(!asked.isEmpty, "a window with nobody to answer")
            var answers = Answers()
            for s in asked {
                let a = bot.choose(state, s, &rng)
                answers[s] = a
                decisions.append((s, a))
            }
            let kind: Kind? = switch state.phase {
                case .reactions(let d): d.tile.kind
                case .robbing(let k): k.kind == .added ? k.tile.kind : nil
                default: nil
            }
            let discarder: Seat? = switch state.phase {
                case .reactions(let d): d.seat
                case .robbing(let k): k.seat
                default: nil
            }
            if check {
                // Answer order does not matter: Answers is keyed by seat, so the same
                // answers built in reverse order give the same state.
                var reversed = Answers()
                for s in asked.reversed() { reversed[s] = answers[s] }
                #expect(reversed == answers)
                // Something outside legalActions is refused and changes nothing.
                var bad = answers
                bad[asked[0]] = .discard(Tile(Kind(0)), tsumogiri: true)
                var copy = state
                #expect(throws: RoundError.self) { try copy.resolve(bad) }
            }
            // Which seats wait on the tile, before the window closes.
            let waiting = Seat.all.filter { s in
                guard let kind, s != discarder else { return false }
                return state.waits(of: s).contains(kind)
            }
            try state.resolve(answers, events: &events)
            if check, let kind, state.result == nil {
                // Every seat that was waiting on the tile is now furiten (unless it just
                // called it and its hand changed).
                for s in waiting where !state.waits(of: s).isEmpty && state.waits(of: s).contains(kind) {
                    let calledIt: Bool = if case .turn(let t, _) = state.phase { t == s } else { false }
                    if !calledIt { #expect(state.isFuriten(s), "seat \(s) waits on \(kind) but is not furiten") }
                }
            }
        case .ended:
            break
        }
    }
    if check { try checkInvariants(state, total: total) }
    let r = try #require(state.result)
    #expect(r.deltas.reduce(0, +) + 1000 * (r.sticks - sticks) == 0)
    #expect(zip(scores, r.deltas).map(+) == r.scores)
    switch r.outcome {
    case .wins(let w):
        coverage.hit(w.count == 1 ? (w[0].isTsumo ? "tsumo" : "ron") : "ron_x\(w.count)")
        for win in w {
            if win.liable != nil { coverage.hit("pao_\(win.isTsumo ? "tsumo" : win.from == win.liable ? "liable_ron" : "third_party_ron")") }
            for y in win.scored.yaku {
                if case .yaku(let n) = y.name, [.rinshan, .chankan, .haitei, .houtei, .ippatsu, .double_riichi,
                                                 .tenhou, .chiihou, .suukantsu].contains(n) {
                    coverage.hit(n.rawValue)
                }
            }
            if case .yakuman = win.scored.value { coverage.hit("yakuman") }
        }
    case .exhaustiveDraw(let tenpai, let n):
        coverage.hit(n.isEmpty ? "exhaustive" : "nagashi")
        // The ryukyoku payment: 3,000 split by tenpai count, unless nagashi.
        // The cached-waits tenpai test agrees with the hand-analysis one.
        for s in Seat.all {
            let counts = Counts(state.hand(of: s))
            let melds = state.melds(of: s).map(\.meld)
            #expect(tenpai.contains(s) == isTenpaiAtDraw(counts, melds: melds, rules: rules))
        }
        if n.isEmpty, case .ryukyoku(_, let d, let flags, _, _) = events[events.count - 2] {
            #expect(flags == Seat.all.map(tenpai.contains))
            let k = tenpai.count
            let want = Seat.all.map { s in
                k == 0 || k == 4 ? 0 : tenpai.contains(s) ? 3000 / k : -3000 / (4 - k)
            }
            #expect(d == want)
        }
    case .abortiveDraw(let a):
        coverage.hit("abort_\(a.rawValue)")
    }
    if Seat.all.contains(where: { state.melds(of: $0).count(where: { $0.kind != .chi && $0.kind != .pon }) == 4 }) {
        coverage.hit("four_kans_one_seat")
    }
    // Events: one start, one end, and the end last.
    #expect(events.first.map { if case .startKyoku = $0 { true } else { false } } == true)
    #expect(events.last == .endKyoku)
    return (state, events)
}

/// Tiles conserved by kind and red flag; points conserved.
func checkInvariants(_ s: RoundState, total: Int) throws {
    #expect(s.scores.reduce(0, +) + 1000 * s.sticks == total)
    var inPlay: [Tile] = []
    for seat in Seat.all {
        inPlay += s.hand(of: seat)
        if let d = s.drawnTile(of: seat) { inPlay.append(d) }
        inPlay += s.melds(of: seat).flatMap(\.tiles)
        inPlay += s.pond(of: seat).filter { !$0.calledAway }.map(\.tile)
    }
    if case .robbing(let k) = s.phase, k.kind == .added { inPlay.append(k.tile) }
    // A robbed added kan's tile is the winning tile, held by no one.
    if let r = s.result, let w = r.wins.first, w.robbedKan == .added { inPlay.append(w.tile) }
    var used = Array(s.wall.tiles[0..<52])
    used += (0..<s.liveDrawn).map(s.wall.liveDraw)
    used += (0..<s.replacementsDrawn).map(s.wall.replacement)
    #expect(inPlay.sorted() == used.sorted(), "tiles not conserved")
    #expect(s.liveTilesLeft >= 0)
    #expect(s.liveDrawn + s.kanCount <= 70)
}

/// Every action in legalActions applies without error on a copy, and a few that are
/// not in it are refused without changing the state.
func checkEveryLegalApplies(_ s: RoundState, _ seat: Seat, _ legal: [Action]) throws {
    for a in legal {
        var copy = s
        try copy.apply(a, by: seat)
    }
    var probes: [Action] = [.ron, .pass, .daiminkan, .pon(Tile(Kind(0)), Tile(Kind(0)))]
    for k in Kind.all where !legal.contains(.ankan(k)) { probes.append(.ankan(k)); break }
    for t in Wall.sorted.distinct where !legal.contains(.discard(t, tsumogiri: false)) {
        probes.append(.discard(t, tsumogiri: false))
    }
    for p in [Action.tsumo, .riichi, .kyuushu] where !legal.contains(p) { probes.append(p) }
    for p in probes where !legal.contains(p) {
        var copy = s
        #expect(throws: RoundError.self, "\(p) is not legal but applied") { try copy.apply(p, by: seat) }
        #expect(copy.legalActions(for: seat) == legal)
    }
    // Another seat cannot act.
    var copy = s
    #expect(throws: RoundError.self) { try copy.apply(legal[0], by: seat.next) }
}

@Suite struct SelfPlayTests {
    @Test(arguments: [(Bot.random, "mahjongsoul"), (.random, "tenhou"), (.eager, "mahjongsoul"), (.eager, "tenhou")])
    func invariants(_ bot: Bot, _ ruleset: String) throws {
        let rules: Rules = ruleset == "tenhou" ? .tenhou : .mahjongSoul
        var rng = TestRNG(state: ruleset == "tenhou" ? 7 : 11)
        var coverage = Coverage()
        let rounds = bot == .eager ? 2000 : 1000
        for i in 0..<rounds {
            var d: [(Seat, Action)] = []
            // Full checks on an eighth of the rounds (they apply every legal action).
            try playRound(rules: rules, seed: UInt64(i) &* 7919 &+ 3, hand: i % 9, bot: bot, rng: &rng,
                          coverage: &coverage, check: i % 8 == 0, decisions: &d)
        }
        print("coverage \(bot) \(ruleset) over \(rounds) rounds: \(coverage)")
    }

    /// A round replays exactly from its wall and decisions.
    @Test func replayIsExact() throws {
        var coverage = Coverage()
        for i in 0..<200 {
            var rng = TestRNG(state: UInt64(i))
            var d: [(Seat, Action)] = []
            let (a, ea) = try playRound(rules: .mahjongSoul, seed: UInt64(i), hand: 0, bot: .eager,
                                        rng: &rng, coverage: &coverage, check: false, decisions: &d)
            var rng2 = TestRNG(state: UInt64(i))
            var d2: [(Seat, Action)] = []
            let (b, eb) = try playRound(rules: .mahjongSoul, seed: UInt64(i), hand: 0, bot: .eager,
                                        rng: &rng2, coverage: &coverage, check: false, decisions: &d2)
            #expect(ea == eb)
            #expect(a.result == b.result)
        }
    }

    /// Rotating the three suits throughout the wall, reds included, gives the same
    /// game with suits rotated.
    @Test func suitRotation() throws {
        func rot(_ t: Tile) -> Tile {
            guard !t.kind.isHonor else { return t }
            let suit = Suit(rawValue: (t.kind.suit.rawValue + 1) % 3)!
            return Tile(Kind(suit, t.kind.number), red: t.isRed)
        }
        func rot(_ a: Action) -> Action {
            switch a {
            case .discard(let t, let g): .discard(rot(t), tsumogiri: g)
            case .ankan(let k): .ankan(rot(Tile(k)).kind)
            case .kakan(let t): .kakan(rot(t))
            case .pon(let x, let y): .pon(rot(x), rot(y))
            case .chi(let x, let y): .chi(rot(x), rot(y))
            default: a
            }
        }
        var coverage = Coverage()
        for i in 0..<200 {
            var rng = TestRNG(state: UInt64(1000 + i))
            var decisions: [(Seat, Action)] = []
            let (a, _) = try playRound(rules: .mahjongSoul, seed: UInt64(i), hand: 1, bot: .eager, rng: &rng,
                                       coverage: &coverage, check: false, decisions: &decisions)
            let ra = try #require(a.result)
            // Replay on the rotated wall with rotated decisions.
            let wall = Wall(tiles: a.wall.tiles.map(rot))!
            var b = RoundState(rules: .mahjongSoul, wall: wall, roundWind: a.roundWind, kyoku: a.kyoku,
                           honba: a.honba, sticks: a.initialSticks, dealer: a.dealer, scores: a.initialScores)
            var k = 0
            while b.result == nil {
                switch b.phase {
                case .turn(let s, _):
                    let (seat, act) = decisions[k]; k += 1
                    #expect(seat == s)
                    try b.apply(rot(act), by: s)
                default:
                    var answers = Answers()
                    for s in b.seatsToAnswer {
                        let (seat, act) = decisions[k]; k += 1
                        #expect(seat == s)
                        answers[s] = rot(act)
                    }
                    try b.resolve(answers)
                }
            }
            let rb = try #require(b.result)
            #expect(ra.deltas == rb.deltas && ra.sticks == rb.sticks && ra.dealerRepeats == rb.dealerRepeats)
            #expect(ra.wins.map(\.scored.yakuText) == rb.wins.map(\.scored.yakuText))
        }
    }
}
