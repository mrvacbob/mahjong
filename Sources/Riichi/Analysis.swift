// What a bot or a tool needs from one seat's view (docs/design/engine.md §6.1):
// the seat's wind, hand and waits, tile counts it can see, a per-discard analysis
// and basic defensive facts. Pure functions of a `PlayerView` (or of tiles and
// counts); none needs the `RoundState`.

/// The sorts of furiten (`RoundState.furitenParts(of:)`).
public struct FuritenParts: Hashable, Sendable {
    /// A wait of the seat is in its own pond.
    public var ownDiscard: Bool
    /// It let a winning tile pass since its last live draw (or call).
    public var temporary: Bool
    /// In riichi, it let a winning tile pass: for the rest of the hand.
    public var riichi: Bool

    public init(ownDiscard: Bool, temporary: Bool, riichi: Bool) {
        self.ownDiscard = ownDiscard
        self.temporary = temporary
        self.riichi = riichi
    }

    public var any: Bool { ownDiscard || temporary || riichi }
}

extension PlayerView.Table {
    /// `s`'s wind this hand.
    public func wind(of s: Seat) -> Wind { s.wind(dealer: dealer) }
    /// The viewing seat's wind this hand.
    public var seatWind: Wind { wind(of: seat) }

    /// No open meld (a closed kan keeps a hand closed).
    public func isClosed(_ s: Seat) -> Bool { melds[s.index].allSatisfy { $0.kind == .ankan } }
    public var isClosed: Bool { isClosed(seat) }

    /// `s` has declared riichi (accepted or not yet).
    public func isRiichi(_ s: Seat) -> Bool { riichi[s.index] != .none }
    /// The viewing seat's riichi status.
    public var riichiStatus: RiichiStatus { riichi[seat.index] }

    /// The viewing seat's concealed tiles, its drawn tile included.
    public var concealed: [Tile] { hand + (drawn.map { [$0] } ?? []) }

    /// Tiles the viewing seat can see, by kind: its own concealed tiles, every
    /// seat's melds, every discard still in a pond (a called discard is counted in
    /// the meld that took it), and the dora indicators.
    public var visibleCounts: Counts {
        var n = [Int](repeating: 0, count: Kind.count)
        for t in concealed { n[t.kind.index] += 1 }
        for ms in melds { for m in ms { for t in m.tiles { n[t.kind.index] += 1 } } }
        for p in ponds { for d in p where !d.calledAway { n[d.tile.kind.index] += 1 } }
        for t in doraIndicators { n[t.kind.index] += 1 }
        var c = Counts()
        for k in Kind.all { c[k] = min(n[k.index], 15) }
        return c
    }

    /// Copies of `kind` the viewing seat cannot see (in the wall or another hand).
    public func unseen(_ kind: Kind) -> Int { max(0, 4 - visibleCounts[kind]) }
}

extension PlayerView {
    /// Kinds that complete the seat's concealed hand, structurally (a fifth copy
    /// counts), as furiten is decided (`RoundState.waits(of:)`): empty unless the
    /// hand, without a drawn tile, holds 13 − 3 × melds tiles and is tenpai.
    public var waits: [Kind] {
        let melds = table.melds[seat.index].count
        guard table.hand.count == 13 - 3 * melds, isPossibleTileSet(table.hand) else { return [] }
        let m = waitMask(Counts(table.hand), meldCount: melds)
        return Kind.all.filter { m & bit($0) != 0 }
    }

    /// `discardAnalysis(concealed:meldCount:visible:candidates:)` for every legal
    /// discard (with its tsumogiri flag as offered); empty when none is legal.
    public func discardOptions() throws(InputError) -> [DiscardOption] {
        let offered = legalActions.compactMap { a -> (Tile, Bool)? in
            if case .discard(let t, let g) = a { (t, g) } else { nil }
        }
        guard !offered.isEmpty else { return [] }
        let all = try discardAnalysis(concealed: table.concealed, meldCount: table.melds[seat.index].count,
                                      visible: table.visibleCounts, candidates: offered.map(\.0))
        return offered.compactMap { t, g in
            all.first { $0.tile == t }.map { DiscardOption(tile: t, tsumogiri: g, shanten: $0.shanten, improving: $0.improving) }
        }
    }

    // MARK: defence

    /// Kinds `s` cannot ron now (genbutsu): those in its own pond (a wait there
    /// makes it furiten for every wait), those any seat discarded after its riichi
    /// declaration (passing a winning tile in riichi is furiten for the hand), and
    /// those other seats discarded since its last discard (passing one is furiten
    /// until its next draw). A discard whose window is open now has not been passed
    /// yet and counts for neither. Certain, not a guess. Empty for the viewing seat.
    public func genbutsu(against s: Seat) -> [Kind] {
        guard s != seat else { return [] }
        let own = table.ponds[s.index]
        var safe = Set(own.map(\.tile.kind))
        let riichiAt = own.first(where: \.riichi)?.order
        // A seat announcing a kan has drawn since its last discard: its temporary
        // furiten is over.
        var drewSince = false
        if case .kan(let k)? = table.reacting, k.seat == s { drewSince = true }
        let lastOwn = drewSince ? nil : own.last?.order
        // The discard of an open window (the last discard made).
        var open: Int?
        if case .discard? = table.reacting { open = table.ponds.reduce(0) { $0 + $1.count } - 1 }
        for (i, pond) in table.ponds.enumerated() where i != s.index {
            for d in pond where d.order != open {
                if let r = riichiAt, d.order > r { safe.insert(d.tile.kind) }
                if let l = lastOwn, d.order > l { safe.insert(d.tile.kind) }
            }
        }
        return Kind.all.filter(safe.contains)
    }

    /// Suited kinds, not genbutsu, that no two-sided wait (ryanmen) of `s` can win
    /// on without being furiten: every ryanmen that waits on the kind waits also
    /// on a genbutsu kind (4 needs 1 and 7, 1 needs 4, 9 needs 6). A heuristic:
    /// single, closed and edge waits, and shanpons, still win on them.
    public func suji(against s: Seat) -> [Kind] {
        guard s != seat else { return [] }
        let safe = Set(genbutsu(against: s))
        return Kind.all.filter { k in
            guard !k.isHonor, !safe.contains(k) else { return false }
            let up = k.shifted(3), down = k.shifted(-3)
            // The ryanmen k+1 k+2 waits on k and k+3 (k ≤ 6); k−2 k−1 on k−3 and k (k ≥ 4).
            let upCovered = k.number > 6 || up.map(safe.contains) == true
            let downCovered = k.number < 4 || down.map(safe.contains) == true
            return upCovered && downCovered
        }
    }

    /// Kinds whose four copies the viewing seat can all see: no other seat holds
    /// one, so no single (tanki) or shanpon wait on them is possible. A run wait on
    /// them still is.
    public var allCopiesSeen: [Kind] {
        let v = table.visibleCounts
        return Kind.all.filter { v[$0] >= 4 }
    }
}

/// One discard and what it leaves.
public struct DiscardOption: Hashable, Sendable {
    /// A kind that lowers the shanten of what is left, and how many copies of it
    /// the seat cannot see (0: every copy is in sight).
    public struct Draw: Hashable, Sendable {
        public let kind: Kind
        public let unseen: Int
    }
    public let tile: Tile
    /// As offered in `legalActions` (false from `discardAnalysis`).
    public let tsumogiri: Bool
    /// Shanten of the 13 − 3 × melds tiles left (the least of the standard form,
    /// seven pairs and kokushi; 0 is tenpai).
    public let shanten: Int
    /// Kinds that lower it, ascending, each one the hand does not already hold
    /// four of.
    public let improving: [Draw]
    /// Copies of the improving kinds the seat cannot see (ukeire).
    public var unseen: Int { improving.reduce(0) { $0 + $1.unseen } }
}

/// For each distinct tile of `candidates` (default: every distinct tile of
/// `concealed`): the shanten of the tiles left after discarding it, the kinds that
/// improve that, and how many copies of each `visible` leaves unseen (`4 −
/// visible`, never below 0). `concealed` is the seat's 14 − 3 × `meldCount` tiles;
/// `visible` counts what the seat can see, `concealed` included
/// (`PlayerView.Table.visibleCounts`). Throws for an impossible tile set, a wrong
/// number of tiles, more than four melds, or a candidate not in `concealed`.
public func discardAnalysis(concealed: [Tile], meldCount: Int, visible: Counts,
                            candidates: [Tile]? = nil) throws(InputError) -> [DiscardOption] {
    guard (0...4).contains(meldCount) else { throw InputError("meldCount", "\(meldCount) is not 0...4") }
    guard concealed.count == 14 - 3 * meldCount else {
        throw InputError("concealed", "\(concealed.count) tiles, not \(14 - 3 * meldCount)")
    }
    guard isPossibleTileSet(concealed) else {
        throw InputError("concealed", "more than four of a kind or two red fives of a suit")
    }
    let tiles = (candidates ?? concealed).distinct
    for t in tiles where !concealed.contains(t) { throw InputError("candidates", "\(t) is not held") }
    let all = Counts(concealed)
    return tiles.map { t in
        let rest = all.removing(t.kind)
        let now = shanten(rest, meldCount: meldCount).min
        let improving = Kind.all.compactMap { k -> DiscardOption.Draw? in
            guard rest[k] < 4, shanten(rest.adding(k), meldCount: meldCount).min < now else { return nil }
            return DiscardOption.Draw(kind: k, unseen: max(0, 4 - visible[k]))
        }
        return DiscardOption(tile: t, tsumogiri: false, shanten: now, improving: improving)
    }
}

extension ScoreRequest {
    /// A request with the melds as the table keeps them (`TableMeld`, as in
    /// `PlayerView.Table.melds`).
    public init(hand: [Tile], tableMelds: [TableMeld], win: Tile, context: WinContext,
                dora: [Tile] = [], ura: [Tile] = [], honba: Int = 0) {
        self.init(hand: hand, melds: tableMelds.map(\.meld), win: win, context: context,
                  dora: dora, ura: ura, honba: honba)
    }
}
