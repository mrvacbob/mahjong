// Run in a scratch copy of the package alongside RoundTests.swift and ScenarioTests.swift.
import Testing
@testable import Riichi

@Suite struct CodexReviewProbes {
    @Test func tenhouSkippedTsumoThenAnkan() throws {
        let wall = makeWall(hands: ["4444s56s678m234p8p",
                                    "1m4m7m1p4p7p2s5s8s1z2z3z4z",
                                    "2m5m8m2p5p8p3s6s9s1z2z3z4z",
                                    "3m6m9m3p6p9p1s2s7s1z2z3z4z"],
                            draws: "8p7s", rinshan: "7z")
        var events: [Event] = []
        for rules in [Rules.tenhou, .mahjongSoul] {
            var s = RoundState(rules: rules, wall: wall)
            #expect(s.legalActions(for: Seat(0)).contains(.tsumo))
            try s.apply(.ankan(t1("4s").kind), by: Seat(0))
            try s.tsumogiri(0, events: &events)
            if !s.seatsToAnswer.isEmpty { try s.answer(events: &events) }
            try s.tsumogiri(1, events: &events)
            // Observed on both presets. Design §4.2 expects Tenhou to suppress ron.
            #expect(!s.isFuriten(Seat(0)))
            #expect(s.legalActions(for: Seat(0)).contains(.ron))
        }
    }

    @Test func passedRonSurvivesReplacementDraw() throws {
        let wall = makeWall(hands: ["1m4m7m1p4p7p2s5s8s1z2z3z4z",
                                    "444s56s678m234p88p",
                                    "2m5m8m2p5p8p3s6s9s1z2z3z4z",
                                    "3m6m9m3p6p9p1s2s7s1z2z3z4z"],
                            draws: "4s7s", rinshan: "7z")
        var events: [Event] = []
        for rules in [Rules.tenhou, .mahjongSoul] {
            var s = RoundState(rules: rules, wall: wall)
            try s.tsumogiri(0, events: &events)
            let offers = s.legalActions(for: Seat(1))
            #expect(offers.contains(.ron))
            #expect(offers.contains(.daiminkan))
            try s.answer([1: .daiminkan], events: &events)
            #expect(s.drawnTile(of: Seat(1)) == t1("7z"))
            #expect(s.isFuriten(Seat(1)))
            try s.tsumogiri(1, events: &events)
            if !s.seatsToAnswer.isEmpty { try s.answer(events: &events) }
            try s.tsumogiri(2, events: &events)
            #expect(s.waits(of: Seat(1)).contains(t1("7s").kind))
            #expect(!s.legalActions(for: Seat(1)).contains(.ron))
        }
    }

    @Test func robbedClosedKanState() throws {
        let wall = makeWall(hands: ["1111m456p789p234s", "99m19p19s1234567z",
                                    "23m678m234p567s88p", "234m678m234p56s88s"],
                            draws: "4z", rinshan: "7s", dora: "3z5z")
        var events: [Event] = []
        var s = RoundState(rules: .mahjongSoul, wall: wall, events: &events)
        try s.apply(.ankan(t1("1m").kind), by: Seat(0), events: &events)
        #expect(s.kanCount == 0)
        #expect(s.melds(of: Seat(0)).count == 1)
        try s.answer([1: .ron], events: &events)
        #expect(s.result?.wins.first?.robbedKan == .closed)
        #expect(s.kanCount == 0)
        #expect(!s.anyCallMade)
        #expect(s.melds(of: Seat(0)).flatMap(\.tiles).count == 4)
        #expect(s.hand(of: Seat(0)).count == 10)
        #expect(s.doraIndicators.count == 1)
        #expect(events.map(\.text).suffix(2) == ["hora(1)", "end_kyoku"])
    }

    @Test func fourWindsKeepsPreviouslyAcceptedStick() throws {
        let json = try ScenarioFiles.load("closed_kan_rinshan_tsumo")
        let spec = (json["runs"] as! [String: [String: Any]])["mahjongsoul"]!
        var variant = spec
        variant["steps"] = Array((spec["steps"] as! [[String: Any]]).prefix(5))
        variant["expect"] = ["outcome": "abortive_draw", "abort_reason": "suufon_renda",
                             "deltas": [-1000, 0, 0, 0], "sticks": 1,
                             "events_order": ["reach_accepted(0)", "ryukyoku(suufon_renda)"]]
        #expect(ScenarioRunner(json: json, ruleset: "mahjongsoul", spec: variant).run().isEmpty)
    }

    @Test func skippedTsumoViaLegalRiichiAnkan() throws {
        // Before the kan: 111s + 23s + 44s. After the kan: 23s + 44s.
        // Both have structural waits 1s/4s, with 4s still physically available.
        let wall = makeWall(hands: ["1112344s123m789p", quietHands[0], quietHands[1],
                                    "3m6m9m3p6p9p2s4s7s1z2z3z4z"],
                            draws: "7z6z6z5z1s4s", rinshan: "7z")
        var s = RoundState(rules: .mahjongSoul, wall: wall)
        var events: [Event] = []
        try s.apply(.riichi, by: Seat(0))
        for i in 0..<4 {
            try s.tsumogiri(i, events: &events)
            if !s.seatsToAnswer.isEmpty { try s.answer(events: &events) }
        }
        let waits = [t1("1s").kind, t1("4s").kind]
        #expect(s.waits(of: Seat(0)) == waits)
        #expect(s.legalActions(for: Seat(0)).contains(.tsumo))
        #expect(s.legalActions(for: Seat(0)).contains(.ankan(t1("1s").kind)))
        #expect(!s.isFuriten(Seat(0)))
        try s.apply(.ankan(t1("1s").kind), by: Seat(0))
        #expect(s.waits(of: Seat(0)) == waits)
        #expect(s.isFuriten(Seat(0)))
        try s.tsumogiri(0, events: &events)
        if !s.seatsToAnswer.isEmpty { try s.answer(events: &events) }
        try s.tsumogiri(1, events: &events)
        #expect(!s.legalActions(for: Seat(0)).contains(.ron))
        if !s.seatsToAnswer.isEmpty { try s.answer(events: &events) }
        for i in 2..<4 {
            try s.tsumogiri(i, events: &events)
            if !s.seatsToAnswer.isEmpty { try s.answer(events: &events) }
        }
        #expect(s.phase.isTurn(of: Seat(0)))
        #expect(s.isFuriten(Seat(0)))
    }

    @Test func skippedTsumoDisputeWithFourWindsRemoved() throws {
        let wall = makeWall(hands: ["23444s678m234p88p", "1s1144p5566p1122m",
                                    "23s567m456p789p99m", "3344m7799p6677s6z"],
                            draws: "3z3z3z7z4s4z", rinshan: "5z", dora: "1z2z")
        var s = RoundState(rules: .mahjongSoul, wall: wall)
        var events: [Event] = []
        try s.apply(.riichi, by: Seat(0))
        for i in 0..<4 {
            try s.tsumogiri(i, events: &events)
            if !s.seatsToAnswer.isEmpty { try s.answer(events: &events) }
        }
        #expect(s.waits(of: Seat(0)) == [t1("8p").kind, t1("1s").kind, t1("4s").kind])
        #expect(completingKinds(Counts(t("678m234p23s88p")), meldCount: 1) ==
                [t1("1s").kind, t1("4s").kind])
        #expect(s.legalActions(for: Seat(0)).contains(.tsumo))
        #expect(!s.legalActions(for: Seat(0)).contains(.ankan(t1("4s").kind)))
    }
}
