// Hand decomposition: standard (sets + pair), chiitoi, kokushi.

/// One concealed group of a standard decomposition.
enum Group: Hashable {
    case pair(Kind)
    case run(Kind)      // first tile of the sequence
    case triplet(Kind)

    var base: Kind {
        switch self { case .pair(let k), .run(let k), .triplet(let k): return k }
    }
    var kinds: [Kind] {
        switch self {
        case .pair(let k): return [k, k]
        case .run(let k): return [k, k.shifted(1)!, k.shifted(2)!]
        case .triplet(let k): return [k, k, k]
        }
    }
    /// pair < run < triplet, as the agari output order wants.
    private var shapeRank: Int {
        switch self { case .pair: 0; case .run: 1; case .triplet: 2 }
    }
    static func agariOrder(_ a: Group, _ b: Group) -> Bool {
        (a.base, a.shapeRank) < (b.base, b.shapeRank)
    }
    var text: String { format(kinds: kinds) }
}

/// Every way to split `counts` into exactly one pair plus runs and triplets.
func standardDecompositions(_ counts: Counts) -> [[Group]] {
    guard counts.total % 3 == 2 else { return [] }
    var results: [[Group]] = []
    for head in Kind.all where counts[head] >= 2 {
        var rest = counts
        rest[head] -= 2
        for sets in setDecompositions(rest, from: 0) {
            results.append([.pair(head)] + sets)
        }
    }
    return results
}

/// Splits `counts` (no pair) into runs and triplets, peeling the lowest kind first.
private func setDecompositions(_ counts: Counts, from start: Int) -> [[Group]] {
    guard let i = (start..<Kind.count).first(where: { counts.n[$0] > 0 }) else { return [[]] }
    let k = Kind(i)
    var results: [[Group]] = []
    if counts[k] >= 3 {
        var rest = counts
        rest[k] -= 3
        for tail in setDecompositions(rest, from: i) { results.append([.triplet(k)] + tail) }
    }
    if let k1 = k.shifted(1), let k2 = k.shifted(2), counts[k1] > 0, counts[k2] > 0 {
        var rest = counts
        rest[k] -= 1; rest[k1] -= 1; rest[k2] -= 1
        for tail in setDecompositions(rest, from: i) { results.append([.run(k)] + tail) }
    }
    return results
}

/// Seven distinct pairs.
func isChiitoi(_ counts: Counts) -> Bool {
    counts.total == 14 && counts.n.allSatisfy { $0 == 0 || $0 == 2 }
}

/// One of each terminal and honor plus one duplicate.
func isKokushi(_ counts: Counts) -> Bool {
    counts.total == 14 && Kind.yaochu.allSatisfy { counts[$0] >= 1 }
        && Kind.all.allSatisfy { $0.isYaochu || counts[$0] == 0 }
}

/// The `agari` answer for the concealed tiles of a hand with `meldCount` melds.
func agariForms(_ counts: Counts, meldCount: Int) -> [String] {
    var forms = Set(standardDecompositions(counts).map { groups in
        groups.sorted(by: Group.agariOrder).map(\.text).joined(separator: ",")
    })
    if meldCount == 0 {
        if isChiitoi(counts) { forms.insert("chiitoi") }
        if isKokushi(counts) { forms.insert("kokushi") }
    }
    return forms.sorted()
}
