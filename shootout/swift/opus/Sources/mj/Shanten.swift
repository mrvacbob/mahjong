// Shanten (structural: tile availability is ignored) and waits.

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

    func shifted(_ ds: Int, _ dt: Int, _ dp: Int) -> ShapeStates {
        var out = ShapeStates()
        forEach { s, t, p in if p + dp <= 1 { out.insert(s + ds, t + dt, p + dp) } }
        return out
    }
}

/// Memoised per-suit search. One instance lives for the whole run.
final class ShantenCalculator {
    private var memo: [Int: ShapeStates] = [:]

    /// Every reachable shape state for one suit's counts (9 kinds, or 7 honors).
    private func states(_ a: inout [Int], runs: Bool) -> ShapeStates {
        guard let i = a.firstIndex(where: { $0 > 0 }) else { return .empty }
        let key = a.reduce(runs ? 1 : 2) { $0 * 5 + $1 }
        if let hit = memo[key] { return hit }

        var out = ShapeStates()
        func take(_ removed: [Int], _ ds: Int, _ dt: Int, _ dp: Int) {
            for j in removed { a[j] -= 1 }
            out.formUnion(states(&a, runs: runs).shifted(ds, dt, dp))
            for j in removed { a[j] += 1 }
        }
        let c = a[i]
        if c >= 3 { take([i, i, i], 1, 0, 0) }
        if c >= 2 { take([i, i], 0, 0, 1); take([i, i], 0, 1, 0) }
        if runs {
            let has1 = i + 1 < a.count && a[i + 1] > 0
            let has2 = i + 2 < a.count && a[i + 2] > 0
            if has1 && has2 { take([i, i + 1, i + 2], 1, 0, 0) }
            if has1 { take([i, i + 1], 0, 1, 0) }
            if has2 { take([i, i + 2], 0, 1, 0) }
        }
        take([i], 0, 0, 0)  // leave this tile isolated
        memo[key] = out
        return out
    }

    /// 8 - 2*sets - partials - pair, with sets + partials <= 4.
    func standard(_ counts: Counts, meldCount: Int) -> Int {
        var acc = ShapeStates()
        acc.insert(meldCount, 0, 0)
        for suit in Suit.allCases {
            let lo = suit.rawValue * 9
            var slice = Array(counts.n[lo..<(lo + (suit == .honor ? 7 : 9))])
            acc = acc.combined(with: states(&slice, runs: suit != .honor))
        }
        var best = 8
        acc.forEach { s, t, p in best = min(best, 8 - 2 * s - min(t, 4 - s) - p) }
        return best
    }
}

func chiitoiShanten(_ counts: Counts) -> Int {
    let pairs = counts.n.filter { $0 >= 2 }.count
    let kinds = counts.n.filter { $0 >= 1 }.count
    return 6 - pairs + max(0, 7 - kinds)
}

func kokushiShanten(_ counts: Counts) -> Int {
    let present = Kind.yaochu.filter { counts[$0] >= 1 }
    let hasPair = present.contains { counts[$0] >= 2 }
    return 13 - present.count - (hasPair ? 1 : 0)
}

struct ShantenResult {
    let standard: Int
    let chiitoi: Int?   // nil when the hand has melds
    let kokushi: Int?
    var min: Int { [standard, chiitoi ?? 99, kokushi ?? 99].min()! }
}

extension ShantenCalculator {
    func shanten(_ counts: Counts, meldCount: Int) -> ShantenResult {
        ShantenResult(
            standard: standard(counts, meldCount: meldCount),
            chiitoi: meldCount == 0 ? chiitoiShanten(counts) : nil,
            kokushi: meldCount == 0 ? kokushiShanten(counts) : nil)
    }

    /// Kinds whose draw lowers `min` shanten, ignoring availability.
    func structuralWaits(_ counts: Counts, meldCount: Int) -> [Kind] {
        let now = shanten(counts, meldCount: meldCount).min
        return Kind.all.filter { shanten(counts.adding($0), meldCount: meldCount).min < now }
    }

    /// The `waits` op: kinds that lower shanten and have a copy outside hand and melds.
    func waits(_ counts: Counts, melds: [Meld]) -> (shanten: Int, tiles: [Kind], count: Int) {
        var visible = counts
        for t in melds.flatMap(\.tiles) { visible[t.kind] += 1 }
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
}
