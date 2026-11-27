import Riichi
import RiichiMjai

@main struct Probes {
    static func main() throws {
        switch CommandLine.arguments[1] {
        case "honba":
            let wall = makeWall(hands: ["19m19p19s1234567z"] + quietHands, draws: "5z")
            var events: [Event] = []
            var game = GameState(rules: .mahjongSoul, seed: 0,
                                 position: GamePosition(honba: RoundState.maxCount,
                                                        scores: [25000, 25000, 25000, 25000]),
                                 wall: wall, events: &events)
            precondition(game.legalActions(for: Seat(0)).contains(.kyuushu))
            try game.apply(.kyuushu, by: Seat(0))
        case "timeout":
            let child = try ChildProcess(command: "exec /bin/sleep 1")
            _ = child.readLine(timeoutMs: 3_000_000_000)
        case "score":
            var request = ScoreRequest(hand: t("123456m789p23s99s"), melds: [],
                                       win: t1("1s"), context: WinContext(tsumo: false))
            let control = try score(request, rules: .mahjongSoul)
            precondition(control.payment == .ron(1500))
            request.honba = Int.max
            _ = try score(request, rules: .mahjongSoul)
        default:
            try chained(CommandLine.arguments[2])
            try composite()
            try rinshan()
            try kokushi()
            try heavenly()
            try windStack()
            try east()
            try replyValidation()
        }
    }

    static func chained(_ command: String) throws {
        let wall = makeWall(hands: ["1p1p234m678m567s33z", "1m4m7m9p1p2s5s8s1z2z3z4z5z",
                                    "1m4m7m5p9p2s5s8s9s1z2z4z6z", "23p456m789m340s99s"],
                            draws: "9m6z6z6z1s1s3z", rinshan: "1p8p", dora: "1z8s")
        for soul in [true, false] {
            var rules = Rules.mahjongSoul
            rules.owedDoraAtChainedAddedKan = soul
            rules.openKanDoraBeforeRon = false
            var events: [Event] = []
            var round = RoundState(rules: rules, wall: wall, events: &events)
            try round.tsumogiri(0, events: &events)
            try round.apply(.discard(t1("3z"), tsumogiri: false), by: Seat(1))
            try round.answer([0: .pon(t1("3z"), t1("3z"))], events: &events)
            try round.apply(.discard(t1("8m"), tsumogiri: false), by: Seat(0))
            try round.apply(.discard(t1("1p"), tsumogiri: false), by: Seat(1))
            try round.answer([0: .pon(t1("1p"), t1("1p"))], events: &events)
            try round.apply(.discard(t1("7m"), tsumogiri: false), by: Seat(0))
            for seat in 1...3 {
                try round.tsumogiri(seat, events: &events)
                if !round.seatsToAnswer.isEmpty { try round.answer(events: &events) }
            }
            try round.apply(.kakan(t1("3z")), by: Seat(0))
            events = []
            try round.apply(.kakan(t1("1p")), by: Seat(0), events: &events)
            let robber = Seat(3)
            let view = round.view(of: robber)
            precondition(view.legalActions == [.ron, .pass])
            precondition(events.map(\.type) == (soul ? ["kakan", "dora"] : ["kakan"]))
            var bot = MjaiBot(seat: robber, command: command, names: [], timeoutMs: 2000)
            var answer: Action?
            // Same delivery rule as Driver.deliver.
            for (index, event) in events.enumerated() {
                answer = bot.receive([event.masked(for: robber)],
                                     view: index == events.count - 1 ? view : nil)
            }
            bot.finish()
            precondition(answer == (soul ? .pass : .ron) && bot.substitutions.total == 0)
            try round.answer([3: .ron], events: &events)
            let win = round.result!.wins[0]
            precondition(win.robbedKan == .added && win.doraIndicators.count == (soul ? 2 : 1))
            precondition(win.scored.yaku.first { $0.name == .dora }?.value == (soul ? 2 : nil))
            print("chained owed=\(soul) adapter=\(answer!) substitutions=0 score=\(win.scored.yakuText)")
        }
    }

    static func composite() throws {
        let wall = makeWall(hands: ["234m1112556677z", "147m147p258s2356z",
                                    "258m258p369s2347z", "369m369p147s1344z"],
                            draws: "8p8s9s5p6p6s8m7s2z")
        for whole in [false, true] {
            for tsumo in [false, true] {
                var rules = Rules.mahjongSoul
                rules.paoCoversWholeHand = whole
                var events: [Event] = []
                var round = RoundState(rules: rules, wall: wall, honba: 2)
                try round.tsumogiri(0, events: &events)
                for (index, dragon) in ["5z", "6z", "7z"].enumerated() {
                    let from = index == 2 ? 2 : 1
                    if index == 2 {
                        try round.tsumogiri(1, events: &events)
                        if !round.seatsToAnswer.isEmpty { try round.answer(events: &events) }
                    }
                    try round.apply(.discard(t1(dragon), tsumogiri: false), by: Seat(from))
                    try round.answer([0: .pon(t1(dragon), t1(dragon))], events: &events)
                    try round.apply(.discard(t1(["2m", "3m", "4m"][index]), tsumogiri: false), by: Seat(0))
                    if !round.seatsToAnswer.isEmpty { try round.answer(events: &events) }
                }
                // The hand now waits on 2z, and seat 2 fed the decisive pon.
                if tsumo {
                    for index in 1...3 {
                        try round.tsumogiri(index, events: &events)
                        if !round.seatsToAnswer.isEmpty { try round.answer(events: &events) }
                    }
                    try round.apply(.tsumo, by: Seat(0))
                } else {
                    try round.apply(.discard(t1("2z"), tsumogiri: false), by: Seat(1))
                    try round.answer([0: .ron], events: &events)
                }
                let win = round.result!.wins[0]
                precondition(win.scored.value == .yakuman(2) && win.liable == Seat(2))
                let expected = tsumo
                    ? (whole ? [96600, 0, -96600, 0] : [96600, -16000, -64600, -16000])
                    : (whole ? [96600, -48000, -48600, 0] : [96600, -72000, -24600, 0])
                precondition(win.deltas == expected)
                print("composite whole=\(whole) tsumo=\(tsumo) \(win.deltas)")
            }
        }
    }

    static func rinshan() throws {
        let wall = makeWall(hands: [quietHands[0], "123456m99p23s555z", quietHands[1], quietHands[2]],
                            draws: "5z", rinshan: "1s", dora: "4z9s")
        for base in [Rules.mahjongSoul, .tenhou] {
            var rules = base
            rules.openKanDoraBeforeRon.toggle()
            var events: [Event] = []
            var round = RoundState(rules: rules, wall: wall)
            try round.tsumogiri(0, events: &events)
            events = []
            try round.answer([1: .daiminkan], events: &events)
            precondition(events.map(\.type) == ["daiminkan", "tsumo"])
            try round.apply(.tsumo, by: Seat(1), events: &events)
            let win = round.result!.wins[0]
            precondition(win.doraIndicators == t("4z") && win.scored.value(of: .rinshan) == 1)
            print("open kan rinshan", win.scored.yakuText)
        }
    }

    static func kokushi() throws {
        let wall = makeWall(hands: ["111123456m234p5z", "9m19p19s12345677z",
                                    "258m258p258s1122z", "369m369p369s3344z"],
                            draws: "5p", rinshan: "6p", dora: "6z7z")
        for rules in [Rules.mahjongSoul, .tenhou] {
            var events: [Event] = []
            var round = RoundState(rules: rules, wall: wall)
            try round.apply(.ankan(t1("1m").kind), by: Seat(0), events: &events)
            let soul = rules == .mahjongSoul
            precondition(round.seatsToAnswer == (soul ? [Seat(1)] : []))
            if soul {
                precondition(events.map(\.type) == ["ankan"])
                let announcement = events[0].masked(for: Seat(1))
                guard case .ankan(_, let consumed) = announcement else { preconditionFailure() }
                precondition(consumed == t("1111m"))
                precondition(round.view(of: Seat(2)).table.reacting == nil)
                try round.answer([1: .ron], events: &events)
                precondition(round.result!.wins[0].robbedKan == .closed && round.kanCount == 0)
                precondition(round.result!.wins[0].scored.value == .yakuman(1))
            } else {
                precondition(round.kanCount == 1 && events.map(\.type) == ["ankan", "dora", "tsumo"])
            }
        }
        print("closed-kan kokushi and masked event cases passed")
    }

    static func heavenly() throws {
        let wall = makeWall(hands: ["119m19p19s123456z", "258m258p258s1122z",
                                    "369m369p369s3344z", "147m147p147s5566z"], draws: "7z")
        for rules in [Rules.mahjongSoul, .tenhou] {
            var round = RoundState(rules: rules, wall: wall)
            try round.apply(.tsumo, by: Seat(0))
            let win = round.result!.wins[0]
            precondition(win.tile == t1("7z"))
            precondition(win.scored.value == .yakuman(rules == .mahjongSoul ? 3 : 2))
            print("heavenly \(win.tile) \(win.scored.yakuText)")
        }
    }

    static func windStack() throws {
        let request = ScoreRequest(hand: t("1112223334445z"), melds: [], win: t1("5z"),
                                   context: WinContext(seat: .south, tsumo: false))
        for (rules, multiple) in [(Rules.mahjongSoul, 5), (Rules.tenhou, 3)] {
            let scored = try score(request, rules: rules)
            precondition(scored.value == .yakuman(multiple))
            precondition(scored.payment == .ron(32000 * multiple))
            print("wind stack", scored.yakuText, scored.payment.total)
        }
    }

    static func replyValidation() throws {
        let message = try Mjai.decode(#"{"type":"hora","actor":3,"target":2,"pai":"9s"}"#)
        let offer = (tile: t1("1p"), from: Seat(0))
        let action = Mjai.action(message, seat: Seat(3), legal: [.ron, .pass], offered: offer)
        precondition(action == .ron)
        print("wrong target and tile still request ron on the current offer")
    }

    static func east() throws {
        var rules = Rules.mahjongSoul
        rules.length = .east
        rules.targetPoints = 1_000_000
        var events: [Event] = []
        var game = GameState(rules: rules, seed: 0,
                             position: GamePosition(sticks: 2, scores: [25000, 25000, 25000, 25000]),
                             events: &events)
        var folder = ViewFolder(seat: Seat(0))
        for event in events { folder.apply(event.masked(for: Seat(0))) }
        var winds: Set<Wind> = []
        for _ in 0..<4000 where !game.isOver {
            winds.insert(game.position.roundWind)
            events = []
            if case .turn(let seat, _) = game.phase {
                try game.apply(game.legalActions(for: seat).first {
                    if case .discard(_, true) = $0 { true } else { false }
                }!, by: seat, events: &events)
            } else {
                var answers = Answers()
                for seat in game.seatsToAnswer { answers[seat] = .pass }
                try game.resolve(answers, events: &events)
            }
            for event in events { folder.apply(event.masked(for: Seat(0))) }
        }
        precondition(folder.table.scores == game.round.scores && folder.table.sticks == 2)
        precondition(game.result?.scores != folder.table.scores && game.result?.sticksAwarded == 2)
        print("terminal folder \(folder.table.scores), final \(game.result!.scores)")
        precondition(winds == [.east, .south] && game.result?.end == .extensionOver)
        let result = GameFlow.result(scores: [30000, 30000, 19000, 19000], sticks: 2,
                                     rules: rules, end: .extensionOver)
        precondition(result.scores == [32000, 30000, 19000, 19000] && result.sticksAwarded == 2)
        print("East-only game finished \(game.handsDealt) hands; leftover stick tie goes to seat 0")
    }
}
