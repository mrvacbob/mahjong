// Round behaviour the scenarios do not reach, on hand-built walls.

import Testing
@testable import Riichi

/// A wall with these hands (by seat), live draws from index 0, replacement tiles
/// and indicators; every other slot filled from the unused tiles in canonical order
/// (as Tools/scenario.py fills them).
func makeWall(dealer: Int = 0, hands: [String], draws: String = "", rinshan: String = "",
              dora: String = "", ura: String = "") -> Wall {
    var pool = Wall.sorted
    func take(_ t: Tile) -> Tile {
        guard let i = pool.firstIndex(of: t) else { fatalError("tile \(t) over-allocated") }
        pool.remove(at: i)
        return t
    }
    var slots = [Tile?](repeating: nil, count: 136)
    let hs = hands.map { t($0) }
    precondition(hs.count == 4 && hs.allSatisfy { $0.count == 13 })
    var cursor = [0, 0, 0, 0], w = 0
    for round in 0..<4 {
        for off in 0..<4 {
            let s = (dealer + off) % 4
            for _ in 0..<(round < 3 ? 4 : 1) {
                slots[w] = take(hs[s][cursor[s]]); cursor[s] += 1; w += 1
            }
        }
    }
    for (i, x) in t(draws).enumerated() { slots[52 + i] = take(x) }
    for (i, x) in t(rinshan).enumerated() { slots[122 + i] = take(x) }
    for (i, x) in t(dora).enumerated() { slots[126 + i] = take(x) }
    for (i, x) in t(ura).enumerated() { slots[131 + i] = take(x) }
    var rest = pool.makeIterator()
    return Wall(tiles: slots.map { $0 ?? rest.next()! })!
}

extension Phase {
    func isTurn(of seat: Seat) -> Bool { if case .turn(let s, _) = self { s == seat } else { false } }
}

extension RoundState {
    /// Every seat asked answers `.pass`, except those given.
    mutating func answer(_ given: [Int: Action] = [:], events: inout [Event]) throws {
        var a = Answers()
        for s in seatsToAnswer { a[s] = given[s.index] ?? .pass }
        try resolve(a, events: &events)
    }
    mutating func tsumogiri(_ seat: Int, events: inout [Event]) throws {
        try apply(.discard(drawnTile(of: Seat(seat))!, tsumogiri: true), by: Seat(seat), events: &events)
    }
}

/// Four hands with no pairs and few neighbours: nobody can call honors 5z-7z.
let quietHands = [
    "1m4m7m1p4p7p2s5s8s1z2z3z4z",
    "2m5m8m2p5p8p3s6s9s1z2z3z4z",
    "3m6m9m3p6p9p1s4s7s1z2z3z4z",
]

@Suite struct RoundTests {
    @Test func riichiFuritenAfterSkippedTsumo() throws {
        // Seat 0 (dealer) waits 1s/4s; riichi on 7z, then draws 1s and lets it go.
        let wall = makeWall(hands: ["123m456m789p23s99s", quietHands[0], quietHands[1], quietHands[2]],
                            draws: "7z6z6z5z1s4s")
        var ev: [Event] = []
        var s = try RoundState(rules: .mahjongSoul, wall: wall, events: &ev)
        try s.apply(.riichi, by: Seat(0), events: &ev)
        try s.tsumogiri(0, events: &ev)
        for seat in 1...3 { try s.tsumogiri(seat, events: &ev) }
        #expect(s.legalActions(for: Seat(0)).contains(.tsumo))
        #expect(!s.isFuriten(Seat(0)))
        try s.tsumogiri(0, events: &ev)  // skips the winning 1s
        #expect(s.isFuriten(Seat(0)))
        // Seat 1 discards 4s: seat 0 is not asked.
        try s.tsumogiri(1, events: &ev)
        #expect(s.legalActions(for: Seat(0)).isEmpty)
        // It is permanent: still furiten after its next draw.
        while case .turn(let t, _) = s.phase, t != Seat(0) { try s.tsumogiri(t.index, events: &ev) }
        #expect(s.isFuriten(Seat(0)))
    }

    @Test func temporaryFuritenEndsAtOwnDrawOnly() throws {
        // Seat 1 waits 1s/4s, not in riichi; passes the 4s seat 0 discards.
        let wall = makeWall(hands: [quietHands[0].replacingOccurrences(of: "5s", with: "4s"),
                                    "123m456m789p23s99s", quietHands[1], quietHands[2]],
                            draws: "5s6z6z5z")
        var ev: [Event] = []
        var s = try RoundState(rules: .mahjongSoul, wall: wall, events: &ev)
        try s.apply(.discard(t1("4s"), tsumogiri: false), by: Seat(0), events: &ev)
        #expect(s.legalActions(for: Seat(1)).contains(.ron))
        try s.answer(events: &ev)
        // Seat 1 has drawn since, so the temporary furiten is over.
        #expect(s.phase.isTurn(of: Seat(1)))
        #expect(!s.isFuriten(Seat(1)))
    }

    @Test func passingARonMakesFuritenUntilOwnDraw() throws {
        // Seat 2 waits on 1s/4s and passes the 4s; seat 1 draws next, so seat 2 is
        // still furiten.
        let wall = makeWall(hands: [quietHands[0], quietHands[1], "123m456m789p23s99s", quietHands[2]],
                            draws: "4s6z")
        var ev: [Event] = []
        var s = try RoundState(rules: .mahjongSoul, wall: wall, events: &ev)
        try s.tsumogiri(0, events: &ev)  // 4s: seat 2 may ron
        #expect(s.seatsToAnswer == [Seat(2)])
        try s.answer(events: &ev)
        #expect(s.isFuriten(Seat(2)))
    }

    @Test func tenhouAndChiihou() throws {
        // Dealer's 13 + first draw 1s is complete.
        var wall = makeWall(hands: ["123m456m789p23s99s", quietHands[0], quietHands[1], quietHands[2]],
                            draws: "1s")
        var s = try RoundState(rules: .mahjongSoul, wall: wall)
        #expect(s.legalActions(for: Seat(0)).first == .tsumo)
        try s.apply(.tsumo, by: Seat(0))
        let w = try #require(s.result?.wins.first)
        #expect(w.scored.yakuText == "tenhou:1")
        #expect(s.result?.deltas == [48_000, -16_000, -16_000, -16_000])

        // Non-dealer: seat 1 completes on its first draw.
        wall = makeWall(hands: [quietHands[0], "123m456m789p23s99s", quietHands[1], quietHands[2]],
                        draws: "6z1s")
        s = try RoundState(rules: .tenhou, wall: wall)
        var ev: [Event] = []
        try s.tsumogiri(0, events: &ev)
        try s.apply(.tsumo, by: Seat(1))
        #expect(s.result?.wins.first?.scored.yakuText == "chiihou:1")
        #expect(s.result?.deltas == [-16_000, 32_000, -8_000, -8_000])
    }

    @Test func errorsLeaveTheStateUnchanged() throws {
        let wall = makeWall(hands: [quietHands[0], quietHands[1], "123m456m789p23s99s", quietHands[2]],
                            draws: "4s6z")
        var ev: [Event] = []
        var s = try RoundState(rules: .mahjongSoul, wall: wall, events: &ev)
        #expect(throws: RoundError.wrongPhase) { try s.resolve(Answers()) }
        #expect(throws: RoundError.notYourTurn(Seat(1))) { try s.apply(.tsumo, by: Seat(1)) }
        #expect(throws: RoundError.illegal(Seat(0), .riichi)) { try s.apply(.riichi, by: Seat(0)) }
        try s.tsumogiri(0, events: &ev)
        let before = ev.count
        #expect(throws: RoundError.missingAnswer(Seat(2))) { try s.resolve(Answers(), events: &ev) }
        #expect(ev.count == before)
        #expect(throws: RoundError.wrongPhase) { try s.apply(.pass, by: Seat(2)) }
        var a = Answers()
        a[Seat(2)] = .pass
        a[Seat(1)] = .ron  // not asked
        #expect(throws: RoundError.illegal(Seat(1), .ron)) { try s.resolve(a) }
        a[Seat(1)] = .pass  // a pass from a seat not asked is accepted
        try s.resolve(a, events: &ev)
        #expect(ev.map(\.text).suffix(1) == ["tsumo(1)"])
    }

    @Test func eventText() {
        #expect(Event.pon(actor: Seat(1), target: Seat(0), tile: t1("5m"), consumed: t("05m")).text == "pon(1)")
        #expect(Event.dora(marker: t1("9p")).text == "dora(9p)")
        #expect(Event.ryukyoku(reason: .exhaustive, deltas: [], tenpais: [], tehais: [], scores: []).text
                == "ryukyoku(exhaustive)")
        #expect(Event.ryukyoku(reason: .abort(.suufonRenda), deltas: [], tenpais: [], tehais: [], scores: []).text
                == "ryukyoku(suufon_renda)")
        #expect(Event.endKyoku.text == "end_kyoku")
        #expect(Action.pon(t1("0m"), t1("5m")).description == "pon:05m")
        #expect(Action.discard(t1("5m"), tsumogiri: true).description == "tsumogiri:5m")
    }

    @Test func canonicalOrderOfTurnActions() throws {
        // Dealer holds 5m 5m 0m? No: 0m 5m 5m and draws 5m: ankan:5m, and discards
        // 0m, 5m, then the tsumogiri of 5m.
        let wall = makeWall(hands: ["055m1p4p7p2s5s8s1z2z3z4z", quietHands[0].replacingOccurrences(of: "5s", with: "6s"),
                                    quietHands[1].replacingOccurrences(of: "5m", with: "6m"), quietHands[2]],
                            draws: "5m")
        let s = try RoundState(rules: .mahjongSoul, wall: wall)
        let legal = s.legalActions(for: Seat(0)).map(\.description)
        #expect(legal.first == "ankan:5m")
        let discards = legal.filter { $0.hasPrefix("discard:") || $0.hasPrefix("tsumogiri:") }
        #expect(Array(discards.prefix(3)) == ["discard:0m", "discard:5m", "tsumogiri:5m"])
    }
}

/// `Rules` fields with no preset that turns them on, checked by flipping one field
/// on an existing scenario and adjusting its expectations.
@Suite struct RulesFieldScenarioTests {
    func run(_ name: String, rules: Rules, ruleset: String = "mahjongsoul",
             patch: (inout [String: Any]) -> Void) throws -> [String] {
        let json = try ScenarioFiles.load(name)
        let runs = json["runs"] as! [String: Any]
        var spec = runs[ruleset] as! [String: Any]
        var expect = spec["expect"] as! [String: Any]
        patch(&expect)
        spec["expect"] = expect
        return ScenarioRunner(json: json, ruleset: ruleset, spec: spec, rules: rules).run()
    }

    @Test func honbaToEveryRonWinner() throws {
        var r = Rules.mahjongSoul
        r.honbaToEveryRonWinner = true
        let problems = try run("double_ron_with_sticks_and_honba", rules: r) { e in
            // Seat 0 (dealer, 2900) now also gets the 600 honba.
            e["deltas"] = [3500, -6100, 3600, 0]
            e["scores"] = [28500, 18900, 28600, 24000]
        }
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func fourWindsRiichiStickNotPaid() throws {
        // Both presets pay the stick (settled from real game records); the field
        // off gives the old default: no acceptance, no stick.
        var r = Rules.mahjongSoul
        r.fourWindsRiichiStickPaid = false
        let problems = try run("abort_suufon_renda_riichi_stick", rules: r) { e in
            e["deltas"] = [0, 0, 0, 0]
            e["scores"] = [25000, 25000, 25000, 25000]
            e["sticks"] = 0
            var ev = e["events"] as! [String]
            ev.remove(at: ev.firstIndex(of: "reach_accepted(3)")!)
            e["events"] = ev
        }
        #expect(problems.isEmpty, "\(problems)")
    }

    /// Gemini final finding 6: both presets have `openKanDoraBeforeRon` on, so the
    /// earlier test here (setting it on) tested nothing. Off, the open kan's
    /// indicator is still owed when the discard after the kan is ronned: no `dora`
    /// event, no kan dora, 2 han instead of 4.
    @Test(arguments: ["mahjongsoul", "tenhou"]) func openKanDoraAfterTheWindow(_ ruleset: String) throws {
        var r: Rules = ruleset == "tenhou" ? .tenhou : .mahjongSoul
        r.openKanDoraBeforeRon = false
        let problems = try run("open_kan_discard_ron_dora", rules: r, ruleset: ruleset) { e in
            e["win 2"] = nil
            e["wins"] = ["2": ["han": 2, "fu": 30, "yaku": ["pinfu", "tanyao"]]]
            e["deltas"] = [0, -2000, 2000, 0]
            e["scores"] = [25000, 23000, 27000, 25000]
            e["events"] = ["start_kyoku", "tsumo(0)", "dahai(0)", "daiminkan(1)", "tsumo(1)", "dahai(1)", "hora(2)",
                           "end_kyoku"]
        }
        #expect(problems.isEmpty, "\(problems)")
        // The unpatched expectation (the kan dora counted) fails with the field off.
        let json = try ScenarioFiles.load("open_kan_discard_ron_dora")
        let runs = json["runs"] as! [String: Any]
        #expect(!ScenarioRunner(json: json, ruleset: ruleset, spec: runs[ruleset] as! [String: Any], rules: r).run().isEmpty)
    }

    /// Gemini final finding 8: `allLastTestAfterNagashi` off, asserted somewhere. In
    /// South 4 the tenpai dealer is first on 31,000 before a non-dealer's nagashi
    /// and fourth after it: with the field off the test reads the scores before the
    /// payments, so tenpai-yame ends the game.
    @Test func allLastTestBeforeNagashi() throws {
        var r = Rules.mahjongSoul
        r.allLastTestAfterNagashi = false
        let problems = try run("endgame_nagashi_pushes_dealer_out_of_first", rules: r) { e in
            e["game_ended"] = true
            for k in ["next_wind", "next_round", "next_dealer"] { e[k] = nil }
            e["final_scores"] = [33000, 23000, 17000, 27000]
            e["final_ranks"] = [0, 3, 1, 2]
        }
        #expect(problems.isEmpty, "\(problems)")
    }
}
