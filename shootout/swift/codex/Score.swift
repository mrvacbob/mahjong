struct ScoreContext {
    let seat: Int
    let round: Int
    let dora: [Tile]
    let ura: [Tile]
    let honba: Int
    var flags: Set<Substring>
}

private enum Wait {
    case tanki, shanpon, ryanmen, kanchan, penchan

    init(group: Group, winningKind: Int) {
        switch group.type {
        case .pair: self = .tanki
        case .triplet, .kan: self = .shanpon
        case .sequence:
            let offset = winningKind - group.kind
            if offset == 1 {
                self = .kanchan
            } else if (offset == 2 && group.kind % 9 == 0) || (offset == 0 && group.kind % 9 == 6) {
                self = .penchan
            } else {
                self = .ryanmen
            }
        }
    }

    var fu: Int {
        switch self {
        case .ryanmen, .shanpon: 0
        case .tanki, .kanchan, .penchan: 2
        }
    }
}

private struct StandardWin {
    let groups: [Group]
    let wait: Wait

    var pair: Int { groups.first { $0.type == .pair }!.kind }
    var sequences: [Int] { groups.filter { $0.type == .sequence }.map(\.kind) }
    var triplets: [Group] { groups.filter { $0.type == .triplet || $0.type == .kan } }
    var kans: Int { triplets.count(where: { $0.type == .kan }) }
    var concealedTriplets: Int { triplets.count(where: { !$0.open }) }

    func pairFu(_ context: ScoreContext) -> Int {
        if pair >= 31 { return 2 }
        return (pair == context.seat ? 2 : 0) + (pair == context.round ? 2 : 0)
    }

    func fu(_ context: ScoreContext, closed: Bool, tsumo: Bool, pinfu: Bool) -> Int {
        if pinfu && tsumo { return 20 }
        var raw = 20 + pairFu(context) + wait.fu
        raw += tsumo ? 2 : (closed ? 10 : 0)
        for group in triplets {
            let base = group.type == .kan ? 8 : 2
            raw += base * (group.open ? 1 : 2) * (isOutside(group.kind) ? 2 : 1)
        }
        return max(30, (raw + 9) / 10 * 10)
    }
}

private struct Score {
    let yaku: String
    let yakuman: Int
    let han: Int
    let fu: Int
    let payment: String
    let total: Int

    init(_ entries: [String: Int], fu: Int = 0, yakuman: Bool = false, dealer: Bool, tsumo: Bool, honba: Int) {
        yaku = entries.keys.sorted().map { "\($0):\(entries[$0]!)" }.joined(separator: ",")
        let value = entries.values.reduce(0, +)
        self.yakuman = yakuman ? value : 0
        han = yakuman ? 0 : value
        self.fu = fu

        let basic: Int
        if yakuman {
            basic = 8000 * value
        } else {
            switch han {
            case 13...: basic = 8000
            case 11...12: basic = 6000
            case 8...10: basic = 4000
            case 6...7: basic = 3000
            case 5: basic = 2000
            default: basic = min(2000, fu * (1 << (han + 2)))
            }
        }

        func roundPayment(_ points: Int) -> Int { (points + 99) / 100 * 100 }
        if !tsumo {
            total = roundPayment(basic * (dealer ? 6 : 4)) + honba * 300
            payment = "ron:\(total)"
        } else {
            let high = roundPayment(basic * 2) + honba * 100
            let low = roundPayment(basic) + honba * 100
            total = dealer ? high * 3 : high + low * 2
            payment = dealer ? "all:\(high)" : "tsumo:\(low)/\(high)"
        }
    }

    var text: String {
        let points = yakuman > 0 ? "yakuman=\(yakuman)" : "han=\(han) fu=\(fu)"
        return "yaku=\(yaku) \(points) pay=\(payment) total=\(total)"
    }

    func beats(_ other: Score) -> Bool {
        let rank = (total, yakuman > 0 ? 1 : 0, han, fu)
        let otherRank = (other.total, other.yakuman > 0 ? 1 : 0, other.han, other.fu)
        return rank == otherRank ? yaku < other.yaku : rank > otherRank
    }
}

enum ScoreResult {
    case notAgari, noYaku, scored(String)

    var text: String {
        switch self {
        case .notAgari: "error=not_agari"
        case .noYaku: "error=no_yaku"
        case .scored(let result): result
        }
    }

    var canWin: Bool {
        if case .scored = self { return true }
        return false
    }
}

private func doraKind(_ kind: Int) -> Int {
    switch kind {
    case 0..<27: kind / 9 * 9 + (kind % 9 + 1) % 9
    case 27...30: 27 + (kind - 27 + 1) % 4
    default: 31 + (kind - 31 + 1) % 3
    }
}

func score(_ hand: Hand, win: Tile, tsumo: Bool, context: ScoreContext) -> ScoreResult {
    let concealed = counts(hand.tiles + [win])
    let forms = winningForms(concealed, meldCount: hand.melds.count)
    guard !forms.isEmpty else { return .notAgari }

    let allTiles = hand.allTiles + [win]
    let totalCounts = counts(allTiles)
    let present = kinds.filter { totalCounts[$0] > 0 }
    let numberedSuits = Set(present.filter { $0 < 27 }.map { $0 / 9 })
    let hasHonors = present.contains { $0 >= 27 }
    let closed = hand.closed
    let flags = context.flags
    let winningKinds = flags.contains("tenhou") ? kinds.filter { concealed[$0] > 0 } : [win.kind]
    let meldGroups = hand.melds.map(\.group)
    let gatePattern = [3, 1, 1, 1, 1, 1, 1, 1, 3]
    let gatesSuit = numberedSuits.first.map { $0 * 9 } ?? 0
    let nineGates = hand.melds.isEmpty && !hasHonors && numberedSuits.count == 1
        && gatePattern.indices.allSatisfy { concealed[gatesSuit + $0] >= gatePattern[$0] }

    var best: Score?
    func offer(_ entries: [String: Int], fu: Int = 0, yakuman: Bool = false) {
        let candidate = Score(entries, fu: fu, yakuman: yakuman, dealer: context.seat == 27,
                              tsumo: tsumo, honba: context.honba)
        if let current = best, !candidate.beats(current) { return }
        best = candidate
    }

    func evaluate(_ standard: StandardWin?, sevenPairs: Bool = false, kokushi: Bool = false, winningKind: Int) {
        let tripletKinds = Set(standard?.triplets.map(\.kind) ?? [])
        let dragonTriplets = tripletKinds.count(where: { $0 >= 31 })
        let windTriplets = tripletKinds.count(where: { (27...30).contains($0) })
        let pair = standard?.pair

        var yakuman: [String: Int] = [:]
        if flags.contains("tenhou") { yakuman["tenhou"] = 1 }
        if flags.contains("chiihou") { yakuman["chiihou"] = 1 }
        if kokushi {
            if concealed[winningKind] == 2 { yakuman["kokushi_13"] = 2 }
            else { yakuman["kokushi"] = 1 }
        }
        if dragonTriplets == 3 { yakuman["daisangen"] = 1 }
        if windTriplets == 4 { yakuman["daisuushii"] = 2 }
        else if windTriplets == 3, let pair, (27...30).contains(pair) { yakuman["shousuushii"] = 1 }
        if numberedSuits.isEmpty { yakuman["tsuuiisou"] = 1 }
        if present.allSatisfy(isTerminal) { yakuman["chinroutou"] = 1 }
        if present.allSatisfy({ [19, 20, 21, 23, 25, 32].contains($0) }) { yakuman["ryuuiisou"] = 1 }
        if nineGates {
            let extra = concealed[winningKind] > gatePattern[winningKind - gatesSuit]
            yakuman[extra ? "junsei_chuuren" : "chuuren"] = extra ? 2 : 1
        }
        if let standard {
            if standard.kans == 4 { yakuman["suukantsu"] = 1 }
            if standard.concealedTriplets == 4 {
                let tanki = standard.wait == .tanki
                yakuman[tanki ? "suuankou_tanki" : "suuankou"] = tanki ? 2 : 1
            }
        }
        if !yakuman.isEmpty {
            offer(yakuman, yakuman: true)
            return
        }

        var yaku: [String: Int] = [:]
        for situational in ["ippatsu", "haitei", "houtei", "rinshan", "chankan"] where flags.contains(Substring(situational)) {
            yaku[situational] = 1
        }
        let riichi = flags.contains("riichi") || flags.contains("double_riichi")
        if flags.contains("double_riichi") { yaku["double_riichi"] = 2 }
        else if riichi { yaku["riichi"] = 1 }
        if closed && tsumo { yaku["tsumo"] = 1 }
        if present.allSatisfy({ !isOutside($0) }) { yaku["tanyao"] = 1 }
        if present.allSatisfy(isOutside) { yaku["honroutou"] = 2 }
        if numberedSuits.count == 1 {
            if hasHonors { yaku["honitsu"] = closed ? 3 : 2 }
            else { yaku["chinitsu"] = closed ? 6 : 5 }
        }

        var fu = 25
        if sevenPairs { yaku["chiitoi"] = 2 }
        if let standard {
            let sequences = standard.sequences
            let starts = Set(sequences)
            let pinfu = closed && sequences.count == 4 && standard.pairFu(context) == 0
                && standard.wait == .ryanmen
            if pinfu { yaku["pinfu"] = 1 }
            if closed {
                let repeats = starts.reduce(0) { sum, start in
                    sum + sequences.count(where: { $0 == start }) / 2
                }
                if repeats == 2 { yaku["ryanpeikou"] = 3 }
                else if repeats == 1 { yaku["iipeikou"] = 1 }
            }
            for (kind, name) in [(31, "haku"), (32, "hatsu"), (33, "chun"),
                                 (context.seat, "seat"), (context.round, "round")]
                where tripletKinds.contains(kind) {
                yaku["yakuhai_\(name)"] = 1
            }
            if sequences.isEmpty { yaku["toitoi"] = 2 }
            if standard.concealedTriplets == 3 { yaku["sanankou"] = 2 }
            if standard.kans == 3 { yaku["sankantsu"] = 2 }
            if dragonTriplets == 2, standard.pair >= 31 { yaku["shousangen"] = 2 }
            if (0...6).contains(where: { starts.contains($0) && starts.contains($0 + 9) && starts.contains($0 + 18) }) {
                yaku["sanshoku"] = closed ? 2 : 1
            }
            if (0...8).contains(where: { tripletKinds.contains($0) && tripletKinds.contains($0 + 9) && tripletKinds.contains($0 + 18) }) {
                yaku["sanshoku_doukou"] = 2
            }
            if [0, 9, 18].contains(where: { starts.contains($0) && starts.contains($0 + 3) && starts.contains($0 + 6) }) {
                yaku["ittsu"] = closed ? 2 : 1
            }
            if !sequences.isEmpty, standard.groups.allSatisfy({ $0.kinds.contains(where: isOutside) }) {
                if hasHonors { yaku["chanta"] = closed ? 2 : 1 }
                else { yaku["junchan"] = closed ? 3 : 2 }
            }
            fu = standard.fu(context, closed: closed, tsumo: tsumo, pinfu: pinfu)
        }
        guard !yaku.isEmpty else { return }

        func bonus(_ indicators: [Tile]) -> Int {
            indicators.reduce(0) { $0 + totalCounts[doraKind($1.kind)] }
        }
        let dora = bonus(context.dora)
        let aka = allTiles.count(where: \.red)
        let ura = riichi ? bonus(context.ura) : 0
        for (name, count) in [("dora", dora), ("aka", aka), ("ura", ura)] where count > 0 {
            yaku[name] = count
        }
        offer(yaku, fu: fu)
    }

    for form in forms {
        for winningKind in winningKinds {
            switch form {
            case .kokushi: evaluate(nil, kokushi: true, winningKind: winningKind)
            case .chiitoi: evaluate(nil, sevenPairs: true, winningKind: winningKind)
            case .standard(let groups):
                for index in groups.indices where groups[index].kinds.contains(winningKind) {
                    let wait = Wait(group: groups[index], winningKind: winningKind)
                    var interpreted = groups
                    if !tsumo && wait == .shanpon { interpreted[index].open = true }
                    evaluate(StandardWin(groups: interpreted + meldGroups, wait: wait), winningKind: winningKind)
                }
            }
        }
    }
    return best.map { .scored($0.text) } ?? .noYaku
}
