//
//  Scoring.swift
//  swift_mahjong
//
//  Created by Alex Strange on 10/22/17.
//  Copyright © 2017 Alex Strange. All rights reserved.
//

enum WinType {
    enum YakuType {
        case riichi
        case tsumo
        case ippatsu
        case haitei
        case houtei
        case rinshan
        case chankan
        case doubleriichi
        case pinfu
        case iipeikou
        case sanshokudoujun
        case ittsuu
        case ryanpeikou
        case toitoi
        case sanankou
        case sanshokudoukou
        case sankantsu
        case tanyao
        case yakuhai
        case chanta
        case junchan
        case honroutou
        case shousangen
        case honitsu
        case chinitsu
        case chitoitsu
        case nagashi
    }
    
    public enum YakumanType {
        case kokushi
        case suuankou
        case daisangen
        case shoushuushii
        case daisuushii
        case tsuuiisou
        case chinroutou
        case ryuuiisou
        case chuurenpoutou
        case suukantsu
        case tenhou
        case chihou
        case renhou
        case daichisei
        case parenchan
    }
    
    case NoYaku
    case Yaku([YakuType])
    case Yakuman([YakumanType])
}

struct HanFuScore {
    let han : Int
    let fu : Int
    let yakumanCount : Int
    let bonusCount : Int
    let isDealer : Bool
    
    init(han : Int, fu : Int, yakumanCount : Int, bonusCount : Int, isDealer : Bool) {
        self.han = han
        self.fu = fu
        self.yakumanCount = yakumanCount
        self.bonusCount = bonusCount
        self.isDealer = isDealer
    }
    
    private(set) lazy var basicPoints : Int = {
        if (yakumanCount >= 1) {
            return yakumanCount * 8000
        }
        
        precondition(han >= 0)
        
        switch han {
        case 0...4: // Ordinary
            precondition(fu > 0)
            return fu * ipow(2, 2+han)
        case 5: // Mangan
            return 2000
        case 6...7: // Haneman
            return 3000
        case 8...10: // Baiman
            return 4000
        case 11...12: // Sanbaiman
            return 6000
        default: // Kazoe Yakuman
            return 8000
        }
    }()
    
    private mutating func perPersonScore(_ factor : Int) -> Int {
        return iroundup(factor*basicPoints + 100*bonusCount, 100)
    }
    
    private(set) lazy var tsumoScore : (dealer: Int, notDealer: Int) = {
        if (isDealer) {
            return (0, perPersonScore(2))
        } else {
            return (perPersonScore(2), perPersonScore(1))
        }
    }()
    
    private(set) lazy var ronScore : Int = {
        if (isDealer) {
            return perPersonScore(6)
        } else {
            return perPersonScore(4)
        }
    }()
}

// Description of a game+hand as is relevant to scoring.
// Excluding the actual hand, because we need to try different theories there.
struct HandEnvironment {
    // Seating position
    let roundWind : Wind
    let seatWind : Wind
    
    // Time in round
    let discardRound : Int
    
    // Bonus sticks and riichis in the pot
    let bonusCount : Int
    let bonusPoints : Int
    
    // My closed melds
    let closedTiles : [Meld]
    
    // My open tiles
    let openTiles : [Meld]
    
    // Am I riichi
    let isRiichi : Bool
    
    // The new tile
    let lastTile : Tile // For furiten
    
    // Where did the new tile come from?
    let isSelfDraw : Bool
    let isRinshan : Bool
    let discardedFrom : RelativeSeat? // For furiten
}

func scoreHand(_ hand : HandEnvironment) -> (WinType,HanFuScore) {
    let ctx = ScoringCtx(hand)
    
    print(ctx)
    
    return (.Yaku([.chitoitsu]),HanFuScore(han: 1, fu: 20, yakumanCount: 0, bonusCount: hand.bonusCount, isDealer: hand.seatWind == Wind.east))
}

fileprivate struct ScoringCtx {
    // Internal calculations for scoring
    let hand : HandEnvironment
    
    init(_ hand : HandEnvironment) {
        self.hand = hand
        
        numKou = 0
        numShun = 0
        numKan = 0
        numPair = 0
        numSpare = 0
        
        numSuits = 0
        numHonor = 0
        numTerminal = 0
        
        var numMan = 0
        var numPin = 0
        var numSou = 0
        var numWind = 0
        var numDragon = 0
        
        for meld in allMelds {
            // Count meld types
            switch meld {
            case .Pair: numPair += 1
            case .Chi: numShun += 1
            case .Pon: numKou += 1
            case .OpenKan, .ClosedKan: numKan += 1
            case .SingleTile: numSpare += 1
            }
            
            // Count suits
            func countSuit(_ tile : Tile) {
                switch tile {
                case .Man: numMan += 1
                case .Pin: numPin += 1
                case .Sou: numSou += 1
                case .Wind: numWind += 1
                case .Dragon: numDragon += 1
                }
            }
            
            switch meld {
            case .Pair(let t), .Pon(_, let t), .ClosedKan(_, let t), .OpenKan(_, let t):
                countSuit(t)
            case .Chi(let t1, let t2, let t3):
                for t in [t1,t2,t3] {countSuit(t)}
            case .SingleTile: break
            }

            // Count terminal vs tanyao
            func countTerminal(_ tiles : [Tile]) {
                if tiles.contains(where: {
                    switch $0 {
                    case .Man(let n),.Pin (let n),.Sou (let n):
                        let v = n.hashValue+1
                        if (v == 1 || v == 9) {
                            return true
                        }
                    default: break
                    }
                    return false
                }) {
                    numTerminal += 1
                }
            }
            
            switch meld {
            case .Pair(let t), .Pon(_, let t), .ClosedKan(_, let t), .OpenKan(_, let t):
                countTerminal([t])
            case .Chi(let t1, let t2, let t3):
                countTerminal([t1,t2,t3])
            case .SingleTile: break
            }
        }
        
        numHonor = numWind + numDragon
        numSuits = [numMan,numPin,numSou,numWind,numDragon].lazy.filter({$0 > 0}).count
    }

    // All of the hand
    private(set) lazy var allMelds : [Meld] = {
        return hand.closedTiles + hand.openTiles
    }()
    
    private(set) lazy var isClosed : Bool = {
        return hand.openTiles.isEmpty
    }()
    
    private(set) var numKou : Int // Triplets
    private(set) var numShun : Int // Sequences
    private(set) var numKan : Int
    private(set) var numPair : Int
    private(set) var numSpare : Int
    
    private(set) var numSuits : Int
    private(set) var numHonor : Int
    private(set) var numTerminal : Int
}

fileprivate func iroundup(_ value: Int, _ roundTo: Int) -> Int {
    precondition(roundTo > 0)
    
    let sign = (value >= 0) ? 1 : -1
    let one_half = sign * (roundTo/2)
    
    return ((value + one_half) / roundTo) * roundTo
}

// From stackoverflow
fileprivate func ipow(_ base: Int, _ power: Int) -> Int {
    func expBySq(_ y: Int, _ x: Int, _ n: Int) -> Int {
        precondition(n >= 0)
        if n == 0 {
            return y
        } else if n == 1 {
            return y * x
        } else if n % 2 == 0 {
            return expBySq(y, x * x, n / 2)
        } else { // n is odd
            return expBySq(y * x, x * x, (n - 1) / 2)
        }
    }
    
    return expBySq(1, base, power)
}
