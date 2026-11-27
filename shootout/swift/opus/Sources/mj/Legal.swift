// The `legal` op, built from score, shanten and waits.

enum Situation {
    case draw(Tile)
    case discard(Tile, fromKamicha: Bool)
    case called(Meld, took: Tile)
}

struct LegalRequest {
    var hand: [Tile]
    var melds: [Meld]
    var situation: Situation
    var seat: Wind = .east
    var round: Wind = .east
    var flags: Set<Flag> = []
    var inRiichi = false
    var furiten = false
    var wall = 70
    var firstTurn = false
    var kans = 0
}

extension Array where Element == Tile {
    /// This list without one copy of `t` (exact tile).
    func removingOne(_ t: Tile) -> [Tile] {
        var out = self
        if let i = out.firstIndex(of: t) { out.remove(at: i) }
        return out
    }
    var distinct: [Tile] { Array(Set(self)) }
}

/// Kinds that may not be discarded right after taking `took` with `fromHand`.
func kuikaeForbidden(took: Kind, fromHand: [Kind]) -> Set<Kind> {
    var out: Set<Kind> = [took]
    let pair = fromHand.sorted()
    if pair.count == 2, pair[0] != pair[1], pair[0].shifted(1) == pair[1] {
        // Took one end of a run whose other two tiles are adjacent: the far end too.
        if took < pair[0], let far = pair[1].shifted(1) { out.insert(far) }
        if took > pair[1], let far = pair[0].shifted(-1) { out.insert(far) }
    }
    return out
}

struct LegalEngine {
    let shanten: ShantenCalculator

    func actions(_ q: LegalRequest) -> [String] {
        var out: [String]
        switch q.situation {
        case .draw(let t): out = afterDraw(q, drawn: t)
        case .discard(let t, let kamicha): out = onDiscard(q, tile: t, fromKamicha: kamicha)
        case .called(let meld, let took): out = afterCall(q, meld: meld, took: took)
        }
        return Set(out).sorted()  // distinct actions, sorted as strings
    }

    private func context(_ q: LegalRequest, tsumo: Bool, allowed: Set<Flag>) -> WinContext {
        var flags = q.flags.intersection(allowed)
        if q.inRiichi { flags.insert(.riichi) }
        return WinContext(seat: q.seat, round: q.round, tsumo: tsumo, flags: flags)
    }

    private func wins(_ q: LegalRequest, tile: Tile, tsumo: Bool, allowed: Set<Flag>) -> Bool {
        let req = ScoreRequest(hand: q.hand, melds: q.melds, win: tile,
                               context: context(q, tsumo: tsumo, allowed: allowed))
        return (try? score(req)) != nil
    }

    // MARK: own draw

    private func afterDraw(_ q: LegalRequest, drawn: Tile) -> [String] {
        let tiles = q.hand + [drawn]
        let counts = Counts(tiles)
        var out: [String] = []

        let discards = q.inRiichi ? [drawn] : tiles.distinct
        out += discards.map { "discard:\($0)" }

        if wins(q, tile: drawn, tsumo: true, allowed: [.rinshan, .haitei, .tenhou, .chiihou]) {
            out.append("tsumo")
        }

        let closed = q.melds.allSatisfy { !$0.isOpen }
        if !q.inRiichi && closed && q.wall >= 4 {
            for t in tiles.distinct {
                let rest = Counts(tiles.removingOne(t))
                let w = shanten.waits(rest, melds: q.melds)
                if w.shanten == 0 && w.count > 0 { out.append("riichi:\(t)") }
            }
        }

        if q.wall >= 1 && q.kans < 4 {
            for k in counts.kinds where counts[k] == 4 {
                if q.inRiichi {
                    guard k == drawn.kind else { continue }
                    var after = counts
                    after[k] = 0
                    let before = shanten.structuralWaits(Counts(q.hand), meldCount: q.melds.count)
                    let now = shanten.structuralWaits(after, meldCount: q.melds.count + 1)
                    guard before == now else { continue }
                }
                out.append("ankan:\(Tile(k))")
            }
            if !q.inRiichi {
                for m in q.melds where m.kind == .pon {
                    for t in tiles.distinct where t.kind == m.base { out.append("kakan:\(t)") }
                }
            }
        }

        if q.firstTurn && Kind.yaochu.filter({ counts[$0] > 0 }).count >= 9 {
            out.append("kyuushu")
        }
        return out
    }

    // MARK: another seat's discard

    private func onDiscard(_ q: LegalRequest, tile: Tile, fromKamicha: Bool) -> [String] {
        var out = ["pass"]
        let robbing = q.flags.contains(.chankan) || q.flags.contains(.ankan_rob)

        if !q.furiten {
            let canRon: Bool
            if q.flags.contains(.ankan_rob) {
                canRon = q.melds.isEmpty && isKokushi(Counts(q.hand + [tile]))
            } else {
                canRon = wins(q, tile: tile, tsumo: false, allowed: [.houtei, .chankan])
            }
            if canRon { out.append("ron") }
        }
        if robbing || q.inRiichi || q.wall < 1 { return out }

        let k = tile.kind
        // A call is offered only if some discard remains allowed afterwards.
        func leavesDiscard(_ used: [Tile], forbidden: Set<Kind>) -> Bool {
            var rest = q.hand
            for t in used { rest = rest.removingOne(t) }
            return rest.contains { !forbidden.contains($0.kind) }
        }

        if fromKamicha && !k.isHonor {
            for (a, b) in [(-2, -1), (-1, 1), (1, 2)] {
                guard let ka = k.shifted(a), let kb = k.shifted(b) else { continue }
                for ta in q.hand.distinct where ta.kind == ka {
                    for tb in q.hand.distinct where tb.kind == kb {
                        let forbidden = kuikaeForbidden(took: k, fromHand: [ka, kb])
                        if leavesDiscard([ta, tb], forbidden: forbidden) {
                            out.append("chi:\(format([ta, tb]))")
                        }
                    }
                }
            }
        }

        let same = q.hand.filter { $0.kind == k }
        let plain = same.filter { !$0.isRed }.count
        let red = same.count - plain
        var pons: [[Tile]] = []
        if plain >= 2 { pons.append([Tile(k), Tile(k)]) }
        if red >= 1 && plain >= 1 { pons.append([Tile(k, red: true), Tile(k)]) }
        for p in pons where leavesDiscard(p, forbidden: [k]) {
            out.append("pon:\(format(p))")
        }
        if same.count == 3 && q.kans < 4 { out.append("kan:\(Tile(k))") }
        return out
    }

    // MARK: after this seat's own chi or pon

    private func afterCall(_ q: LegalRequest, meld: Meld, took: Tile) -> [String] {
        var fromHand = meld.tiles.map(\.kind)
        fromHand.remove(at: fromHand.firstIndex(of: took.kind) ?? 0)
        let forbidden = meld.isChi
            ? kuikaeForbidden(took: took.kind, fromHand: fromHand)
            : [took.kind]
        return q.hand.distinct.filter { !forbidden.contains($0.kind) }.map { "discard:\($0)" }
    }
}
