private struct Request {
    let op: Substring
    let fields: [Substring: Substring]

    func require(_ key: Substring) throws -> Substring {
        guard let value = fields[key] else { throw InputError.malformed }
        return value
    }

    func tile(_ key: Substring) throws -> Tile {
        let tiles = try parseTiles(require(key))
        guard tiles.count == 1, let tile = tiles.first else { throw InputError.malformed }
        return tile
    }

    func integer(_ key: Substring, default fallback: Int) throws -> Int {
        guard let value = fields[key] else { return fallback }
        guard let number = Int(value), number >= 0, number <= Int.max / 1000 else {
            throw InputError.malformed
        }
        return number
    }

    func scoreContext() throws -> ScoreContext {
        func wind(_ key: Substring) throws -> Int {
            let value = fields[key] ?? "E"
            guard let index = ["E", "S", "W", "N"].firstIndex(of: value) else {
                throw InputError.malformed
            }
            return 27 + index
        }
        let flags = fields["flags"] ?? "-"
        return try ScoreContext(
            seat: wind("seat"), round: wind("round"),
            dora: parseTiles(fields["dora"] ?? "-"), ura: parseTiles(fields["ura"] ?? "-"),
            honba: integer("honba", default: 0), flags: flags == "-" ? [] : Set(flags.split(separator: ","))
        )
    }

    func response() throws -> String {
        let tiles = try parseTiles(require("hand"))
        let meldText = fields["melds"] ?? "-"
        let melds = try meldText == "-" ? [] : meldText.split(separator: ",").map(parseMeld)
        let hand = Hand(tiles: tiles, melds: melds)
        let concealed = counts(tiles)
        let shortCount = 13 - 3 * melds.count
        guard melds.count <= 4, counts(hand.allTiles).allSatisfy({ $0 <= 4 }) else {
            throw InputError.malformed
        }
        switch op {
        case "agari":
            let forms = Set(winningForms(concealed, meldCount: melds.count).map(\.text)).sorted()
            return forms.isEmpty ? "win=0" : "win=1 forms=" + forms.joined(separator: ";")
        case "shanten":
            guard tiles.count == shortCount || tiles.count == shortCount + 1 else {
                throw InputError.malformed
            }
            return ShapeSearch().shanten(concealed, meldCount: melds.count).text
        case "waits":
            guard tiles.count == shortCount else { throw InputError.malformed }
            let search = ShapeSearch()
            let shanten = search.shanten(concealed, meldCount: melds.count).minimum
            let improvements = search.liveImprovements(hand, from: shanten)
            let text = formatTiles(improvements.keys.map { Tile(kind: $0) })
            return "shanten=\(shanten) tiles=\(text) count=\(improvements.values.reduce(0, +))"
        case "score":
            let by = try require("by")
            guard by == "tsumo" || by == "ron" else { throw InputError.malformed }
            let win = try tile("win")
            return try score(hand, win: win, tsumo: by == "tsumo", context: scoreContext()).text
        case "legal":
            let turn: Turn
            if fields["draw"] != nil {
                turn = try .draw(tile("draw"))
            } else if fields["discard"] != nil {
                turn = try .discard(tile("discard"), fromLeft: fields["from"] == "kamicha")
            } else {
                let meld = try parseMeld(require("called"))
                let took = try tile("took")
                guard meld.type == .chi || meld.type == .pon, meld.tiles.contains(took),
                      tiles.count == shortCount + 1 else { throw InputError.malformed }
                turn = .afterCall(meld, took: took)
            }
            if fields["called"] == nil, tiles.count != shortCount { throw InputError.malformed }
            let context = try LegalContext(
                score: scoreContext(), riichi: fields["riichi"] == "1", furiten: fields["furiten"] == "1",
                wall: integer("wall", default: 70), first: fields["first"] == "1", kans: integer("kans", default: 0)
            )
            let actions = legal(hand, turn: turn, context: context)
            guard !actions.isEmpty else { throw InputError.malformed }
            return "actions=" + actions.joined(separator: ",")
        default:
            return "error=unknown_op"
        }
    }
}

while let line = readLine() {
    let parts = line.split(separator: " ")
    let id = parts.first ?? "-"
    do {
        guard parts.count >= 2 else { throw InputError.malformed }
        var fields: [Substring: Substring] = [:]
        for part in parts.dropFirst(2) {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { throw InputError.malformed }
            fields[pair[0]] = pair[1]
        }
        let result = try Request(op: parts[1], fields: fields).response()
        print("\(id) \(result)")
    } catch {
        print("\(id) error=bad_input")
    }
}
