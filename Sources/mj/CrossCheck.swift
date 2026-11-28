// The Mercury cross-check dump (design §8 layer 3): every decision as a `legal`
// line request and every win as a `score` request, each with the answer the round
// engine gives, so that `./mj`, `Sources/Mercury/mj` and the round can be
// compared (`mj crosscheck`).

import Riichi

final class RequestDump: GameObserver {
    var requests: [String] = []
    var expected: [String] = []
    /// Requests where the seat has under 1,000 points (riichi differs by design).
    var lowPoints: [String] = []
    var next = 0
    let prefix: String

    init(prefix: String) { self.prefix = prefix }

    static func meldText(_ m: Meld) -> String { "\(m.kind.rawValue)\(mpsz(m.tiles))" }
    static func windLetter(_ w: Wind) -> String { ["E", "S", "W", "N"][w.rawValue - 1] }

    func add(_ request: String, _ answer: String) {
        next += 1
        requests.append("\(prefix)\(next) \(request)")
        expected.append("\(prefix)\(next) \(answer)")
    }

    func deciding(_ game: GameState, seat: Seat, action: Action) {
        let s = game.round
        if action == .tsumo, let req = s.winRequest(for: seat) { addScore(req) }
        guard let req = legalRequest(s, seat) else { return }
        add(req, "actions=\(expectedActions(s, seat).joined(separator: ","))")
        // `legal` assumes enough points for riichi; the round does not.
        if s.scores[seat.index] < 1000 { lowPoints.append("\(prefix)\(next)") }
    }

    /// A ron's honba depend on every answer (Gemini final finding 2), so its
    /// request is made with all of them.
    func resolving(_ game: GameState, answers: Answers) {
        for seat in game.seatsToAnswer where answers[seat] == .ron {
            if let req = game.round.winRequest(for: seat, answers: answers) { addScore(req) }
        }
    }

    func addScore(_ r: ScoreRequest) {
        let flags = r.context.flags.map(\.rawValue).sorted()
        var q = "score hand=\(mpsz(r.hand)) melds=\(r.melds.isEmpty ? "-" : r.melds.map(Self.meldText).joined(separator: ","))"
        q += " win=\(r.win) seat=\(Self.windLetter(r.context.seat)) round=\(Self.windLetter(r.context.round))"
        q += " by=\(r.context.tsumo ? "tsumo" : "ron") flags=\(flags.isEmpty ? "-" : flags.joined(separator: ","))"
        q += " dora=\(r.dora.isEmpty ? "-" : mpsz(r.dora)) ura=\(r.ura.isEmpty ? "-" : mpsz(r.ura)) honba=\(r.honba)"
        let answer: String
        do { answer = try score(r, rules: .mahjongSoul).text } catch { answer = "error=\(error.rawValue)" }
        add(q, answer)
    }

    /// The `legal` question for this decision, or nil if the line protocol cannot
    /// ask it (the riichi discard, which `legal` folds into `riichi:<tile>`).
    func legalRequest(_ s: RoundState, _ seat: Seat) -> String? {
        let melds = s.melds(of: seat).map(\.meld)
        var q = "legal hand=\(mpsz(s.hand(of: seat))) melds=\(melds.isEmpty ? "-" : melds.map(Self.meldText).joined(separator: ","))"
        var flags: [String] = []
        let first = !s.anyCallMade && s.pond(of: seat).isEmpty
        switch s.phase {
        case .turn(_, let start):
            switch start {
            case .riichiDeclared: return nil
            case .call:
                let m = s.melds(of: seat).last!
                q += " called=\(Self.meldText(m.meld)) took=\(m.taken!)"
            case .draw, .replacementDraw:
                q += " draw=\(s.drawnTile(of: seat)!)"
                if start == .replacementDraw { flags.append("rinshan") }
                if start == .draw && s.liveTilesLeft == 0 { flags.append("haitei") }
                if start == .draw && first { flags.append(seat == s.dealer ? "tenhou" : "chiihou") }
            }
        case .reactions(let d):
            q += " discard=\(d.tile) from=\(relation(seat, d.seat))"
            if s.liveTilesLeft == 0 { flags.append("houtei") }
        case .robbing(let k):
            q += " discard=\(k.tile) from=\(relation(seat, k.seat))"
            flags.append(k.kind == .added ? "chankan" : "ankan_rob")
        case .ended:
            return nil
        }
        q += " seat=\(Self.windLetter(seat.wind(dealer: s.dealer))) round=\(Self.windLetter(s.roundWind))"
        q += " flags=\(flags.isEmpty ? "-" : flags.sorted().joined(separator: ","))"
        q += " riichi=\(s.riichiStatus(of: seat) == .accepted ? 1 : 0) furiten=\(s.isFuriten(seat) ? 1 : 0)"
        q += " wall=\(s.liveTilesLeft) first=\(first ? 1 : 0) kans=\(s.kanCount)"
        return q
    }

    func relation(_ me: Seat, _ other: Seat) -> String {
        switch other.distance(from: me) {
        case 3: "kamicha"
        case 2: "toimen"
        default: "shimocha"
        }
    }

    /// The round's legal actions in the `legal` operation's terms.
    func expectedActions(_ s: RoundState, _ seat: Seat) -> [String] {
        var out: Set<String> = []
        for a in s.legalActions(for: seat) {
            switch a {
            case .discard(let t, _): out.insert("discard:\(t)")
            case .riichi:
                if let (after, _) = try? s.applying(.riichi, by: seat) {
                    for b in after.legalActions(for: seat) {
                        if case .discard(let t, _) = b { out.insert("riichi:\(t)") }
                    }
                }
            case .tsumo: out.insert("tsumo")
            case .ankan(let k): out.insert("ankan:\(k)")
            case .kakan(let t): out.insert("kakan:\(t)")
            case .kyuushu: out.insert("kyuushu")
            case .ron: out.insert("ron")
            case .pon(let x, let y): out.insert("pon:\(mpsz([x, y]))")
            case .chi(let x, let y): out.insert("chi:\(mpsz([x, y]))")
            case .daiminkan:
                if case .reactions(let d) = s.phase { out.insert("kan:\(d.tile.kind)") }
            case .pass: out.insert("pass")
            }
        }
        return out.sorted()
    }
}
