enum Turn {
    case draw(Tile)
    case discard(Tile, fromLeft: Bool)
    case afterCall(Meld, took: Tile)
}

struct LegalContext {
    var score: ScoreContext
    let riichi: Bool
    let furiten: Bool
    let wall: Int
    let first: Bool
    let kans: Int

    var canKan: Bool { wall >= 1 && kans < 4 }
}

private func kuikae(took: Int, sequenceStart: Int?) -> Set<Int> {
    var forbidden: Set<Int> = [took]
    if let start = sequenceStart {
        if took == start, start % 9 <= 5 { forbidden.insert(start + 3) }
        if took == start + 2, start % 9 >= 1 { forbidden.insert(start - 1) }
    }
    return forbidden
}

func legal(_ hand: Hand, turn: Turn, context: LegalContext) -> [String] {
    var scoreContext = context.score
    if context.riichi { scoreContext.flags.insert("riichi") }
    var actions: Set<String> = []

    switch turn {
    case .afterCall(let meld, let took):
        let forbidden = kuikae(took: took.kind, sequenceStart: meld.type == .chi ? meld.group.kind : nil)
        for tile in hand.tiles where !forbidden.contains(tile.kind) {
            actions.insert("discard:\(tile.text)")
        }

    case .draw(let draw):
        let tiles = hand.tiles + [draw]
        let distinct = Set(tiles)
        let concealed = counts(tiles)
        for tile in context.riichi ? [draw] : Array(distinct) {
            actions.insert("discard:\(tile.text)")
        }
        if score(hand, win: draw, tsumo: true, context: scoreContext).canWin {
            actions.insert("tsumo")
        }
        if context.first && orphans.count(where: { concealed[$0] > 0 }) >= 9 {
            actions.insert("kyuushu")
        }

        if hand.closed && !context.riichi && context.wall >= 4 {
            let search = ShapeSearch()
            var tenpai: [Int: Bool] = [:]
            for tile in distinct {
                if tenpai[tile.kind] == nil {
                    var afterDiscard = tiles
                    afterDiscard.remove(at: afterDiscard.firstIndex(of: tile)!)
                    let reduced = Hand(tiles: afterDiscard, melds: hand.melds)
                    let distance = search.shanten(counts(afterDiscard), meldCount: hand.melds.count).minimum
                    tenpai[tile.kind] = distance == 0 && !search.liveImprovements(reduced, from: 0).isEmpty
                }
                if tenpai[tile.kind] == true { actions.insert("riichi:\(tile.text)") }
            }
        }

        if context.canKan {
            for kind in kinds where concealed[kind] == 4 {
                if context.riichi {
                    guard kind == draw.kind else { continue }
                    let meld = Meld(type: .closedKan, tiles: tiles.filter { $0.kind == kind })
                    let afterKan = Hand(tiles: tiles.filter { $0.kind != kind }, melds: hand.melds + [meld])
                    guard structuralWaits(hand) == structuralWaits(afterKan) else { continue }
                }
                actions.insert("ankan:\(Tile(kind: kind).text)")
            }
            if !context.riichi {
                let pons = Set(hand.melds.filter { $0.type == .pon }.map { $0.group.kind })
                for tile in distinct where pons.contains(tile.kind) {
                    actions.insert("kakan:\(tile.text)")
                }
            }
        }

    case .discard(let discard, let fromLeft):
        actions.insert("pass")
        let ankanRob = scoreContext.flags.contains("ankan_rob")
        if !context.furiten {
            let canRon: Bool
            if ankanRob {
                let forms = winningForms(counts(hand.tiles + [discard]), meldCount: hand.melds.count)
                canRon = forms.contains { if case .kokushi = $0 { return true }; return false }
            } else {
                canRon = score(hand, win: discard, tsumo: false, context: scoreContext).canWin
            }
            if canRon { actions.insert("ron") }
        }
        if ankanRob || scoreContext.flags.contains("chankan") || context.riichi || context.wall < 1 {
            break
        }

        let kind = discard.kind
        if context.canKan && hand.tiles.count(where: { $0.kind == kind }) == 3 {
            actions.insert("kan:\(Tile(kind: kind).text)")
        }
        for first in hand.tiles.indices {
            for second in hand.tiles.indices.dropFirst(first + 1) {
                let a = hand.tiles[first]
                let b = hand.tiles[second]
                if a.kind == kind && b.kind == kind {
                    if hand.tiles.contains(where: { $0.kind != kind }) {
                        actions.insert("pon:\(formatTiles([a, b]))")
                    }
                } else if fromLeft && kind < 27 && a.kind / 9 == kind / 9 && b.kind / 9 == kind / 9 {
                    let ordered = [a.kind, b.kind, kind].sorted()
                    let start = ordered[0]
                    guard ordered == [start, start + 1, start + 2] else { continue }
                    let forbidden = kuikae(took: kind, sequenceStart: start)
                    if hand.tiles.indices.contains(where: {
                        $0 != first && $0 != second && !forbidden.contains(hand.tiles[$0].kind)
                    }) {
                        actions.insert("chi:\(formatTiles([a, b]))")
                    }
                }
            }
        }
    }
    return actions.sorted()
}
