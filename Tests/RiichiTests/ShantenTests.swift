// Shanten from several threads at once.

import Testing
@testable import Riichi

/// A deterministic spread of 14-tile hands drawn from seeded walls.
func sampleHands(_ n: Int) -> [Counts] {
    (0..<n).map { i in Counts(Wall(seed: UInt64(i), hand: 0).tiles.prefix(14).map(\.kind)) }
}

@Suite struct ShantenTests {
    @Test func knownValues() {
        #expect(shanten(Counts(t("123m456p789s1122z")), meldCount: 0).min == 0)
        #expect(shanten(Counts(t("19m19p19s1234567z")), meldCount: 0).kokushi == 0)
        #expect(shanten(Counts(t("113355779m1133z")), meldCount: 0).chiitoi == 0)
        #expect(standardShanten(Counts(t("123m456p789s11z")), meldCount: 1) == -1)
        // Nine distinct isolated tiles and more: the worst case is 8.
        #expect(standardShanten(Counts(t("147m258p369s1234z")), meldCount: 0) == 8)
    }

    @Test func concurrentCallsAgreeWithSerial() async {
        let hands = sampleHands(400)
        let serial = hands.map { shanten($0, meldCount: 0) }
        let results = await withTaskGroup(of: (Int, [ShantenResult]).self) { group in
            for worker in 0..<8 {
                group.addTask {
                    // Each worker walks the hands in a different order.
                    let order = (0..<hands.count).map { ($0 * 7 + worker * 13) % hands.count }
                    var out = [ShantenResult?](repeating: nil, count: hands.count)
                    for i in order { out[i] = shanten(hands[i], meldCount: 0) }
                    return (worker, out.map { $0! })
                }
            }
            var all: [[ShantenResult]] = []
            for await (_, r) in group { all.append(r) }
            return all
        }
        #expect(results.count == 8)
        for r in results { #expect(r == serial) }
    }
}
