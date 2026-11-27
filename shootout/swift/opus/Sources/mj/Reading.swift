// A Reading is one interpretation of a winning hand: its shape, where the winning
// tile went, and the context. Yaku and fu are functions of a Reading.

enum Flag: String, CaseIterable {
    case riichi, double_riichi, ippatsu, haitei, houtei, rinshan, chankan, tenhou, chiihou
    case ankan_rob  // legal only: a closed kan is being robbed
}

struct WinContext {
    var seat: Wind = .east
    var round: Wind = .east
    var tsumo: Bool
    var flags: Set<Flag> = []
    var isDealer: Bool { seat == .east }
}

enum SetShape { case run, triplet, kan }

/// A complete set (concealed group or meld), with openness already resolved.
struct HandSet {
    let shape: SetShape
    let base: Kind
    /// For fu and anko counting. A triplet completed by ron is not concealed.
    let concealed: Bool

    var isTriplet: Bool { shape != .run }  // triplets and kans
    var kinds: [Kind] {
        shape == .run ? [base, base.shifted(1)!, base.shifted(2)!] : [base, base, base]
    }
    var hasYaochu: Bool { kinds.contains(where: \.isYaochu) }
    var hasTerminal: Bool { kinds.contains(where: \.isTerminal) }
}

enum Wait { case ryanmen, kanchan, penchan, shanpon, tanki }

enum Shape {
    case standard(sets: [HandSet], pair: Kind, wait: Wait)
    case chiitoi
    case kokushi
}

struct Reading {
    let shape: Shape
    let context: WinContext
    /// No open melds (ankan keeps the hand closed).
    let menzen: Bool
    /// No melds of any kind (chuuren needs this).
    let noMelds: Bool
    /// Every tile of the hand as kinds: concealed tiles, the winning tile, meld tiles.
    let allKinds: [Kind]
    /// The 14 concealed tiles' counts (meaningful when noMelds).
    let concealed: Counts
    /// The concealed tiles before the winning tile.
    let waiting: Counts
    let winKind: Kind

    // Views used by the yaku declarations.
    var sets: [HandSet] {
        if case .standard(let sets, _, _) = shape { return sets }
        return []
    }
    var pair: Kind? {
        if case .standard(_, let pair, _) = shape { return pair }
        return nil
    }
    var wait: Wait? {
        if case .standard(_, _, let wait) = shape { return wait }
        return nil
    }
    var isStandard: Bool { pair != nil }
    var runs: [Kind] { sets.filter { $0.shape == .run }.map(\.base) }
    var triplets: [Kind] { sets.filter(\.isTriplet).map(\.base) }
    var kans: Int { sets.filter { $0.shape == .kan }.count }
    var concealedTriplets: Int { sets.filter { $0.isTriplet && $0.concealed }.count }
    var suits: Set<Suit> { Set(allKinds.map(\.suit)) }
    var hasHonor: Bool { allKinds.contains(where: \.isHonor) }

    /// Seat wind, round wind or dragon.
    func isValue(_ k: Kind) -> Bool {
        k.isDragon || k == context.seat.kind || k == context.round.kind
    }

    /// Number of pairs of identical runs (2 for ryanpeikou).
    var identicalRunPairs: Int {
        Dictionary(grouping: runs, by: { $0 }).values.reduce(0) { $0 + $1.count / 2 }
    }

    /// Four runs, a non-value pair, a two-sided wait, closed.
    var isPinfuShape: Bool {
        menzen && runs.count == 4 && wait == .ryanmen && !(pair.map(isValue) ?? true)
    }

    func hasTriplet(_ k: Kind) -> Bool { triplets.contains(k) }

    /// Every set and the pair contain a tile satisfying `p`; at least one run.
    func allGroupsContain(_ p: (HandSet) -> Bool, pair pairOK: (Kind) -> Bool) -> Bool {
        guard let pair, !runs.isEmpty else { return false }
        return sets.allSatisfy(p) && pairOK(pair)
    }

    /// A run of `number` in each of the three suits.
    var hasSanshokuRuns: Bool {
        (1...7).contains { n in
            [Suit.man, .pin, .sou].allSatisfy { runs.contains(Kind($0, n)) }
        }
    }
    var hasSanshokuTriplets: Bool {
        (1...9).contains { n in
            [Suit.man, .pin, .sou].allSatisfy { triplets.contains(Kind($0, n)) }
        }
    }
    var hasIttsu: Bool {
        [Suit.man, .pin, .sou].contains { s in
            [1, 4, 7].allSatisfy { runs.contains(Kind(s, $0)) }
        }
    }
}

/// Every reading of a complete hand. `concealed` includes the winning tile.
func readings(concealed: Counts, win: Kind, melds: [Meld], context: WinContext) -> [Reading] {
    let menzen = melds.allSatisfy { !$0.isOpen }
    let allKinds = concealed.kinds.flatMap { Array(repeating: $0, count: concealed[$0]) }
        + melds.flatMap { $0.tiles.map(\.kind) }
    let waiting = concealed.removing(win)
    func reading(_ shape: Shape) -> Reading {
        Reading(shape: shape, context: context, menzen: menzen, noMelds: melds.isEmpty,
                allKinds: allKinds, concealed: concealed, waiting: waiting, winKind: win)
    }

    let meldSets = melds.map { m in
        HandSet(shape: m.isChi ? .run : (m.isKan ? .kan : .triplet),
                base: m.base, concealed: !m.isOpen)
    }

    var out: [Reading] = []
    for groups in standardDecompositions(concealed) {
        guard case .pair(let pair) = groups[0] else { continue }
        let rest = groups.dropFirst()
        // Which group did the winning tile complete?
        var placements: [(index: Int?, wait: Wait)] = []
        if pair == win { placements.append((nil, .tanki)) }
        for (i, g) in rest.enumerated() {
            switch g {
            case .triplet(let k) where k == win:
                placements.append((i, .shanpon))
            case .run(let k) where g.kinds.contains(win):
                let pos = win.number - k.number
                let wait: Wait
                if pos == 1 { wait = .kanchan }
                else if pos == 0 { wait = k.number == 7 ? .penchan : .ryanmen }
                else { wait = k.number == 1 ? .penchan : .ryanmen }
                placements.append((i, wait))
            default: break
            }
        }
        for (index, wait) in placements {
            let sets = rest.enumerated().map { i, g -> HandSet in
                switch g {
                case .run(let k): return HandSet(shape: .run, base: k, concealed: true)
                case .triplet(let k):
                    let byRon = i == index && !context.tsumo
                    return HandSet(shape: .triplet, base: k, concealed: !byRon)
                case .pair: fatalError("one pair per decomposition")
                }
            }
            out.append(reading(.standard(sets: sets + meldSets, pair: pair, wait: wait)))
        }
    }
    if melds.isEmpty && isChiitoi(concealed) { out.append(reading(.chiitoi)) }
    if melds.isEmpty && isKokushi(concealed) { out.append(reading(.kokushi)) }
    return out
}
