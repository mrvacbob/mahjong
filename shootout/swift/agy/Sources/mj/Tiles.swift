import Foundation

enum Suit: UInt8, CaseIterable, Comparable, Hashable, Sendable {
    case man = 0
    case pin = 1
    case sou = 2
    case honor = 3

    static func < (lhs: Suit, rhs: Suit) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var char: Character {
        switch self {
        case .man: return "m"
        case .pin: return "p"
        case .sou: return "s"
        case .honor: return "z"
        }
    }

    var isNumbered: Bool {
        self != .honor
    }

    var baseOffset: UInt8 {
        rawValue * 9
    }

    init?(char: Character) {
        switch char {
        case "m": self = .man
        case "p": self = .pin
        case "s": self = .sou
        case "z": self = .honor
        default: return nil
        }
    }
}

enum Wind: UInt8, CaseIterable, Hashable, Sendable {
    case east = 0
    case south = 1
    case west = 2
    case north = 3

    var tileKind: TileKind {
        TileKind(rawValue: 27 + rawValue)!
    }

    init?(string: Substring) {
        switch string {
        case "E": self = .east
        case "S": self = .south
        case "W": self = .west
        case "N": self = .north
        default: return nil
        }
    }
}

/// One of the 34 canonical tile kinds (ignoring red-five status).
/// 0...8: 1m...9m, 9...17: 1p...9p, 18...26: 1s...9s, 27...30: E/S/W/N, 31...33: haku/hatsu/chun.
struct TileKind: RawRepresentable, Comparable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UInt8

    init?(rawValue: UInt8) {
        guard rawValue < 34 else { return nil }
        self.rawValue = rawValue
    }

    init(unchecked rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init?(suit: Suit, rank: UInt8) {
        if suit == .honor {
            guard rank >= 1 && rank <= 7 else { return nil }
            self.rawValue = 27 + (rank - 1)
        } else {
            guard rank >= 1 && rank <= 9 else { return nil }
            self.rawValue = suit.baseOffset + (rank - 1)
        }
    }

    static let all: [TileKind] = (0..<UInt8(34)).map { TileKind(unchecked: $0) }
    static let yaochuKinds: [TileKind] = [
        0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33
    ].map { TileKind(unchecked: $0) }

    static let haku = TileKind(unchecked: 31)
    static let hatsu = TileKind(unchecked: 32)
    static let chun = TileKind(unchecked: 33)

    static func < (lhs: TileKind, rhs: TileKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var index: Int { Int(rawValue) }

    var suit: Suit {
        Suit(rawValue: rawValue / 9)!
    }

    /// 1...9 for numbered suits, 1...7 for honors.
    var rank: UInt8 {
        (rawValue % 9) + 1
    }

    var isHonor: Bool { rawValue >= 27 }
    var isWind: Bool { rawValue >= 27 && rawValue <= 30 }
    var isDragon: Bool { rawValue >= 31 }
    var isTerminal: Bool { !isHonor && (rank == 1 || rank == 9) }
    var isYaochu: Bool { isHonor || isTerminal }
    var isSimple: Bool { !isYaochu }

    /// 2s, 3s, 4s, 6s, 8s, 6z (hatsu)
    var isGreen: Bool {
        switch rawValue {
        case 19, 20, 21, 23, 25, 32: return true
        default: return false
        }
    }

    /// The dora tile indicated by this tile kind.
    var doraNext: TileKind {
        if rawValue < 27 {
            let base = (rawValue / 9) * 9
            let nextRank = (rawValue - base + 1) % 9
            return TileKind(unchecked: base + nextRank)
        } else if rawValue <= 30 {
            return TileKind(unchecked: 27 + ((rawValue - 27 + 1) % 4))
        } else {
            return TileKind(unchecked: 31 + ((rawValue - 31 + 1) % 3))
        }
    }

    func offset(_ delta: Int) -> TileKind? {
        guard !isHonor else { return nil }
        let newRank = Int(rank) + delta
        guard newRank >= 1 && newRank <= 9 else { return nil }
        return TileKind(unchecked: UInt8(Int(rawValue) + delta))
    }

    var description: String {
        "\(rank)\(suit.char)"
    }
}

/// An exact tile, distinguishing red fives (`0m`, `0p`, `0s`) from plain fives.
struct Tile: Comparable, Hashable, Sendable, CustomStringConvertible {
    let kind: TileKind
    let isRed: Bool

    init(kind: TileKind, isRed: Bool = false) {
        self.kind = kind
        self.isRed = isRed
    }

    /// Canonical order: kind ascending, with red five (`0`) sorting before plain five (`5`).
    static func < (lhs: Tile, rhs: Tile) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
        return lhs.isRed && !rhs.isRed
    }

    var digitChar: Character {
        if isRed { return "0" }
        return Character(UnicodeScalar(UInt8(ascii: "0") + kind.rank))
    }

    var description: String {
        "\(digitChar)\(kind.suit.char)"
    }

    static func parse(_ s: Substring) -> Tile? {
        guard s.count == 2 else { return nil }
        let d = s.first!
        let sc = s.last!
        guard let suit = Suit(char: sc) else { return nil }
        if d == "0" {
            guard suit.isNumbered, let k = TileKind(suit: suit, rank: 5) else { return nil }
            return Tile(kind: k, isRed: true)
        }
        guard let ascii = d.asciiValue, ascii >= UInt8(ascii: "1"), ascii <= UInt8(ascii: "9") else { return nil }
        let rank = ascii - UInt8(ascii: "0")
        guard let k = TileKind(suit: suit, rank: rank) else { return nil }
        return Tile(kind: k, isRed: false)
    }
}

/// Fixed-size 34-slot multiset of tile kinds (stack allocated via InlineArray).
struct TileCounts: Equatable, Hashable, Sendable {
    var data: InlineArray<34, UInt8>

    init() {
        self.data = InlineArray(repeating: 0)
    }

    subscript(kind: TileKind) -> UInt8 {
        get { data[kind.index] }
        set { data[kind.index] = newValue }
    }

    subscript(index: Int) -> UInt8 {
        get { data[index] }
        set { data[index] = newValue }
    }

    var total: Int {
        var sum = 0
        for i in 0..<34 { sum += Int(data[i]) }
        return sum
    }

    var distinctKinds: Int {
        var count = 0
        for i in 0..<34 where data[i] > 0 { count += 1 }
        return count
    }

    static func == (lhs: TileCounts, rhs: TileCounts) -> Bool {
        for i in 0..<34 {
            if lhs.data[i] != rhs.data[i] { return false }
        }
        return true
    }

    func hash(into hasher: inout Hasher) {
        for i in 0..<34 {
            hasher.combine(data[i])
        }
    }

    mutating func add(_ kind: TileKind, count: UInt8 = 1) {
        data[kind.index] &+= count
    }

    mutating func remove(_ kind: TileKind, count: UInt8 = 1) {
        data[kind.index] &-= count
    }
}

/// Exact multiset of tiles, preserving red-five presence (at most one red five per suit).
struct HandTiles: Equatable, Sendable {
    var counts: TileCounts
    var redMask: UInt8 // bit 0: 0m, bit 1: 0p, bit 2: 0s

    init(counts: TileCounts = TileCounts(), redMask: UInt8 = 0) {
        self.counts = counts
        self.redMask = redMask
    }

    init(tiles: [Tile]) {
        self.counts = TileCounts()
        self.redMask = 0
        for t in tiles {
            add(t)
        }
    }

    func hasRed(suit: Suit) -> Bool {
        guard suit.isNumbered else { return false }
        return (redMask & (1 << suit.rawValue)) != 0
    }

    mutating func add(_ tile: Tile) {
        counts.add(tile.kind)
        if tile.isRed {
            redMask |= (1 << tile.kind.suit.rawValue)
        }
    }

    mutating func remove(_ tile: Tile) {
        counts.remove(tile.kind)
        if tile.isRed {
            redMask &= ~(1 << tile.kind.suit.rawValue)
        }
    }

    func plainCount(of kind: TileKind) -> Int {
        let total = Int(counts[kind])
        if !kind.isHonor && kind.rank == 5 && hasRed(suit: kind.suit) {
            return total - 1
        }
        return total
    }

    var akaCount: Int {
        redMask.nonzeroBitCount
    }

    /// Distinct exact tiles present in canonical order.
    func distinctTiles() -> [Tile] {
        var result: [Tile] = []
        result.reserveCapacity(14)
        for i in 0..<34 {
            let c = counts[i]
            if c == 0 { continue }
            let kind = TileKind(unchecked: UInt8(i))
            if !kind.isHonor && kind.rank == 5 && hasRed(suit: kind.suit) {
                result.append(Tile(kind: kind, isRed: true))
                if c > 1 {
                    result.append(Tile(kind: kind, isRed: false))
                }
            } else {
                result.append(Tile(kind: kind, isRed: false))
            }
        }
        return result
    }
}

enum MeldKind: UInt8, Equatable, Hashable, Sendable {
    case chi
    case pon
    case daiminkan
    case shouminkan
    case ankan

    var prefix: Character {
        switch self {
        case .chi: return "c"
        case .pon: return "p"
        case .daiminkan: return "k"
        case .shouminkan: return "s"
        case .ankan: return "a"
        }
    }

    init?(prefix: Character) {
        switch prefix {
        case "c": self = .chi
        case "p": self = .pon
        case "k": self = .daiminkan
        case "s": self = .shouminkan
        case "a": self = .ankan
        default: return nil
        }
    }
}

struct Meld: Equatable, Hashable, Sendable {
    let kind: MeldKind
    let baseKind: TileKind
    let tiles: [Tile]

    var isOpen: Bool { kind != .ankan }
    var isClosed: Bool { kind == .ankan }
    var isKan: Bool { kind == .daiminkan || kind == .shouminkan || kind == .ankan }
    var isSequence: Bool { kind == .chi }
    var isTripletOrKan: Bool { kind != .chi }
    var akaCount: Int { tiles.reduce(0) { $0 + ($1.isRed ? 1 : 0) } }

    static func parse(_ s: Substring) -> Meld? {
        guard let first = s.first, let kind = MeldKind(prefix: first) else { return nil }
        guard let tiles = TileFormat.parseTileList(s.dropFirst()) else { return nil }
        guard !tiles.isEmpty else { return nil }
        let sorted = tiles.sorted()
        let base = sorted.first!.kind
        return Meld(kind: kind, baseKind: base, tiles: sorted)
    }
}

/// Concealed decomposition unit for `agari` and `score`.
/// Raw values encode the spec's tie-break order: pair < sequence < triplet.
enum GroupKind: UInt8, Comparable, Hashable, Sendable {
    case pair = 0
    case sequence = 1
    case triplet = 2

    static func < (lhs: GroupKind, rhs: GroupKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Group: Comparable, Hashable, Sendable, CustomStringConvertible {
    let kind: GroupKind
    let base: TileKind

    static func < (lhs: Group, rhs: Group) -> Bool {
        if lhs.base != rhs.base { return lhs.base < rhs.base }
        return lhs.kind < rhs.kind
    }

    var description: String {
        let r = base.rank
        let sc = base.suit.char
        switch kind {
        case .pair:
            return "\(r)\(r)\(sc)"
        case .sequence:
            return "\(r)\(r + 1)\(r + 2)\(sc)"
        case .triplet:
            return "\(r)\(r)\(r)\(sc)"
        }
    }
}

enum TileFormat {
    static func parseTileList(_ s: Substring) -> [Tile]? {
        if s == "-" { return [] }
        var tiles: [Tile] = []
        var pendingDigits: [Character] = []
        for ch in s {
            if ch >= "0" && ch <= "9" {
                pendingDigits.append(ch)
            } else if let suit = Suit(char: ch) {
                guard !pendingDigits.isEmpty else { return nil }
                for d in pendingDigits {
                    if d == "0" {
                        guard suit.isNumbered, let k = TileKind(suit: suit, rank: 5) else { return nil }
                        tiles.append(Tile(kind: k, isRed: true))
                    } else {
                        let rank = d.asciiValue! - UInt8(ascii: "0")
                        guard let k = TileKind(suit: suit, rank: rank) else { return nil }
                        tiles.append(Tile(kind: k, isRed: false))
                    }
                }
                pendingDigits.removeAll(keepingCapacity: true)
            } else {
                return nil
            }
        }
        guard pendingDigits.isEmpty else { return nil }
        return tiles
    }

    static func parseMelds(_ s: Substring) -> [Meld]? {
        if s == "-" { return [] }
        var melds: [Meld] = []
        for part in s.split(separator: ",", omittingEmptySubsequences: false) {
            guard let m = Meld.parse(part) else { return nil }
            melds.append(m)
        }
        return melds
    }

    static func formatTileList(_ tiles: [Tile]) -> String {
        if tiles.isEmpty { return "-" }
        let sorted = tiles.sorted()
        var out = ""
        var currentSuit: Suit? = nil
        for t in sorted {
            if let cs = currentSuit, cs != t.kind.suit {
                out.append(cs.char)
            }
            out.append(t.digitChar)
            currentSuit = t.kind.suit
        }
        if let cs = currentSuit {
            out.append(cs.char)
        }
        return out
    }

    static func formatTileKinds(_ kinds: [TileKind]) -> String {
        if kinds.isEmpty { return "-" }
        let sorted = kinds.sorted()
        var out = ""
        var currentSuit: Suit? = nil
        for k in sorted {
            if let cs = currentSuit, cs != k.suit {
                out.append(cs.char)
            }
            out.append(Character(UnicodeScalar(UInt8(ascii: "0") + k.rank)))
            currentSuit = k.suit
        }
        if let cs = currentSuit {
            out.append(cs.char)
        }
        return out
    }
}
