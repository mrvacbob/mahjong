// The ruleset. One field per row of spec/rules.md §1 where Mahjong Soul and Tenhou
// differ or the row is unverified, plus the fields docs/design/engine.md §4.2 and §5
// name. Rows on which both clients agree and nothing is in doubt are not fields:
// they are simply how the engine works.

public enum GameLength: Sendable, Hashable {
    /// Tonpuusen: East round, extension into South.
    case east
    /// Hanchan: East and South rounds, extension into West.
    case south
}

public struct Rules: Sendable, Hashable {
    // MARK: game (design §5)

    /// Every seat's score at the start (`starting_points`).
    public var startingPoints: Int
    /// Subtracted from each final score before uma (`oka`: 25,000 on Mahjong Soul,
    /// 30,000 on Tenhou). See `oka`.
    public var returnPoints: Int
    /// Added to the final score by rank, first to fourth, in points (`uma`).
    public var uma: [Int] {
        didSet { precondition(uma.count == 4, "uma has one entry per rank") }
    }
    /// Score that ends the game in all last and in the extension (`target_points`).
    public var targetPoints: Int
    public var length: GameLength
    /// Rules.md §5 item 8: in all last, a dealer repeat takes priority over another
    /// seat reaching `targetPoints` (Tenhou's manual; Mahjong Soul unverified).
    public var dealerRepeatBeforeTarget: Bool
    /// Rules.md §5 item 6: the all-last tenpai-yame test uses scores after nagashi
    /// mangan payments (the design's ordering; unverified on both clients).
    public var allLastTestAfterNagashi: Bool

    // MARK: scoring

    /// Mahjong Soul's four double yakuman (`natural_double_yakuman`): kokushi_13,
    /// suuankou_tanki, junsei_chuuren and daisuushii count 2 instead of 1.
    public var doubleYakuman: Bool
    /// On a tenhou, any of the dealer's 14 tiles may be taken as the winning tile and
    /// the best choice is scored (Mahjong Soul). Otherwise the drawn tile is the
    /// winning tile.
    public var tenhouAnyWinningTile: Bool
    /// Open tanyao (`kuitan_enabled`).
    public var kuitan: Bool
    /// Fu for a pair of the wind that is both seat and round wind
    /// (`double_wind_pair_fu`).
    public var doubleWindPairFu: Int

    // MARK: wins and windows

    /// Three rons on one discard abort the hand (`abort_sanchahou`). Otherwise all
    /// three win (`triple_ron_enabled`).
    public var tripleRonAborts: Bool
    /// Rules.md §5 item 2: on a multiple ron, every winner collects honba, not only
    /// the one nearest the discarder (`multi_ron_honba`, unverified for Mahjong Soul;
    /// default off on both).
    public var honbaToEveryRonWinner: Bool
    /// Kokushi may rob a closed kan (`chankan_ankan_kokushi`).
    public var kokushiRobsClosedKan: Bool

    // MARK: kans

    /// The indicator owed by an open or added kan is revealed immediately before the
    /// kan seat's discard, so a ron on that discard counts it. On for both: Tenhou's
    /// manual, and Mahjong Soul's records (rules.md §5 item 4, settled from real
    /// logs; docs/notes/p3-reallogs.md). If false it is revealed only after the
    /// window passes. `kan_dora_daiminkan_timing`, `kan_dora_shouminkan_timing`.
    public var openKanDoraBeforeRon: Bool
    /// An indicator still owed by an open or added kan is revealed when the same
    /// seat announces another added kan (after the `kakan` event, before that
    /// kan's robbing window), so a chankan on the chained kan counts it (as a
    /// closed kan always does, design §4.2). Mahjong Soul, from its records; off
    /// for Tenhou, whose manual flips it only before the next replacement draw
    /// (docs/notes/p3-reallogs.md).
    public var owedDoraAtChainedAddedKan: Bool = false

    // MARK: pao

    /// Pao covers the whole composite yakuman hand (Tenhou), not only the liable
    /// yakuman (Mahjong Soul) (`pao_composite_yakuman`).
    public var paoCoversWholeHand: Bool

    // MARK: riichi and draws

    /// Riichi may be declared on a hand whose only wait is a fifth copy of a kind
    /// the hand and melds already hold four of, as long as the four are not all in
    /// the concealed hand (some are in a kan): the same test as
    /// `fifthCopyTenpaiAtDraw`. On for both: both clients' records show such riichi,
    /// each on a wait whose four copies form the seat's own closed kan (rules.md §5
    /// item 7; docs/notes/p3-reallogs.md). A wait on four concealed copies stays
    /// refused, as `spec/formats.md` has it.
    public var riichiOnFifthCopyWait: Bool
    /// At an exhaustive draw, a hand whose only wait is a fifth copy counts as tenpai
    /// unless all four copies are in the concealed hand (Tenhou, rules.md §5 item 7).
    /// On for both (Mahjong Soul from its records, docs/notes/p3-reallogs.md).
    /// Otherwise it is noten (as `formats.md` defines tenpai).
    public var fifthCopyTenpaiAtDraw: Bool
    /// Rules.md §5 item 9: a riichi declared on the discard that completes four winds
    /// pays its stick. On for both: in every such hand in the records the next
    /// header shows the stick on the table (docs/notes/p3-reallogs.md). libriichi
    /// does not pay it.
    public var fourWindsRiichiStickPaid: Bool
    /// Temporary furiten also ends when the seat makes a call (`furiten_temporary`).
    /// On for both: in both clients' records a seat that passed a winning tile,
    /// then called, wins on a discard before its next draw (docs/notes/p3-reallogs.md;
    /// design §4.1 had it ending at the next draw only).
    public var temporaryFuritenEndsOnCall: Bool
    /// A seat not in riichi that could win on its own draw and does anything else is
    /// temporarily furiten until its next live-wall draw (design §4.2; Tenhou's
    /// manual: 「和了放棄…後は同巡フリテン」). Unverified for Mahjong Soul: default off.
    public var temporaryFuritenOnDeclinedTsumo: Bool

    public init(
        startingPoints: Int, returnPoints: Int, uma: [Int], targetPoints: Int,
        length: GameLength, dealerRepeatBeforeTarget: Bool, allLastTestAfterNagashi: Bool,
        doubleYakuman: Bool, tenhouAnyWinningTile: Bool, kuitan: Bool, doubleWindPairFu: Int,
        tripleRonAborts: Bool, honbaToEveryRonWinner: Bool, kokushiRobsClosedKan: Bool,
        openKanDoraBeforeRon: Bool, paoCoversWholeHand: Bool, riichiOnFifthCopyWait: Bool,
        fifthCopyTenpaiAtDraw: Bool, fourWindsRiichiStickPaid: Bool,
        temporaryFuritenEndsOnCall: Bool, temporaryFuritenOnDeclinedTsumo: Bool
    ) {
        precondition(uma.count == 4, "uma has one entry per rank")
        self.startingPoints = startingPoints
        self.returnPoints = returnPoints
        self.uma = uma
        self.targetPoints = targetPoints
        self.length = length
        self.dealerRepeatBeforeTarget = dealerRepeatBeforeTarget
        self.allLastTestAfterNagashi = allLastTestAfterNagashi
        self.doubleYakuman = doubleYakuman
        self.tenhouAnyWinningTile = tenhouAnyWinningTile
        self.kuitan = kuitan
        self.doubleWindPairFu = doubleWindPairFu
        self.tripleRonAborts = tripleRonAborts
        self.honbaToEveryRonWinner = honbaToEveryRonWinner
        self.kokushiRobsClosedKan = kokushiRobsClosedKan
        self.openKanDoraBeforeRon = openKanDoraBeforeRon
        self.paoCoversWholeHand = paoCoversWholeHand
        self.riichiOnFifthCopyWait = riichiOnFifthCopyWait
        self.fifthCopyTenpaiAtDraw = fifthCopyTenpaiAtDraw
        self.fourWindsRiichiStickPaid = fourWindsRiichiStickPaid
        self.temporaryFuritenEndsOnCall = temporaryFuritenEndsOnCall
        self.temporaryFuritenOnDeclinedTsumo = temporaryFuritenOnDeclinedTsumo
    }

    /// Every point setting within ±1,000,000 (non-negative where it must be) and the
    /// double-wind fu 2 or 4, so that no intermediate of the payment and game-end
    /// arithmetic can leave 32-bit `Int` (wasm32) when scores, honba and sticks
    /// also keep within `RoundState`'s bounds (Codex C/D finding 5).
    public var isValid: Bool {
        let p = 0...1_000_000
        return p.contains(startingPoints) && p.contains(returnPoints) && p.contains(targetPoints)
            && uma.count == 4 && uma.allSatisfy { (-1_000_000...1_000_000).contains($0) }
            && [2, 4].contains(doubleWindPairFu)
    }

    /// The bonus to first place: what the four seats put in above `startingPoints`
    /// to reach `returnPoints` (`oka`; 0 on Mahjong Soul, 20,000 on Tenhou).
    public var oka: Int { 4 * (returnPoints - startingPoints) }
}

extension Rules {
    /// Mahjong Soul four-player ranked, hanchan. The default everywhere. The kan
    /// dora timing, fifth-copy and furiten fields are as its records show
    /// (docs/notes/p3-reallogs.md), not as first published in rules.md.
    public static let mahjongSoul: Rules = {
        var r = Rules(
            startingPoints: 25_000, returnPoints: 25_000, uma: [15_000, 5_000, -5_000, -15_000],
            targetPoints: 30_000, length: .south, dealerRepeatBeforeTarget: true,
            allLastTestAfterNagashi: true,
            doubleYakuman: true, tenhouAnyWinningTile: true, kuitan: true, doubleWindPairFu: 4,
            tripleRonAborts: false, honbaToEveryRonWinner: false, kokushiRobsClosedKan: true,
            openKanDoraBeforeRon: true, paoCoversWholeHand: false, riichiOnFifthCopyWait: true,
            fifthCopyTenpaiAtDraw: true, fourWindsRiichiStickPaid: true,
            temporaryFuritenEndsOnCall: true, temporaryFuritenOnDeclinedTsumo: false)
        r.owedDoraAtChainedAddedKan = true
        return r
    }()

    /// Tenhou four-player ranked, hanchan, red fives on.
    public static let tenhou = Rules(
        startingPoints: 25_000, returnPoints: 30_000, uma: [20_000, 10_000, -10_000, -20_000],
        targetPoints: 30_000, length: .south, dealerRepeatBeforeTarget: true,
        allLastTestAfterNagashi: true,
        doubleYakuman: false, tenhouAnyWinningTile: false, kuitan: true, doubleWindPairFu: 4,
        tripleRonAborts: true, honbaToEveryRonWinner: false, kokushiRobsClosedKan: false,
        openKanDoraBeforeRon: true, paoCoversWholeHand: true, riichiOnFifthCopyWait: true,
        fifthCopyTenpaiAtDraw: true, fourWindsRiichiStickPaid: true,
        temporaryFuritenEndsOnCall: true, temporaryFuritenOnDeclinedTsumo: true)
}
