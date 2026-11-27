// Players for the drivers: built-in random and eager bots, which see only a
// `PlayerView` (design §1 goal 3), and the interface the mjai adapter also fills.

import Riichi

/// SplitMix64, for bot decisions (not the wall, which has its own generator).
struct BotRNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
}

/// One seat's player. The driver hands it every event it may see, in order, and
/// with the last event of each step the seat's view if it must decide then.
protocol Player {
    /// Returns the decision when `view` is given (it must be in
    /// `view.legalActions`), else nil.
    mutating func receive(_ events: [MaskedEvent], view: PlayerView?) -> Action?
    /// Bad replies substituted so far (mjai bots only).
    var substitutions: Substitutions { get }
    mutating func finish()
}

extension Player {
    var substitutions: Substitutions { Substitutions() }
    mutating func finish() {}
}

/// Why a bot's reply was replaced, counted (design §6: the illegal-move rate).
struct Substitutions: Sendable {
    var malformed = 0, illegal = 0, timeout = 0, crashed = 0
    var total: Int { malformed + illegal + timeout + crashed }
    static func + (a: Substitutions, b: Substitutions) -> Substitutions {
        Substitutions(malformed: a.malformed + b.malformed, illegal: a.illegal + b.illegal,
                      timeout: a.timeout + b.timeout, crashed: a.crashed + b.crashed)
    }
    var text: String { "malformed=\(malformed) illegal=\(illegal) timeout=\(timeout) crashed=\(crashed)" }
}

enum BotKind: String {
    case random, eager
}

struct BuiltinBot: Player {
    let kind: BotKind
    var rng: BotRNG

    mutating func receive(_ events: [MaskedEvent], view: PlayerView?) -> Action? {
        guard let view else { return nil }
        return kind == .random ? random(view) : eager(view)
    }

    mutating func random(_ v: PlayerView) -> Action {
        v.legalActions[rng.below(v.legalActions.count)]
    }

    /// Shanten of the seat's tiles after discarding `t`.
    static func shantenAfter(_ v: PlayerView, removing t: Tile) -> Int {
        var tiles = v.table.hand
        if let d = v.table.drawn { tiles.append(d) }
        if let i = tiles.firstIndex(of: t) { tiles.remove(at: i) }
        return shanten(Counts(tiles), meldCount: v.table.melds[v.seat.index].count).min
    }

    /// Always wins (but passes a ron one time in ten), declares riichi when legal,
    /// calls or kans with probability 60%, nine terminals half the time, and
    /// otherwise discards to the lowest shanten.
    mutating func eager(_ v: PlayerView) -> Action {
        let legal = v.legalActions
        if legal.contains(.tsumo) { return .tsumo }
        if legal.contains(.ron) && !rng.chance(10) { return .ron }
        if legal.contains(.riichi) { return .riichi }
        if legal.contains(.kyuushu) && rng.chance(50) { return .kyuushu }
        let calls = legal.filter {
            switch $0 {
            case .pon, .chi, .daiminkan, .ankan, .kakan: true
            default: false
            }
        }
        if !calls.isEmpty && rng.chance(60) { return calls[rng.below(calls.count)] }
        let discards = legal.filter { if case .discard = $0 { true } else { false } }
        if discards.isEmpty { return legal.contains(.pass) ? .pass : legal[rng.below(legal.count)] }
        let scored = discards.map { a -> (Action, Int) in
            guard case .discard(let t, _) = a else { return (a, 99) }
            return (a, Self.shantenAfter(v, removing: t))
        }
        let best = scored.map(\.1).min()!
        let top = scored.filter { $0.1 == best }.map(\.0)
        return top[rng.below(top.count)]
    }
}

/// Plays a recorded trace back: the decisions in order.
struct TracePlayer: Player {
    let seat: Seat
    var queue: Decisions

    mutating func receive(_ events: [MaskedEvent], view: PlayerView?) -> Action? {
        guard view != nil else { return nil }
        return queue.next(for: seat)
    }
}

/// A trace's decisions, shared by the four `TracePlayer`s.
final class Decisions {
    var items: [(Seat, Action)]
    var i = 0
    var mismatch: String?
    init(_ items: [(Seat, Action)]) { self.items = items }
    func next(for seat: Seat) -> Action? {
        guard i < items.count else { mismatch = mismatch ?? "trace ended early"; return nil }
        let (s, a) = items[i]
        guard s == seat else { mismatch = mismatch ?? "decision \(i + 1) is for seat \(s), not \(seat)"; return nil }
        i += 1
        return a
    }
}
