// Fu, han, payments, and the choice between readings.

struct ScoreRequest {
    var hand: [Tile]          // concealed, excluding the winning tile
    var melds: [Meld]
    var win: Tile
    var context: WinContext
    var dora: [Tile] = []
    var ura: [Tile] = []
    var honba = 0
}

enum ScoreError: Error {
    case notAgari, noYaku
    var text: String { self == .notAgari ? "not_agari" : "no_yaku" }
}

enum Payment {
    case ron(Int)
    case dealerTsumo(Int)                  // each
    case tsumo(nonDealer: Int, dealer: Int)

    var text: String {
        switch self {
        case .ron(let n): "ron:\(n)"
        case .dealerTsumo(let n): "all:\(n)"
        case .tsumo(let nd, let d): "tsumo:\(nd)/\(d)"
        }
    }
    var total: Int {
        switch self {
        case .ron(let n): n
        case .dealerTsumo(let n): 3 * n
        case .tsumo(let nd, let d): 2 * nd + d
        }
    }
}

struct Scored {
    enum Value { case ordinary(han: Int, fu: Int), yakuman(Int) }
    let yaku: [(name: String, value: Int)]
    let value: Value
    let payment: Payment

    var yakuText: String { yaku.map { "\($0.name):\($0.value)" }.joined(separator: ",") }

    var text: String {
        switch value {
        case .ordinary(let han, let fu):
            "yaku=\(yakuText) han=\(han) fu=\(fu) pay=\(payment.text) total=\(payment.total)"
        case .yakuman(let n):
            "yaku=\(yakuText) yakuman=\(n) pay=\(payment.text) total=\(payment.total)"
        }
    }

    /// The spec's preference: total, real yakuman over kazoe, han, fu, then the
    /// yaku list that sorts first.
    func isBetter(than o: Scored) -> Bool {
        func key(_ s: Scored) -> (Int, Int, Int, Int) {
            switch s.value {
            case .yakuman: (s.payment.total, 1, 0, 0)
            case .ordinary(let han, let fu): (s.payment.total, 0, han, fu)
            }
        }
        let (a, b) = (key(self), key(o))
        return a != b ? a > b : yakuText < o.yakuText
    }
}

// MARK: fu

func fu(_ r: Reading) -> Int {
    guard case .standard(let sets, let pair, let wait) = r.shape else { return 25 }
    if r.isPinfuShape { return r.context.tsumo ? 20 : 30 }
    var fu = 20
    if r.menzen && !r.context.tsumo { fu += 10 }
    if r.context.tsumo { fu += 2 }
    for s in sets where s.shape != .run {
        var f = s.shape == .kan ? 8 : 2
        if s.concealed { f *= 2 }
        if s.base.isYaochu { f *= 2 }
        fu += f
    }
    if pair.isDragon { fu += 2 }
    if pair == r.context.seat.kind { fu += 2 }
    if pair == r.context.round.kind { fu += 2 }
    if [.kanchan, .penchan, .tanki].contains(wait) { fu += 2 }
    return max(30, (fu + 9) / 10 * 10)  // open no-fu ron counts 30
}

// MARK: payments

func roundUp100(_ n: Int) -> Int { (n + 99) / 100 * 100 }

func basicPoints(han: Int, fu: Int) -> Int {
    switch han {
    case 13...: return 8000
    case 11...: return 6000
    case 8...: return 4000
    case 6...: return 3000
    case 5: return 2000
    default: return min(2000, fu << (2 + han))
    }
}

func payment(basic: Int, context: WinContext, honba: Int) -> Payment {
    if !context.tsumo {
        return .ron(roundUp100(basic * (context.isDealer ? 6 : 4)) + 300 * honba)
    }
    if context.isDealer { return .dealerTsumo(roundUp100(2 * basic) + 100 * honba) }
    return .tsumo(nonDealer: roundUp100(basic) + 100 * honba,
                  dealer: roundUp100(2 * basic) + 100 * honba)
}

// MARK: scoring a hand

func doraCount(_ tiles: [Tile], indicators: [Tile]) -> Int {
    let dora = indicators.map(\.kind.doraSuccessor)
    return tiles.reduce(0) { n, t in n + dora.filter { $0 == t.kind }.count }
}

func score(_ req: ScoreRequest) throws(ScoreError) -> Scored {
    if req.context.flags.contains(.tenhou) {
        // Any of the dealer's 14 tiles may be the winning tile: score the best.
        let all = req.hand + [req.win]
        var best: Scored?
        var lastError = ScoreError.notAgari
        for t in Set(all) {
            var alt = req
            alt.win = t
            var rest = all
            rest.remove(at: rest.firstIndex(of: t)!)
            alt.hand = rest
            do {
                let s = try scoreWithWinningTile(alt)
                if best.map({ s.isBetter(than: $0) }) ?? true { best = s }
            } catch {
                lastError = error
            }
        }
        if let best { return best }
        throw lastError
    }
    return try scoreWithWinningTile(req)
}

private func scoreWithWinningTile(_ req: ScoreRequest) throws(ScoreError) -> Scored {
    let concealed = Counts(req.hand + [req.win])
    let all = readings(concealed: concealed, win: req.win.kind, melds: req.melds,
                       context: req.context)
    if all.isEmpty { throw .notAgari }

    let tiles = req.hand + [req.win] + req.melds.flatMap(\.tiles)
    let flags = req.context.flags
    let dora = doraCount(tiles, indicators: req.dora)
    let aka = tiles.filter(\.isRed).count
    let ura = flags.contains(.riichi) || flags.contains(.double_riichi)
        ? doraCount(tiles, indicators: req.ura) : 0

    var best: Scored?
    for r in all {
        let s: Scored
        let yakuman = yakumanOf(r)
        if !yakuman.isEmpty {
            let n = yakuman.map(\.1).reduce(0, +)
            s = Scored(yaku: yakuman.map { ($0.0.rawValue, $0.1) }.sorted { $0.name < $1.name },
                       value: .yakuman(n),
                       payment: payment(basic: 8000 * n, context: req.context, honba: req.honba))
        } else {
            let yaku = ordinaryYaku(r)
            if yaku.isEmpty { continue }
            var listed = yaku.map { ($0.0.rawValue, $0.1) }
            for (name, n) in [("dora", dora), ("aka", aka), ("ura", ura)] where n > 0 {
                listed.append((name, n))
            }
            let han = listed.map(\.1).reduce(0, +)
            let f = fu(r)
            s = Scored(yaku: listed.sorted { $0.0 < $1.0 }, value: .ordinary(han: han, fu: f),
                       payment: payment(basic: basicPoints(han: han, fu: f),
                                        context: req.context, honba: req.honba))
        }
        if best.map({ s.isBetter(than: $0) }) ?? true { best = s }
    }
    guard let best else { throw .noYaku }
    return best
}
