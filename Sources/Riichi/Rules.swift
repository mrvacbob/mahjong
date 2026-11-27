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

    /// The indicator owed by an open or added kan is revealed at the kan seat's
    /// discard, before the window, so a ron on that discard counts it (Tenhou). If
    /// false it is revealed only after the window passes (Mahjong Soul as published;
    /// rules.md §5 item 4, unverified). `kan_dora_daiminkan_timing`,
    /// `kan_dora_shouminkan_timing`.
    public var openKanDoraBeforeRon: Bool

    // MARK: pao

    /// Pao covers the whole composite yakuman hand (Tenhou), not only the liable
    /// yakuman (Mahjong Soul) (`pao_composite_yakuman`).
    public var paoCoversWholeHand: Bool

    // MARK: riichi and draws

    /// Riichi may be declared on a hand whose only wait is a fifth copy of a kind
    /// the hand and melds already hold four of. Unverified on both clients (rules.md
    /// §5 item 7); default off (`spec/formats.md`, `legal`).
    public var riichiOnFifthCopyWait: Bool
    /// At an exhaustive draw, a hand whose only wait is a fifth copy counts as tenpai
    /// unless all four copies are in the concealed hand (Tenhou, rules.md §5 item 7).
    /// Otherwise it is noten (Mahjong Soul, as `formats.md` defines tenpai).
    public var fifthCopyTenpaiAtDraw: Bool
    /// Rules.md §5 item 9: a riichi declared on the discard that completes four winds
    /// pays its stick. Unverified on both; default off, as libriichi does.
    public var fourWindsRiichiStickPaid: Bool
    /// Temporary furiten also ends when the seat makes a call (`furiten_temporary`).
    /// Off for both: Tenhou's manual and Mahjong Soul's published rules end it at the
    /// seat's next draw only (design §4.1).
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

    /// The bonus to first place: what the four seats put in above `startingPoints`
    /// to reach `returnPoints` (`oka`; 0 on Mahjong Soul, 20,000 on Tenhou).
    public var oka: Int { 4 * (returnPoints - startingPoints) }
}

extension Rules {
    /// Mahjong Soul four-player ranked, hanchan. The default everywhere.
    public static let mahjongSoul = Rules(
        startingPoints: 25_000, returnPoints: 25_000, uma: [15_000, 5_000, -5_000, -15_000],
        targetPoints: 30_000, length: .south, dealerRepeatBeforeTarget: true,
        allLastTestAfterNagashi: true,
        doubleYakuman: true, tenhouAnyWinningTile: true, kuitan: true, doubleWindPairFu: 4,
        tripleRonAborts: false, honbaToEveryRonWinner: false, kokushiRobsClosedKan: true,
        openKanDoraBeforeRon: false, paoCoversWholeHand: false, riichiOnFifthCopyWait: false,
        fifthCopyTenpaiAtDraw: false, fourWindsRiichiStickPaid: false,
        temporaryFuritenEndsOnCall: false, temporaryFuritenOnDeclinedTsumo: false)

    /// Tenhou four-player ranked, hanchan, red fives on.
    public static let tenhou = Rules(
        startingPoints: 25_000, returnPoints: 30_000, uma: [20_000, 10_000, -10_000, -20_000],
        targetPoints: 30_000, length: .south, dealerRepeatBeforeTarget: true,
        allLastTestAfterNagashi: true,
        doubleYakuman: false, tenhouAnyWinningTile: false, kuitan: true, doubleWindPairFu: 4,
        tripleRonAborts: true, honbaToEveryRonWinner: false, kokushiRobsClosedKan: false,
        openKanDoraBeforeRon: true, paoCoversWholeHand: true, riichiOnFifthCopyWait: false,
        fifthCopyTenpaiAtDraw: true, fourWindsRiichiStickPaid: false,
        temporaryFuritenEndsOnCall: false, temporaryFuritenOnDeclinedTsumo: true)
}
