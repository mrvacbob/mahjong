@testable import Riichi
import RiichiMjai

// 1. Finding 12: GameFlow.next with dealerRepeatBeforeTarget == false ends on an abortive draw in all-last
var r = Rules.mahjongSoul
r.dealerRepeatBeforeTarget = false
let s4 = GamePosition(roundWind: .south, kyoku: 4, honba: 0, sticks: 0, scores: [20_000, 20_000, 20_000, 40_000])
let abortRes = RoundResult(
    outcome: .abortiveDraw(.kyuushu),
    deltas: [0, 0, 0, 0],
    scores: [20_000, 20_000, 20_000, 40_000],
    sticks: 0,
    dealer: Seat(3),
    dealerRepeats: true
)
let (nextPos, trans) = GameFlow.next(after: abortRes, at: s4, rules: r)
print("[Finding 12: dealerRepeatBeforeTarget=false + abortive draw in S4] next=\(String(describing: nextPos)) transition=\(trans)")
assert(nextPos == nil && trans == .ends(.target), "Expected bug to reproduce")

// 2. Finding 11: Mjai.action accepts ankan with 1-tile or mismatched consumed
let badAnkan = try Mjai.decode(#"{"type":"ankan","actor":0,"consumed":["1m"]}"#)
let act11a = Mjai.action(badAnkan, seat: Seat(0), legal: [.ankan(Kind(.man, 1))])
let badAnkan2 = try Mjai.decode(#"{"type":"ankan","actor":0,"consumed":["1m","9p","2s","E"]}"#)
let act11b = Mjai.action(badAnkan2, seat: Seat(0), legal: [.ankan(Kind(.man, 1))])
print("[Finding 11: bogus ankan consumed] 1-tile=\(String(describing: act11a)) mismatched=\(String(describing: act11b))")
assert(act11a == .ankan(Kind(.man, 1)) && act11b == .ankan(Kind(.man, 1)), "Expected bug to reproduce")

// 3. Finding 9: duplicate keys first-wins vs last-wins
let dup = try Mjai.decode(#"{"type":"none","type":"dahai","actor":0,"pai":"1m","tsumogiri":true}"#)
print("[Finding 9: duplicate key type] parsed type=\(dup.type) (standard JSON last-wins would be 'dahai')")
assert(dup.type == "none")

// 4. Verify all other design §5 game-flow branches (sanity check)
// 4a. Leftover sticks excluded from 30,000 test: S4 dealer at 29,000 + 1 stick = 30,000 -> must NOT end
let s4Sticks = GamePosition(roundWind: .south, kyoku: 4, honba: 0, sticks: 1, scores: [29_000, 25_000, 16_000, 29_000])
let resSticks = RoundResult(outcome: .exhaustiveDraw(tenpai: [Seat(3)], nagashi: []),
                            deltas: [0, 0, 0, 0], scores: [29_000, 25_000, 16_000, 29_000],
                            sticks: 1, dealer: Seat(3), dealerRepeats: true)
let (nSticks, tSticks) = GameFlow.next(after: resSticks, at: s4Sticks, rules: .tenhou)
assert(nSticks != nil && tSticks == .allLastRepeat)

// 4b. West 1 (extension) dealer is Seat 0, tied for 1st with Seat 2 at 31,000 -> Seat 0 IS first (seat-order tie-break) -> ends(.dealerFirst)
let w1 = GamePosition(roundWind: .west, kyoku: 1, honba: 0, sticks: 0, scores: [31_000, 19_000, 31_000, 19_000])
let resW1 = RoundResult(outcome: .exhaustiveDraw(tenpai: [Seat(0)], nagashi: []),
                        deltas: [0, 0, 0, 0], scores: [31_000, 19_000, 31_000, 19_000],
                        sticks: 0, dealer: Seat(0), dealerRepeats: true)
let (nW1, tW1) = GameFlow.next(after: resW1, at: w1, rules: .mahjongSoul)
assert(nW1 == nil && tW1 == .ends(.dealerFirst))

// 4c. West 4 (last hand of extension) dealer repeats with < 30,000 -> continues in West 4
let w4 = GamePosition(roundWind: .west, kyoku: 4, honba: 0, sticks: 0, scores: [25_000, 25_000, 25_000, 25_000])
let resW4Rep = RoundResult(outcome: .exhaustiveDraw(tenpai: [Seat(3)], nagashi: []),
                           deltas: [0, 0, 0, 0], scores: [25_000, 25_000, 25_000, 25_000],
                           sticks: 0, dealer: Seat(3), dealerRepeats: true)
let (nW4, tW4) = GameFlow.next(after: resW4Rep, at: w4, rules: .tenhou)
assert(nW4?.roundWind == .west && nW4?.kyoku == 4 && tW4 == .allLastRepeat)

// 4d. Oka & Uma for Mahjong Soul vs Tenhou
let msRes = GameFlow.result(scores: [32_000, 28_000, 22_000, 18_000], sticks: 0, rules: .mahjongSoul, end: .target)
assert(msRes.adjusted == [22_000, 8_000, -8_000, -22_000])
let thRes = GameFlow.result(scores: [32_000, 28_000, 22_000, 18_000], sticks: 0, rules: .tenhou, end: .target)
assert(thRes.adjusted == [42_000, 8_000, -18_000, -32_000])
assert(thRes.adjusted.reduce(0, +) == 0)

print("All Swift repros and §5 sanity checks completed.")
