// The game driver: asks each seat that must act, steps the `GameState`, and
// writes the mjai log and the engine trace (design §6–§7).

import Riichi
import RiichiMjai

/// Observes the game as it runs, for the dumps and checks.
protocol GameObserver: AnyObject {
    /// The state as of each event, as it is emitted (start_game excluded).
    func event(_ e: Event, state: RoundState)
    /// After every step (and once after the start): the game as it rests, and the
    /// events of the step.
    func step(_ game: GameState, events: [Event])
    /// Just before a decision is applied (the game still shows the choice).
    func deciding(_ game: GameState, seat: Seat, action: Action)
    /// Just before a window is resolved with these answers.
    func resolving(_ game: GameState, answers: Answers)
}

extension GameObserver {
    func event(_ e: Event, state: RoundState) {}
    func step(_ game: GameState, events: [Event]) {}
    func deciding(_ game: GameState, seat: Seat, action: Action) {}
    func resolving(_ game: GameState, answers: Answers) {}
}

/// Collects the unmasked mjai log, one JSON line per event.
final class LogWriter: GameObserver {
    var lines: [String] = []
    let names: [String]
    init(names: [String]) { self.names = names }

    func addStartGame() { lines.append(Mjai.encode(Event.startGame, Mjai.Extras(names: names))) }

    func event(_ e: Event, state: RoundState) {
        var x = Mjai.Extras()
        switch e {
        case .startKyoku: x.wall = state.wall
        case .endKyoku: x.result = state.result
        default: break
        }
        lines.append(Mjai.encode(e, x))
    }

    var text: String { lines.map { $0 + "\n" }.joined() }
}

struct GameRecord {
    var game: GameState
    var log: String
    /// The trace: header lines, then one `seat action` line per decision.
    var trace: String
    var substitutions: Substitutions
    var decisions: Int
}

enum DriverError: Error, CustomStringConvertible {
    case illegal(String)
    case trace(String)
    var description: String {
        switch self {
        case .illegal(let s): "illegal decision: \(s)"
        case .trace(let s): "trace: \(s)"
        }
    }
}

func rulesetName(_ r: Rules) -> String { r == .tenhou ? "tenhou" : "mahjongsoul" }

/// Plays one game to the end with these players.
func playGame(rules: Rules, seed: UInt64, players: inout [any Player], names: [String],
              observers: [any GameObserver], botsLabel: String) throws -> GameRecord {
    let log = LogWriter(names: names)
    let all: [any GameObserver] = [log] + observers
    let observe: (RoundState, Event) -> Void = { s, e in for o in all { o.event(e, state: s) } }
    var events: [Event] = []
    log.addStartGame()
    var game = GameState(rules: rules, seed: seed, events: &events, observe: observe)
    var trace = "mj-trace 1\nrules \(rulesetName(rules))\nseed \(seed)\nbots \(botsLabel)\n"
    var decisions = 0

    func deliver(_ events: [Event], _ game: GameState) -> [Action?] {
        for o in all { o.step(game, events: events) }
        var out: [Action?] = [nil, nil, nil, nil]
        for seat in Seat.all {
            let masked = events.map { $0.masked(for: seat) }
            let legal = game.legalActions(for: seat)
            let view = legal.isEmpty ? nil : game.round.view(of: seat)
            out[seat.index] = players[seat.index].receive(masked, view: view)
        }
        return out
    }

    var pending = deliver(events, game)
    while !game.isOver {
        events = []
        if case .turn(let seat, _) = game.phase {
            guard let a = pending[seat.index] else { throw DriverError.illegal("seat \(seat) gave no decision") }
            for o in all { o.deciding(game, seat: seat, action: a) }
            trace += "\(seat) \(a)\n"
            decisions += 1
            do { try game.apply(a, by: seat, events: &events, observe: observe) }
            catch { throw DriverError.illegal("seat \(seat) \(a): \(error)") }
        } else {
            var answers = Answers()
            for seat in game.seatsToAnswer {
                guard let a = pending[seat.index] else { throw DriverError.illegal("seat \(seat) gave no answer") }
                for o in all { o.deciding(game, seat: seat, action: a) }
                answers[seat] = a
                trace += "\(seat) \(a)\n"
                decisions += 1
            }
            for o in all { o.resolving(game, answers: answers) }
            do { try game.resolve(answers, events: &events, observe: observe) }
            catch { throw DriverError.illegal("window: \(error)") }
        }
        pending = deliver(events, game)
    }
    var subs = Substitutions()
    for i in 0..<4 {
        players[i].finish()
        subs = subs + players[i].substitutions
    }
    return GameRecord(game: game, log: log.text, trace: trace, substitutions: subs, decisions: decisions)
}

/// Parses a trace written by `playGame`.
func parseTrace(_ text: String) throws -> (rules: Rules, seed: UInt64, bots: String, decisions: [(Seat, Action)]) {
    var rules: Rules?, seed: UInt64?, bots = ""
    var decisions: [(Seat, Action)] = []
    for (n, line) in text.split(separator: "\n").enumerated() {
        let parts = line.split(separator: " ")
        guard parts.count == 2 else { throw DriverError.trace("line \(n + 1): \(line)") }
        switch parts[0] {
        case "mj-trace": guard parts[1] == "1" else { throw DriverError.trace("unknown version \(parts[1])") }
        case "rules": rules = parts[1] == "tenhou" ? .tenhou : .mahjongSoul
        case "seed": seed = UInt64(parts[1])
        case "bots": bots = String(parts[1])
        default:
            guard let s = Int(parts[0]), (0..<4).contains(s), let a = Action(parts[1]) else {
                throw DriverError.trace("line \(n + 1): \(line)")
            }
            decisions.append((Seat(s), a))
        }
    }
    guard let rules, let seed else { throw DriverError.trace("missing rules or seed") }
    return (rules, seed, bots, decisions)
}
