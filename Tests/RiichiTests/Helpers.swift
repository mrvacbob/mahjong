@testable import Riichi

/// Tiles from mpsz text, e.g. `t("123m0p")`.
func t(_ text: String) -> [Tile] { parseTiles(Substring(text))! }
/// One tile.
func t1(_ text: String) -> Tile { Tile(Substring(text))! }
/// Melds from the `melds=` form.
func melds(_ text: String) -> [Meld] { parseMelds(Substring(text))! }

/// `score` as the line protocol would ask it; returns the scored hand or the error.
func scored(hand: String, melds m: String = "-", win: String, tsumo: Bool, seat: Wind = .south,
            flags: Set<Flag> = [], rules: Rules) -> Result<Scored, ScoreError> {
    let req = ScoreRequest(hand: t(hand), melds: melds(m), win: t1(win),
                           context: WinContext(seat: seat, tsumo: tsumo, flags: flags))
    return Result { () throws(ScoreError) in try score(req, rules: rules) }
}

extension Result where Success == Scored {
    var yaku: String? { (try? get())?.yakuText }
    var total: Int? { (try? get())?.payment.total }
    var value: Scored.Value? { (try? get())?.value }
    var error: Failure? { if case .failure(let e) = self { e } else { nil } }
}
