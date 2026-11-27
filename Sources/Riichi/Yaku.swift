// Yaku and yakuman, declared one per row of spec/rules.md section 2.

public enum YakuName: String, Sendable {
    case riichi, double_riichi, ippatsu, tsumo, pinfu, tanyao, iipeikou
    case yakuhai_haku, yakuhai_hatsu, yakuhai_chun, yakuhai_seat, yakuhai_round
    case haitei, houtei, rinshan, chankan, chiitoi, toitoi, sanankou, sanshoku
    case sanshoku_doukou, ittsu, chanta, honroutou, shousangen, sankantsu, honitsu
    case junchan, ryanpeikou, chinitsu
    // yakuman
    case kokushi, kokushi_13, suuankou, suuankou_tanki, daisangen, shousuushii
    case daisuushii, tsuuiisou, chinroutou, ryuuiisou, chuuren, junsei_chuuren
    case suukantsu, tenhou, chiihou
}

struct Yaku: Sendable {
    let name: YakuName
    /// Han when closed, and when open (nil: closed only).
    let closed: Int
    let open: Int?
    let applies: @Sendable (Reading) -> Bool

    init(_ name: YakuName, closed: Int, open: Int?, _ applies: @escaping @Sendable (Reading) -> Bool) {
        self.name = name; self.closed = closed; self.open = open; self.applies = applies
    }

    func han(_ r: Reading) -> Int? {
        guard let han = r.menzen ? closed : open, applies(r) else { return nil }
        return han
    }
}

struct Yakuman: Sendable {
    let name: YakuName
    /// One of the hands `Rules.doubleYakuman` counts twice.
    let isDouble: Bool
    let applies: @Sendable (Reading) -> Bool

    init(_ name: YakuName, double: Bool = false,
         _ applies: @escaping @Sendable (Reading) -> Bool) {
        self.name = name; isDouble = double; self.applies = applies
    }

    func multiple(_ rules: Rules) -> Int { isDouble && rules.doubleYakuman ? 2 : 1 }
}

let yakuList: [Yaku] = [
    Yaku(.riichi, closed: 1, open: nil) { $0.context.flags.contains(.riichi) },
    Yaku(.double_riichi, closed: 2, open: nil) { $0.context.flags.contains(.double_riichi) },
    Yaku(.ippatsu, closed: 1, open: nil) { $0.context.flags.contains(.ippatsu) },
    Yaku(.tsumo, closed: 1, open: nil) { $0.context.tsumo },
    Yaku(.pinfu, closed: 1, open: nil) { $0.isPinfuShape },
    Yaku(.tanyao, closed: 1, open: 1) { r in
        (r.menzen || r.rules.kuitan) && r.allKinds.allSatisfy(\.isSimple)
    },
    Yaku(.iipeikou, closed: 1, open: nil) { $0.identicalRunPairs == 1 },
    Yaku(.yakuhai_haku, closed: 1, open: 1) { $0.triplets.contains(.haku) },
    Yaku(.yakuhai_hatsu, closed: 1, open: 1) { $0.triplets.contains(.hatsu) },
    Yaku(.yakuhai_chun, closed: 1, open: 1) { $0.triplets.contains(.chun) },
    Yaku(.yakuhai_seat, closed: 1, open: 1) { $0.triplets.contains($0.context.seat.kind) },
    Yaku(.yakuhai_round, closed: 1, open: 1) { $0.triplets.contains($0.context.round.kind) },
    Yaku(.rinshan, closed: 1, open: 1) { $0.context.flags.contains(.rinshan) },
    Yaku(.chankan, closed: 1, open: 1) { $0.context.flags.contains(.chankan) },
    Yaku(.haitei, closed: 1, open: 1) { $0.context.flags.contains(.haitei) },
    Yaku(.houtei, closed: 1, open: 1) { $0.context.flags.contains(.houtei) },
    Yaku(.sanshoku, closed: 2, open: 1) { $0.hasSanshokuRuns },
    Yaku(.sanshoku_doukou, closed: 2, open: 2) { $0.hasSanshokuTriplets },
    Yaku(.sanankou, closed: 2, open: 2) { $0.concealedTriplets == 3 },
    Yaku(.ittsu, closed: 2, open: 1) { $0.hasIttsu },
    Yaku(.chiitoi, closed: 2, open: nil) { $0.shape == .chiitoi },
    Yaku(.toitoi, closed: 2, open: 2) { $0.triplets.count == 4 },
    Yaku(.chanta, closed: 2, open: 1) { r in
        r.hasHonor && r.allGroupsContain(\.hasYaochu, pair: \.isYaochu)
    },
    Yaku(.sankantsu, closed: 2, open: 2) { $0.kans == 3 },
    Yaku(.honroutou, closed: 2, open: 2) { $0.allKinds.allSatisfy(\.isYaochu) },
    Yaku(.shousangen, closed: 2, open: 2) { r in
        r.triplets.count(where: \.isDragon) == 2 && r.pair?.isDragon == true
    },
    Yaku(.honitsu, closed: 3, open: 2) { $0.hasHonor && $0.suits.count == 2 },
    Yaku(.junchan, closed: 3, open: 2) { r in
        !r.hasHonor && r.allGroupsContain(\.hasTerminal, pair: \.isTerminal)
    },
    Yaku(.ryanpeikou, closed: 3, open: nil) { $0.identicalRunPairs == 2 },
    Yaku(.chinitsu, closed: 6, open: 5) { !$0.hasHonor && $0.suits.count == 1 },
]

/// Nine gates: 1112345678999 of one suit.
private let nineGates = [3, 1, 1, 1, 1, 1, 1, 1, 3]

/// The suit of a closed one-suit hand holding at least 1112345678999 (14 tiles, no kan).
private func nineGatesSuit(_ r: Reading) -> Suit? {
    guard r.melds.isEmpty, r.suits.count == 1, let suit = r.suits.first, suit != .honor,
          (1...9).allSatisfy({ r.concealed[Kind(suit, $0)] >= nineGates[$0 - 1] })
    else { return nil }
    return suit
}

/// Junsei: before the win the hand was exactly 1112345678999 (a nine-sided wait).
private func isPureNineGates(_ r: Reading, _ suit: Suit) -> Bool {
    (1...9).allSatisfy { r.waiting[Kind(suit, $0)] == nineGates[$0 - 1] }
}

/// Before the win, the hand held one of each of the 13 terminals and honors.
private func isThirteenWait(_ r: Reading) -> Bool {
    Kind.yaochu.allSatisfy { r.waiting[$0] == 1 }
}

let yakumanList: [Yakuman] = [
    Yakuman(.kokushi) { $0.shape == .kokushi && !isThirteenWait($0) },
    Yakuman(.kokushi_13, double: true) { $0.shape == .kokushi && isThirteenWait($0) },
    Yakuman(.suuankou) { $0.concealedTriplets == 4 && $0.wait != .tanki },
    Yakuman(.suuankou_tanki, double: true) { $0.concealedTriplets == 4 && $0.wait == .tanki },
    Yakuman(.daisangen) { $0.triplets.count(where: \.isDragon) == 3 },
    Yakuman(.shousuushii) { r in
        r.triplets.count(where: \.isWind) == 3 && r.pair?.isWind == true
    },
    Yakuman(.daisuushii, double: true) { $0.triplets.count(where: \.isWind) == 4 },
    Yakuman(.tsuuiisou) { $0.allKinds.allSatisfy(\.isHonor) },
    Yakuman(.chinroutou) { $0.allKinds.allSatisfy(\.isTerminal) },
    Yakuman(.ryuuiisou) { $0.allKinds.allSatisfy(\.isGreen) },
    Yakuman(.chuuren) { r in nineGatesSuit(r).map { !isPureNineGates(r, $0) } ?? false },
    Yakuman(.junsei_chuuren, double: true) { r in nineGatesSuit(r).map { isPureNineGates(r, $0) } ?? false },
    Yakuman(.suukantsu) { $0.kans == 4 },
    Yakuman(.tenhou) { $0.context.flags.contains(.tenhou) },
    Yakuman(.chiihou) { $0.context.flags.contains(.chiihou) },
]

/// The ordinary yaku of a reading. The rules' "does not stack" exclusions are in
/// the predicates (iipeikou vs ryanpeikou, chanta vs junchan, honitsu vs chinitsu).
func ordinaryYaku(_ r: Reading) -> [(name: String, value: Int)] {
    yakuList.compactMap { y in y.han(r).map { (y.name.rawValue, $0) } }
}

func yakumanOf(_ r: Reading) -> [(name: String, value: Int)] {
    yakumanList.filter { $0.applies(r) }.map { ($0.name.rawValue, $0.multiple(r.rules)) }
}
