// What each seat may do now: the only place that decides (design §1 goal 1).
//
// Canonical order of `legalActions`:
// - own turn: `tsumo`, `riichi`, `ankan` (by kind), `kakan` (by tile), `kyuushu`,
//   then discards by tile, each from-hand discard before the tsumogiri of an equal
//   tile;
// - a window: `ron`, `daiminkan`, `pon` (by tiles used), `chi` (by tiles used),
//   `pass`.

extension [Tile] {
    /// The distinct tiles of a sorted list, in order (no hashing).
    var uniqueSorted: [Tile] {
        var out: [Tile] = []
        out.reserveCapacity(count)
        for t in self where out.last != t { out.append(t) }
        return out
    }
}

extension Kind {
    /// A suited five, which has a red copy.
    var hasRed: Bool { !isHonor && number == 5 }
}

extension RoundState {
    /// Empty if the seat has nothing to decide now.
    public func legalActions(for seat: Seat) -> [Action] {
        switch phase {
        case .turn(let s, let start): s == seat ? turnActions(seat, start) : []
        case .reactions, .robbing: offers.isEmpty ? [] : offers[seat.index]
        case .ended: []
        }
    }

    // MARK: own turn

    func turnActions(_ seat: Seat, _ start: TurnStart) -> [Action] {
        let p = players[seat.index]
        switch start {
        case .call:
            return p.hand.uniqueSorted.filter { p.kuikae & bit($0.kind) == 0 }
                .map { .discard($0, tsumogiri: false) }
        case .riichiDeclared:
            return riichiDiscards(p)
        case .draw, .replacementDraw:
            break
        }
        let drawn = p.drawn!
        var out: [Action] = []
        if canTsumo(seat, start) { out.append(.tsumo) }
        if canRiichi(p, seat) { out.append(.riichi) }
        out += ankanKinds(p).map { .ankan($0) }
        out += kakanTiles(p).map { .kakan($0) }
        if canKyuushu(p, start) { out.append(.kyuushu) }
        if p.riichi == .accepted {
            out.append(.discard(drawn, tsumogiri: true))
        } else {
            var placed = false
            for t in p.hand.uniqueSorted {
                if !placed && drawn < t {
                    out.append(.discard(drawn, tsumogiri: true))
                    placed = true
                }
                out.append(.discard(t, tsumogiri: false))
                if !placed && drawn == t {
                    out.append(.discard(drawn, tsumogiri: true))
                    placed = true
                }
            }
            if !placed { out.append(.discard(drawn, tsumogiri: true)) }
        }
        return out
    }

    /// As `turnActions(...).contains(action)`, without building the list.
    func isLegalTurnAction(_ action: Action, seat: Seat, start: TurnStart) -> Bool {
        let p = players[seat.index]
        switch (action, start) {
        case (.discard(let t, let tg), .call):
            return !tg && p.hand.contains(t) && p.kuikae & bit(t.kind) == 0
        case (.discard, .riichiDeclared):
            return riichiDiscards(p).contains(action)
        case (.discard(let t, let tg), _):
            if tg { return p.drawn == t }
            return p.riichi != .accepted && p.hand.contains(t)
        case (_, .call), (_, .riichiDeclared):
            return false
        case (.tsumo, _): return canTsumo(seat, start)
        case (.riichi, _): return canRiichi(p, seat)
        case (.ankan(let k), _): return ankanKinds(p).contains(k)
        case (.kakan(let t), _): return kakanTiles(p).contains(t)
        case (.kyuushu, _): return canKyuushu(p, start)
        default: return false
        }
    }

    func canTsumo(_ seat: Seat, _ start: TurnStart) -> Bool {
        let p = players[seat.index]
        guard let d = p.drawn, p.waits & bit(d.kind) != 0 else { return false }
        return scoreWin(seat, d, source: .draw(start), honba: 0) != nil
    }

    /// Tenpai for riichi after discarding down to `rest`: some wait has a copy
    /// outside the hand and melds, or (`rules.riichiOnFifthCopyWait`) is a fifth
    /// copy whose four are not all concealed, as for tenpai at a draw.
    func isRiichiTenpai(_ rest: Counts, _ p: PlayerState) -> Bool {
        var w = waitMask(rest, meldCount: p.melds.count)
        guard w != 0 else { return false }
        let meldKinds = Counts(p.analysisMelds.tiles)
        for k in Kind.all where w & bit(k) != 0 && rest[k] + meldKinds[k] >= 4 {
            if rules.riichiOnFifthCopyWait && rest[k] < 4 { continue }
            w &= ~bit(k)
        }
        return w != 0
    }

    func canRiichi(_ p: PlayerState, _ seat: Seat) -> Bool {
        guard p.riichi == .none, p.isClosed, scores[seat.index] >= 1000, liveTilesLeft >= 4,
              let d = p.drawn else { return false }
        let all = p.counts.adding(d.kind)
        guard shanten(all, meldCount: p.melds.count).min <= 0 else { return false }
        return Kind.all.contains { all[$0] > 0 && isRiichiTenpai(all.removing($0), p) }
    }

    /// The riichi discards: those leaving the hand tenpai.
    func riichiDiscards(_ p: PlayerState) -> [Action] {
        let d = p.drawn!
        let all = p.counts.adding(d.kind)
        var ok: UInt64 = 0
        for k in Kind.all where all[k] > 0 && isRiichiTenpai(all.removing(k), p) { ok |= bit(k) }
        var out: [Action] = []
        var placed = false
        for t in p.hand.uniqueSorted {
            if !placed && d < t {
                if ok & bit(d.kind) != 0 { out.append(.discard(d, tsumogiri: true)) }
                placed = true
            }
            if ok & bit(t.kind) != 0 { out.append(.discard(t, tsumogiri: false)) }
            if !placed && d == t {
                if ok & bit(d.kind) != 0 { out.append(.discard(d, tsumogiri: true)) }
                placed = true
            }
        }
        if !placed && ok & bit(d.kind) != 0 { out.append(.discard(d, tsumogiri: true)) }
        return out
    }

    /// No kan of any sort with no live tiles left, and never a fifth kan.
    var kanAllowed: Bool { liveTilesLeft >= 1 && kanCount < 4 }

    func ankanKinds(_ p: PlayerState) -> [Kind] {
        guard kanAllowed, let d = p.drawn else { return [] }
        let all = p.counts.adding(d.kind)
        if p.riichi == .accepted {
            // Only the drawn tile, and only if the waits stay the same.
            guard all[d.kind] == 4 else { return [] }
            var after = p.counts
            after[d.kind] = 0
            return waitMask(after, meldCount: p.melds.count + 1) == p.waits ? [d.kind] : []
        }
        return Kind.all.filter { all[$0] == 4 }
    }

    func kakanTiles(_ p: PlayerState) -> [Tile] {
        guard kanAllowed, p.riichi == .none, let d = p.drawn,
              p.melds.contains(where: { $0.kind == .pon }) else { return [] }
        let tiles = (p.hand + [d]).distinct
        var out: [Tile] = []
        for m in p.melds where m.kind == .pon {
            out += tiles.filter { $0.kind == m.tiles[0].kind }
        }
        return out.sorted()
    }

    func canKyuushu(_ p: PlayerState, _ start: TurnStart) -> Bool {
        guard start == .draw, !anyCallMade, p.pond.isEmpty, let d = p.drawn else { return false }
        let all = p.counts.adding(d.kind)
        return Kind.yaochu.count(where: { all[$0] > 0 }) >= 9
    }

    // MARK: windows

    func canRon(_ seat: Seat, _ tile: Tile, source: WinSource) -> Bool {
        let p = players[seat.index]
        guard p.waits & bit(tile.kind) != 0, !p.isFuriten else { return false }
        return scoreWin(seat, tile, source: source, honba: 0) != nil
    }

    /// Each seat's choices on a discard (empty when it has none).
    func discardOffers(_ d: Discard) -> [[Action]] {
        var out: [[Action]] = [[], [], [], []]
        let k = d.tile.kind
        for n in 1...3 {
            let s = d.seat.advanced(by: n)
            let p = players[s.index]
            var acts: [Action] = []
            if canRon(s, d.tile, source: .discard) { acts.append(.ron) }
            if liveTilesLeft > 0 && p.riichi == .none {
                let same = p.counts[k]
                if same == 3 && kanCount < 4 { acts.append(.daiminkan) }
                if same >= 2 {
                    let red = k.hasRed && p.hand.contains(Tile(k, red: true)) ? 1 : 0
                    let plain = same - red
                    if red >= 1 && plain >= 1 && leavesDiscard(p, [k, k], forbidden: bit(k)) {
                        acts.append(.pon(Tile(k, red: true), Tile(k)))
                    }
                    if plain >= 2 && leavesDiscard(p, [k, k], forbidden: bit(k)) {
                        acts.append(.pon(Tile(k), Tile(k)))
                    }
                }
                if n == 1 && !k.isHonor { acts += chiOptions(p, k) }
            }
            if !acts.isEmpty {
                acts.append(.pass)
                out[s.index] = acts
            }
        }
        return out
    }

    /// Some discard is allowed after using `used` from the hand for a call.
    func leavesDiscard(_ p: PlayerState, _ used: [Kind], forbidden: UInt64) -> Bool {
        var rest = p.counts
        for k in used { rest[k] -= 1 }
        return Kind.all.contains { rest[$0] > 0 && forbidden & bit($0) == 0 }
    }

    func chiOptions(_ p: PlayerState, _ k: Kind) -> [Action] {
        var out: [Action] = []
        for (a, b) in [(-2, -1), (-1, 1), (1, 2)] {
            guard let ka = k.shifted(a), let kb = k.shifted(b), p.counts[ka] > 0, p.counts[kb] > 0,
                  leavesDiscard(p, [ka, kb], forbidden: chiKuikae(took: k, ka, kb)) else { continue }
            for ta in variants(p, ka) {
                for tb in variants(p, kb) { out.append(.chi(ta, tb)) }
            }
        }
        return out
    }

    /// The distinct tiles of kind `k` in the hand, red first.
    func variants(_ p: PlayerState, _ k: Kind) -> [Tile] {
        var out: [Tile] = []
        if k.hasRed && p.hand.contains(Tile(k, red: true)) { out.append(Tile(k, red: true)) }
        if p.counts[k] > out.count { out.append(Tile(k)) }
        return out
    }

    /// Each seat's choices on an announced kan: ron or pass.
    func kanOffers(_ pk: PendingKan) -> [[Action]] {
        var out: [[Action]] = [[], [], [], []]
        for n in 1...3 {
            let s = pk.seat.advanced(by: n)
            let p = players[s.index]
            let rob: Bool
            switch pk.kind {
            case .added:
                rob = canRon(s, pk.tile, source: .robbing(.added))
            case .closed:
                rob = rules.kokushiRobsClosedKan && p.melds.isEmpty && !p.isFuriten
                    && isKokushi(p.counts.adding(pk.tile.kind))
            }
            if rob { out[s.index] = [.ron, .pass] }
        }
        return out
    }
}
