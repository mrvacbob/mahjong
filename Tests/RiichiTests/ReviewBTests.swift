// Findings of the package B review (docs/reviews/p3/B-codex.md), each fixed and
// tested here; the probes are adapted from docs/reviews/p3/B-codex-repro.

import Testing
@testable import Riichi

@Suite struct ReviewBTests {
    /// Finding 1, as settled by the real logs (docs/notes/p3-closeout.md): a seat
    /// that declines a tsumo by a closed kan may ron before its next live draw on
    /// both clients (Tenhou's records have such rons, 2010–18), so neither preset
    /// sets `temporaryFuritenOnDeclinedTsumo`. With the field on (the strict
    /// reading of Tenhou's manual) the furiten lasts through the kan's replacement
    /// draw until the next live draw.
    @Test func declinedTsumoThenAnkan() throws {
        let wall = makeWall(hands: ["4444s56s678m234p8p",
                                    "1m4m7m1p4p7p2s5s8s1z2z3z4z",
                                    "2m5m8m2p5p8p3s6s9s1z2z3z4z",
                                    "3m6m9m3p6p9p1s2s7s1z2z3z4z"],
                            draws: "8p7s", rinshan: "7z")
        var events: [Event] = []
        var strict = Rules.tenhou
        strict.temporaryFuritenOnDeclinedTsumo = true
        for rules in [Rules.tenhou, .mahjongSoul, strict] {
            let furiten = rules.temporaryFuritenOnDeclinedTsumo
            var s = RoundState(rules: rules, wall: wall)
            #expect(s.legalActions(for: Seat(0)).contains(.tsumo))
            try s.apply(.ankan(t1("4s").kind), by: Seat(0))
            #expect(s.drawnTile(of: Seat(0)) == t1("7z"))
            #expect(s.isFuriten(Seat(0)) == furiten)
            try s.tsumogiri(0, events: &events)
            if !s.seatsToAnswer.isEmpty { try s.answer(events: &events) }
            try s.tsumogiri(1, events: &events)
            #expect(s.isFuriten(Seat(0)) == furiten)
            #expect(s.legalActions(for: Seat(0)).contains(.ron) == !furiten)
        }
        #expect(!Rules.tenhou.temporaryFuritenOnDeclinedTsumo && !Rules.mahjongSoul.temporaryFuritenOnDeclinedTsumo)
    }

    /// Why the field cannot show except through a kan: a tsumo declined by a
    /// discard leaves 13 tiles that wait on the discarded kind (with it they are the
    /// winning hand), so the seat is own-discard furiten until its hand changes,
    /// whatever the field says.
    @Test func declinedTsumoByDiscardIsOwnDiscardFuriten() throws {
        let wall = makeWall(hands: ["23456m456p789s55z",
                                    "1m4m7m1p4p7p2s5s8s1z2z3z4z",
                                    "2m5m8m2p5p8p3s6s9s1z2z3z4z",
                                    "3m6m9m3p6p9p1s2s7s1z2z3z4z"],
                            draws: "6z6z6z6z7m5m")
        var strict = Rules.tenhou
        strict.temporaryFuritenOnDeclinedTsumo = true
        for rules in [Rules.tenhou, .mahjongSoul, strict] {
            var events: [Event] = []
            var s = RoundState(rules: rules, wall: wall)
            for seat in 0..<4 {
                try s.tsumogiri(seat, events: &events)
                if !s.seatsToAnswer.isEmpty { try s.answer(events: &events) }
            }
            #expect(s.legalActions(for: Seat(0)).contains(.tsumo))
            try s.apply(.discard(t1("2m"), tsumogiri: false), by: Seat(0))
            let f = s.furitenParts(of: Seat(0))
            #expect(f.ownDiscard)
            #expect(f.temporary == rules.temporaryFuritenOnDeclinedTsumo)
            #expect(s.waits(of: Seat(0)).map(\.description) == ["2m", "5m", "8m"])
            try s.tsumogiri(1, events: &events)  // 5m: a wait, but furiten
            #expect(!s.seatsToAnswer.contains(Seat(0)))
        }
    }

    /// Finding 2: a robbed closed kan is never a meld; the declarer keeps three
    /// copies concealed and the fourth is the winning tile.
    @Test func robbedClosedKanIsNotAMeld() throws {
        let wall = makeWall(hands: ["1111m456p789p234s", "99m19p19s1234567z",
                                    "23m678m234p567s88p", "234m678m234p56s88s"],
                            draws: "4z", rinshan: "7s", dora: "3z5z")
        var events: [Event] = []
        var s = RoundState(rules: .mahjongSoul, wall: wall, events: &events)
        try s.apply(.ankan(t1("1m").kind), by: Seat(0), events: &events)
        #expect(s.kanCount == 0)
        #expect(s.melds(of: Seat(0)).isEmpty)
        try checkInvariants(s, total: 100_000)
        try s.answer([1: .ron], events: &events)
        #expect(s.result?.wins.first?.robbedKan == .closed)
        #expect(s.kanCount == 0)
        #expect(!s.anyCallMade)
        #expect(s.melds(of: Seat(0)).isEmpty)
        #expect(s.hand(of: Seat(0)).count == 13)
        #expect(s.hand(of: Seat(0)).count(where: { $0 == t1("1m") }) == 3)
        #expect(s.doraIndicators.count == 1)
        try checkInvariants(s, total: 100_000)
        #expect(events.map(\.text).suffix(2) == ["hora(1)", "end_kyoku"])
    }

    /// Finding 3: the fourth kan's owed indicator is shown before the four-kan abort
    /// (Mahjong Soul: after the ron window; Tenhou: at the discard).
    @Test func fourthOpenKanDoraBeforeAbort() throws {
        let wall = makeWall(hands: ["1111m9999m1111p2z", "999p234m678m234p6z",
                                    "55z345p678p234s88s", "456m567s1122s666z"],
                            draws: "9p", rinshan: "3z4z4z5z", dora: "1z2z3z4z7z")
        for rules in [Rules.mahjongSoul, .tenhou] {
            var events: [Event] = []
            var s = RoundState(rules: rules, wall: wall, events: &events)
            for k in ["1m", "9m", "1p"] {
                try s.apply(.ankan(t1(k).kind), by: Seat(0), events: &events)
            }
            try s.apply(.discard(t1("9p"), tsumogiri: false), by: Seat(0), events: &events)
            try s.answer([1: .daiminkan], events: &events)
            try s.tsumogiri(1, events: &events)
            #expect(s.legalActions(for: Seat(2)).contains(.pon(t1("5z"), t1("5z"))))
            try s.answer([2: .pon(t1("5z"), t1("5z"))], events: &events)
            #expect(s.result?.outcome == .abortiveDraw(.suukaikan))
            let tail = events.map(\.text).suffix(4)
            #expect(tail.contains("dora(7z)"), "\(rules == .tenhou ? "tenhou" : "ms"): \(tail)")
            #expect(tail.last == "end_kyoku")
        }
    }

    /// Gemini finding 1: nothing about a closed kan changes until its window
    /// closes, so no cache is stale during it; after the commit the waits are the
    /// new hand's.
    @Test func closedKanWindowLeavesHandAndWaitsAsBefore() throws {
        let wall = makeWall(hands: ["1111m234p567p88s4z", "99m19p19s1234567z",
                                    "234m567m234s567s2z", "345m678m345s678s2z"],
                            draws: "8s", rinshan: "7s", dora: "3z")
        var s = RoundState(rules: .mahjongSoul, wall: wall)
        let before = (s.hand(of: Seat(0)), s.drawnTile(of: Seat(0)), s.waits(of: Seat(0)))
        try s.apply(.ankan(t1("1m").kind), by: Seat(0))
        guard case .robbing(let pk) = s.phase, pk.kind == .closed else { Issue.record("no window"); return }
        #expect(s.hand(of: Seat(0)) == before.0)
        #expect(s.drawnTile(of: Seat(0)) == before.1)
        #expect(s.waits(of: Seat(0)) == before.2)
        #expect(s.waits(of: Seat(0)) == waitKinds(s.hand(of: Seat(0)), melds: 0))
        #expect(s.melds(of: Seat(0)).isEmpty)
        try checkInvariants(s, total: 100_000)
        var events: [Event] = []
        try s.answer(events: &events)   // seat 1 passes: the kan commits
        #expect(s.melds(of: Seat(0)).count == 1)
        #expect(s.waits(of: Seat(0)) == [t1("4z").kind])
        try checkInvariants(s, total: 100_000)
    }

    /// Gemini finding 2: three kokushi rons on a closed kan with both
    /// kokushiRobsClosedKan and tripleRonAborts: the abort keeps every tile.
    @Test func sanchahouOnClosedKanConservesTiles() throws {
        let wall = makeWall(hands: ["1111m234p567p234s", "99m19p19s1234567z",
                                    "9m119p19s1234567z", "9m19p119s1234567z"],
                            draws: "5s", rinshan: "6s", dora: "2m")
        var rules = Rules.tenhou
        rules.kokushiRobsClosedKan = true
        var s = RoundState(rules: rules, wall: wall)
        try s.apply(.ankan(t1("1m").kind), by: Seat(0))
        #expect(s.seatsToAnswer == [Seat(1), Seat(2), Seat(3)])
        var a = Answers()
        for i in 1...3 { a[Seat(i)] = .ron }
        try s.resolve(a)
        #expect(s.result?.outcome == .abortiveDraw(.sanchahou))
        #expect(s.melds(of: Seat(0)).isEmpty)
        try checkInvariants(s, total: 100_000)
    }
}

/// Structural waits of a 13 − 3k tile hand.
func waitKinds(_ hand: [Tile], melds: Int) -> [Kind] {
    Kind.all.filter { shanten(Counts(hand).adding($0), meldCount: melds).min < 0 }
}
