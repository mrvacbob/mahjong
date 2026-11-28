// `mj check-log --stdin` framing: `NAME LENGTH\n` then LENGTH bytes. The input may
// end only between frames; anything else is an error, not the end of input.

import Foundation
import Testing
@testable import mj

@Suite struct FramedInputTests {
    /// The frames read from `bytes`, and the error that stopped the reading, if any.
    func frames(_ bytes: String) throws -> ([String], String?) {
        var fds: [Int32] = [-1, -1]
        #expect(pipe(&fds) == 0)
        let data = Array(bytes.utf8)
        #expect(data.withUnsafeBytes { write(fds[1], $0.baseAddress, $0.count) } == data.count)
        close(fds[1])
        defer { close(fds[0]) }
        var input = FramedInput(fd: fds[0])
        var out: [String] = []
        do {
            while let (name, text) = try input.next() { out.append("\(name):\(text)") }
        } catch {
            return (out, error.description)
        }
        return (out, nil)
    }

    @Test func wellFormedFrames() throws {
        let (f, e) = try frames("a 3\nxyzb 0\nc 2\n\n\n")
        #expect(f == ["a:xyz", "b:", "c:\n\n"])
        #expect(e == nil)
        let (none, e2) = try frames("")
        #expect(none.isEmpty && e2 == nil)
    }

    @Test func negativeLengthIsAnError() throws {
        let (f, e) = try frames("a 1\nxgame -1\n")
        #expect(f == ["a:x"])
        #expect(e?.contains("bad frame header") == true, "\(e ?? "no error")")
    }

    @Test func truncatedFrameIsAnError() throws {
        let (f, e) = try frames("a 1\nxgame 5\nabc")
        #expect(f == ["a:x"])
        #expect(e?.contains("ends after 3 of 5 bytes") == true, "\(e ?? "no error")")
        let (_, h) = try frames("a 1\nxgam")
        #expect(h?.contains("inside a frame header") == true, "\(h ?? "no error")")
        let (_, b) = try frames("game x\n")
        #expect(b?.contains("bad frame header") == true, "\(b ?? "no error")")
    }
}
