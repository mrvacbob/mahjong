// The wall: 136 tiles in a fixed layout, and the seeded shuffle of Spec/wall.md.

/// SplitMix64 (Steele, Lea and Flood), used only to seed `Xoshiro256StarStar`.
struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// xoshiro256** 1.0 (Blackman and Vigna).
struct Xoshiro256StarStar {
    var s: (UInt64, UInt64, UInt64, UInt64)

    init(seeding seed: UInt64) {
        var sm = SplitMix64(state: seed)
        s = (sm.next(), sm.next(), sm.next(), sm.next())
    }

    private static func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 { x << k | x >> (64 - k) }

    mutating func next() -> UInt64 {
        let result = Self.rotl(s.1 &* 5, 7) &* 9
        let t = s.1 << 17
        s.2 ^= s.0
        s.3 ^= s.1
        s.1 ^= s.2
        s.0 ^= s.3
        s.2 ^= t
        s.3 = Self.rotl(s.3, 45)
        return result
    }

    /// Uniform in `0..<bound` (bound > 0), by rejecting the `2^64 mod bound` lowest
    /// outputs and reducing the rest modulo `bound`.
    mutating func next(below bound: UInt64) -> UInt64 {
        let threshold = (0 &- bound) % bound
        while true {
            let r = next()
            if r >= threshold { return r % bound }
        }
    }
}

/// The 136 tiles of one hand, in the order they are used:
///
/// - `0..<52`: the deal. Tiles `4i..<4i+4` (i in 0..<12) go to the seat `i % 4`
///   places after the dealer, then tile `48 + j` to the seat `j` places after the
///   dealer. So the dealer's 13 are indices 0–3, 16–19, 32–35 and 48.
/// - `52..<122`: the 70 live draws, in order.
/// - `122..<126`: the four replacement tiles, in the order drawn.
/// - `126..<131`: the dora indicators, in the order revealed.
/// - `131..<136`: the ura indicators matching them.
public struct Wall: Sendable, Hashable {
    public static let count = 136
    public static let liveDraws = 70
    public static let replacements = 4
    public static let indicators = 5

    public let tiles: [Tile]

    /// The exact 136-tile set in canonical order: four of each kind, and for each
    /// suit's five one red and three plain. The shuffle starts from this order.
    public static let sorted: [Tile] = Kind.all.flatMap { k -> [Tile] in
        let fives = !k.isHonor && k.number == 5
        return (0..<4).map { Tile(k, red: fives && $0 == 0) }
    }

    /// Validated: `tiles` must be exactly the 136-tile set, in any order.
    public init?(tiles: [Tile]) {
        guard tiles.count == Wall.count, tiles.sorted() == Wall.sorted else { return nil }
        self.tiles = tiles
    }

    /// The seeded wall for the hand numbered `hand` (the count of hands dealt so far
    /// in this game, from 0). `Spec/wall.md` gives the algorithm and test vectors.
    public init(seed: UInt64, hand: Int) {
        precondition(hand >= 0, "hand number must be non-negative")
        var rng = Xoshiro256StarStar(seeding: Wall.key(seed: seed, hand: hand))
        var t = Wall.sorted
        for i in stride(from: t.count - 1, to: 0, by: -1) {
            let j = Int(rng.next(below: UInt64(i + 1)))
            t.swapAt(i, j)
        }
        tiles = t
    }

    /// The generator key of Spec/wall.md §2: `mix(seed) ^ mix(~hand)`, where `mix`
    /// is one SplitMix64 output step from that state.
    static func key(seed: UInt64, hand: Int) -> UInt64 {
        var a = SplitMix64(state: seed), b = SplitMix64(state: ~UInt64(hand))
        return a.next() ^ b.next()
    }

    /// The 13 tiles dealt to the seat `offset` places after the dealer (0 = dealer),
    /// in the order dealt.
    public func dealt(toDealerOffset offset: Int) -> [Tile] {
        precondition((0..<4).contains(offset), "dealer offset out of range")
        var out: [Tile] = []
        for round in 0..<3 {
            let start = 16 * round + 4 * offset
            out += tiles[start..<start + 4]
        }
        out.append(tiles[48 + offset])
        return out
    }

    /// The 13 tiles dealt to `seat` when `dealer` deals.
    public func dealt(to seat: Seat, dealer: Seat) -> [Tile] {
        dealt(toDealerOffset: seat.distance(from: dealer))
    }

    /// The `i`th live draw (0 is the dealer's first draw).
    public func liveDraw(_ i: Int) -> Tile {
        precondition((0..<Wall.liveDraws).contains(i)); return tiles[52 + i]
    }
    /// The `i`th replacement tile drawn after a kan.
    public func replacement(_ i: Int) -> Tile {
        precondition((0..<Wall.replacements).contains(i)); return tiles[122 + i]
    }
    /// The `i`th dora indicator (0 is shown at the start).
    public func doraIndicator(_ i: Int) -> Tile {
        precondition((0..<Wall.indicators).contains(i)); return tiles[126 + i]
    }
    /// The ura indicator under the `i`th dora indicator.
    public func uraIndicator(_ i: Int) -> Tile {
        precondition((0..<Wall.indicators).contains(i)); return tiles[131 + i]
    }
}
