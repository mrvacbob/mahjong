// Runs scenarios/*.scn (expanded to JSON by tools/scenario.py --json-dir) through
// the engine: each scenario's round is the first hand of a `GameState` started at
// the scenario's position, so the game-flow expectations (endgame_*) are checked
// against the after-round transition. Disputed scenarios are known issues with a one-line reason;
// docs/notes/p3-B.md has the working.

import Foundation
import Testing
@testable import Riichi

/// Scenarios this engine disagrees with, and why. A disputed scenario that starts
/// passing fails the run (the known issue is not recorded), so this list cannot go
/// stale silently.
let disputedScenarios: [String: String] = [:]

enum ScenarioFiles {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let names: [String] = {
        let dir = root.appendingPathComponent("scenarios")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".scn") }.map { String($0.dropLast(4)) }.sorted()
    }()

    /// Every scenario expanded once per test process.
    static let jsonDir: Result<URL, ScenarioFailure> = {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("riichi-scenarios-\(ProcessInfo.processInfo.processIdentifier)")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3.14", root.appendingPathComponent("tools/scenario.py").path,
                       "--json-dir", out.path, root.appendingPathComponent("scenarios").path]
        do { try p.run() } catch { return .failure(ScenarioFailure("cannot run python3.14: \(error)")) }
        p.waitUntilExit()
        return .success(out)
    }()

    static func load(_ name: String) throws -> [String: Any] {
        let dir = try jsonDir.get()
        let data = try Data(contentsOf: dir.appendingPathComponent("\(name).json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

struct ScenarioFailure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

@Suite struct ScenarioTests {
    @Test(arguments: ScenarioFiles.names) func scenario(_ name: String) throws {
        let json = try ScenarioFiles.load(name)
        if let error = json["error"] as? String {
            if let reason = disputedScenarios[name] {
                withKnownIssue(Comment(rawValue: reason)) { Issue.record("scenario.py rejects \(name): \(error)") }
            } else {
                Issue.record("scenario.py rejects \(name): \(error)")
            }
            return
        }
        let runs = try #require(json["runs"] as? [String: Any])
        for (ruleset, run) in runs.sorted(by: { $0.key < $1.key }) {
            let label = "\(name) [\(ruleset)]"
            let problems = ScenarioRunner(json: json, ruleset: ruleset, spec: run as! [String: Any]).run()
            let reason = disputedScenarios[name] ?? disputedScenarios["\(name).\(ruleset)"]
            if let reason {
                withKnownIssue(Comment(rawValue: "\(label): \(reason)")) {
                    for p in problems { Issue.record("\(label): \(p)") }
                }
            } else {
                for p in problems { Issue.record("\(label): \(p)") }
            }
        }
    }

    @Test func everyDisputeNamesAScenario() {
        #expect(!ScenarioFiles.names.isEmpty)
        for name in disputedScenarios.keys {
            let base = name.split(separator: ".").first.map(String.init) ?? name
            #expect(ScenarioFiles.names.contains(base), "disputed scenario \(name) does not exist")
        }
    }
}

/// One ruleset's run of one scenario. Returns every disagreement found.
struct ScenarioRunner {
    let json: [String: Any]
    let ruleset: String
    let spec: [String: Any]
    /// Overrides the ruleset's preset (to test one `Rules` field against a scenario).
    var rules: Rules? = nil

    func tile(_ s: Any?) -> Tile? { (s as? String).flatMap { Tile(Substring($0)) } }
    func tiles(_ s: Any?) -> [Tile] { ((s as? [String]) ?? []).compactMap { Tile(Substring($0)) } }

    func run() -> [String] {
        var problems: [String] = []
        var rules: Rules = self.rules ?? (ruleset == "tenhou" ? .tenhou : .mahjongSoul)
        let round = json["round"] as! [String: Any]
        guard let wall = Wall(tiles: tiles(json["wall"])) else { return ["bad wall"] }
        let wind = Wind(letter: Substring(round["wind"] as! String))!
        if let length = round["game_length"] as? String { rules.length = length == "east" ? .east : .south }
        let position = GamePosition(roundWind: wind, kyoku: round["round"] as! Int,
                                    honba: round["honba"] as! Int, sticks: round["sticks"] as! Int,
                                    scores: round["scores"] as? [Int] ?? [25_000, 25_000, 25_000, 25_000])
        guard position.dealer.index == round["dealer"] as! Int else {
            return ["dealer \(round["dealer"]!) is not seat kyoku − 1 (\(position.dealer))"]
        }
        var events: [Event] = []
        var state = GameState(rules: rules, seed: 0, position: position, wall: wall, startGame: false,
                              events: &events)
        let steps = spec["steps"] as? [[String: Any]] ?? []

        for (n, step) in steps.enumerated() {
            let at = "step \(n + 1) (\(describe(step)))"
            do {
                try perform(step, &state, &events)
            } catch let f as ScenarioFailure {
                problems.append("\(at): \(f)")
                return problems
            } catch {
                problems.append("\(at): \(error) [phase \(state.phase), legal \(legalSummary(state))]")
                return problems
            }
        }
        guard let (result, transition) = state.lastRound else {
            return problems + ["round did not end; phase \(state.phase), legal \(legalSummary(state))"]
        }
        // This hand's events, and end_game if the game ended with it.
        let end = events.firstIndex(of: .endKyoku)!
        var mine = Array(events[...end])
        // end_game is compared only where the scenario's event list names it (round
        // scenarios with unusual scores can end the game without saying so).
        let expect = spec["expect"] as? [String: Any] ?? [:]
        let named = ((expect["events"] as? [String] ?? []) + (expect["events_order"] as? [String] ?? []))
            .contains("end_game")
        if named, end + 1 < events.count, case .endGame = events[end + 1] { mine.append(events[end + 1]) }
        problems += check(spec["expect"] as? [String: Any] ?? [:], result, mine, position)
        problems += checkGame(spec["expect"] as? [String: Any] ?? [:], transition, state)
        return problems
    }

    func describe(_ step: [String: Any]) -> String {
        step.filter { $0.key != "type" }.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            .replacingOccurrences(of: "\n", with: "")
    }

    func legalSummary(_ g: GameState) -> String {
        let s = g.round
        return Seat.all.compactMap { seat in
            let a = s.legalActions(for: seat)
            return a.isEmpty ? nil : "\(seat): \(a.map(\.description).joined(separator: " "))"
        }.joined(separator: "; ")
    }

    func perform(_ step: [String: Any], _ state: inout GameState, _ events: inout [Event]) throws {
        let seat = (step["seat"] as? Int).map(Seat.init)
        // Steps act on the scenario's hand only. Once it is over nothing is legal in it.
        if state.lastRound != nil {
            switch step["type"] as! String {
            case "assert_illegal", "assert_not_asked": return
            default: throw ScenarioFailure("the hand is over (the game is at \(state.position))")
            }
        }
        switch step["type"] as! String {
        case "turn":
            let seat = seat!
            let action: Action
            switch step["action"] as! String {
            case "discard":
                let tsumogiri = step["tsumogiri"] as? Bool ?? false
                if tsumogiri {
                    guard let d = state.round.drawnTile(of: seat) else { throw ScenarioFailure("no drawn tile to tsumogiri") }
                    if let t = tile(step["tile"]), t != d {
                        throw ScenarioFailure("tsumogiri \(t) but the drawn tile is \(d)")
                    }
                    action = .discard(d, tsumogiri: true)
                } else {
                    action = .discard(tile(step["tile"])!, tsumogiri: false)
                }
            case "riichi": action = .riichi
            case "tsumo": action = .tsumo
            case "kyuushu": action = .kyuushu
            case "ankan": action = .ankan(tile(step["kind"])!.kind)
            case "kakan": action = .kakan(tile(step["tile"])!)
            case let a: throw ScenarioFailure("unknown turn action \(a)")
            }
            try state.apply(action, by: seat, events: &events)
        case "window":
            let given = step["answers"] as? [String: [String: Any]] ?? [:]
            var answers = Answers()
            let asked = state.seatsToAnswer
            guard !asked.isEmpty else {
                throw ScenarioFailure("no window is open (phase \(state.phase))")
            }
            for s in Seat.all {
                guard let g = given[String(s.index)] else {
                    if asked.contains(s) { answers[s] = .pass }
                    continue
                }
                let a = windowAction(g)
                if !asked.contains(s) && a != .pass {
                    throw ScenarioFailure("seat \(s) answers \(a) but is not asked (legal: \(legalSummary(state)))")
                }
                if asked.contains(s) { answers[s] = a }
            }
            try state.resolve(answers, events: &events)
        case "auto_tsumogiri":
            for _ in 0..<(step["count"] as! Int) {
                if state.lastRound != nil { break }
                guard case .turn(let s, _) = state.phase, let d = state.round.drawnTile(of: s) else {
                    throw ScenarioFailure("auto_tsumogiri: no seat with a drawn tile (phase \(state.phase))")
                }
                try state.apply(.discard(d, tsumogiri: true), by: s, events: &events)
                while !state.seatsToAnswer.isEmpty {
                    var answers = Answers()
                    for s in state.seatsToAnswer { answers[s] = .pass }
                    try state.resolve(answers, events: &events)
                }
            }
        case "assert_legal", "assert_illegal":
            let target = step["target"] as! [String: Any]
            let legal = state.legalActions(for: seat!)
            let found = legal.contains { matches($0, target) }
            let want = step["type"] as! String == "assert_legal"
            if found != want {
                throw ScenarioFailure("expected \(target) \(want ? "legal" : "illegal") for seat \(seat!); legal: \(legal.map(\.description))")
            }
        case "assert_furiten":
            let want = step["expected"] as! Bool
            if state.round.isFuriten(seat!) != want {
                throw ScenarioFailure("seat \(seat!) furiten is \(!want), expected \(want)")
            }
        case "assert_not_asked":
            let legal = state.legalActions(for: seat!)
            if !legal.isEmpty {
                throw ScenarioFailure("seat \(seat!) is asked: \(legal.map(\.description))")
            }
        case let t:
            throw ScenarioFailure("unknown step type \(t)")
        }
    }

    func windowAction(_ g: [String: Any]) -> Action {
        let using = tiles(g["using"]).sorted()
        switch g["action"] as! String {
        case "ron": return .ron
        case "daiminkan": return .daiminkan
        case "pon": return .pon(using[0], using[1])
        case "chi": return .chi(using[0], using[1])
        default: return .pass
        }
    }

    func matches(_ a: Action, _ target: [String: Any]) -> Bool {
        let t = tile(target["tile"])
        let using = target["using"].map { tiles($0).sorted() }
        switch (a, target["action"] as! String) {
        case (.discard(let x, _), "discard"): return t == nil || t == x
        case (.discard(let x, true), "tsumogiri"): return t == nil || t == x
        case (.riichi, "riichi"), (.tsumo, "tsumo"), (.kyuushu, "kyuushu"), (.ron, "ron"),
             (.daiminkan, "daiminkan"), (.pass, "pass"):
            return true
        case (.ankan(let k), "ankan"): return t == nil || t!.kind == k
        case (.kakan(let x), "kakan"): return t == nil || t == x
        case (.pon(let x, let y), "pon"), (.chi(let x, let y), "chi"): return using == nil || using! == [x, y]
        default: return false
        }
    }

    func check(_ expect: [String: Any], _ r: RoundResult, _ events: [Event], _ position: GamePosition) -> [String] {
        var p: [String] = []
        func eq<T: Equatable>(_ what: String, _ got: T, _ want: T?) {
            if let want, got != want { p.append("\(what): got \(got), expected \(want)") }
        }
        let outcome: String, reason: String?
        switch r.outcome {
        case .wins(let w): outcome = w[0].isTsumo ? "tsumo" : "ron"; reason = nil
        case .exhaustiveDraw: outcome = "exhaustive_draw"; reason = nil
        case .abortiveDraw(let a): outcome = "abortive_draw"; reason = a.rawValue
        }
        eq("outcome", outcome, expect["outcome"] as? String)
        eq("abort_reason", reason ?? "-", expect["abort_reason"] as? String)
        eq("winners", r.wins.map(\.winner.index), expect["winners"] as? [Int])
        if case .exhaustiveDraw(let tenpai, let nagashi) = r.outcome {
            eq("tenpai", tenpai.map(\.index), expect["tenpai"] as? [Int])
            eq("nagashi", nagashi.map(\.index), expect["nagashi"] as? [Int])
        }
        for (seatText, w) in (expect["wins"] as? [String: [String: Any]] ?? [:]) {
            guard let win = r.wins.first(where: { $0.winner.index == Int(seatText) }) else {
                p.append("win \(seatText): not a winner"); continue
            }
            let s = win.scored
            switch s.value {
            case .ordinary(let han, let fu):
                eq("win \(seatText) han", han, w["han"] as? Int)
                eq("win \(seatText) fu", fu, w["fu"] as? Int)
                if w["yakuman"] != nil { p.append("win \(seatText): expected yakuman, got \(s.yakuText)") }
            case .yakuman(let n):
                eq("win \(seatText) yakuman", n, w["yakuman"] as? Int)
                if w["han"] != nil { p.append("win \(seatText): expected han, got yakuman \(s.yakuText)") }
            }
            if let want = w["yaku"] as? [String] {
                let gotNames = s.yaku.map(\.name.text).sorted()
                let wantNames = want.map { String($0.split(separator: ":")[0]) }.sorted()
                let valuesOK = want.allSatisfy { y in
                    let parts = y.split(separator: ":")
                    guard parts.count == 2 else { return true }
                    return s.yaku.contains { $0.name.text == parts[0] && "\($0.value)" == parts[1] }
                }
                if gotNames != wantNames || !valuesOK {
                    p.append("win \(seatText) yaku: got \(s.yakuText), expected \(want.joined(separator: ","))")
                }
            }
        }
        eq("deltas", r.deltas, expect["deltas"] as? [Int])
        eq("scores", r.scores, expect["scores"] as? [Int])
        eq("sticks", r.sticks, expect["sticks"] as? Int)
        eq("honba", r.nextHonba(after: position.honba), expect["honba"] as? Int)
        eq("dealer_repeats", r.dealerRepeats, expect["dealer_repeats"] as? Bool)

        let texts = events.map(\.text)
        func same(_ got: String, _ want: String) -> Bool {
            want.contains("(") ? got == want : got.split(separator: "(")[0] == want
        }
        if let want = expect["events"] as? [String] {
            if texts.count != want.count || !zip(texts, want).allSatisfy(same) {
                p.append("events:\n  got      \(texts.joined(separator: ", "))\n  expected \(want.joined(separator: ", "))")
            }
        }
        if let want = expect["events_order"] as? [String] {
            var i = 0
            for t in texts where i < want.count && same(t, want[i]) { i += 1 }
            if i < want.count {
                p.append("events_order: \(want[i]) (item \(i + 1)) not found in order; got \(texts.joined(separator: ", "))")
            }
        }
        return p
    }

    /// The after-round transition: game end, the next hand, the final result.
    func checkGame(_ expect: [String: Any], _ transition: GameTransition, _ g: GameState) -> [String] {
        var p: [String] = []
        func eq<T: Equatable>(_ what: String, _ got: T, _ want: T?) {
            if let want, got != want { p.append("\(what): got \(got), expected \(want) (transition \(transition))") }
        }
        eq("game_ended", g.isOver, expect["game_ended"] as? Bool)
        if g.isOver {
            for key in ["next_wind", "next_round", "next_dealer"] where expect[key] != nil {
                p.append("expects \(key) but the game ended (transition \(transition))")
            }
        } else {
            let letters = [Wind.east: "E", .south: "S", .west: "W", .north: "N"]
            eq("next_wind", letters[g.position.roundWind]!, expect["next_wind"] as? String)
            eq("next_round", g.position.kyoku, expect["next_round"] as? Int)
            eq("next_dealer", g.position.dealer.index, expect["next_dealer"] as? Int)
        }
        if let r = g.result {
            eq("final_scores", r.scores, expect["final_scores"] as? [Int])
            eq("final_ranks", r.ranks.map(\.index), expect["final_ranks"] as? [Int])
            eq("adjusted_scores", r.adjusted, expect["adjusted_scores"] as? [Int])
        } else {
            for key in ["final_scores", "final_ranks", "adjusted_scores"] where expect[key] != nil {
                p.append("expects \(key) but the game did not end (transition \(transition))")
            }
        }
        return p
    }
}
