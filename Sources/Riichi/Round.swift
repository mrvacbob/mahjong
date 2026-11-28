// The round state machine (Docs/Design/engine.md §4).
//
// `RoundState` is a value. `apply` handles the turn player's action, `resolve` the
// answers to a window; both run on through draws and through windows nobody can
// use, so the state always rests where some seat must decide, or at the end.

/// A discard in a pond.
public struct PondTile: Hashable, Sendable {
    public let tile: Tile
    public let tsumogiri: Bool
    /// This discard declared riichi.
    public let riichi: Bool
    /// Another seat called it.
    public internal(set) var calledAway: Bool
    /// Its place among all the round's discards, every seat's (0 is the first):
    /// what came after a riichi, or after a seat's last discard.
    public let order: Int
}

public enum RiichiStatus: Hashable, Sendable {
    case none
    /// Declared; the riichi discard has not been made.
    case declared
    /// The riichi discard is out and its window is open.
    case pending
    /// Accepted: the stick is on the table.
    case accepted
}

/// Pao: `liable` fed the meld that completed `yakuman`.
public struct Pao: Hashable, Sendable {
    public let liable: Seat
    public let yakuman: YakuName
}

@inline(__always) func bit(_ k: Kind) -> UInt64 { 1 << UInt64(k.index) }

/// Kinds completing a 13 − 3k tile hand, structurally (a fifth copy counts): the
/// waits that furiten is decided from. A bit per kind index.
func waitMask(_ c: Counts, meldCount: Int) -> UInt64 {
    guard shanten(c, meldCount: meldCount).min == 0 else { return 0 }
    var m: UInt64 = 0
    for k in Kind.all where shanten(c.adding(k), meldCount: meldCount).min < 0 { m |= bit(k) }
    return m
}

struct PlayerState: Sendable {
    /// Concealed tiles, sorted, without the drawn tile.
    var hand: [Tile] = []
    var drawn: Tile?
    /// Counts of `hand`.
    var counts = Counts()
    var melds: [TableMeld] = []
    var analysisMelds: [Meld] = []
    var pond: [PondTile] = []
    var pondKinds: UInt64 = 0
    /// `waitMask` of `hand`; valid whenever `hand` holds 13 − 3k tiles.
    var waits: UInt64 = 0
    var riichi = RiichiStatus.none
    var doubleRiichi = false
    var ippatsu = false
    var temporaryFuriten = false
    var riichiFuriten = false
    var kans = 0
    var pao: Pao?
    /// Every discard so far a terminal or honor and none called away.
    var nagashi = true
    /// Kinds that may not be discarded now (right after a chi or pon).
    var kuikae: UInt64 = 0

    var isFuriten: Bool { temporaryFuriten || riichiFuriten || waits & pondKinds != 0 }
    var isClosed: Bool { melds.allSatisfy { $0.kind == .ankan } }

    mutating func insert(_ t: Tile) {
        let i = hand.firstIndex { $0 > t } ?? hand.count
        hand.insert(t, at: i)
    }
    mutating func remove(_ t: Tile) {
        hand.remove(at: hand.firstIndex(of: t)!)
    }
    mutating func refresh() {
        counts = Counts(hand)
        waits = waitMask(counts, meldCount: melds.count)
    }
}

/// Events go to a caller-owned buffer; with `on` false nothing is built.
struct Emitter {
    var on: Bool
    var events: [Event]
    /// Called after each event with the state as of that event (tools only).
    var observe: ((RoundState, Event) -> Void)? = nil
}

/// Where a winning tile came from.
enum WinSource {
    case draw(TurnStart)
    case discard
    case robbing(KanKind)
}

public struct RoundState: Sendable {
    /// Bounds on honba and sticks, and on each starting score, of a position given
    /// from outside (`init`, `GameState.init`): with `Rules.validate()` they keep every
    /// payment and total within 32-bit `Int` (wasm32).
    public static let maxCount = 1_000
    public static let maxScore = 100_000_000
    /// The largest honba a running game reaches: the game ends (`GameEnd.counterLimit`)
    /// rather than deal a hand with more. An engine bound to keep `300 × honba`
    /// payments within 32-bit `Int`. Sticks and scores need no running bound because
    /// every point stays among the seats and the table, preserving their initial sum.
    public static let maxRunningHonba = 1_000_000

    public let rules: Rules
    public let wall: Wall
    public let roundWind: Wind
    /// 1–4.
    public let kyoku: Int
    public let honba: Int
    public let dealer: Seat
    public let initialScores: [Int]
    public let initialSticks: Int
    public private(set) var scores: [Int]
    /// Riichi sticks on the table.
    public private(set) var sticks: Int
    public private(set) var phase: Phase

    var players: [PlayerState]
    /// Draws made from the live wall.
    var liveDrawn = 0
    var replacementsDrawn = 0
    /// Completed kans, table-wide.
    public private(set) var kanCount = 0
    /// Dora indicators shown (1 at the start).
    var doraShown = 1
    /// An open or added kan's indicator has not been shown yet.
    var doraOwed = false
    /// Any call so far, a closed kan included: ends the first go-around.
    public private(set) var anyCallMade = false
    /// The open window's choices per seat (empty when no window is open).
    var offers: [[Action]] = []
    /// Set only on the copies shown to an event observer, taken while a step is
    /// part-applied: such a state offers no actions and accepts none.
    var advancing = false

    // MARK: start

    /// Deals the hand from `wall` and makes the dealer's first draw.
    /// `dealer` defaults to seat `kyoku − 1`, `scores` to `rules.startingPoints`.
    /// Throws if the rules or the position are out of range (`Rules.validate()`,
    /// kyoku 1–4, honba and sticks 0...`maxCount`, four scores within ±`maxScore`).
    public init(rules: Rules, wall: Wall, roundWind: Wind = .east, kyoku: Int = 1,
                honba: Int = 0, sticks: Int = 0, dealer: Seat? = nil, scores: [Int]? = nil,
                events: inout [Event], observe: ((RoundState, Event) -> Void)? = nil) throws(InputError) {
        try RoundState.check(rules: rules, kyoku: kyoku, honba: honba, sticks: sticks, scores: scores)
        var e = Emitter(on: true, events: events, observe: observe)
        events = []
        self.init(rules: rules, wall: wall, roundWind: roundWind, kyoku: kyoku, honba: honba,
                  sticks: sticks, dealer: dealer, scores: scores, emitter: &e)
        events = e.events
    }

    /// As above, without events.
    public init(rules: Rules, wall: Wall, roundWind: Wind = .east, kyoku: Int = 1,
                honba: Int = 0, sticks: Int = 0, dealer: Seat? = nil, scores: [Int]? = nil) throws(InputError) {
        try RoundState.check(rules: rules, kyoku: kyoku, honba: honba, sticks: sticks, scores: scores)
        var e = Emitter(on: false, events: [])
        self.init(rules: rules, wall: wall, roundWind: roundWind, kyoku: kyoku, honba: honba,
                  sticks: sticks, dealer: dealer, scores: scores, emitter: &e)
    }

    /// The admission bounds of a position given from outside.
    static func check(rules: Rules, kyoku: Int, honba: Int, sticks: Int, scores: [Int]?) throws(InputError) {
        try rules.validate()
        guard (1...4).contains(kyoku) else { throw InputError("kyoku", "\(kyoku) is not 1...4") }
        guard (0...maxCount).contains(honba) else { throw InputError("honba", "\(honba) is not 0...\(maxCount)") }
        guard (0...maxCount).contains(sticks) else { throw InputError("sticks", "\(sticks) is not 0...\(maxCount)") }
        if let scores {
            guard scores.count == 4 else { throw InputError("scores", "\(scores.count) scores, not one per seat") }
            guard scores.allSatisfy({ abs($0) <= maxScore }) else {
                throw InputError("scores", "a score is outside ±\(maxScore)")
            }
        }
    }

    /// The engine's own path (a game's next hand): its counters may pass the
    /// admission bounds, within `maxRunningHonba` and the points in play.
    init(rules: Rules, wall: Wall, roundWind: Wind, kyoku: Int, honba: Int, sticks: Int,
         dealer: Seat?, scores: [Int]?, emitter e: inout Emitter) {
        let scores = scores ?? Array(repeating: rules.startingPoints, count: 4)
        precondition((1...4).contains(kyoku) && scores.count == 4 && (0...RoundState.maxRunningHonba).contains(honba)
                     && sticks >= 0, "internal: position out of range")
        self.rules = rules
        self.wall = wall
        self.roundWind = roundWind
        self.kyoku = kyoku
        self.honba = honba
        self.sticks = sticks
        self.dealer = dealer ?? Seat(kyoku - 1)
        self.initialScores = scores
        self.initialSticks = sticks
        self.scores = scores
        phase = .turn(self.dealer, .draw)
        players = Seat.all.map { s in
            var p = PlayerState()
            p.hand = wall.dealt(to: s, dealer: dealer ?? Seat(kyoku - 1)).sorted()
            p.refresh()
            return p
        }
        let tehais = players.map(\.hand)
        emit(.startKyoku(bakaze: roundWind, kyoku: kyoku, honba: honba, kyotaku: sticks,
                      oya: self.dealer, doraMarker: wall.doraIndicator(0), scores: scores,
                      tehais: tehais), &e)
        drawLive(self.dealer, &e)
    }

    /// Appends an event to the caller's buffer (building nothing if there is none)
    /// and shows the observer, if any, the state as of this event. The step is not
    /// finished, so the observer gets a copy marked as advancing: its
    /// `legalActions` and `seatsToAnswer` are empty and `apply` and `resolve` throw
    /// `wrongPhase`.
    @inline(__always) func emit(_ ev: @autoclosure () -> Event, _ e: inout Emitter) {
        guard e.on else { return }
        let event = ev()
        e.events.append(event)
        if let observe = e.observe {
            var snapshot = self
            snapshot.advancing = true
            observe(snapshot, event)
        }
    }

    // MARK: queries

    /// Live wall tiles left: 70 − live draws − completed kans.
    public var liveTilesLeft: Int { Wall.liveDraws - liveDrawn - kanCount }
    public var doraIndicators: [Tile] { (0..<doraShown).map(wall.doraIndicator) }
    public var result: RoundResult? {
        if case .ended(let r) = phase { r } else { nil }
    }
    public func hand(of seat: Seat) -> [Tile] { players[seat.index].hand }
    public func drawnTile(of seat: Seat) -> Tile? { players[seat.index].drawn }
    public func melds(of seat: Seat) -> [TableMeld] { players[seat.index].melds }
    public func pond(of seat: Seat) -> [PondTile] { players[seat.index].pond }
    public func riichiStatus(of seat: Seat) -> RiichiStatus { players[seat.index].riichi }
    public func pao(of seat: Seat) -> Pao? { players[seat.index].pao }
    /// Structural waits of the seat's concealed hand (empty while it holds a tile
    /// to discard after a call).
    public func waits(of seat: Seat) -> [Kind] {
        let w = players[seat.index].waits
        return Kind.all.filter { w & bit($0) != 0 }
    }
    /// Furiten of any sort: own discard, temporary or riichi.
    public func isFuriten(_ seat: Seat) -> Bool { players[seat.index].isFuriten }
    /// The three sorts separately: a wait in the seat's own pond, temporary (until
    /// its next live draw), riichi (for the rest of the hand).
    public func furitenParts(of seat: Seat) -> FuritenParts {
        let p = players[seat.index]
        return FuritenParts(ownDiscard: p.waits & p.pondKinds != 0, temporary: p.temporaryFuriten, riichi: p.riichiFuriten)
    }

    /// Seats that must answer the open window, ascending.
    public var seatsToAnswer: [Seat] {
        offers.isEmpty || advancing ? [] : Seat.all.filter { !offers[$0.index].isEmpty }
    }

    // MARK: stepping

    /// The turn player's action. Throws, leaving the state unchanged, unless the
    /// action is in `legalActions(for: seat)`.
    /// `observe`, if given, is shown the state as of each event as it is emitted
    /// (tools that need per-event snapshots; the engine itself never calls out).
    /// That state is mid-step: it offers no actions and accepts none (`emit`).
    public mutating func apply(_ action: Action, by seat: Seat, events: inout [Event],
                               observe: ((RoundState, Event) -> Void)? = nil) throws(RoundError) {
        var e = Emitter(on: true, events: events, observe: observe)
        events = []
        defer { events = e.events }
        try apply(action, by: seat, &e)
    }

    public mutating func apply(_ action: Action, by seat: Seat) throws(RoundError) {
        var e = Emitter(on: false, events: [])
        try apply(action, by: seat, &e)
    }

    /// Answers to the open window: one per seat in `seatsToAnswer`, from its
    /// `legalActions`; other seats `nil` (or `.pass`).
    public mutating func resolve(_ answers: Answers, events: inout [Event],
                                 observe: ((RoundState, Event) -> Void)? = nil) throws(RoundError) {
        var e = Emitter(on: true, events: events, observe: observe)
        events = []
        defer { events = e.events }
        try resolve(answers, &e)
    }

    public mutating func resolve(_ answers: Answers) throws(RoundError) {
        var e = Emitter(on: false, events: [])
        try resolve(answers, &e)
    }

    /// Non-mutating forms, for tests and tools.
    public func applying(_ action: Action, by seat: Seat) throws(RoundError) -> (RoundState, [Event]) {
        var s = self, ev: [Event] = []
        try s.apply(action, by: seat, events: &ev)
        return (s, ev)
    }
    public func resolving(_ answers: Answers) throws(RoundError) -> (RoundState, [Event]) {
        var s = self, ev: [Event] = []
        try s.resolve(answers, events: &ev)
        return (s, ev)
    }

    mutating func apply(_ action: Action, by seat: Seat, _ e: inout Emitter) throws(RoundError) {
        guard !advancing, case .turn(let s, let start) = phase else { throw .wrongPhase }
        guard s == seat else { throw .notYourTurn(seat) }
        guard isLegalTurnAction(action, seat: seat, start: start) else { throw .illegal(seat, action) }
        let i = seat.index
        switch action {
        case .tsumo, .kyuushu: break
        default: declineWinningDraw(seat, start)
        }
        switch action {
        case .discard(let t, let tsumogiri):
            discard(seat, t, tsumogiri: tsumogiri, riichi: start == .riichiDeclared, &e)
        case .riichi:
            players[i].riichi = .declared
            players[i].doubleRiichi = !anyCallMade && players[i].pond.isEmpty
            phase = .turn(seat, .riichiDeclared)
            emit(.reach(actor: seat), &e)
        case .tsumo:
            settle(winners: [seat], tile: players[i].drawn!, from: seat, source: .draw(start), &e)
        case .ankan(let k):
            announceClosedKan(seat, k, &e)
        case .kakan(let t):
            announceAddedKan(seat, t, &e)
        case .kyuushu:
            abort(.kyuushu, &e)
        default:
            throw .illegal(seat, action)
        }
    }

    mutating func resolve(_ answers: Answers, _ e: inout Emitter) throws(RoundError) {
        guard !advancing else { throw .wrongPhase }
        switch phase {
        case .reactions, .robbing: break
        default: throw .wrongPhase
        }
        for s in Seat.all {
            let offered = offers[s.index], a = answers[s]
            if offered.isEmpty {
                if let a, a != .pass { throw .illegal(s, a) }
            } else {
                guard let a else { throw .missingAnswer(s) }
                guard offered.contains(a) else { throw .illegal(s, a) }
            }
        }
        offers = []
        switch phase {
        case .reactions(let d): closeDiscardWindow(d, answers, &e)
        case .robbing(let k): closeKanWindow(k, answers, &e)
        default: break
        }
    }

    // MARK: draws

    mutating func drawLive(_ seat: Seat, _ e: inout Emitter) {
        guard liveTilesLeft > 0 else { return exhaustiveDraw(&e) }
        let t = wall.liveDraw(liveDrawn)
        liveDrawn += 1
        players[seat.index].drawn = t
        players[seat.index].temporaryFuriten = false
        phase = .turn(seat, .draw)
        emit(.tsumo(actor: seat, tile: t), &e)
    }

    mutating func drawReplacement(_ seat: Seat, _ e: inout Emitter) {
        let t = wall.replacement(replacementsDrawn)
        replacementsDrawn += 1
        players[seat.index].drawn = t
        phase = .turn(seat, .replacementDraw)
        emit(.tsumo(actor: seat, tile: t), &e)
    }

    mutating func revealIndicator(_ e: inout Emitter) {
        doraShown += 1
        emit(.dora(marker: wall.doraIndicator(doraShown - 1)), &e)
    }

    mutating func revealOwed(_ e: inout Emitter) {
        if doraOwed {
            doraOwed = false
            revealIndicator(&e)
        }
    }

    /// The turn seat does something other than `tsumo` with a drawn tile. A riichi
    /// seat whose drawn tile was a winning kind is furiten for the rest of the hand
    /// (whether or not it had a yaku: in riichi it always does). Under
    /// `Rules.temporaryFuritenOnDeclinedTsumo`, any other seat that could have
    /// declared `tsumo` is temporarily furiten until its next live-wall draw; a
    /// replacement draw after a kan does not clear it (design §4.2). (Off in both
    /// presets: a tsumo declined by a discard leaves the seat furiten on the
    /// discarded tile anyway, and Tenhou's records show seats that declined by a
    /// kan winning by ron before their next live draw.)
    mutating func declineWinningDraw(_ seat: Seat, _ start: TurnStart) {
        let i = seat.index
        guard start == .draw || start == .replacementDraw, let d = players[i].drawn else { return }
        if players[i].riichi == .accepted {
            if players[i].waits & bit(d.kind) != 0 { players[i].riichiFuriten = true }
        } else if rules.temporaryFuritenOnDeclinedTsumo && canTsumo(seat, start) {
            players[i].temporaryFuriten = true
        }
    }

    // MARK: discards

    mutating func discard(_ seat: Seat, _ t: Tile, tsumogiri: Bool, riichi: Bool, _ e: inout Emitter) {
        let i = seat.index
        // Tenhou: an owed indicator is flipped immediately before the discard
        // (「後めくり（打牌または続く嶺上の直前）」), so a ron on it counts it.
        if rules.openKanDoraBeforeRon { revealOwed(&e) }
        if players[i].riichi == .accepted { players[i].ippatsu = false }
        if tsumogiri {
            players[i].drawn = nil  // the hand is unchanged, and so are its waits
        } else {
            players[i].remove(t)
            if let d = players[i].drawn { players[i].insert(d) }
            players[i].drawn = nil
            players[i].refresh()
        }
        players[i].kuikae = 0
        let order = players.reduce(0) { $0 + $1.pond.count }
        players[i].pond.append(PondTile(tile: t, tsumogiri: tsumogiri, riichi: riichi, calledAway: false, order: order))
        players[i].pondKinds |= bit(t.kind)
        if !t.kind.isYaochu { players[i].nagashi = false }
        if riichi { players[i].riichi = .pending }
        emit(.dahai(actor: seat, tile: t, tsumogiri: tsumogiri), &e)

        let d = Discard(seat: seat, tile: t, tsumogiri: tsumogiri, riichi: riichi)
        let o = discardOffers(d)
        if o.contains(where: { !$0.isEmpty }) {
            offers = o
            phase = .reactions(d)
        } else {
            closeDiscardWindow(d, Answers(), &e)
        }
    }

    /// Every seat waiting on `kind` (other than `seat`) becomes furiten: temporary,
    /// or permanent in riichi. For a closed kan only seats that could have robbed it.
    mutating func markFuriten(_ kind: Kind, except seat: Seat, closedKan: Bool) {
        for s in Seat.all where s != seat {
            let p = players[s.index]
            let waiting = closedKan
                ? rules.kokushiRobsClosedKan && p.melds.isEmpty && isKokushi(p.counts.adding(kind))
                : p.waits & bit(kind) != 0
            guard waiting else { continue }
            if p.riichi == .accepted { players[s.index].riichiFuriten = true }
            else { players[s.index].temporaryFuriten = true }
        }
    }

    mutating func acceptRiichi(_ seat: Seat, _ e: inout Emitter) {
        let i = seat.index
        players[i].riichi = .accepted
        players[i].ippatsu = true
        scores[i] -= 1000
        sticks += 1
        emit(.reachAccepted(actor: seat, scores: scores), &e)
    }

    func isFourWinds(_ d: Discard) -> Bool {
        guard !anyCallMade, d.tile.kind.isWind else { return false }
        return players.allSatisfy { $0.pond.count == 1 && $0.pond[0].tile.kind == d.tile.kind }
    }

    /// Ron winners among `answers`, in turn order from `from`.
    func rons(_ answers: Answers, from: Seat) -> [Seat] {
        (1...3).map { from.advanced(by: $0) }.filter { answers[$0] == .ron }
    }

    /// The resolution table of design §4.1.
    mutating func closeDiscardWindow(_ d: Discard, _ answers: Answers, _ e: inout Emitter) {
        let winners = rons(answers, from: d.seat)
        if !winners.isEmpty {                                                   // row 1
            if winners.count == 3 && rules.tripleRonAborts { return abort(.sanchahou, &e) }
            return settle(winners: winners, tile: d.tile, from: d.seat, source: .discard, &e)
        }
        markFuriten(d.tile.kind, except: d.seat, closedKan: false)
        // Mahjong Soul: an open or added kan's owed indicator, once no ron is made and
        // before anything else (a four-kan abort included). Under Tenhou it was shown
        // at the discard. (A riichi or four winds cannot fall on such a discard: both
        // need a closed table or hand.)
        revealOwed(&e)
        if isFourWinds(d) {                                                     // row 2
            if d.riichi && rules.fourWindsRiichiStickPaid { acceptRiichi(d.seat, &e) }
            return abort(.suufonRenda, &e)
        }
        if d.riichi { acceptRiichi(d.seat, &e) }                                // row 3
        if kanCount == 4 && players.count(where: { $0.kans > 0 }) >= 2 {        // row 4
            return abort(.suukaikan, &e)
        }
        if d.riichi && players.allSatisfy({ $0.riichi == .accepted }) {         // row 5
            return abort(.suuchaRiichi, &e)
        }
        let callers = (1...3).map { d.seat.advanced(by: $0) }
        if let s = callers.first(where: {
            switch answers[$0] { case .pon, .daiminkan: true; default: false }
        }) {                                                                    // row 6
            return makeCall(s, answers[s]!, d, &e)
        }
        if let s = callers.first(where: {
            if case .chi = answers[$0] { true } else { false }
        }) {                                                                    // row 7
            return makeCall(s, answers[s]!, d, &e)
        }
        if liveTilesLeft == 0 { return exhaustiveDraw(&e) }                     // row 8
        drawLive(d.seat.next, &e)                                               // row 9
    }

    // MARK: calls

    mutating func makeCall(_ caller: Seat, _ action: Action, _ d: Discard, _ e: inout Emitter) {
        let di = d.seat.index, i = caller.index
        players[di].pond[players[di].pond.count - 1].calledAway = true
        players[di].nagashi = false
        let k = d.tile.kind
        let meld: TableMeld
        switch action {
        case .pon(let a, let b):
            meld = TableMeld.pon(taken: d.tile, from: d.seat, using: [a, b])!
            players[i].kuikae = bit(k)
        case .chi(let a, let b):
            meld = TableMeld.chi(taken: d.tile, from: d.seat, using: [a, b])!
            players[i].kuikae = chiKuikae(took: k, a.kind, b.kind)
        default:
            meld = TableMeld.daiminkan(taken: d.tile, from: d.seat,
                                       using: players[i].hand.filter { $0.kind == k })!
        }
        for t in meld.consumed { players[i].remove(t) }
        players[i].melds.append(meld)
        players[i].analysisMelds.append(meld.meld)
        anyCallMade = true
        for s in 0..<4 { players[s].ippatsu = false }
        if rules.temporaryFuritenEndsOnCall { players[i].temporaryFuriten = false }
        checkPao(caller, meld)
        // The state is updated before the event, so that the event shows it settled.
        if meld.kind == .daiminkan {
            players[i].refresh()
            kanCount += 1
            players[i].kans += 1
        } else {
            players[i].counts = Counts(players[i].hand)
            players[i].waits = 0  // 14 − 3k tiles: no waits until the discard
            phase = .turn(caller, .call)
        }
        switch meld.kind {
        case .chi: emit(.chi(actor: caller, target: d.seat, tile: d.tile, consumed: meld.consumed), &e)
        case .pon: emit(.pon(actor: caller, target: d.seat, tile: d.tile, consumed: meld.consumed), &e)
        default: emit(.daiminkan(actor: caller, target: d.seat, tile: d.tile, consumed: meld.consumed), &e)
        }
        if meld.kind == .daiminkan {
            revealOwed(&e)
            doraOwed = true
            drawReplacement(caller, &e)
        }
    }

    /// The pon or open kan that completes the third dragon set or the fourth wind
    /// set makes its feeder liable.
    mutating func checkPao(_ caller: Seat, _ meld: TableMeld) {
        guard meld.kind == .pon || meld.kind == .daiminkan, let from = meld.from else { return }
        let k = meld.tiles[0].kind
        let sets = players[caller.index].melds.filter { $0.kind != .chi }.map { $0.tiles[0].kind }
        if k.isDragon && sets.count(where: \.isDragon) == 3 {
            players[caller.index].pao = Pao(liable: from, yakuman: .daisangen)
        } else if k.isWind && sets.count(where: \.isWind) == 4 {
            players[caller.index].pao = Pao(liable: from, yakuman: .daisuushii)
        }
    }

    // MARK: kans

    // A closed or added kan is a transaction: announced (the `ankan`/`kakan` event and
    // the robbing window) with nothing changed, then committed or robbed. Until the
    // window closes the declarer's hand, drawn tile, melds and cached waits are as
    // they were before the announcement.

    mutating func announceClosedKan(_ seat: Seat, _ k: Kind, _ e: inout Emitter) {
        let p = players[seat.index]
        revealOwed(&e)  // design §4.2: open kan then closed kan shows the owed one first
        var tiles = p.hand.filter { $0.kind == k }
        if let d = p.drawn, d.kind == k { tiles.append(d) }
        emit(.ankan(actor: seat, consumed: tiles.sorted()), &e)
        let pk = PendingKan(seat: seat, tile: Tile(k), kind: .closed)
        let o = kanOffers(pk)
        if o.contains(where: { !$0.isEmpty }) {
            offers = o
            phase = .robbing(pk)
        } else {
            commitKan(pk, &e)
        }
    }

    mutating func announceAddedKan(_ seat: Seat, _ t: Tile, _ e: inout Emitter) {
        let m = players[seat.index].melds.first { $0.kind == .pon && $0.tiles[0].kind == t.kind }!
        emit(.kakan(actor: seat, tile: t, consumed: m.tiles), &e)
        if rules.owedDoraAtChainedAddedKan { revealOwed(&e) }
        let pk = PendingKan(seat: seat, tile: t, kind: .added)
        let o = kanOffers(pk)
        if o.contains(where: { !$0.isEmpty }) {
            offers = o
            phase = .robbing(pk)
        } else {
            commitKan(pk, &e)
        }
    }

    /// Takes `t` out of the seat's concealed tiles (the drawn tile if it is `t`);
    /// the drawn tile, if any is left, joins the hand.
    mutating func take(_ t: Tile, from seat: Seat) {
        let i = seat.index
        if players[i].drawn == t {
            players[i].drawn = nil
        } else {
            players[i].remove(t)
            if let d = players[i].drawn { players[i].insert(d) }
            players[i].drawn = nil
        }
    }

    mutating func closeKanWindow(_ pk: PendingKan, _ answers: Answers, _ e: inout Emitter) {
        let winners = rons(answers, from: pk.seat)
        if !winners.isEmpty {
            // Three rons abort with the kan never made: every tile stays where it was.
            if winners.count == 3 && rules.tripleRonAborts { return abort(.sanchahou, &e) }
            // The robbed tile is the winning tile; the declarer keeps the rest.
            take(pk.tile, from: pk.seat)
            players[pk.seat.index].refresh()
            return settle(winners: winners, tile: pk.tile, from: pk.seat, source: .robbing(pk.kind), &e)
        }
        commitKan(pk, &e)
    }

    mutating func commitKan(_ pk: PendingKan, _ e: inout Emitter) {
        let i = pk.seat.index
        markFuriten(pk.tile.kind, except: pk.seat, closedKan: pk.kind == .closed)
        kanCount += 1
        players[i].kans += 1
        anyCallMade = true
        for s in 0..<4 { players[s].ippatsu = false }
        switch pk.kind {
        case .closed:
            let k = pk.tile.kind
            var tiles = players[i].hand.filter { $0.kind == k }
            for t in tiles { players[i].remove(t) }
            if let d = players[i].drawn {
                if d.kind == k { tiles.append(d) } else { players[i].insert(d) }
            }
            players[i].drawn = nil
            let meld = TableMeld.ankan(tiles)!
            players[i].melds.append(meld)
            players[i].analysisMelds.append(meld.meld)
            players[i].refresh()
            revealIndicator(&e)
        case .added:
            take(pk.tile, from: pk.seat)
            let j = players[i].melds.firstIndex { $0.kind == .pon && $0.tiles[0].kind == pk.tile.kind }!
            let kan = players[i].melds[j].adding(pk.tile)!
            players[i].melds[j] = kan
            players[i].analysisMelds[j] = kan.meld
            players[i].refresh()
            revealOwed(&e)
            doraOwed = true
        }
        drawReplacement(pk.seat, &e)
    }

    // MARK: endings

    mutating func end(_ outcome: RoundResult.Outcome, dealerRepeats: Bool, _ e: inout Emitter) {
        let deltas = (0..<4).map { scores[$0] - initialScores[$0] }
        phase = .ended(RoundResult(outcome: outcome, deltas: deltas, scores: scores, sticks: sticks,
                                   dealer: dealer, dealerRepeats: dealerRepeats))
        offers = []
        emit(.endKyoku, &e)
    }

    mutating func abort(_ reason: AbortReason, _ e: inout Emitter) {
        emit(.ryukyoku(reason: .abort(reason), deltas: [0, 0, 0, 0],
                    tenpais: [false, false, false, false], tehais: players.map(\.hand), scores: scores), &e)
        end(.abortiveDraw(reason), dealerRepeats: true, &e)
    }

    mutating func exhaustiveDraw(_ e: inout Emitter) {
        let tenpai = Seat.all.filter { isTenpaiForPayment(players[$0.index]) }
        let nagashi = Seat.all.filter { players[$0.index].nagashi && !players[$0.index].pond.isEmpty }
        var deltas = [0, 0, 0, 0]
        if !nagashi.isEmpty {
            for s in nagashi {
                for o in Seat.all where o != s {
                    let pay = s == dealer || o == dealer ? 4000 : 2000
                    deltas[o.index] -= pay
                    deltas[s.index] += pay
                }
            }
        } else if (1...3).contains(tenpai.count) {
            for s in Seat.all {
                deltas[s.index] = tenpai.contains(s) ? 3000 / tenpai.count : -3000 / (4 - tenpai.count)
            }
        }
        for s in 0..<4 { scores[s] += deltas[s] }
        emit(.ryukyoku(reason: .exhaustive, deltas: deltas, tenpais: Seat.all.map(tenpai.contains),
                    tehais: players.map(\.hand), scores: scores), &e)
        end(.exhaustiveDraw(tenpai: tenpai, nagashi: nagashi), dealerRepeats: tenpai.contains(dealer), &e)
    }

    /// `isTenpaiAtDraw` from the cached waits: some wait counts under the rules'
    /// fifth-copy test (rules.md §5 item 7).
    func isTenpaiForPayment(_ p: PlayerState) -> Bool {
        guard p.waits != 0 else { return false }
        let meldKinds = Counts(p.analysisMelds.tiles)
        return Kind.all.contains { w in
            guard p.waits & bit(w) != 0 else { return false }
            return rules.fifthCopyTenpaiAtDraw ? p.counts[w] < 4 : p.counts[w] + meldKinds[w] < 4
        }
    }

    /// Scores `seat` winning on `tile`, or nil if it is not a win with a yaku.
    func scoreWin(_ seat: Seat, _ tile: Tile, source: WinSource, honba: Int) -> Scored? {
        try? scoreChecked(winRequest(seat, tile, source: source, honba: honba), rules: rules)
    }

    /// The `score` question for the win `seat` may declare now (its `tsumo`, or a
    /// `ron` on the open window's tile); nil if it has no such option. A host-side
    /// tool (the Mercury cross-check dump): the request holds the ura indicators,
    /// which no seat may see before the win.
    ///
    /// The honba of a ron depend on the other answers: they go to the winner
    /// nearest the discarder (every winner under `Rules.honbaToEveryRonWinner`).
    /// Given `answers` (the window's answers), the winners are the seats that answer
    /// `ron` there, and the request is nil if `seat` does not, or if three rons
    /// abort the hand; without them, `seat` is taken to be the only winner.
    public func winRequest(for seat: Seat, answers: Answers? = nil) -> ScoreRequest? {
        func ronHonba(from discarder: Seat) -> Int? {
            guard let answers else { return honba }
            guard answers[seat] == .ron else { return nil }
            let winners = rons(answers, from: discarder)
            if winners.count == 3 && rules.tripleRonAborts { return nil }
            return winners.first == seat || rules.honbaToEveryRonWinner ? honba : 0
        }
        switch phase {
        case .turn(let s, let start) where s == seat && canTsumo(seat, start):
            return winRequest(seat, players[seat.index].drawn!, source: .draw(start), honba: honba)
        case .reactions(let d) where legalActions(for: seat).contains(.ron):
            guard let h = ronHonba(from: d.seat) else { return nil }
            return winRequest(seat, d.tile, source: .discard, honba: h)
        case .robbing(let k) where legalActions(for: seat).contains(.ron):
            guard let h = ronHonba(from: k.seat) else { return nil }
            return winRequest(seat, k.tile, source: .robbing(k.kind), honba: h)
        default:
            return nil
        }
    }

    func winRequest(_ seat: Seat, _ tile: Tile, source: WinSource, honba: Int) -> ScoreRequest {
        let p = players[seat.index]
        var flags: Set<Flag> = []
        if p.riichi == .accepted { flags.insert(p.doubleRiichi ? .double_riichi : .riichi) }
        if p.ippatsu { flags.insert(.ippatsu) }
        let tsumo: Bool
        switch source {
        case .draw(let start):
            tsumo = true
            if start == .replacementDraw { flags.insert(.rinshan) }
            if start == .draw && liveTilesLeft == 0 { flags.insert(.haitei) }
            if start == .draw && !anyCallMade && p.pond.isEmpty {
                flags.insert(seat == dealer ? .tenhou : .chiihou)
            }
        case .discard:
            tsumo = false
            if liveTilesLeft == 0 { flags.insert(.houtei) }
        case .robbing(let kind):
            tsumo = false
            if kind == .added { flags.insert(.chankan) }
        }
        let context = WinContext(seat: seat.wind(dealer: dealer), round: roundWind, tsumo: tsumo,
                                 flags: flags)
        let inRiichi = p.riichi == .accepted
        return ScoreRequest(hand: p.hand, melds: p.analysisMelds, win: tile, context: context,
                            dora: doraIndicators,
                            ura: inRiichi ? (0..<doraShown).map(wall.uraIndicator) : [],
                            honba: honba)
    }

    mutating func settle(winners: [Seat], tile: Tile, from: Seat, source: WinSource, _ e: inout Emitter) {
        var wins: [Win] = []
        var repeats = false
        for (n, w) in winners.enumerated() {
            let h = n == 0 || rules.honbaToEveryRonWinner ? honba : 0
            let scored = scoreWin(w, tile, source: source, honba: h)!
            let tsumo = from == w
            let dealerWin = w == dealer
            if dealerWin { repeats = true }
            var deltas = [0, 0, 0, 0]
            func pay(_ s: Seat, _ amount: Int) {
                deltas[s.index] -= amount
                deltas[w.index] += amount
            }
            func ronValue(_ multiple: Int) -> Int { roundUp100(8000 * multiple * (dealerWin ? 6 : 4)) }
            var liable: Seat?
            let pao = players[w.index].pao
            if let pao, case .yakuman = scored.value, scored.value(of: pao.yakuman) != nil {
                liable = pao.liable
            }
            if let pao, liable != nil, case .yakuman(let total) = scored.value,
               let own = scored.value(of: pao.yakuman), !(from == pao.liable && !tsumo) {
                // (A ron from the liable seat itself is an ordinary payment: it pays all.)
                let m = rules.paoCoversWholeHand ? total : own
                let rest = total - m
                if tsumo {
                    pay(pao.liable, ronValue(m) + 300 * h)
                    if rest > 0 {
                        let ctx = WinContext(seat: w.wind(dealer: dealer), round: roundWind, tsumo: true)
                        switch payment(basic: 8000 * rest, context: ctx, honba: 0) {
                        case .dealerTsumo(let each): for o in Seat.all where o != w { pay(o, each) }
                        case .tsumo(let nd, let d):
                            for o in Seat.all where o != w { pay(o, o == dealer ? d : nd) }
                        case .ron: break
                        }
                    }
                } else {
                    let half = ronValue(m) / 2
                    pay(pao.liable, half + 300 * h)
                    pay(from, half + (rest > 0 ? ronValue(rest) : 0))
                }
            } else {
                switch scored.payment {
                case .ron(let amount): pay(from, amount)
                case .dealerTsumo(let each): for o in Seat.all where o != w { pay(o, each) }
                case .tsumo(let nd, let d): for o in Seat.all where o != w { pay(o, o == dealer ? d : nd) }
                }
            }
            if n == 0 {
                deltas[w.index] += 1000 * sticks
                sticks = 0
            }
            for s in 0..<4 { scores[s] += deltas[s] }
            let ura = players[w.index].riichi == .accepted ? (0..<doraShown).map(wall.uraIndicator) : []
            let win = Win(winner: w, from: from, tile: tile, scored: scored, doraIndicators: doraIndicators,
                          uraIndicators: ura, deltas: deltas, liable: liable,
                          robbedKan: { if case .robbing(let k) = source { k } else { nil } }())
            wins.append(win)
            emit(.hora(actor: w, target: from, tile: tile, deltas: deltas, uraMarkers: ura,
                    horaTehais: players[w.index].hand, scored: scored, scores: scores), &e)
        }
        end(.wins(wins), dealerRepeats: repeats, &e)
    }
}

/// Kinds forbidden right after a chi of `took` with `a` and `b` from the hand.
func chiKuikae(took: Kind, _ a: Kind, _ b: Kind) -> UInt64 {
    var m = bit(took)
    let (lo, hi) = a < b ? (a, b) : (b, a)
    if lo.shifted(1) == hi {
        if took < lo, let far = hi.shifted(1) { m |= bit(far) }
        if took > hi, let far = lo.shifted(-1) { m |= bit(far) }
    }
    return m
}
