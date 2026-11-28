// PlayerView analysis helpers (Docs/Design/engine.md §6.3): checked against
// the engine's own state in whole games, and the defensive facts on built tables.

import Testing
@testable import Riichi

@Suite struct AnalysisTests {
    /// Copies of each kind the seat cannot see, from the engine's side: the other
    /// seats' concealed tiles and every wall tile not yet drawn or revealed.
    func hidden(_ s: RoundState, from seat: Seat) -> [Int] {
        var n = [Int](repeating: 0, count: Kind.count)
        for o in Seat.all where o != seat {
            for t in s.hand(of: o) { n[t.kind.index] += 1 }
            if let d = s.drawnTile(of: o) { n[d.kind.index] += 1 }
        }
        for i in s.liveDrawn..<Wall.liveDraws { n[s.wall.liveDraw(i).kind.index] += 1 }
        for i in s.replacementsDrawn..<Wall.replacements { n[s.wall.replacement(i).kind.index] += 1 }
        for i in s.doraShown..<Wall.indicators { n[s.wall.doraIndicator(i).kind.index] += 1 }
        for i in 0..<Wall.indicators { n[s.wall.uraIndicator(i).kind.index] += 1 }
        // A live draw that a kan's replacement took the place of is not in the wall
        // the seat could draw from, but it is still unseen.
        return n
    }

    func check(_ g: GameState, _ seat: Seat) throws {
        let s = g.round, v = g.view(of: seat), t = v.table
        #expect(v == s.view(of: seat))
        #expect(t.seatWind == seat.wind(dealer: s.dealer))
        #expect(t.isClosed == s.melds(of: seat).allSatisfy { $0.kind == .ankan })
        for o in Seat.all { #expect(t.isRiichi(o) == (s.riichiStatus(of: o) != .none)) }
        #expect(v.furitenParts == s.furitenParts(of: seat) && v.furitenParts.any == v.furiten)
        if t.hand.count == 13 - 3 * t.melds[seat.index].count { #expect(v.waits == s.waits(of: seat)) }
        // Visible and unseen copies add up to four of every kind (no meld or called
        // discard counted twice), unless a kan is announced and not yet made.
        if case .robbing = s.phase {} else {
            let h = hidden(s, from: seat)
            for k in Kind.all { #expect(t.unseen(k) == h[k.index], "\(k): unseen \(t.unseen(k)), hidden \(h[k.index])") }
        }
        #expect(v.allCopiesSeen == Kind.all.filter { t.visibleCounts[$0] == 4 })
        // Each legal discard: what it leaves, and what improves that.
        let options = try v.discardOptions()
        let discards = v.legalActions.filter { if case .discard = $0 { true } else { false } }
        #expect(options.count == discards.count)
        for o in options {
            #expect(discards.contains(.discard(o.tile, tsumogiri: o.tsumogiri)))
            var rest = t.concealed
            rest.remove(at: rest.firstIndex(of: o.tile)!)
            let counts = Counts(rest), m = t.melds[seat.index].count
            #expect(o.shanten == shanten(counts, meldCount: m).min)
            for k in Kind.all where counts[k] < 4 {
                let better = shanten(counts.adding(k), meldCount: m).min < o.shanten
                let d = o.improving.first { $0.kind == k }
                #expect((d != nil) == better)
                if let d { #expect(d.unseen == t.unseen(k)) }
            }
        }
        // Genbutsu is certain: the seat named cannot ron that kind now.
        for x in Seat.all where x != seat {
            if case .robbing(let k) = s.phase, k.seat == x { continue }
            for k in v.genbutsu(against: x) {
                #expect(s.isFuriten(x) || !s.waits(of: x).contains(k), "genbutsu \(k) against \(x)")
            }
            #expect(Set(v.suji(against: x)).isDisjoint(with: v.genbutsu(against: x)))
        }
        #expect(v.genbutsu(against: seat).isEmpty)
    }

    @Test(arguments: [Bot.eager, .random]) func helpersAgreeWithTheEngine(_ bot: Bot) throws {
        var genbutsuSeen = 0
        for seed in 0..<6 as Range<UInt64> {
            var rng = TestRNG(state: seed &+ 4242)
            _ = try playGame(rules: seed % 2 == 0 ? .tenhou : .mahjongSoul, seed: seed, bot: bot, rng: &rng) { g, _ in
                guard !g.isOver else { return }
                for seat in Seat.all where !g.legalActions(for: seat).isEmpty {
                    try check(g, seat)
                    genbutsuSeen += Seat.all.filter { $0 != seat }.map { g.view(of: seat).genbutsu(against: $0).count }.reduce(0, +)
                }
            }
        }
        #expect(genbutsuSeen > 0)
    }

    /// The defensive facts on a built table: seat 1 discarded 4m and declared
    /// riichi on 9p; seat 2 then discarded 5s, seat 3 discarded 2p.
    @Test func defenceOnABuiltTable() throws {
        var tb = PlayerView.Table(seat: Seat(0))
        func d(_ tile: String, order: Int, riichi: Bool = false) -> PondTile {
            PondTile(tile: t1(tile), tsumogiri: false, riichi: riichi, calledAway: false, order: order)
        }
        tb.ponds = [[d("1z", order: 0)], [d("4m", order: 1), d("9p", order: 5, riichi: true)],
                    [d("2z", order: 2), d("5s", order: 6)], [d("3z", order: 3), d("2p", order: 7)]]
        tb.riichi = [.none, .accepted, .none, .none]
        tb.hand = t("1m4m7m2p3p5p6s7s8s5z5z5z6z")
        tb.drawn = t1("6z")
        let none = FuritenParts(ownDiscard: false, temporary: false, riichi: false)
        let v = PlayerView(table: tb, furiten: false, furitenParts: none, legalActions: [])
        // Its own 4m and 9p; 5s and 2p came after its riichi.
        #expect(v.genbutsu(against: Seat(1)) == [Kind(.man, 4), Kind(.pin, 2), Kind(.pin, 9), Kind(.sou, 5)])
        // Suji: 1m and 7m by 4m (7m's other ryanmen would wait on 10m); 2s and 8s by
        // 5s. Not 5p (needs 2p and 8p), 6p (needs 3p and 9p) or 3p (needs 6p).
        #expect(v.suji(against: Seat(1)) == [Kind(.man, 1), Kind(.man, 7), Kind(.sou, 2), Kind(.sou, 8)])
        // Seat 2 has discarded since seat 1: its own pond, and 2p after its last discard.
        #expect(v.genbutsu(against: Seat(2)) == [Kind(.pin, 2), Kind(.sou, 5), Kind(.honor, 2)])
        // Three 5z and two 6z in sight: no kind fully seen yet.
        #expect(v.allCopiesSeen.isEmpty)
        tb.doraIndicators = [t1("5z")]
        tb.melds[3] = [TableMeld.pon(taken: t1("6z"), from: Seat(0), using: t("66z"))!]
        let v2 = PlayerView(table: tb, furiten: false, furitenParts: none, legalActions: [])
        #expect(v2.allCopiesSeen == [Kind(.honor, 5), Kind(.honor, 6)])
        #expect(v2.table.unseen(Kind(.honor, 6)) == 0 && v2.table.unseen(Kind(.man, 1)) == 3)
        // The table's melds go straight into a score request.
        let pon = TableMeld.pon(taken: t1("5z"), from: Seat(1), using: t("55z"))!
        let req = ScoreRequest(hand: t("234m567p2345s"), tableMelds: [pon], win: t1("5s"),
                               context: WinContext(tsumo: false))
        #expect(req.melds == [pon.meld])
        #expect(try score(req, rules: .mahjongSoul).yakuText == "yakuhai_haku:1")
    }

    @Test func discardAnalysisChecksItsInput() throws {
        let none = Counts()
        #expect(throws: InputError.self) { try discardAnalysis(concealed: t("123m"), meldCount: 0, visible: none) }
        #expect(throws: InputError.self) { try discardAnalysis(concealed: t("11111m234567p99s"), meldCount: 0, visible: none) }
        #expect(throws: InputError.self) { try discardAnalysis(concealed: t("11m"), meldCount: 5, visible: none) }
        #expect(throws: InputError.self) {
            try discardAnalysis(concealed: t("123456789m12344p"), meldCount: 0, visible: none, candidates: t("9s"))
        }
        // 123456789m 12344p: discarding 1p leaves 2344p, waiting on 1p and 4p (44p + 23p).
        let hand = t("123456789m12344p")
        let options = try discardAnalysis(concealed: hand, meldCount: 0, visible: Counts(hand))
        #expect(options.map(\.tile) == t("123456789m1234p"))
        let one = try #require(options.first { $0.tile == t1("1p") })
        #expect(one.shanten == 0)
        #expect(one.improving.map(\.kind) == [Kind(.pin, 1), Kind(.pin, 4)])
        #expect(one.improving.map(\.unseen) == [3, 2] && one.unseen == 5)
    }
}
