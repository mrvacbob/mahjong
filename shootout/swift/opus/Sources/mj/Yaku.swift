// Yaku and yakuman, declared one per row of spec/rules.md section 2.

enum YakuName: String {
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
    let multiple: Int
    let applies: @Sendable (Reading) -> Bool

    init(_ name: YakuName, _ multiple: Int, _ applies: @escaping @Sendable (Reading) -> Bool) {
        self.name = name; self.multiple = multiple; self.applies = applies
    }
}

let yakuList: [Yaku] = [
    Yaku(.riichi, closed: 1, open: nil) { $0.context.flags.contains(.riichi) },
    Yaku(.double_riichi, closed: 2, open: nil) { $0.context.flags.contains(.double_riichi) },
    Yaku(.ippatsu, closed: 1, open: nil) { $0.context.flags.contains(.ippatsu) },
    Yaku(.tsumo, closed: 1, open: nil) { $0.context.tsumo },
    Yaku(.pinfu, closed: 1, open: nil) { $0.isPinfuShape },
    Yaku(.tanyao, closed: 1, open: 1) { $0.allKinds.allSatisfy(\.isSimple) },
    Yaku(.iipeikou, closed: 1, open: nil) { $0.identicalRunPairs == 1 },
    Yaku(.yakuhai_haku, closed: 1, open: 1) { $0.hasTriplet(.haku) },
    Yaku(.yakuhai_hatsu, closed: 1, open: 1) { $0.hasTriplet(.hatsu) },
    Yaku(.yakuhai_chun, closed: 1, open: 1) { $0.hasTriplet(.chun) },
    Yaku(.yakuhai_seat, closed: 1, open: 1) { $0.hasTriplet($0.context.seat.kind) },
    Yaku(.yakuhai_round, closed: 1, open: 1) { $0.hasTriplet($0.context.round.kind) },
    Yaku(.rinshan, closed: 1, open: 1) { $0.context.flags.contains(.rinshan) },
    Yaku(.chankan, closed: 1, open: 1) { $0.context.flags.contains(.chankan) },
    Yaku(.haitei, closed: 1, open: 1) { $0.context.flags.contains(.haitei) },
    Yaku(.houtei, closed: 1, open: 1) { $0.context.flags.contains(.houtei) },
    Yaku(.sanshoku, closed: 2, open: 1) { $0.hasSanshokuRuns },
    Yaku(.sanshoku_doukou, closed: 2, open: 2) { $0.hasSanshokuTriplets },
    Yaku(.sanankou, closed: 2, open: 2) { $0.concealedTriplets == 3 },
    Yaku(.ittsu, closed: 2, open: 1) { $0.hasIttsu },
    Yaku(.chiitoi, closed: 2, open: nil) {
        if case .chiitoi = $0.shape { return true } else { return false }
    },
    Yaku(.toitoi, closed: 2, open: 2) { $0.isStandard && $0.triplets.count == 4 },
    Yaku(.chanta, closed: 2, open: 1) { r in
        r.hasHonor && r.allGroupsContain(\.hasYaochu, pair: \.isYaochu)
    },
    Yaku(.sankantsu, closed: 2, open: 2) { $0.kans == 3 },
    Yaku(.honroutou, closed: 2, open: 2) { $0.allKinds.allSatisfy(\.isYaochu) },
    Yaku(.shousangen, closed: 2, open: 2) { r in
        r.triplets.filter(\.isDragon).count == 2 && r.pair?.isDragon == true
    },
    Yaku(.honitsu, closed: 3, open: 2) { $0.hasHonor && $0.suits.count == 2 },
    Yaku(.junchan, closed: 3, open: 2) { r in
        !r.hasHonor && r.allGroupsContain(\.hasTerminal, pair: \.isTerminal)
    },
    Yaku(.ryanpeikou, closed: 3, open: nil) { $0.identicalRunPairs == 2 },
    Yaku(.chinitsu, closed: 6, open: 5) { !$0.hasHonor && $0.suits.count == 1 },
]

/// The 13 tiles before the win are exactly 1112345678999 of one suit.
private func isPureNineGates(_ c: Counts, suit: Suit) -> Bool {
    let pattern = [3, 1, 1, 1, 1, 1, 1, 1, 3]
    return c.total == 13 && (1...9).allSatisfy { c[Kind(suit, $0)] == pattern[$0 - 1] }
}

/// 1112345678999 plus one more of the same suit, all concealed, no kan.
private func isNineGates(_ r: Reading) -> Bool {
    guard r.noMelds, r.suits.count == 1, let suit = r.suits.first, suit != .honor else {
        return false
    }
    let need = [3, 1, 1, 1, 1, 1, 1, 1, 3]
    return (1...9).allSatisfy { r.concealed[Kind(suit, $0)] >= need[$0 - 1] }
}

private func isKokushiShape(_ r: Reading) -> Bool {
    if case .kokushi = r.shape { return true } else { return false }
}

/// Before the win, the hand held one of each of the 13 terminals and honors.
private func isThirteenWait(_ r: Reading) -> Bool {
    Kind.yaochu.allSatisfy { r.waiting[$0] == 1 }
}

let yakumanList: [Yakuman] = [
    Yakuman(.kokushi, 1) { r in isKokushiShape(r) && !isThirteenWait(r) },
    Yakuman(.kokushi_13, 2) { r in isKokushiShape(r) && isThirteenWait(r) },
    Yakuman(.suuankou, 1) { $0.concealedTriplets == 4 && $0.wait != .tanki },
    Yakuman(.suuankou_tanki, 2) { $0.concealedTriplets == 4 && $0.wait == .tanki },
    Yakuman(.daisangen, 1) { $0.triplets.filter(\.isDragon).count == 3 },
    Yakuman(.shousuushii, 1) { r in
        r.triplets.filter(\.isWind).count == 3 && r.pair?.isWind == true
    },
    Yakuman(.daisuushii, 2) { $0.triplets.filter(\.isWind).count == 4 },
    Yakuman(.tsuuiisou, 1) { $0.allKinds.allSatisfy(\.isHonor) },
    Yakuman(.chinroutou, 1) { $0.allKinds.allSatisfy(\.isTerminal) },
    Yakuman(.ryuuiisou, 1) { $0.allKinds.allSatisfy(\.isGreen) },
    Yakuman(.chuuren, 1) { r in
        isNineGates(r) && !isPureNineGates(r.waiting, suit: r.winKind.suit)
    },
    Yakuman(.junsei_chuuren, 2) { r in
        isNineGates(r) && isPureNineGates(r.waiting, suit: r.winKind.suit)
    },
    Yakuman(.suukantsu, 1) { $0.kans == 4 },
    Yakuman(.tenhou, 1) { $0.context.flags.contains(.tenhou) },
    Yakuman(.chiihou, 1) { $0.context.flags.contains(.chiihou) },
]

/// The ordinary yaku of a reading, with the rules' "does not stack" exclusions.
func ordinaryYaku(_ r: Reading) -> [(YakuName, Int)] {
    var found = yakuList.compactMap { y in y.han(r).map { (y.name, $0) } }
    if found.contains(where: { $0.0 == .ryanpeikou }) {
        found.removeAll { $0.0 == .iipeikou }
    }
    return found
}

func yakumanOf(_ r: Reading) -> [(YakuName, Int)] {
    yakumanList.filter { $0.applies(r) }.map { ($0.name, $0.multiple) }
}
