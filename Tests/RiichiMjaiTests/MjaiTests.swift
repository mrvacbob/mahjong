// The mjai codec: tile names, the JSON reader (skipping what it does not need),
// encoding every event and reading it back, masking, bot replies.

import Testing
import Riichi
@testable import RiichiMjai

@Suite struct MjaiTests {
    @Test func tileNames() {
        for t in Wall.sorted {
            #expect(Mjai.tile(Mjai.name(t)) == t)
        }
        #expect(Mjai.name(Tile(Kind(.man, 5), red: true)) == "5mr")
        #expect(Mjai.name(Tile(Kind(.honor, 5))) == "P")
        #expect(Mjai.name(Tile(Kind(.honor, 7))) == "C")
        #expect(Mjai.name(nil as Tile?) == "?")
        for bad in ["?", "0m", "5z", "4mr", "10m", "", "m5", "Z", "5mrr"] { #expect(Mjai.tile(bad) == nil, "\(bad)") }
    }

    /// Mortal's replies carry `meta` with nested objects and arrays of floats.
    @Test func readerSkipsNestedValues() throws {
        let reply = #"{"type":"dahai","meta":{"q_values":[0.25,-1.5e-3,1E+2,[1,{"a":[]}]],"mask_bits":7,"s":"x\"}y","n":null,"ok":true},"actor":2,"pai":"5mr","tsumogiri":false}"#
        let m = try Mjai.decode(reply)
        #expect(m.type == "dahai" && m.actor == 2 && m.pai == Tile(Kind(.man, 5), red: true) && m.tsumogiri == false)
        let legal: [Action] = [.discard(Tile(Kind(.man, 5), red: true), tsumogiri: false), .discard(Tile(Kind(.man, 1)), tsumogiri: true)]
        #expect(Mjai.action(m, seat: Seat(2), legal: legal) == legal[0])
        #expect(Mjai.action(m, seat: Seat(1), legal: legal) == nil)  // not this seat's
        let o = try JSONObject(parsing: #"  {"s": "aé\n🀄", "x": [1, 2] }  "#)
        #expect(o["s"]?.string == "aé\n🀄")
        #expect(o["x"]?.array?.compactMap(\.int) == [1, 2])
        for bad in ["", "{", #"{"a":}"#, #"{"a":1,}"#, #"{"a":1} x"#, "[1]", #"{"a":tru}"#, #"{"a":"x}"#] {
            #expect(throws: JSONError.self, "\(bad)") { try JSONObject(parsing: bad) }
        }
        #expect(throws: MjaiError.self) { try Mjai.decode(#"{"type":"dahai","actor":9}"#) }
        #expect(throws: MjaiError.self) { try Mjai.decode(#"{"actor":1}"#) }
    }

    @Test func writerEscapes() throws {
        let o = JSONOut.object([("a", .string("q\"\\\n\u{1}é")), ("b", .array([.int(-3), .bool(true), .null]))])
        #expect(o.text == #"{"a":"q\"\\\n\u0001é","b":[-3,true,null]}"#)
        #expect(try JSONObject(parsing: o.text)["a"]?.string == "q\"\\\n\u{1}é")
    }

    /// Every event of some real games encodes and reads back with the same fields,
    /// and each seat's masked form hides exactly the other hands and draws.
    @Test func eventsRoundTrip() throws {
        var seen: Set<String> = []
        for seed in 0..<30 as Range<UInt64> {
            var events: [Event] = []
            var g = GameState(rules: seed % 2 == 0 ? .tenhou : .mahjongSoul, seed: seed, events: &events)
            var all = events
            var rng = seed &+ 1
            func pick(_ a: [Action]) -> Action {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                // Prefer wins and calls so that every event type appears.
                if let w = a.first(where: { $0 == .tsumo || $0 == .ron }) { return w }
                if a.contains(.riichi) { return .riichi }
                if let c = a.first(where: { if case .pon = $0 { true } else if case .chi = $0 { true } else if case .ankan = $0 { true } else if case .kakan = $0 { true } else { $0 == .daiminkan } }), rng >> 60 < 9 { return c }
                return a[Int((rng >> 33) % UInt64(a.count))]
            }
            var steps = 0
            while !g.isOver && steps < 5000 {
                steps += 1
                events = []
                if case .turn(let s, _) = g.phase {
                    try g.apply(pick(g.legalActions(for: s)), by: s, events: &events)
                } else {
                    var ans = Answers()
                    for s in g.seatsToAnswer { ans[s] = pick(g.legalActions(for: s)) }
                    try g.resolve(ans, events: &events)
                }
                all += events
            }
            #expect(g.isOver)
            for e in all {
                seen.insert(e.type)
                let m = try Mjai.decode(Mjai.encode(e))
                #expect(m.type == e.type)
                #expect(m.actor == e.actor?.index)
                switch e {
                case .startKyoku(let b, let k, let h, let s, let o, let d, let sc, let th):
                    #expect(m.bakaze == b && m.kyoku == k && m.honba == h && m.kyotaku == s && m.oya == o.index)
                    #expect(m.doraMarker == d && m.scores == sc && m.tehais == th.map { $0.map { $0 } })
                    for seat in Seat.all {
                        let mm = try Mjai.decode(Mjai.encode(e.masked(for: seat)))
                        for (i, h) in (mm.tehais ?? []).enumerated() {
                            #expect(h.allSatisfy { ($0 == nil) == (i != seat.index) })
                        }
                    }
                case .tsumo(let a, let t):
                    #expect(m.pai == t)
                    for seat in Seat.all {
                        let mm = try Mjai.decode(Mjai.encode(e.masked(for: seat)))
                        #expect(mm.paiHidden == (seat != a) && (mm.pai == (seat == a ? t : nil)))
                    }
                case .dahai(_, let t, let tg): #expect(m.pai == t && m.tsumogiri == tg)
                case .chi(_, let tg, let t, let c), .pon(_, let tg, let t, let c), .daiminkan(_, let tg, let t, let c):
                    #expect(m.target == tg.index && m.pai == t && m.consumed == c)
                case .ankan(_, let c): #expect(m.consumed == c)
                case .kakan(_, let t, let c): #expect(m.pai == t && m.consumed == c)
                case .dora(let d): #expect(m.doraMarker == d)
                case .reachAccepted(_, let s): #expect(m.scores == s)
                case .hora(_, let tg, let t, let d, let u, _, _, let s):
                    #expect(m.target == tg.index && m.pai == t && m.deltas == d && m.uraMarkers == u && m.scores == s)
                case .ryukyoku(let r, let d, _, _, let s):
                    #expect(m.reason == r.description && m.deltas == d && m.scores == s)
                case .endGame(let s): #expect(m.scores == s)
                default: break
                }
            }
        }
        for t in ["start_game", "start_kyoku", "tsumo", "dahai", "chi", "pon", "ankan", "kakan", "dora", "reach",
                  "reach_accepted", "hora", "ryukyoku", "end_kyoku", "end_game"] {
            #expect(seen.contains(t), "no \(t) in the sample")
        }
    }

    @Test func replies() throws {
        let s = Seat(1)
        func act(_ json: String, _ legal: [Action]) throws -> Action? { Mjai.action(try Mjai.decode(json), seat: s, legal: legal) }
        let five = Tile(Kind(.pin, 5)), red = Tile(Kind(.pin, 5), red: true)
        #expect(try act(#"{"type":"none"}"#, [.ron, .pass]) == .pass)
        #expect(try act(#"{"type":"hora","actor":1,"target":0}"#, [.ron, .pass]) == .ron)
        #expect(try act(#"{"type":"hora","actor":1,"target":1}"#, [.tsumo, .discard(five, tsumogiri: true)]) == .tsumo)
        #expect(try act(#"{"type":"ryukyoku","actor":1}"#, [.kyuushu]) == .kyuushu)
        #expect(try act(#"{"type":"reach","actor":1}"#, [.riichi]) == .riichi)
        #expect(try act(#"{"type":"reach","actor":1}"#, [.tsumo]) == nil)
        // The tsumogiri flag is corrected when only the other form is legal.
        #expect(try act(#"{"type":"dahai","actor":1,"pai":"5p","tsumogiri":false}"#, [.discard(five, tsumogiri: true)]) == .discard(five, tsumogiri: true))
        #expect(try act(#"{"type":"pon","actor":1,"target":0,"pai":"5p","consumed":["5p","5pr"]}"#, [.pon(red, five), .pon(five, five), .pass]) == .pon(red, five))
        #expect(try act(#"{"type":"chi","actor":1,"target":0,"pai":"5p","consumed":["6p","4p"]}"#, [.chi(Tile(Kind(.pin, 4)), Tile(Kind(.pin, 6))), .pass]) == .chi(Tile(Kind(.pin, 4)), Tile(Kind(.pin, 6))))
        #expect(try act(#"{"type":"ankan","actor":1,"consumed":["E","E","E","E"]}"#, [.ankan(Kind(.honor, 1))]) == .ankan(Kind(.honor, 1)))
        #expect(try act(#"{"type":"kakan","actor":1,"pai":"5pr"}"#, [.kakan(red)]) == .kakan(red))
        #expect(try act(#"{"type":"daiminkan","actor":1,"target":0,"pai":"E","consumed":["E","E","E"]}"#, [.daiminkan, .pass]) == .daiminkan)
        #expect(try act(#"{"type":"dahai","actor":1,"pai":"9s","tsumogiri":false}"#, [.discard(five, tsumogiri: false)]) == nil)
    }
}
