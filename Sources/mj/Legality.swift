// Legality rows for agpl/libriichi-check/compare.py: for every event of every hand,
// from start_kyoku through end_kyoku, and for all four seats, what the seat may do
// and its waits, shanten and furiten, as the engine has them (README "Legality
// JSONL").

import Riichi
import RiichiMjai

final class LegalityRows: GameObserver {
    /// The path string the checker is given for this game's log.
    let file: String
    var out: [String] = []

    struct Status {
        var shanten: Int, waits: [Kind], furiten: Bool
        /// Diagnostics, ignored by compare.py: which furiten (o = own discard,
        /// t = temporary, r = riichi).
        var parts: String
        /// The concealed tiles (drawn tile included), mpsz.
        var hand: String
    }
    struct Pending {
        var type: String, actor: Seat?, status: [Status]
    }
    var hand = 0
    var index = 0
    var inHand = false
    /// The rows of the current step, flags still to come.
    var pending: [(hand: Int, index: Int, row: Pending)] = []

    init(file: String) { self.file = file }

    static func status(_ s: RoundState, _ seat: Seat) -> Status {
        var tiles = s.hand(of: seat)
        if let d = s.drawnTile(of: seat) { tiles.append(d) }
        let sh = shanten(Counts(tiles), meldCount: s.melds(of: seat).count).min
        let f = s.furitenParts(of: seat)
        let parts = (f.ownDiscard ? "o" : "") + (f.temporary ? "t" : "") + (f.riichi ? "r" : "")
        return Status(shanten: sh, waits: s.waits(of: seat), furiten: s.isFuriten(seat), parts: parts,
                      hand: mpsz(tiles.sorted()))
    }

    func event(_ e: Event, state: RoundState) {
        switch e {
        case .startGame, .endGame: return
        case .startKyoku:
            hand += 1
            index = 0
            inHand = true
        default:
            guard inHand else { return }
        }
        pending.append((hand, index, Pending(type: e.type, actor: e.actor,
                                              status: Seat.all.map { Self.status(state, $0) })))
        index += 1
        if case .endKyoku = e { inHand = false }
    }

    /// The step is over: the last event's rows get the flags of the seats that must
    /// decide now; every earlier event of the step had nobody to decide.
    func step(_ game: GameState, events: [Event]) {
        for (n, p) in pending.enumerated() {
            let last = n == pending.count - 1 && !game.isOver && p.row.type != "end_kyoku"
            for seat in Seat.all {
                let legal = last ? game.legalActions(for: seat) : []
                out.append(row(p.row, hand: pending[n].hand, index: pending[n].index, seat: seat, legal: legal,
                               reactingTo: game.phase))
            }
        }
        pending = []
    }

    func row(_ p: Pending, hand: Int, index: Int, seat: Seat, legal: [Action], reactingTo phase: Phase) -> String {
        var f: [String: Bool] = [:]
        for k in ["can_discard", "can_chi_low", "can_chi_mid", "can_chi_high", "can_pon", "can_daiminkan",
                  "can_kakan", "can_ankan", "can_riichi", "can_tsumo_agari", "can_ron_agari", "can_ryukyoku"] {
            f[k] = false
        }
        var discards: [String] = [], ankan: [String] = [], kakan: [String] = []
        var called: Kind?
        if case .reactions(let d) = phase { called = d.tile.kind }
        for a in legal {
            switch a {
            case .discard(let t, _):
                f["can_discard"] = true
                let n = Mjai.name(t)
                if !discards.contains(n) { discards.append(n) }
            case .chi(let x, let y):
                guard let c = called else { break }
                if c < x.kind && c < y.kind { f["can_chi_low"] = true }
                else if c > x.kind && c > y.kind { f["can_chi_high"] = true }
                else { f["can_chi_mid"] = true }
            case .pon: f["can_pon"] = true
            case .daiminkan: f["can_daiminkan"] = true
            case .kakan(let t):
                f["can_kakan"] = true
                let n = Mjai.name(t.kind)
                if !kakan.contains(n) { kakan.append(n) }
            case .ankan(let k):
                f["can_ankan"] = true
                ankan.append(Mjai.name(k))
            case .riichi: f["can_riichi"] = true
            case .tsumo: f["can_tsumo_agari"] = true
            case .ron: f["can_ron_agari"] = true
            case .kyuushu: f["can_ryukyoku"] = true
            case .pass: break
            }
        }
        let st = p.status[seat.index]
        let flagsOut: [(String, JSONOut)] = f.keys.sorted().map { ($0, .bool(f[$0]!)) }
            + [("target_actor", .int((p.actor ?? seat).index))]
        let names = { (xs: [String]) in JSONOut.array(xs.map { .string($0) }) }
        return JSONOut.object([
            ("file", .string(file)), ("hand", .int(hand)), ("event_index", .int(index)),
            ("seat", .int(seat.index)), ("event_type", .string(p.type)), ("flags", .object(flagsOut)),
            ("discard", names(discards)), ("ankan", names(ankan)), ("kakan", names(kakan)),
            ("waits", names(st.waits.map { Mjai.name($0) })), ("shanten", .int(st.shanten)),
            ("furiten", .bool(st.furiten)), ("x_furiten", .string(st.parts)),
            ("x_hand", .string(st.hand)),
        ]).text
    }

    var text: String { out.map { $0 + "\n" }.joined() }
}
