// Unmasked round events, one per mjai message (docs/design/engine.md §6). The mjai
// JSON codec and the masked per-seat view are package D; this is the Swift value.

public enum AbortReason: String, Hashable, Sendable {
    case kyuushu, suufonRenda = "suufon_renda", suuchaRiichi = "suucha_riichi"
    case suukaikan, sanchahou
}

/// Why a `ryukyoku` happened: the live wall ran out, or an abortive draw.
public enum DrawReason: Hashable, Sendable, CustomStringConvertible {
    case exhaustive
    case abort(AbortReason)

    /// `exhaustive`, or the abort's name (`kyuushu`, `suufon_renda`, ...).
    public var description: String {
        switch self {
        case .exhaustive: "exhaustive"
        case .abort(let r): r.rawValue
        }
    }
}

public enum Event: Hashable, Sendable {
    /// `tehais` in seat order, each sorted.
    case startKyoku(bakaze: Wind, kyoku: Int, honba: Int, kyotaku: Int, oya: Seat,
                    doraMarker: Tile, scores: [Int], tehais: [[Tile]])
    /// A live or replacement draw.
    case tsumo(actor: Seat, tile: Tile)
    case dahai(actor: Seat, tile: Tile, tsumogiri: Bool)
    case chi(actor: Seat, target: Seat, tile: Tile, consumed: [Tile])
    case pon(actor: Seat, target: Seat, tile: Tile, consumed: [Tile])
    case daiminkan(actor: Seat, target: Seat, tile: Tile, consumed: [Tile])
    case ankan(actor: Seat, consumed: [Tile])
    /// `consumed` is the three tiles of the pon; `tile` the one added.
    case kakan(actor: Seat, tile: Tile, consumed: [Tile])
    case dora(marker: Tile)
    case reach(actor: Seat)
    case reachAccepted(actor: Seat, scores: [Int])
    /// `target == actor` for tsumo. `deltas` are this win's point changes (the first
    /// winner's include the sticks); `scores` are the scores after it.
    /// `horaTehais` is the concealed hand without the winning tile. `uraMarkers` is
    /// empty for a winner not in riichi.
    case hora(actor: Seat, target: Seat, tile: Tile, deltas: [Int], uraMarkers: [Tile],
              horaTehais: [Tile], scored: Scored, scores: [Int])
    /// `tenpais` and `tehais` in seat order (`tehais` unmasked here).
    case ryukyoku(reason: DrawReason, deltas: [Int], tenpais: [Bool], tehais: [[Tile]],
                  scores: [Int])
    case endKyoku

    /// The mjai message type.
    public var type: String {
        switch self {
        case .startKyoku: "start_kyoku"
        case .tsumo: "tsumo"
        case .dahai: "dahai"
        case .chi: "chi"
        case .pon: "pon"
        case .daiminkan: "daiminkan"
        case .ankan: "ankan"
        case .kakan: "kakan"
        case .dora: "dora"
        case .reach: "reach"
        case .reachAccepted: "reach_accepted"
        case .hora: "hora"
        case .ryukyoku: "ryukyoku"
        case .endKyoku: "end_kyoku"
        }
    }

    public var actor: Seat? {
        switch self {
        case .tsumo(let a, _), .dahai(let a, _, _), .chi(let a, _, _, _), .pon(let a, _, _, _),
             .daiminkan(let a, _, _, _), .ankan(let a, _), .kakan(let a, _, _), .reach(let a),
             .reachAccepted(let a, _), .hora(let a, _, _, _, _, _, _, _):
            a
        default: nil
        }
    }

    /// A plain, stable rendering for tests: the type, then in parentheses the actor
    /// (`pon(1)`), the indicator (`dora(9p)`) or the reason (`ryukyoku(exhaustive)`).
    public var text: String {
        switch self {
        case .dora(let m): "dora(\(m))"
        case .ryukyoku(let r, _, _, _, _): "ryukyoku(\(r))"
        default: actor.map { "\(type)(\($0.index))" } ?? type
        }
    }
}
