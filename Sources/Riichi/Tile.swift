// Tiles, kinds, counts, melds and the mpsz notation.

public enum Suit: Int, CaseIterable, Sendable {
    case man, pin, sou, honor

    public var letter: Character { ["m", "p", "s", "z"][rawValue] }

    public init?(letter: Character) {
        switch letter {
        case "m": self = .man
        case "p": self = .pin
        case "s": self = .sou
        case "z": self = .honor
        default: return nil
        }
    }

    /// Kinds in this suit: 9, or 7 for honors.
    public var size: Int { self == .honor ? 7 : 9 }
}

/// A tile kind, ignoring red. Index 0..<34: m 0-8, p 9-17, s 18-26, z 27-33.
public struct Kind: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let index: Int

    public init(_ index: Int) {
        precondition((0..<Kind.count).contains(index), "kind index out of range")
        self.index = index
    }
    /// `number` is 1-9 for suits, 1-7 for honors (E S W N haku hatsu chun).
    public init(_ suit: Suit, _ number: Int) {
        precondition((1...suit.size).contains(number), "kind number out of range for its suit")
        self.init(suit.rawValue * 9 + number - 1)
    }

    public static let all = (0..<34).map(Kind.init)
    public static let count = 34

    public var suit: Suit { Suit(rawValue: index / 9)! }
    /// 1-9 for suits, 1-7 for honors (E S W N haku hatsu chun).
    public var number: Int { index % 9 + 1 }

    public var isHonor: Bool { index >= 27 }
    public var isTerminal: Bool { !isHonor && (number == 1 || number == 9) }
    public var isYaochu: Bool { isHonor || isTerminal }
    public var isSimple: Bool { !isYaochu }
    public var isWind: Bool { isHonor && number <= 4 }
    public var isDragon: Bool { isHonor && number >= 5 }
    public var isGreen: Bool {
        (suit == .sou && [2, 3, 4, 6, 8].contains(number)) || self == .hatsu
    }

    public static let haku = Kind(.honor, 5), hatsu = Kind(.honor, 6), chun = Kind(.honor, 7)
    public static let yaochu = all.filter(\.isYaochu)

    /// The kind `offset` steps up in the same suit, if it exists (for runs).
    public func shifted(_ offset: Int) -> Kind? {
        guard !isHonor, (1...9).contains(number + offset) else { return nil }
        return Kind(index + offset)
    }
    /// The run that starts at this kind (which must be 1-7 of a suit).
    var run: [Kind] { [self, shifted(1)!, shifted(2)!] }

    /// The dora this kind indicates.
    public var doraSuccessor: Kind {
        switch suit {
        case .honor where isWind: return Kind(.honor, number % 4 + 1)
        case .honor: return Kind(.honor, (number - 5 + 1) % 3 + 5)
        default: return Kind(suit, number % 9 + 1)
        }
    }

    public static func < (a: Kind, b: Kind) -> Bool { a.index < b.index }
    public var description: String { "\(number)\(suit.letter)" }
}

public enum Wind: Int, CaseIterable, Sendable {
    case east = 1, south, west, north

    public init?(letter: Substring) {
        switch letter {
        case "E": self = .east
        case "S": self = .south
        case "W": self = .west
        case "N": self = .north
        default: return nil
        }
    }
    public var kind: Kind { Kind(.honor, rawValue) }
    /// The wind after this one (north wraps to east).
    public var next: Wind { Wind(rawValue: rawValue % 4 + 1)! }
}

/// A physical tile: a kind, possibly the red five.
public struct Tile: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let kind: Kind
    public let isRed: Bool

    /// `red` requires a five of a suit.
    public init(_ kind: Kind, red: Bool = false) {
        precondition(!red || (!kind.isHonor && kind.number == 5), "only a suited five can be red")
        self.kind = kind
        isRed = red
    }

    /// Sort key: within a suit ascending, 0 just before 5.
    private var sortKey: Int { kind.index * 2 + (isRed ? 0 : 1) }
    public static func < (a: Tile, b: Tile) -> Bool { a.sortKey < b.sortKey }

    var digit: Character { isRed ? "0" : Character(String(kind.number)) }
    /// mpsz, e.g. `5m`, `0p`, `7z`.
    public var description: String { "\(digit)\(kind.suit.letter)" }

    /// One tile in mpsz.
    public init?(_ text: Substring) {
        guard let tiles = parseTiles(text), tiles.count == 1 else { return nil }
        self = tiles[0]
    }
}

/// Parses "123m406p77z" (or "-") into tiles in the order written.
public func parseTiles(_ text: Substring) -> [Tile]? {
    if text == "-" { return [] }
    var out: [Tile] = []
    var digits: [Int] = []
    for ch in text {
        if let d = ch.wholeNumberValue {
            digits.append(d)
        } else if let suit = Suit(letter: ch), !digits.isEmpty {
            for d in digits {
                if d == 0 {
                    guard suit != .honor else { return nil }
                    out.append(Tile(Kind(suit, 5), red: true))
                } else {
                    guard suit != .honor || d <= 7 else { return nil }
                    out.append(Tile(Kind(suit, d)))
                }
            }
            digits = []
        } else {
            return nil
        }
    }
    return digits.isEmpty ? out : nil
}

/// Canonical mpsz text of a tile list, sorted ("-" for empty).
public func mpsz(_ tiles: [Tile]) -> String {
    if tiles.isEmpty { return "-" }
    var out = ""
    let sorted = tiles.sorted()
    for (i, t) in sorted.enumerated() {
        out.append(t.digit)
        if i == sorted.count - 1 || sorted[i + 1].kind.suit != t.kind.suit {
            out.append(t.kind.suit.letter)
        }
    }
    return out
}

/// Canonical mpsz text of a kind list (no reds).
public func mpsz(kinds: [Kind]) -> String { mpsz(kinds.map { Tile($0) }) }

extension [Tile] {
    /// This list without one copy of `t` (exact tile).
    func removingOne(_ t: Tile) -> [Tile] {
        var out = self
        if let i = out.firstIndex(of: t) { out.remove(at: i) }
        return out
    }
    /// The distinct tiles, in canonical order (deterministic, unlike `Set` order).
    var distinct: [Tile] { Array(Set(self)).sorted() }
}

/// A histogram of kinds, the working representation for shape searches.
///
/// Fixed inline storage: one 64-bit word per suit, four bits per kind (kind number n
/// at bits 4(n-1)..<4n). A count may go up to 15, so a structural fifth copy fits.
public struct Counts: Hashable, Sendable {
    var words: SIMD4<UInt64> = .zero

    public init() {}
    public init<S: Sequence>(_ kinds: S) where S.Element == Kind {
        for k in kinds { self[k] += 1 }
    }
    public init(_ tiles: [Tile]) { self.init(tiles.lazy.map(\.kind)) }

    public subscript(k: Kind) -> Int {
        get { Int(truncatingIfNeeded: words[k.index / 9] >> UInt64(4 * (k.index % 9))) & 0xF }
        set {
            precondition((0...15).contains(newValue), "count out of range")
            let shift = UInt64(4 * (k.index % 9)), s = k.index / 9
            words[s] = words[s] & ~(0xF << shift) | UInt64(newValue) << shift
        }
    }

    /// The packed counts of one suit (see the type's comment).
    func word(_ suit: Suit) -> UInt64 { words[suit.rawValue] }

    public var total: Int { Kind.all.reduce(0) { $0 + self[$1] } }
    /// Kinds with a nonzero count, ascending.
    public var kinds: [Kind] { Kind.all.filter { self[$0] > 0 } }
    /// Number of kinds whose count satisfies `p`.
    public func count(where p: (Int) -> Bool) -> Int { Kind.all.count { p(self[$0]) } }

    public func adding(_ k: Kind) -> Counts { var c = self; c[k] += 1; return c }
    public func removing(_ k: Kind) -> Counts { var c = self; c[k] -= 1; return c }
}

public enum MeldKind: Character, Sendable {
    case chi = "c", pon = "p", daiminkan = "k", shouminkan = "s", ankan = "a"
}

/// A meld as hand analysis sees it: what it is and which tiles. The round keeps
/// `TableMeld`, which also knows where the tiles came from.
public struct Meld: Hashable, Sendable {
    public let kind: MeldKind
    /// In canonical order.
    public let tiles: [Tile]

    public var isOpen: Bool { kind != .ankan }
    public var isKan: Bool { tiles.count == 4 }
    /// The lowest kind (first tile of a run, the kind of a triplet or kan).
    public var base: Kind { tiles[0].kind }

    /// Validated: a chi is a run of three in one suit, a pon three of a kind, a kan
    /// four of a kind, and at most one red five.
    public init?(kind: MeldKind, tiles: [Tile]) {
        let tiles = tiles.sorted()
        let kinds = tiles.map(\.kind)
        guard tiles.count(where: \.isRed) <= 1 else { return nil }
        switch kind {
        case .chi:
            guard tiles.count == 3, kinds[0].shifted(2) != nil, kinds == kinds[0].run else { return nil }
        case .pon:
            guard tiles.count == 3, Set(kinds).count == 1 else { return nil }
        case .daiminkan, .shouminkan, .ankan:
            guard tiles.count == 4, Set(kinds).count == 1 else { return nil }
        }
        self.kind = kind
        self.tiles = tiles
    }

    /// Parses the `melds=` form of one meld, e.g. `c345m`, `a2222m`.
    public init?(_ text: Substring) {
        guard let letter = text.first, let k = MeldKind(rawValue: letter),
              let tiles = parseTiles(text.dropFirst()) else { return nil }
        self.init(kind: k, tiles: tiles)
    }

    /// Kinds that may not be discarded right after making this chi or pon by
    /// taking `took` (kuikae). Red and plain fives are the same kind. Empty for a
    /// kan, which is followed by a replacement draw. `took` must be in the meld.
    public func kuikaeForbidden(took: Kind) -> Set<Kind> {
        guard kind == .chi || kind == .pon else { return [] }
        var fromHand = tiles.map(\.kind)
        guard let i = fromHand.firstIndex(of: took) else {
            preconditionFailure("kuikaeForbidden: the taken kind \(took) is not in the meld")
        }
        var out: Set<Kind> = [took]
        guard kind == .chi else { return out }
        fromHand.remove(at: i)
        if fromHand[0].shifted(1) == fromHand[1] {
            // Took one end of a run whose other two tiles are adjacent: the far end too.
            if took < fromHand[0], let far = fromHand[1].shifted(1) { out.insert(far) }
            if took > fromHand[1], let far = fromHand[0].shifted(-1) { out.insert(far) }
        }
        return out
    }
}

/// Parses the `melds=` list (comma-separated, or `-`).
public func parseMelds(_ text: Substring) -> [Meld]? {
    if text == "-" { return [] }
    var out: [Meld] = []
    for part in text.split(separator: ",") {
        guard let m = Meld(part) else { return nil }
        out.append(m)
    }
    return out
}

extension [Meld] {
    /// No open melds (an ankan keeps the hand closed).
    public var isClosed: Bool { allSatisfy { !$0.isOpen } }
    public var tiles: [Tile] { flatMap(\.tiles) }
}
