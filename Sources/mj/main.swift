// Line protocol: "<id> <op> key=value ..." in, "<id> key=value ..." out.

struct BadInput: Error { let reason: String }

struct Request {
    let id: Substring
    let op: Substring
    let keys: [Substring: Substring]

    init?(_ line: String) {
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        id = parts[0]
        op = parts[1]
        var keys: [Substring: Substring] = [:]
        for p in parts.dropFirst(2) {
            guard let eq = p.firstIndex(of: "=") else { return nil }
            keys[p[..<eq]] = p[p.index(after: eq)...]
        }
        self.keys = keys
    }

    /// The value of `key` (or `d` when absent), parsed.
    func value<T>(_ key: Substring, default d: Substring? = nil,
                  _ parse: (Substring) -> T?) throws(BadInput) -> T {
        guard let text = keys[key] ?? d else { throw BadInput(reason: "missing_\(key)") }
        guard let v = parse(text) else { throw BadInput(reason: "bad_\(key)") }
        return v
    }
    func string(_ key: Substring) throws(BadInput) -> Substring { try value(key) { $0 } }
    func tiles(_ key: Substring, default d: Substring? = nil) throws(BadInput) -> [Tile] {
        try value(key, default: d, parseTiles)
    }
    func tile(_ key: Substring) throws(BadInput) -> Tile { try value(key) { Tile($0) } }
    func wind(_ key: Substring) throws(BadInput) -> Wind { try value(key, default: "E", Wind.init) }
    func int(_ key: Substring, default d: Int, in range: ClosedRange<Int>) throws(BadInput) -> Int {
        try value(key, default: "\(d)") { Int($0).flatMap { range.contains($0) ? $0 : nil } }
    }
    func bool(_ key: Substring) throws(BadInput) -> Bool { try int(key, default: 0, in: 0...1) == 1 }
    func flags() throws(BadInput) -> Set<Flag> { try value("flags", default: "-", parseFlags) }
}

extension Request {
    /// `hand` and `melds`, checked with `extra` (a win, draw or discard) against
    /// the physical tile set: at most four of a kind, one red five per suit.
    func hand(plus extra: Tile? = nil) throws(BadInput) -> (tiles: [Tile], melds: [Meld]) {
        let hand = try tiles("hand"), melds = try value("melds", default: "-", parseMelds)
        let all = hand + (extra.map { [$0] } ?? []) + melds.tiles
        let reds = all.filter(\.isRed).map(\.kind)
        guard Counts(all).n.allSatisfy({ $0 <= 4 }), Set(reds).count == reds.count else {
            throw BadInput(reason: "impossible_tiles")
        }
        return (hand, melds)
    }

    /// The one `legal` trigger: exactly one of `draw`, `discard`, `called`.
    func situation() throws(BadInput) -> Situation {
        let present: [Substring] = ["draw", "discard", "called"].filter { keys[$0] != nil }
        guard present.count == 1 else { throw BadInput(reason: "bad_situation") }
        switch present[0] {
        case "draw": return .draw(try tile("draw"))
        case "discard":
            return .discard(try tile("discard"), fromKamicha: try string("from") == "kamicha")
        default:
            let meld = try value("called") { Meld($0) }, took = try tile("took")
            guard meld.tiles.contains(took) else { throw BadInput(reason: "bad_took") }
            return .called(meld, took: took)
        }
    }
}

func answer(_ q: Request, shantenCalc: ShantenCalculator) throws(BadInput) -> String {
    switch q.op {
    case "agari":
        let (hand, melds) = try q.hand()
        let forms = agariForms(Counts(hand), meldCount: melds.count)
        return forms.isEmpty ? "win=0" : "win=1 forms=\(forms.joined(separator: ";"))"

    case "shanten":
        let (hand, melds) = try q.hand()
        let s = shantenCalc.shanten(Counts(hand), meldCount: melds.count)
        let x = { (n: Int?) in n.map(String.init) ?? "x" }
        return "std=\(s.standard) chiitoi=\(x(s.chiitoi)) kokushi=\(x(s.kokushi)) min=\(s.min)"

    case "waits":
        let (hand, melds) = try q.hand()
        let w = shantenCalc.waits(Counts(hand), melds: melds)
        return "shanten=\(w.shanten) tiles=\(format(kinds: w.tiles)) count=\(w.count)"

    case "score":
        let win = try q.tile("win")
        let (hand, melds) = try q.hand(plus: win)
        let req = ScoreRequest(
            hand: hand, melds: melds, win: win,
            context: WinContext(seat: try q.wind("seat"), round: try q.wind("round"),
                                tsumo: try q.string("by") == "tsumo", flags: try q.flags()),
            dora: try q.tiles("dora", default: "-"), ura: try q.tiles("ura", default: "-"),
            // Bounded so that payments cannot overflow.
            honba: try q.int("honba", default: 0, in: 0...999))
        do { return try score(req).text } catch { return "error=\(error.rawValue)" }

    case "legal":
        let situation = try q.situation()
        let extra: Tile? = switch situation {
            case .draw(let t), .discard(let t, _): t
            case .called: nil  // the taken tile is already in `melds`
        }
        let (hand, melds) = try q.hand(plus: extra)
        let req = LegalRequest(
            hand: hand, melds: melds, situation: situation,
            seat: try q.wind("seat"), round: try q.wind("round"), flags: try q.flags(),
            inRiichi: try q.bool("riichi"), furiten: try q.bool("furiten"),
            wall: try q.int("wall", default: 70, in: 0...136), firstTurn: try q.bool("first"),
            kans: try q.int("kans", default: 0, in: 0...4))
        return "actions=\(req.actions.joined(separator: ","))"

    default:
        throw BadInput(reason: "unknown_op")
    }
}

let shantenCalc = ShantenCalculator()

while let line = readLine() {
    if line.isEmpty { continue }
    guard let q = Request(line) else {
        print("\(line.split(separator: " ").first ?? "?") error=bad_request")
        continue
    }
    do {
        print("\(q.id) \(try answer(q, shantenCalc: shantenCalc))")
    } catch {
        print("\(q.id) error=\(error.reason)")
    }
}
