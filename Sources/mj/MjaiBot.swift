// The mjai bot adapter (design §6): a child process speaking JSON lines. Every
// event a seat may see is sent, one per line, and one reply is read per event
// (`{"type":"none"}` when the bot has nothing to do). Riichi is two steps, as in
// mjai: the bot answers `reach`, is shown the `reach` event, and answers its
// `dahai`. A bad reply is replaced by the first legal of `pass`, tsumogiri, the
// first legal discard, and counted as malformed, illegal, timeout, crashed or
// unbound.

import Foundation
import Riichi
import RiichiMjai

/// A bot's process: `/bin/sh -c COMMAND` in a process group of its own, so that
/// stopping it reaches whatever the command started (Gemini final finding 4).
final class ChildProcess {
    let pid: pid_t
    let toChild: Int32
    let fromChild: Int32
    var buffer: [UInt8] = []
    /// Bytes of `buffer` already searched for a newline.
    var scanned = 0
    /// A reply longer than this is refused and the bot treated as crashed.
    static let maxLine = 1 << 20
    /// The longest single wait in `poll` (a longer deadline polls again).
    static let maxPollMs = 60_000
    var stopped = false

    struct SpawnError: Error, CustomStringConvertible {
        let description: String
    }

    init(command: String) throws {
        var toPipe: [Int32] = [-1, -1], fromPipe: [Int32] = [-1, -1]
        guard pipe(&toPipe) == 0 else { throw SpawnError(description: "pipe: errno \(errno)") }
        guard pipe(&fromPipe) == 0 else {
            close(toPipe[0]); close(toPipe[1])
            throw SpawnError(description: "pipe: errno \(errno)")
        }
        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t? = nil
        var attr: posix_spawnattr_t? = nil
        #else
        var actions = posix_spawn_file_actions_t()
        var attr = posix_spawnattr_t()
        #endif
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, toPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, fromPipe[1], 1)
        for fd in toPipe + fromPipe { posix_spawn_file_actions_addclose(&actions, fd) }
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // A new process group (its id is the child's pid), default signal handling
        // (mj ignores SIGPIPE) and no blocked signals.
        var defaults = sigset_t(), none = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        posix_spawnattr_setsigmask(&attr, &none)
        posix_spawnattr_setpgroup(&attr, 0)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        let argv: [UnsafeMutablePointer<CChar>?] = ["/bin/sh", "-c", command].map { strdup($0) } + [nil]
        defer { for a in argv { free(a) } }
        var child: pid_t = 0
        let rc = posix_spawn(&child, "/bin/sh", &actions, &attr, argv, environ)
        close(toPipe[0]); close(fromPipe[1])
        guard rc == 0 else {
            close(toPipe[1]); close(fromPipe[0])
            throw SpawnError(description: "posix_spawn: \(rc)")
        }
        // Our ends stay out of later children (another seat's bot).
        _ = fcntl(toPipe[1], F_SETFD, FD_CLOEXEC)
        _ = fcntl(fromPipe[0], F_SETFD, FD_CLOEXEC)
        pid = child
        toChild = toPipe[1]
        fromChild = fromPipe[0]
    }

    deinit { stop() }

    /// False if the child has gone away.
    func send(_ line: String) -> Bool {
        guard !stopped else { return false }
        var bytes = Array((line + "\n").utf8)
        var off = 0
        while off < bytes.count {
            let n = bytes.withUnsafeMutableBytes { write(toChild, $0.baseAddress! + off, $0.count - off) }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return false }
            off += n
        }
        return true
    }

    enum Read { case line(String), timeout, closed, tooLong }

    /// The next line within `timeoutMs` (which `mj selfplay` keeps to
    /// 1...`maxTimeoutMs`; any larger value just waits longer, Codex final finding 6).
    func readLine(timeoutMs: Int) -> Read {
        guard !stopped else { return .closed }
        let deadline = ContinuousClock.now + .milliseconds(max(0, timeoutMs))
        while true {
            if let nl = buffer[scanned...].firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[..<nl], as: UTF8.self)
                buffer.removeSubrange(...nl)
                scanned = 0
                return .line(line)
            }
            scanned = buffer.count
            if buffer.count > ChildProcess.maxLine { return .tooLong }
            let left = deadline - ContinuousClock.now
            guard left > .zero else { return .timeout }
            // Whole milliseconds, rounded up, and capped: poll takes an Int32.
            let seconds = min(left.components.seconds, Int64(ChildProcess.maxPollMs / 1000))
            let ms = min(ChildProcess.maxPollMs,
                         Int(seconds) * 1000 + Int(left.components.attoseconds / 1_000_000_000_000_000) + 1)
            var p = pollfd(fd: fromChild, events: Int16(POLLIN), revents: 0)
            let r = poll(&p, 1, Int32(ms))
            if r < 0 { if errno == EINTR { continue }; return .closed }
            if r == 0 { continue }  // the loop decides whether the deadline has passed
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = chunk.withUnsafeMutableBytes { read(fromChild, $0.baseAddress!, 4096) }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return .closed }
            buffer += chunk[..<n]
        }
    }

    /// Whether the shell has exited (without reaping it).
    func exited() -> Bool {
        var info = siginfo_t()
        return waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0 && info.si_pid == pid
    }

    /// Ends the child and everything it started: closes its input, asks the whole
    /// process group to stop (SIGTERM), waits up to half a second for the shell,
    /// then kills the group (SIGKILL: a member that ignores SIGTERM, or outlives
    /// the shell, is killed too) and reaps the shell. Safe to call twice.
    func stop() {
        guard !stopped else { return }
        stopped = true
        close(toChild)
        kill(-pid, SIGTERM)
        let deadline = ContinuousClock.now + .milliseconds(500)
        while !exited() && ContinuousClock.now < deadline { usleep(5_000) }
        // Before reaping the shell, so the group id cannot have been reused.
        kill(-pid, SIGKILL)
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        close(fromChild)
    }
}

/// An mjai bot (design §6). Each event the seat may see is sent and one reply read.
/// The reply to the event that asks for a decision (`PlayerView.prompt(in:)`) is
/// the decision, checked against it (`Mjai.action(_:for:)`); a later event of the
/// same step (an owed indicator) must be answered `none`. A reply that cannot be
/// bound to the decision or mapped to one of its actions is substituted and
/// counted, never taken as a pass (Codex final finding 1).
struct MjaiBot: Player {
    enum Failure { case malformed, illegal, timeout, crashed, unbound }

    /// The longest `--timeout` (an hour).
    static let maxTimeoutMs = 3_600_000

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
    /// The reply to the open decision's prompt (nil if none was read).
    var promptReply: String?
    var prompted = false
    /// A reply other than `none` to an event after the prompt.
    var strayReply: String?

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
        case .unbound: substitutions.unbound += 1
        }
        if notes.count < 5 { notes.append("seat \(seat): \(f): \(why)") }
    }

    static func substitute(_ legal: [Action]) -> Action {
        if legal.contains(.pass) { return .pass }
        if let t = legal.first(where: { if case .discard(_, true) = $0 { true } else { false } }) { return t }
        if let d = legal.first(where: { if case .discard = $0 { true } else { false } }) { return d }
        return legal[0]
    }

    static func isNone(_ line: String) -> Bool { (try? Mjai.decode(line))?.type == "none" }

    mutating func receive(_ e: MaskedEvent, prompt: PlayerView?) {
        if prompt != nil { prompted = true }
        guard dead == nil, let child else { return }
        guard child.send(Mjai.encode(e, names: names)) else { dead = .crashed; child.stop(); return }
        switch child.readLine(timeoutMs: timeoutMs) {
        case .line(let l):
            if prompt != nil {
                promptReply = l
            } else if !Self.isNone(l) {
                if prompted { strayReply = l } else { count(.unbound, "reply to \(Mjai.encode(e)): \(l)") }
            }
        case .timeout: dead = .timeout; child.stop()
        case .closed, .tooLong: dead = .crashed; child.stop()
        }
    }

    mutating func decision(_ view: PlayerView) -> Action? {
        defer { promptReply = nil; prompted = false; strayReply = nil }
        let legal = view.legalActions
        if let dead {
            count(dead, "no reply")
            return Self.substitute(legal)
        }
        guard prompted, let reply = promptReply else {
            count(.unbound, "no reply bound to the decision")
            return Self.substitute(legal)
        }
        if let strayReply {
            count(.illegal, "after its answer \(reply), a reply to a later notification: \(strayReply)")
            return Self.substitute(legal)
        }
        guard let m = try? Mjai.decode(reply) else {
            count(.malformed, reply)
            return Self.substitute(legal)
        }
        guard let a = Mjai.action(m, for: Mjai.Decision(view)) else {
            count(.illegal, reply)
            return Self.substitute(legal)
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
