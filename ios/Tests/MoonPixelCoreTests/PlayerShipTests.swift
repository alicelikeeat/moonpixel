import XCTest
@testable import MoonPixelCore

/// The traveller builds ships from the pack: a ferry, a liner, a freighter, an aircraft carrier.
final class PlayerShipTests: XCTestCase {
    func testTheCarrierIsAShipWithADeck() {
        let k = VehicleKind.carrier
        XCTAssertEqual(k.mode, .water)
        XCTAssertEqual(k.name(zh: true), "航空母舰")
        XCTAssertGreaterThan(k.spec.length, VehicleKind.freighter.spec.length)
        XCTAssertGreaterThan(k.spec.draft, VehicleKind.freighter.spec.draft)
        XCTAssertFalse(Figure3D.vehicle(k).isEmpty)
        XCTAssertEqual(Society.playerShips, [.ferry, .liner, .freighter, .carrier])
    }
}

extension PlayerShipTests {
    func testAFerryIsBuiltFromThePackOnTheNearestWater() {
        let (sc, _, _) = TransportScene.portScene()
        let s = sc.s
        // on the bank, a few tiles from the river
        s.realm.player.body = Body(at: sc.t(70, 60).center, z: 0, depth: 0)
        let (none, why) = s.buildShipNear(.ferry)
        XCTAssertNil(none); XCTAssertEqual(why, "materials", "nothing is made from nothing")
        sc.give(VehicleKind.ferry.spec.build, .pack)
        let (v, why2) = s.buildShipNear(.ferry)
        XCTAssertNil(why2)
        guard let ferry = v else { return XCTFail("no ferry") }
        XCTAssertEqual(ferry.kind, .ferry)
        XCTAssertTrue(s.passable(NetNode(ferry.tile.x, ferry.tile.y, 0), s.profile(.ferry)), "afloat")
        XCTAssertEqual(ferry.owner, .pack)
        XCTAssertEqual(s.carried("iron"), 0, accuracy: 1e-9, "paid for once")
        // far from any water: no ship
        s.realm.player.body = Body(at: sc.t(15, 70).center, z: 0, depth: 0)
        sc.give(VehicleKind.ferry.spec.build, .pack)
        XCTAssertEqual(s.buildShipNear(.ferry, reach: 8).1, "no_water")
        // a carrier costs far more than a ferry's materials
        s.realm.player.body = Body(at: sc.t(70, 60).center, z: 0, depth: 0)
        XCTAssertEqual(s.buildShipNear(.carrier).1, "materials")
    }
}

/// Coastal cities build a harbour and open shipping lines (abroad only at peace).
extension PlayerShipTests {
    func testCoastalCitiesBuildHarboursAndOpenAShippingLine() {
        var sc = TransportScene()
        sc.cities()
        let s = sc.s
        func step(_ d: District, _ n: Int = 6) { for _ in 0..<n { s.planShipping(d); for site in s.realm.transport.sites where site.finished == nil { s.finishSite(site.id) } } }
        // a third town on the river's west bank (the west city's nearest water is a lake beyond the scene)
        // (and two towns on its banks; the east city's nearest water lies beyond the scene too)
        let c = s.foundDistrict(name: "Bank", at: sc.t(62, 70), nation: 1, money: 100_000, store: ["stone": 500, "planks": 500, "iron": 500, "parts": 500, "fuel": 2000])
        let e = s.foundDistrict(name: "Ford", at: sc.t(94, 70), nation: 1, money: 100_000, store: ["stone": 500, "planks": 500, "iron": 500, "parts": 500, "fuel": 2000])
        c.autoBuild = false; e.autoBuild = false
        step(sc.a); step(c); step(e)
        guard let pa = s.seaPort(sc.a), let pb = s.seaPort(e), let pc = s.seaPort(c) else { return XCTFail("harbours: \(sc.a.events.suffix(4)) / \(e.events.suffix(4)) / \(c.events.suffix(4))") }
        XCTAssertGreaterThanOrEqual(s.waterDepth(pb.tile), 1.5)
        XCTAssertTrue(s.quayBeside(pb.tile) && s.quayBeside(pc.tile), "each on the water by its quay")
        // the lake has no way to the river: no line from the west city, and it is not tried again
        step(sc.a, 2)
        XCTAssertFalse(s.realm.transport.lines.contains { $0.stops.contains(pa.id) }, "no line where no ship can sail")
        XCTAssertTrue(sc.a.events.contains { $0.contains("no sea way") })
        step(c, 1)
        let line = s.realm.transport.lines.first { $0.kind.mode == .water && $0.stops.contains(pb.id) && $0.stops.contains(pc.id) }
        XCTAssertNotNil(line, "a sea line between the two river harbours")
        XCTAssertEqual(line?.kind, .ferry, "a ferry between two near cities of one nation")
        XCTAssertEqual(line?.vehicles.count, 1)
        // once is enough: the next step opens no second passenger line
        step(c, 2)
        XCTAssertEqual(s.realm.transport.lines.filter { $0.kind.mode == .water && !$0.freight }.count, 1)
    }
}
