// Tiles, counts, seats and table melds.

import Testing
@testable import Riichi

@Suite struct CountsTests {
    @Test func inlineStorage() {
        var c = Counts()
        #expect(c.total == 0 && c.kinds.isEmpty)
        c[Kind(0)] = 4
        c[Kind(8)] = 15
        c[Kind(33)] = 1
        #expect(c[Kind(0)] == 4 && c[Kind(8)] == 15 && c[Kind(33)] == 1 && c[Kind(9)] == 0)
        #expect(c.total == 20)
        #expect(c.kinds == [Kind(0), Kind(8), Kind(33)])
        c[Kind(8)] = 0
        #expect(c.adding(Kind(9))[Kind(9)] == 1 && c.removing(Kind(0))[Kind(0)] == 3)
        #expect(Counts(t("1122z0m5m")) == Counts([Kind(27), Kind(27), Kind(28), Kind(28), Kind(4), Kind(4)]))
        #expect(c.count(where: { $0 > 0 }) == 2)
    }

    @Test func fifthCopyIsRepresentable() {
        let c = Counts(t("1111z")).adding(Kind(.honor, 1))
        #expect(c[Kind(.honor, 1)] == 5)
        // Structural shanten of a 14-tile hand holding a fifth copy still works.
        #expect(standardShanten(Counts(t("234567789m11111z")), meldCount: 0) == -1)
    }
}

@Suite struct TileTests {
    @Test func mpszRoundTrip() {
        #expect(mpsz(t("5m0m123p77z")) == "05m123p77z")
        #expect(mpsz([]) == "-")
        #expect(parseTiles("8z") == nil && parseTiles("0z") == nil && parseTiles("12") == nil)
    }

    @Test func meldValidation() {
        #expect(Meld(kind: .chi, tiles: t("435m"))?.tiles == t("345m"))
        #expect(Meld(kind: .chi, tiles: t("891m")) == nil)
        #expect(Meld(kind: .chi, tiles: t("123z")) == nil)
        #expect(Meld(kind: .pon, tiles: t("550m")) != nil)
        #expect(Meld(kind: .pon, tiles: t("005m")) == nil)  // two reds
        #expect(Meld(kind: .ankan, tiles: t("111m")) == nil)
    }

    @Test func kuikae() {
        func forbidden(_ chi: String, took: String) -> [Kind] {
            Meld(kind: .chi, tiles: t(chi))!.kuikaeForbidden(took: t1(took).kind).sorted()
        }
        #expect(forbidden("456m", took: "4m") == [Kind(.man, 4), Kind(.man, 7)])
        #expect(forbidden("456m", took: "6m") == [Kind(.man, 3), Kind(.man, 6)])
        #expect(forbidden("456m", took: "5m") == [Kind(.man, 5)])
        #expect(forbidden("123m", took: "3m") == [Kind(.man, 3)])
        #expect(forbidden("789m", took: "7m") == [Kind(.man, 7)])
        #expect(Meld(kind: .pon, tiles: t("055m"))!.kuikaeForbidden(took: Kind(.man, 5)) == [Kind(.man, 5)])
    }
}

@Suite struct SeatTests {
    @Test func arithmetic() {
        let s = Seat(1)
        #expect(s.next == Seat(2) && Seat(3).next == Seat(0))
        #expect(s.advanced(by: -2) == Seat(3) && s.advanced(by: 7) == Seat(0))
        #expect(Seat(0).distance(from: Seat(1)) == 3)  // seat 0 is seat 1's kamicha
        #expect(Seat(2).distance(from: Seat(1)) == 1)
        #expect(Seat(1).wind(dealer: Seat(1)) == .east && Seat(0).wind(dealer: Seat(1)) == .north)
        #expect(Seat.all.map(\.index) == [0, 1, 2, 3])
    }
}

@Suite struct TableMeldTests {
    @Test func chi() throws {
        let m = try #require(TableMeld.chi(taken: t1("0m"), from: Seat(3), using: t("46m")))
        #expect(m.kind == .chi && m.tiles == t("40m6m") && m.from == Seat(3))
        #expect(m.consumed == t("46m"))
        #expect(m.meld == Meld(kind: .chi, tiles: t("406m")))
        #expect(m.kuikaeForbidden == [Kind(.man, 5)])
        #expect(TableMeld.chi(taken: t1("1m"), from: Seat(3), using: t("46m")) == nil)
    }

    @Test func addedKanKeepsThePonHistory() throws {
        let pon = try #require(TableMeld.pon(taken: t1("0p"), from: Seat(2), using: t("55p")))
        #expect(pon.consumed == t("55p") && pon.kuikaeForbidden == [Kind(.pin, 5)])
        let kan = try #require(pon.adding(t1("5p")))
        #expect(kan.kind == .shouminkan && kan.taken == t1("0p") && kan.from == Seat(2))
        #expect(kan.added == t1("5p") && kan.tiles == t("0555p"))
        #expect(kan.consumed == t("055p"))  // mjai kakan: the three pon tiles
        #expect(kan.meld.kind == .shouminkan && kan.kuikaeForbidden.isEmpty)
        #expect(pon.adding(t1("6p")) == nil && kan.adding(t1("5p")) == nil)
    }

    @Test func kans() throws {
        let open = try #require(TableMeld.daiminkan(taken: t1("9s"), from: Seat(0), using: t("999s")))
        #expect(open.consumed == t("999s") && open.meld.isOpen)
        let closed = try #require(TableMeld.ankan(t("1111z")))
        #expect(closed.taken == nil && closed.from == nil && !closed.meld.isOpen)
        #expect(closed.consumed == t("1111z"))
        #expect(TableMeld.ankan(t("111z")) == nil)
    }
}
