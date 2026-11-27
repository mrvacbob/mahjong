// Hostile input to the JSON reader and the mjai decoder (Gemini's C/D review,
// docs/reviews/p3/CD-agy.md findings 1, 2, 8–11): nothing a bot or a log can send
// may crash; it must come back as an error.

import Testing
import Riichi
@testable import RiichiMjai

@Suite struct HardeningTests {
    /// Finding 1: a high surrogate followed by an escape that is not a low surrogate.
    @Test func unpairedSurrogates() throws {
        let o = try JSONObject(parsing: #"{"a":"\uD800\u0000","b":"🀄","c":"\uDC00x"}"#)
        #expect(o["a"]?.string == "\u{FFFD}\u{0}")
        #expect(o["b"]?.string == "🀄")
        #expect(o["c"]?.string == "\u{FFFD}x")
    }

    /// Finding 2: deep nesting is refused, not recursed into.
    @Test func deepNesting() {
        let deep = #"{"type":"none","meta":"# + String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000) + "}"
        #expect(throws: JSONError.self) { try JSONObject(parsing: deep) }
        #expect(throws: MjaiError.self) { try Mjai.decode(deep) }
        let ok = #"{"a":"# + String(repeating: "[", count: 60) + String(repeating: "]", count: 60) + "}"
        #expect((try? JSONObject(parsing: ok)) != nil)
    }

    /// Finding 8: escapes, control characters and numbers are validated at parse
    /// time, also inside values that are only skipped.
    @Test func strictGrammar() {
        for bad in [#"{"a":"\q"}"#, #"{"a":"x\#u{1}y"}"#, #"{"a":1..2e+-3}"#, #"{"a":01}"#, #"{"a":.5}"#,
                    #"{"a":-}"#, #"{"a":1e}"#, #"{"a":[1,"\x"]}"#, #"{"a":{"b":"\u12"}}"#] {
            #expect(throws: JSONError.self, "\(bad)") { try JSONObject(parsing: bad) }
        }
        for good in [#"{"a":0}"#, #"{"a":-0.5e+10}"#, #"{"a":12.25E-3}"#, #"{"a":"\/\b\f\t"}"#] {
            #expect((try? JSONObject(parsing: good)) != nil, "\(good)")
        }
        #expect(throws: MjaiError.self) { try Mjai.decode(#"{"type":"dahai","actor":0,"pai":"\q","tsumogiri":false}"#) }
    }

    /// Finding 9: the last of repeated keys wins, as in other JSON readers.
    @Test func duplicateKeysLastWins() throws {
        #expect(try Mjai.decode(#"{"type":"none","type":"dahai","actor":0,"pai":"1m","tsumogiri":true}"#).type == "dahai")
    }

    /// Finding 10: a present field of the wrong type is an error.
    @Test func wrongTypes() {
        for bad in [#"{"type":"dahai","actor":0,"pai":123,"tsumogiri":false}"#,
                    #"{"type":"dahai","actor":0,"pai":"1m","tsumogiri":"nope"}"#,
                    #"{"type":"start_kyoku","tehais":"x"}"#, #"{"type":"start_kyoku","bakaze":1}"#,
                    #"{"type":"start_game","names":[1,2]}"#, #"{"type":"ryukyoku","reason":7}"#,
                    #"{"type":"end_kyoku","dealer_repeats":1}"#, #"{"type":"ryukyoku","tenpais":[1]}"#] {
            #expect(throws: MjaiError.self, "\(bad)") { try Mjai.decode(bad) }
        }
        // Null is "absent"; `uradora_markers` is read as `ura_markers`.
        #expect((try? Mjai.decode(#"{"type":"dahai","actor":0,"pai":"1m","tsumogiri":null}"#))?.tsumogiri == nil)
        #expect((try? Mjai.decode(#"{"type":"hora","actor":0,"target":0,"uradora_markers":["1m"]}"#))?.uraMarkers == [Tile(Kind(.man, 1))])
    }

    /// Finding 11: a closed kan names four tiles of one kind; a call names the
    /// discard it takes.
    @Test func callFieldsValidated() throws {
        let k = Kind(.man, 1)
        let turn = Mjai.Decision(seat: Seat(0), legal: [.ankan(k), .discard(Tile(k), tsumogiri: true)],
                                 trigger: .turn(drawn: Tile(k)), concealed: t("1111m234p567s789s"))
        for c in [#"["1m"]"#, #"["1m","9p","2s","E"]"#, #"["1m","1m","1m"]"#] {
            let m = try Mjai.decode(#"{"type":"ankan","actor":0,"consumed":"# + c + "}")
            #expect(Mjai.action(m, for: turn) == nil, "\(c)")
        }
        let good = try Mjai.decode(#"{"type":"ankan","actor":0,"consumed":["1m","1m","1m","1m"]}"#)
        #expect(Mjai.action(good, for: turn) == .ankan(k))
        let five = Tile(Kind(.pin, 5))
        let calls = Mjai.Decision(seat: Seat(0), legal: [.daiminkan, .pon(five, five), .pass],
                                  trigger: .discard(tile: five, from: Seat(3)), concealed: t("555p123m456m789m1z"))
        func act(_ s: String) throws -> Action? { Mjai.action(try Mjai.decode(s), for: calls) }
        #expect(try act(#"{"type":"daiminkan","actor":0,"target":3,"pai":"5p","consumed":["5p","5p","5p"]}"#) == .daiminkan)
        #expect(try act(#"{"type":"daiminkan","actor":0}"#) == .daiminkan)
        #expect(try act(#"{"type":"daiminkan","actor":0,"target":2,"pai":"5p"}"#) == nil)
        #expect(try act(#"{"type":"daiminkan","actor":0,"target":3,"pai":"6p"}"#) == nil)
        #expect(try act(#"{"type":"daiminkan","actor":0,"consumed":["5p","5p"]}"#) == nil)
        #expect(try act(#"{"type":"pon","actor":0,"target":3,"pai":"5p","consumed":["5p","5p"]}"#) == .pon(five, five))
        #expect(try act(#"{"type":"pon","actor":0,"target":1,"pai":"5p","consumed":["5p","5p"]}"#) == nil)
    }

    /// Gemini final finding 3: a kan names the very tiles it uses, so impossible red
    /// fives are refused; an added kan's `consumed`, when given, is the pon.
    @Test func kanTilesAreTheHand() throws {
        let five = Kind(.man, 5)
        let ankan = Mjai.Decision(seat: Seat(0), legal: [.ankan(five), .discard(Tile(five), tsumogiri: true)],
                                  trigger: .turn(drawn: Tile(five)), concealed: t("0555m234p567s789s"))
        func act(_ s: String, _ d: Mjai.Decision) throws -> Action? { Mjai.action(try Mjai.decode(s), for: d) }
        #expect(try act(#"{"type":"ankan","actor":0,"consumed":["5mr","5m","5m","5m"]}"#, ankan) == .ankan(five))
        for bad in [#"["5mr","5mr","5mr","5mr"]"#, #"["5m","5m","5m","5m"]"#, #"["5mr","5mr","5m","5m"]"#] {
            #expect(try act(#"{"type":"ankan","actor":0,"consumed":"# + bad + "}", ankan) == nil, "\(bad)")
        }
        let open = Mjai.Decision(seat: Seat(0), legal: [.daiminkan, .pass],
                                 trigger: .discard(tile: Tile(five), from: Seat(1)), concealed: t("055m234p567s789s1z"))
        #expect(try act(#"{"type":"daiminkan","actor":0,"target":1,"pai":"5m","consumed":["5mr","5m","5m"]}"#, open) == .daiminkan)
        #expect(try act(#"{"type":"daiminkan","actor":0,"target":1,"pai":"5m","consumed":["5mr","5mr","5mr"]}"#, open) == nil)
        let pon = t("055m")
        let kakan = Mjai.Decision(seat: Seat(0), legal: [.kakan(Tile(five)), .discard(Tile(five), tsumogiri: true)],
                                  trigger: .turn(drawn: Tile(five)), concealed: t("234p567s789s5m"), pons: [pon])
        #expect(try act(#"{"type":"kakan","actor":0,"pai":"5m"}"#, kakan) == .kakan(Tile(five)))
        #expect(try act(#"{"type":"kakan","actor":0,"pai":"5m","consumed":["5mr","5m","5m"]}"#, kakan) == .kakan(Tile(five)))
        #expect(try act(#"{"type":"kakan","actor":0,"pai":"5m","consumed":["5m","5m","5m"]}"#, kakan) == nil)
    }
}

func t(_ s: String) -> [Tile] { parseTiles(Substring(s))! }
