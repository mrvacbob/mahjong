// Line protocol: "<id> <op> key=value ..." in, "<id> key=value ..." out.

import Riichi

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
    /// `rules=mahjongsoul|tenhou`, default Mahjong Soul. The line protocol keeps
    /// `spec/formats.md`'s definition of a riichi wait (no fifth copy, even of a
    /// kan's tiles), which the corpus fixes; the clients allow more
    /// (`Rules.riichiOnFifthCopyWait`, docs/notes/p3-reallogs.md).
    func rules() throws(BadInput) -> Rules {
        var r = try value("rules", default: "mahjongsoul") { text -> Rules? in
            switch text {
            case "mahjongsoul": .mahjongSoul
            case "tenhou": .tenhou
            default: nil
            }
        }
        r.riichiOnFifthCopyWait = false
        return r
    }
}

extension Request {
    /// `hand` and `melds`, checked with `extra` (a win, draw or discard) against
    /// the physical tile set: at most four of a kind, one red five per suit.
    func hand(plus extra: Tile? = nil) throws(BadInput) -> (tiles: [Tile], melds: [Meld]) {
        let hand = try tiles("hand"), melds = try value("melds", default: "-", parseMelds)
        // Counted before any `Counts` is built (Gemini final finding 1: `Counts`
        // holds at most 15 of a kind).
        guard isPossibleTileSet(hand + (extra.map { [$0] } ?? []) + melds.tiles) else {
            throw BadInput(reason: "impossible_tiles")
        }
        guard melds.count <= 4 else { throw BadInput(reason: "bad_melds") }
        return (hand, melds)
    }

    /// The one `legal` trigger: exactly one of `draw`, `discard`, `called`.
    func situation() throws(BadInput) -> Situation {
        let present: [Substring] = ["draw", "discard", "called"].filter { keys[$0] != nil }
        guard present.count == 1 else { throw BadInput(reason: "bad_situation") }
        switch present[0] {
        case "draw": return .draw(try tile("draw"))
        case "discard":
            let from = try value("from") { ["kamicha", "toimen", "shimocha"].contains($0) ? $0 : nil }
            return .discard(try tile("discard"), fromKamicha: from == "kamicha")
        default:
            // A chi or pon only: a kan is followed by a replacement draw, not a discard.
            let meld = try value("called") { m in Meld(m).flatMap { [.chi, .pon].contains($0.kind) ? $0 : nil } }
            let took = try tile("took")
            guard meld.tiles.contains(took) else { throw BadInput(reason: "bad_took") }
            return .called(meld, took: took)
        }
    }
}

extension Payment {
    var text: String {
        switch self {
        case .ron(let n): "ron:\(n)"
        case .dealerTsumo(let n): "all:\(n)"
        case .tsumo(let nd, let d): "tsumo:\(nd)/\(d)"
        }
    }
}

extension Scored {
    var text: String {
        switch value {
        case .ordinary(let han, let fu):
            "yaku=\(yakuText) han=\(han) fu=\(fu) pay=\(payment.text) total=\(payment.total)"
        case .yakuman(let n):
            "yaku=\(yakuText) yakuman=\(n) pay=\(payment.text) total=\(payment.total)"
        }
    }
}

func answer(_ q: Request) throws(BadInput) -> String {
    switch q.op {
    case "agari":
        let (hand, melds) = try q.hand()
        let forms = agariForms(Counts(hand), meldCount: melds.count)
        return forms.isEmpty ? "win=0" : "win=1 forms=\(forms.joined(separator: ";"))"

    case "shanten":
        let (hand, melds) = try q.hand()
        let s = shanten(Counts(hand), meldCount: melds.count)
        let x = { (n: Int?) in n.map(String.init) ?? "x" }
        return "std=\(s.standard) chiitoi=\(x(s.chiitoi)) kokushi=\(x(s.kokushi)) min=\(s.min)"

    case "waits":
        let (hand, melds) = try q.hand()
        let w = waits(Counts(hand), melds: melds)
        return "shanten=\(w.shanten) tiles=\(mpsz(kinds: w.tiles)) count=\(w.count)"

    case "score":
        let win = try q.tile("win")
        let (hand, melds) = try q.hand(plus: win)
        let req = ScoreRequest(
            hand: hand, melds: melds, win: win,
            context: WinContext(seat: try q.wind("seat"), round: try q.wind("round"),
                                tsumo: try q.value("by") { ["tsumo": true, "ron": false][$0] },
                                flags: try q.flags()),
            dora: try q.tiles("dora", default: "-"), ura: try q.tiles("ura", default: "-"),
            // Bounded so that payments cannot overflow.
            honba: try q.int("honba", default: 0, in: 0...999))
        let rules = try q.rules()
        do { return try score(req, rules: rules).text } catch { return "error=\(error.rawValue)" }

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
            kans: try q.int("kans", default: 0, in: 0...4), rules: try q.rules())
        do { return "actions=\(try req.actions.joined(separator: ","))" }
        catch { throw BadInput(reason: "bad_\(error.field)") }

    default:
        throw BadInput(reason: "unknown_op")
    }
}

/// `mj bench-round [ROUNDS] [tenhou]` (not part of the line protocol): rounds per
/// second of uniform random play in process, without and with event collection.
func benchRounds(_ args: [String]) {
    let rounds = args.first.flatMap { Int($0) } ?? 20_000
    let rules: Rules = args.contains("tenhou") ? .tenhou : .mahjongSoul
    struct RNG {
        var state: UInt64
        mutating func below(_ n: Int) -> Int {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Int((z ^ (z >> 31)) % UInt64(n))
        }
    }
    func play(events collect: Bool) -> (Duration, Int, Int) {
        var rng = RNG(state: 1)
        var decisions = 0, eventCount = 0
        var events: [Event] = []
        let clock = ContinuousClock()
        let start = clock.now
        for i in 0..<rounds {
            let wall = Wall(seed: UInt64(i), hand: 0)
            var s = collect ? try! RoundState(rules: rules, wall: wall, events: &events)
                            : try! RoundState(rules: rules, wall: wall)
            while s.result == nil {
                decisions += 1
                if case .turn(let seat, _) = s.phase {
                    let legal = s.legalActions(for: seat)
                    let a = legal[rng.below(legal.count)]
                    if collect { try! s.apply(a, by: seat, events: &events) } else { try! s.apply(a, by: seat) }
                } else {
                    var answers = Answers()
                    for seat in s.seatsToAnswer {
                        let legal = s.legalActions(for: seat)
                        answers[seat] = legal[rng.below(legal.count)]
                    }
                    if collect { try! s.resolve(answers, events: &events) } else { try! s.resolve(answers) }
                }
            }
            eventCount += events.count
            events.removeAll(keepingCapacity: true)
        }
        return (clock.now - start, decisions, eventCount)
    }
    _ = shanten(Counts(), meldCount: 0)  // build the tables outside the timing
    for collect in [false, true] {
        let (d, decisions, events) = play(events: collect)
        let secs = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        let rps = Int(Double(rounds) / secs)
        print("events=\(collect ? "on " : "off") rounds=\(rounds) time=\(Int(secs * 1000))ms rounds/s=\(rps) decisions/round=\(decisions / rounds) events/round=\(events / rounds)")
    }
}

import Foundation

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : nil
func run(_ body: () throws -> Int32) -> Never {
    do { exit(try body()) } catch {
        FileHandle.standardError.write(Data("mj \(command ?? ""): \(error)\n".utf8))
        exit(2)
    }
}
signal(SIGPIPE, SIG_IGN)
switch command {
case "bench-round":
    benchRounds(Array(args.dropFirst(2)))
    exit(0)
case "selfplay": run { try selfplay(Array(args.dropFirst(2))) }
case "replay": run { try replay(Array(args.dropFirst(2))) }
case "check-log": run { try checkLogCommand(Array(args.dropFirst(2))) }
case nil: break
default:
    FileHandle.standardError.write(Data("""
        usage: mj [selfplay|replay|check-log|bench-round] ... (no argument: line protocol on stdin)
        selfplay writes referee-only files: the unmasked log (.jsonl: every wall and hand),
        the trace (.trace: the seed and every decision), --legal rows (all four hands)
        and --requests dumps. Keep them where no player or bot can read them.

        """.utf8))
    exit(2)
}

while let line = readLine() {
    if line.isEmpty { continue }
    guard let q = Request(line) else {
        print("\(line.split(separator: " ").first ?? "?") error=bad_request")
        continue
    }
    do {
        print("\(q.id) \(try answer(q))")
    } catch {
        print("\(q.id) error=\(error.reason)")
    }
}
