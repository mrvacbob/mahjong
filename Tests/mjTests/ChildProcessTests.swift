// The bot's process: its whole process group is stopped (Gemini final finding 4),
// and a long timeout cannot trap (Codex final finding 6).

import Foundation
import Testing
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
        // The review's probe: three billion milliseconds, and a child that says
        // nothing and exits after a second.
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
}
