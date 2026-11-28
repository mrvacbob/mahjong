// Game flow (Docs/Design/engine.md §5): a sequence of rounds, the after-round
// transition, and the final result.

/// Where the game stands at the start of a hand: what `start_kyoku` announces.
/// Always in range (the initializer checks it), so the game flow never traps on one.
public struct GamePosition: Hashable, Sendable {
    public internal(set) var roundWind: Wind
    /// 1–4.
    public internal(set) var kyoku: Int
    /// 0...`RoundState.maxRunningHonba`.
    public internal(set) var honba: Int
    /// Riichi sticks on the table: 0...`GamePosition.maxSticks`.
    public internal(set) var sticks: Int
    /// Four scores, each within ±`GamePosition.maxScore`.
    public internal(set) var scores: [Int]

    /// The bounds a running game keeps to: every point stays among the seats and
    /// the table, so neither the sticks nor any score can pass what four seats
    /// admitted at `RoundState.maxScore` with `RoundState.maxCount` sticks hold.
    public static let maxSticks = 4 * RoundState.maxScore / 1000 + RoundState.maxCount
    public static let maxScore = 4 * RoundState.maxScore + 1000 * RoundState.maxCount

    public init(roundWind: Wind = .east, kyoku: Int = 1, honba: Int = 0, sticks: Int = 0,
                scores: [Int]) throws(InputError) {
        guard (1...4).contains(kyoku) else { throw InputError("kyoku", "\(kyoku) is not 1...4") }
        guard (0...RoundState.maxRunningHonba).contains(honba) else {
            throw InputError("honba", "\(honba) is not 0...\(RoundState.maxRunningHonba)")
        }
        guard (0...GamePosition.maxSticks).contains(sticks) else {
            throw InputError("sticks", "\(sticks) is not 0...\(GamePosition.maxSticks)")
        }
        guard scores.count == 4 else { throw InputError("scores", "\(scores.count) scores, not one per seat") }
        guard scores.allSatisfy({ abs($0) <= GamePosition.maxScore }) else {
            throw InputError("scores", "a score is outside ±\(GamePosition.maxScore)")
        }
        self.roundWind = roundWind
        self.kyoku = kyoku
        self.honba = honba
        self.sticks = sticks
        self.scores = scores
    }

    /// Seat 0 deals East 1; the deal passes in turn order.
    public var dealer: Seat { Seat(kyoku - 1) }
}

/// Why the game ended after a hand.
public enum GameEnd: String, Hashable, Sendable {
    /// A score went below zero (step 1).
    case belowZero = "below_zero"
    /// All last: the dealer repeated by winning or by tenpai and is first with at
    /// least the target (agari-yame, tenpai-yame).
    case dealerFirst = "dealer_first"
    /// All last: the dealer did not repeat (or, with `dealerRepeatBeforeTarget`
    /// off, repeated without being first) and someone has the target.
    case target
    /// All last: the next hand would start a wind beyond the extension.
    case extensionOver = "extension_over"
    /// The next hand would have more than `RoundState.maxRunningHonba` honba (not a
    /// rule of either client: the bound that keeps payments in 32-bit `Int`).
    case counterLimit = "counter_limit"
}

/// What the after-round transition decided.
public enum GameTransition: Hashable, Sendable {
    /// Before all last: the dealer repeats or the deal passes.
    case ordinary
    /// All last: the dealer repeats and play continues (an abortive draw, the
    /// dealer below the target or not first, or a dealer repeat taking priority
    /// over another seat's target).
    case allLastRepeat
    /// All last: the deal passes into, or within, the extension, nobody having the
    /// target.
    case allLastAdvance
    case ends(GameEnd)
}

public struct GameResult: Hashable, Sendable {
    /// Seats first to fourth: by final score, ties to the earlier starting seat.
    public let ranks: [Seat]
    /// Final scores by seat, after leftover sticks go to first place.
    public let scores: [Int]
    /// Sticks left on the table at the end, awarded to first place.
    public let sticksAwarded: Int
    /// `score − returnPoints + uma[rank]`, plus `oka` for first, by seat (integer
    /// points: +27.0 is 27000).
    public let adjusted: [Int]
    public let end: GameEnd
}

public enum GameFlow {
    /// Seats in rank order for these four scores: higher first, ties to the lower
    /// seat.
    public static func ranking(_ scores: [Int]) throws(InputError) -> [Seat] {
        guard scores.count == 4 else { throw InputError("scores", "\(scores.count) scores, not one per seat") }
        return rank(scores)
    }

    static func rank(_ scores: [Int]) -> [Seat] {
        Seat.all.sorted { scores[$0.index] != scores[$1.index] ? scores[$0.index] > scores[$1.index] : $0 < $1 }
    }

    /// The last hand of the scheduled game, and the wind of the extension.
    static func lastWind(_ rules: Rules) -> Wind { rules.length == .east ? .east : .south }

    /// Whether this hand is all last: the scheduled last hand or any hand after it.
    public static func isAllLast(_ p: GamePosition, rules: Rules) -> Bool {
        let last = lastWind(rules)
        return p.roundWind.rawValue > last.rawValue || (p.roundWind == last && p.kyoku == 4)
    }

    /// The transition of design §5 after the hand at `position` ended with `result`.
    /// `testScores` are the scores the 30,000 tests read (the result's scores, or
    /// the scores before nagashi payments when `allLastTestAfterNagashi` is off).
    /// Returns the next hand's position, or nil when the game ends.
    public static func next(after result: RoundResult, at position: GamePosition, rules: Rules,
                            testScores: [Int]? = nil) throws(InputError) -> (GamePosition?, GameTransition) {
        if let testScores, testScores.count != 4 {
            throw InputError("testScores", "\(testScores.count) scores, not one per seat")
        }
        return transition(after: result, at: position, rules: rules, testScores: testScores)
    }

    static func transition(after result: RoundResult, at position: GamePosition, rules: Rules,
                           testScores: [Int]?) -> (GamePosition?, GameTransition) {
        let scores = result.scores
        let test = testScores ?? scores
        // 1. Below zero ends the game; zero continues.
        if scores.contains(where: { $0 < 0 }) { return (nil, .ends(.belowZero)) }
        // 2. Honba. 3. Dealer repeat.
        let honba = result.nextHonba(after: position.honba)
        if honba > RoundState.maxRunningHonba { return (nil, .ends(.counterLimit)) }
        let repeats = result.dealerRepeats
        var next = position
        next.honba = honba
        next.sticks = result.sticks
        next.scores = scores
        if !repeats {
            // North 4 is the last hand there is: never wrap to East (Codex C/D finding 4).
            if next.kyoku == 4 && next.roundWind == .north { return (nil, .ends(.extensionOver)) }
            if next.kyoku == 4 {
                next.kyoku = 1
                next.roundWind = next.roundWind.next
            } else {
                next.kyoku += 1
            }
        }
        // 4. All last.
        guard isAllLast(position, rules: rules) else { return (next, .ordinary) }
        let target = test.contains { $0 >= rules.targetPoints }
        if repeats {
            let abort: Bool = if case .abortiveDraw = result.outcome { true } else { false }
            let dealer = position.dealer
            if !abort && rank(test)[0] == dealer && test[dealer.index] >= rules.targetPoints {
                return (nil, .ends(.dealerFirst))
            }
            // An abortive draw in all last always continues (design §5).
            if !abort && target && !rules.dealerRepeatBeforeTarget { return (nil, .ends(.target)) }
            return (next, .allLastRepeat)
        }
        if target { return (nil, .ends(.target)) }
        // The extension is the wind after the scheduled last one; beyond it, the end.
        let extensionWind = lastWind(rules).next
        if next.roundWind.rawValue > extensionWind.rawValue {
            return (nil, .ends(.extensionOver))
        }
        return (next, .allLastAdvance)
    }

    /// Step 5: leftover sticks to first place, ranks, return points, oka and uma.
    public static func result(scores: [Int], sticks: Int, rules: Rules, end: GameEnd) throws(InputError) -> GameResult {
        try rules.validate()
        guard scores.count == 4 else { throw InputError("scores", "\(scores.count) scores, not one per seat") }
        guard scores.allSatisfy({ abs($0) <= GamePosition.maxScore }) else {
            throw InputError("scores", "a score is outside ±\(GamePosition.maxScore)")
        }
        guard (0...GamePosition.maxSticks).contains(sticks) else {
            throw InputError("sticks", "\(sticks) is not 0...\(GamePosition.maxSticks)")
        }
        return final(scores: scores, sticks: sticks, rules: rules, end: end)
    }

    static func final(scores: [Int], sticks: Int, rules: Rules, end: GameEnd) -> GameResult {
        let ranks = rank(scores)
        var final = scores
        final[ranks[0].index] += 1000 * sticks
        var adjusted = [0, 0, 0, 0]
        for (r, s) in ranks.enumerated() {
            adjusted[s.index] = final[s.index] - rules.returnPoints + rules.uma[r] + (r == 0 ? rules.oka : 0)
        }
        return GameResult(ranks: ranks, scores: final, sticksAwarded: sticks, adjusted: adjusted, end: end)
    }
}

/// A whole game: `Rules`, seed, hands dealt so far, the current position and
/// `RoundState`. When a round ends the transition runs at once, so the state rests
/// only where some seat must decide, or at the end of the game.
public struct GameState: Sendable {
    public let rules: Rules
    public let seed: UInt64
    /// Hands dealt so far, the current one included (keys the next wall).
    public private(set) var handsDealt: Int
    /// The current (or, at the end, the last) hand's starting position.
    public private(set) var position: GamePosition
    public private(set) var round: RoundState
    /// The last completed hand's result and the transition it caused.
    public private(set) var lastRound: (result: RoundResult, transition: GameTransition)?
    /// Set when the game is over.
    public private(set) var result: GameResult?
    /// Deals each hand's wall from the seed and the hand number; nil for the
    /// seeded shuffle `Wall(seed:hand:)`. (Directed self-play arranges walls.)
    public let walls: (@Sendable (_ seed: UInt64, _ hand: Int) -> Wall)?

    /// A new game: every seat on `rules.startingPoints`, East 1, seat 0 dealing.
    /// Throws if `rules` are out of range (`Rules.validate()`).
    public init(rules: Rules, seed: UInt64, events: inout [Event],
                observe: ((RoundState, Event) -> Void)? = nil) throws(InputError) {
        try rules.validate()
        try self.init(rules: rules, seed: seed,
                      position: GamePosition(scores: Array(repeating: rules.startingPoints, count: 4)),
                      events: &events, observe: observe)
    }

    /// A game from `position` (default: a new game) whose walls come from `walls`.
    public init(rules: Rules, seed: UInt64, position: GamePosition? = nil,
                walls: @escaping @Sendable (_ seed: UInt64, _ hand: Int) -> Wall,
                events: inout [Event], observe: ((RoundState, Event) -> Void)? = nil) throws(InputError) {
        try rules.validate()
        let start: GamePosition
        if let position { start = position } else {
            start = try GamePosition(scores: Array(repeating: rules.startingPoints, count: 4))
        }
        try self.init(rules: rules, seed: seed, position: start,
                      handsDealt: 0, wall: nil, walls: walls, events: &events, observe: observe)
    }

    /// A game from a given position (scenarios, tools). The first hand uses `wall`
    /// if given, else the seeded wall for `handsDealt`. Throws if the rules or the
    /// position are out of range: `Rules.validate()`, and the position's honba and
    /// sticks within 0...`RoundState.maxCount` and its scores within
    /// ±`RoundState.maxScore` (the bounds of `RoundState.init`); `handsDealt` ≥ 0.
    public init(rules: Rules, seed: UInt64, position: GamePosition, handsDealt: Int = 0, wall: Wall? = nil,
                walls: (@Sendable (_ seed: UInt64, _ hand: Int) -> Wall)? = nil,
                startGame: Bool = true, events: inout [Event],
                observe: ((RoundState, Event) -> Void)? = nil) throws(InputError) {
        try RoundState.check(rules: rules, kyoku: position.kyoku, honba: position.honba,
                             sticks: position.sticks, scores: position.scores)
        guard (0..<Int.max).contains(handsDealt) else { throw InputError("handsDealt", "\(handsDealt) is negative") }
        self.rules = rules
        self.seed = seed
        self.position = position
        self.handsDealt = handsDealt + 1
        self.walls = walls
        var e = Emitter(on: true, events: events, observe: observe)
        events = []
        let w = wall ?? walls?(seed, handsDealt) ?? Wall(seed: seed, hand: handsDealt)
        // (No round exists yet to show the observer; start_game has no state anyway.)
        if startGame { e.events.append(.startGame) }
        round = RoundState(rules: rules, wall: w, roundWind: position.roundWind, kyoku: position.kyoku,
                           honba: position.honba, sticks: position.sticks, dealer: nil,
                           scores: position.scores, emitter: &e)
        events = e.events
    }

    /// As above without events.
    public init(rules: Rules, seed: UInt64) throws(InputError) {
        var ev: [Event] = []
        try self.init(rules: rules, seed: seed, events: &ev)
    }

    public var phase: Phase { round.phase }
    public var isOver: Bool { result != nil }
    public func legalActions(for seat: Seat) -> [Action] { isOver ? [] : round.legalActions(for: seat) }
    public var seatsToAnswer: [Seat] { round.seatsToAnswer }

    /// What `seat` may know now (`RoundState.view(of:)`). Once the game is over the
    /// table shows the final scores, leftover sticks paid to first place and none
    /// left (what folding `end_game` gives, Codex final finding 4).
    public func view(of seat: Seat) -> PlayerView {
        var v = round.view(of: seat)
        if let result {
            v.table.scores = result.scores
            v.table.sticks = 0
            v.legalActions = []
        }
        return v
    }

    public mutating func apply(_ action: Action, by seat: Seat, events: inout [Event],
                               observe: ((RoundState, Event) -> Void)? = nil) throws(RoundError) {
        var e = Emitter(on: true, events: events, observe: observe)
        events = []  // the emitter owns the buffer: no copy on append (Gemini final finding 9)
        defer { events = e.events }
        try round.apply(action, by: seat, &e)
        advance(&e)
    }

    public mutating func apply(_ action: Action, by seat: Seat) throws(RoundError) {
        var e = Emitter(on: false, events: [])
        try round.apply(action, by: seat, &e)
        advance(&e)
    }

    public mutating func resolve(_ answers: Answers, events: inout [Event],
                                 observe: ((RoundState, Event) -> Void)? = nil) throws(RoundError) {
        var e = Emitter(on: true, events: events, observe: observe)
        events = []
        defer { events = e.events }
        try round.resolve(answers, &e)
        advance(&e)
    }

    public mutating func resolve(_ answers: Answers) throws(RoundError) {
        var e = Emitter(on: false, events: [])
        try round.resolve(answers, &e)
        advance(&e)
    }

    /// The scores the all-last tests read for this round's result.
    func testScores(_ r: RoundResult) -> [Int] {
        guard !rules.allLastTestAfterNagashi, case .exhaustiveDraw(_, let nagashi) = r.outcome,
              !nagashi.isEmpty else { return r.scores }
        // Before the nagashi payments: the starting scores less accepted deposits.
        return Seat.all.map { s in
            round.initialScores[s.index] - (round.riichiStatus(of: s) == .accepted ? 1000 : 0)
        }
    }

    /// After a round ends: the transition, then the next hand or the end.
    mutating func advance(_ e: inout Emitter) {
        guard let r = round.result else { return }
        let (next, transition) = GameFlow.transition(after: r, at: position, rules: rules, testScores: testScores(r))
        lastRound = (r, transition)
        guard let next else {
            guard case .ends(let end) = transition else { preconditionFailure() }
            let g = GameFlow.final(scores: r.scores, sticks: r.sticks, rules: rules, end: end)
            result = g
            round.emit(.endGame(scores: g.scores), &e)
            return
        }
        position = next
        let wall = walls?(seed, handsDealt) ?? Wall(seed: seed, hand: handsDealt)
        handsDealt += 1
        round = RoundState(rules: rules, wall: wall, roundWind: next.roundWind, kyoku: next.kyoku,
                           honba: next.honba, sticks: next.sticks, dealer: nil, scores: next.scores,
                           emitter: &e)
    }
}
