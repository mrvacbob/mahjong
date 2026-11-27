// Fu, han, payments, and the choice between readings.

public struct ScoreRequest: Sendable {
    /// Concealed tiles, excluding the winning tile.
    public var hand: [Tile]
    public var melds: [Meld]
    public var win: Tile
    public var context: WinContext
    /// Indicators, not dora.
    public var dora: [Tile]
    /// Counted only with riichi or double riichi.
    public var ura: [Tile]
    public var honba: Int

    public init(hand: [Tile], melds: [Meld], win: Tile, context: WinContext,
                dora: [Tile] = [], ura: [Tile] = [], honba: Int = 0) {
        self.hand = hand; self.melds = melds; self.win = win; self.context = context
        self.dora = dora; self.ura = ura; self.honba = honba
    }
}

public enum ScoreError: String, Error, Sendable {
    case notAgari = "not_agari", noYaku = "no_yaku"
    /// The request itself cannot be scored (Codex final finding 3): the rules fail
    /// `Rules.validate()`; the hand, winning tile, melds and indicators are not a
    /// possible tile set (`isPossibleTileSet`); the hand is not 13 − 3 × melds tiles
    /// (at most four melds); honba outside 0...`RoundState.maxRunningHonba`. (The
    /// number of indicators is not checked: `spec/formats.md` leaves it open and
    /// the corpus has a request with eight.)
    case badRules = "bad_rules", impossibleTiles = "impossible_tiles", badHandSize = "bad_hand_size",
         badHonba = "bad_honba"
}

/// What the winner is paid, honba included, riichi sticks not.
public enum Payment: Sendable, Hashable {
    case ron(Int)
    case dealerTsumo(Int)                  // each
    case tsumo(nonDealer: Int, dealer: Int)

    public var total: Int {
        switch self {
        case .ron(let n): n
        case .dealerTsumo(let n): 3 * n
        case .tsumo(let nd, let d): 2 * nd + d
        }
    }
}

/// One line of a scored hand: a yaku, a yakuman, or a dora count.
public struct YakuEntry: Sendable, Hashable, CustomStringConvertible {
    public enum Name: Sendable, Hashable {
        case yaku(YakuName)
        /// Indicator dora, red fives, ura dora: han, but not yaku.
        case dora, aka, ura

        /// The name in `spec/formats.md` (`riichi`, `dora`, `kokushi_13`, ...).
        public var text: String {
            switch self {
            case .yaku(let y): y.rawValue
            case .dora: "dora"
            case .aka: "aka"
            case .ura: "ura"
            }
        }
    }
    public let name: Name
    /// Han for an ordinary yaku or a dora count; the multiple for a yakuman.
    public let value: Int

    public init(_ name: Name, _ value: Int) { self.name = name; self.value = value }
    public init(_ yaku: YakuName, _ value: Int) { self.init(.yaku(yaku), value) }

    /// `name:value`.
    public var description: String { "\(name.text):\(value)" }
}

public struct Scored: Sendable, Hashable {
    public enum Value: Sendable, Hashable { case ordinary(han: Int, fu: Int), yakuman(Int) }
    /// Sorted by name text. Han for ordinary yaku and `dora`/`aka`/`ura`; the
    /// multiple for yakuman.
    public let yaku: [YakuEntry]
    public let value: Value
    public let payment: Payment

    init(yaku: [YakuEntry], value: Value, payment: Payment) {
        self.yaku = yaku.sorted { $0.name.text < $1.name.text }
        self.value = value
        self.payment = payment
    }

    /// `name:value,...`, the `yaku=` text of `spec/formats.md` and the last tie-break.
    public var yakuText: String { yaku.map(\.description).joined(separator: ",") }

    /// The value of the named yaku or yakuman in this hand, if present.
    public func value(of name: YakuName) -> Int? {
        yaku.first { $0.name == .yaku(name) }?.value
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
    for s in sets where s.isTriplet {
        var f = s.shape == .kan ? 8 : 2
        if s.concealed { f *= 2 }
        if s.base.isYaochu { f *= 2 }
        fu += f
    }
    if pair.isDragon { fu += 2 }
    let (seat, round) = (r.context.seat.kind, r.context.round.kind)
    if pair == seat && pair == round {
        fu += r.rules.doubleWindPairFu
    } else if pair == seat || pair == round {
        fu += 2
    }
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

public func doraCount(_ tiles: [Tile], indicators: [Tile]) -> Int {
    let held = Counts(tiles)
    return indicators.reduce(0) { $0 + held[$1.kind.doraSuccessor] }
}

/// The best of several scorings, by the spec's preference.
private func best(_ all: [Scored]) -> Scored? { all.max { $1.isBetter(than: $0) } }

/// Scores a winning hand under `rules`: the best interpretation by the order of
/// `spec/formats.md` (`score`). Checks the request first (`ScoreError`).
public func score(_ req: ScoreRequest, rules: Rules) throws(ScoreError) -> Scored {
    try req.check(rules: rules)
    return try scoreChecked(req, rules: rules)
}

extension ScoreRequest {
    /// What `score` requires of a request (see `ScoreError`).
    func check(rules: Rules) throws(ScoreError) {
        guard rules.isValid else { throw .badRules }
        guard melds.count <= 4, hand.count == 13 - 3 * melds.count else { throw .badHandSize }
        guard (0...RoundState.maxRunningHonba).contains(honba) else { throw .badHonba }
        guard isPossibleTileSet(hand + [win] + melds.tiles + dora + ura) else { throw .impossibleTiles }
    }
}

/// `score` for a request the engine built itself (always valid).
func scoreChecked(_ req: ScoreRequest, rules: Rules) throws(ScoreError) -> Scored {
    guard req.context.flags.contains(.tenhou) && rules.tenhouAnyWinningTile else {
        return try scoreWithWinningTile(req, rules: rules)
    }
    // Any of the dealer's 14 tiles may be the winning tile: score the best.
    let all = req.hand + [req.win]
    var scored: [Scored] = []
    var lastError = ScoreError.notAgari
    for t in all.distinct {
        var alt = req
        alt.win = t
        alt.hand = all.removingOne(t)
        do { scored.append(try scoreWithWinningTile(alt, rules: rules)) } catch { lastError = error }
    }
    guard let top = best(scored) else { throw lastError }
    return top
}

private func scoreWithWinningTile(_ req: ScoreRequest, rules: Rules) throws(ScoreError) -> Scored {
    let concealed = Counts(req.hand + [req.win])
    let all = readings(concealed: concealed, win: req.win.kind, melds: req.melds,
                       context: req.context, rules: rules)
    if all.isEmpty { throw .notAgari }

    let tiles = req.hand + [req.win] + req.melds.tiles
    let flags = req.context.flags
    let dora = doraCount(tiles, indicators: req.dora)
    let aka = tiles.count(where: \.isRed)
    let ura = flags.contains(.riichi) || flags.contains(.double_riichi)
        ? doraCount(tiles, indicators: req.ura) : 0
    func pay(_ basic: Int) -> Payment { payment(basic: basic, context: req.context, honba: req.honba) }

    let scored = all.compactMap { r -> Scored? in
        let yakuman = yakumanOf(r)
        if !yakuman.isEmpty {
            let n = yakuman.map(\.value).reduce(0, +)
            return Scored(yaku: yakuman, value: .yakuman(n), payment: pay(8000 * n))
        }
        let yaku = ordinaryYaku(r)
        if yaku.isEmpty { return nil }
        let extras = [YakuEntry(.dora, dora), YakuEntry(.aka, aka), YakuEntry(.ura, ura)]
        let listed = yaku + extras.filter { $0.value > 0 }
        let han = listed.map(\.value).reduce(0, +)
        let f = fu(r)
        return Scored(yaku: listed, value: .ordinary(han: han, fu: f),
                      payment: pay(basicPoints(han: han, fu: f)))
    }
    guard let top = best(scored) else { throw .noYaku }
    return top
}
