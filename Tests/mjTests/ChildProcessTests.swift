// Bot child process lifecycle: stopping kills the whole process group, and long
// timeouts do not trap.

import Foundation
import Testing
import Riichi
@testable import mj

@Suite struct ChildProcessTests {
    func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    func tempFile(_ name: String) -> String {
        let p = FileManager.default.temporaryDirectory
            .appendingPathComponent("mj-\(name)-\(ProcessInfo.processInfo.processIdentifier)").path
        try? FileManager.default.removeItem(atPath: p)
        return p
    }

    func waitForPid(_ path: String) throws -> pid_t {
        for _ in 0..<400 {
            if let s = try? String(contentsOfFile: path, encoding: .utf8), let p = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return p
            }
            usleep(10_000)
        }
        throw ChildProcess.SpawnError(description: "no pid written")
    }

    /// A grandchild that ignores SIGTERM, behind a shell that does not exec it.
    func stubbornCommand(_ pidFile: String) -> String {
        #"python3.14 -c "import os, signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); open('"# + pidFile
            + #"', 'w').write(str(os.getpid())); time.sleep(60)"; true"#
    }

    @Test func stopKillsTheProcessGroup() throws {
        let pidFile = tempFile("grandchild")
        let child = try ChildProcess(command: stubbornCommand(pidFile))
        let grandchild = try waitForPid(pidFile)
        #expect(alive(grandchild))
        let start = ContinuousClock.now
        child.stop()
        #expect(ContinuousClock.now - start < .seconds(5))
        usleep(50_000)
        #expect(!alive(grandchild))
        child.stop()  // twice is fine
    }

    @Test func droppingTheProcessStopsIt() throws {
        let pidFile = tempFile("dropped")
        var child: ChildProcess? = try ChildProcess(command: stubbornCommand(pidFile))
        let grandchild = try waitForPid(pidFile)
        let shell = child!.pid
        child = nil
        usleep(50_000)
        #expect(!alive(grandchild) && !alive(shell))
    }

    @Test func longTimeoutsDoNotTrap() throws {
        // Three billion milliseconds, with a child that exits after a second without output.
        let child = try ChildProcess(command: "exec /bin/sleep 1")
        let r = child.readLine(timeoutMs: 3_000_000_000)
        guard case .closed = r else { Issue.record("\(r)"); return }
        // A short timeout still times out.
        let quiet = try ChildProcess(command: "exec /bin/sleep 5")
        let start = ContinuousClock.now
        guard case .timeout = quiet.readLine(timeoutMs: 200) else { Issue.record("no timeout"); return }
        #expect(ContinuousClock.now - start < .seconds(2))
        // Huge and negative values are no trap either.
        _ = quiet.readLine(timeoutMs: -5)
        quiet.stop()
        _ = quiet.readLine(timeoutMs: Int.max / 2)
    }

    /// A bot that writes `none` lines without ever reading its input: once the pipe
    /// to it fills, the send has to give up at the same deadline as the read.
    @Test func aBotThatNeverReadsTimesOut() throws {
        var bot = MjaiBot(seat: Seat(0), command: #"exec yes '{"type":"none"}'"#, names: [], timeoutMs: 200)
        let e = Event.dora(marker: t1("1m")).masked(for: Seat(0))
        let start = ContinuousClock.now
        for _ in 0..<100_000 where bot.dead == nil { bot.receive(e, prompt: nil) }
        #expect(bot.dead == .timeout)
        #expect(ContinuousClock.now - start < .seconds(10))
        bot.finish()
    }

    /// A reply one byte over `maxLine` is refused even when its newline arrives in
    /// the read that crosses the limit.
    @Test func anOversizedReplyIsRefused() throws {
        let n = ChildProcess.maxLine + 1
        let cmd = #"exec python3.14 -c "import sys; sys.stdin.readline(); sys.stdout.write('a' * "#
            + "\(n)" + #" + '\n'); sys.stdout.flush(); sys.stdin.read()""#
        var bot = MjaiBot(seat: Seat(0), command: cmd, names: [], timeoutMs: 10_000)
        bot.receive(Event.dora(marker: t1("1m")).masked(for: Seat(0)), prompt: nil)
        #expect(bot.dead == .crashed)
        bot.finish()
        // Exactly `maxLine` bytes is still a line.
        let child = try ChildProcess(command: #"exec python3.14 -c "import sys; sys.stdout.write('a' * "#
            + "\(ChildProcess.maxLine)" + #" + '\n'); sys.stdout.flush(); sys.stdin.read()""#)
        guard case .line(let l) = child.readLine(timeoutMs: 10_000) else { Issue.record("no line"); return }
        #expect(l.utf8.count == ChildProcess.maxLine)
        child.stop()
    }
}
