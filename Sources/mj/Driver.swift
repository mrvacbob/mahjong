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

/// The preset a ruleset is (or is with `length = .east`), by its trace name.
func rulesetName(_ r: Rules) -> String {
    var base = r
    base.length = .south
    return base == .tenhou ? "tenhou" : "mahjongsoul"
}

/// Whether a version 1 trace can record `r`: a preset, or a preset played East
/// only (the trace's optional `length east` line).
func isRecordable(_ r: Rules) -> Bool {
    var base = r
    base.length = .south
    return base == .tenhou || base == .mahjongSoul
}

/// A game from a given position on given walls (tests). Its trace records
/// neither, so it cannot be replayed from the trace.
struct GameStart {
    var position: GamePosition
    var walls: @Sendable (_ seed: UInt64, _ hand: Int) -> Wall
}

/// Plays one game to the end with these players.
func playGame(rules: Rules, seed: UInt64, players: inout [any Player], names: [String],
              observers: [any GameObserver], botsLabel: String, scenario: Scenario? = nil,
              start: GameStart? = nil) throws -> GameRecord {
    // A version 1 trace names a preset only (Codex C/D finding 6), and the length.
    guard isRecordable(rules) else {
        throw DriverError.trace("only the two preset rulesets (hanchan or East only) can be recorded in a trace")
    }
    let log = LogWriter(names: names)
    let all: [any GameObserver] = [log] + observers
    let observe: (RoundState, Event) -> Void = { s, e in for o in all { o.event(e, state: s) } }
    var events: [Event] = []
    log.addStartGame()
    var game: GameState
    if let scenario {
        game = try GameState(rules: rules, seed: seed, position: scenario.position(seed: seed),
                             walls: { scenario.wall(seed: $0, hand: $1) }, events: &events, observe: observe)
    } else if let start {
        game = try GameState(rules: rules, seed: seed, position: start.position, walls: start.walls,
                             events: &events, observe: observe)
    } else {
        game = try GameState(rules: rules, seed: seed, events: &events, observe: observe)
    }
    var trace = "mj-trace 1\nrules \(rulesetName(rules))\nseed \(seed)\nbots \(botsLabel)\n"
    if rules.length == .east { trace += "length east\n" }
    if let scenario { trace += "scenario \(scenario.rawValue)\n" }
    var decisions = 0

    /// Each seat is given the step's events one at a time (so where the engine
    /// paused does not show, Codex C/D finding 1), its view with the event that
    /// asks it to decide, and then asked for the decision: the decision is bound to
    /// that event (Codex final finding 1).
    func deliver(_ events: [Event], _ game: GameState) throws -> [Action?] {
        for o in all { o.step(game, events: events) }
        var out: [Action?] = [nil, nil, nil, nil]
        for seat in Seat.all {
            let masked = events.map { $0.masked(for: seat) }
            let view = game.legalActions(for: seat).isEmpty ? nil : game.view(of: seat)
            var prompt: Int?
            if let view {
                prompt = view.prompt(in: masked)
                guard prompt != nil else {
                    throw DriverError.illegal("internal: seat \(seat)'s decision has no prompt among \(masked)")
                }
            }
            for (i, m) in masked.enumerated() {
                players[seat.index].receive(m, prompt: i == prompt ? view : nil)
            }
            if let view { out[seat.index] = players[seat.index].decision(view) }
        }
        return out
    }

    var pending = try deliver(events, game)
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
        pending = try deliver(events, game)
    }
    var subs = Substitutions()
    for i in 0..<4 {
        players[i].finish()
        subs = subs + players[i].substitutions
    }
    return GameRecord(game: game, log: log.text, trace: trace, substitutions: subs, decisions: decisions)
}

/// Parses a trace written by `playGame`.
func parseTrace(_ text: String) throws -> (rules: Rules, seed: UInt64, bots: String, scenario: Scenario?,
                                          decisions: [(Seat, Action)]) {
    var rules: Rules?, seed: UInt64?, bots = ""
    var length = GameLength.south
    var scenario: Scenario?
    var decisions: [(Seat, Action)] = []
    for (n, line) in text.split(separator: "\n").enumerated() {
        let parts = line.split(separator: " ")
        guard parts.count == 2 else { throw DriverError.trace("line \(n + 1): \(line)") }
        switch parts[0] {
        case "mj-trace": guard parts[1] == "1" else { throw DriverError.trace("unknown version \(parts[1])") }
        case "rules": rules = parts[1] == "tenhou" ? .tenhou : .mahjongSoul
        case "length":
            guard parts[1] == "east" else { throw DriverError.trace("unknown length \(parts[1])") }
            length = .east
        case "seed": seed = UInt64(parts[1])
        case "bots": bots = String(parts[1])
        case "scenario":
            guard let sc = Scenario(rawValue: String(parts[1])) else { throw DriverError.trace("unknown scenario \(parts[1])") }
            scenario = sc
        default:
            guard let s = Int(parts[0]), (0..<4).contains(s), let a = Action(parts[1]) else {
                throw DriverError.trace("line \(n + 1): \(line)")
            }
            decisions.append((Seat(s), a))
        }
    }
    guard var rules, let seed else { throw DriverError.trace("missing rules or seed") }
    rules.length = length
    return (rules, seed, bots, scenario, decisions)
}
