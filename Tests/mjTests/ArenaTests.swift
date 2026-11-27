// The mjai adapter in a whole game (Codex final finding 1): a bot's reply is bound
// to the event that asks for the decision, through the indicator Mahjong Soul shows
// after a chained added kan; a reply the adapter cannot bind is counted.

import Testing
import Riichi
@testable import mj

@Suite struct ArenaTests {
    /// Seat 0 pons 3z and 1p, adds a kan of 3z, draws 1p from the dead wall and
    /// adds a kan of it; seat 3 (`23p456m789m340s99s`) may rob it. Under Mahjong
    /// Soul the 3z kan's owed indicator is shown between the `kakan` and the window.
    static let wall = makeWall(hands: ["1p1p234m678m567s33z", "1m4m7m9p1p2s5s8s1z2z3z4z5z",
                                       "1m4m7m5p9p2s5s8s9s1z2z4z6z", "23p456m789m340s99s"],
                               draws: "9m6z6z6z1s1s3z", rinshan: "1p8p", dora: "1z8s")

    func play(_ rules: Rules, bot mode: String) throws -> (GameRecord, [String]) {
        var players: [any Player] = [
            ScriptedPlayer(script: [.discard(t1("9m"), tsumogiri: true), .pon(t1("3z"), t1("3z")),
                                    .discard(t1("8m"), tsumogiri: false), .pon(t1("1p"), t1("1p")),
                                    .discard(t1("7m"), tsumogiri: false), .kakan(t1("3z")), .kakan(t1("1p"))]),
            ScriptedPlayer(script: [.discard(t1("3z"), tsumogiri: false), .discard(t1("1p"), tsumogiri: false),
                                    .discard(t1("6z"), tsumogiri: true)]),
            ScriptedPlayer(script: [.discard(t1("1s"), tsumogiri: true)]),
            MjaiBot(seat: Seat(3), command: "python3.14 \(fixture("robbot.py")) \(mode)", names: [], timeoutMs: 10_000),
        ]
        let wall = Self.wall
        let start = GameStart(position: try GamePosition(scores: [25_000, 25_000, 25_000, 25_000]),
                              walls: { seed, hand in hand == 0 ? wall : Wall(seed: seed, hand: hand) })
        let rec = try playGame(rules: rules, seed: 9, players: &players, names: ["a", "b", "c", "mjai"],
                               observers: [], botsLabel: "test", start: start)
        for p in players.prefix(3) { #expect((p as! ScriptedPlayer).refused.isEmpty) }
        let lines = rec.log.split(separator: "\n").map(String.init)
        // The first hand's events, as types (with the kan's tile).
        let first = lines.prefix { !$0.contains(#""type":"end_kyoku""#) }.map { line -> String in
            let type = line.split(separator: "\"")[3]
            if type == "kakan", let r = line.range(of: #""pai":""#) { return "kakan:\(line[r.upperBound...].prefix(2))" }
            return String(type)
        }
        return (rec, first)
    }

    @Test func robbingReplyToTheKakanIsTheDecision() throws {
        // Mahjong Soul: kakan, dora, then the window; the reply to the kakan wins.
        let (ms, msEvents) = try play(.mahjongSoul, bot: "kakan")
        let kan = try #require(msEvents.firstIndex(of: "kakan:1p"))
        #expect(Array(msEvents[kan...]) == ["kakan:1p", "dora", "hora"])
        #expect(ms.log.contains(#""type":"hora","actor":3,"target":0,"pai":"1p""#))
        #expect(ms.substitutions.total == 0, "\(ms.substitutions.text)")
        // Tenhou: no indicator before the window; the same reply wins.
        let (th, thEvents) = try play(.tenhou, bot: "kakan")
        let k2 = try #require(thEvents.firstIndex(of: "kakan:1p"))
        #expect(Array(thEvents[k2...]) == ["kakan:1p", "hora"])
        #expect(th.log.contains(#""type":"hora","actor":3,"target":0,"pai":"1p""#))
        #expect(th.substitutions.total == 0, "\(th.substitutions.text)")
    }

    @Test func aReplyToTheIndicatorIsNotTheDecision() throws {
        // Mahjong Soul: `none` to the kakan, `hora` to the indicator after it. The
        // decision is the kakan's reply (pass); the late hora is counted.
        let (ms, msEvents) = try play(.mahjongSoul, bot: "dora")
        let kan = try #require(msEvents.firstIndex(of: "kakan:1p"))
        #expect(Array(msEvents[kan...].prefix(3)) == ["kakan:1p", "dora", "tsumo"])
        #expect(!msEvents.contains("hora") || msEvents.lastIndex(of: "hora")! < kan)
        #expect(ms.substitutions.illegal == 1 && ms.substitutions.total == 1, "\(ms.substitutions.text)")
        // Tenhou: the indicator comes after the window, so the hora answers nothing.
        let (th, thEvents) = try play(.tenhou, bot: "dora")
        let k2 = try #require(thEvents.firstIndex(of: "kakan:1p"))
        #expect(Array(thEvents[k2...].prefix(3)) == ["kakan:1p", "dora", "tsumo"])
        #expect(th.substitutions.unbound == 1 && th.substitutions.total == 1, "\(th.substitutions.text)")
    }
}
