// The mjai bot adapter (design §6): a child process speaking JSON lines. Every
// event a seat may see is sent, one per line, and one reply is read per event
// (`{"type":"none"}` when the bot has nothing to do). Riichi is two steps, as in
// mjai: the bot answers `reach`, is shown the `reach` event, and answers its
// `dahai`. A bad reply is replaced by the first legal of `pass`, tsumogiri, the
// first legal discard, and counted as malformed, illegal, timeout or crashed.

import Foundation
import Riichi
import RiichiMjai

final class ChildProcess {
    let process = Process()
    let toChild: Int32
    let fromChild: Int32
    var buffer: [UInt8] = []

    init(command: String) throws {
        let stdin = Pipe(), stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        toChild = stdin.fileHandleForWriting.fileDescriptor
        fromChild = stdout.fileHandleForReading.fileDescriptor
        // Keep the handles alive (they own the descriptors).
        handles = [stdin, stdout]
    }
    private var handles: [Pipe]

    /// False if the child has gone away.
    func send(_ line: String) -> Bool {
        var bytes = Array((line + "\n").utf8)
        var off = 0
        while off < bytes.count {
            let n = bytes.withUnsafeMutableBytes { write(toChild, $0.baseAddress! + off, $0.count - off) }
            if n <= 0 { return false }
            off += n
        }
        return true
    }

    enum Read { case line(String), timeout, closed }

    func readLine(timeoutMs: Int) -> Read {
        let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[..<nl], as: UTF8.self)
                buffer.removeSubrange(...nl)
                return .line(line)
            }
            let left = deadline - ContinuousClock.now
            let ms = Int(left.components.seconds * 1000 + left.components.attoseconds / 1_000_000_000_000_000)
            if ms <= 0 { return .timeout }
            var p = pollfd(fd: fromChild, events: Int16(POLLIN), revents: 0)
            let r = poll(&p, 1, Int32(ms))
            if r < 0 { if errno == EINTR { continue }; return .closed }
            if r == 0 { return .timeout }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = chunk.withUnsafeMutableBytes { read(fromChild, $0.baseAddress!, 4096) }
            if n <= 0 { return .closed }
            buffer += chunk[..<n]
        }
    }

    func stop() {
        if process.isRunning { process.terminate() }
        close(toChild)
        process.waitUntilExit()
    }
}

struct MjaiBot: Player {
    enum Failure { case malformed, illegal, timeout, crashed }

    let seat: Seat
    let names: [String]
    let timeoutMs: Int
    let child: ChildProcess?
    /// Why the bot is no longer asked (it timed out or exited); its later
    /// decisions are substituted and counted under the same reason.
    var dead: Failure?
    var substitutions = Substitutions()
    /// Diagnostics for the first few failures.
    var notes: [String] = []

    init(seat: Seat, command: String, names: [String], timeoutMs: Int) {
        self.seat = seat
        self.names = names
        self.timeoutMs = timeoutMs
        child = try? ChildProcess(command: command)
        if child == nil { dead = .crashed }
    }

    mutating func count(_ f: Failure, _ why: String) {
        switch f {
        case .malformed: substitutions.malformed += 1
        case .illegal: substitutions.illegal += 1
        case .timeout: substitutions.timeout += 1
        case .crashed: substitutions.crashed += 1
        }
        if notes.count < 5 { notes.append("seat \(seat): \(f): \(why)") }
    }

    static func substitute(_ legal: [Action]) -> Action {
        if legal.contains(.pass) { return .pass }
        if let t = legal.first(where: { if case .discard(_, true) = $0 { true } else { false } }) { return t }
        if let d = legal.first(where: { if case .discard = $0 { true } else { false } }) { return d }
        return legal[0]
    }

    mutating func receive(_ events: [MaskedEvent], view: PlayerView?) -> Action? {
        var reply: String?
        for (n, e) in events.enumerated() where dead == nil {
            guard let child, child.send(Mjai.encode(e, names: names)) else { dead = .crashed; break }
            switch child.readLine(timeoutMs: timeoutMs) {
            case .line(let l): if n == events.count - 1 { reply = l }
            case .timeout: dead = .timeout; child.stop()
            case .closed: dead = .crashed
            }
        }
        guard let view else { return nil }
        if let dead {
            count(dead, "no reply")
            return Self.substitute(view.legalActions)
        }
        guard let reply, let m = try? Mjai.decode(reply) else {
            count(.malformed, reply ?? "")
            return Self.substitute(view.legalActions)
        }
        guard let a = Mjai.action(m, seat: seat, legal: view.legalActions) else {
            count(.illegal, reply)
            return Self.substitute(view.legalActions)
        }
        return a
    }

    mutating func finish() {
        if dead == nil, let child {
            _ = child.send(#"{"type":"end"}"#)
        }
        child?.stop()
    }
}
