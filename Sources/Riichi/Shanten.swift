// Shanten (structural: tile availability is ignored) and waits.
//
// Thread safety: the per-suit search results live in two immutable tables, built
// once on first use. Swift initialises globals exactly once even under concurrent
// first access, and nothing writes to the tables afterwards, so every function here
// may be called from any number of threads.

/// A set of reachable (sets, partials, pair) states, sets and partials capped at 4,
/// packed as bits of a UInt64: bit s*10 + t*2 + p.
struct ShapeStates {
    var bits: UInt64 = 0

    static func bit(_ s: Int, _ t: Int, _ p: Int) -> UInt64 {
        1 << UInt64(min(s, 4) * 10 + min(t, 4) * 2 + p)
    }
    static let empty = ShapeStates(bits: bit(0, 0, 0))

    mutating func insert(_ s: Int, _ t: Int, _ p: Int) { bits |= Self.bit(s, t, p) }
    mutating func formUnion(_ o: ShapeStates) { bits |= o.bits }

    func forEach(_ body: (Int, Int, Int) -> Void) {
        var b = bits
        while b != 0 {
            let i = b.trailingZeroBitCount
            body(i / 10, (i % 10) / 2, i % 2)
            b &= b - 1
        }
    }

    /// Every state of `self` combined with every state of `o`; at most one pair.
    func combined(with o: ShapeStates) -> ShapeStates {
        var out = ShapeStates()
        forEach { s1, t1, p1 in
            o.forEach { s2, t2, p2 in
                if p1 + p2 <= 1 { out.insert(s1 + s2, t1 + t2, p1 + p2) }
            }
        }
        return out
    }

    /// Bits of the states with s == 4, with t == 4, and with p == 0.
    private static let sFull: UInt64 = 0x3FF << 40
    private static let tFull: UInt64 = (0..<5).reduce(0) { $0 | 0b11 << UInt64($1 * 10 + 8) }
    private static let noPair: UInt64 = (0..<25).reduce(0) { $0 | 1 << UInt64($1 * 2) }

    /// Each state with `ds` sets, `dt` partials and `dp` pairs added (each 0 or 1),
    /// capped as `bit` caps; states that would hold two pairs are dropped.
    func shifted(_ ds: Int, _ dt: Int, _ dp: Int) -> ShapeStates {
        var b = bits
        if ds > 0 { b = (b & ~Self.sFull) << 10 | b & Self.sFull }
        if dt > 0 { b = (b & ~Self.tFull) << 2 | b & Self.tFull }
        if dp > 0 { b = (b & Self.noPair) << 1 }
        return ShapeStates(bits: b)
    }
}

// MARK: per-suit tables

/// Powers of five: a suit's counts as a base-5 number index its table.
private let pow5: [Int] = (0..<10).map { n in (0..<n).reduce(1) { a, _ in a * 5 } }

/// Hands have at most 14 concealed tiles, so only suits of up to 14 tiles are tabled.
private let maxTabled = 14

/// The table index of a packed suit word (`Counts.word`), or nil when some count
/// is above 4 or the suit holds more than `maxTabled` tiles.
@inline(__always)
private func tableIndex(_ word: UInt64, size: Int) -> Int? {
    var index = 0, sum = 0
    for i in 0..<size {
        let c = Int(truncatingIfNeeded: word >> UInt64(4 * i)) & 0xF
        if c > 4 { return nil }
        index += c * pow5[i]
        sum += c
    }
    return sum <= maxTabled ? index : nil
}

/// Every reachable shape state of one suit's counts (`word`, packed as in `Counts`),
/// peeling the lowest kind first. `child(w, d)` supplies the states of a smaller
/// word `w`, whose table index is `d` less than this word's.
@inline(__always)
private func expand(_ word: UInt64, size: Int, runs: Bool,
                    child: (UInt64, Int) -> ShapeStates) -> ShapeStates {
    func count(_ i: Int) -> UInt64 { i < size ? word >> UInt64(4 * i) & 0xF : 0 }
    guard word != 0 else { return .empty }
    let i = word.trailingZeroBitCount / 4
    let one = { (j: Int) -> (UInt64, Int) in (1 << UInt64(4 * j), pow5[j]) }
    let (a, b, c) = (one(i), i + 1 < size ? one(i + 1) : (0, 0), i + 2 < size ? one(i + 2) : (0, 0))

    var out = ShapeStates()
    func take(_ removed: (UInt64, Int), _ ds: Int, _ dt: Int, _ dp: Int) {
        out.formUnion(child(word - removed.0, removed.1).shifted(ds, dt, dp))
    }
    let n = count(i)
    if n >= 3 { take((3 * a.0, 3 * a.1), 1, 0, 0) }
    if n >= 2 { take((2 * a.0, 2 * a.1), 0, 0, 1); take((2 * a.0, 2 * a.1), 0, 1, 0) }
    if runs {
        let has1 = count(i + 1) > 0, has2 = count(i + 2) > 0
        if has1 && has2 { take((a.0 + b.0 + c.0, a.1 + b.1 + c.1), 1, 0, 0) }
        if has1 { take((a.0 + b.0, a.1 + b.1), 0, 1, 0) }
        if has2 { take((a.0 + c.0, a.1 + c.1), 0, 1, 0) }
    }
    take(a, 0, 0, 0)  // leave this tile isolated
    return out
}

/// States for every suit of `size` kinds with counts 0...4 and at most `maxTabled`
/// tiles, indexed by `tableIndex`. Entries for larger suits are left empty.
private func buildTable(size: Int, runs: Bool) -> [UInt64] {
    var table = [UInt64](repeating: 0, count: pow5[size])
    var digits = [Int](repeating: 0, count: size)
    var word: UInt64 = 0, sum = 0
    for index in 0..<pow5[size] {
        if index > 0 {
            // Odometer step in base 5, keeping the packed word and the sum in step.
            var i = 0
            while digits[i] == 4 {
                digits[i] = 0; word &= ~(0xF << UInt64(4 * i)); sum -= 4; i += 1
            }
            digits[i] += 1; word += 1 << UInt64(4 * i); sum += 1
        }
        guard sum <= maxTabled else { continue }
        // Children have fewer tiles, so a smaller index: already filled.
        let states = expand(word, size: size, runs: runs) { _, d in
            ShapeStates(bits: table[index - d])
        }
        table[index] = states.bits
    }
    return table
}

private let suitTable = buildTable(size: 9, runs: true)
private let honorTable = buildTable(size: 7, runs: false)

/// The states of one suit: a table lookup, or (for a structural fifth copy or an
/// oversized input) a search that falls back to the table as soon as it can.
private func suitStates(_ word: UInt64, suit: Suit) -> ShapeStates {
    let runs = suit != .honor
    if let i = tableIndex(word, size: suit.size) {
        return ShapeStates(bits: runs ? suitTable[i] : honorTable[i])
    }
    return expand(word, size: suit.size, runs: runs) { w, _ in suitStates(w, suit: suit) }
}

// MARK: shanten

/// Standard-form shanten: 8 - 2*sets - partials - pair, with sets + partials <= 4.
public func standardShanten(_ counts: Counts, meldCount: Int) -> Int {
    var acc = ShapeStates()
    acc.insert(meldCount, 0, 0)
    for suit in Suit.allCases {
        acc = acc.combined(with: suitStates(counts.word(suit), suit: suit))
    }
    var best = 8
    acc.forEach { s, t, p in best = min(best, 8 - 2 * s - min(t, 4 - s) - p) }
    return best
}

public func chiitoiShanten(_ counts: Counts) -> Int {
    let pairs = counts.count { $0 >= 2 }
    let kinds = counts.count { $0 >= 1 }
    return 6 - pairs + max(0, 7 - kinds)
}

public func kokushiShanten(_ counts: Counts) -> Int {
    let present = Kind.yaochu.filter { counts[$0] >= 1 }
    let hasPair = present.contains { counts[$0] >= 2 }
    return 13 - present.count - (hasPair ? 1 : 0)
}

public struct ShantenResult: Sendable, Hashable {
    public let standard: Int
    /// nil when the hand has melds.
    public let chiitoi: Int?
    public let kokushi: Int?
    public var min: Int { Swift.min(standard, chiitoi ?? standard, kokushi ?? standard) }
}

public func shanten(_ counts: Counts, meldCount: Int) -> ShantenResult {
    ShantenResult(
        standard: standardShanten(counts, meldCount: meldCount),
        chiitoi: meldCount == 0 ? chiitoiShanten(counts) : nil,
        kokushi: meldCount == 0 ? kokushiShanten(counts) : nil)
}

/// The `waits` op: kinds that lower shanten and have a copy outside hand and melds.
public func waits(_ counts: Counts, melds: [Meld]) -> (shanten: Int, tiles: [Kind], count: Int) {
    var visible = counts
    for t in melds.tiles { visible[t.kind] += 1 }
    let now = shanten(counts, meldCount: melds.count).min
    var tiles: [Kind] = []
    var total = 0
    for k in Kind.all where visible[k] < 4 {
        if shanten(counts.adding(k), meldCount: melds.count).min < now {
            tiles.append(k)
            total += 4 - visible[k]
        }
    }
    return (now, tiles, total)
}
