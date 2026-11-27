let suits = Array("mpsz")
let kinds = 0..<34
let orphans = kinds.filter(isOutside)

func isTerminal(_ kind: Int) -> Bool {
    kind < 27 && (kind % 9 == 0 || kind % 9 == 8)
}

func isOutside(_ kind: Int) -> Bool { kind >= 27 || isTerminal(kind) }

struct Tile: Hashable {
    let kind: Int
    var red = false

    var text: String { formatTiles([self]) }
}

enum InputError: Error { case malformed }

func parseTiles(_ text: Substring) throws -> [Tile] {
    if text == "-" { return [] }
    var tiles: [Tile] = []
    var digits: [Int] = []
    for character in text {
        if let digit = character.wholeNumberValue, digit <= 9 {
            digits.append(digit)
        } else {
            guard let suit = suits.firstIndex(of: character), !digits.isEmpty else {
                throw InputError.malformed
            }
            for digit in digits {
                guard suit != 3 || (1...7).contains(digit) else { throw InputError.malformed }
                tiles.append(Tile(kind: suit * 9 + (digit == 0 ? 4 : digit - 1), red: digit == 0))
            }
            digits.removeAll(keepingCapacity: true)
        }
    }
    guard !tiles.isEmpty, digits.isEmpty else { throw InputError.malformed }
    return tiles
}

func formatTiles(_ tiles: [Tile]) -> String {
    let ordered = tiles.sorted { ($0.kind, !$0.red ? 1 : 0) < ($1.kind, !$1.red ? 1 : 0) }
    guard let first = ordered.first else { return "-" }
    var result = ""
    var suit = first.kind / 9
    for tile in ordered {
        if tile.kind / 9 != suit {
            result.append(suits[suit])
            suit = tile.kind / 9
        }
        result += String(tile.red ? 0 : tile.kind % 9 + 1)
    }
    result.append(suits[suit])
    return result
}

func counts(_ tiles: [Tile]) -> [Int] {
    var result = Array(repeating: 0, count: 34)
    for tile in tiles { result[tile.kind] += 1 }
    return result
}

enum GroupType: Int { case pair, sequence, triplet, kan }

struct Group {
    let kind: Int
    let type: GroupType
    var open = false

    var kinds: [Int] {
        switch type {
        case .pair: [kind, kind]
        case .sequence: [kind, kind + 1, kind + 2]
        case .triplet: [kind, kind, kind]
        case .kan: [kind, kind, kind, kind]
        }
    }
}

enum MeldType: Character {
    case chi = "c", pon = "p", openKan = "k", addedKan = "s", closedKan = "a"
}

struct Meld {
    let type: MeldType
    let tiles: [Tile]

    var group: Group {
        let kind = tiles.map(\.kind).min()!
        switch type {
        case .chi: return Group(kind: kind, type: .sequence, open: true)
        case .pon: return Group(kind: kind, type: .triplet, open: true)
        case .openKan, .addedKan, .closedKan:
            return Group(kind: kind, type: .kan, open: type != .closedKan)
        }
    }
}

func parseMeld(_ text: Substring) throws -> Meld {
    guard let first = text.first, let type = MeldType(rawValue: first) else {
        throw InputError.malformed
    }
    let tiles = try parseTiles(text.dropFirst())
    let sorted = tiles.map(\.kind).sorted()
    guard let start = sorted.first else { throw InputError.malformed }
    switch type {
    case .chi:
        guard start < 27, start % 9 <= 6, sorted == [start, start + 1, start + 2] else {
            throw InputError.malformed
        }
    case .pon, .openKan, .addedKan, .closedKan:
        guard sorted.count == (type == .pon ? 3 : 4), sorted.allSatisfy({ $0 == start }) else {
            throw InputError.malformed
        }
    }
    return Meld(type: type, tiles: tiles)
}

struct Hand {
    let tiles: [Tile]
    let melds: [Meld]

    var closed: Bool { melds.allSatisfy { $0.type == .closedKan } }
    var allTiles: [Tile] { tiles + melds.flatMap(\.tiles) }
}
