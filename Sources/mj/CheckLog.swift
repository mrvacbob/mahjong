// `mj check-log [--rules tenhou] FILE...` (design §7): for mjai logs from
// elsewhere. Each hand's wall is rebuilt from what the log reveals (dealt hands,
// draws, indicators, ura), unseen slots filled with the unused tiles; then every
// logged action must be legal, every engine event must match the log's, and every
// point change and next-hand header must follow. What the log cannot show (passes,
// calls that lost, unseen ura) is counted, not checked.

import Riichi
import RiichiMjai

struct CheckReport {
    var errors: [String] = []
    var hands = 0
    var unchecked: [String: Int] = [:]
    mutating func note(_ k: String) { unchecked[k, default: 0] += 1 }
}

func checkLog(text: String, rules: Rules, path: String) -> CheckReport {
    var report = CheckReport()
    var msgs: [MjaiMessage] = []
    for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
        do { msgs.append(try Mjai.decode(String(line))) }
        catch { report.errors.append("\(path):\(n + 1): \(error)"); return report }
    }
    // Split into hands.
    var hands: [ArraySlice<MjaiMessage>] = []
    var i = 0
    while i < msgs.count {
        guard msgs[i].type == "start_kyoku" else { i += 1; continue }
        var j = i + 1
        while j < msgs.count && msgs[j].type != "start_kyoku" && msgs[j].type != "end_game" {
            j += 1
            if msgs[j - 1].type == "end_kyoku" { break }
        }
        hands.append(msgs[i..<j])
        i = j
    }
    let endGame = msgs.last { $0.type == "end_game" }
    var predicted: (GamePosition?, GameTransition, sticks: Int)? = nil
    for (h, hand) in hands.enumerated() {
        report.hands += 1
        let label = "\(path) hand \(h + 1)"
        var c = HandChecker(rules: rules, events: Array(hand), label: label)
        let outcome = c.run(&report)
        // The header follows from the previous hand.
        if let (pos, t, _) = predicted, let header = c.position {
            if let pos {
                if pos != header { report.errors.append("\(label): header \(header) but the previous hand gives \(pos)") }
            } else {
                report.errors.append("\(label): the game should have ended (\(t))")
            }
        }
        predicted = nil
        if let (result, position) = outcome {
            let (next, t) = GameFlow.next(after: result, at: position, rules: rules)
            predicted = (next, t, result.sticks)
            if h == hands.count - 1, let end = endGame {
                if next != nil {
                    report.errors.append("\(label): end_game, but the game continues (\(t))")
                } else if let scores = end.scores, case .ends(let why) = t {
                    let g = GameFlow.result(scores: result.scores, sticks: result.sticks, rules: rules, end: why)
                    if g.scores != scores { report.errors.append("\(label): end_game scores \(scores), expected \(g.scores)") }
                }
            }
        }
    }
    return report
}

struct HandChecker {
    let rules: Rules
    let events: [MjaiMessage]
    let label: String
    var position: GamePosition?

    init(rules: Rules, events: [MjaiMessage], label: String) {
        self.rules = rules
        self.events = events
        self.label = label
    }

    func fail(_ r: inout CheckReport, _ n: Int, _ s: String) {
        r.errors.append("\(label) event \(n): \(s)")
    }

    /// The wall the log reveals, unseen slots filled in canonical order.
    func rebuildWall(_ r: inout CheckReport) -> Wall? {
        let start = events[0]
        guard let tehais = start.tehais, tehais.count == 4, let oya = start.oya, let dm = start.doraMarker else {
            fail(&r, 0, "start_kyoku lacks tehais, oya or dora_marker"); return nil
        }
        var slots = [Tile?](repeating: nil, count: 136)
        for off in 0..<4 {
            let hand = tehais[(oya + off) % 4]
            guard hand.count == 13, hand.allSatisfy({ $0 != nil }) else { fail(&r, 0, "masked or short tehai"); return nil }
            var k = 0
            for round in 0..<3 { for x in 0..<4 { slots[16 * round + 4 * off + x] = hand[k]; k += 1 } }
            slots[48 + off] = hand[12]
        }
        var live = 0, repl = 0, dora = 1, afterKan = false
        slots[126] = dm
        var ura: [Tile] = []
        for (n, e) in events.enumerated().dropFirst() {
            switch e.type {
            case "tsumo":
                guard let t = e.pai else { fail(&r, n, "masked tsumo"); return nil }
                if afterKan {
                    guard repl < 4 else { fail(&r, n, "a fifth replacement draw"); return nil }
                    slots[122 + repl] = t; repl += 1
                } else {
                    guard live < 70 else { fail(&r, n, "a 71st live draw"); return nil }
                    slots[52 + live] = t; live += 1
                }
                afterKan = false
            case "daiminkan", "ankan", "kakan": afterKan = true
            case "dora":
                guard let t = e.doraMarker, dora < 5 else { fail(&r, n, "bad dora"); return nil }
                slots[126 + dora] = t; dora += 1
            case "hora":
                if let u = e.uraMarkers, u.count > ura.count { ura = u }
            default: break
            }
        }
        for (k, t) in ura.enumerated() where k < 5 { slots[131 + k] = t }
        var pool = Wall.sorted
        for t in slots.compactMap({ $0 }) {
            guard let k = pool.firstIndex(of: t) else { fail(&r, 0, "the log uses a fifth \(t)"); return nil }
            pool.remove(at: k)
        }
        var rest = pool.makeIterator()
        return Wall(tiles: slots.map { $0 ?? rest.next()! })
    }

    /// Checks the hand; returns its result and starting position if it got to the end.
    mutating func run(_ r: inout CheckReport) -> (RoundResult, GamePosition)? {
        let start = events[0]
        guard let wind = start.bakaze, let kyoku = start.kyoku, (1...4).contains(kyoku),
              let honba = start.honba, let sticks = start.kyotaku, let scores = start.scores, scores.count == 4,
              let oya = start.oya else {
            fail(&r, 0, "incomplete start_kyoku"); return nil
        }
        let pos = GamePosition(roundWind: wind, kyoku: kyoku, honba: honba, sticks: sticks, scores: scores)
        position = pos
        guard oya == kyoku - 1 else { fail(&r, 0, "oya \(oya) is not kyoku − 1"); return nil }
        guard let wall = rebuildWall(&r) else { return nil }
        var engine: [Event] = []
        var state = RoundState(rules: rules, wall: wall, roundWind: wind, kyoku: kyoku, honba: honba,
                               sticks: sticks, scores: scores, events: &engine)
        var queue = engine.map { Mjai.decode0($0) }
        var n = 0  // next log event
        while n < events.count {
            if let mine = queue.first {
                queue.removeFirst()
                if let d = Self.differs(events[n], mine) { fail(&r, n, d); return nil }
                n += 1
                continue
            }
            guard state.result == nil else { fail(&r, n, "the log goes on after the hand ended"); return nil }
            // The engine waits for a decision: read it from the log.
            var out: [Event] = []
            do {
                switch state.phase {
                case .turn(let seat, _):
                    // Tenhou flips an owed kan indicator just before the discard.
                    var n = n
                    while n + 1 < events.count && events[n].type == "dora" { n += 1 }
                    let e = events[n]
                    let legal = state.legalActions(for: seat)
                    guard e.actor == seat.index || e.type == "ryukyoku",
                          let a = Mjai.action(e, seat: seat, legal: legal) else {
                        fail(&r, n, "\(e.type) is not a legal action for seat \(seat) (legal: \(legal.map(\.description).joined(separator: " ")))")
                        return nil
                    }
                    try state.apply(a, by: seat, events: &out)
                case .reactions, .robbing:
                    // Riichi acceptance, and (Mahjong Soul) an owed kan indicator, come
                    // after the window and before the call that answers it: decide
                    // from the event after them.
                    var n = n
                    while n + 1 < events.count && ["dora", "reach_accepted"].contains(events[n].type) { n += 1 }
                    let e = events[n]
                    var answers = Answers()
                    let asked = state.seatsToAnswer
                    for s in asked { answers[s] = .pass }
                    switch e.type {
                    case "hora":
                        // One hora per winner, in turn order.
                        var k = n
                        while k < events.count && events[k].type == "hora" {
                            guard let a = events[k].actor, asked.contains(Seat(a)),
                                  state.legalActions(for: Seat(a)).contains(.ron) else {
                                fail(&r, k, "hora by a seat that may not ron"); return nil
                            }
                            answers[Seat(a)] = .ron
                            k += 1
                        }
                    case "chi", "pon", "daiminkan":
                        guard let a = e.actor, asked.contains(Seat(a)),
                              let act = Mjai.action(e, seat: Seat(a), legal: state.legalActions(for: Seat(a))) else {
                            fail(&r, n, "\(e.type) is not legal here"); return nil
                        }
                        answers[Seat(a)] = act
                        if asked.count > 1 { r.note("passes") }
                    case "ryukyoku" where e.reason == nil || e.reason == "sanchahou":
                        // Three rons aborting (Tenhou) leave no hora in the log.
                        let rons = asked.filter { state.legalActions(for: $0).contains(.ron) }
                        if rons.count == 3 && rules.tripleRonAborts {
                            for s in rons { answers[s] = .ron }
                        }
                        r.note("passes")
                    default:
                        r.note("passes")
                    }
                    try state.resolve(answers, events: &out)
                case .ended:
                    fail(&r, n, "the hand is over"); return nil
                }
            } catch {
                fail(&r, n, "refused: \(error)"); return nil
            }
            queue = out.map { Mjai.decode0($0) }
        }
        if !queue.isEmpty { fail(&r, n, "the log ends before the engine's \(queue[0].type)"); return nil }
        guard let result = state.result else { fail(&r, n, "the hand did not end"); return nil }
        // The optional end_kyoku result fields.
        if let end = events.last, end.type == "end_kyoku" {
            if let s = end.scores, s != result.scores { fail(&r, n - 1, "end_kyoku.scores \(s), engine \(result.scores)") }
            if let d = end.deltas, d != result.deltas { fail(&r, n - 1, "end_kyoku.deltas \(d), engine \(result.deltas)") }
            if let k = end.kyotakuLeft, k != result.sticks { fail(&r, n - 1, "end_kyoku.kyotaku_left \(k), engine \(result.sticks)") }
            if let d = end.dealerRepeats, d != result.dealerRepeats { fail(&r, n - 1, "end_kyoku.dealer_repeats") }
        }
        for w in result.wins where state.riichiStatus(of: w.winner) == .accepted {
            if !events.contains(where: { $0.type == "hora" && $0.uraMarkers != nil }) { r.note("unseen_ura") }
        }
        return (result, pos)
    }

    /// The first field in which a logged event differs from the engine's.
    static func differs(_ log: MjaiMessage, _ mine: MjaiMessage) -> String? {
        if log.type != mine.type { return "log has \(log.type), engine \(mine.type)" }
        func cmp<T: Equatable>(_ what: String, _ a: T?, _ b: T?) -> String? {
            guard let a else { return nil }  // a field the log does not give is not checked
            return a == b ? nil : "\(log.type).\(what): log \(a), engine \(b.map { "\($0)" } ?? "none")"
        }
        let checks: [String?] = [
            cmp("actor", log.actor, mine.actor),
            cmp("target", log.target, mine.target),
            log.type == "start_kyoku" ? nil : cmp("pai", log.pai, mine.pai),
            cmp("consumed", log.consumed?.sorted(), mine.consumed?.sorted()),
            cmp("tsumogiri", log.tsumogiri, mine.tsumogiri),
            cmp("dora_marker", log.doraMarker, mine.doraMarker),
            log.type == "end_kyoku" || log.type == "start_kyoku" ? nil : cmp("deltas", log.deltas, mine.deltas),
            log.type == "end_kyoku" || log.type == "start_kyoku" ? nil : cmp("scores", log.scores, mine.scores),
            cmp("ura_markers", log.uraMarkers, mine.uraMarkers),
        ]
        return checks.compactMap { $0 }.first
    }
}

extension Mjai {
    /// An engine event as the log would read it.
    static func decode0(_ e: Event) -> MjaiMessage { try! decode(encode(e)) }
}

/// `mj check-log [--rules tenhou] FILE...`
func checkLogCommand(_ args: [String]) throws -> Int32 {
    let o = try Options(args, flags: [])
    let rules = try o.rules()
    var errors = 0, hands = 0
    var unchecked: [String: Int] = [:]
    for path in o.positional {
        let r = checkLog(text: try readFile(path), rules: rules, path: path)
        hands += r.hands
        errors += r.errors.count
        for e in r.errors.prefix(10) { print(e) }
        for (k, v) in r.unchecked { unchecked[k, default: 0] += v }
    }
    print("files=\(o.positional.count) hands=\(hands) errors=\(errors)")
    print("not checked: " + (unchecked.isEmpty ? "-" : unchecked.keys.sorted().map { "\($0)=\(unchecked[$0]!)" }.joined(separator: " ")))
    return errors == 0 ? 0 : 1
}
