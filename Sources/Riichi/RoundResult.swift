// How a round ended, and who pays whom (Docs/Design/engine.md §4.3).

/// One winner of a round.
public struct Win: Hashable, Sendable {
    public let winner: Seat
    /// The discarder or kan seat for a ron; the winner for a tsumo.
    public let from: Seat
    public let tile: Tile
    public var isTsumo: Bool { from == winner }
    /// The hand as `score` values it (the ordinary payment, with this winner's
    /// honba). Pao redistribution is in `deltas`, not here.
    public let scored: Scored
    /// Dora indicators shown at the win.
    public let doraIndicators: [Tile]
    /// Ura indicators shown: empty for a winner not in riichi.
    public let uraIndicators: [Tile]
    /// This win's point changes by seat, including the sticks for the first winner.
    public let deltas: [Int]
    /// The liable seat, if pao applied to this win (including a ron from the liable
    /// seat itself, which is paid as an ordinary ron).
    public let liable: Seat?
    /// Set when the win robbed a kan (chankan, or kokushi robbing a closed kan).
    public let robbedKan: KanKind?
}

public struct RoundResult: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        /// In turn order from the discarder (one entry for a tsumo).
        case wins([Win])
        /// Seats tenpai for payment, and seats paid nagashi mangan, ascending.
        case exhaustiveDraw(tenpai: [Seat], nagashi: [Seat])
        case abortiveDraw(AbortReason)
    }

    public let outcome: Outcome
    /// Score changes over the whole round, by seat: riichi sticks paid in, win or
    /// draw payments, sticks collected. `sum(deltas) + 1000 × (sticks change) == 0`.
    public let deltas: [Int]
    /// Scores after the round (before any end-of-game award of leftover sticks).
    public let scores: [Int]
    /// Sticks left on the table.
    public let sticks: Int
    public let dealer: Seat
    public let dealerRepeats: Bool

    public var wins: [Win] {
        if case .wins(let w) = outcome { w } else { [] }
    }

    /// The honba count of the next hand (design §5 step 2): reset only after a win
    /// with no dealer among the winners.
    public func nextHonba(after honba: Int) -> Int {
        if case .wins(let w) = outcome, !w.contains(where: { $0.winner == dealer }) { return 0 }
        return honba + 1
    }
}
