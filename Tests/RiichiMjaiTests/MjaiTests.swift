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
        func turn(_ s: Int) -> Mjai.Decision { Mjai.Decision(seat: Seat(s), legal: legal, trigger: .turn(drawn: Tile(Kind(.man, 1)))) }
        #expect(Mjai.action(m, for: turn(2)) == legal[0])
        #expect(Mjai.action(m, for: turn(1)) == nil)  // not this seat's
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
            var g = try GameState(rules: seed % 2 == 0 ? .tenhou : .mahjongSoul, seed: seed, events: &events)
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
                case .hora(_, let tg, let t, let d, let u, let h, let sc, let s):
                    #expect(m.target == tg.index && m.pai == t && m.deltas == d && m.uraMarkers == u && m.scores == s)
                    // Winning hand and scoring fields.
                    #expect(m.horaTehais == h)
                    #expect(m.yakus == sc.yaku.map { YakuText($0.name.text, $0.value) })
                    switch sc.value {
                    case .ordinary(let han, let fu): #expect(m.fan == han && m.fu == fu)
                    case .yakuman(let n): #expect(m.fan == 13 * n && m.fu == 0)
                    }
                    if !u.isEmpty { seen.insert("hora_with_ura") }
                case .ryukyoku(let r, let d, let tp, let th, let s):
                    #expect(m.reason == r.description && m.deltas == d && m.scores == s)
                    #expect(m.tenpais == tp && m.tehais == th.map { $0.map { $0 } })
                    // Each seat sees exactly the tenpai hands, its own included only if tenpai.
                    for seat in Seat.all {
                        let mm = try Mjai.decode(Mjai.encode(e.masked(for: seat)))
                        for (i, hand) in (mm.tehais ?? []).enumerated() {
                            #expect(hand == (tp[i] ? th[i].map { $0 } : Array(repeating: nil, count: th[i].count)))
                        }
                    }
                    if tp.contains(true) && tp.contains(false) { seen.insert("ryukyoku_mixed_tenpai") }
                case .endGame(let s): #expect(m.scores == s)
                default: break
                }
            }
        }
        for t in ["start_game", "start_kyoku", "tsumo", "dahai", "chi", "pon", "daiminkan", "ankan", "kakan", "dora",
                  "reach", "reach_accepted", "hora", "ryukyoku", "end_kyoku", "end_game", "hora_with_ura",
                  "ryukyoku_mixed_tenpai"] {
            #expect(seen.contains(t), "no \(t) in the sample")
        }
    }

    @Test func replies() throws {
        let s = Seat(1)
        let five = Tile(Kind(.pin, 5)), red = Tile(Kind(.pin, 5), red: true)
        let onDiscard = Mjai.Decision.Trigger.discard(tile: five, from: Seat(0))
        func act(_ json: String, _ legal: [Action], _ trigger: Mjai.Decision.Trigger = .turn(drawn: five),
                 concealed: [Tile] = [], pons: [[Tile]] = []) throws -> Action? {
            Mjai.action(try Mjai.decode(json), for: Mjai.Decision(seat: s, legal: legal, trigger: trigger,
                                                                  concealed: concealed, pons: pons))
        }
        #expect(try act(#"{"type":"none"}"#, [.ron, .pass], onDiscard) == .pass)
        #expect(try act(#"{"type":"hora","actor":1,"target":0}"#, [.ron, .pass], onDiscard) == .ron)
        #expect(try act(#"{"type":"hora","actor":1,"target":0,"pai":"5p"}"#, [.ron, .pass], onDiscard) == .ron)
        #expect(try act(#"{"type":"hora","actor":1,"target":1}"#, [.tsumo, .discard(five, tsumogiri: true)]) == .tsumo)
        #expect(try act(#"{"type":"ryukyoku","actor":1}"#, [.kyuushu]) == .kyuushu)
        #expect(try act(#"{"type":"reach","actor":1}"#, [.riichi]) == .riichi)
        #expect(try act(#"{"type":"reach","actor":1}"#, [.tsumo]) == nil)
        // The tsumogiri flag is corrected when only the other form is legal.
        #expect(try act(#"{"type":"dahai","actor":1,"pai":"5p","tsumogiri":false}"#, [.discard(five, tsumogiri: true)]) == .discard(five, tsumogiri: true))
        #expect(try act(#"{"type":"pon","actor":1,"target":0,"pai":"5p","consumed":["5p","5pr"]}"#, [.pon(red, five), .pon(five, five), .pass], onDiscard) == .pon(red, five))
        #expect(try act(#"{"type":"chi","actor":1,"target":0,"pai":"5p","consumed":["6p","4p"]}"#, [.chi(Tile(Kind(.pin, 4)), Tile(Kind(.pin, 6))), .pass], onDiscard) == .chi(Tile(Kind(.pin, 4)), Tile(Kind(.pin, 6))))
        let east = Kind(.honor, 1)
        #expect(try act(#"{"type":"ankan","actor":1,"consumed":["E","E","E","E"]}"#, [.ankan(east)], concealed: t("1111z")) == .ankan(east))
        #expect(try act(#"{"type":"kakan","actor":1,"pai":"5pr"}"#, [.kakan(red)], .turn(drawn: red), pons: [t("555p")]) == .kakan(red))
        #expect(try act(#"{"type":"daiminkan","actor":1,"target":0,"pai":"5p","consumed":["5p","5p","5p"]}"#, [.daiminkan, .pass], onDiscard, concealed: t("555p")) == .daiminkan)
        #expect(try act(#"{"type":"dahai","actor":1,"pai":"9s","tsumogiri":false}"#, [.discard(five, tsumogiri: false)]) == nil)
        // A reply that does not fit the trigger: a call or `none` on the seat's
        // turn, a discard in a window, a call on a kan.
        #expect(try act(#"{"type":"none"}"#, [.discard(five, tsumogiri: true)]) == nil)
        #expect(try act(#"{"type":"dahai","actor":1,"pai":"5p","tsumogiri":true}"#, [.pass], onDiscard) == nil)
        #expect(try act(#"{"type":"pon","actor":1,"consumed":["5p","5p"]}"#, [.ron, .pass], .kan(tile: five, from: Seat(0), kind: .added)) == nil)
    }

    /// A `hora` reply must match the offered target and tile (discarder or kan seat
    /// and its tile; on a tsumo, the seat itself and its drawn tile) when those fields
    /// are present.
    @Test func winRepliesMatchTheOffer() throws {
        let p1 = Tile(Kind(.pin, 1))
        let ron = Mjai.Decision(seat: Seat(3), legal: [.ron, .pass], trigger: .discard(tile: p1, from: Seat(0)))
        func act(_ json: String, _ d: Mjai.Decision) throws -> Action? { Mjai.action(try Mjai.decode(json), for: d) }
        #expect(try act(#"{"type":"hora","actor":3,"target":2,"pai":"9s"}"#, ron) == nil)  // wrong target and tile
        #expect(try act(#"{"type":"hora","actor":3,"target":2}"#, ron) == nil)
        #expect(try act(#"{"type":"hora","actor":3,"pai":"9s"}"#, ron) == nil)
        #expect(try act(#"{"type":"hora","actor":3,"target":0,"pai":"1p"}"#, ron) == .ron)
        #expect(try act(#"{"type":"hora","actor":3}"#, ron) == .ron)
        #expect(try act(#"{"type":"hora","actor":2,"target":0}"#, ron) == nil)
        let rob = Mjai.Decision(seat: Seat(3), legal: [.ron, .pass], trigger: .kan(tile: p1, from: Seat(1), kind: .added))
        #expect(try act(#"{"type":"hora","actor":3,"target":1,"pai":"1p"}"#, rob) == .ron)
        #expect(try act(#"{"type":"hora","actor":3,"target":0,"pai":"1p"}"#, rob) == nil)
        let tsumo = Mjai.Decision(seat: Seat(3), legal: [.tsumo, .discard(p1, tsumogiri: true)], trigger: .turn(drawn: p1))
        #expect(try act(#"{"type":"hora","actor":3,"target":3,"pai":"1p"}"#, tsumo) == .tsumo)
        #expect(try act(#"{"type":"hora","actor":3,"target":0}"#, tsumo) == nil)
        #expect(try act(#"{"type":"hora","actor":3,"target":3,"pai":"2p"}"#, tsumo) == nil)
    }

    /// `Mjai.reply` writes every field of a call or win, and every legal action
    /// from real games round-trips through `Mjai.decode` and `Mjai.action`.
    @Test func replyRoundTripsEveryOffer() throws {
        let pon = Mjai.reply(.pon(Tile(Kind(.man, 5)), Tile(Kind(.man, 5))), seat: Seat(0), target: Seat(1), tile: Tile(Kind(.man, 5)))
        #expect(pon == #"{"type":"pon","actor":0,"target":1,"pai":"5m","consumed":["5m","5m"]}"#)
        let kan = Mjai.reply(.daiminkan, seat: Seat(0), target: Seat(1), tile: Tile(Kind(.man, 5)), consumed: t("055m"))
        #expect(kan == #"{"type":"daiminkan","actor":0,"target":1,"pai":"5m","consumed":["5mr","5m","5m"]}"#)
        var checked = 0
        for seed in 0..<40 as Range<UInt64> {
            var g = try GameState(rules: seed % 2 == 0 ? .tenhou : .mahjongSoul, seed: seed)
            var rng = seed &+ 7
            func pick(_ a: [Action]) -> Action {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                if let w = a.first(where: { $0 == .tsumo || $0 == .ron }) { return w }
                return a[Int((rng >> 33) % UInt64(a.count))]
            }
            var steps = 0
            while !g.isOver && steps < 5000 {
                steps += 1
                for seat in Seat.all where !g.legalActions(for: seat).isEmpty {
                    let v = g.view(of: seat), d = Mjai.Decision(v)
                    for a in v.legalActions {
                        var target: Seat?, tile: Tile?, consumed: [Tile] = []
                        switch d.trigger {
                        case .turn(let drawn): tile = drawn
                        case .discard(let t, let from), .kan(let t, let from, _): target = from; tile = t
                        }
                        switch a {
                        case .ankan(let k): consumed = d.concealed.filter { $0.kind == k }
                        case .daiminkan: consumed = d.concealed.filter { $0.kind == tile!.kind }
                        case .kakan(let t): consumed = d.pons.first { $0[0].kind == t.kind }!
                        default: break
                        }
                        let reply = Mjai.reply(a, seat: seat, target: target, tile: tile, consumed: consumed)
                        #expect(Mjai.action(try Mjai.decode(reply), for: d) == a, "\(reply) for \(a)")
                        checked += 1
                    }
                }
                if case .turn(let s, _) = g.phase {
                    try g.apply(pick(g.legalActions(for: s)), by: s)
                } else {
                    var ans = Answers()
                    for s in g.seatsToAnswer { ans[s] = pick(g.legalActions(for: s)) }
                    try g.resolve(ans)
                }
            }
        }
        #expect(checked > 10_000)
    }
}
