// A Reading is one interpretation of a winning hand: its shape, where the winning
// tile went, and the context. Yaku and fu are functions of a Reading.

public enum Flag: String, Sendable {
    case riichi, double_riichi, ippatsu, haitei, houtei, rinshan, chankan, tenhou, chiihou
    case ankan_rob  // legal only: a closed kan is being robbed
}

/// Parses "riichi,ippatsu" (or "-").
public func parseFlags(_ text: Substring) -> Set<Flag>? {
    if text == "-" { return [] }
    var out: Set<Flag> = []
    for f in text.split(separator: ",") {
        guard let flag = Flag(rawValue: String(f)) else { return nil }
        out.insert(flag)
    }
    return out
}

/// The situation of a win, apart from the tiles.
public struct WinContext: Sendable {
    public var seat: Wind
    public var round: Wind
    public var tsumo: Bool
    /// Situational yaku come only from here.
    public var flags: Set<Flag>

    public init(seat: Wind = .east, round: Wind = .east, tsumo: Bool, flags: Set<Flag> = []) {
        self.seat = seat; self.round = round; self.tsumo = tsumo; self.flags = flags
    }
    public var isDealer: Bool { seat == .east }
}

enum SetShape { case run, triplet, kan }

extension MeldKind {
    var shape: SetShape {
        switch self {
        case .chi: .run
        case .pon: .triplet
        case .daiminkan, .shouminkan, .ankan: .kan
        }
    }
}

/// A complete set (concealed group or meld), with openness already resolved.
struct HandSet: Equatable {
    let shape: SetShape
    let base: Kind
    /// For fu and anko counting. A triplet completed by ron is not concealed.
    let concealed: Bool

    init(_ meld: Meld) {
        shape = meld.kind.shape; base = meld.base; concealed = !meld.isOpen
    }
    init(_ group: Group, concealed: Bool) {
        switch group {
        case .run(let k): shape = .run; base = k
        case .triplet(let k): shape = .triplet; base = k
        }
        self.concealed = concealed
    }

    var isTriplet: Bool { shape != .run }  // triplets and kans
    var kinds: [Kind] { shape == .run ? base.run : [base, base, base] }
    var hasYaochu: Bool { kinds.contains(where: \.isYaochu) }
    var hasTerminal: Bool { kinds.contains(where: \.isTerminal) }
}

enum Wait { case ryanmen, kanchan, penchan, shanpon, tanki }

enum Shape: Equatable {
    case standard(sets: [HandSet], pair: Kind, wait: Wait)
    case chiitoi
    case kokushi
}

struct Reading {
    let shape: Shape
    let context: WinContext
    let rules: Rules
    let melds: [Meld]
    /// Every tile of the hand as kinds: concealed tiles, the winning tile, meld tiles.
    let allKinds: [Kind]
    /// The concealed tiles, including the winning tile.
    let concealed: Counts
    let winKind: Kind

    /// No open melds (ankan keeps the hand closed).
    var menzen: Bool { melds.isClosed }
    /// The concealed tiles before the winning tile.
    var waiting: Counts { concealed.removing(winKind) }

    // Views used by the yaku declarations.
    private var standard: (sets: [HandSet], pair: Kind, wait: Wait)? {
        if case .standard(let sets, let pair, let wait) = shape { (sets, pair, wait) } else { nil }
    }
    var sets: [HandSet] { standard?.sets ?? [] }
    var pair: Kind? { standard?.pair }
    var wait: Wait? { standard?.wait }
    var runs: [Kind] { sets.filter { $0.shape == .run }.map(\.base) }
    var triplets: [Kind] { sets.filter(\.isTriplet).map(\.base) }
    var kans: Int { sets.count { $0.shape == .kan } }
    var concealedTriplets: Int { sets.count { $0.isTriplet && $0.concealed } }
    var suits: Set<Suit> { Set(allKinds.map(\.suit)) }
    var hasHonor: Bool { allKinds.contains(where: \.isHonor) }

    /// Seat wind, round wind or dragon.
    func isValue(_ k: Kind) -> Bool {
        k.isDragon || k == context.seat.kind || k == context.round.kind
    }

    /// Number of pairs of identical runs (2 for ryanpeikou).
    var identicalRunPairs: Int {
        let c = Counts(runs)
        return c.kinds.reduce(0) { $0 + c[$1] / 2 }
    }

    /// Four runs, a non-value pair, a two-sided wait, closed.
    var isPinfuShape: Bool {
        menzen && runs.count == 4 && wait == .ryanmen && !(pair.map(isValue) ?? true)
    }

    /// Every set and the pair contain a tile satisfying `p`; at least one run.
    func allGroupsContain(_ p: (HandSet) -> Bool, pair pairOK: (Kind) -> Bool) -> Bool {
        guard let pair, !runs.isEmpty else { return false }
        return sets.allSatisfy(p) && pairOK(pair)
    }

    /// Some number in `numbers` appears in `bases` in all three suits.
    private func inThreeSuits(_ bases: [Kind], _ numbers: ClosedRange<Int>) -> Bool {
        numbers.contains { n in [Suit.man, .pin, .sou].allSatisfy { bases.contains(Kind($0, n)) } }
    }
    var hasSanshokuRuns: Bool { inThreeSuits(runs, 1...7) }
    var hasSanshokuTriplets: Bool { inThreeSuits(triplets, 1...9) }
    var hasIttsu: Bool {
        let runs = runs
        return [Suit.man, .pin, .sou].contains { s in
            [1, 4, 7].allSatisfy { runs.contains(Kind(s, $0)) }
        }
    }
}

/// The wait shape when `win` completed `group`, or nil if `win` is not in it.
private func wait(completing group: Group, with win: Kind) -> Wait? {
    guard group.kinds.contains(win) else { return nil }
    switch group {
    case .triplet: return .shanpon
    case .run(let k):
        switch win.number - k.number {
        case 1: return .kanchan
        case 0: return k.number == 7 ? .penchan : .ryanmen
        default: return k.number == 1 ? .penchan : .ryanmen
        }
    }
}

/// Every reading of a complete hand. `concealed` includes the winning tile.
func readings(concealed: Counts, win: Kind, melds: [Meld], context: WinContext,
              rules: Rules) -> [Reading] {
    let allKinds = concealed.kinds.flatMap { Array(repeating: $0, count: concealed[$0]) }
        + melds.tiles.map(\.kind)
    func reading(_ shape: Shape) -> Reading {
        Reading(shape: shape, context: context, rules: rules, melds: melds,
                allKinds: allKinds, concealed: concealed, winKind: win)
    }
    let meldSets = melds.map(HandSet.init)

    var out: [Reading] = []
    for d in standardDecompositions(concealed) {
        // Which group did the winning tile complete? (nil: the pair.)
        var placements: [(index: Int?, wait: Wait)] = d.pair == win ? [(nil, .tanki)] : []
        for (i, g) in d.sets.enumerated() {
            if let w = wait(completing: g, with: win) { placements.append((i, w)) }
        }
        for (index, wait) in placements {
            let sets = d.sets.enumerated().map { i, g in
                // A set completed by ron counts as open (it matters for triplets).
                HandSet(g, concealed: !(i == index && !context.tsumo))
            }
            out.append(reading(.standard(sets: sets + meldSets, pair: d.pair, wait: wait)))
        }
    }
    if melds.isEmpty && isChiitoi(concealed) { out.append(reading(.chiitoi)) }
    if melds.isEmpty && isKokushi(concealed) { out.append(reading(.kokushi)) }
    return out
}
