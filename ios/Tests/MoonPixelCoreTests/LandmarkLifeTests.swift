import XCTest
@testable import MoonPixelCore

/// Landmarks are lived in, built onto, and can be taken down in part.
final class LandmarkLifeTests: XCTestCase {
    func capital(_ s: Society) -> (Settlement, Int) {
        if let n = s.realm.nations.first(where: { s.capital(of: $0.id) != nil }) { return (s.capital(of: n.id)!, n.id) }
        let n = s.realm.nations.first { $0.exileSince == nil }!
        let t = s.settlements.values.filter { !$0.abandoned && $0.nation == n.id }.min { $0.id < $1.id } ?? s.settlements.values.min { $0.id < $1.id }!
        t.nation = n.id
        s.setCapital(n.id, t, kind: "test", cause: "test")
        return (s.capital(of: n.id)!, n.id)
    }

    func testTheHomelessMoveIntoALandmarksBedsAndSleepThere() {
        let s = makeSociety(71)
        let (cap, n) = capital(s)
        guard let m = s.raiseMonument(.pagoda, near: cap, nation: n) else { return XCTFail("no room") }
        let i = s.realm.monuments!.firstIndex { $0.id == m.id }!
        XCTAssertEqual(s.landmarkBeds(i).count, 3, "the keepers' lodge has three beds")
        let homeless = cap.members.compactMap { s.agents[$0] }.filter { $0.legion == nil }.prefix(3)
        for a in homeless { a.home = -1; a.partner = 0; a.children = [] }
        s.landmarkHomesDaily()
        let m2 = s.realm.monuments![i]
        XCTAssertEqual(s.landmarkLiving(m2).residents, 3)
        for a in homeless {
            XCTAssertEqual(a.home, -3, "lives in the landmark")
            XCTAssertNotNil(a.bedAt)
            XCTAssertEqual(s.world.tile(2, a.bedAt![0], a.bedAt![1]), s.content.tid("bed"))
        }
        XCTAssertTrue(WorldMap.describe(s, m2.center, zh: true).contains("住户 3/3"))
    }

    func testTheTownBuildsInsideALandmarkAndPartsComeDownWhole() {
        let s = makeSociety(72)
        let (cap, n) = capital(s)
        guard let m = s.raiseMonument(.pagoda, near: cap, nation: n) else { return XCTFail("no room") }
        let i = s.realm.monuments!.firstIndex { $0.id == m.id }!
        cap.wood = 500; cap.stone = 500
        // a few days on: houses inside it, with beds
        for d in 0..<9 { s.world.time = Double(d) * MP.daySeconds + 1; s.landmarkBuildDaily() }
        var m2 = s.realm.monuments![i]
        XCTAssertGreaterThan((m2.annexes ?? []).count, 0, "the town built inside the landmark")
        let a = m2.annexes![0]
        XCTAssertEqual(a.kind, "house")
        XCTAssertEqual(s.world.tile(2, a.x, a.y), s.content.tid("wall_brick"))
        XCTAssertGreaterThan(m2.beds?.count ?? 0, 3, "its beds join the landmark's")
        // someone moves into it, then it is taken down: they are homeless again, the walls are gone
        let who = cap.members.compactMap { s.agents[$0] }.first { $0.legion == nil }!
        who.home = -1; who.partner = 0; who.children = []
        let bedsBefore = m2.beds!.count
        var list = s.realm.monuments!; list[i].beds = [[a.x + 1, a.y + 1]] + (list[i].beds ?? []).filter { $0 != [a.x + 1, a.y + 1] }; s.realm.monuments = list
        s.landmarkHomesDaily()
        XCTAssertEqual(who.bedAt ?? [], [a.x + 1, a.y + 1])
        let stone = s.carried("stone")
        let what = s.demolishLandmarkPart(at: TilePos(a.x + 2, a.y + 2))
        XCTAssertNotNil(what)
        XCTAssertTrue(what!.contains("民居") || what!.contains("house"))
        m2 = s.realm.monuments![i]
        XCTAssertEqual(s.world.tile(2, a.x, a.y), 0, "its walls came down")
        XCTAssertEqual(m2.beds!.count, bedsBefore - 4)
        XCTAssertEqual(who.home, -1, "homeless again")
        XCTAssertGreaterThan(s.carried("stone"), stone, "some stone back")
        // the pagoda itself is one piece: its tower is not taken down by a tap
        XCTAssertNil(s.demolishLandmarkPart(at: m2.center))
    }

    func testAPartOfThePalaceCityComesDownAndLeavesTheView() {
        let s = makeSociety(73)
        let (cap, n) = capital(s)
        guard let m = s.raiseMonument(.palace, near: cap, nation: n) else { return XCTFail("no room") }
        let i = s.realm.monuments!.firstIndex { $0.id == m.id }!
        XCTAssertGreaterThan(s.landmarkBeds(i).count, 100, "the courtyard houses are homes")
        let court = Palace.courts[0]
        let before = Figure3D.livePieces(for: s.realm.monuments![i]).count
        let what = s.demolishLandmarkPart(at: TilePos(m.x + court.x + 10, m.y + court.z + 5))
        XCTAssertEqual(what?.contains("四合院") ?? false || what?.contains("courtyard") ?? false, true, what ?? "nil")
        let m2 = s.realm.monuments![i]
        XCTAssertEqual(Figure3D.livePieces(for: m2).count, before - 1, "its model is gone")
        XCTAssertEqual(s.world.tile(2, m.x + court.x + 6, m.y + court.z + 3), 0, "its walls are gone")
        XCTAssertEqual(m2.removed?.count, 1)
        XCTAssertLessThan(m2.beds!.count, s.landmarkBeds(i).count + 1)
        // what stands still is drawn; saved and loaded, it stays down
        let back = try! JSONDecoder().decode(Monument.self, from: JSONEncoder().encode(m2))
        XCTAssertEqual(back.removed, m2.removed)
    }
}
