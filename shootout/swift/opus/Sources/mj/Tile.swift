// Tiles, kinds, melds and the mpsz notation.

enum Suit: Int, CaseIterable, Comparable {
    case man, pin, sou, honor

    var letter: Character { ["m", "p", "s", "z"][rawValue] }

    init?(letter: Character) {
        switch letter {
        case "m": self = .man
        case "p": self = .pin
        case "s": self = .sou
        case "z": self = .honor
        default: return nil
        }
    }

    static func < (a: Suit, b: Suit) -> Bool { a.rawValue < b.rawValue }
}

/// A tile kind, ignoring red. Index 0..<34: m 0-8, p 9-17, s 18-26, z 27-33.
struct Kind: Hashable, Comparable, CustomStringConvertible {
    let index: Int

    init(_ index: Int) { self.index = index }
    init(_ suit: Suit, _ number: Int) { index = suit.rawValue * 9 + number - 1 }

    static let all = (0..<34).map(Kind.init)
    static let count = 34

    var suit: Suit { Suit(rawValue: index / 9)! }
    /// 1-9 for suits, 1-7 for honors (E S W N haku hatsu chun).
    var number: Int { index % 9 + 1 }

    var isHonor: Bool { suit == .honor }
    var isTerminal: Bool { !isHonor && (number == 1 || number == 9) }
    var isYaochu: Bool { isHonor || isTerminal }
    var isSimple: Bool { !isYaochu }
    var isWind: Bool { isHonor && number <= 4 }
    var isDragon: Bool { isHonor && number >= 5 }
    var isGreen: Bool {
        (suit == .sou && [2, 3, 4, 6, 8].contains(number)) || self == .hatsu
    }

    static let haku = Kind(.honor, 5), hatsu = Kind(.honor, 6), chun = Kind(.honor, 7)
    static let yaochu = all.filter(\.isYaochu)

    /// The kind `offset` steps up in the same suit, if it exists (for runs).
    func shifted(_ offset: Int) -> Kind? {
        guard !isHonor, (1...9).contains(number + offset) else { return nil }
        return Kind(index + offset)
    }

    /// The dora this kind indicates.
    var doraSuccessor: Kind {
        switch suit {
        case .honor where isWind: return Kind(.honor, number % 4 + 1)
        case .honor: return Kind(.honor, (number - 5 + 1) % 3 + 5)
        default: return Kind(suit, number % 9 + 1)
        }
    }

    static func < (a: Kind, b: Kind) -> Bool { a.index < b.index }
    var description: String { "\(number)\(suit.letter)" }
}

enum Wind: Int {
    case east = 1, south, west, north
    init?(letter: Substring) {
        switch letter {
        case "E": self = .east
        case "S": self = .south
        case "W": self = .west
        case "N": self = .north
        default: return nil
        }
    }
    var kind: Kind { Kind(.honor, rawValue) }
}

/// A physical tile: a kind, possibly the red five.
struct Tile: Hashable, Comparable, CustomStringConvertible {
    let kind: Kind
    let isRed: Bool

    init(_ kind: Kind, red: Bool = false) { self.kind = kind; isRed = red }

    /// Sort key: within a suit ascending, 0 just before 5.
    private var sortKey: Int { kind.index * 2 + (isRed ? 0 : 1) }
    static func < (a: Tile, b: Tile) -> Bool { a.sortKey < b.sortKey }

    var digit: Character { isRed ? "0" : Character(String(kind.number)) }
    var description: String { "\(digit)\(kind.suit.letter)" }

    init?(_ text: Substring) {
        guard let tiles = parseTiles(text), tiles.count == 1 else { return nil }
        self = tiles[0]
    }
}

/// Parses "123m406p77z" (or "-") into tiles in the given order.
func parseTiles(_ text: Substring) -> [Tile]? {
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

/// Canonical tile-list text ("-" for empty).
func format(_ tiles: [Tile]) -> String {
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

func format(kinds: [Kind]) -> String { format(kinds.map { Tile($0) }) }

/// A histogram of kinds, the working representation for shape searches.
struct Counts: Hashable {
    var n: [Int]

    init() { n = Array(repeating: 0, count: Kind.count) }
    init<S: Sequence>(_ kinds: S) where S.Element == Kind {
        self.init()
        for k in kinds { n[k.index] += 1 }
    }
    init(_ tiles: [Tile]) { self.init(tiles.map(\.kind)) }

    subscript(k: Kind) -> Int {
        get { n[k.index] }
        set { n[k.index] = newValue }
    }
    var total: Int { n.reduce(0, +) }
    var kinds: [Kind] { Kind.all.filter { n[$0.index] > 0 } }

    func adding(_ k: Kind) -> Counts { var c = self; c[k] += 1; return c }
    func removing(_ k: Kind) -> Counts { var c = self; c[k] -= 1; return c }
}

enum MeldKind: Character {
    case chi = "c", pon = "p", daiminkan = "k", shouminkan = "s", ankan = "a"
}

struct Meld {
    let kind: MeldKind
    let tiles: [Tile]

    var isOpen: Bool { kind != .ankan }
    var isKan: Bool { tiles.count == 4 }
    var isChi: Bool { kind == .chi }
    /// The lowest kind (first tile of a run, the kind of a triplet or kan).
    var base: Kind { tiles.map(\.kind).min()! }

    init?(_ text: Substring) {
        guard let letter = text.first, let k = MeldKind(rawValue: letter),
              let tiles = parseTiles(text.dropFirst()) else { return nil }
        let kinds = tiles.map(\.kind).sorted()
        switch k {
        case .chi:
            guard tiles.count == 3, kinds[0].shifted(1) == kinds[1], kinds[0].shifted(2) == kinds[2]
            else { return nil }
        case .pon:
            guard tiles.count == 3, Set(kinds).count == 1 else { return nil }
        case .daiminkan, .shouminkan, .ankan:
            guard tiles.count == 4, Set(kinds).count == 1 else { return nil }
        }
        kind = k
        self.tiles = tiles
    }
}

func parseMelds(_ text: Substring) -> [Meld]? {
    if text == "-" { return [] }
    var out: [Meld] = []
    for part in text.split(separator: ",") {
        guard let m = Meld(part) else { return nil }
        out.append(m)
    }
    return out
}
