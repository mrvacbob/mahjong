// The `legal` op, built from score and hand completion.

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

/// Kinds that may not be discarded right after taking `took` with `fromHand`.
func kuikaeForbidden(took: Kind, fromHand: [Kind]) -> Set<Kind> {
    var out: Set<Kind> = [took]
    let pair = fromHand.sorted()
    if pair.count == 2, pair[0].shifted(1) == pair[1] {
        // Took one end of a run whose other two tiles are adjacent: the far end too.
        if took < pair[0], let far = pair[1].shifted(1) { out.insert(far) }
        if took > pair[1], let far = pair[0].shifted(-1) { out.insert(far) }
    }
    return out
}

extension LegalRequest {
    /// The `legal` answer: distinct actions, sorted as strings.
    var actions: [String] {
        let out = switch situation {
        case .draw(let t): afterDraw(drawn: t)
        case .discard(let t, let kamicha): onDiscard(tile: t, fromKamicha: kamicha)
        case .called(let meld, let took): afterCall(meld: meld, took: took)
        }
        return Set(out).sorted()
    }

    /// Whether `score` accepts this hand winning on `tile`, with the situational
    /// flags `allowed` for this trigger.
    private func wins(_ tile: Tile, tsumo: Bool, allowed: Set<Flag>) -> Bool {
        var flags = flags.intersection(allowed)
        if inRiichi { flags.insert(.riichi) }
        let context = WinContext(seat: seat, round: round, tsumo: tsumo, flags: flags)
        return (try? score(ScoreRequest(hand: hand, melds: melds, win: tile, context: context))) != nil
    }

    // MARK: own draw

    private func afterDraw(drawn: Tile) -> [String] {
        let tiles = hand + [drawn]
        let counts = Counts(tiles)
        var out: [String] = []

        let discards = inRiichi ? [drawn] : tiles.distinct
        out += discards.map { "discard:\($0)" }

        if wins(drawn, tsumo: true, allowed: [.rinshan, .haitei, .tenhou, .chiihou]) {
            out.append("tsumo")
        }

        if !inRiichi && melds.isClosed && wall >= 4 {
            // Tenpai after the discard, on a wait with a copy outside hand and melds.
            let meldKinds = Counts(melds.tiles)
            for k in counts.kinds {
                let rest = counts.removing(k)
                let tenpai = Kind.all.contains { w in
                    rest[w] + meldKinds[w] < 4 && isComplete(rest.adding(w), meldCount: melds.count)
                }
                if tenpai { out += tiles.distinct.filter { $0.kind == k }.map { "riichi:\($0)" } }
            }
        }

        if wall >= 1 && kans < 4 {
            for k in counts.kinds where counts[k] == 4 {
                if inRiichi {
                    // The kan must use the drawn tile and keep the structural waits.
                    guard k == drawn.kind else { continue }
                    var after = counts
                    after[k] = 0
                    let before = completingKinds(Counts(hand), meldCount: melds.count)
                    let now = completingKinds(after, meldCount: melds.count + 1)
                    guard before == now else { continue }
                }
                out.append("ankan:\(Tile(k))")
            }
            if !inRiichi {
                for m in melds where m.kind == .pon {
                    for t in tiles.distinct where t.kind == m.base { out.append("kakan:\(t)") }
                }
            }
        }

        if firstTurn && Kind.yaochu.count(where: { counts[$0] > 0 }) >= 9 {
            out.append("kyuushu")
        }
        return out
    }

    // MARK: another seat's discard

    private func onDiscard(tile: Tile, fromKamicha: Bool) -> [String] {
        var out = ["pass"]
        let robbing = flags.contains(.chankan) || flags.contains(.ankan_rob)

        if !furiten {
            let canRon: Bool
            if flags.contains(.ankan_rob) {
                canRon = melds.isEmpty && isKokushi(Counts(hand + [tile]))
            } else {
                canRon = wins(tile, tsumo: false, allowed: [.houtei, .chankan])
            }
            if canRon { out.append("ron") }
        }
        if robbing || inRiichi || wall < 1 { return out }

        let k = tile.kind
        // A call is offered only if some discard remains allowed afterwards.
        func leavesDiscard(_ used: [Tile], forbidden: Set<Kind>) -> Bool {
            var rest = hand
            for t in used { rest = rest.removingOne(t) }
            return rest.contains { !forbidden.contains($0.kind) }
        }

        if fromKamicha {
            for (a, b) in [(-2, -1), (-1, 1), (1, 2)] {
                guard let ka = k.shifted(a), let kb = k.shifted(b) else { continue }
                for ta in hand.distinct where ta.kind == ka {
                    for tb in hand.distinct where tb.kind == kb {
                        let forbidden = kuikaeForbidden(took: k, fromHand: [ka, kb])
                        if leavesDiscard([ta, tb], forbidden: forbidden) {
                            out.append("chi:\(format([ta, tb]))")
                        }
                    }
                }
            }
        }

        let same = hand.filter { $0.kind == k }
        let plain = same.count { !$0.isRed }
        let red = same.count - plain
        var pons: [[Tile]] = []
        if plain >= 2 { pons.append([Tile(k), Tile(k)]) }
        if red >= 1 && plain >= 1 { pons.append([Tile(k, red: true), Tile(k)]) }
        for p in pons where leavesDiscard(p, forbidden: [k]) {
            out.append("pon:\(format(p))")
        }
        if same.count == 3 && kans < 4 { out.append("kan:\(Tile(k))") }
        return out
    }

    // MARK: after this seat's own chi or pon

    private func afterCall(meld: Meld, took: Tile) -> [String] {
        let k = took.kind
        let forbidden = meld.kind == .chi
            ? kuikaeForbidden(took: k, fromHand: meld.tiles.map(\.kind).filter { $0 != k })
            : [k]
        return hand.distinct.filter { !forbidden.contains($0.kind) }.map { "discard:\($0)" }
    }
}
