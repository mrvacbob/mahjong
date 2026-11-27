import Foundation

struct ShantenResult: Sendable {
    let std: Int
    let chiitoi: Int?
    let kokushi: Int?

    var minShanten: Int {
        var m = std
        if let c = chiitoi, c < m { m = c }
        if let k = kokushi, k < m { m = k }
        return m
    }
}

struct WaitsResult: Sendable {
    let shanten: Int
    let tiles: [TileKind]
    let count: Int
}

enum Shanten {
    private struct SuitTable {
        // Index = sets (0...4), value = max taatsu (-1 if unreachable)
        var noHead: InlineArray<5, Int8> = InlineArray(repeating: -1)
        var withHead: InlineArray<5, Int8> = InlineArray(repeating: -1)
    }

    static func compute(_ counts: TileCounts, meldCount: Int) -> ShantenResult {
        let std = standardShanten(counts, meldCount: meldCount)
        if meldCount > 0 {
            return ShantenResult(std: std, chiitoi: nil, kokushi: nil)
        }
        let chiitoi = chiitoiShanten(counts)
        let kokushi = kokushiShanten(counts)
        return ShantenResult(std: std, chiitoi: chiitoi, kokushi: kokushi)
    }

    static func chiitoiShanten(_ counts: TileCounts) -> Int {
        var pairs = 0
        var kinds = 0
        for i in 0..<34 {
            let c = counts[i]
            if c >= 1 { kinds += 1 }
            if c >= 2 { pairs += 1 }
        }
        return 6 - pairs + max(0, 7 - kinds)
    }

    static func kokushiShanten(_ counts: TileCounts) -> Int {
        var unique = 0
        var hasPair = false
        for k in TileKind.yaochuKinds {
            let c = counts[k]
            if c >= 1 { unique += 1 }
            if c >= 2 { hasPair = true }
        }
        return 13 - unique - (hasPair ? 1 : 0)
    }

    static func standardShanten(_ counts: TileCounts, meldCount: Int) -> Int {
        let mTable = computeNumberedSuit(counts, offset: 0)
        let pTable = computeNumberedSuit(counts, offset: 9)
        let sTable = computeNumberedSuit(counts, offset: 18)
        let zTable = computeHonorSuit(counts)

        // Combine m + p, then + s, then + z.
        // State: bestNoHead[sets], bestWithHead[sets] for sets in 0...4 (concealed sets).
        var cur = combine(mTable, pTable)
        cur = combine(cur, sTable)
        cur = combine(cur, zTable)

        var best = 8
        for s in 0...4 {
            let totalSets = s + meldCount
            if totalSets > 4 { continue }
            let cap = 4 - totalSets

            let tNo = Int(cur.noHead[s])
            if tNo >= 0 {
                let val = 8 - 2 * totalSets - min(tNo, cap)
                if val < best { best = val }
            }

            let tWith = Int(cur.withHead[s])
            if tWith >= 0 {
                let val = 8 - 2 * totalSets - min(tWith, cap) - 1
                if val < best { best = val }
            }
        }
        return best
    }

    private static func combine(_ a: SuitTable, _ b: SuitTable) -> SuitTable {
        var out = SuitTable()
        for sa in 0...4 {
            let aNo = a.noHead[sa]
            let aWith = a.withHead[sa]
            if aNo < 0 && aWith < 0 { continue }
            for sb in 0...(4 - sa) {
                let s = sa + sb
                let bNo = b.noHead[sb]
                let bWith = b.withHead[sb]
                if aNo >= 0 && bNo >= 0 {
                    let t = aNo + bNo
                    if t > out.noHead[s] { out.noHead[s] = t }
                }
                if aWith >= 0 && bNo >= 0 {
                    let t = aWith + bNo
                    if t > out.withHead[s] { out.withHead[s] = t }
                }
                if aNo >= 0 && bWith >= 0 {
                    let t = aNo + bWith
                    if t > out.withHead[s] { out.withHead[s] = t }
                }
            }
        }
        return out
    }

    private static func computeNumberedSuit(_ counts: TileCounts, offset: Int) -> SuitTable {
        var c: InlineArray<9, UInt8> = InlineArray(repeating: 0)
        var total = 0
        for i in 0..<9 {
            let v = counts[offset + i]
            c[i] = v
            total += Int(v)
        }
        var table = SuitTable()
        if total == 0 {
            table.noHead[0] = 0
            return table
        }

        dfsNumbered(&c, idx: 0, sets: 0, best: &table.noHead)

        for h in 0..<9 where c[h] >= 2 {
            c[h] -= 2
            dfsNumbered(&c, idx: 0, sets: 0, best: &table.withHead)
            c[h] += 2
        }
        return table
    }

    private static func dfsNumbered(
        _ c: inout InlineArray<9, UInt8>,
        idx: Int,
        sets: Int,
        best: inout InlineArray<5, Int8>
    ) {
        var i = idx
        while i < 9 && c[i] == 0 {
            i += 1
        }
        if i == 9 {
            let t = Int8(maxTaatsuNumbered(c))
            if t > best[sets] {
                best[sets] = t
            }
            return
        }

        // Branch 1: 0 triplets at i, then 0..maxSeq sequences starting at i
        let maxSeq0: Int
        if i <= 6 {
            maxSeq0 = Int(min(c[i], min(c[i + 1], c[i + 2])))
        } else {
            maxSeq0 = 0
        }
        for q in 0...maxSeq0 {
            if sets + q > 4 { break }
            if q > 0 {
                let qu = UInt8(q)
                c[i] -= qu
                c[i + 1] -= qu
                c[i + 2] -= qu
            }
            dfsNumbered(&c, idx: i + 1, sets: sets + q, best: &best)
            if q > 0 {
                let qu = UInt8(q)
                c[i] += qu
                c[i + 1] += qu
                c[i + 2] += qu
            }
        }

        // Branch 2: 1 triplet at i, then 0..maxSeq sequences starting at i
        if c[i] >= 3 && sets + 1 <= 4 {
            c[i] -= 3
            let maxSeq1: Int
            if i <= 6 {
                maxSeq1 = Int(min(c[i], min(c[i + 1], c[i + 2])))
            } else {
                maxSeq1 = 0
            }
            for q in 0...maxSeq1 {
                if sets + 1 + q > 4 { break }
                if q > 0 {
                    let qu = UInt8(q)
                    c[i] -= qu
                    c[i + 1] -= qu
                    c[i + 2] -= qu
                }
                dfsNumbered(&c, idx: i + 1, sets: sets + 1 + q, best: &best)
                if q > 0 {
                    let qu = UInt8(q)
                    c[i] += qu
                    c[i + 1] += qu
                    c[i + 2] += qu
                }
            }
            c[i] += 3
        }
    }

    /// Optimal greedy left-to-right taatsu extraction on remaining tiles of a single numbered suit.
    private static func maxTaatsuNumbered(_ input: InlineArray<9, UInt8>) -> Int {
        var c = input
        var taatsu = 0
        for i in 0..<9 {
            while c[i] > 0 {
                if c[i] >= 2 {
                    c[i] -= 2
                    taatsu += 1
                } else if i + 1 < 9 && c[i + 1] > 0 {
                    c[i] -= 1
                    c[i + 1] -= 1
                    taatsu += 1
                } else if i + 2 < 9 && c[i + 2] > 0 {
                    c[i] -= 1
                    c[i + 2] -= 1
                    taatsu += 1
                } else {
                    break
                }
            }
        }
        return taatsu
    }

    private static func computeHonorSuit(_ counts: TileCounts) -> SuitTable {
        var c: InlineArray<7, UInt8> = InlineArray(repeating: 0)
        for i in 0..<7 {
            c[i] = counts[27 + i]
        }
        var table = SuitTable()

        var sets = 0
        var taatsu = 0
        for i in 0..<7 {
            let v = Int(c[i])
            sets += v / 3
            taatsu += (v % 3) / 2
        }
        if sets <= 4 {
            table.noHead[sets] = Int8(taatsu)
        }

        for h in 0..<7 where c[h] >= 2 {
            c[h] -= 2
            var s = 0
            var t = 0
            for i in 0..<7 {
                let v = Int(c[i])
                s += v / 3
                t += (v % 3) / 2
            }
            if s <= 4 && Int8(t) > table.withHead[s] {
                table.withHead[s] = Int8(t)
            }
            c[h] += 2
        }
        return table
    }

    static func computeWaits(_ hand: TileCounts, melds: [Meld]) -> WaitsResult {
        let meldCount = melds.count
        let base = compute(hand, meldCount: meldCount).minShanten

        var used = hand
        for m in melds {
            for t in m.tiles {
                used.add(t.kind)
            }
        }

        var working = hand
        var waits: [TileKind] = []
        var totalRemaining = 0

        for i in 0..<34 {
            let remaining = 4 - Int(used[i])
            if remaining <= 0 { continue }
            working[i] += 1
            let nextShanten = compute(working, meldCount: meldCount).minShanten
            working[i] -= 1
            if nextShanten < base {
                waits.append(TileKind(unchecked: UInt8(i)))
                totalRemaining += remaining
            }
        }
        return WaitsResult(shanten: base, tiles: waits, count: totalRemaining)
    }

    /// Structural tenpai waits (ignoring tile availability), used for riichi ankan validation.
    static func structuralTenpaiWaits(_ hand: TileCounts, meldCount: Int) -> Set<TileKind> {
        var working = hand
        var waits = Set<TileKind>()
        for i in 0..<34 {
            working[i] += 1
            if Agari.isComplete(working, meldCount: meldCount) {
                waits.insert(TileKind(unchecked: UInt8(i)))
            }
            working[i] -= 1
        }
        return waits
    }
}
