import XCTest
@testable import MoonPixelCore

/// The number of nations is whatever the world makes it: one village is one nation, nothing is invented
/// to reach three, and a nation with any id flies a flag.
final class NationCountTests: XCTestCase {
    func testOneVillageIsOneNationAndNoWarIsMadeUp() {
        let s = makeSociety(8, villages: 1, per: 30)
        XCTAssertEqual(s.realm.nations.count, 1, "one town, one nation (v2.5 made three)")
        XCTAssertTrue(s.realm.relations.isEmpty, "no one to be at war with")
        runYears(s, 1)
        XCTAssertEqual(s.realm.counts.wars, 0)
        XCTAssertEqual(s.audit(), [])
        XCTAssertGreaterThan(s.agents.count, 0)
    }

    func testTwoVillagesTwoNations() {
        let s = makeSociety(8, villages: 2, per: 30)
        XCTAssertEqual(s.realm.nations.count, 2)
        XCTAssertEqual(Set(s.settlements.values.compactMap { $0.nation }).count, 2)
    }

    func testARecipeForOneVillageIsKeptAsOne() {
        let r = WorldRecipe.parse("a quiet world with 1 village")
        XCTAssertEqual(r.villages, 1, "no longer raised to three")
    }

    func testAnyNationFliesAFlagAndLaterNationsHaveTheirOwnDevice() {
        let s = makeSociety(8)
        let t = s.settlements.values.sorted { $0.id < $1.id }[0]
        var n = Nation(); n.id = 7; n.nameEn = "Seventh"; n.nameZh = "第七"; n.color = "#40c080"
        s.realm.nations.append(n)
        let pole = s.world.findFree(near: t.center + TilePos(2, -5), maxR: 4)
        s.world.setTile(2, pole.x, pole.y, s.content.tid("banner_1"))
        t.nation = 7
        s.reflag(t)
        XCTAssertEqual(t.flagOf, 7, "v2.5 left nations above 3 without a flag")
        XCTAssertEqual(s.world.tile(2, pole.x, pole.y), s.content.tid("banner_\(Society.bannerTile(7))"))
        func grey(_ b: Bitmap) -> [Bool] { var o: [Bool] = []; var i = 0; while i + 2 < b.px.count { o.append((Int(b.px[i]) + Int(b.px[i + 1]) + Int(b.px[i + 2])) / 3 > 140); i += 4 }; return o }
        let crests = (4...8).map { grey(PixelArt.gateCrest(nation: $0, color: "#808080")) }
        XCTAssertEqual(Set(crests.map { $0.description }).count, 5, "nations 4 to 8 each have their own device, also in grey")
    }

    func testWhenYourNationPassesIntoHistoryYouAreWithoutOne() {
        let s = makeSociety(8)
        let n = s.realm.nations[0].id
        s.playerJoin(n)
        s.carry("wood", 5)
        s.civHourly()
        XCTAssertEqual(s.realm.player.nation, n)
        s.realm.nations[0].status = 2              // the realm owns a detailed nation's state; the layer mirrors it
        s.civHourly()
        XCTAssertEqual(s.civ.polities[n]?.status, .history)
        XCTAssertEqual(s.realm.player.nation, 0, "stateless, not a member of a nation that is gone")
        XCTAssertEqual(s.carried("wood"), 5, "and keeps what they carry")
    }
}
