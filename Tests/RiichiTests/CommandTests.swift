// `mj selfplay`, `replay`, `check-log` and the mjai bot adapter, run as child
// processes of the built executable (skipped when it has not been built).

import Foundation
import Testing

@Suite struct CommandTests {
    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    static var mj: String? { LineProtocolTests.mjPath }

    func run(_ args: [String]) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: try #require(Self.mj))
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func tempDir(_ name: String) -> String {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("mj-\(name)-\(ProcessInfo.processInfo.processIdentifier)").path
        try? FileManager.default.removeItem(atPath: d)
        return d
    }

    /// Self-play with every invariant check (view fold, answer order, replay to the
    /// same bytes, check-log accepting the log), then `replay` and `check-log` on
    /// the files written.
    @Test(.enabled(if: mj != nil), arguments: ["tenhou", "mahjongsoul"]) func selfplayReplayCheckLog(_ rules: String) throws {
        let dir = tempDir("sp-\(rules)")
        let (status, out) = try run(["selfplay", "--seed", "11", "--games", "3", "--rules", rules, "--bots", "eager",
                                     "--seat", "2=random", "--out", dir, "--check", "--legal"])
        #expect(status == 0, "\(out)")
        #expect(out.contains("invariants ok"))
        let traces = (0..<3).map { String(format: "%@/%06d.trace", dir, $0) }
        let (rs, ro) = try run(["replay"] + traces)
        #expect(rs == 0 && ro.contains("identical=3"), "\(ro)")
        let logs = (0..<3).map { String(format: "%@/%06d.jsonl", dir, $0) }
        let (cs, co) = try run(["check-log", "--rules", rules] + logs)
        #expect(cs == 0 && co.contains("errors=0"), "\(co)")
        // Every log line is a JSON object with a type; start_kyoku carries the wall.
        let text = try String(contentsOfFile: logs[0], encoding: .utf8)
        #expect(text.split(separator: "\n").allSatisfy { $0.hasPrefix(#"{"type":""#) })
        #expect(text.contains(#""wall":["#))
        // A tampered log is refused: change the first win's payment.
        var lines = text.split(separator: "\n").map(String.init)
        let i = try #require(lines.firstIndex { $0.contains(#""type":"hora""#) })
        lines[i] = lines[i].replacingOccurrences(of: #""deltas":["#, with: #""deltas":[7"#)
        let bad = dir + "/bad.jsonl"
        try (lines.joined(separator: "\n") + "\n").write(toFile: bad, atomically: false, encoding: .utf8)
        let (bs, _) = try run(["check-log", "--rules", rules, bad])
        #expect(bs != 0)
        // A trace that does not match its log is reported.
        try "garbage\n".write(toFile: dir + "/000000.jsonl", atomically: false, encoding: .utf8)
        let (xs, _) = try run(["replay", traces[0]])
        #expect(xs != 0)
    }

    /// The mjai adapter with the scripted fake bot: two-step riichi, and each kind
    /// of bad reply substituted and counted.
    @Test(.enabled(if: mj != nil)) func mjaiAdapter() throws {
        let bot = Self.root.appendingPathComponent("Tests/Fixtures/fakebot.py").path
        let dir = tempDir("fake")
        func spec(_ s: Int, _ arg: String) -> [String] { ["--seat", "\(s)=mjai:python3.14 \(bot) \(arg)"] }
        let (status, out) = try run(["selfplay", "--seed", "3", "--games", "1", "--bots", "eager", "--timeout", "300",
                                     "--out", dir, "--check"]
                                    + spec(0, "malformed=2") + spec(1, "illegal=3") + spec(2, "sleep=4") + spec(3, "exit=5"))
        #expect(status == 0, "\(out)")
        let line = try #require(out.split(separator: "\n").first { $0.hasPrefix("substitutions") })
        func count(_ k: String) -> Int {
            Int(line.split(separator: " ").first { $0.hasPrefix(k + "=") }!.dropFirst(k.count + 1))!
        }
        #expect(count("malformed") >= 1)
        #expect(count("illegal") >= 1)
        #expect(count("timeout") >= 1)
        #expect(count("crashed") >= 1)
        // A well-behaved fake bot at every seat: no malformed, timeout or crash
        // (its yaku-less win attempts count as illegal), and riichi made in two steps.
        let (s2, o2) = try run(["selfplay", "--seed", "3", "--games", "3", "--bots", "mjai:python3.14 \(bot)",
                                "--out", dir + "/ok", "--check"])
        #expect(s2 == 0, "\(o2)")
        #expect(o2.contains("malformed=0") && o2.contains("timeout=0") && o2.contains("crashed=0"), "\(o2)")
        let log = try (0..<3).map { try String(contentsOfFile: String(format: "%@/ok/%06d.jsonl", dir, $0), encoding: .utf8) }
            .joined()
        #expect(log.contains(#""type":"reach","actor""#))
        #expect(log.contains(#""type":"reach_accepted""#))
    }

    /// Gemini C/D finding 3: a bot that ignores SIGTERM, or floods its output
    /// without a newline, is killed and its decisions substituted, without hanging.
    @Test(.enabled(if: mj != nil)) func mjaiAdapterHostileBots() throws {
        let bot = Self.root.appendingPathComponent("Tests/Fixtures/fakebot.py").path
        let start = ContinuousClock.now
        let (status, out) = try run(["selfplay", "--seed", "3", "--games", "1", "--bots", "eager", "--timeout", "300",
                                     "--seat", "0=mjai:python3.14 \(bot) stubborn=2",
                                     "--seat", "1=mjai:python3.14 \(bot) flood=2", "--check"])
        #expect(status == 0, "\(out)")
        #expect(ContinuousClock.now - start < .seconds(20))
        #expect(out.contains("invariants ok"), "\(out)")
        let line = try #require(out.split(separator: "\n").first { $0.hasPrefix("substitutions") })
        #expect(!line.contains("timeout=0") && !line.contains("crashed=0"), "\(line)")
    }

    /// Gemini C/D findings 4, 5 and 7, and the seed options: bad logs and bad
    /// arguments are errors, not crashes or silent passes.
    @Test(.enabled(if: mj != nil)) func checkLogRefusesBadLogs() throws {
        let dir = tempDir("badlogs")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let (s0, o0) = try run(["selfplay", "--seed", "5", "--games", "1", "--bots", "eager", "--out", dir, "--quiet"])
        #expect(s0 == 0, "\(o0)")
        let log = try String(contentsOfFile: dir + "/000000.jsonl", encoding: .utf8)
        var lines = log.split(separator: "\n").map(String.init)
        func check(_ name: String, _ text: String) throws -> (Int32, String) {
            let path = "\(dir)/\(name).jsonl"
            try text.write(toFile: path, atomically: false, encoding: .utf8)
            return try run(["check-log", path])
        }
        var (s, o) = try check("good", log)
        #expect(s == 0, "\(o)")
        (s, o) = try check("empty", "")
        #expect(s != 0 && o.contains("no start_kyoku"), "\(o)")
        (s, o) = try check("outside", lines[0] + "\n" + #"{"type":"hora","actor":0,"target":1}"# + "\n" + lines.dropFirst().joined(separator: "\n"))
        #expect(s != 0 && o.contains("outside a hand"), "\(o)")
        let k = try #require(lines.firstIndex { $0.contains(#""type":"start_kyoku""#) })
        var neg = lines
        neg[k] = neg[k].replacingOccurrences(of: #""honba":0"#, with: #""honba":-1"#)
        (s, o) = try check("neg", neg.joined(separator: "\n"))
        #expect(s != 0 && o.contains("out of range"), "\(o)")
        if let r = lines.firstIndex(where: { $0.contains(#""type":"ryukyoku""#) }) {
            lines[r] = lines[r].replacingOccurrences(of: #""reason":"#, with: #""reason":"bogus","x":"#)
            (s, o) = try check("reason", lines.joined(separator: "\n"))
            #expect(s != 0 && o.contains("ryukyoku.reason"), "\(o)")
        }
        (s, o) = try run(["selfplay", "--seed", "-1", "--games", "1"])
        #expect(s != 0 && !o.contains("Fatal"), "\(o)")
        (s, o) = try run(["selfplay", "--seed", "18446744073709551615", "--games", "1", "--quiet"])
        #expect(s == 0, "\(o)")
        (s, o) = try run(["selfplay", "--games", "-1"])
        #expect(s != 0 && !o.contains("Fatal"), "\(o)")
    }

    /// Codex C/D findings 2 and 7: with an external bot and no --seed, each game's
    /// wall seed is fresh from the system (recorded in the trace only); with --seed
    /// a warning is printed. The replay check compares bytes.
    @Test(.enabled(if: mj != nil)) func externalBotSeeds() throws {
        let bot = Self.root.appendingPathComponent("Tests/Fixtures/fakebot.py").path
        var seeds: [String] = []
        for k in 0..<2 {
            let dir = tempDir("seed\(k)")
            let (s, o) = try run(["selfplay", "--games", "2", "--bots", "eager", "--seat", "0=mjai:python3.14 \(bot)",
                                  "--out", dir, "--quiet"])
            #expect(s == 0, "\(o)")
            #expect(!o.contains("warning"))
            for g in 0..<2 {
                let trace = try String(contentsOfFile: String(format: "%@/%06d.trace", dir, g), encoding: .utf8)
                seeds += trace.split(separator: "\n").filter { $0.hasPrefix("seed ") }.map(String.init)
                let (rs, ro) = try run(["replay", String(format: "%@/%06d.trace", dir, g)])
                #expect(rs == 0, "\(ro)")
            }
        }
        #expect(Set(seeds).count == 4, "\(seeds)")
        let (s, o) = try run(["selfplay", "--seed", "1", "--games", "1", "--bots", "eager",
                              "--seat", "0=mjai:python3.14 \(bot)", "--quiet"])
        #expect(s == 0 && o.contains("warning: --seed with an external bot"), "\(o)")
        // A log differing from the replay only in Unicode normalization is a difference.
        let dir = tempDir("nfc")
        _ = try run(["selfplay", "--seed", "2", "--games", "1", "--bots", "eager", "--out", dir, "--quiet"])
        let path = dir + "/000000.jsonl"
        var bytes = try [UInt8](Data(contentsOf: URL(fileURLWithPath: path)))
        let (rs, _) = try run(["replay", dir + "/000000.trace"])
        #expect(rs == 0)
        // Append a combining accent to a bot name: "eager" + U+0301 vs. the same bytes
        // re-encoded is not equal byte-wise even where String equality might hold.
        let eager = Array(#""eager""#.utf8)
        if let i = (0...(bytes.count - eager.count)).first(where: { Array(bytes[$0..<$0 + eager.count]) == eager }) {
            bytes.insert(contentsOf: [0xCC, 0x81], at: i + eager.count - 1)
            try Data(bytes).write(to: URL(fileURLWithPath: path))
            let (bs, _) = try run(["replay", dir + "/000000.trace"])
            #expect(bs != 0)
        }
    }

    /// Directed self-play (docs/notes/p3-closeout.md): each scenario reaches its
    /// branch with every invariant on, its traces replay to the same bytes (the
    /// trace names the scenario, which rebuilds the walls and the starting
    /// position), and check-log accepts the logs.
    @Test(.enabled(if: mj != nil), arguments: ["tenhou", "mahjongsoul"]) func directedScenarios(_ rules: String) throws {
        let tenhou = rules == "tenhou"
        let branches: [(String, [String])] = [
            ("fourwinds", ["abort_suufon_renda", "abort_suufon_renda_riichi"]),
            ("fourriichi", ["abort_suucha_riichi"]),
            ("tripleron", [tenhou ? "abort_sanchahou" : "ron_x3"]),
            ("robkan", tenhou ? [] : ["robbed_closed_kan"]),
            ("pao", ["pao_tsumo", "pao_third_party_ron", "pao_liable_ron"]),
            ("nagashi", ["nagashi"]),
            ("fourkans", ["four_kans_one_seat"]),
            ("endgame", ["end_dealer_first", "end_target", "all_last_repeat", "all_last_advance"]),
        ]
        for (scenario, keys) in branches {
            let dir = tempDir("dir-\(scenario)-\(rules)")
            let (s, o) = try run(["selfplay", "--scenario", scenario, "--seed", "5", "--games", "12", "--rules", rules,
                                  "--out", dir, "--check"])
            #expect(s == 0 && o.contains("invariants ok"), "\(scenario): \(o)")
            for k in keys { #expect(o.contains("  \(k)="), "\(scenario) \(rules): \(k) not reached\n\(o)") }
            let traces = (0..<12).map { String(format: "%@/%06d.trace", dir, $0) }
            let (rs, ro) = try run(["replay"] + traces)
            #expect(rs == 0 && ro.contains("identical=12"), "\(scenario): \(ro)")
            let trace = try String(contentsOfFile: traces[0], encoding: .utf8)
            #expect(trace.contains("\nscenario \(scenario)\n"))
        }
        let (bs, bo) = try run(["selfplay", "--scenario", "nonesuch", "--games", "1"])
        #expect(bs != 0 && bo.contains("unknown scenario"), "\(bo)")
    }

    /// check-log on the reduced format of the real-log campaign (docs/notes/p3-reallogs.md):
    /// our own logs stripped to it (no deltas, scores, dora events or ura; the
    /// dealer's first draw dealt as a 14th tile) still check, the hidden
    /// indicators being searched for against the next hand's scores.
    @Test(.enabled(if: mj != nil), arguments: ["tenhou", "mahjongsoul"]) func checkLogReducedFormat(_ rules: String) throws {
        let dir = tempDir("lite-\(rules)")
        let (s0, o0) = try run(["selfplay", "--seed", "40", "--games", "6", "--rules", rules, "--bots", "eager", "--out", dir, "--quiet"])
        #expect(s0 == 0, "\(o0)")
        var paths: [String] = []
        for g in 0..<6 {
            let text = try String(contentsOfFile: String(format: "%@/%06d.jsonl", dir, g), encoding: .utf8)
            var out: [String] = []
            var pendingDealer: (index: Int, tile: Any)? = nil
            for line in text.split(separator: "\n") {
                var e = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
                let type = e["type"] as! String
                switch type {
                case "dora": continue
                case "start_kyoku": e["wall"] = nil
                case "hora": e = e.filter { ["type", "actor", "target", "pai"].contains($0.key) }
                case "ryukyoku", "end_kyoku", "end_game", "reach_accepted": e = e.filter { ["type", "actor"].contains($0.key) }
                case "tsumo":
                    // The dealer's first draw joins its dealt hand.
                    if let p = pendingDealer {
                        var start = try #require(try JSONSerialization.jsonObject(with: Data(out[p.index].utf8)) as? [String: Any])
                        var tehais = start["tehais"] as! [[Any]]
                        let oya = start["oya"] as! Int
                        tehais[oya].append(e["pai"]!)
                        start["tehais"] = tehais
                        out[p.index] = String(decoding: try JSONSerialization.data(withJSONObject: start), as: UTF8.self)
                        pendingDealer = nil
                        continue
                    }
                default: break
                }
                out.append(String(decoding: try JSONSerialization.data(withJSONObject: e), as: UTF8.self))
                if type == "start_kyoku" { pendingDealer = (out.count - 1, 0) }
            }
            let path = String(format: "%@/lite%06d.jsonl", dir, g)
            try (out.joined(separator: "\n") + "\n").write(toFile: path, atomically: false, encoding: .utf8)
            paths.append(path)
        }
        let (s, o) = try run(["check-log", "--rules", rules] + paths)
        #expect(s == 0 && o.contains("errors=0"), "\(o)")
        #expect(o.contains("lite_hidden_indicators") || o.contains("lite_no_dora"), "\(o)")
        // A wrong final score in the next header is still caught.
        var t = try String(contentsOfFile: paths[0], encoding: .utf8).split(separator: "\n").map(String.init)
        let k = try #require(t.indices.filter { t[$0].contains(#""type":"start_kyoku""#) }.dropFirst().first)
        t[k] = t[k].replacingOccurrences(of: #""scores":["#, with: #""scores":[1"#)
        try (t.joined(separator: "\n") + "\n").write(toFile: paths[0], atomically: false, encoding: .utf8)
        let (bs, bo) = try run(["check-log", "--rules", rules, paths[0]])
        #expect(bs != 0, "\(bo)")
    }
}
