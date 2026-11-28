// What one seat may see (Docs/Design/engine.md §6): masked events and `PlayerView`.
// Code that plays a seat is handed these, never a `RoundState` or an `Event`.

/// An event as one seat sees it. A distinct type from `Event`, so an unmasked event
/// cannot be shown to a seat by mistake. `nil` is a tile the observer may not see.
public enum MaskedEvent: Hashable, Sendable {
    /// `id` is the recipient's seat.
    case startGame(id: Seat)
    /// The observer's own hand is shown; other hands are 13 unknown tiles.
    case startKyoku(bakaze: Wind, kyoku: Int, honba: Int, kyotaku: Int, oya: Seat,
                    doraMarker: Tile, scores: [Int], tehais: [[Tile?]])
    case tsumo(actor: Seat, tile: Tile?)
    case dahai(actor: Seat, tile: Tile, tsumogiri: Bool)
    case chi(actor: Seat, target: Seat, tile: Tile, consumed: [Tile])
    case pon(actor: Seat, target: Seat, tile: Tile, consumed: [Tile])
    case daiminkan(actor: Seat, target: Seat, tile: Tile, consumed: [Tile])
    case ankan(actor: Seat, consumed: [Tile])
    case kakan(actor: Seat, tile: Tile, consumed: [Tile])
    case dora(marker: Tile)
    case reach(actor: Seat)
    case reachAccepted(actor: Seat, scores: [Int])
    case hora(actor: Seat, target: Seat, tile: Tile, deltas: [Int], uraMarkers: [Tile],
              horaTehais: [Tile], scored: Scored, scores: [Int])
    /// A hand that is not tenpai is not shown (its tiles are `nil`).
    case ryukyoku(reason: DrawReason, deltas: [Int], tenpais: [Bool], tehais: [[Tile?]], scores: [Int])
    case endKyoku
    case endGame(scores: [Int])
}

extension Event {
    /// This event as `seat` sees it.
    public func masked(for seat: Seat) -> MaskedEvent {
        switch self {
        case .startGame: return .startGame(id: seat)
        case .startKyoku(let b, let k, let h, let s, let o, let d, let sc, let th):
            let tehais: [[Tile?]] = th.enumerated().map { i, hand in
                i == seat.index ? hand.map { $0 } : Array(repeating: nil, count: hand.count)
            }
            return .startKyoku(bakaze: b, kyoku: k, honba: h, kyotaku: s, oya: o, doraMarker: d,
                               scores: sc, tehais: tehais)
        case .tsumo(let a, let t): return .tsumo(actor: a, tile: a == seat ? t : nil)
        case .dahai(let a, let t, let g): return .dahai(actor: a, tile: t, tsumogiri: g)
        case .chi(let a, let tg, let t, let c): return .chi(actor: a, target: tg, tile: t, consumed: c)
        case .pon(let a, let tg, let t, let c): return .pon(actor: a, target: tg, tile: t, consumed: c)
        case .daiminkan(let a, let tg, let t, let c): return .daiminkan(actor: a, target: tg, tile: t, consumed: c)
        case .ankan(let a, let c): return .ankan(actor: a, consumed: c)
        case .kakan(let a, let t, let c): return .kakan(actor: a, tile: t, consumed: c)
        case .dora(let m): return .dora(marker: m)
        case .reach(let a): return .reach(actor: a)
        case .reachAccepted(let a, let s): return .reachAccepted(actor: a, scores: s)
        case .hora(let a, let t, let p, let d, let u, let h, let sc, let s):
            return .hora(actor: a, target: t, tile: p, deltas: d, uraMarkers: u, horaTehais: h, scored: sc, scores: s)
        case .ryukyoku(let r, let d, let tp, let th, let s):
            return .ryukyoku(reason: r, deltas: d, tenpais: tp,
                             tehais: th.enumerated().map { i, hand in
                                 tp[i] ? hand.map { $0 } : Array(repeating: nil, count: hand.count)
                             }, scores: s)
        case .endKyoku: return .endKyoku
        case .endGame(let s): return .endGame(scores: s)
        }
    }
}

/// What a window is about: a discard, or an announced kan that may be robbed.
public enum Reacting: Hashable, Sendable {
    case discard(Discard)
    case kan(PendingKan)
}

/// Everything at the table that one seat may know, and its decision.
public struct PlayerView: Hashable, Sendable {
    /// The parts that follow from the seat's masked events alone.
    public struct Table: Hashable, Sendable {
        public var seat: Seat
        public var roundWind: Wind = .east
        public var kyoku = 1
        public var honba = 0
        public var sticks = 0
        public var dealer = Seat(0)
        public var scores = [0, 0, 0, 0]
        public var doraIndicators: [Tile] = []
        public var liveTilesLeft = Wall.liveDraws
        /// The seat's concealed tiles, sorted, without the drawn tile.
        public var hand: [Tile] = []
        public var drawn: Tile?
        public var melds: [[TableMeld]] = [[], [], [], []]
        public var ponds: [[PondTile]] = [[], [], [], []]
        public var riichi: [RiichiStatus] = [.none, .none, .none, .none]
        /// The open window (whether or not this seat is asked in it).
        public var reacting: Reacting?

        public init(seat: Seat) { self.seat = seat }
    }

    public var table: Table
    /// The seat's own furiten (any kind), as the engine decides it.
    public var furiten: Bool
    /// Its three sorts (`RoundState.furitenParts(of:)`).
    public var furitenParts: FuritenParts
    /// The seat's legal actions now, in `legalActions` order.
    public var legalActions: [Action]

    public var seat: Seat { table.seat }

    /// The index in `events` (the masked events of the step that brought the seat
    /// to this decision) of the event that asks for it: the seat's draw, its chi or
    /// pon, or its riichi declaration on its turn; the discard in a discard window;
    /// the `ankan` or `kakan` in a robbing window. Only indicators (`dora`) can come
    /// after it: Mahjong Soul shows an owed one just after a chained added kan,
    /// before that kan's robbing window. Nil if the seat has no decision or the
    /// prompt is not among `events`.
    public func prompt(in events: [MaskedEvent]) -> Int? {
        guard !legalActions.isEmpty else { return nil }
        let me = seat
        guard let i = events.lastIndex(where: { e in
            switch (table.reacting, e) {
            case (.discard(let d)?, .dahai(let a, let t, _)): a == d.seat && t == d.tile
            case (.kan(let k)?, .kakan(let a, _, _)): a == k.seat && k.kind == .added
            case (.kan(let k)?, .ankan(let a, _)): a == k.seat && k.kind == .closed
            case (nil, .tsumo(let a, _)), (nil, .reach(let a)): a == me
            case (nil, .chi(let a, _, _, _)), (nil, .pon(let a, _, _, _)): a == me
            default: false
            }
        }) else { return nil }
        for e in events[(i + 1)...] {
            guard case .dora = e else { return nil }
        }
        return i
    }
}

extension RoundState {
    /// The view of `seat`. It has no wall and no other hands, and nothing in it leads
    /// back to this state.
    public func view(of seat: Seat) -> PlayerView {
        var t = PlayerView.Table(seat: seat)
        t.roundWind = roundWind
        t.kyoku = kyoku
        t.honba = honba
        t.sticks = sticks
        t.dealer = dealer
        t.scores = scores
        t.doraIndicators = doraIndicators
        t.liveTilesLeft = liveTilesLeft
        t.hand = players[seat.index].hand
        t.drawn = players[seat.index].drawn
        t.melds = players.map(\.melds)
        t.ponds = players.map(\.pond)
        t.riichi = players.map(\.riichi)
        let legal = legalActions(for: seat)
        // The window shows only to a seat asked in it: that a window is open at all
        // reveals that some seat may call.
        switch phase {
        case .reactions(let d) where !legal.isEmpty: t.reacting = .discard(d)
        case .robbing(let k) where !legal.isEmpty: t.reacting = .kan(k)
        default: t.reacting = nil
        }
        return PlayerView(table: t, furiten: players[seat.index].isFuriten, furitenParts: furitenParts(of: seat),
                          legalActions: legal)
    }
}

/// Rebuilds `PlayerView.Table` by folding one seat's masked events.
public struct ViewFolder: Sendable {
    public private(set) var table: PlayerView.Table
    /// The table as `PlayerView` shows it to a seat that is (or is not) asked to
    /// decide now: a seat not asked sees no open window.
    public func table(asked: Bool) -> PlayerView.Table {
        var t = table
        if !asked { t.reacting = nil }
        return t
    }
    /// An announced kan (a closed kan's four tiles, or an added kan's tile), until
    /// it commits; nothing changes until then.
    var pendingKan: (seat: Seat, tiles: [Tile], added: Bool)?
    /// The next draw is a replacement.
    var replacementNext = false
    var riichiDeclared: Seat?
    var kans = 0
    var liveDraws = 0

    public init(seat: Seat) { table = PlayerView.Table(seat: seat) }

    mutating func insert(_ t: Tile) {
        let i = table.hand.firstIndex { $0 > t } ?? table.hand.count
        table.hand.insert(t, at: i)
    }
    mutating func removeFromHand(_ t: Tile) {
        if table.drawn == t {
            table.drawn = nil
        } else if let i = table.hand.firstIndex(of: t) {
            table.hand.remove(at: i)
            if let d = table.drawn { insert(d); table.drawn = nil }
        }
    }

    public mutating func apply(_ e: MaskedEvent) {
        let me = table.seat
        // A pending kan commits on whatever follows it, unless that is the robbing win,
        // or an indicator: Mahjong Soul shows one still owed by the seat's earlier kan
        // right after a chained added kan, before its robbing window
        // (`Rules.owedDoraAtChainedAddedKan`), and a committing kan's own indicator
        // comes just before its replacement draw, which commits it here as well.
        var indicator = false
        if case .dora = e { indicator = true }
        if let pk = pendingKan, !indicator {
            pendingKan = nil
            if case .hora = e {
                // Robbed: the robbed tile is the winning tile.
                if pk.seat == me { removeFromHand(pk.added ? pk.tiles[0] : Tile(pk.tiles[0].kind)) }
            } else if case .ryukyoku = e {
                // Three rons on the kan: aborted, nothing made.
            } else {
                kans += 1
                if pk.seat == me {
                    if let d = table.drawn { insert(d); table.drawn = nil }
                    for x in pk.tiles { table.hand.remove(at: table.hand.firstIndex(of: x)!) }
                }
                if pk.added {
                    let ms = table.melds[pk.seat.index]
                    if let j = ms.firstIndex(where: { $0.kind == .pon && $0.tiles[0].kind == pk.tiles[0].kind }) {
                        table.melds[pk.seat.index][j] = ms[j].adding(pk.tiles[0])!
                    }
                } else {
                    table.melds[pk.seat.index].append(TableMeld.ankan(pk.tiles)!)
                }
                replacementNext = true
            }
        }
        if !(indicator && pendingKan != nil) { table.reacting = nil }
        switch e {
        case .startGame:
            break
        case .endGame(let s):
            // Final scores with leftover sticks paid to first place, matching `GameState.view(of:)`.
            table.scores = s
            table.sticks = 0
        case .startKyoku(let b, let k, let h, let s, let o, let d, let sc, let th):
            table = PlayerView.Table(seat: me)
            table.roundWind = b
            table.kyoku = k
            table.honba = h
            table.sticks = s
            table.dealer = o
            table.doraIndicators = [d]
            table.scores = sc
            table.hand = th[me.index].compactMap { $0 }.sorted()
            kans = 0
            liveDraws = 0
            replacementNext = false
            riichiDeclared = nil
        case .tsumo(let a, let t):
            if replacementNext { replacementNext = false } else { liveDraws += 1 }
            if a == me { table.drawn = t }
        case .dahai(let a, let t, let g):
            if a == me {
                if !g {
                    table.hand.remove(at: table.hand.firstIndex(of: t)!)
                    if let d = table.drawn { insert(d) }
                }
                table.drawn = nil
            }
            let riichi = riichiDeclared == a
            if riichi {
                riichiDeclared = nil
                table.riichi[a.index] = .pending
            }
            let order = table.ponds.reduce(0) { $0 + $1.count }
            table.ponds[a.index].append(PondTile(tile: t, tsumogiri: g, riichi: riichi, calledAway: false, order: order))
            table.reacting = .discard(Discard(seat: a, tile: t, tsumogiri: g, riichi: riichi))
        case .chi(let a, let tg, let t, let c), .pon(let a, let tg, let t, let c), .daiminkan(let a, let tg, let t, let c):
            let meld: TableMeld
            switch e {
            case .chi: meld = TableMeld.chi(taken: t, from: tg, using: c)!
            case .pon: meld = TableMeld.pon(taken: t, from: tg, using: c)!
            default:
                meld = TableMeld.daiminkan(taken: t, from: tg, using: c)!
                kans += 1
                replacementNext = true
            }
            table.melds[a.index].append(meld)
            table.ponds[tg.index][table.ponds[tg.index].count - 1].calledAway = true
            if a == me { for x in c { removeFromHand(x) } }
        case .ankan(let a, let c):
            pendingKan = (a, c.sorted(), false)
            table.reacting = .kan(PendingKan(seat: a, tile: Tile(c[0].kind), kind: .closed))
        case .kakan(let a, let t, _):
            pendingKan = (a, [t], true)
            table.reacting = .kan(PendingKan(seat: a, tile: t, kind: .added))
        case .dora(let m):
            table.doraIndicators.append(m)
        case .reach(let a):
            riichiDeclared = a
            table.riichi[a.index] = .declared
        case .reachAccepted(let a, let s):
            table.riichi[a.index] = .accepted
            table.scores = s
            table.sticks += 1
        case .hora(_, _, _, _, _, _, _, let s):
            table.scores = s
            table.sticks = 0
        case .ryukyoku(_, _, _, _, let s):
            table.scores = s
        case .endKyoku:
            break
        }
        table.liveTilesLeft = Wall.liveDraws - liveDraws - kans
    }
}
