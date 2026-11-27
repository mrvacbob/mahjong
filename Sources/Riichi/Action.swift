// What a seat may do, and the phases of a round (docs/design/engine.md §4).

/// One decision. Red fives make calls distinct: a pon of 5m using `0m 5m` and one
/// using `5m 5m` are two actions. The two tiles of `pon` and `chi` are the ones from
/// the caller's hand, in canonical order.
public enum Action: Hashable, Sendable, CustomStringConvertible {
    /// Discard `tile`; `tsumogiri` when it is the tile just drawn.
    case discard(Tile, tsumogiri: Bool)
    /// Declare riichi; the discard follows as a separate action.
    case riichi
    case tsumo
    /// Closed kan of four tiles of this kind.
    case ankan(Kind)
    /// Add this tile to a pon (shouminkan).
    case kakan(Tile)
    /// Nine terminals and honors on the first draw.
    case kyuushu
    case ron
    case pon(Tile, Tile)
    case daiminkan
    case chi(Tile, Tile)
    case pass

    /// A plain, stable text form: `discard:5m`, `tsumogiri:5m`, `pon:05m`, `ankan:1z`.
    public var description: String {
        switch self {
        case .discard(let t, let tg): "\(tg ? "tsumogiri" : "discard"):\(t)"
        case .riichi: "riichi"
        case .tsumo: "tsumo"
        case .ankan(let k): "ankan:\(k)"
        case .kakan(let t): "kakan:\(t)"
        case .kyuushu: "kyuushu"
        case .ron: "ron"
        case .pon(let a, let b): "pon:\(mpsz([a, b]))"
        case .daiminkan: "daiminkan"
        case .chi(let a, let b): "chi:\(mpsz([a, b]))"
        case .pass: "pass"
        }
    }
}

/// How the seat to act came to have the turn.
public enum TurnStart: Hashable, Sendable {
    /// Drew from the live wall.
    case draw
    /// Drew a replacement tile after a kan.
    case replacementDraw
    /// Made a chi or pon and must discard (no drawn tile).
    case call
    /// Declared riichi and must make the riichi discard.
    case riichiDeclared
}

/// A discard that has opened a window.
public struct Discard: Hashable, Sendable {
    public let seat: Seat
    public let tile: Tile
    public let tsumogiri: Bool
    /// This discard declares riichi (not yet accepted).
    public let riichi: Bool
}

public enum KanKind: Hashable, Sendable {
    case closed, added
}

/// A closed or added kan that has been announced and may be robbed.
public struct PendingKan: Hashable, Sendable {
    public let seat: Seat
    /// The kan's tile: the added tile, or a tile of the closed kan's kind.
    public let tile: Tile
    public let kind: KanKind
}

public enum Phase: Sendable {
    /// This seat must act (`apply`).
    case turn(Seat, TurnStart)
    /// One or more other seats may ron, pon, kan, chi or pass (`resolve`).
    case reactions(Discard)
    /// One or more other seats may ron the kan or pass (`resolve`).
    case robbing(PendingKan)
    case ended(RoundResult)
}

/// One optional answer per seat, for `resolve`. A fixed four-slot value.
public struct Answers: Sendable, Hashable {
    private var a0, a1, a2, a3: Action?

    public init() {}

    public subscript(seat: Seat) -> Action? {
        get {
            switch seat.index {
            case 0: a0
            case 1: a1
            case 2: a2
            default: a3
            }
        }
        set {
            switch seat.index {
            case 0: a0 = newValue
            case 1: a1 = newValue
            case 2: a2 = newValue
            default: a3 = newValue
            }
        }
    }
}

/// Why `apply` or `resolve` refused. The state is unchanged.
public enum RoundError: Error, Sendable, Hashable {
    /// The round is not in a phase where this call makes sense (e.g. `apply` during
    /// a window, or after the end).
    case wrongPhase
    /// This seat has no decision to make now.
    case notYourTurn(Seat)
    /// The action is not in `legalActions(for:)`.
    case illegal(Seat, Action)
    /// A seat that must answer the window gave no answer.
    case missingAnswer(Seat)
}
