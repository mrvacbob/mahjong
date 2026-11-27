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

/// One seat's player. The driver hands it every event it may see, one at a time and
/// in order. When the seat must decide, the event that asks it (the prompt: its
/// draw, its call, its riichi declaration, the discard or the announced kan it may
/// claim; `PlayerView.prompt(in:)`) comes with the seat's view, and once the step's
/// remaining events (an owed dora indicator at most) are delivered the driver asks
/// for the decision.
protocol Player {
    mutating func receive(_ event: MaskedEvent, prompt: PlayerView?)
    /// The decision the last prompt asked for; it must be in `view.legalActions`.
    mutating func decision(_ view: PlayerView) -> Action?
    /// Bad replies substituted so far (mjai bots only).
    var substitutions: Substitutions { get }
    mutating func finish()
}

extension Player {
    mutating func receive(_ event: MaskedEvent, prompt: PlayerView?) {}
    var substitutions: Substitutions { Substitutions() }
    mutating func finish() {}
}

/// Why a bot's reply was replaced, counted (design §6: the illegal-move rate).
/// `unbound` counts replies other than `none` to an event that asked the bot
/// nothing: they answer no decision, so nothing was played for them.
struct Substitutions: Sendable {
    var malformed = 0, illegal = 0, timeout = 0, crashed = 0, unbound = 0
    var total: Int { malformed + illegal + timeout + crashed + unbound }
    static func + (a: Substitutions, b: Substitutions) -> Substitutions {
        Substitutions(malformed: a.malformed + b.malformed, illegal: a.illegal + b.illegal,
                      timeout: a.timeout + b.timeout, crashed: a.crashed + b.crashed,
                      unbound: a.unbound + b.unbound)
    }
    var text: String {
        "malformed=\(malformed) illegal=\(illegal) timeout=\(timeout) crashed=\(crashed) unbound=\(unbound)"
    }
}

enum BotKind: String {
    case random, eager
}

struct BuiltinBot: Player {
    let kind: BotKind
    var rng: BotRNG

    mutating func decision(_ view: PlayerView) -> Action? {
        kind == .random ? random(view) : eager(view)
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

    mutating func decision(_ view: PlayerView) -> Action? { queue.next(for: seat) }
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
