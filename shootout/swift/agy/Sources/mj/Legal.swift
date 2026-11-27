import Foundation

enum SeatRelation: String, Sendable {
    case kamicha
    case toimen
    case shimocha
}

enum LegalTrigger: Sendable {
    case draw(Tile)
    case discard(Tile, from: SeatRelation)
    case called(Meld, took: Tile)
}

struct LegalRequest: Sendable {
    let hand: HandTiles
    let melds: [Meld]
    let seat: Wind
    let round: Wind
    let dora: [Tile]
    let ura: [Tile]
    let honba: Int
    let flags: ScoreFlags
    let riichi: Bool
    let furiten: Bool
    let wall: Int
    let first: Bool
    let kans: Int
    let trigger: LegalTrigger
}

enum Legal {
    static func actions(_ req: LegalRequest) -> [String] {
        var result: [String] = []
        switch req.trigger {
        case .called(let meld, let took):
            let forbidden = kuikaeForbiddenKinds(meld: meld, took: took.kind)
            for tile in req.hand.distinctTiles() {
                if !forbidden.contains(tile.kind) {
                    result.append("discard:\(tile)")
                }
            }

        case .draw(let drawn):
            var fullHand = req.hand
            fullHand.add(drawn)

            // Tsumo check
            var scoreFlags = req.flags
            if req.riichi { scoreFlags.insert(.riichi) }
            let scoreReq = ScoreRequest(
                hand: req.hand,
                melds: req.melds,
                win: drawn,
                by: .tsumo,
                seat: req.seat,
                round: req.round,
                dora: req.dora,
                ura: req.ura,
                honba: req.honba,
                flags: scoreFlags
            )
            if case .scored = Scorer.score(scoreReq) {
                result.append("tsumo")
            }

            if req.riichi {
                result.append("discard:\(drawn)")
                if req.wall >= 1 && req.kans < 4 && fullHand.counts[drawn.kind] == 4 {
                    if canRiichiAnkan(handBeforeDraw: req.hand.counts, drawnKind: drawn.kind, melds: req.melds) {
                        result.append("ankan:\(drawn.kind)")
                    }
                }
            } else {
                let distinct = fullHand.distinctTiles()
                for tile in distinct {
                    result.append("discard:\(tile)")
                }

                // Riichi declaration check
                let isClosed = req.melds.allSatisfy(\.isClosed)
                if isClosed && req.wall >= 4 {
                    for tile in distinct {
                        var rem = fullHand
                        rem.remove(tile)
                        let w = Shanten.computeWaits(rem.counts, melds: req.melds)
                        if w.shanten == 0 && w.count > 0 {
                            result.append("riichi:\(tile)")
                        }
                    }
                }

                // Ankan & Kakan
                if req.wall >= 1 && req.kans < 4 {
                    for i in 0..<34 where fullHand.counts[i] == 4 {
                        result.append("ankan:\(TileKind(unchecked: UInt8(i)))")
                    }
                    for m in req.melds where m.kind == .pon {
                        if fullHand.counts[m.baseKind] > 0 {
                            let isRed = !m.baseKind.isHonor && m.baseKind.rank == 5 && fullHand.hasRed(suit: m.baseKind.suit)
                            let tile = Tile(kind: m.baseKind, isRed: isRed)
                            result.append("kakan:\(tile)")
                        }
                    }
                }

                // Kyuushu kyuuhai
                if req.first {
                    var yaochuKinds = 0
                    for k in TileKind.yaochuKinds where fullHand.counts[k] > 0 {
                        yaochuKinds += 1
                    }
                    if yaochuKinds >= 9 {
                        result.append("kyuushu")
                    }
                }
            }

        case .discard(let discarded, let from):
            result.append("pass")

            if req.flags.contains(.ankanRob) {
                if !req.furiten && req.melds.isEmpty {
                    var c = req.hand.counts
                    c.add(discarded.kind)
                    if Agari.isKokushi(c, meldCount: 0) {
                        result.append("ron")
                    }
                }
            } else if req.flags.contains(.chankan) {
                if !req.furiten {
                    var scoreFlags = req.flags
                    if req.riichi { scoreFlags.insert(.riichi) }
                    let scoreReq = ScoreRequest(
                        hand: req.hand,
                        melds: req.melds,
                        win: discarded,
                        by: .ron,
                        seat: req.seat,
                        round: req.round,
                        dora: req.dora,
                        ura: req.ura,
                        honba: req.honba,
                        flags: scoreFlags
                    )
                    if case .scored = Scorer.score(scoreReq) {
                        result.append("ron")
                    }
                }
            } else {
                // Normal discard: ron
                if !req.furiten {
                    var scoreFlags = req.flags
                    if req.riichi { scoreFlags.insert(.riichi) }
                    let scoreReq = ScoreRequest(
                        hand: req.hand,
                        melds: req.melds,
                        win: discarded,
                        by: .ron,
                        seat: req.seat,
                        round: req.round,
                        dora: req.dora,
                        ura: req.ura,
                        honba: req.honba,
                        flags: scoreFlags
                    )
                    if case .scored = Scorer.score(scoreReq) {
                        result.append("ron")
                    }
                }

                // Calls: only when not in riichi and wall >= 1
                if !req.riichi && req.wall >= 1 {
                    let dk = discarded.kind

                    // Daiminkan
                    if req.kans < 4 && req.hand.counts[dk] >= 3 {
                        result.append("kan:\(dk)")
                    }

                    // Pon
                    if req.hand.counts[dk] >= 2 {
                        let hasRed = !dk.isHonor && dk.rank == 5 && req.hand.hasRed(suit: dk.suit)
                        let plain = req.hand.plainCount(of: dk)
                        if hasRed {
                            if plain >= 1 {
                                result.append("pon:\(TileFormat.formatTileList([Tile(kind: dk, isRed: true), Tile(kind: dk, isRed: false)]))")
                            }
                            if plain >= 2 {
                                result.append("pon:\(TileFormat.formatTileList([Tile(kind: dk, isRed: false), Tile(kind: dk, isRed: false)]))")
                            }
                        } else {
                            result.append("pon:\(TileFormat.formatTileList([Tile(kind: dk, isRed: false), Tile(kind: dk, isRed: false)]))")
                        }
                    }

                    // Chi (kamicha only, numbered suits only)
                    if from == .kamicha && !dk.isHonor {
                        let suit = dk.suit
                        let r = Int(dk.rank)
                        let patterns: [(Int, Int, Int)] = [
                            (r - 2, r - 1, r - 2), // base = r - 2
                            (r - 1, r + 1, r - 1), // base = r - 1
                            (r + 1, r + 2, r),     // base = r
                        ]
                        for (r1, r2, baseRank) in patterns {
                            guard r1 >= 1 && r1 <= 9 && r2 >= 1 && r2 <= 9 else { continue }
                            let k1 = TileKind(suit: suit, rank: UInt8(r1))!
                            let k2 = TileKind(suit: suit, rank: UInt8(r2))!
                            guard req.hand.counts[k1] > 0 && req.hand.counts[k2] > 0 else { continue }

                            let baseKind = TileKind(suit: suit, rank: UInt8(baseRank))!
                            let forbidden = kuikaeForbiddenKindsForChi(baseKind: baseKind, took: dk)

                            // Check if any tile left in hand after removing k1 and k2 is not forbidden
                            var remCounts = req.hand.counts
                            remCounts.remove(k1)
                            remCounts.remove(k2)
                            var hasLegalDiscard = false
                            for i in 0..<34 where remCounts[i] > 0 {
                                if !forbidden.contains(TileKind(unchecked: UInt8(i))) {
                                    hasLegalDiscard = true
                                    break
                                }
                            }
                            guard hasLegalDiscard else { continue }

                            let opts1 = tileVariants(in: req.hand, kind: k1)
                            let opts2 = tileVariants(in: req.hand, kind: k2)
                            for t1 in opts1 {
                                for t2 in opts2 {
                                    result.append("chi:\(TileFormat.formatTileList([t1, t2]))")
                                }
                            }
                        }
                    }
                }
            }
        }

        result.sort()
        return result
    }

    private static func tileVariants(in hand: HandTiles, kind: TileKind) -> [Tile] {
        if !kind.isHonor && kind.rank == 5 && hand.hasRed(suit: kind.suit) {
            var res = [Tile(kind: kind, isRed: true)]
            if hand.plainCount(of: kind) > 0 {
                res.append(Tile(kind: kind, isRed: false))
            }
            return res
        }
        return [Tile(kind: kind, isRed: false)]
    }

    private static func kuikaeForbiddenKinds(meld: Meld, took: TileKind) -> Set<TileKind> {
        switch meld.kind {
        case .pon:
            return [took]
        case .chi:
            return kuikaeForbiddenKindsForChi(baseKind: meld.baseKind, took: took)
        default:
            return []
        }
    }

    private static func kuikaeForbiddenKindsForChi(baseKind: TileKind, took: TileKind) -> Set<TileKind> {
        var forbidden: Set<TileKind> = [took]
        if took == baseKind {
            if let other = baseKind.offset(3) {
                forbidden.insert(other)
            }
        } else if took.rank == baseKind.rank + 2 {
            if let other = baseKind.offset(-1) {
                forbidden.insert(other)
            }
        }
        return forbidden
    }

    private static func canRiichiAnkan(handBeforeDraw: TileCounts, drawnKind: TileKind, melds: [Meld]) -> Bool {
        let waitsBefore = Shanten.structuralTenpaiWaits(handBeforeDraw, meldCount: melds.count)
        var afterCounts = handBeforeDraw
        afterCounts.remove(drawnKind, count: 3)
        let waitsAfter = Shanten.structuralTenpaiWaits(afterCounts, meldCount: melds.count + 1)
        return waitsBefore == waitsAfter
    }
}
