import Foundation

enum WinMethod: String, Sendable {
    case tsumo
    case ron
}

struct ScoreFlags: OptionSet, Sendable {
    let rawValue: UInt16

    static let riichi       = ScoreFlags(rawValue: 1 << 0)
    static let doubleRiichi = ScoreFlags(rawValue: 1 << 1)
    static let ippatsu      = ScoreFlags(rawValue: 1 << 2)
    static let haitei       = ScoreFlags(rawValue: 1 << 3)
    static let houtei       = ScoreFlags(rawValue: 1 << 4)
    static let rinshan      = ScoreFlags(rawValue: 1 << 5)
    static let chankan      = ScoreFlags(rawValue: 1 << 6)
    static let tenhou       = ScoreFlags(rawValue: 1 << 7)
    static let chiihou      = ScoreFlags(rawValue: 1 << 8)
    static let ankanRob     = ScoreFlags(rawValue: 1 << 9)

    var hasAnyRiichi: Bool {
        contains(.riichi) || contains(.doubleRiichi)
    }

    static func parse(_ s: Substring) -> ScoreFlags? {
        if s == "-" { return [] }
        var flags: ScoreFlags = []
        for part in s.split(separator: ",", omittingEmptySubsequences: false) {
            switch part {
            case "riichi": flags.insert(.riichi)
            case "double_riichi": flags.insert(.doubleRiichi)
            case "ippatsu": flags.insert(.ippatsu)
            case "haitei": flags.insert(.haitei)
            case "houtei": flags.insert(.houtei)
            case "rinshan": flags.insert(.rinshan)
            case "chankan": flags.insert(.chankan)
            case "tenhou": flags.insert(.tenhou)
            case "chiihou": flags.insert(.chiihou)
            case "ankan_rob": flags.insert(.ankanRob)
            default: return nil
            }
        }
        return flags
    }
}

struct ScoreRequest: Sendable {
    let hand: HandTiles
    let melds: [Meld]
    let win: Tile
    let by: WinMethod
    let seat: Wind
    let round: Wind
    let dora: [Tile]
    let ura: [Tile]
    let honba: Int
    let flags: ScoreFlags
}

enum WaitType: Sendable {
    case ryanmen
    case shanpon
    case kanchan
    case penchan
    case tanki

    var fu: Int {
        switch self {
        case .ryanmen, .shanpon: return 0
        case .kanchan, .penchan, .tanki: return 2
        }
    }
}

struct ResolvedSet: Sendable {
    enum Kind: Sendable {
        case sequence
        case triplet
        case kan
    }

    let kind: Kind
    let base: TileKind
    let isConcealed: Bool

    var isSequence: Bool { kind == .sequence }
    var isTripletOrKan: Bool { kind != .sequence }
    var isKan: Bool { kind == .kan }

    var hasYaochu: Bool {
        switch kind {
        case .sequence:
            return base.rank == 1 || base.rank == 7
        case .triplet, .kan:
            return base.isYaochu
        }
    }

    var hasHonor: Bool {
        kind != .sequence && base.isHonor
    }

    var fu: Int {
        switch kind {
        case .sequence:
            return 0
        case .triplet:
            let simpleFu = isConcealed ? 4 : 2
            return base.isYaochu ? simpleFu * 2 : simpleFu
        case .kan:
            let simpleFu = isConcealed ? 16 : 8
            return base.isYaochu ? simpleFu * 2 : simpleFu
        }
    }
}

struct HandInterpretation: Sendable {
    enum Shape: Sendable {
        case standard(pair: TileKind, sets: [ResolvedSet], wait: WaitType)
        case chiitoi(pairs: [TileKind])
        case kokushi(is13Wait: Bool)
    }

    let shape: Shape
    let winKind: TileKind
    let isClosed: Bool
    let hasMelds: Bool
    let allCounts: TileCounts

    var isStandard: Bool {
        if case .standard = shape { return true }
        return false
    }

    var isChiitoi: Bool {
        if case .chiitoi = shape { return true }
        return false
    }

    var sets: [ResolvedSet] {
        if case .standard(_, let s, _) = shape { return s }
        return []
    }

    var pair: TileKind? {
        if case .standard(let p, _, _) = shape { return p }
        return nil
    }

    var wait: WaitType? {
        if case .standard(_, _, let w) = shape { return w }
        return nil
    }

    var concealedTripletCount: Int {
        sets.reduce(0) { $0 + ($1.isTripletOrKan && $1.isConcealed ? 1 : 0) }
    }

    var kanCount: Int {
        sets.reduce(0) { $0 + ($1.isKan ? 1 : 0) }
    }

    func hasTripletOrKan(of kind: TileKind) -> Bool {
        sets.contains { $0.isTripletOrKan && $0.base == kind }
    }

    func allTilesSatisfy(_ predicate: (TileKind) -> Bool) -> Bool {
        for i in 0..<34 where allCounts[i] > 0 {
            if !predicate(TileKind(unchecked: UInt8(i))) { return false }
        }
        return true
    }

    var suitPresence: (numberedCount: Int, hasHonor: Bool, singleNumberedSuit: Suit?) {
        var suitsMask: UInt8 = 0
        var hasHonor = false
        for i in 0..<34 where allCounts[i] > 0 {
            let s = TileKind(unchecked: UInt8(i)).suit
            if s == .honor {
                hasHonor = true
            } else {
                suitsMask |= (1 << s.rawValue)
            }
        }
        let count = suitsMask.nonzeroBitCount
        let single: Suit? = (count == 1) ? Suit(rawValue: UInt8(suitsMask.trailingZeroBitCount)) : nil
        return (count, hasHonor, single)
    }

    var sequencePairCount: Int {
        guard isStandard else { return 0 }
        var freq: [TileKind: Int] = [:]
        for s in sets where s.isSequence {
            freq[s.base, default: 0] += 1
        }
        return freq.values.reduce(0) { $0 + $1 / 2 }
    }

    /// Returns `(isChuuren, isJunsei)` for closed 14-tile hands without melds.
    var chuurenStatus: (isChuuren: Bool, isJunsei: Bool) {
        guard !hasMelds, isStandard else { return (false, false) }
        let sp = suitPresence
        guard !sp.hasHonor, let suit = sp.singleNumberedSuit else { return (false, false) }
        let offset = Int(suit.baseOffset)
        var extraRank: UInt8? = nil
        for r in 1...9 {
            let need: UInt8 = (r == 1 || r == 9) ? 3 : 1
            let c = allCounts[offset + (r - 1)]
            if c < need { return (false, false) }
            if c == need + 1 {
                if extraRank != nil { return (false, false) }
                extraRank = UInt8(r)
            } else if c > need + 1 {
                return (false, false)
            }
        }
        guard let extra = extraRank else { return (false, false) }
        return (true, winKind.suit == suit && winKind.rank == extra)
    }
}

struct ScoreContext: Sendable {
    let by: WinMethod
    let seat: Wind
    let round: Wind
    let flags: ScoreFlags
}

struct YakumanRule: Sendable {
    let name: String
    let multiple: Int
    let matches: @Sendable (ScoreContext, HandInterpretation) -> Bool
}

struct YakuRule: Sendable {
    let name: String
    let closedHan: Int
    let openHan: Int // 0 means closed-only
    let matches: @Sendable (ScoreContext, HandInterpretation) -> Bool
}

enum ScoreOutcome: Sendable {
    case notAgari
    case noYaku
    case scored(ScoredHand)
}

struct ScoredHand: Sendable, Comparable {
    let yaku: [(name: String, value: Int)]
    let isYakuman: Bool
    let han: Int
    let fu: Int
    let yakumanMultiple: Int
    let payString: String
    let total: Int
    let yakuString: String

    /// Strict total order where `<` means "worse than", so `max()` picks the best interpretation.
    static func < (lhs: ScoredHand, rhs: ScoredHand) -> Bool {
        if lhs.total != rhs.total { return lhs.total < rhs.total }
        if lhs.isYakuman != rhs.isYakuman { return !lhs.isYakuman && rhs.isYakuman }
        if !lhs.isYakuman {
            if lhs.han != rhs.han { return lhs.han < rhs.han }
            if lhs.fu != rhs.fu { return lhs.fu < rhs.fu }
        }
        // Smaller yaku string wins ties
        return lhs.yakuString > rhs.yakuString
    }

    static func == (lhs: ScoredHand, rhs: ScoredHand) -> Bool {
        lhs.total == rhs.total &&
        lhs.isYakuman == rhs.isYakuman &&
        lhs.han == rhs.han &&
        lhs.fu == rhs.fu &&
        lhs.yakuString == rhs.yakuString
    }
}

enum Scorer {
    static let yakumanRules: [YakumanRule] = [
        YakumanRule(name: "tenhou", multiple: 1) { ctx, _ in
            ctx.flags.contains(.tenhou)
        },
        YakumanRule(name: "chiihou", multiple: 1) { ctx, _ in
            ctx.flags.contains(.chiihou)
        },
        YakumanRule(name: "kokushi", multiple: 1) { _, h in
            if case .kokushi(let is13) = h.shape { return !is13 }
            return false
        },
        YakumanRule(name: "kokushi_13", multiple: 2) { _, h in
            if case .kokushi(let is13) = h.shape { return is13 }
            return false
        },
        YakumanRule(name: "suuankou", multiple: 1) { _, h in
            h.isStandard && h.concealedTripletCount == 4 && h.wait != .tanki
        },
        YakumanRule(name: "suuankou_tanki", multiple: 2) { _, h in
            h.isStandard && h.concealedTripletCount == 4 && h.wait == .tanki
        },
        YakumanRule(name: "daisangen", multiple: 1) { _, h in
            h.isStandard &&
            h.hasTripletOrKan(of: .haku) &&
            h.hasTripletOrKan(of: .hatsu) &&
            h.hasTripletOrKan(of: .chun)
        },
        YakumanRule(name: "shousuushii", multiple: 1) { _, h in
            guard let pair = h.pair, pair.isWind else { return false }
            let windSets = h.sets.filter { $0.isTripletOrKan && $0.base.isWind }.count
            return windSets == 3
        },
        YakumanRule(name: "daisuushii", multiple: 2) { _, h in
            guard h.isStandard else { return false }
            let windSets = h.sets.filter { $0.isTripletOrKan && $0.base.isWind }.count
            return windSets == 4
        },
        YakumanRule(name: "tsuuiisou", multiple: 1) { _, h in
            h.allTilesSatisfy(\.isHonor)
        },
        YakumanRule(name: "chinroutou", multiple: 1) { _, h in
            h.allTilesSatisfy(\.isTerminal)
        },
        YakumanRule(name: "ryuuiisou", multiple: 1) { _, h in
            h.allTilesSatisfy(\.isGreen)
        },
        YakumanRule(name: "chuuren", multiple: 1) { _, h in
            let st = h.chuurenStatus
            return st.isChuuren && !st.isJunsei
        },
        YakumanRule(name: "junsei_chuuren", multiple: 2) { _, h in
            let st = h.chuurenStatus
            return st.isChuuren && st.isJunsei
        },
        YakumanRule(name: "suukantsu", multiple: 1) { _, h in
            h.isStandard && h.kanCount == 4
        },
    ]

    static let yakuRules: [YakuRule] = [
        // Situational
        YakuRule(name: "riichi", closedHan: 1, openHan: 0) { ctx, _ in
            ctx.flags.contains(.riichi) && !ctx.flags.contains(.doubleRiichi)
        },
        YakuRule(name: "double_riichi", closedHan: 2, openHan: 0) { ctx, _ in
            ctx.flags.contains(.doubleRiichi)
        },
        YakuRule(name: "ippatsu", closedHan: 1, openHan: 0) { ctx, _ in
            ctx.flags.contains(.ippatsu)
        },
        YakuRule(name: "tsumo", closedHan: 1, openHan: 0) { ctx, h in
            h.isClosed && ctx.by == .tsumo
        },
        YakuRule(name: "haitei", closedHan: 1, openHan: 1) { ctx, _ in
            ctx.flags.contains(.haitei)
        },
        YakuRule(name: "houtei", closedHan: 1, openHan: 1) { ctx, _ in
            ctx.flags.contains(.houtei)
        },
        YakuRule(name: "rinshan", closedHan: 1, openHan: 1) { ctx, _ in
            ctx.flags.contains(.rinshan)
        },
        YakuRule(name: "chankan", closedHan: 1, openHan: 1) { ctx, _ in
            ctx.flags.contains(.chankan)
        },
        // Shape & Tile Yaku
        YakuRule(name: "pinfu", closedHan: 1, openHan: 0) { ctx, h in
            guard case .standard(let pair, let sets, let wait) = h.shape else { return false }
            guard wait == .ryanmen else { return false }
            guard sets.allSatisfy(\.isSequence) else { return false }
            if pair.isDragon || pair == ctx.seat.tileKind || pair == ctx.round.tileKind {
                return false
            }
            return true
        },
        YakuRule(name: "tanyao", closedHan: 1, openHan: 1) { _, h in
            h.allTilesSatisfy(\.isSimple)
        },
        YakuRule(name: "iipeikou", closedHan: 1, openHan: 0) { _, h in
            h.isStandard && h.sequencePairCount == 1
        },
        YakuRule(name: "ryanpeikou", closedHan: 3, openHan: 0) { _, h in
            h.isStandard && h.sequencePairCount == 2
        },
        YakuRule(name: "yakuhai_haku", closedHan: 1, openHan: 1) { _, h in
            h.hasTripletOrKan(of: .haku)
        },
        YakuRule(name: "yakuhai_hatsu", closedHan: 1, openHan: 1) { _, h in
            h.hasTripletOrKan(of: .hatsu)
        },
        YakuRule(name: "yakuhai_chun", closedHan: 1, openHan: 1) { _, h in
            h.hasTripletOrKan(of: .chun)
        },
        YakuRule(name: "yakuhai_seat", closedHan: 1, openHan: 1) { ctx, h in
            h.hasTripletOrKan(of: ctx.seat.tileKind)
        },
        YakuRule(name: "yakuhai_round", closedHan: 1, openHan: 1) { ctx, h in
            h.hasTripletOrKan(of: ctx.round.tileKind)
        },
        YakuRule(name: "chiitoi", closedHan: 2, openHan: 0) { _, h in
            h.isChiitoi
        },
        YakuRule(name: "toitoi", closedHan: 2, openHan: 2) { _, h in
            h.isStandard && h.sets.allSatisfy(\.isTripletOrKan)
        },
        YakuRule(name: "sanankou", closedHan: 2, openHan: 2) { _, h in
            h.isStandard && h.concealedTripletCount == 3
        },
        YakuRule(name: "sanshoku", closedHan: 2, openHan: 1) { _, h in
            guard h.isStandard else { return false }
            let seqs = h.sets.filter(\.isSequence)
            for r in UInt8(1)...7 {
                let hasM = seqs.contains { $0.base.suit == .man && $0.base.rank == r }
                let hasP = seqs.contains { $0.base.suit == .pin && $0.base.rank == r }
                let hasS = seqs.contains { $0.base.suit == .sou && $0.base.rank == r }
                if hasM && hasP && hasS { return true }
            }
            return false
        },
        YakuRule(name: "sanshoku_doukou", closedHan: 2, openHan: 2) { _, h in
            guard h.isStandard else { return false }
            let trips = h.sets.filter(\.isTripletOrKan)
            for r in UInt8(1)...9 {
                let hasM = trips.contains { $0.base.suit == .man && $0.base.rank == r }
                let hasP = trips.contains { $0.base.suit == .pin && $0.base.rank == r }
                let hasS = trips.contains { $0.base.suit == .sou && $0.base.rank == r }
                if hasM && hasP && hasS { return true }
            }
            return false
        },
        YakuRule(name: "ittsu", closedHan: 2, openHan: 1) { _, h in
            guard h.isStandard else { return false }
            let seqs = h.sets.filter(\.isSequence)
            for suit in [Suit.man, .pin, .sou] {
                let has1 = seqs.contains { $0.base.suit == suit && $0.base.rank == 1 }
                let has4 = seqs.contains { $0.base.suit == suit && $0.base.rank == 4 }
                let has7 = seqs.contains { $0.base.suit == suit && $0.base.rank == 7 }
                if has1 && has4 && has7 { return true }
            }
            return false
        },
        YakuRule(name: "chanta", closedHan: 2, openHan: 1) { _, h in
            guard case .standard(let pair, let sets, _) = h.shape else { return false }
            guard pair.isYaochu && sets.allSatisfy(\.hasYaochu) else { return false }
            guard sets.contains(where: \.isSequence) else { return false }
            return pair.isHonor || sets.contains(where: \.hasHonor)
        },
        YakuRule(name: "junchan", closedHan: 3, openHan: 2) { _, h in
            guard case .standard(let pair, let sets, _) = h.shape else { return false }
            guard pair.isTerminal && sets.allSatisfy({ $0.hasYaochu && !$0.hasHonor }) else { return false }
            return sets.contains(where: \.isSequence)
        },
        YakuRule(name: "honroutou", closedHan: 2, openHan: 2) { _, h in
            h.allTilesSatisfy(\.isYaochu)
        },
        YakuRule(name: "shousangen", closedHan: 2, openHan: 2) { _, h in
            guard let pair = h.pair, pair.isDragon else { return false }
            let dragonSets = h.sets.filter { $0.isTripletOrKan && $0.base.isDragon }.count
            return dragonSets == 2
        },
        YakuRule(name: "sankantsu", closedHan: 2, openHan: 2) { _, h in
            h.isStandard && h.kanCount == 3
        },
        YakuRule(name: "honitsu", closedHan: 3, openHan: 2) { _, h in
            let sp = h.suitPresence
            return sp.numberedCount == 1 && sp.hasHonor
        },
        YakuRule(name: "chinitsu", closedHan: 6, openHan: 5) { _, h in
            let sp = h.suitPresence
            return sp.numberedCount == 1 && !sp.hasHonor
        },
    ]

    static func score(_ req: ScoreRequest) -> ScoreOutcome {
        var concealed = req.hand
        concealed.add(req.win)

        let agari = Agari.decompose(concealed.counts, meldCount: req.melds.count)
        guard agari.isWin else { return .notAgari }

        var allCounts = concealed.counts
        var akaCount = concealed.akaCount
        for m in req.melds {
            akaCount += m.akaCount
            for t in m.tiles {
                allCounts.add(t.kind)
            }
        }

        let isClosed = req.melds.allSatisfy(\.isClosed)
        let hasMelds = !req.melds.isEmpty

        let doraCount = req.dora.reduce(0) { $0 + Int(allCounts[$1.kind.doraNext]) }
        let uraCount = req.flags.hasAnyRiichi
            ? req.ura.reduce(0) { $0 + Int(allCounts[$1.kind.doraNext]) }
            : 0

        let ctx = ScoreContext(by: req.by, seat: req.seat, round: req.round, flags: req.flags)

        // For tenhou, any tile kind in the 14-tile hand may be treated as the winning tile.
        let candidateWinKinds: [TileKind]
        if req.flags.contains(.tenhou) {
            candidateWinKinds = (0..<34).compactMap { concealed.counts[$0] > 0 ? TileKind(unchecked: UInt8($0)) : nil }
        } else {
            candidateWinKinds = [req.win.kind]
        }

        var best: ScoredHand? = nil
        for winKind in candidateWinKinds {
            let interpretations = buildInterpretations(
                agari: agari,
                concealedCounts: concealed.counts,
                allCounts: allCounts,
                melds: req.melds,
                winKind: winKind,
                by: req.by,
                isClosed: isClosed,
                hasMelds: hasMelds
            )
            for interp in interpretations {
                if let candidate = evaluate(
                    interp: interp,
                    ctx: ctx,
                    doraCount: doraCount,
                    akaCount: akaCount,
                    uraCount: uraCount,
                    honba: req.honba
                ) {
                    if best == nil || best! < candidate {
                        best = candidate
                    }
                }
            }
        }

        if let best {
            return .scored(best)
        }
        return .noYaku
    }

    private static func buildInterpretations(
        agari: AgariResult,
        concealedCounts: TileCounts,
        allCounts: TileCounts,
        melds: [Meld],
        winKind: TileKind,
        by: WinMethod,
        isClosed: Bool,
        hasMelds: Bool
    ) -> [HandInterpretation] {
        var result: [HandInterpretation] = []

        let meldSets: [ResolvedSet] = melds.map { m in
            switch m.kind {
            case .chi:
                return ResolvedSet(kind: .sequence, base: m.baseKind, isConcealed: false)
            case .pon:
                return ResolvedSet(kind: .triplet, base: m.baseKind, isConcealed: false)
            case .daiminkan, .shouminkan:
                return ResolvedSet(kind: .kan, base: m.baseKind, isConcealed: false)
            case .ankan:
                return ResolvedSet(kind: .kan, base: m.baseKind, isConcealed: true)
            }
        }

        for form in agari.standardForms {
            guard let pairGroup = form.first(where: { $0.kind == .pair }) else { continue }
            let concealedGroups = form.filter { $0.kind != .pair }

            // Option A: winKind completes the pair (tanki wait)
            if pairGroup.base == winKind {
                var sets = meldSets
                for g in concealedGroups {
                    sets.append(ResolvedSet(
                        kind: g.kind == .sequence ? .sequence : .triplet,
                        base: g.base,
                        isConcealed: true
                    ))
                }
                result.append(HandInterpretation(
                    shape: .standard(pair: pairGroup.base, sets: sets, wait: .tanki),
                    winKind: winKind,
                    isClosed: isClosed,
                    hasMelds: hasMelds,
                    allCounts: allCounts
                ))
            }

            // Option B: winKind completes one of the concealed groups
            var triedGroupKeys = Set<Group>()
            for (idx, g) in concealedGroups.enumerated() {
                if !triedGroupKeys.insert(g).inserted { continue }

                let waitType: WaitType?
                switch g.kind {
                case .pair:
                    waitType = nil
                case .triplet:
                    waitType = (g.base == winKind) ? .shanpon : nil
                case .sequence:
                    if winKind.suit == g.base.suit {
                        let diff = Int(winKind.rank) - Int(g.base.rank)
                        if diff == 1 {
                            waitType = .kanchan
                        } else if diff == 0 {
                            waitType = (g.base.rank == 7) ? .penchan : .ryanmen
                        } else if diff == 2 {
                            waitType = (g.base.rank == 1) ? .penchan : .ryanmen
                        } else {
                            waitType = nil
                        }
                    } else {
                        waitType = nil
                    }
                }

                guard let wait = waitType else { continue }

                var sets = meldSets
                for (j, cg) in concealedGroups.enumerated() {
                    let isWinningTripletByRon = (j == idx && cg.kind == .triplet && by == .ron)
                    sets.append(ResolvedSet(
                        kind: cg.kind == .sequence ? .sequence : .triplet,
                        base: cg.base,
                        isConcealed: !isWinningTripletByRon
                    ))
                }
                result.append(HandInterpretation(
                    shape: .standard(pair: pairGroup.base, sets: sets, wait: wait),
                    winKind: winKind,
                    isClosed: isClosed,
                    hasMelds: hasMelds,
                    allCounts: allCounts
                ))
            }
        }

        if agari.isChiitoi {
            let pairs = (0..<34).compactMap { concealedCounts[$0] == 2 ? TileKind(unchecked: UInt8($0)) : nil }
            result.append(HandInterpretation(
                shape: .chiitoi(pairs: pairs),
                winKind: winKind,
                isClosed: true,
                hasMelds: false,
                allCounts: allCounts
            ))
        }

        if agari.isKokushi {
            // 13-sided wait iff winKind is the duplicated yaochu tile
            let is13 = concealedCounts[winKind] == 2
            result.append(HandInterpretation(
                shape: .kokushi(is13Wait: is13),
                winKind: winKind,
                isClosed: true,
                hasMelds: false,
                allCounts: allCounts
            ))
        }

        return result
    }

    private static func evaluate(
        interp: HandInterpretation,
        ctx: ScoreContext,
        doraCount: Int,
        akaCount: Int,
        uraCount: Int,
        honba: Int
    ) -> ScoredHand? {
        // 1. Check natural yakuman
        var yakumanMatched: [(name: String, value: Int)] = []
        var yakumanTotal = 0
        for rule in yakumanRules {
            if rule.matches(ctx, interp) {
                yakumanMatched.append((rule.name, rule.multiple))
                yakumanTotal += rule.multiple
            }
        }
        if yakumanTotal > 0 {
            yakumanMatched.sort { $0.name < $1.name }
            let basic = 8000 * yakumanTotal
            let (payStr, total) = computePayment(basic: basic, by: ctx.by, seat: ctx.seat, honba: honba)
            let yakuStr = yakumanMatched.map { "\($0.name):\($0.value)" }.joined(separator: ",")
            return ScoredHand(
                yaku: yakumanMatched,
                isYakuman: true,
                han: 0,
                fu: 0,
                yakumanMultiple: yakumanTotal,
                payString: payStr,
                total: total,
                yakuString: yakuStr
            )
        }

        // 2. Check regular yaku
        var matched: [(name: String, value: Int)] = []
        var han = 0
        var hasPinfu = false
        for rule in yakuRules {
            let h = interp.isClosed ? rule.closedHan : rule.openHan
            if h == 0 { continue }
            if rule.matches(ctx, interp) {
                matched.append((rule.name, h))
                han += h
                if rule.name == "pinfu" { hasPinfu = true }
            }
        }
        guard han > 0 else { return nil }

        if doraCount > 0 {
            matched.append(("dora", doraCount))
            han += doraCount
        }
        if akaCount > 0 {
            matched.append(("aka", akaCount))
            han += akaCount
        }
        if uraCount > 0 {
            matched.append(("ura", uraCount))
            han += uraCount
        }
        matched.sort { $0.name < $1.name }

        let fu = computeFu(interp: interp, ctx: ctx, hasPinfu: hasPinfu)
        let basic = computeBasicPoints(han: han, fu: fu)
        let (payStr, total) = computePayment(basic: basic, by: ctx.by, seat: ctx.seat, honba: honba)
        let yakuStr = matched.map { "\($0.name):\($0.value)" }.joined(separator: ",")

        return ScoredHand(
            yaku: matched,
            isYakuman: false,
            han: han,
            fu: fu,
            yakumanMultiple: 0,
            payString: payStr,
            total: total,
            yakuString: yakuStr
        )
    }

    private static func computeFu(interp: HandInterpretation, ctx: ScoreContext, hasPinfu: Bool) -> Int {
        switch interp.shape {
        case .chiitoi:
            return 25
        case .kokushi:
            return 20
        case .standard(let pair, let sets, let wait):
            if hasPinfu && ctx.by == .tsumo {
                return 20
            }
            var fu = 20
            if interp.isClosed && ctx.by == .ron {
                fu += 10
            }
            if ctx.by == .tsumo {
                fu += 2
            }
            for s in sets {
                fu += s.fu
            }
            if pair.isDragon {
                fu += 2
            } else {
                if pair == ctx.seat.tileKind { fu += 2 }
                if pair == ctx.round.tileKind { fu += 2 }
            }
            fu += wait.fu

            if !interp.isClosed && ctx.by == .ron && fu == 20 {
                return 30
            }
            return ((fu + 9) / 10) * 10
        }
    }

    private static func computeBasicPoints(han: Int, fu: Int) -> Int {
        if han >= 13 { return 8000 }
        if han >= 11 { return 6000 }
        if han >= 8  { return 4000 }
        if han >= 6  { return 3000 }
        if han >= 5  { return 2000 }
        let raw = fu * (1 << (2 + han))
        return min(2000, raw)
    }

    private static func ceil100(_ value: Int) -> Int {
        ((value + 99) / 100) * 100
    }

    private static func computePayment(basic: Int, by: WinMethod, seat: Wind, honba: Int) -> (String, Int) {
        let isDealer = (seat == .east)
        switch by {
        case .ron:
            let mult = isDealer ? 6 : 4
            let pay = ceil100(basic * mult) + 300 * honba
            return ("ron:\(pay)", pay)
        case .tsumo:
            if isDealer {
                let each = ceil100(basic * 2) + 100 * honba
                return ("all:\(each)", each * 3)
            } else {
                let nonDealer = ceil100(basic) + 100 * honba
                let dealer = ceil100(basic * 2) + 100 * honba
                return ("tsumo:\(nonDealer)/\(dealer)", nonDealer * 2 + dealer)
            }
        }
    }
}
