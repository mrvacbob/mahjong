// mjai JSON for events and bot replies (docs/design/engine.md §6). Field order
// is fixed, so the same events always give the same bytes.

import Riichi

public enum Mjai {
    // MARK: tiles

    static let honorNames = ["E", "S", "W", "N", "P", "F", "C"]

    /// `1m`…`9m`, `5mr` for a red five, `E S W N P F C` for honors.
    public static func name(_ t: Tile) -> String {
        if t.kind.isHonor { return honorNames[t.kind.number - 1] }
        return "\(t.kind.number)\(t.kind.suit.letter)\(t.isRed ? "r" : "")"
    }
    /// A kind's name (never red).
    public static func name(_ k: Kind) -> String { name(Tile(k)) }
    /// `?` for a tile that is not shown.
    public static func name(_ t: Tile?) -> String { t.map(name) ?? "?" }

    /// The tile named, or nil (also for `?`).
    public static func tile(_ s: String) -> Tile? {
        if let i = honorNames.firstIndex(of: s) { return Tile(Kind(.honor, i + 1)) }
        let u = Array(s.utf8)
        guard u.count == 2 || (u.count == 3 && u[2] == UInt8(ascii: "r")),
              let d = Int(String(UnicodeScalar(u[0]))), (1...9).contains(d),
              let suit = Suit(letter: Character(UnicodeScalar(u[1]))), suit != .honor else { return nil }
        let red = u.count == 3
        if red && d != 5 { return nil }
        return Tile(Kind(suit, d), red: red)
    }

    public static func windName(_ w: Wind) -> String { honorNames[w.rawValue - 1] }

    // MARK: encoding events

    static func tiles(_ ts: [Tile]) -> JSONOut { .array(ts.map { .string(name($0)) }) }
    static func tiles(_ ts: [Tile?]) -> JSONOut { .array(ts.map { .string(name($0)) }) }
    static func ints(_ ns: [Int]) -> JSONOut { .array(ns.map { .int($0) }) }

    /// Extra fields for the unmasked log and for bots.
    public struct Extras: Sendable {
        /// `start_game.names`.
        public var names: [String]?
        /// `start_kyoku.wall` (unmasked log only).
        public var wall: Wall?
        /// `end_kyoku`'s `scores`, `deltas`, `kyotaku_left` and `dealer_repeats` (unmasked
        /// log only: what libriichi-check reads to check an isolated or final hand).
        public var result: RoundResult?
        public init(names: [String]? = nil, wall: Wall? = nil, result: RoundResult? = nil) {
            self.names = names
            self.wall = wall
            self.result = result
        }
    }

    /// An unmasked event (the game log).
    public static func encode(_ e: Event, _ x: Extras = Extras()) -> String {
        object(for: shown(e), id: nil, x).text
    }

    /// An event as a seat sees it (what a bot is sent).
    public static func encode(_ e: MaskedEvent, names: [String]? = nil) -> String {
        var id: Seat? = nil
        if case .startGame(let s) = e { id = s }
        return object(for: e, id: id, Extras(names: names)).text
    }

    /// Every tile shown: the log's form of an event.
    static func shown(_ e: Event) -> MaskedEvent {
        switch e {
        case .startKyoku(let b, let k, let h, let s, let o, let d, let sc, let th):
            return .startKyoku(bakaze: b, kyoku: k, honba: h, kyotaku: s, oya: o, doraMarker: d,
                               scores: sc, tehais: th.map { $0.map { $0 } })
        case .tsumo(let a, let t): return .tsumo(actor: a, tile: t)
        case .ryukyoku(let r, let d, let tp, let th, let s):
            return .ryukyoku(reason: r, deltas: d, tenpais: tp, tehais: th.map { $0.map { $0 } }, scores: s)
        default:
            // Every other event shows the same to everyone.
            return e.masked(for: Seat(0))
        }
    }

    static func object(for e: MaskedEvent, id: Seat?, _ x: Extras) -> JSONOut {
        func ev(_ type: String, _ f: [(String, JSONOut)]) -> JSONOut { .object([("type", .string(type))] + f) }
        switch e {
        case .startGame:
            var f: [(String, JSONOut)] = []
            if let id { f.append(("id", .int(id.index))) }
            f.append(("names", .array((x.names ?? ["0", "1", "2", "3"]).map { .string($0) })))
            return ev("start_game", f)
        case .startKyoku(let b, let k, let h, let s, let o, let d, let sc, let th):
            var f: [(String, JSONOut)] = [
                ("bakaze", .string(windName(b))), ("dora_marker", .string(name(d))), ("kyoku", .int(k)),
                ("honba", .int(h)), ("kyotaku", .int(s)), ("oya", .int(o.index)), ("scores", ints(sc)),
                ("tehais", .array(th.map { tiles($0) })),
            ]
            if let w = x.wall { f.append(("wall", tiles(w.tiles))) }
            return ev("start_kyoku", f)
        case .tsumo(let a, let t):
            return ev("tsumo", [("actor", .int(a.index)), ("pai", .string(name(t)))])
        case .dahai(let a, let t, let g):
            return ev("dahai", [("actor", .int(a.index)), ("pai", .string(name(t))), ("tsumogiri", .bool(g))])
        case .chi(let a, let tg, let t, let c), .pon(let a, let tg, let t, let c), .daiminkan(let a, let tg, let t, let c):
            let type = switch e { case .chi: "chi"; case .pon: "pon"; default: "daiminkan" }
            return ev(type, [("actor", .int(a.index)), ("target", .int(tg.index)), ("pai", .string(name(t))),
                             ("consumed", tiles(c))])
        case .ankan(let a, let c):
            return ev("ankan", [("actor", .int(a.index)), ("consumed", tiles(c))])
        case .kakan(let a, let t, let c):
            return ev("kakan", [("actor", .int(a.index)), ("pai", .string(name(t))), ("consumed", tiles(c))])
        case .dora(let m):
            return ev("dora", [("dora_marker", .string(name(m)))])
        case .reach(let a):
            return ev("reach", [("actor", .int(a.index))])
        case .reachAccepted(let a, let s):
            return ev("reach_accepted", [("actor", .int(a.index)), ("scores", ints(s))])
        case .hora(let a, let tg, let p, let d, let u, let h, let sc, let s):
            let (fan, fu): (Int, Int) = switch sc.value {
                case .ordinary(let han, let fu): (han, fu)
                case .yakuman(let n): (13 * n, 0)
            }
            let yakus: JSONOut = .array(sc.yaku.map { .array([.string($0.name.text), .int($0.value)]) })
            return ev("hora", [
                ("actor", .int(a.index)), ("target", .int(tg.index)), ("pai", .string(name(p))),
                ("deltas", ints(d)), ("ura_markers", tiles(u)), ("uradora_markers", tiles(u)),
                ("hora_tehais", tiles(h)), ("yakus", yakus), ("fu", .int(fu)), ("fan", .int(fan)),
                ("scores", ints(s)),
            ])
        case .ryukyoku(let r, let d, let tp, let th, let s):
            return ev("ryukyoku", [
                ("reason", .string(r.description)), ("deltas", ints(d)),
                ("tenpais", .array(tp.map { .bool($0) })), ("tehais", .array(th.map { tiles($0) })),
                ("scores", ints(s)),
            ])
        case .endKyoku:
            guard let r = x.result else { return ev("end_kyoku", []) }
            return ev("end_kyoku", [
                ("scores", ints(r.scores)), ("deltas", ints(r.deltas)), ("kyotaku_left", .int(r.sticks)),
                ("dealer_repeats", .bool(r.dealerRepeats)),
            ])
        case .endGame(let s):
            return ev("end_game", [("scores", ints(s))])
        }
    }
}

// MARK: decoding

/// One mjai message, as read: every field this package uses, each nil when absent.
/// A tile written `?` reads as `hidden`.
public struct MjaiMessage: Sendable {
    public var type: String
    public var actor: Int?
    public var target: Int?
    public var pai: Tile?
    public var paiHidden = false
    public var consumed: [Tile]?
    public var tsumogiri: Bool?
    /// Each hand's tiles, nil for `?`.
    public var tehais: [[Tile?]]?
    public var scores: [Int]?
    public var deltas: [Int]?
    public var bakaze: Wind?
    public var kyoku: Int?
    public var honba: Int?
    public var kyotaku: Int?
    public var oya: Int?
    public var doraMarker: Tile?
    public var uraMarkers: [Tile]?
    public var wall: [Tile]?
    public var names: [String]?
    public var id: Int?
    public var reason: String?
    public var kyotakuLeft: Int?
    public var dealerRepeats: Bool?
    public var tenpais: [Bool]?
    public var horaTehais: [Tile]?
    /// `yakus`: each yaku's name (`spec/formats.md`) and han (or yakuman multiple).
    public var yakus: [YakuText]?
    public var fu: Int?
    public var fan: Int?

    public init(type: String) { self.type = type }
}

/// One entry of `hora.yakus`.
public struct YakuText: Sendable, Hashable {
    public let name: String
    public let value: Int
    public init(_ name: String, _ value: Int) { self.name = name; self.value = value }
}

public struct MjaiError: Error, Sendable, CustomStringConvertible {
    public let description: String
}

extension Mjai {
    /// Reads one message. Unknown fields (Mortal's `meta`, anything else) are skipped.
    public static func decode(_ line: String) throws(MjaiError) -> MjaiMessage {
        let o: JSONObject
        do { o = try JSONObject(parsing: line) } catch { throw MjaiError(description: "malformed JSON: \(error)") }
        guard let type = o["type"]?.string else { throw MjaiError(description: "no type") }
        var m = MjaiMessage(type: type)
        func int(_ k: String) throws(MjaiError) -> Int? {
            guard let v = o[k], v != .null else { return nil }
            guard let n = v.int else { throw MjaiError(description: "\(k) is not an integer") }
            return n
        }
        func ints(_ k: String) throws(MjaiError) -> [Int]? {
            guard let v = o[k], v != .null else { return nil }
            guard let a = v.array else { throw MjaiError(description: "\(k) is not an array") }
            var out: [Int] = []
            for x in a {
                guard let n = x.int else { throw MjaiError(description: "\(k) holds a non-integer") }
                out.append(n)
            }
            return out
        }
        func tileList(_ v: JSONValue, _ k: String) throws(MjaiError) -> [Tile?] {
            guard let a = v.array else { throw MjaiError(description: "\(k) is not an array") }
            var out: [Tile?] = []
            for x in a {
                guard let s = x.string else { throw MjaiError(description: "\(k) holds a non-string") }
                if s == "?" { out.append(nil); continue }
                guard let t = tile(s) else { throw MjaiError(description: "bad tile \(s) in \(k)") }
                out.append(t)
            }
            return out
        }
        func known(_ k: String) throws(MjaiError) -> [Tile]? {
            guard let v = o[k], v != .null else { return nil }
            let ts = try tileList(v, k)
            var out: [Tile] = []
            for t in ts {
                guard let t else { throw MjaiError(description: "hidden tile in \(k)") }
                out.append(t)
            }
            return out
        }
        func oneTile(_ k: String) throws(MjaiError) -> Tile? {
            guard let v = o[k], v != .null else { return nil }
            guard let s = v.string, let t = tile(s) else { throw MjaiError(description: "bad \(k)") }
            return t
        }
        // A field that is present (and not null) must have its type.
        func bool(_ k: String) throws(MjaiError) -> Bool? {
            guard let v = o[k], v != .null else { return nil }
            guard let b = v.bool else { throw MjaiError(description: "\(k) is not a boolean") }
            return b
        }
        func str(_ k: String) throws(MjaiError) -> String? {
            guard let v = o[k], v != .null else { return nil }
            guard let s = v.string else { throw MjaiError(description: "\(k) is not a string") }
            return s
        }
        m.actor = try int("actor")
        m.target = try int("target")
        if let s = try str("pai") {
            if s == "?" { m.paiHidden = true }
            else if let t = tile(s) { m.pai = t }
            else { throw MjaiError(description: "bad pai \(s)") }
        }
        m.consumed = try known("consumed")
        m.tsumogiri = try bool("tsumogiri")
        if let v = o["tehais"], v != .null {
            guard let a = v.array else { throw MjaiError(description: "tehais is not an array") }
            var hs: [[Tile?]] = []
            for h in a { hs.append(try tileList(h, "tehais")) }
            m.tehais = hs
        }
        m.scores = try ints("scores")
        m.deltas = try ints("deltas")
        if let s = try str("bakaze") {
            guard let i = honorNames.firstIndex(of: s), i < 4 else { throw MjaiError(description: "bad bakaze") }
            m.bakaze = Wind(rawValue: i + 1)
        }
        m.kyoku = try int("kyoku")
        m.honba = try int("honba")
        m.kyotaku = try int("kyotaku")
        m.oya = try int("oya")
        m.doraMarker = try oneTile("dora_marker")
        // `uradora_markers` is the original mjai name.
        m.uraMarkers = try known("ura_markers")
        if m.uraMarkers == nil { m.uraMarkers = try known("uradora_markers") }
        m.wall = try known("wall")
        if let v = o["names"], v != .null {
            guard let a = v.array else { throw MjaiError(description: "names is not an array") }
            var names: [String] = []
            for x in a {
                guard let s = x.string else { throw MjaiError(description: "names holds a non-string") }
                names.append(s)
            }
            m.names = names
        }
        m.id = try int("id")
        m.reason = try str("reason")
        m.kyotakuLeft = try int("kyotaku_left")
        m.dealerRepeats = try bool("dealer_repeats")
        if let v = o["tenpais"], v != .null {
            guard let a = v.array else { throw MjaiError(description: "tenpais is not an array") }
            var out: [Bool] = []
            for x in a {
                guard let b = x.bool else { throw MjaiError(description: "tenpais holds a non-boolean") }
                out.append(b)
            }
            m.tenpais = out
        }
        m.horaTehais = try known("hora_tehais")
        if let v = o["yakus"], v != .null {
            guard let a = v.array else { throw MjaiError(description: "yakus is not an array") }
            var out: [YakuText] = []
            for x in a {
                guard let pair = x.array, pair.count == 2, let n = pair[0].string, let k = pair[1].int else {
                    throw MjaiError(description: "yakus holds an entry that is not [name, value]")
                }
                out.append(YakuText(n, k))
            }
            m.yakus = out
        }
        m.fu = try int("fu")
        m.fan = try int("fan")
        for s in [m.actor, m.target, m.oya, m.id].compactMap({ $0 }) where !(0..<4).contains(s) {
            throw MjaiError(description: "seat \(s) out of range")
        }
        return m
    }

    /// The action a logged event stands for, given what `seat` may do now
    /// (`legal`): `hora` is `tsumo` on the seat's own turn and `ron` otherwise,
    /// `ryukyoku` is nine terminals, `none` is `pass`. A `dahai` whose tsumogiri
    /// flag does not match but whose tile does is taken as the matching discard.
    /// Nil if the event names no action in `legal`. `offered` is the discard a call
    /// would take, when there is one: a call's `pai` and `target`, where given, must
    /// name it. For reading logs (`mj check-log`, which checks each win against the
    /// engine's own); a bot's reply goes through `action(_:for:)`, which checks it
    /// against the whole decision.
    public static func loggedAction(_ m: MjaiMessage, seat: Seat, legal: [Action],
                                    offered: (tile: Tile, from: Seat)? = nil) -> Action? {
        if let a = m.actor, a != seat.index, m.type != "none" { return nil }
        if ["pon", "chi", "daiminkan"].contains(m.type), let offered {
            if let p = m.pai, p != offered.tile { return nil }
            if let t = m.target, t != offered.from.index { return nil }
            if m.type == "daiminkan", let c = m.consumed {
                guard c.count == 3, c.allSatisfy({ $0.kind == offered.tile.kind }) else { return nil }
            }
        }
        let wanted: Action?
        switch m.type {
        case "none": wanted = .pass
        case "dahai":
            guard let t = m.pai else { return nil }
            let exact = Action.discard(t, tsumogiri: m.tsumogiri ?? false)
            if legal.contains(exact) { return exact }
            let other = Action.discard(t, tsumogiri: !(m.tsumogiri ?? false))
            wanted = legal.contains(other) ? other : exact
        case "reach": wanted = .riichi
        case "hora": wanted = legal.contains(.tsumo) ? .tsumo : .ron
        case "ryukyoku": wanted = .kyuushu
        case "ankan":
            guard let c = m.consumed, c.count == 4, let k = c.first?.kind, c.allSatisfy({ $0.kind == k }) else { return nil }
            wanted = .ankan(k)
        case "kakan":
            guard let t = m.pai else { return nil }
            wanted = .kakan(t)
        case "daiminkan": wanted = .daiminkan
        case "pon", "chi":
            guard let c = m.consumed?.sorted(), c.count == 2 else { return nil }
            wanted = m.type == "pon" ? .pon(c[0], c[1]) : .chi(c[0], c[1])
        default: return nil
        }
        guard let wanted, legal.contains(wanted) else { return nil }
        return wanted
    }

    /// The decision a bot's reply answers: which seat, what it may do, and what
    /// asked it (Codex final findings 1 and 5, Gemini final finding 3).
    public struct Decision: Sendable, Hashable {
        public enum Trigger: Sendable, Hashable {
            /// The seat's own turn, with its drawn tile (nil after a chi or pon).
            case turn(drawn: Tile?)
            /// Another seat's discard.
            case discard(tile: Tile, from: Seat)
            /// Another seat's announced kan, which only a ron may answer.
            case kan(tile: Tile, from: Seat, kind: KanKind)
        }
        public var seat: Seat
        public var legal: [Action]
        public var trigger: Trigger
        /// The seat's concealed tiles, its drawn tile included: a closed kan or an
        /// open kan must name the very tiles it uses.
        public var concealed: [Tile]
        /// The seat's pons, each sorted: an added kan's `consumed` must be one.
        public var pons: [[Tile]]

        public init(seat: Seat, legal: [Action], trigger: Trigger, concealed: [Tile] = [], pons: [[Tile]] = []) {
            self.seat = seat
            self.legal = legal
            self.trigger = trigger
            self.concealed = concealed
            self.pons = pons
        }

        /// The decision `view` asks for.
        public init(_ view: PlayerView) {
            let t = view.table
            let trigger: Trigger = switch t.reacting {
            case .discard(let d)?: .discard(tile: d.tile, from: d.seat)
            case .kan(let k)?: .kan(tile: k.tile, from: k.seat, kind: k.kind)
            case nil: .turn(drawn: t.drawn)
            }
            self.init(seat: view.seat, legal: view.legalActions, trigger: trigger,
                      concealed: t.hand + (t.drawn.map { [$0] } ?? []),
                      pons: t.melds[view.seat.index].filter { $0.kind == .pon }.map(\.tiles))
        }
    }

    /// The action a bot's reply asks for in `decision`, or nil if the reply does not
    /// fit it: a message type that cannot answer this trigger, another seat's
    /// `actor`, a `target` or `pai` that is not what was offered (a `hora`'s too:
    /// the discarder or kan seat and its tile, or the seat itself and its drawn
    /// tile), a kan's `consumed` that is not the tiles it would use, or an action
    /// not in `decision.legal`. `hora` is `tsumo` on the seat's turn and `ron`
    /// otherwise, `ryukyoku` is nine terminals, `none` is `pass`; a `dahai` whose
    /// tsumogiri flag is wrong but whose tile is right is the matching discard.
    /// Fields that mjai lets a bot leave out may be left out.
    public static func action(_ m: MjaiMessage, for decision: Decision) -> Action? {
        let seat = decision.seat, legal = decision.legal
        if m.type != "none", let a = m.actor, a != seat.index { return nil }
        func sameTiles(_ a: [Tile], _ b: [Tile]) -> Bool { a.sorted() == b.sorted() }
        let wanted: Action
        switch (m.type, decision.trigger) {
        case ("none", .discard), ("none", .kan):
            wanted = .pass
        case ("hora", .turn(let drawn)):
            if let t = m.target, t != seat.index { return nil }
            if let p = m.pai, p != drawn { return nil }
            wanted = .tsumo
        case ("hora", .discard(let tile, let from)):
            if let t = m.target, t != from.index { return nil }
            if let p = m.pai, p != tile { return nil }
            wanted = .ron
        case ("hora", .kan(let tile, let from, let kind)):
            if let t = m.target, t != from.index { return nil }
            // A closed kan's tile is any of its four: the kind must match.
            if let p = m.pai, kind == .closed ? p.kind != tile.kind : p != tile { return nil }
            wanted = .ron
        case ("dahai", .turn):
            guard let t = m.pai else { return nil }
            let exact = Action.discard(t, tsumogiri: m.tsumogiri ?? false)
            let other = Action.discard(t, tsumogiri: !(m.tsumogiri ?? false))
            wanted = legal.contains(exact) || !legal.contains(other) ? exact : other
        case ("reach", .turn): wanted = .riichi
        case ("ryukyoku", .turn): wanted = .kyuushu
        case ("ankan", .turn):
            guard let c = m.consumed, c.count == 4, let k = c.first?.kind, c.allSatisfy({ $0.kind == k }),
                  sameTiles(c, decision.concealed.filter { $0.kind == k }) else { return nil }
            wanted = .ankan(k)
        case ("kakan", .turn):
            guard let t = m.pai else { return nil }
            if let c = m.consumed, !decision.pons.contains(where: { $0[0].kind == t.kind && sameTiles($0, c) }) {
                return nil
            }
            wanted = .kakan(t)
        case ("pon", .discard(let tile, let from)), ("chi", .discard(let tile, let from)),
             ("daiminkan", .discard(let tile, let from)):
            if let p = m.pai, p != tile { return nil }
            if let t = m.target, t != from.index { return nil }
            if m.type == "daiminkan" {
                if let c = m.consumed, !(c.count == 3 && sameTiles(c, decision.concealed.filter { $0.kind == tile.kind })) {
                    return nil
                }
                wanted = .daiminkan
            } else {
                guard let c = m.consumed?.sorted(), c.count == 2 else { return nil }
                wanted = m.type == "pon" ? .pon(c[0], c[1]) : .chi(c[0], c[1])
            }
        default: return nil
        }
        return legal.contains(wanted) ? wanted : nil
    }

    /// A bot's reply for an action (the same JSON a bot would send), with every
    /// field mjai has for it (Gemini final finding 5): `target` is the discarder or
    /// kan seat of a ron or call, `tile` the drawn tile of a tsumo or the tile
    /// taken; `consumed` for an open kan and a closed kan come from the hand, so
    /// they are passed in (a closed kan defaults to four plain tiles).
    public static func reply(_ a: Action, seat: Seat, target: Seat? = nil, tile: Tile? = nil,
                             consumed: [Tile] = []) -> String {
        func r(_ type: String, _ f: [(String, JSONOut)] = []) -> String {
            JSONOut.object([("type", .string(type)), ("actor", .int(seat.index))] + f).text
        }
        let tgt: [(String, JSONOut)] = target.map { [("target", .int($0.index))] } ?? []
        let pai: [(String, JSONOut)] = tile.map { [("pai", .string(name($0)))] } ?? []
        switch a {
        case .pass: return JSONOut.object([("type", .string("none"))]).text
        case .discard(let t, let g): return r("dahai", [("pai", .string(name(t))), ("tsumogiri", .bool(g))])
        case .riichi: return r("reach")
        case .tsumo: return r("hora", [("target", .int(seat.index))] + pai)
        case .ron: return r("hora", tgt + pai)
        case .kyuushu: return r("ryukyoku")
        case .ankan(let k): return r("ankan", [("consumed", tiles(consumed.isEmpty ? Array(repeating: Tile(k), count: 4) : consumed))])
        case .kakan(let t): return r("kakan", [("pai", .string(name(t)))] + (consumed.isEmpty ? [] : [("consumed", tiles(consumed))]))
        case .daiminkan: return r("daiminkan", tgt + pai + [("consumed", tiles(consumed))])
        case .pon(let x, let y): return r("pon", tgt + pai + [("consumed", tiles([x, y]))])
        case .chi(let x, let y): return r("chi", tgt + pai + [("consumed", tiles([x, y]))])
        }
    }
}
