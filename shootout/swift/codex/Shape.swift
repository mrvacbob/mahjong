enum Form {
    case standard([Group])
    case chiitoi
    case kokushi

    var text: String {
        switch self {
        case .chiitoi: return "chiitoi"
        case .kokushi: return "kokushi"
        case .standard(let groups):
            return groups.sorted { ($0.kind, $0.type.rawValue) < ($1.kind, $1.type.rawValue) }
                .map { formatTiles($0.kinds.map { Tile(kind: $0) }) }.joined(separator: ",")
        }
    }
}

func winningForms(_ concealed: [Int], meldCount: Int) -> [Form] {
    guard concealed.reduce(0, +) == 14 - 3 * meldCount else { return [] }
    var forms: [Form] = []
    if meldCount == 0 {
        if concealed.count(where: { $0 == 2 }) == 7 { forms.append(.chiitoi) }
        if orphans.allSatisfy({ concealed[$0] > 0 }), orphans.contains(where: { concealed[$0] == 2 }),
           orphans.reduce(0, { $0 + concealed[$1] }) == 14 {
            forms.append(.kokushi)
        }
    }

    var remaining = concealed
    var groups: [Group] = []
    func search(from start: Int) {
        guard let kind = (start..<34).first(where: { remaining[$0] > 0 }) else {
            forms.append(.standard(groups))
            return
        }
        if remaining[kind] >= 3 {
            remaining[kind] -= 3
            groups.append(Group(kind: kind, type: .triplet))
            search(from: kind)
            groups.removeLast()
            remaining[kind] += 3
        }
        if kind < 27, kind % 9 <= 6, remaining[kind + 1] > 0, remaining[kind + 2] > 0 {
            remaining[kind] -= 1
            remaining[kind + 1] -= 1
            remaining[kind + 2] -= 1
            groups.append(Group(kind: kind, type: .sequence))
            search(from: kind)
            groups.removeLast()
            remaining[kind] += 1
            remaining[kind + 1] += 1
            remaining[kind + 2] += 1
        }
    }

    for kind in kinds where remaining[kind] >= 2 {
        remaining[kind] -= 2
        groups.append(Group(kind: kind, type: .pair))
        search(from: 0)
        groups.removeLast()
        remaining[kind] += 2
    }
    return forms
}

struct Shanten {
    let standard: Int
    let chiitoi: Int?
    let kokushi: Int?

    var minimum: Int { min(standard, chiitoi ?? 8, kokushi ?? 13) }
    var text: String {
        "std=\(standard) chiitoi=\(chiitoi.map(String.init) ?? "x") kokushi=\(kokushi.map(String.init) ?? "x") min=\(minimum)"
    }
}

private struct Profile {
    var sets = 0
    var head = 0
    var partials = 0
}

final class ShapeSearch {
    private var memo: [Int: [Profile]] = [0: [Profile()]]

    private func profiles(_ code: Int, suited: Bool) -> [Profile] {
        let key = code * 2 + (suited ? 0 : 1)
        if let cached = memo[key] { return cached }
        if code == 0 { return [Profile()] }

        let shift = (code.trailingZeroBitCount / 3) * 3
        let unit = 1 << shift
        let first = (code >> shift) & 7
        let next = (code >> (shift + 3)) & 7
        let third = (code >> (shift + 6)) & 7

        var best = Array(repeating: -1, count: 10)
        func take(_ removed: Int, sets: Int = 0, head: Int = 0, partials: Int = 0) {
            for entry in profiles(code - removed, suited: suited) {
                let totalSets = entry.sets + sets
                let totalHeads = entry.head + head
                guard totalSets <= 4, totalHeads <= 1 else { continue }
                let index = totalSets * 2 + totalHeads
                best[index] = max(best[index], entry.partials + partials)
            }
        }

        take(unit)
        if first >= 2 {
            take(2 * unit, head: 1)
            take(2 * unit, partials: 1)
        }
        if first >= 3 { take(3 * unit, sets: 1) }
        if suited {
            if next > 0 { take(9 * unit, partials: 1) }
            if third > 0 { take(65 * unit, partials: 1) }
            if next > 0, third > 0 { take(73 * unit, sets: 1) }
        }

        let result = best.indices.compactMap { index in
            best[index] < 0 ? nil : Profile(sets: index / 2, head: index % 2, partials: best[index])
        }
        memo[key] = result
        return result
    }

    func shanten(_ concealed: [Int], meldCount: Int) -> Shanten {
        var combined = Array(repeating: -1, count: 10)
        combined[meldCount * 2] = 0
        for suit in 0..<4 {
            let start = suit * 9
            var code = 0
            for kind in start..<min(start + 9, 34) {
                code |= concealed[kind] << (3 * (kind - start))
            }
            if code == 0 { continue }
            var next = Array(repeating: -1, count: 10)
            for local in profiles(code, suited: suit < 3) {
                for index in combined.indices where combined[index] >= 0 {
                    let sets = index / 2 + local.sets
                    let head = index % 2 + local.head
                    guard sets <= 4, head <= 1 else { continue }
                    let target = sets * 2 + head
                    next[target] = max(next[target], combined[index] + local.partials)
                }
            }
            combined = next
        }

        var standard = 8
        for index in combined.indices where combined[index] >= 0 {
            let sets = index / 2
            let head = index % 2
            standard = min(standard, 8 - 2 * sets - min(4 - sets, combined[index]) - head)
        }
        guard meldCount == 0 else { return Shanten(standard: standard, chiitoi: nil, kokushi: nil) }
        let distinct = concealed.count(where: { $0 > 0 })
        let pairs = concealed.count(where: { $0 >= 2 })
        let orphanKinds = orphans.count(where: { concealed[$0] > 0 })
        let orphanPair = orphans.contains(where: { concealed[$0] >= 2 }) ? 1 : 0
        return Shanten(standard: standard, chiitoi: 6 - pairs + max(0, 7 - distinct),
                       kokushi: 13 - orphanKinds - orphanPair)
    }

    func liveImprovements(_ hand: Hand, from shantenBefore: Int) -> [Int: Int] {
        let held = counts(hand.allTiles)
        var concealed = counts(hand.tiles)
        var improvements: [Int: Int] = [:]
        for kind in kinds where held[kind] < 4 {
            concealed[kind] += 1
            let improves = shantenBefore == 0
                ? !winningForms(concealed, meldCount: hand.melds.count).isEmpty
                : shanten(concealed, meldCount: hand.melds.count).minimum < shantenBefore
            if improves { improvements[kind] = 4 - held[kind] }
            concealed[kind] -= 1
        }
        return improvements
    }
}

func structuralWaits(_ hand: Hand) -> [Int] {
    var concealed = counts(hand.tiles)
    return kinds.filter { kind in
        concealed[kind] += 1
        let wins = !winningForms(concealed, meldCount: hand.melds.count).isEmpty
        concealed[kind] -= 1
        return wins
    }
}
