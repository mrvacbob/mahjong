//
//  GameState.swift
//  swift_mahjong
//
//  Created by Alex Strange on 10/22/17.
//  Copyright © 2017 Alex Strange. All rights reserved.
//

import Darwin.C.stdlib

enum Tile {
    enum NumberedTile { case one,two,three,four,five,six,seven,eight,nine }
    enum DragonTile { case haku,hatsu,chun }
    
    case Man(NumberedTile)
    case Pin(NumberedTile)
    case Sou(NumberedTile)
    case Wind(Wind)
    case Dragon(DragonTile)
}

enum Wind {
    case east,south,west,north
}

enum RelativeSeat {
    // Left, Across, Right
    case kamicha,toimen,shimocha
}

enum Meld {
    case SingleTile(Tile)
    case Pair(Tile)
    case Chi(Tile, Tile, Tile)
    case Pon(RelativeSeat, Tile)
    case OpenKan(RelativeSeat, Tile)
    case ClosedKan(RelativeSeat, Tile)
}

struct Player {
    fileprivate(set) var hand : [Tile] = []
    fileprivate(set) var openTiles : [Meld] = []
    fileprivate(set) var discards : [Tile] = []
    
    fileprivate(set) var drawnTile : Tile?
    
    fileprivate(set) var score : Int = 25000
    fileprivate(set) var riichi : Bool = false
    
    fileprivate init() {
        hand.reserveCapacity(13)
    }
}

public struct MahjongGame {
    // The wall (undrawn tiles)
    private var wall : [Tile] = allTiles.shuffled()

    // Dora indicators
    private(set) var doraIndicators : [Tile] = []

    // Players' tiles
    private(set) var players : [Player] = Array(repeating: Player(), count: 4)
    private(set) var dealerPlayer : Int = 0

    // Points in the middle, and bonus counters
    private(set) var extraPoints : Int = 0
    private(set) var bonusCounter : Int = 0
    
    // Wind of the round (east/south)
    private(set) var roundWind : Wind = .east
    
    public init() {
        // Draw dora
        doraIndicators.append(draw())
        
        // Draw for each player
        for player in 0...3 {
            for _ in 1...13 {
                players[player].hand.append(draw())
            }
            
            players[player].hand.sort()
        }
        
        // Draw 14th tile
        players[dealerPlayer].drawnTile = draw()
    }
    
    private mutating func draw() -> Tile {
        return wall.popLast()!
    }
    
    public func printBoard() {
        print("Dora: \(doraIndicators)")
        print("Dealer hand: \(players[0].hand) and \(players[0].drawnTile!)")
    }
}

extension Tile : CustomStringConvertible {
    var description : String {
        switch self {
        case .Man(let num): return "\(num.hashValue+1)M"
        case .Pin(let num): return "\(num.hashValue+1)P"
        case .Sou(let num): return "\(num.hashValue+1)S"
            
        case .Wind(let w): return ["E","S","W","N"][w.hashValue]
        case .Dragon(let d): return ["白","發","中"][d.hashValue]
        }
    }
}

fileprivate let allTiles : [Tile] = {
    var tiles : [Tile] = Array()
    tiles.reserveCapacity(136)
    
    let allTileTypes : [Tile] = [
        .Man(.one),
        .Man(.two),
        .Man(.three),
        .Man(.four),
        .Man(.five),
        .Man(.six),
        .Man(.seven),
        .Man(.eight),
        .Man(.nine),
        
        .Pin(.one),
        .Pin(.two),
        .Pin(.three),
        .Pin(.four),
        .Pin(.five),
        .Pin(.six),
        .Pin(.seven),
        .Pin(.eight),
        .Pin(.nine),
        
        .Sou(.one),
        .Sou(.two),
        .Sou(.three),
        .Sou(.four),
        .Sou(.five),
        .Sou(.six),
        .Sou(.seven),
        .Sou(.eight),
        .Sou(.nine),
        
        .Wind(.east),
        .Wind(.south),
        .Wind(.west),
        .Wind(.north),
        
        .Dragon(.haku),
        .Dragon(.hatsu),
        .Dragon(.chun),
        ]
    
    for _ in 1...4 {
        tiles += allTileTypes
    }
    
    return tiles
}()

extension Tile : Comparable {
    private func suit() -> Int {
        switch self {
        case .Man(_): return 0
        case .Pin(_): return 1
        case .Sou(_): return 2
        case .Wind(_): return 3
        case .Dragon(_): return 4
        }
    }
    
    private func value() -> Int {
        switch self {
        case .Man(let n), .Pin(let n), .Sou(let n): return n.hashValue
        case .Wind(let n): return n.hashValue
        case .Dragon(let n): return n.hashValue
        }
    }
    
    static func == (a : Tile, b : Tile) -> Bool {
        return a.suit() == b.suit() && a.value() == b.value()
    }
    
    static func < (a : Tile, b : Tile) -> Bool {
        if a.suit() == b.suit() {
            return a.value() < b.value()
        }
        
        return a.suit() < b.suit()
    }
}

// Copied from stackoverflow vv

fileprivate extension MutableCollection {
    /// Shuffles the contents of this collection.
    mutating func shuffle() {
        let c = count
        guard c > 1 else { return }
        
        for (firstUnshuffled, unshuffledCount) in zip(indices, stride(from: c, to: 1, by: -1)) {
            let d: IndexDistance = numericCast(arc4random_uniform(numericCast(unshuffledCount)))
            let i = index(firstUnshuffled, offsetBy: d)
            swapAt(firstUnshuffled, i)
        }
    }
}

fileprivate extension Sequence {
    /// Returns an array with the contents of this sequence, shuffled.
    func shuffled() -> [Iterator.Element] {
        var result = Array(self)
        result.shuffle()
        return result
    }
}
