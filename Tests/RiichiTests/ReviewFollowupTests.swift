// TableMeld red fives, scoring and legality edge cases, dealing, and the `mj` line protocol.

import Foundation
import Testing
@testable import Riichi

@Suite struct RedFiveTableMeldTests {
    @Test func ponWithRedFromHandThenPlainAdded() throws {
        let pon = try #require(TableMeld.pon(taken: t1("5p"), from: Seat(1), using: t("0p5p")))
        #expect(pon.tiles == t("055p") && pon.consumed == t("05p") && pon.taken == t1("5p"))
        let kan = try #require(pon.adding(t1("5p")))
        #expect(kan.tiles == t("0555p") && kan.added == t1("5p") && kan.consumed == t("055p"))
    }

    @Test func plainPonWithRedAdded() throws {
        let pon = try #require(TableMeld.pon(taken: t1("5s"), from: Seat(0), using: t("55s")))
        let kan = try #require(pon.adding(t1("0s")))
        #expect(kan.tiles == t("0555s") && kan.added == t1("0s") && kan.consumed == t("555s"))
    }

    @Test func twoRedsAreRejected() throws {
        let pon = try #require(TableMeld.pon(taken: t1("0m"), from: Seat(2), using: t("55m")))
        #expect(pon.adding(t1("0m")) == nil)
        #expect(TableMeld.daiminkan(taken: t1("0m"), from: Seat(1), using: t("055m")) == nil)
        #expect(TableMeld.ankan(t("0055m")) == nil)
        let open = try #require(TableMeld.daiminkan(taken: t1("0m"), from: Seat(1), using: t("555m")))
        #expect(open.consumed == t("555m") && open.tiles == t("0555m"))
        let closed = try #require(TableMeld.ankan(t("5055p")))
        #expect(closed.tiles == t("0555p") && closed.consumed == t("0555p"))
    }

    @Test func chiSujiKuikae() throws {
        let low = try #require(TableMeld.chi(taken: t1("4m"), from: Seat(3), using: t("0m6m")))
        #expect(low.kuikaeForbidden == [Kind(.man, 4), Kind(.man, 7)])
        let high = try #require(TableMeld.chi(taken: t1("0p"), from: Seat(3), using: t("67p")))
        #expect(high.kuikaeForbidden == [Kind(.pin, 5), Kind(.pin, 8)])
    }

    @Test func meldKuikaeIsEmptyForKans() {
        #expect(Meld(kind: .daiminkan, tiles: t("1111m"))!.kuikaeForbidden(took: Kind(.man, 1)).isEmpty)
        #expect(Meld(kind: .ankan, tiles: t("1111m"))!.kuikaeForbidden(took: Kind(.man, 1)).isEmpty)
    }
}

@Suite struct ReviewScoringTests {
    @Test func tenhouWithChuurenPerRuleset() {
        // 1123456789999m + 1m drawn: any-tile choice makes 9m the winner (junsei).
        let hand = "1123456789999m"
        let ms = scored(hand: hand, win: "1m", tsumo: true, seat: .east, flags: [.tenhou],
                        rules: .mahjongSoul)
        let th = scored(hand: hand, win: "1m", tsumo: true, seat: .east, flags: [.tenhou],
                        rules: .tenhou)
        #expect(ms.yaku == "junsei_chuuren:2,tenhou:1")
        #expect(th.yaku == "chuuren:1,tenhou:1")
    }

    @Test func scoredIsHashableAndTyped() throws {
        let a = try scored(hand: "123m456p789s1122z", win: "1z", tsumo: false, seat: .east,
                           rules: .mahjongSoul).get()
        let b = try scored(hand: "123m456p789s1122z", win: "1z", tsumo: false, seat: .east,
                           rules: .mahjongSoul).get()
        #expect(a == b)
        #expect(a.value(of: .yakuhai_seat) == 1 && a.value(of: .riichi) == nil)
    }

    @Test func tenpaiAtDrawWithClosedKan() {
        // Only wait 5m; all four 5m are in the closed kan, none concealed.
        let concealed = Counts(t("46m123p456s99s"))
        let m = melds("a5555m")
        #expect(isTenpaiAtDraw(concealed, melds: m, rules: .tenhou))
        // Mahjong Soul as well.
        #expect(isTenpaiAtDraw(concealed, melds: m, rules: .mahjongSoul))
        var strict = Rules.mahjongSoul
        strict.fifthCopyTenpaiAtDraw = false
        #expect(!isTenpaiAtDraw(concealed, melds: m, rules: strict))
    }

    @Test func calledSituationWithRedFives() throws {
        // Chi 0m with 67m: 5m (either copy) and 8m are forbidden.
        let chi = try LegalRequest(hand: t("558m1z111p234p5s"), melds: melds("c067m"),
                                   situation: .called(Meld(kind: .chi, tiles: t("067m"))!, took: t1("0m")),
                                   rules: .mahjongSoul).actions
        #expect(chi == ["discard:1p", "discard:1z", "discard:2p", "discard:3p", "discard:4p", "discard:5s"])
        // Pon of 5p with 0p5p: no 5p of either colour.
        let pon = try LegalRequest(hand: t("5p3s111m222m333m"), melds: melds("p055p"),
                                   situation: .called(Meld(kind: .pon, tiles: t("055p"))!, took: t1("5p")),
                                   rules: .mahjongSoul).actions
        #expect(pon == ["discard:1m", "discard:2m", "discard:3m", "discard:3s"])
    }
}

@Suite struct DealTests {
    @Test func everyDealerGetsTheDealerSlots() {
        let w = Wall(seed: 5, hand: 0)
        let dealerSlots = Array(0..<4) + Array(16..<20) + Array(32..<36) + [48]
        for d in 0..<4 {
            let dealer = Seat(d)
            #expect(w.dealt(to: dealer, dealer: dealer) == dealerSlots.map { w.tiles[$0] })
            // The four hands partition 0..<52.
            let all = Seat.all.flatMap { w.dealt(to: $0, dealer: dealer) }
            #expect(all.sorted() == Array(w.tiles[0..<52]).sorted())
            for s in Seat.all {
                #expect(w.dealt(to: s, dealer: dealer) == w.dealt(toDealerOffset: s.distance(from: dealer)))
            }
        }
    }
}

/// The `mj` line protocol, run as a child process. Skipped when the executable has
/// not been built next to the test bundle.
@Suite struct LineProtocolTests {
    /// `.build/debug/mj` (or release), else `./mj` from `make`, in the package root.
    static var mjPath: String? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for rel in [".build/debug/mj", ".build/release/mj", "mj"] {
            let candidate = root.appendingPathComponent(rel).path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    func run(_ lines: [String]) throws -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: try #require(Self.mjPath))
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        try p.run()
        input.fileHandleForWriting.write((lines.joined(separator: "\n") + "\n").data(using: .utf8)!)
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    @Test(.enabled(if: mjPath != nil)) func rulesAndValidation() throws {
        let out = try run([
            "1 score hand=55m66m77m11z22z33z4z melds=- win=4z by=ron seat=S rules=tenhou",
            "2 score hand=55m66m77m11z22z33z4z melds=- win=4z by=ron seat=S rules=mahjongsoul",
            "3 score hand=55m66m77m11z22z33z4z melds=- win=4z by=ron seat=S rules=bogus",
            "4 legal hand=9m19p19s1234567z7z melds=- discard=1m from=toimen flags=ankan_rob rules=tenhou",
            "5 legal hand=9m19p19s1234567z7z melds=- discard=1m from=toimen flags=ankan_rob",
            "6 legal hand=9m19p19s1234567z7z melds=- discard=1m from=toimen rules=nope",
            "7 score hand=123m456p789s1122z melds=- win=1z by=bogus seat=E",
            "8 legal hand=123m456p789s1122z melds=- discard=1z from=bogus seat=E",
            "9 legal hand=123m456p789s1z melds=k1111p called=k1111p took=1p",
        ])
        #expect(out.count == 9)
        #expect(out[0].hasPrefix("1 ") && !out[0].contains("error"))
        #expect(out[2] == "3 error=bad_rules")
        #expect(out[3] == "4 actions=pass")
        #expect(out[4] == "5 actions=pass,ron")
        #expect(out[5] == "6 error=bad_rules")
        #expect(out[6] == "7 error=bad_by")
        #expect(out[7] == "8 error=bad_from")
        #expect(out[8] == "9 error=bad_called")
    }

    /// Malformed and physically impossible requests (non-ASCII digits, 16 copies
    /// of a kind, too many melds, honba past `Int`, invalid hand sizes) return an
    /// error rather than crashing.
    @Test(.enabled(if: mjPath != nil)) func hostileRequestsAreAnswered() throws {
        let fixed = [
            "1 shanten hand=⑽m",
            "2 shanten hand=1111111111111111m",
            "3 waits hand=１m",
            "4 score hand=123456m789p23s99s win=1s by=ron honba=9223372036854775807",
            "5 agari hand=11m melds=p111p,p222p,p333p,p444p,p555p",
            "6 legal hand=1m melds=p111p,p222p,p333p,p444p,p555p draw=1m",
            "7 score hand=123456m789p23s9s win=1s by=ron",
        ]
        let out = try run(fixed)
        #expect(out.count == fixed.count)
        #expect(out[0] == "1 error=bad_hand" && out[1] == "2 error=impossible_tiles" && out[2] == "3 error=bad_hand")
        #expect(out[3] == "4 error=bad_honba")
        #expect(out[4] == "5 error=bad_melds" && out[5] == "6 error=bad_melds")
        #expect(out[6] == "7 error=bad_hand_size")
        var rng = TestRNG(state: 2026)
        let parts = ["1", "5", "0", "9", "⑽", "１", "m", "p", "s", "z", "x", "-"]
        func junk() -> String { (0..<rng.below(30)).map { _ in parts[rng.below(parts.count)] }.joined() }
        func hand() -> String {
            let n = [0, 1, 13, 14, 16, 40][rng.below(6)]
            return (0..<n).map { _ in "\(1 + rng.below(9))\(["m", "p", "s"][rng.below(3)])" }.joined()
        }
        var lines: [String] = []
        for i in 0..<3000 {
            let op = ["agari", "shanten", "waits", "score", "legal"][rng.below(5)]
            var q = "h\(i) \(op) hand=\(rng.chance(50) ? hand() : junk())"
            if rng.chance(50) { q += " melds=\(["-", "p111m,p222m,p333m,p444m,p555m", "c123m", "a1111z", junk()][rng.below(5)])" }
            if rng.chance(60) { q += " win=\(rng.chance(50) ? "1m" : junk()) by=\(rng.chance(50) ? "ron" : "tsumo")" }
            if rng.chance(30) { q += " draw=\(junk())" }
            if rng.chance(30) { q += " honba=\(["0", "999", "1000", "-1", "99999999999999999999"][rng.below(5)])" }
            if rng.chance(30) { q += " dora=\(junk())" }
            lines.append(q)
        }
        let answers = try run(lines)
        #expect(answers.count == lines.count)
        #expect(zip(lines, answers).allSatisfy { $1.hasPrefix(String($0.split(separator: " ")[0]) + " ") })
    }
}
