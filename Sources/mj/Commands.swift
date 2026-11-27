// `mj selfplay`, `mj replay` (design §7).

import Foundation
import Riichi
import RiichiMjai

struct UsageError: Error, CustomStringConvertible { let description: String }

/// `--key value` options and positional arguments.
struct Options {
    var values: [String: String] = [:]
    var flags: Set<String> = []
    var seats: [Int: String] = [:]
    var positional: [String] = []

    init(_ args: [String], flags known: Set<String>) throws {
        var i = 0
        while i < args.count {
            let a = args[i]
            if a.hasPrefix("--") {
                let k = String(a.dropFirst(2))
                if known.contains(k) { flags.insert(k); i += 1; continue }
                guard i + 1 < args.count else { throw UsageError(description: "\(a) needs a value") }
                if k == "seat" {
                    let v = args[i + 1]
                    guard let eq = v.firstIndex(of: "="), let s = Int(v[..<eq]), (0..<4).contains(s) else {
                        throw UsageError(description: "--seat N=BOT")
                    }
                    seats[s] = String(v[v.index(after: eq)...])
                } else {
                    values[k] = args[i + 1]
                }
                i += 2
            } else {
                positional.append(a)
                i += 1
            }
        }
    }

    func int(_ k: String, _ d: Int) throws -> Int {
        guard let v = values[k] else { return d }
        guard let n = Int(v) else { throw UsageError(description: "--\(k) wants a number") }
        return n
    }
    func rules() throws -> Rules {
        switch values["rules"] ?? "mahjongsoul" {
        case "mahjongsoul": return .mahjongSoul
        case "tenhou": return .tenhou
        case let r: throw UsageError(description: "unknown rules \(r)")
        }
    }
}

func writeFile(_ path: String, _ text: String) throws {
    try text.write(toFile: path, atomically: false, encoding: .utf8)
}

func readFile(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }

/// The players for one game: `random`, `eager` or `mjai:COMMAND` per seat.
func makePlayers(_ specs: [String], seed: UInt64, timeoutMs: Int) throws -> [any Player] {
    let names = specs.map { $0.hasPrefix("mjai:") ? "mjai" : $0 }
    return try (0..<4).map { i -> any Player in
        let spec = specs[i]
        if spec.hasPrefix("mjai:") {
            return MjaiBot(seat: Seat(i), command: String(spec.dropFirst(5)), names: names, timeoutMs: timeoutMs)
        }
        guard let k = BotKind(rawValue: spec) else { throw UsageError(description: "unknown bot \(spec)") }
        return BuiltinBot(kind: k, rng: BotRNG(state: seed &* 0x2545_F491_4F6C_DD1D &+ UInt64(i + 1)))
    }
}

/// `mj selfplay --seed N --games K [--rules tenhou] [--bots random|eager|mjai:CMD]
/// [--seat N=BOT] [--out DIR] [--legal] [--requests FILE] [--check] [--timeout MS]`
func selfplay(_ args: [String]) throws -> Int32 {
    let o = try Options(args, flags: ["legal", "check", "quiet"])
    let seed = UInt64(try o.int("seed", 0))
    let games = try o.int("games", 1)
    let rules = try o.rules()
    let timeout = try o.int("timeout", 10_000)
    var specs = Array(repeating: o.values["bots"] ?? "eager", count: 4)
    for (s, b) in o.seats { specs[s] = b }
    let names = specs.map { $0.hasPrefix("mjai:") ? "mjai" : $0 }
    let label = specs.map { $0.hasPrefix("mjai:") ? "mjai" : $0 }.joined(separator: ",")
    let out = o.values["out"]
    if let out { try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true) }
    if o.flags.contains("legal") && out == nil { throw UsageError(description: "--legal needs --out") }
    let requests = o.values["requests"].map { _ in RequestDump(prefix: "q") }
    let coverage = Coverage()
    var failures: [String] = []
    var botNotes: [String] = []
    var subs = Substitutions()
    var hands = 0, decisions = 0
    let clock = ContinuousClock()
    let start = clock.now
    for g in 0..<games {
        let gameSeed = seed &+ UInt64(g)
        let name = String(format: "%06d", g)
        var observers: [any GameObserver] = [coverage]
        let legal = o.flags.contains("legal") ? LegalityRows(file: "\(out!)/\(name).jsonl") : nil
        if let legal { observers.append(legal) }
        if let requests, rules == .mahjongSoul { observers.append(requests) }
        let checks = o.flags.contains("check") ? InvariantChecks(label: "game \(g)") : nil
        if let checks { observers.append(checks) }
        var players = try makePlayers(specs, seed: gameSeed, timeoutMs: timeout)
        let rec = try playGame(rules: rules, seed: gameSeed, players: &players, names: names,
                               observers: observers, botsLabel: label)
        hands += rec.game.handsDealt
        decisions += rec.decisions
        subs = subs + rec.substitutions
        for p in players { if let m = p as? MjaiBot { botNotes += m.notes.map { "game \(g) \($0)" } } }
        if let checks { failures += checks.failures }
        if o.flags.contains("check") {
            // The trace replays to the same log, and check-log accepts the log.
            let again = try replayTrace(rec.trace)
            if again != rec.log { failures.append("game \(g): replay of its trace gives a different log") }
            let report = checkLog(text: rec.log, rules: rules, path: name)
            if !report.errors.isEmpty { failures += report.errors.prefix(3).map { "game \(g) check-log: \($0)" } }
        }
        if let out {
            try writeFile("\(out)/\(name).jsonl", rec.log)
            try writeFile("\(out)/\(name).trace", rec.trace)
            if let legal { try writeFile("\(out)/\(name).legality", legal.text) }
        }
    }
    let d = clock.now - start
    let secs = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    if let requests, let path = o.values["requests"] {
        try writeFile(path, requests.requests.map { $0 + "\n" }.joined())
        try writeFile(path + ".expected", requests.expected.map { $0 + "\n" }.joined())
        try writeFile(path + ".lowpoints", requests.lowPoints.map { $0 + "\n" }.joined())
    }
    print("games=\(games) hands=\(hands) decisions=\(decisions) rules=\(rulesetName(rules)) bots=\(label)")
    print(String(format: "time=%.2fs games/s=%.1f", secs, Double(games) / secs))
    print("substitutions \(subs.text)")
    if !o.flags.contains("quiet") { print(coverage.report) }
    for n in botNotes.prefix(10) { print("bot \(n)") }
    for f in failures.prefix(30) { print("FAIL \(f)") }
    print(failures.isEmpty ? "invariants ok" : "failures=\(failures.count)")
    return failures.isEmpty ? 0 : 1
}

/// Plays a trace's decisions again and returns the log.
func replayTrace(_ text: String) throws -> String {
    let t = try parseTrace(text)
    let decisions = Decisions(t.decisions)
    var players: [any Player] = Seat.all.map { TracePlayer(seat: $0, queue: decisions) }
    let specs = t.bots.split(separator: ",").map(String.init)
    let names = specs.count == 4 ? specs : ["0", "1", "2", "3"]
    let rec = try playGame(rules: t.rules, seed: t.seed, players: &players, names: names, observers: [],
                           botsLabel: t.bots)
    if let m = decisions.mismatch { throw DriverError.trace(m) }
    if decisions.i != decisions.items.count { throw DriverError.trace("\(decisions.items.count - decisions.i) decisions left over") }
    return rec.log
}

/// `mj replay TRACE...`: each trace's log must equal the `.jsonl` beside it, byte
/// for byte.
func replay(_ args: [String]) throws -> Int32 {
    var bad = 0
    for path in args {
        let log = try replayTrace(try readFile(path))
        let logPath = (path.hasSuffix(".trace") ? String(path.dropLast(6)) : path) + ".jsonl"
        let want = try readFile(logPath)
        if log != want {
            bad += 1
            print("\(path): differs from \(logPath)")
        }
    }
    print("replayed=\(args.count) identical=\(args.count - bad)")
    return bad == 0 ? 0 : 1
}
