// Hand decomposition: standard (sets + pair), chiitoi, kokushi.

/// One concealed set of a standard decomposition.
public enum Group: Hashable, Sendable {
    case run(Kind)      // first tile of the sequence
    case triplet(Kind)

    public var base: Kind {
        switch self { case .run(let k), .triplet(let k): k }
    }
    public var kinds: [Kind] {
        switch self {
        case .run(let k): k.run
        case .triplet(let k): [k, k, k]
        }
    }
}

/// Four sets (with melds) and a pair.
public struct Decomposition: Sendable {
    public let pair: Kind
    public let sets: [Group]

    /// The agari form: groups by suit, number, then pair < run < triplet.
    public var text: String {
        let pair = (key: (pair, 0), kinds: [pair, pair])
        let sets = sets.map { g in
            switch g {
            case .run(let k): (key: (k, 1), kinds: g.kinds)
            case .triplet(let k): (key: (k, 2), kinds: g.kinds)
            }
        }
        return ([pair] + sets).sorted { $0.key < $1.key }
            .map { mpsz(kinds: $0.kinds) }.joined(separator: ",")
    }
}

/// Every way to split `counts` into exactly one pair plus runs and triplets.
public func standardDecompositions(_ counts: Counts) -> [Decomposition] {
    guard counts.total % 3 == 2 else { return [] }
    return Kind.all.filter { counts[$0] >= 2 }.flatMap { pair in
        var rest = counts
        rest[pair] -= 2
        return setDecompositions(rest, from: 0).map { Decomposition(pair: pair, sets: $0) }
    }
}

/// Splits `counts` (no pair) into runs and triplets, peeling the lowest kind first.
private func setDecompositions(_ counts: Counts, from start: Int) -> [[Group]] {
    guard let i = (start..<Kind.count).first(where: { counts[Kind($0)] > 0 }) else { return [[]] }
    let k = Kind(i)
    var results: [[Group]] = []
    func peel(_ g: Group) {
        var rest = counts
        for x in g.kinds { rest[x] -= 1 }
        results += setDecompositions(rest, from: i).map { [g] + $0 }
    }
    if counts[k] >= 3 { peel(.triplet(k)) }
    if let k1 = k.shifted(1), let k2 = k.shifted(2), counts[k1] > 0, counts[k2] > 0 { peel(.run(k)) }
    return results
}

/// Seven distinct pairs.
public func isChiitoi(_ counts: Counts) -> Bool {
    counts.total == 14 && counts.count { $0 == 2 } == 7
}

/// One of each terminal and honor plus one duplicate.
public func isKokushi(_ counts: Counts) -> Bool {
    counts.total == 14 && Kind.yaochu.allSatisfy { counts[$0] >= 1 }
        && Kind.all.allSatisfy { $0.isYaochu || counts[$0] == 0 }
}

/// A winning shape: four sets and a pair, or (with no melds) chiitoi or kokushi.
public func isComplete(_ counts: Counts, meldCount: Int) -> Bool {
    !standardDecompositions(counts).isEmpty
        || meldCount == 0 && (isChiitoi(counts) || isKokushi(counts))
}

/// Kinds that complete a tenpai hand. Structural: a fifth copy counts.
public func completingKinds(_ counts: Counts, meldCount: Int) -> [Kind] {
    Kind.all.filter { isComplete(counts.adding($0), meldCount: meldCount) }
}

/// The `agari` answer for the concealed tiles of a hand with `meldCount` melds.
public func agariForms(_ counts: Counts, meldCount: Int) -> [String] {
    var forms = Set(standardDecompositions(counts).map(\.text))
    if meldCount == 0 {
        if isChiitoi(counts) { forms.insert("chiitoi") }
        if isKokushi(counts) { forms.insert("kokushi") }
    }
    return forms.sorted()
}
