// `mj check-log [--rules tenhou] [--set field=value]... [--json] [--stdin] FILE...`
// (design §7): for mjai logs from elsewhere. Each hand's wall is rebuilt from what
// the log reveals (dealt hands, draws, indicators, ura), unseen slots filled with the
// unused tiles; then every logged action must be legal, every engine event must
// match the log's, and every point change and next-hand header must follow. What
// the log cannot show (passes, calls that lost, unseen ura) is counted, not checked.
//
// Bulk use (docs/notes/p3-reallogs.md): `--stdin` reads games framed as
// `NAME LENGTH\n` followed by LENGTH bytes of mjai text; `--json` prints one JSON
// line per game (differences, named conventions, unchecked counts, situation tags).
// `tools/reallogs.py` feeds tar shards to parallel workers this way.
//
// Named converter conventions are counted, not errors:
// - `ura_on_multi_ron`: on a multi-ron, the log gives `ura_markers` to every
//   winner when any winner is in riichi; the engine gives them to riichi winners only.
// - `dora_before_dahai`: (indicator revealed after the window, Mahjong Soul) the
//   log's owed kan `dora` comes before the kan seat's `dahai`, the engine's after the
//   window closes.
// - `lite_no_dora`, `lite_hidden_indicators`: the converter's reduced format (no
//   `dora` events, no `deltas`, no `ura_markers`; most Mahjong Soul Jade games from
//   2020): kan and ura indicators are unknown, so the point changes are checked
//   against the next `start_kyoku` by trying every assignment of the hidden
//   indicators the unseen tiles allow.

import Foundation
import Riichi
import RiichiMjai

struct Difference {
    /// 1-based hand; 0 for the file as a whole.
    var hand: Int
    var event: Int
    var category: String
    var message: String
}

struct CheckReport {
    var path = ""
    var diffs: [Difference] = []
    var hands = 0
    var lite = false
    var unchecked: [String: Int] = [:]
    var conventions: [String: Int] = [:]
    /// Situations met, by hand (1-based; 0 for the game).
    var tags: [(Int, String)] = []
    mutating func note(_ k: String) { unchecked[k, default: 0] += 1 }
    mutating func convention(_ k: String) { conventions[k, default: 0] += 1 }

    var errors: [String] {
        diffs.map { $0.hand == 0 ? "\(path): \($0.message)" : "\(path) hand \($0.hand) event \($0.event): \($0.message)" }
    }
}

/// Checks a game. Rooms mix East-only and East-South games and the logs do not say
/// which: a game whose flow fails as a hanchan is tried as an East-only game.
func checkLog(text: String, rules: Rules, path: String) -> CheckReport {
    let r = checkGame(text: text, rules: rules, path: path)
    let flowDiffs: (CheckReport) -> Int = { $0.diffs.filter { ["header", "lite_header", "game_continues"].contains($0.category) }.count }
    guard rules.length == .south, flowDiffs(r) > 0 else { return r }
    var east = rules
    east.length = .east
    var r2 = checkGame(text: text, rules: east, path: path)
    guard r2.diffs.count < r.diffs.count else { return r }
    r2.tags.append((0, "east_game"))
    return r2
}

func checkGame(text: String, rules: Rules, path: String) -> CheckReport {
    var report = CheckReport()
    report.path = path
    var msgs: [MjaiMessage] = []
    for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
        do { msgs.append(try Mjai.decode(String(line))) }
        catch {
            report.diffs.append(Difference(hand: 0, event: n, category: "parse", message: "line \(n + 1): \(error)"))
            return report
        }
    }
    // The reduced format: results without deltas.
    report.lite = msgs.contains { ($0.type == "hora" || $0.type == "ryukyoku") && $0.deltas == nil }
    // Split into hands. Outside them only `start_game` (before the first) and
    // `end_game` (at the end) may appear.
    var hands: [ArraySlice<MjaiMessage>] = []
    var i = 0
    while i < msgs.count {
        guard msgs[i].type == "start_kyoku" else {
            let ok = (msgs[i].type == "start_game" && hands.isEmpty && i == 0)
                || (msgs[i].type == "end_game" && i == msgs.count - 1)
            if !ok {
                report.diffs.append(Difference(hand: hands.count, event: i, category: "outside_hand",
                                               message: "\(msgs[i].type) outside a hand (line \(i + 1))"))
            }
            i += 1
            continue
        }
        var j = i + 1
        while j < msgs.count && msgs[j].type != "start_kyoku" && msgs[j].type != "end_game" {
            j += 1
            if msgs[j - 1].type == "end_kyoku" { break }
        }
        hands.append(msgs[i..<j])
        i = j
    }
    if hands.isEmpty {
        report.diffs.append(Difference(hand: 0, event: 0, category: "no_hands", message: "the log has no start_kyoku"))
        return report
    }
    let endGame = msgs.last { $0.type == "end_game" }
    // The previous hand's checker and outcome, while its result is still to be
    // confirmed by this hand's header.
    var previous: (HandChecker, HandOutcome)? = nil
    for (h, hand) in hands.enumerated() {
        report.hands += 1
        var c = HandChecker(rules: rules, events: Array(hand), hand: h + 1, lite: report.lite)
        let before = report.diffs.count
        var outcome = c.run(&report)
        // A win whose payment depends on indicators the log does not show (no
        // `ura_markers`): try every assignment the unseen tiles allow.
        if outcome == nil, report.diffs.count == before + 1,
           report.diffs[before].category.hasPrefix("hora.") || report.diffs[before].category.hasPrefix("early_dora/hora."),
           c.hasHiddenIndicators {
            var lenient = c
            lenient.lenient = true
            var scratch = CheckReport()
            if let o = lenient.run(&scratch), let found = c.searchHidden(o, where: { _ in true }) {
                report.diffs.removeLast()
                report.convention("hidden_indicators")
                var again = CheckReport()
                var c2 = c
                _ = c2.run(&again, slots: found.slots)
                report.tags += again.tags
                outcome = found
            }
        }
        if let (pc, po) = previous, let header = c.position {
            confirm(pc, po, header: header, report: &report)
        }
        previous = nil
        guard let outcome else { continue }
        if h == hands.count - 1 {
            let (next, t) = flow(outcome, rules)
            gameTags(outcome, rules: rules, report: &report)
            if endGame != nil {
                if next != nil, report.lite, outcome.needsHeader,
                   let found = c.searchHidden(outcome, where: { flow($0, rules).0 == nil }) {
                    report.convention("lite_hidden_indicators")
                    _ = found
                } else if next != nil {
                    report.diffs.append(Difference(hand: h + 1, event: hand.count, category: "game_continues",
                                                   message: "end_game, but the game continues (\(t))"))
                } else if let scores = endGame?.scores, case .ends(let why) = t {
                    let g = GameFlow.result(scores: outcome.result.scores, sticks: outcome.result.sticks, rules: rules, end: why)
                    if g.scores != scores {
                        report.diffs.append(Difference(hand: h + 1, event: hand.count, category: "end_game_scores",
                                                       message: "end_game scores \(scores), expected \(g.scores)"))
                    }
                }
            }
            if report.lite && outcome.needsHeader { report.note("lite_last_hand_points") }
        } else {
            previous = (c, outcome)
        }
    }
    return report
}

/// The transition after a hand, with the scores the all-last test reads.
func flow(_ o: HandOutcome, _ rules: Rules) -> (GamePosition?, GameTransition) {
    GameFlow.next(after: o.result, at: o.position, rules: rules, testScores: o.testScores(rules))
}

/// Tags for the game-flow rulings a hand's transition depends on.
func gameTags(_ o: HandOutcome, rules: Rules, report: inout CheckReport) {
    let (next, t) = flow(o, rules)
    let h = o.hand
    switch t {
    case .ordinary: break
    case .allLastRepeat: report.tags.append((h, "all_last_repeat"))
    case .allLastAdvance: report.tags.append((h, "all_last_advance"))
    case .ends(let why):
        report.tags.append((h, "end_\(why.rawValue)"))
        if o.result.sticks > 0 { report.tags.append((h, "end_sticks_left")) }
    }
    if o.position.roundWind.rawValue > (rules.length == .east ? Wind.east : Wind.south).rawValue {
        report.tags.append((h, "extension_hand"))
    }
    for (name, flip) in [("dealerRepeatBeforeTarget", { (r: inout Rules) in r.dealerRepeatBeforeTarget.toggle() }),
                         ("allLastTestAfterNagashi", { (r: inout Rules) in r.allLastTestAfterNagashi.toggle() })] {
        var r = rules
        flip(&r)
        let (n2, t2) = flow(o, r)
        if n2 != next || t2 != t { report.tags.append((h, "sens_\(name)")) }
    }
}

/// Checks the next header against the previous hand's result; in the reduced
/// format, tries the hidden indicators first.
func confirm(_ c: HandChecker, _ o: HandOutcome, header: GamePosition, report: inout CheckReport) {
    let (pos, t) = flow(o, c.rules)
    if pos == header { gameTags(o, rules: c.rules, report: &report); return }
    if c.lite, o.needsHeader, let found = c.searchHidden(o, header: header) {
        report.convention("lite_hidden_indicators")
        gameTags(found, rules: c.rules, report: &report)
        return
    }
    let msg = pos.map { "next header \(header) but this hand gives \($0)" } ?? "the game should have ended (\(t)), but the log goes on"
    report.diffs.append(Difference(hand: o.hand, event: c.events.count, category: c.lite ? "lite_header" : "header", message: msg))
}

struct HandOutcome {
    var hand: Int
    var result: RoundResult
    var position: GamePosition
    var state: RoundState
    var engine: [Event]
    var slots: [Tile?]
    /// Whether the log's own fields did not check the point changes (reduced format).
    var needsHeader: Bool

    func testScores(_ rules: Rules) -> [Int] {
        guard !rules.allLastTestAfterNagashi, case .exhaustiveDraw(_, let nagashi) = result.outcome,
              !nagashi.isEmpty else { return result.scores }
        return Seat.all.map { s in
            state.initialScores[s.index] - (state.riichiStatus(of: s) == .accepted ? 1000 : 0)
        }
    }
}

struct HandChecker {
    let rules: Rules
    let events: [MjaiMessage]
    let hand: Int
    let lite: Bool
    /// Ignores a win's point fields (to find its winners before a hidden-indicator search).
    var lenient = false
    var position: GamePosition?

    init(rules: Rules, events: [MjaiMessage], hand: Int, lite: Bool = false) {
        self.rules = rules
        self.events = Self.splitDealerDraw(events)
        self.hand = hand
        self.lite = lite
    }

    /// The reduced format deals the dealer 14 tiles and has no first `tsumo`: take
    /// the first discard (if tsumogiri) or the last tile listed as the draw.
    static func splitDealerDraw(_ events: [MjaiMessage]) -> [MjaiMessage] {
        guard var start = events.first, start.type == "start_kyoku", let oya = start.oya, (0..<4).contains(oya),
              var hands = start.tehais, hands.count == 4, hands[oya].count == 14,
              events.count > 1, events[1].type != "tsumo" else { return events }
        var hand = hands[oya]
        // The dealer's first discard (after a double riichi's `reach`), or a tenhou's tile.
        let first = events[1].type == "reach" && events.count > 2 ? events[2] : events[1]
        var k = hand.count - 1
        if first.type == "hora" || (first.type == "dahai" && first.tsumogiri == true),
           let p = first.pai, let i = hand.lastIndex(of: p) {
            k = i
        } else if first.type == "dahai", let p = first.pai, hand[k] == p, let i = hand.lastIndex(where: { $0 != p }) {
            k = i
        }
        let drawn = hand.remove(at: k)
        hands[oya] = hand
        start.tehais = hands
        var tsumo = MjaiMessage(type: "tsumo")
        tsumo.actor = oya
        tsumo.pai = drawn
        return [start, tsumo] + events.dropFirst()
    }

    func fail(_ r: inout CheckReport, _ n: Int, _ category: String, _ s: String) {
        r.diffs.append(Difference(hand: hand, event: n, category: category, message: s))
    }

    /// The wall slots the log reveals.
    func revealedSlots(_ r: inout CheckReport) -> [Tile?]? {
        let start = events[0]
        guard let tehais = start.tehais, tehais.count == 4, let oya = start.oya, let dm = start.doraMarker else {
            fail(&r, 0, "format", "start_kyoku lacks tehais, oya or dora_marker"); return nil
        }
        var slots = [Tile?](repeating: nil, count: 136)
        for off in 0..<4 {
            let hand = tehais[(oya + off) % 4]
            guard hand.count == 13, hand.allSatisfy({ $0 != nil }) else { fail(&r, 0, "format", "masked or short tehai"); return nil }
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
                guard let t = e.pai else { fail(&r, n, "format", "masked tsumo"); return nil }
                if afterKan {
                    guard repl < 4 else { fail(&r, n, "wall", "a fifth replacement draw"); return nil }
                    slots[122 + repl] = t; repl += 1
                } else {
                    guard live < 70 else { fail(&r, n, "wall", "a 71st live draw"); return nil }
                    slots[52 + live] = t; live += 1
                }
                afterKan = false
            case "daiminkan", "ankan", "kakan": afterKan = true
            case "dora":
                guard let t = e.doraMarker, dora < 5 else { fail(&r, n, "format", "bad dora"); return nil }
                slots[126 + dora] = t; dora += 1
            case "hora":
                if let u = e.uraMarkers, u.count > ura.count { ura = u }
            default: break
            }
        }
        for (k, t) in ura.enumerated() where k < 5 { slots[131 + k] = t }
        var pool = Wall.sorted
        for t in slots.compactMap({ $0 }) {
            guard let k = pool.firstIndex(of: t) else { fail(&r, 0, "wall", "the log uses a fifth \(t)"); return nil }
            pool.remove(at: k)
        }
        return slots
    }

    /// The unused tiles after `slots`.
    static func pool(_ slots: [Tile?]) -> [Tile] {
        var pool = Wall.sorted
        for t in slots.compactMap({ $0 }) { if let k = pool.firstIndex(of: t) { pool.remove(at: k) } }
        return pool
    }

    static func wall(_ slots: [Tile?]) -> Wall {
        var rest = pool(slots).makeIterator()
        return Wall(tiles: slots.map { $0 ?? rest.next()! })!
    }

    /// Checks the hand; returns its result if it got to the end.
    mutating func run(_ r: inout CheckReport, slots given: [Tile?]? = nil) -> HandOutcome? {
        let start = events[0]
        guard let wind = start.bakaze, let kyoku = start.kyoku, (1...4).contains(kyoku),
              let honba = start.honba, let sticks = start.kyotaku, let scores = start.scores, scores.count == 4,
              let oya = start.oya else {
            fail(&r, 0, "format", "incomplete start_kyoku"); return nil
        }
        let pos = GamePosition(roundWind: wind, kyoku: kyoku, honba: honba, sticks: sticks, scores: scores)
        position = pos
        guard oya == kyoku - 1 else { fail(&r, 0, "format", "oya \(oya) is not kyoku − 1"); return nil }
        // Bounds that keep the engine's preconditions and arithmetic safe.
        guard (0...1000).contains(honba), (0...1000).contains(sticks),
              scores.allSatisfy({ abs($0) <= 100_000_000 }) else {
            fail(&r, 0, "format", "honba, kyotaku or scores out of range"); return nil
        }
        guard let slots = given ?? revealedSlots(&r) else { return nil }
        let wall = Self.wall(slots)
        var engine: [Event] = []
        var state = RoundState(rules: rules, wall: wall, roundWind: wind, kyoku: kyoku, honba: honba,
                               sticks: sticks, scores: scores, events: &engine)
        var all = engine
        var queue = engine.map(Self.message)
        var n = 0  // next log event
        var earlyDora: [Tile] = []  // log `dora` seen before the engine reveals it
        // Declined a tsumo since its last live draw (and, with
        // `temporaryFuritenEndsOnCall`, its last call): how ("kan", "riichi" or
        // "discard"), and whether a ron has been offered to it since. Run with
        // `temporaryFuritenOnDeclinedTsumo` off, the `dt_*` tags count the rons that
        // field would refuse: offered, taken, passed.
        var declined: [Seat: (how: String, offered: Bool)] = [:]
        var afterKan = false  // the next tsumo is a replacement draw
        var inferredRon = false  // a ron the log leaves out (see the window below)
        var tags: [String] = []
        let multiRon = events.lazy.filter { $0.type == "hora" }.count > 1
        let longestUra = events.compactMap(\.uraMarkers).max { $0.count < $1.count } ?? []
        while n < events.count {
            if let mine = queue.first {
                let log = events[n]
                if log.type != mine.type {
                    // Mahjong Soul: an owed indicator the log shows before the discard.
                    if log.type == "dora", !rules.openKanDoraBeforeRon, let m = log.doraMarker {
                        earlyDora.append(m); n += 1; continue
                    }
                    // The converter omits the fourth riichi's acceptance before a
                    // four-riichi abort (the stick is paid: the next header shows it).
                    // (Also before a four-kan abort on the fourth kan's riichi discard.)
                    if log.type == "ryukyoku", mine.type == "reach_accepted", queue.count > 1,
                       queue[1].type == "ryukyoku", let reason = queue[1].reason {
                        queue.removeFirst(); r.convention("\(reason)_no_reach_accepted"); continue
                    }
                    if lite, log.type == "reach_accepted", mine.type == "hora" {
                        // The reduced format accepts a riichi whose discard was ronned.
                        n += 1; r.convention("lite_reach_accepted_before_ron"); continue
                    }
                    if lite, log.type == "kakan", mine.type == "ankan", let p = log.pai,
                       mine.consumed?.first?.kind == p.kind {
                        queue.removeFirst(); n += 1; continue
                    }
                    if lite, log.type == "ankan", mine.type == "kakan", let k = log.consumed?.first?.kind,
                       mine.pai?.kind == k {
                        queue.removeFirst(); n += 1; continue
                    }
                    if inferredRon, mine.type == "hora" { queue.removeFirst(); continue }
                    if log.type == "end_kyoku" {
                        fail(&r, n, "truncated_hand", "the log ends the hand before the engine's \(mine.type)"); return nil
                    }
                    if log.type == "hora", mine.type == "dora", n > 0, events[n - 1].type == "kakan" {
                        // Mahjong Soul's records omit the owed indicator shown at a
                        // chained added kan when that kan is robbed (the payment counts it).
                        queue.removeFirst(); r.convention("chankan_owed_dora_unlogged"); continue
                    }
                    if mine.type == "dora", let m = mine.doraMarker {
                        if let k = earlyDora.firstIndex(of: m) {
                            earlyDora.remove(at: k); queue.removeFirst()
                            r.convention("dora_before_dahai"); continue
                        }
                        if lite { queue.removeFirst(); r.convention("lite_no_dora"); continue }
                    }
                }
                queue.removeFirst()
                var ignore: Set<String> = []
                if lenient, log.type == "hora" {
                    ignore.formUnion(["deltas", "scores", "ura_markers", "fan", "fu"])
                }
                if lite, log.type == "hora", log.target != mine.target,
                   let k = events[..<n].lastIndex(where: { $0.type != "hora" }), ["ankan", "kakan"].contains(events[k].type) {
                    // ... nor, on a robbed kan, the hora target.
                    ignore.insert("target")
                    r.convention("lite_chankan_target")
                }
                if lite, ["chi", "pon", "daiminkan"].contains(log.type), log.target != mine.target {
                    // The reduced format's call target is not the discarder.
                    ignore.insert("target")
                    r.convention("lite_call_target")
                }
                if log.type == "hora", multiRon, let u = log.uraMarkers, !u.isEmpty, mine.uraMarkers?.isEmpty ?? true,
                   u == longestUra {
                    ignore.insert("ura_markers")
                    r.convention("ura_on_multi_ron")
                }
                if lite, log.type == "ryukyoku", let reason = log.reason, let m = mine.reason,
                   ["reach4": "suufon_renda", "kaze4": "suucha_riichi"][reason] == m {
                    // The reduced format swaps the two names.
                    ignore.insert("reason")
                    r.convention("lite_abort_names_swapped")
                }
                if case (let field, var d)? = Self.differs(log, mine, ignoring: ignore) {
                    let why = earlyDora.isEmpty ? "" : "early_dora/"
                    if log.type == "hora", let a = log.actor, (0..<4).contains(a) {
                        let s = Seat(a), f = state.furitenParts(of: s)
                        d += " [seat \(a): hand \(state.hand(of: s).map(\.description).joined()) waits \(state.waits(of: s).map(\.description).joined(separator: ",")) furiten own=\(f.ownDiscard) temp=\(f.temporary) riichi=\(f.riichi)]"
                    }
                    var category = "\(why)\(log.type == mine.type ? "\(log.type).\(field)" : "sequence:\(log.type)/\(mine.type)")"
                    // Points that do not add up cannot be a rule difference.
                    if field == "deltas", let a = log.deltas, let b = mine.deltas, a.reduce(0, +) != b.reduce(0, +) {
                        category = "log_defect:unbalanced_deltas"
                    }
                    fail(&r, n, category, d)
                    return nil
                }
                n += 1
                continue
            }
            guard state.result == nil else { fail(&r, n, "sequence:after_end", "the log goes on after the hand ended"); return nil }
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
                    var a = e.actor == seat.index || e.type == "ryukyoku" ? Mjai.action(e, seat: seat, legal: legal) : nil
                    if a == nil, lite, e.type == "kakan", e.actor == seat.index, let p = e.pai,
                       legal.contains(.ankan(p.kind)) {
                        // The reduced format writes some closed kans as added kans.
                        a = .ankan(p.kind)
                        r.convention("lite_ankan_as_kakan")
                    }
                    if a == nil, lite, e.type == "ankan", e.actor == seat.index, let k = e.consumed?.first?.kind,
                       let t = legal.lazy.compactMap({ x -> Tile? in if case .kakan(let t) = x, t.kind == k { t } else { nil } }).first {
                        // ... and some added kans as closed kans.
                        a = .kakan(t)
                        r.convention("lite_kakan_as_ankan")
                    }
                    guard let a else {
                        fail(&r, n, "illegal:\(e.type)", "\(e.type) is not a legal action for seat \(seat) (legal: \(legal.map(\.description).joined(separator: " ")))")
                        return nil
                    }
                    if legal.contains(.tsumo), a != .tsumo, a != .kyuushu, state.riichiStatus(of: seat) != .accepted {
                        let how: String
                        switch a {
                        case .ankan, .kakan: how = "kan"
                        case .riichi: how = "riichi"
                        default: how = "discard"
                        }
                        declined[seat] = (how, false)
                        tags.append("declined_tsumo")
                        tags.append("declined_tsumo_\(how)")
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
                    var offeredNow: [Seat] = []
                    for (s, d) in declined where asked.contains(s) && state.legalActions(for: s).contains(.ron) {
                        if !d.offered { tags.append("dt_\(d.how)_offered"); declined[s]!.offered = true }
                        offeredNow.append(s)
                    }
                    switch e.type {
                    case "hora":
                        // One hora per winner, in turn order.
                        var k = n
                        while k < events.count && events[k].type == "hora" {
                            guard let a = events[k].actor, asked.contains(Seat(a)),
                                  state.legalActions(for: Seat(a)).contains(.ron) else {
                                let a = events[k].actor ?? 0, s = Seat((0..<4).contains(a) ? a : 0), f = state.furitenParts(of: s)
                                fail(&r, k, "illegal:ron", "hora by a seat that may not ron [seat \(s.index): hand \(state.hand(of: s).map(\.description).joined()) waits \(state.waits(of: s).map(\.description).joined(separator: ",")) furiten own=\(f.ownDiscard) temp=\(f.temporary) riichi=\(f.riichi) asked=\(asked.contains(s))]"); return nil
                            }
                            answers[Seat(a)] = .ron
                            if let d = declined[Seat(a)] {
                                tags.append("ron_after_declined_tsumo")
                                if offeredNow.contains(Seat(a)) { tags.append("dt_\(d.how)_ron") }
                            }
                            k += 1
                        }
                    case "chi", "pon", "daiminkan":
                        guard let a = e.actor, asked.contains(Seat(a)),
                              let act = Mjai.action(e, seat: Seat(a), legal: state.legalActions(for: Seat(a))) else {
                            fail(&r, n, "illegal:\(e.type)", "\(e.type) is not legal here"); return nil
                        }
                        answers[Seat(a)] = act
                        if asked.count > 1 { r.note("passes") }
                    case "end_kyoku" where asked.contains(where: { state.legalActions(for: $0).contains(.ron) }):
                        // Mahjong Soul Throne records drop the hora of a ron under pao: the
                        // hand stops after the winning discard. The seats that may ron are
                        // taken to have won; the next header (or the game's end) checks it.
                        for s in asked where state.legalActions(for: s).contains(.ron) { answers[s] = .ron }
                        inferredRon = true
                        r.convention("missing_hora_inferred")
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
                    for s in offeredNow where answers[s] != .ron { tags.append("dt_\(declined[s]!.how)_passed") }
                    try state.resolve(answers, events: &out)
                case .ended:
                    fail(&r, n, "sequence:after_end", "the hand is over"); return nil
                }
            } catch {
                fail(&r, n, "refused", "refused: \(error)"); return nil
            }
            for e in out {
                switch e {
                case .tsumo(let a, _):
                    if !afterKan { declined[a] = nil }
                    afterKan = false
                case .ankan, .kakan, .daiminkan: afterKan = true
                case .chi(let a, _, _, _), .pon(let a, _, _, _):
                    if rules.temporaryFuritenEndsOnCall { declined[a] = nil }
                default: break
                }
                if case .daiminkan(let a, _, _, _) = e, rules.temporaryFuritenEndsOnCall { declined[a] = nil }
            }
            all += out
            queue = out.map(Self.message)
        }
        if !queue.isEmpty {
            // Mahjong Soul: the dora the engine reveals last, after an end the log omits.
            fail(&r, n, "sequence:log_ends/\(queue[0].type)", "the log ends before the engine's \(queue[0].type)"); return nil
        }
        guard let result = state.result else { fail(&r, n, "sequence:unfinished", "the hand did not end"); return nil }
        if !earlyDora.isEmpty { tags.append("early_dora_never_revealed") }
        // The optional end_kyoku result fields.
        if let end = events.last, end.type == "end_kyoku" {
            if let s = end.scores, s != result.scores { fail(&r, n - 1, "end_kyoku.scores", "end_kyoku.scores \(s), engine \(result.scores)") }
            if let d = end.deltas, d != result.deltas { fail(&r, n - 1, "end_kyoku.deltas", "end_kyoku.deltas \(d), engine \(result.deltas)") }
            if let k = end.kyotakuLeft, k != result.sticks { fail(&r, n - 1, "end_kyoku.kyotaku_left", "end_kyoku.kyotaku_left \(k), engine \(result.sticks)") }
            if let d = end.dealerRepeats, d != result.dealerRepeats { fail(&r, n - 1, "end_kyoku.dealer_repeats", "end_kyoku.dealer_repeats") }
        }
        for w in result.wins where state.riichiStatus(of: w.winner) == .accepted {
            if !events.contains(where: { $0.type == "hora" && $0.uraMarkers != nil }) { r.note("unseen_ura") }
        }
        let needsHeader = inferredRon || events.contains { ($0.type == "hora" || $0.type == "ryukyoku") && $0.deltas == nil }
        if inferredRon { tags.append("missing_hora_inferred") }
        tags += Self.handTags(all, result: result, state: state, honba: honba, sticks: sticks, rules: rules)
        for t in tags { r.tags.append((hand, t)) }
        return HandOutcome(hand: hand, result: result, position: pos, state: state, engine: all, slots: slots,
                           needsHeader: needsHeader)
    }

    /// Whether some kan or ura indicator a win could use is not in the log.
    var hasHiddenIndicators: Bool {
        events.contains { $0.type == "hora" && $0.uraMarkers == nil }
            || events.filter({ ["ankan", "kakan", "daiminkan"].contains($0.type) }).count > events.filter({ $0.type == "dora" }).count
    }

    /// Reduced format: an assignment of the hidden kan and ura indicators under
    /// which the hand gives `header`.
    func searchHidden(_ o: HandOutcome, header: GamePosition) -> HandOutcome? {
        searchHidden(o) { flow($0, rules).0 == header }
    }

    func searchHidden(_ o: HandOutcome, where accept: (HandOutcome) -> Bool) -> HandOutcome? {
        let wins = o.result.wins
        guard !wins.isEmpty else { return nil }
        let kans = o.state.kanCount
        var hidden: [Int] = (0..<kans).map { 127 + $0 }.filter { o.slots[$0] == nil }
        let riichiWinners = wins.filter { o.state.riichiStatus(of: $0.winner) == .accepted }
        if !riichiWinners.isEmpty { hidden += (0...kans).map { 131 + $0 }.filter { o.slots[$0] == nil } }
        guard !hidden.isEmpty else { return nil }
        // Each winner's 14+ tiles, by kind.
        func held(_ w: Win) -> [Int] {
            var c = [Int](repeating: 0, count: 34)
            for e in o.engine {
                if case .hora(let a, _, let t, _, _, let tehai, _, _) = e, a == w.winner {
                    for x in tehai + [t] { c[x.kind.index] += 1 }
                }
            }
            for m in o.state.melds(of: w.winner) { for x in m.tiles { c[x.kind.index] += 1 } }
            return c
        }
        let all = wins.map(held), ura = riichiWinners.map(held)
        let pool = Self.pool(o.slots)
        // Per slot: the unseen tiles grouped by their effect on the winners.
        var choices: [[[Int]]] = []  // slot -> group -> indices into pool
        for s in hidden {
            let counts = s < 131 ? all : ura
            var groups: [[Int]: [Int]] = [:]
            for (i, t) in pool.enumerated() { groups[counts.map { $0[t.kind.doraSuccessor.index] }, default: []].append(i) }
            choices.append(groups.keys.sorted { $0.lexicographicallyPrecedes($1) }.map { groups[$0]! })
        }
        var tried = 0
        var pick = [Int](repeating: 0, count: hidden.count)
        while tried < 20_000 {
            tried += 1
            var slots = o.slots
            var used: Set<Int> = []
            var ok = true
            for (i, s) in hidden.enumerated() {
                guard let k = choices[i][pick[i]].first(where: { !used.contains($0) }) else { ok = false; break }
                used.insert(k)
                slots[s] = pool[k]
            }
            if ok {
                var c = self
                var scratch = CheckReport()
                if let o2 = c.run(&scratch, slots: slots), scratch.diffs.isEmpty, accept(o2) {
                    return o2
                }
            }
            // Next combination.
            var i = 0
            while i < pick.count {
                pick[i] += 1
                if pick[i] < choices[i].count { break }
                pick[i] = 0
                i += 1
            }
            if i == pick.count { break }
        }
        return nil
    }

    /// The situations of a hand that the frequency table and the rulings count.
    static func handTags(_ events: [Event], result: RoundResult, state: RoundState, honba: Int, sticks: Int,
                         rules: Rules) -> [String] {
        var tags: [String] = []
        var accepted: Set<Seat> = []
        var openKanBy: Seat? = nil        // made an open or added kan, not yet discarded
        var discardAfterOpenKan = false    // the last discard was that seat's
        var lastKan: String? = nil         // the kan before the current draw
        var riichiDiscard: Seat? = nil     // declared riichi on the last discard
        var declaring: Seat? = nil
        var kans = [Int](repeating: 0, count: 4)
        var chainedKakan = false
        for e in events {
            switch e {
            case .reach(let a): declaring = a
            case .reachAccepted(let a, _): accepted.insert(a); riichiDiscard = nil
            case .dahai(let a, _, _):
                discardAfterOpenKan = openKanBy == a
                openKanBy = nil
                riichiDiscard = declaring == a ? a : nil
                declaring = nil
                lastKan = nil
            case .tsumo: discardAfterOpenKan = false
            case .chi, .pon: discardAfterOpenKan = false
            case .daiminkan(let a, _, _, _):
                kans[a.index] += 1; openKanBy = a; lastKan = "daiminkan"; discardAfterOpenKan = false
                tags.append("open_kan")
            case .kakan(let a, _, _):
                chainedKakan = openKanBy == a  // an earlier open kan's indicator is owed
                kans[a.index] += 1; openKanBy = a; lastKan = "kakan"
                tags.append("open_kan")
            case .ankan(let a, _):
                kans[a.index] += 1; lastKan = "ankan"
                if accepted.contains(a) { tags.append("riichi_ankan") }
            case .hora(let a, let t, _, _, _, _, _, _):
                if a != t, openKanBy == t, lastKan == "kakan", chainedKakan { tags.append("chankan_of_chained_kan") }
                if a == t {
                    if let k = lastKan { tags.append("rinshan_after_\(k)") }
                } else {
                    if discardAfterOpenKan {
                        tags.append(accepted.contains(a) ? "ron_after_open_kan_riichi" : "ron_after_open_kan")
                    }
                    if riichiDiscard == t { tags.append("riichi_discard_ronned") }
                }
            case .ryukyoku(.abort(.suufonRenda), _, _, _, _):
                if riichiDiscard != nil { tags.append("riichi_on_kaze4") }
            default: break
            }
        }
        if kans.contains(4) { tags.append("four_kans_one_seat") }
        switch result.outcome {
        case .wins(let ws):
            if ws.count > 1 {
                tags.append("ron_x\(ws.count)")
                if honba > 0 { tags.append("multi_ron_honba") }
                if sticks > 0 || !accepted.isEmpty { tags.append("multi_ron_sticks") }
            }
            for w in ws {
                tags.append(w.isTsumo ? "tsumo" : "ron")
                // A pair of the wind that is both seat and round wind (double-wind fu).
                let seatWind = Kind(.honor, w.winner.distance(from: result.dealer) + 1)
                if seatWind == Kind(.honor, state.roundWind.rawValue) {
                    var n = 0
                    for e in events {
                        if case .hora(let a, _, let t, _, _, let h, _, _) = e, a == w.winner {
                            n = (h + [t]).filter { $0.kind == seatWind }.count
                        }
                    }
                    if n == 2 { tags.append("double_wind_pair") }
                }
                if let k = w.robbedKan { tags.append(k == .added ? "chankan" : "chankan_ankan") }
                if w.scored.value(of: .rinshan) != nil { tags.append("rinshan") }
                switch w.scored.value {
                case .yakuman(let m):
                    for y in w.scored.yaku { if case .yaku(let n) = y.name { tags.append("yakuman_\(n.rawValue)") } }
                    if m > 1 { tags.append("yakuman_multiple") }
                case .ordinary(let han, _):
                    if han >= 13 { tags.append("kazoe") }
                }
                if let l = w.liable {
                    tags.append("pao")
                    tags.append(w.isTsumo ? "pao_tsumo" : (w.from == l ? "pao_ron_liable" : "pao_ron_third"))
                    if honba > 0 { tags.append("pao_honba") }
                    if case .yakuman = w.scored.value, w.scored.yaku.count > 1 { tags.append("pao_composite") }
                }
            }
        case .exhaustiveDraw(let tenpai, let nagashi):
            tags.append("exhaustive")
            if !nagashi.isEmpty {
                tags.append("nagashi")
                if nagashi.count > 1 { tags.append("nagashi_x\(nagashi.count)") }
                if honba > 0 { tags.append("nagashi_honba") }
                if sticks > 0 || !accepted.isEmpty { tags.append("nagashi_sticks") }
                if nagashi.contains(result.dealer) { tags.append("nagashi_by_dealer") }
                tags.append(tenpai.contains(result.dealer) ? "nagashi_dealer_tenpai" : "nagashi_dealer_noten")
            }
            // A seat whose only waits are fifth copies.
            for s in Seat.all {
                let w = state.waits(of: s)
                guard !w.isEmpty else { continue }
                var conc = [Int](repeating: 0, count: 34), meld = conc
                for t in state.hand(of: s) { conc[t.kind.index] += 1 }
                if let d = state.drawnTile(of: s) { conc[d.kind.index] += 1 }
                for m in state.melds(of: s) { for t in m.tiles { meld[t.kind.index] += 1 } }
                let tenhou = w.contains { conc[$0.index] < 4 }
                let soul = w.contains { conc[$0.index] + meld[$0.index] < 4 }
                if tenhou != soul { tags.append("fifth_copy_wait_at_draw") }
            }
        case .abortiveDraw(let a):
            tags.append("abort_\(a.rawValue)")
        }
        return tags
    }

    /// An engine event in the log's terms.
    static func message(_ e: Event) -> MjaiMessage {
        var m = MjaiMessage(type: e.type)
        m.actor = e.actor?.index
        switch e {
        case .startKyoku(_, _, _, _, _, let d, let s, _): m.doraMarker = d; m.scores = s
        case .tsumo(_, let t): m.pai = t
        case .dahai(_, let t, let g): m.pai = t; m.tsumogiri = g
        case .chi(_, let tg, let t, let c), .pon(_, let tg, let t, let c), .daiminkan(_, let tg, let t, let c):
            m.target = tg.index; m.pai = t; m.consumed = c
        case .ankan(_, let c): m.consumed = c
        case .kakan(_, let t, let c): m.pai = t; m.consumed = c
        case .dora(let d): m.doraMarker = d
        case .reachAccepted(_, let s): m.scores = s
        case .hora(_, let tg, let t, let d, let u, let h, let sc, let s):
            m.target = tg.index; m.pai = t; m.deltas = d; m.uraMarkers = u; m.scores = s
            m.horaTehais = h
            if case .ordinary(let han, let fu) = sc.value { m.fan = han; m.fu = fu }
        case .ryukyoku(let r, let d, let tp, _, let s):
            m.deltas = d; m.scores = s; m.tenpais = tp
            if case .abort(let a) = r { m.reason = a.rawValue }
        default: break
        }
        return m
    }

    /// The first field in which a logged event differs from the engine's.
    static func differs(_ log: MjaiMessage, _ mine: MjaiMessage, ignoring: Set<String> = []) -> (String, String)? {
        if log.type != mine.type { return ("type", "log has \(log.type), engine \(mine.type)") }
        func cmp<T: Equatable>(_ what: String, _ a: T?, _ b: T?) -> (String, String)? {
            guard let a, !ignoring.contains(what) else { return nil }  // a field the log does not give is not checked
            return a == b ? nil : (what, "\(log.type).\(what): log \(a), engine \(b.map { "\($0)" } ?? "none")")
        }
        let results = log.type == "end_kyoku" || log.type == "start_kyoku"
        if let d = cmp("actor", log.actor, mine.actor) { return d }
        if let d = cmp("target", log.target, mine.target) { return d }
        if log.type != "start_kyoku", let d = cmp("pai", log.pai, mine.pai) { return d }
        if let d = cmp("consumed", log.consumed?.sorted(), mine.consumed?.sorted()) { return d }
        if let d = cmp("tsumogiri", log.tsumogiri, mine.tsumogiri) { return d }
        if let d = cmp("dora_marker", log.doraMarker, mine.doraMarker) { return d }
        if !results, let d = cmp("deltas", log.deltas, mine.deltas) { return d }
        if !results, let d = cmp("scores", log.scores, mine.scores) { return d }
        if let d = cmp("ura_markers", log.uraMarkers, mine.uraMarkers) { return d }
        if let d = cmp("tenpais", log.tenpais, mine.tenpais) { return d }
        if let d = cmp("hora_tehais", log.horaTehais?.sorted(), mine.horaTehais?.sorted()) { return d }
        // Fu and han of an ordinary hand (yakuman conventions differ between writers).
        if mine.fan != nil, let d = cmp("fan", log.fan, mine.fan) { return d }
        if mine.fu != nil, let d = cmp("fu", log.fu, mine.fu) { return d }
        if log.type == "ryukyoku", let reason = log.reason, !ignoring.contains("reason") {
            // The converter's tenhou.net names, or ours; an exhaustive draw has none.
            let names = ["yao9": "kyuushu", "kaze4": "suufon_renda", "reach4": "suucha_riichi",
                         "kan4": "suukaikan", "ron3": "sanchahou"]
            let want = names[reason] ?? reason
            if want != (mine.reason ?? "exhaustive") {
                return ("reason", "ryukyoku.reason: log \(reason), engine \(mine.reason ?? "exhaustive")")
            }
        }
        return nil
    }
}

extension Mjai {
    /// An engine event as the log would read it.
    static func decode0(_ e: Event) -> MjaiMessage { try! decode(encode(e)) }
}

/// `--set field=value`: one `Rules` field.
func setRule(_ r: inout Rules, _ spec: String) throws {
    guard let eq = spec.firstIndex(of: "=") else { throw UsageError(description: "--set field=value") }
    let k = String(spec[..<eq]), v = String(spec[spec.index(after: eq)...])
    func b() throws -> Bool {
        switch v {
        case "true", "1", "on": return true
        case "false", "0", "off": return false
        default: throw UsageError(description: "--set \(k) wants true or false")
        }
    }
    func i() throws -> Int {
        guard let n = Int(v) else { throw UsageError(description: "--set \(k) wants a number") }
        return n
    }
    switch k {
    case "startingPoints": r.startingPoints = try i()
    case "returnPoints": r.returnPoints = try i()
    case "targetPoints": r.targetPoints = try i()
    case "length":
        switch v {
        case "east": r.length = .east
        case "south": r.length = .south
        default: throw UsageError(description: "--set length wants east or south")
        }
    case "dealerRepeatBeforeTarget": r.dealerRepeatBeforeTarget = try b()
    case "allLastTestAfterNagashi": r.allLastTestAfterNagashi = try b()
    case "doubleYakuman": r.doubleYakuman = try b()
    case "tenhouAnyWinningTile": r.tenhouAnyWinningTile = try b()
    case "kuitan": r.kuitan = try b()
    case "doubleWindPairFu": r.doubleWindPairFu = try i()
    case "tripleRonAborts": r.tripleRonAborts = try b()
    case "honbaToEveryRonWinner": r.honbaToEveryRonWinner = try b()
    case "kokushiRobsClosedKan": r.kokushiRobsClosedKan = try b()
    case "openKanDoraBeforeRon": r.openKanDoraBeforeRon = try b()
    case "owedDoraAtChainedAddedKan": r.owedDoraAtChainedAddedKan = try b()
    case "paoCoversWholeHand": r.paoCoversWholeHand = try b()
    case "riichiOnFifthCopyWait": r.riichiOnFifthCopyWait = try b()
    case "fifthCopyTenpaiAtDraw": r.fifthCopyTenpaiAtDraw = try b()
    case "fourWindsRiichiStickPaid": r.fourWindsRiichiStickPaid = try b()
    case "temporaryFuritenEndsOnCall": r.temporaryFuritenEndsOnCall = try b()
    case "temporaryFuritenOnDeclinedTsumo": r.temporaryFuritenOnDeclinedTsumo = try b()
    default: throw UsageError(description: "--set: no Rules field \(k)")
    }
}

/// A JSON string literal.
func jsonString(_ s: String) -> String {
    var out = "\""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        default:
            if ch.value < 0x20 { out += "\\u00" + (ch.value < 16 ? "0" : "") + String(ch.value, radix: 16) }
            else { out.unicodeScalars.append(ch) }
        }
    }
    return out + "\""
}

extension CheckReport {
    /// One line: `{"g":…,"lite":…,"h":…,"d":[[hand,event,category,message]…],"c":{…},"u":{…},"t":[[hand,tag]…]}`.
    var json: String {
        func dict(_ d: [String: Int]) -> String {
            "{" + d.keys.sorted().map { "\(jsonString($0)):\(d[$0]!)" }.joined(separator: ",") + "}"
        }
        let d = diffs.map { "[\($0.hand),\($0.event),\(jsonString($0.category)),\(jsonString($0.message))]" }
        let t = tags.map { "[\($0.0),\(jsonString($0.1))]" }
        return "{\"g\":\(jsonString(path)),\"lite\":\(lite ? 1 : 0),\"h\":\(hands),\"d\":[\(d.joined(separator: ","))],"
            + "\"c\":\(dict(conventions)),\"u\":\(dict(unchecked)),\"t\":[\(t.joined(separator: ","))]}"
    }
}

/// Framed games on standard input: `NAME LENGTH\n` then LENGTH bytes.
struct FramedInput: IteratorProtocol {
    var buffer: [UInt8] = []
    var start = 0
    var eof = false

    mutating func fill() -> Bool {
        if eof { return false }
        if start > 0 { buffer.removeFirst(start); start = 0 }
        var chunk = [UInt8](repeating: 0, count: 1 << 20)
        var n: Int
        repeat { n = read(0, &chunk, chunk.count) } while n < 0 && errno == EINTR
        if n <= 0 { eof = true; return false }
        buffer += chunk[0..<n]
        return true
    }

    mutating func next() -> (String, String)? {
        var nl: Int? = nil
        while true {
            if let k = buffer[start...].firstIndex(of: 10) { nl = k; break }
            if !fill() { return nil }
        }
        let header = String(decoding: buffer[start..<nl!], as: UTF8.self)
        let parts = header.split(separator: " ")
        guard parts.count == 2, let len = Int(parts[1]) else { return nil }
        start = nl! + 1
        while buffer.count - start < len { if !fill() { return nil } }
        let text = String(decoding: buffer[start..<start + len], as: UTF8.self)
        start += len
        return (String(parts[0]), text)
    }
}

/// `mj check-log [--rules tenhou] [--set field=value]... [--json] [--stdin] FILE...`
func checkLogCommand(_ args: [String]) throws -> Int32 {
    let o = try Options(args, flags: ["json", "stdin"])
    var rules = try o.rules()
    for s in o.sets { try setRule(&rules, s) }
    guard rules.isValid else { throw UsageError(description: "--set: a Rules value out of range (Rules.isValid)") }
    let json = o.flags.contains("json")
    var errors = 0, hands = 0, files = 0
    var unchecked: [String: Int] = [:], conventions: [String: Int] = [:]
    func take(_ r: CheckReport) {
        files += 1
        hands += r.hands
        errors += r.diffs.count
        if json {
            print(r.json)
            fflush(stdout)
        } else {
            for e in r.errors.prefix(10) { print(e) }
        }
        for (k, v) in r.unchecked { unchecked[k, default: 0] += v }
        for (k, v) in r.conventions { conventions[k, default: 0] += v }
    }
    if o.flags.contains("stdin") {
        var input = FramedInput()
        while let (name, text) = input.next() { take(checkLog(text: text, rules: rules, path: name)) }
    }
    for path in o.positional { take(checkLog(text: try readFile(path), rules: rules, path: path)) }
    if json { return 0 }
    print("files=\(files) hands=\(hands) errors=\(errors)")
    print("conventions: " + (conventions.isEmpty ? "-" : conventions.keys.sorted().map { "\($0)=\(conventions[$0]!)" }.joined(separator: " ")))
    print("not checked: " + (unchecked.isEmpty ? "-" : unchecked.keys.sorted().map { "\($0)=\(unchecked[$0]!)" }.joined(separator: " ")))
    return errors == 0 ? 0 : 1
}
