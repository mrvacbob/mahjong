// Checking values that come from outside the library (Docs/Design/engine.md §2.1).
//
// Every public entry point that takes such a value (a ruleset, a starting position,
// a score request, text) checks it and returns an error; `precondition` is kept for
// the engine's own invariants and for typed index accessors (`Seat(_:)`,
// `Kind(_:)`, `Wall.liveDraw(_:)`, `Counts` subscripts), which, like `Array`'s
// subscript, are given only checked values by every decoder in the library.

/// A value the engine cannot take: which one, and why.
public struct InputError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The field or argument, e.g. `honba`, `rules.uma`.
    public let field: String
    public let reason: String

    public init(_ field: String, _ reason: String) {
        self.field = field
        self.reason = reason
    }

    public var description: String { "\(field): \(reason)" }
}

/// Whether `tiles` can all be on one table at once: at most four of a kind and at
/// most one red five per suit.
public func isPossibleTileSet(_ tiles: [Tile]) -> Bool {
    var kinds = [Int](repeating: 0, count: Kind.count)
    var reds = [false, false, false]
    for t in tiles {
        kinds[t.kind.index] += 1
        if kinds[t.kind.index] > 4 { return false }
        if t.isRed {
            if reds[t.kind.suit.rawValue] { return false }
            reds[t.kind.suit.rawValue] = true
        }
    }
    return true
}

extension Seat {
    /// The seat with this index, or nil outside 0..<4.
    public init?(checked index: Int) {
        guard (0..<4).contains(index) else { return nil }
        self.init(index)
    }
}

extension Kind {
    /// The kind with this index, or nil outside 0..<34.
    public init?(checked index: Int) {
        guard (0..<Kind.count).contains(index) else { return nil }
        self.init(index)
    }
    /// The kind of this suit and number, or nil if the suit has no such number.
    public init?(checked suit: Suit, _ number: Int) {
        guard (1...suit.size).contains(number) else { return nil }
        self.init(suit, number)
    }
}
