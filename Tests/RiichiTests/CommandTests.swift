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
}
