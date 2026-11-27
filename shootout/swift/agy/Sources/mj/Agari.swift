import Foundation

struct AgariResult: Sendable {
    let standardForms: [[Group]]
    let isChiitoi: Bool
    let isKokushi: Bool

    var isWin: Bool {
        !standardForms.isEmpty || isChiitoi || isKokushi
    }

    func formattedForms() -> [String] {
        var forms: [String] = []
        forms.reserveCapacity(standardForms.count + 2)
        for groups in standardForms {
            forms.append(groups.map(\.description).joined(separator: ","))
        }
        if isChiitoi {
            forms.append("chiitoi")
        }
        if isKokushi {
            forms.append("kokushi")
        }
        forms.sort()
        return forms
    }
}

enum Agari {
    static func isChiitoi(_ counts: TileCounts, meldCount: Int) -> Bool {
        guard meldCount == 0 else { return false }
        var pairs = 0
        for i in 0..<34 {
            let c = counts[i]
            if c == 2 {
                pairs += 1
            } else if c != 0 {
                return false
            }
        }
        return pairs == 7
    }

    static func isKokushi(_ counts: TileCounts, meldCount: Int) -> Bool {
        guard meldCount == 0 else { return false }
        var yaochuTotal = 0
        for k in TileKind.yaochuKinds {
            let c = counts[k]
            if c == 0 { return false }
            yaochuTotal += Int(c)
        }
        return yaochuTotal == 14 && counts.total == 14
    }

    static func decompose(_ counts: TileCounts, meldCount: Int) -> AgariResult {
        let neededSets = 4 - meldCount
        var uniqueForms = Set<[Group]>()
        var current: [Group] = []
        current.reserveCapacity(neededSets + 1)

        var working = counts
        for p in 0..<34 where working[p] >= 2 {
            working[p] -= 2
            current.append(Group(kind: .pair, base: TileKind(unchecked: UInt8(p))))
            extractSets(&working, startIdx: 0, setsLeft: neededSets, current: &current, out: &uniqueForms)
            current.removeLast()
            working[p] += 2
        }

        return AgariResult(
            standardForms: Array(uniqueForms),
            isChiitoi: isChiitoi(counts, meldCount: meldCount),
            isKokushi: isKokushi(counts, meldCount: meldCount)
        )
    }

    static func isComplete(_ counts: TileCounts, meldCount: Int) -> Bool {
        if isChiitoi(counts, meldCount: meldCount) || isKokushi(counts, meldCount: meldCount) {
            return true
        }
        let neededSets = 4 - meldCount
        var working = counts
        for p in 0..<34 where working[p] >= 2 {
            working[p] -= 2
            if canExtractSets(&working, startIdx: 0, setsLeft: neededSets) {
                return true
            }
            working[p] += 2
        }
        return false
    }

    private static func extractSets(
        _ counts: inout TileCounts,
        startIdx: Int,
        setsLeft: Int,
        current: inout [Group],
        out: inout Set<[Group]>
    ) {
        if setsLeft == 0 {
            out.insert(current.sorted())
            return
        }
        var idx = startIdx
        while idx < 34 && counts[idx] == 0 {
            idx += 1
        }
        guard idx < 34 else { return }

        let kind = TileKind(unchecked: UInt8(idx))
        if counts[idx] >= 3 {
            counts[idx] -= 3
            current.append(Group(kind: .triplet, base: kind))
            extractSets(&counts, startIdx: idx, setsLeft: setsLeft - 1, current: &current, out: &out)
            current.removeLast()
            counts[idx] += 3
        }
        if idx < 27 && (idx % 9) <= 6 && counts[idx + 1] > 0 && counts[idx + 2] > 0 {
            counts[idx] -= 1
            counts[idx + 1] -= 1
            counts[idx + 2] -= 1
            current.append(Group(kind: .sequence, base: kind))
            extractSets(&counts, startIdx: idx, setsLeft: setsLeft - 1, current: &current, out: &out)
            current.removeLast()
            counts[idx] += 1
            counts[idx + 1] += 1
            counts[idx + 2] += 1
        }
    }

    private static func canExtractSets(
        _ counts: inout TileCounts,
        startIdx: Int,
        setsLeft: Int
    ) -> Bool {
        if setsLeft == 0 { return true }
        var idx = startIdx
        while idx < 34 && counts[idx] == 0 {
            idx += 1
        }
        guard idx < 34 else { return false }

        if counts[idx] >= 3 {
            counts[idx] -= 3
            if canExtractSets(&counts, startIdx: idx, setsLeft: setsLeft - 1) {
                counts[idx] += 3
                return true
            }
            counts[idx] += 3
        }
        if idx < 27 && (idx % 9) <= 6 && counts[idx + 1] > 0 && counts[idx + 2] > 0 {
            counts[idx] -= 1
            counts[idx + 1] -= 1
            counts[idx + 2] -= 1
            if canExtractSets(&counts, startIdx: idx, setsLeft: setsLeft - 1) {
                counts[idx] += 1
                counts[idx + 1] += 1
                counts[idx + 2] += 1
                return true
            }
            counts[idx] += 1
            counts[idx + 1] += 1
            counts[idx + 2] += 1
        }
        return false
    }
}
