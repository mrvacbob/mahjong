// Self-play invariants that need the whole game (design §8 layer 4), and the
// coverage report of rare branches (layer 5).

import Riichi

/// Folding each seat's masked events rebuilds its view; results do not depend on
/// the order in which answers are supplied. Failures are collected, not thrown.
final class InvariantChecks: GameObserver {
    var folders = Seat.all.map(ViewFolder.init)
    var failures: [String] = []
    var steps = 0
    let label: String
    init(label: String) { self.label = label }

    func fail(_ s: String) { if failures.count < 20 { failures.append("\(label): \(s)") } }

    func step(_ game: GameState, events: [Event]) {
        steps += 1
        for seat in Seat.all {
            for e in events { folders[seat.index].apply(e.masked(for: seat)) }
            guard !game.isOver else { continue }
            let view = game.round.view(of: seat)
            if folders[seat.index].table != view.table {
                fail("step \(steps): seat \(seat)'s folded view differs from its PlayerView\n  folded \(folders[seat.index].table)\n  engine \(view.table)")
            }
            if view.legalActions != game.legalActions(for: seat) { fail("step \(steps): view's legal actions") }
        }
        // Points are conserved.
        if !game.isOver {
            let r = game.round
            if r.scores.reduce(0, +) + 1000 * r.sticks != 4 * game.rules.startingPoints {
                fail("step \(steps): points not conserved")
            }
        }
    }

    /// Answers set in ascending and in descending seat order resolve identically.
    func resolving(_ game: GameState, answers: Answers) {
        var reversed = Answers()
        for s in Seat.all.reversed() { reversed[s] = answers[s] }
        var a = game, b = game
        var ea: [Event] = [], eb: [Event] = []
        let ra = Result { () throws(RoundError) in try a.resolve(answers, events: &ea) }
        let rb = Result { () throws(RoundError) in try b.resolve(reversed, events: &eb) }
        if (try? ra.get()) == nil || (try? rb.get()) == nil || ea != eb || a.round.result != b.round.result {
            fail("answers in a different seat order resolve differently")
        }
    }
}

/// Counts of how often each rare branch was reached.
final class Coverage: GameObserver {
    var counts: [String: Int] = [:]
    func hit(_ k: String) { counts[k, default: 0] += 1 }

    static let required = [
        "abort_kyuushu", "abort_suufon_renda", "abort_suucha_riichi", "abort_suukaikan", "abort_sanchahou",
        "chankan", "robbed_closed_kan", "rinshan", "haitei", "houtei", "pao_tsumo", "pao_third_party_ron",
        "pao_liable_ron", "ron_x2", "ron_x3", "nagashi", "riichi_ankan", "four_kans_one_seat",
        "end_below_zero", "end_dealer_first", "end_target", "end_extension_over", "all_last_repeat",
        "all_last_advance",
    ]

    func deciding(_ game: GameState, seat: Seat, action: Action) {
        if case .ankan = action, game.round.riichiStatus(of: seat) == .accepted { hit("riichi_ankan") }
    }

    func event(_ e: Event, state: RoundState) {
        guard case .endKyoku = e, let r = state.result else { return }
        switch r.outcome {
        case .wins(let w):
            hit(w.count == 1 ? (w[0].isTsumo ? "tsumo" : "ron") : "ron_x\(w.count)")
            for win in w {
                if win.robbedKan == .closed { hit("robbed_closed_kan") }
                if let l = win.liable {
                    hit(win.isTsumo ? "pao_tsumo" : win.from == l ? "pao_liable_ron" : "pao_third_party_ron")
                }
                for y in win.scored.yaku {
                    if case .yaku(let n) = y.name, [.rinshan, .chankan, .haitei, .houtei, .ippatsu, .double_riichi,
                                                     .tenhou, .chiihou, .suukantsu].contains(n) {
                        hit(n.rawValue)
                    }
                }
                if case .yakuman = win.scored.value { hit("yakuman") }
            }
        case .exhaustiveDraw(_, let n):
            hit(n.isEmpty ? "exhaustive" : "nagashi")
        case .abortiveDraw(let a):
            hit("abort_\(a.rawValue)")
        }
        if Seat.all.contains(where: { s in state.melds(of: s).count(where: { $0.tiles.count == 4 }) == 4 }) {
            hit("four_kans_one_seat")
        }
    }

    func step(_ game: GameState, events: [Event]) {
        guard events.contains(.endKyoku), let (_, t) = game.lastRound else { return }
        switch t {
        case .ordinary: break
        case .allLastRepeat: hit("all_last_repeat")
        case .allLastAdvance: hit("all_last_advance")
        case .ends(let e): hit("end_\(e.rawValue)")
        }
    }

    var report: String {
        let missing = Self.required.filter { counts[$0] == nil }
        let body = counts.keys.sorted().map { "  \($0)=\(counts[$0]!)" }.joined(separator: "\n")
        return "coverage:\n\(body)\n  not reached: \(missing.isEmpty ? "-" : missing.joined(separator: " "))"
    }
}
