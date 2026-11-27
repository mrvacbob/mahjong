// The `legal` op, built from score and hand completion.

public enum Situation: Sendable {
    /// Own turn, having just drawn this tile (not in `hand`).
    case draw(Tile)
    /// Another seat discarded this tile (or is adding it to a kan, with the
    /// `chankan` or `ankan_rob` flag).
    case discard(Tile, fromKamicha: Bool)
    /// This seat just made this chi or pon (already in `melds`) by taking `took`.
    case called(Meld, took: Tile)
}

/// One `legal` question (`spec/formats.md`).
public struct LegalRequest: Sendable {
    public var hand: [Tile]
    public var melds: [Meld]
    public var situation: Situation
    public var seat: Wind
    public var round: Wind
    public var flags: Set<Flag>
    public var inRiichi: Bool
    public var furiten: Bool
    /// Live wall tiles left.
    public var wall: Int
    public var firstTurn: Bool
    /// Kans at the table so far.
    public var kans: Int
    public var rules: Rules

    public init(hand: [Tile], melds: [Meld], situation: Situation, seat: Wind = .east,
                round: Wind = .east, flags: Set<Flag> = [], inRiichi: Bool = false,
                furiten: Bool = false, wall: Int = 70, firstTurn: Bool = false, kans: Int = 0,
                rules: Rules) {
        self.hand = hand; self.melds = melds; self.situation = situation
        self.seat = seat; self.round = round; self.flags = flags
        self.inRiichi = inRiichi; self.furiten = furiten; self.wall = wall
        self.firstTurn = firstTurn; self.kans = kans; self.rules = rules
    }
}

/// Whether discarding down to `rest` leaves a hand that may declare riichi: tenpai,
/// on a wait with a copy outside the hand and melds, or (`rules.riichiOnFifthCopyWait`)
/// on a fifth copy whose four are not all concealed.
func isRiichiTenpai(_ rest: Counts, melds: [Meld], rules: Rules) -> Bool {
    let meldKinds = Counts(melds.tiles)
    return Kind.all.contains { w in
        (rest[w] + meldKinds[w] < 4 || (rules.riichiOnFifthCopyWait && rest[w] < 4))
            && isComplete(rest.adding(w), meldCount: melds.count)
    }
}

/// Tenpai for payments at an exhaustive draw. `concealed` is the 13 − 3k concealed
/// tiles. A wait that exists only as a fifth copy counts only under
/// `Rules.fifthCopyTenpaiAtDraw`, and then only if the four copies are not all
/// concealed (rules.md §5 item 7).
public func isTenpaiAtDraw(_ concealed: Counts, melds: [Meld], rules: Rules) -> Bool {
    let meldKinds = Counts(melds.tiles)
    return Kind.all.contains { w in
        let available = rules.fifthCopyTenpaiAtDraw
            ? concealed[w] < 4
            : concealed[w] + meldKinds[w] < 4
        return available && isComplete(concealed.adding(w), meldCount: melds.count)
    }
}

extension LegalRequest {
    /// Throws unless the request can be answered: valid rules, at most four melds,
    /// 13 − 3 × melds concealed tiles (14 − 3 × melds right after a call), a
    /// possible tile set, `wall` 0...70 and `kans` 0...4.
    public func check() throws(InputError) {
        try rules.validate()
        guard melds.count <= 4 else { throw InputError("melds", "\(melds.count) melds") }
        let extra: [Tile]
        let size: Int
        switch situation {
        case .draw(let t), .discard(let t, _): extra = [t]; size = 13 - 3 * melds.count
        case .called(let m, let took):
            guard m.kind == .chi || m.kind == .pon, m.tiles.contains(took), melds.contains(m) else {
                throw InputError("called", "not a chi or pon among the melds that takes \(took)")
            }
            extra = []; size = 14 - 3 * melds.count
        }
        guard hand.count == size else { throw InputError("hand", "\(hand.count) tiles, not \(size)") }
        guard isPossibleTileSet(hand + extra + melds.tiles) else {
            throw InputError("hand", "more than four of a kind or two red fives of a suit")
        }
        guard (0...Wall.liveDraws).contains(wall) else { throw InputError("wall", "\(wall) is not 0...\(Wall.liveDraws)") }
        guard (0...4).contains(kans) else { throw InputError("kans", "\(kans) is not 0...4") }
    }

    /// The `legal` answer: distinct actions, sorted as strings (after `check()`).
    public var actions: [String] {
        get throws(InputError) {
            try check()
            return answer
        }
    }

    private var answer: [String] {
        let out = switch situation {
        case .draw(let t): afterDraw(drawn: t)
        case .discard(let t, let kamicha): onDiscard(tile: t, fromKamicha: kamicha)
        case .called(let meld, let took): afterCall(meld: meld, took: took)
        }
        return Set(out).sorted()
    }

    /// Whether `score` accepts this hand winning on `tile`, with the situational
    /// flags `allowed` for this trigger.
    private func wins(_ tile: Tile, tsumo: Bool, allowed: Set<Flag>) -> Bool {
        var flags = flags.intersection(allowed)
        if inRiichi { flags.insert(.riichi) }
        let context = WinContext(seat: seat, round: round, tsumo: tsumo, flags: flags)
        return (try? score(ScoreRequest(hand: hand, melds: melds, win: tile, context: context),
                           rules: rules)) != nil
    }

    // MARK: own draw

    private func afterDraw(drawn: Tile) -> [String] {
        let tiles = hand + [drawn]
        let counts = Counts(tiles)
        var out: [String] = []

        let discards = inRiichi ? [drawn] : tiles.distinct
        out += discards.map { "discard:\($0)" }

        if wins(drawn, tsumo: true, allowed: [.rinshan, .haitei, .tenhou, .chiihou]) {
            out.append("tsumo")
        }

        if !inRiichi && melds.isClosed && wall >= 4 {
            for k in counts.kinds where isRiichiTenpai(counts.removing(k), melds: melds, rules: rules) {
                out += tiles.distinct.filter { $0.kind == k }.map { "riichi:\($0)" }
            }
        }

        if wall >= 1 && kans < 4 {
            for k in counts.kinds where counts[k] == 4 {
                if inRiichi {
                    // The kan must use the drawn tile and keep the structural waits.
                    guard k == drawn.kind else { continue }
                    var after = counts
                    after[k] = 0
                    let before = completingKinds(Counts(hand), meldCount: melds.count)
                    let now = completingKinds(after, meldCount: melds.count + 1)
                    guard before == now else { continue }
                }
                out.append("ankan:\(Tile(k))")
            }
            if !inRiichi {
                for m in melds where m.kind == .pon {
                    for t in tiles.distinct where t.kind == m.base { out.append("kakan:\(t)") }
                }
            }
        }

        if firstTurn && Kind.yaochu.count(where: { counts[$0] > 0 }) >= 9 {
            out.append("kyuushu")
        }
        return out
    }

    // MARK: another seat's discard

    private func onDiscard(tile: Tile, fromKamicha: Bool) -> [String] {
        var out = ["pass"]
        let robbing = flags.contains(.chankan) || flags.contains(.ankan_rob)

        if !furiten {
            let canRon: Bool
            if flags.contains(.ankan_rob) {
                canRon = rules.kokushiRobsClosedKan && melds.isEmpty && isKokushi(Counts(hand + [tile]))
            } else {
                canRon = wins(tile, tsumo: false, allowed: [.houtei, .chankan])
            }
            if canRon { out.append("ron") }
        }
        if robbing || inRiichi || wall < 1 { return out }

        let k = tile.kind
        // A call is offered only if some discard remains allowed afterwards.
        func leavesDiscard(_ used: [Tile], forbidden: Set<Kind>) -> Bool {
            var rest = hand
            for t in used { rest = rest.removingOne(t) }
            return rest.contains { !forbidden.contains($0.kind) }
        }

        if fromKamicha {
            for (a, b) in [(-2, -1), (-1, 1), (1, 2)] {
                guard let ka = k.shifted(a), let kb = k.shifted(b) else { continue }
                for ta in hand.distinct where ta.kind == ka {
                    for tb in hand.distinct where tb.kind == kb {
                        let chi = Meld(kind: .chi, tiles: [ta, tb, tile])!
                        if leavesDiscard([ta, tb], forbidden: chi.kuikaeForbidden(took: k)) {
                            out.append("chi:\(mpsz([ta, tb]))")
                        }
                    }
                }
            }
        }

        let same = hand.filter { $0.kind == k }
        let plain = same.count { !$0.isRed }
        let red = same.count - plain
        var pons: [[Tile]] = []
        if plain >= 2 { pons.append([Tile(k), Tile(k)]) }
        if red >= 1 && plain >= 1 { pons.append([Tile(k, red: true), Tile(k)]) }
        for p in pons where leavesDiscard(p, forbidden: [k]) {
            out.append("pon:\(mpsz(p))")
        }
        if same.count == 3 && kans < 4 { out.append("kan:\(Tile(k))") }
        return out
    }

    // MARK: after this seat's own chi or pon

    private func afterCall(meld: Meld, took: Tile) -> [String] {
        let forbidden = meld.kuikaeForbidden(took: took.kind)
        return hand.distinct.filter { !forbidden.contains($0.kind) }.map { "discard:\($0)" }
    }
}
