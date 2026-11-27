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

    func string(_ key: Substring, default d: Substring? = nil) throws -> Substring {
        guard let v = keys[key] ?? d else { throw BadInput(reason: "missing_\(key)") }
        return v
    }
    func tiles(_ key: Substring, default d: Substring? = nil) throws -> [Tile] {
        guard let t = parseTiles(try string(key, default: d)) else { throw BadInput(reason: "bad_\(key)") }
        return t
    }
    func tile(_ key: Substring) throws -> Tile {
        guard let t = Tile(try string(key)) else { throw BadInput(reason: "bad_\(key)") }
        return t
    }
    func melds() throws -> [Meld] {
        guard let m = parseMelds(try string("melds", default: "-")) else { throw BadInput(reason: "bad_melds") }
        return m
    }
    func wind(_ key: Substring) throws -> Wind {
        guard let w = Wind(letter: try string(key, default: "E")) else { throw BadInput(reason: "bad_\(key)") }
        return w
    }
    func int(_ key: Substring, default d: Int) throws -> Int {
        guard let v = keys[key] else { return d }
        guard let n = Int(v) else { throw BadInput(reason: "bad_\(key)") }
        return n
    }
    func flags() throws -> Set<Flag> {
        let v = try string("flags", default: "-")
        if v == "-" { return [] }
        var out: Set<Flag> = []
        for f in v.split(separator: ",") {
            guard let flag = Flag(rawValue: String(f)) else { throw BadInput(reason: "bad_flag") }
            out.insert(flag)
        }
        return out
    }
}

let shantenCalc = ShantenCalculator()

func answer(_ q: Request, shantenCalc: ShantenCalculator) throws -> String {
    switch q.op {
    case "agari":
        let forms = agariForms(Counts(try q.tiles("hand")), meldCount: try q.melds().count)
        return forms.isEmpty ? "win=0" : "win=1 forms=\(forms.joined(separator: ";"))"

    case "shanten":
        let s = shantenCalc.shanten(Counts(try q.tiles("hand")), meldCount: try q.melds().count)
        let x = { (n: Int?) in n.map(String.init) ?? "x" }
        return "std=\(s.standard) chiitoi=\(x(s.chiitoi)) kokushi=\(x(s.kokushi)) min=\(s.min)"

    case "waits":
        let w = shantenCalc.waits(Counts(try q.tiles("hand")), melds: try q.melds())
        return "shanten=\(w.shanten) tiles=\(format(kinds: w.tiles)) count=\(w.count)"

    case "score":
        let flags = try q.flags()
        let req = ScoreRequest(
            hand: try q.tiles("hand"), melds: try q.melds(), win: try q.tile("win"),
            context: WinContext(seat: try q.wind("seat"), round: try q.wind("round"),
                                tsumo: try q.string("by") == "tsumo", flags: flags),
            dora: try q.tiles("dora", default: "-"), ura: try q.tiles("ura", default: "-"),
            honba: try q.int("honba", default: 0))
        do { return try score(req).text } catch { return "error=\(error.text)" }

    case "legal":
        let situation: Situation
        if q.keys["draw"] != nil {
            situation = .draw(try q.tile("draw"))
        } else if q.keys["discard"] != nil {
            situation = .discard(try q.tile("discard"), fromKamicha: try q.string("from") == "kamicha")
        } else if let c = q.keys["called"], let meld = Meld(c) {
            situation = .called(meld, took: try q.tile("took"))
        } else {
            throw BadInput(reason: "no_situation")
        }
        let req = LegalRequest(
            hand: try q.tiles("hand"), melds: try q.melds(), situation: situation,
            seat: try q.wind("seat"), round: try q.wind("round"), flags: try q.flags(),
            inRiichi: try q.int("riichi", default: 0) == 1,
            furiten: try q.int("furiten", default: 0) == 1,
            wall: try q.int("wall", default: 70), firstTurn: try q.int("first", default: 0) == 1,
            kans: try q.int("kans", default: 0))
        return "actions=\(LegalEngine(shanten: shantenCalc).actions(req).joined(separator: ","))"

    default:
        throw BadInput(reason: "unknown_op")
    }
}

while let line = readLine() {
    if line.isEmpty { continue }
    guard let q = Request(line) else {
        print("\(line.split(separator: " ").first ?? "?") error=bad_request")
        continue
    }
    do {
        print("\(q.id) \(try answer(q, shantenCalc: shantenCalc))")
    } catch let e as BadInput {
        print("\(q.id) error=\(e.reason)")
    } catch {
        print("\(q.id) error=internal")
    }
}
