import Foundation

@main
struct MJRunner {
    static func main() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            print(handleLine(trimmed))
        }
    }

    static func handleLine(_ line: String) -> String {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return "\(parts.first ?? "?") error=bad_input"
        }
        let id = parts[0]
        let op = parts[1]

        var kv: [Substring: Substring] = [:]
        kv.reserveCapacity(parts.count - 2)
        for token in parts.dropFirst(2) {
            if let eq = token.firstIndex(of: "=") {
                let k = token[..<eq]
                let v = token[token.index(after: eq)...]
                kv[k] = v
            }
        }

        switch op {
        case "agari":
            return handleAgari(id: id, kv: kv)
        case "shanten":
            return handleShanten(id: id, kv: kv)
        case "waits":
            return handleWaits(id: id, kv: kv)
        case "score":
            return handleScore(id: id, kv: kv)
        case "legal":
            return handleLegal(id: id, kv: kv)
        default:
            return "\(id) error=unknown_op"
        }
    }

    private static func parseCommonHandAndMelds(_ kv: [Substring: Substring]) -> (HandTiles, [Meld])? {
        guard let handStr = kv["hand"], let tiles = TileFormat.parseTileList(handStr) else { return nil }
        let meldsStr = kv["melds"] ?? "-"
        guard let melds = TileFormat.parseMelds(meldsStr) else { return nil }
        return (HandTiles(tiles: tiles), melds)
    }

    private static func handleAgari(id: Substring, kv: [Substring: Substring]) -> String {
        guard let (hand, melds) = parseCommonHandAndMelds(kv) else {
            return "\(id) error=bad_input"
        }
        let res = Agari.decompose(hand.counts, meldCount: melds.count)
        if !res.isWin {
            return "\(id) win=0"
        }
        let forms = res.formattedForms().joined(separator: ";")
        return "\(id) win=1 forms=\(forms)"
    }

    private static func handleShanten(id: Substring, kv: [Substring: Substring]) -> String {
        guard let (hand, melds) = parseCommonHandAndMelds(kv) else {
            return "\(id) error=bad_input"
        }
        let res = Shanten.compute(hand.counts, meldCount: melds.count)
        let chiitoiStr = res.chiitoi.map(String.init) ?? "x"
        let kokushiStr = res.kokushi.map(String.init) ?? "x"
        return "\(id) std=\(res.std) chiitoi=\(chiitoiStr) kokushi=\(kokushiStr) min=\(res.minShanten)"
    }

    private static func handleWaits(id: Substring, kv: [Substring: Substring]) -> String {
        guard let (hand, melds) = parseCommonHandAndMelds(kv) else {
            return "\(id) error=bad_input"
        }
        let res = Shanten.computeWaits(hand.counts, melds: melds)
        let tilesStr = TileFormat.formatTileKinds(res.tiles)
        return "\(id) shanten=\(res.shanten) tiles=\(tilesStr) count=\(res.count)"
    }

    private static func handleScore(id: Substring, kv: [Substring: Substring]) -> String {
        guard let (hand, melds) = parseCommonHandAndMelds(kv),
              let winStr = kv["win"], let winTile = Tile.parse(winStr),
              let byStr = kv["by"], let by = WinMethod(rawValue: String(byStr)),
              let seat = Wind(string: kv["seat"] ?? "E"),
              let round = Wind(string: kv["round"] ?? "E"),
              let dora = TileFormat.parseTileList(kv["dora"] ?? "-"),
              let ura = TileFormat.parseTileList(kv["ura"] ?? "-"),
              let honba = Int(kv["honba"] ?? "0"),
              let flags = ScoreFlags.parse(kv["flags"] ?? "-")
        else {
            return "\(id) error=bad_input"
        }

        let req = ScoreRequest(
            hand: hand,
            melds: melds,
            win: winTile,
            by: by,
            seat: seat,
            round: round,
            dora: dora,
            ura: ura,
            honba: honba,
            flags: flags
        )
        switch Scorer.score(req) {
        case .notAgari:
            return "\(id) error=not_agari"
        case .noYaku:
            return "\(id) error=no_yaku"
        case .scored(let s):
            if s.isYakuman {
                return "\(id) yaku=\(s.yakuString) yakuman=\(s.yakumanMultiple) pay=\(s.payString) total=\(s.total)"
            } else {
                return "\(id) yaku=\(s.yakuString) han=\(s.han) fu=\(s.fu) pay=\(s.payString) total=\(s.total)"
            }
        }
    }

    private static func handleLegal(id: Substring, kv: [Substring: Substring]) -> String {
        guard let (hand, melds) = parseCommonHandAndMelds(kv),
              let seat = Wind(string: kv["seat"] ?? "E"),
              let round = Wind(string: kv["round"] ?? "E"),
              let dora = TileFormat.parseTileList(kv["dora"] ?? "-"),
              let ura = TileFormat.parseTileList(kv["ura"] ?? "-"),
              let honba = Int(kv["honba"] ?? "0"),
              let flags = ScoreFlags.parse(kv["flags"] ?? "-"),
              let wall = Int(kv["wall"] ?? "70"),
              let kans = Int(kv["kans"] ?? "0")
        else {
            return "\(id) error=bad_input"
        }

        let riichi = (kv["riichi"] ?? "0") == "1"
        let furiten = (kv["furiten"] ?? "0") == "1"
        let first = (kv["first"] ?? "0") == "1"

        let trigger: LegalTrigger
        if let drawStr = kv["draw"], let t = Tile.parse(drawStr) {
            trigger = .draw(t)
        } else if let discStr = kv["discard"], let t = Tile.parse(discStr),
                  let fromStr = kv["from"], let from = SeatRelation(rawValue: String(fromStr)) {
            trigger = .discard(t, from: from)
        } else if let calledStr = kv["called"], let m = Meld.parse(calledStr),
                  let tookStr = kv["took"], let took = Tile.parse(tookStr) {
            trigger = .called(m, took: took)
        } else {
            return "\(id) error=bad_input"
        }

        let req = LegalRequest(
            hand: hand,
            melds: melds,
            seat: seat,
            round: round,
            dora: dora,
            ura: ura,
            honba: honba,
            flags: flags,
            riichi: riichi,
            furiten: furiten,
            wall: wall,
            first: first,
            kans: kans,
            trigger: trigger
        )
        let actions = Legal.actions(req)
        return "\(id) actions=\(actions.joined(separator: ","))"
    }
}
