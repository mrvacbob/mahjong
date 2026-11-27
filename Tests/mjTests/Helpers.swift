// Wall and tile helpers for the driver tests (as in Tests/RiichiTests).

import Foundation
import Riichi
@testable import mj

func t(_ text: String) -> [Tile] { parseTiles(Substring(text))! }
func t1(_ text: String) -> Tile { Tile(Substring(text))! }

/// A wall with these hands (seat 0 deals), live draws, replacement tiles and
/// indicators; every other slot from the unused tiles in canonical order.
func makeWall(hands: [String], draws: String = "", rinshan: String = "", dora: String = "") -> Wall {
    var pool = Wall.sorted
    func take(_ x: Tile) -> Tile { pool.remove(at: pool.firstIndex(of: x)!) }
    var slots = [Tile?](repeating: nil, count: 136)
    let hs = hands.map { t($0) }
    var cursor = [0, 0, 0, 0], w = 0
    for round in 0..<4 {
        for s in 0..<4 {
            for _ in 0..<(round < 3 ? 4 : 1) { slots[w] = take(hs[s][cursor[s]]); cursor[s] += 1; w += 1 }
        }
    }
    for (i, x) in t(draws).enumerated() { slots[52 + i] = take(x) }
    for (i, x) in t(rinshan).enumerated() { slots[122 + i] = take(x) }
    for (i, x) in t(dora).enumerated() { slots[126 + i] = take(x) }
    var rest = pool.makeIterator()
    return Wall(tiles: slots.map { $0 ?? rest.next()! })!
}

/// Plays a script: each decision takes the next scripted action if it is legal,
/// else passes in a window; once the script is used up it plays eager.
struct ScriptedPlayer: Player {
    var script: [Action]
    var eager = BuiltinBot(kind: .eager, rng: BotRNG(state: 1))
    var refused: [String] = []

    mutating func decision(_ view: PlayerView) -> Action? {
        if let next = script.first {
            if view.legalActions.contains(next) { script.removeFirst(); return next }
            if view.legalActions.contains(.pass) { return .pass }
            refused.append("\(next) not in \(view.legalActions)")
        }
        return eager.eager(view)
    }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
func fixture(_ name: String) -> String { root.appendingPathComponent("Tests/Fixtures/\(name)").path }
