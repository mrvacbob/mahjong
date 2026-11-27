// Runs scenarios/*.scn (expanded to JSON by tools/scenario.py --json-dir) through
// the round engine. Scenarios about game end (endgame_*) wait for package C and are
// listed as disabled. Disputed scenarios are known issues with a one-line reason;
// docs/notes/p3-B.md has the working.

import Foundation
import Testing
@testable import Riichi

/// Scenarios this engine disagrees with, and why. A disputed scenario that starts
/// passing fails the run (the known issue is not recorded), so this list cannot go
/// stale silently.
let disputedScenarios: [String: String] = [
    "closed_kan_rinshan_tsumo":
        "all four first discards are 3z (West) with no call: four winds aborts at seat 3's discard",
    "riichi_furiten_skipped_tsumo_ankan":
        "all four first discards are 3z (West): four winds aborts; and 23444s 678m 234p 88p also waits on 8p (234s+44s+88p), so ankan 4s changes the waits and is illegal",
    "kan_one_live_tile_rinshan_not_haitei":
        "the dealer wins, so honba becomes 1, not 0 (design §5 step 2; the file's own dealer_repeats is true)",
    "last_tile_houtei_no_calls":
        "the dealer wins, so honba becomes 1, not 0 (design §5 step 2; the file's own dealer_repeats is true)",
    "riichi_ankan_waits":
        "after ankan 6666s, 23m 999p 33345s + 1m reads only 33s+345s: two concealed triplets, no sanankou (4 han 50 fu)",
    // Second batch, not yet reviewed.
    "nagashi_mangan_dealer":
        "expects ryukyoku(nagashi_mangan); a nagashi is an exhaustive draw (design §4.3), as reviewed nagashi_mangan_tenpai_dealer expects ryukyoku(exhaustive)",
    "nagashi_mangan_multiple_winners":
        "expects ryukyoku(nagashi_mangan); a nagashi is an exhaustive draw (design §4.3), as reviewed nagashi_mangan_tenpai_dealer expects ryukyoku(exhaustive)",
]

enum ScenarioFiles {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let names: [String] = {
        let dir = root.appendingPathComponent("scenarios")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".scn") }.map { String($0.dropLast(4)) }.sorted()
    }()
    static let roundNames = names.filter { !$0.hasPrefix("endgame_") }
    static let gameEndNames = names.filter { $0.hasPrefix("endgame_") }

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
    @Test(arguments: ScenarioFiles.roundNames) func scenario(_ name: String) throws {
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

    /// The disputed scenarios with the correction docs/notes/p3-B.md proposes, so
    /// that what they were written to test is still tested.
    @Test func correctedDisputedScenarios() throws {
        func run(_ json: [String: Any]) -> [String] {
            let runs = json["runs"] as! [String: Any]
            return runs.flatMap { ScenarioRunner(json: json, ruleset: $0.key, spec: $0.value as! [String: Any]).run() }
        }
        /// Seat 3's first draw (wall 55, a 3z) swapped with a later honor that is not
        /// 3z, so the first go-around is not four winds.
        func breakFourWinds(_ name: String) throws -> [String: Any] {
            var json = try ScenarioFiles.load(name)
            var wall = json["wall"] as! [String]
            #expect(wall[52..<56] == ["3z", "3z", "3z", "3z"])
            let j = try #require((70..<122).first { wall[$0].hasSuffix("z") && wall[$0] != "3z" && wall[$0] != "5z" })
            wall.swapAt(55, j)
            json["wall"] = wall
            // Seat 3's tsumogiri no longer names 3z.
            var runs = json["runs"] as! [String: Any]
            for (k, v) in runs {
                var run = v as! [String: Any]
                var steps = run["steps"] as! [[String: Any]]
                if let i = steps.firstIndex(where: { $0["seat"] as? Int == 3 && $0["tile"] as? String == "3z" }) {
                    steps[i]["tile"] = nil
                }
                run["steps"] = steps
                runs[k] = run
            }
            json["runs"] = runs
            return json
        }
        for name in ["closed_kan_rinshan_tsumo"] {
            let problems = run(try breakFourWinds(name))
            #expect(problems.isEmpty, "\(name) corrected: \(problems)")
        }
        // riichi_ankan_waits: double riichi + tsumo + rinshan, 4 han 50 fu (mangan).
        var json = try ScenarioFiles.load("riichi_ankan_waits")
        var runs = json["runs"] as! [String: Any]
        var ms = runs["mahjongsoul"] as! [String: Any]
        var expect = ms["expect"] as! [String: Any]
        expect["wins"] = ["1": ["han": 4, "fu": 50, "yaku": ["double_riichi", "rinshan", "tsumo"]]]
        expect["deltas"] = [-5000, 9000, -2000, -2000]
        expect["scores"] = [20000, 34000, 23000, 23000]
        ms["expect"] = expect
        runs["mahjongsoul"] = ms
        json["runs"] = runs
        let problems = run(json)
        #expect(problems.isEmpty, "riichi_ankan_waits corrected: \(problems)")
    }

    @Test(.disabled("game end is package C (GameState)"), arguments: ScenarioFiles.gameEndNames)
    func gameEndScenario(_ name: String) {}

    @Test func everyScenarioIsRunOrListedAsSkipped() {
        #expect(!ScenarioFiles.names.isEmpty)
        #expect(ScenarioFiles.roundNames.count + ScenarioFiles.gameEndNames.count == ScenarioFiles.names.count)
        for name in disputedScenarios.keys {
            let base = name.split(separator: ".").first.map(String.init) ?? name
            #expect(ScenarioFiles.roundNames.contains(base), "disputed scenario \(name) does not exist")
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
        let rules: Rules = self.rules ?? (ruleset == "tenhou" ? .tenhou : .mahjongSoul)
        let round = json["round"] as! [String: Any]
        guard let wall = Wall(tiles: tiles(json["wall"])) else { return ["bad wall"] }
        let wind = Wind(letter: Substring(round["wind"] as! String))!
        var events: [Event] = []
        var state = RoundState(
            rules: rules, wall: wall, roundWind: wind, kyoku: round["round"] as! Int,
            honba: round["honba"] as! Int, sticks: round["sticks"] as! Int,
            dealer: Seat(round["dealer"] as! Int), scores: round["scores"] as? [Int], events: &events)
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
        guard let result = state.result else {
            return problems + ["round did not end; phase \(state.phase), legal \(legalSummary(state))"]
        }
        problems += check(spec["expect"] as? [String: Any] ?? [:], result, events, state)
        return problems
    }

    func describe(_ step: [String: Any]) -> String {
        step.filter { $0.key != "type" }.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            .replacingOccurrences(of: "\n", with: "")
    }

    func legalSummary(_ s: RoundState) -> String {
        Seat.all.compactMap { seat in
            let a = s.legalActions(for: seat)
            return a.isEmpty ? nil : "\(seat): \(a.map(\.description).joined(separator: " "))"
        }.joined(separator: "; ")
    }

    func perform(_ step: [String: Any], _ state: inout RoundState, _ events: inout [Event]) throws {
        let seat = (step["seat"] as? Int).map(Seat.init)
        switch step["type"] as! String {
        case "turn":
            let seat = seat!
            let action: Action
            switch step["action"] as! String {
            case "discard":
                let tsumogiri = step["tsumogiri"] as? Bool ?? false
                if tsumogiri {
                    guard let d = state.drawnTile(of: seat) else { throw ScenarioFailure("no drawn tile to tsumogiri") }
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
                if state.result != nil { break }
                guard case .turn(let s, _) = state.phase, let d = state.drawnTile(of: s) else {
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
            if state.isFuriten(seat!) != want {
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

    func check(_ expect: [String: Any], _ r: RoundResult, _ events: [Event], _ state: RoundState) -> [String] {
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
        eq("honba", r.nextHonba(after: state.honba), expect["honba"] as? Int)
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
        for key in ["game_ended", "next_wind", "next_round", "next_dealer", "final_scores",
                    "final_ranks", "adjusted_scores"] where expect[key] != nil {
            p.append("expects \(key), which is game flow (package C): not checked")
        }
        return p
    }
}
