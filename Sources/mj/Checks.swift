// Whole-game self-play invariants and rare-branch coverage (Docs/Design/engine.md §8).

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
            // Also checked at game end (final scores, leftover sticks paid out).
            let view = game.view(of: seat)
            if folders[seat.index].table(asked: !view.legalActions.isEmpty) != view.table {
                fail("step \(steps): seat \(seat)'s folded view differs from its PlayerView\n  folded \(folders[seat.index].table)\n  engine \(view.table)")
            }
        }
        // Every action offered is accepted (on a copy): the turn seat's by `apply`,
        // each window answer by `resolve` with the other seats passing.
        if case .turn(let s, _) = game.phase {
            for a in game.legalActions(for: s) {
                var copy = game
                if (try? copy.apply(a, by: s)) == nil { fail("step \(steps): seat \(s)'s offered \(a) refused") }
            }
        } else if !game.isOver {
            for s in game.seatsToAnswer {
                for a in game.legalActions(for: s) {
                    var answers = Answers()
                    for o in game.seatsToAnswer { answers[o] = .pass }
                    answers[s] = a
                    var copy = game
                    if (try? copy.resolve(answers)) == nil { fail("step \(steps): seat \(s)'s offered \(a) refused") }
                }
            }
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
    /// Finer game-flow branches (Docs/Design/engine.md §5), reported alongside.
    static let flow = [
        "all_last_repeat_abort", "all_last_repeat_not_first", "all_last_repeat_below_target",
        "all_last_repeat_other_at_target", "all_last_advance_into_extension", "all_last_advance_in_extension",
        "end_target_in_extension", "end_below_zero_all_last", "end_sticks_left", "end_rank_tie",
        "zero_points_continue", "abort_suufon_renda_riichi", "nagashi_all_last",
    ]
    var start: (wind: Wind, kyoku: Int)?
    /// The position of the hand that ended last (the step that ends a hand also
    /// deals the next one).
    var ended: (wind: Wind, kyoku: Int)?
    var riichiDiscard = false
    var lastDahaiRiichi = false

    func deciding(_ game: GameState, seat: Seat, action: Action) {
        if case .ankan = action, game.round.riichiStatus(of: seat) == .accepted { hit("riichi_ankan") }
    }

    func event(_ e: Event, state: RoundState) {
        switch e {
        case .startKyoku(let b, let k, _, _, _, _, _, _): start = (b, k); riichiDiscard = false
        case .reach: riichiDiscard = true
        case .dahai: lastDahaiRiichi = riichiDiscard; riichiDiscard = false
        case .ryukyoku(.abort(.suufonRenda), _, _, _, _): if lastDahaiRiichi { hit("abort_suufon_renda_riichi") }
        default: break
        }
        guard case .endKyoku = e, let r = state.result else { return }
        ended = start
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
        guard events.contains(.endKyoku), let (r, t) = game.lastRound, let start = ended else { return }
        let rules = game.rules
        let last: Wind = rules.length == .east ? .east : .south
        let inExtension = start.wind.rawValue > last.rawValue
        let dealer = Seat(start.kyoku - 1)
        let allLast = inExtension || (start.wind == last && start.kyoku == 4)
        if allLast, case .exhaustiveDraw(_, let n) = r.outcome, !n.isEmpty { hit("nagashi_all_last") }
        switch t {
        case .ordinary: break
        case .allLastRepeat:
            hit("all_last_repeat")
            if case .abortiveDraw = r.outcome { hit("all_last_repeat_abort") }
            else if (try? GameFlow.ranking(r.scores))?.first != dealer { hit("all_last_repeat_not_first") }
            else if r.scores[dealer.index] < rules.targetPoints { hit("all_last_repeat_below_target") }
            if case .abortiveDraw = r.outcome {} else if Seat.all.contains(where: { $0 != dealer && r.scores[$0.index] >= rules.targetPoints }) {
                hit("all_last_repeat_other_at_target")
            }
        case .allLastAdvance:
            hit("all_last_advance")
            hit(inExtension ? "all_last_advance_in_extension" : "all_last_advance_into_extension")
        case .ends(let e):
            hit("end_\(e.rawValue)")
            if e == .target && inExtension { hit("end_target_in_extension") }
            if e == .belowZero && allLast { hit("end_below_zero_all_last") }
            if let g = game.result {
                if g.sticksAwarded > 0 { hit("end_sticks_left") }
                if Set(g.scores).count < 4 { hit("end_rank_tie") }
            }
        }
        if !game.isOver && r.scores.contains(0) { hit("zero_points_continue") }
    }

    var report: String {
        let missing = (Self.required + Self.flow).filter { counts[$0] == nil }
        let body = counts.keys.sorted().map { "  \($0)=\(counts[$0]!)" }.joined(separator: "\n")
        return "coverage:\n\(body)\n  not reached: \(missing.isEmpty ? "-" : missing.joined(separator: " "))"
    }
}
