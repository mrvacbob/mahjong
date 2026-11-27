// Seats at the table and melds as the table records them.

/// A seat, fixed for the whole game. Seat 0 is the first dealer; turn order is
/// 0, 1, 2, 3 (each seat's shimocha is the next index).
public struct Seat: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let index: Int

    public init(_ index: Int) {
        precondition((0..<4).contains(index), "seat index out of range")
        self.index = index
    }

    public static let all = (0..<4).map(Seat.init)

    /// The seat `n` places later in turn order (`n` may be negative).
    public func advanced(by n: Int) -> Seat { Seat(((index + n) % 4 + 4) % 4) }
    /// The next seat to play after this one (shimocha).
    public var next: Seat { advanced(by: 1) }
    /// How many places after `other` this seat plays: 0 for itself, 1 for its
    /// shimocha, 3 for its kamicha.
    public func distance(from other: Seat) -> Int { ((index - other.index) % 4 + 4) % 4 }

    /// This seat's wind when `dealer` is East.
    public func wind(dealer: Seat) -> Wind { Wind(rawValue: distance(from: dealer) + 1)! }

    public static func < (a: Seat, b: Seat) -> Bool { a.index < b.index }
    public var description: String { "\(index)" }
}

/// A meld as the round keeps it: the analysis `Meld` plus where its tiles came from.
/// Kuikae, pao, nagashi mangan, mjai's `target`/`pai`/`consumed` and an added kan's
/// history read from here.
public struct TableMeld: Hashable, Sendable {
    public let kind: MeldKind
    /// All tiles of the meld, in canonical order.
    public let tiles: [Tile]
    /// The tile called from another seat's discard; nil for a closed kan. For an
    /// added kan, the tile taken for the original pon.
    public let taken: Tile?
    /// The seat whose discard was called; nil exactly when `taken` is.
    public let from: Seat?
    /// For an added kan only: the tile added to the pon.
    public let added: Tile?

    private init?(kind: MeldKind, tiles: [Tile], taken: Tile?, from: Seat?, added: Tile?) {
        guard Meld(kind: kind, tiles: tiles) != nil else { return nil }
        self.kind = kind
        self.tiles = tiles.sorted()
        self.taken = taken
        self.from = from
        self.added = added
    }

    /// Chi of `taken` (from the caller's kamicha) with two tiles from hand.
    public static func chi(taken: Tile, from: Seat, using hand: [Tile]) -> TableMeld? {
        guard hand.count == 2 else { return nil }
        return TableMeld(kind: .chi, tiles: hand + [taken], taken: taken, from: from, added: nil)
    }
    /// Pon of `taken` with two tiles from hand.
    public static func pon(taken: Tile, from: Seat, using hand: [Tile]) -> TableMeld? {
        guard hand.count == 2 else { return nil }
        return TableMeld(kind: .pon, tiles: hand + [taken], taken: taken, from: from, added: nil)
    }
    /// Open kan of `taken` with three tiles from hand.
    public static func daiminkan(taken: Tile, from: Seat, using hand: [Tile]) -> TableMeld? {
        guard hand.count == 3 else { return nil }
        return TableMeld(kind: .daiminkan, tiles: hand + [taken], taken: taken, from: from, added: nil)
    }
    /// Closed kan of four tiles from hand.
    public static func ankan(_ hand: [Tile]) -> TableMeld? {
        TableMeld(kind: .ankan, tiles: hand, taken: nil, from: nil, added: nil)
    }
    /// This pon with `tile` added (shouminkan). Keeps the pon's taken tile and source.
    public func adding(_ tile: Tile) -> TableMeld? {
        guard kind == .pon, tile.kind == tiles[0].kind else { return nil }
        return TableMeld(kind: .shouminkan, tiles: tiles + [tile], taken: taken, from: from, added: tile)
    }

    /// The analysis view.
    public var meld: Meld { Meld(kind: kind, tiles: tiles)! }

    /// The tiles that came from the owner's hand: mjai's `consumed`. For an added
    /// kan, the three tiles of the pon (mjai's `consumed` for `kakan`), so the added
    /// tile is `added` and not here.
    public var consumed: [Tile] {
        switch kind {
        case .ankan: return tiles
        case .shouminkan: return tiles.removingOne(added!)
        default: return tiles.removingOne(taken!)
        }
    }

    /// Kinds that may not be discarded right after this chi or pon (empty for kans).
    public var kuikaeForbidden: Set<Kind> {
        guard kind == .chi || kind == .pon, let taken else { return [] }
        return meld.kuikaeForbidden(took: taken.kind)
    }
}
