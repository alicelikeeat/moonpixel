import XCTest
@testable import MoonPixelCore

/// Sky cities, the air network (planes and saucers), and the teleport centre.
final class SkyTests: XCTestCase {
    func firstSky(_ s: Society) -> (name: String, cx: Int, cy: Int) {
        let list = s.skyCities(near: TilePos(0, 0), within: 60, zh: true)
        XCTAssertFalse(list.isEmpty)
        return list[0]
    }

    func testASkyCityFloatsOnItsStoreyWithAPlazaAnAirportAndAWayDown() {
        let s = makeSociety(21)
        let c = firstSky(s)
        XCTAssertTrue(s.world.gen.isSkyCity(c.cx, c.cy))
        let w = s.skyWorld()
        let ct = s.content
        let home = w.chunk(c.cx, c.cy)
        XCTAssertEqual(home.layers[2][16 * 32 + 16], ct.tid("stairs_down"), "the way down in its plaza")
        XCTAssertTrue(home.layers[0].contains(ct.tid("grass")) || home.layers[0].contains(ct.tid("stone_floor")))
        let port = w.chunk(c.cx + 1, c.cy)
        XCTAssertTrue(port.layers[1].contains(ct.tid("runway")), "a runway")
        XCTAssertTrue(port.layers[0].contains(ct.tid("ufo_pad")), "a UFO pad")
        // the edge of the island is fenced; beyond it, open air
        let far = w.chunk(c.cx + 4, c.cy)
        XCTAssertTrue(far.layers[0].allSatisfy { $0 == 0 }, "open air off the island")
        var fenced = false
        for y in 0..<32 { for x in 0..<32 where w.chunk(c.cx + 2, c.cy).layers[2][y * 32 + x] == ct.tid("fence") { fenced = true } }
        XCTAssertTrue(fenced, "a fence round its edge")
        XCTAssertFalse(s.skyFolk(center: Vec2(Double(c.cx * 32) * 16, Double(c.cy * 32) * 16), halfW: 1200, halfH: 1200).isEmpty, "its people")
        // the stairway down comes out on the ground right below
        _ = s.place(at: TilePos(c.cx * 32 + 16, c.cy * 32 + 17), depth: SkyTune.depth)
        XCTAssertEqual(s.realm.player.depth, SkyTune.depth)
        let down = s.useStairs(at: TilePos(c.cx * 32 + 16, c.cy * 32 + 16).center)
        XCTAssertEqual(down?.depth, 0)
        XCTAssertLessThan(abs((down?.pos.tile.x ?? 0) - (c.cx * 32 + 16)), 30)
    }

    func testPlanesAndSaucersFlyBetweenAirportsUfoPortsAndSkyCities() {
        let s = makeSociety(22)
        let c = firstSky(s)
        let hubs = s.airHubs(around: TilePos(0, 0), within: 60, zh: true)
        XCTAssertTrue(hubs.contains { $0.kind == .sky })
        let ufo = hubs.first { $0.kind == .ufo }
        // away from every airport: no flight
        _ = s.place(at: TilePos(c.cx * 32 + 16, c.cy * 32 + 18), depth: SkyTune.depth)
        _ = s.place(at: TilePos(5000, 5000), depth: 0)
        if s.airHubHere(zh: true) == nil { XCTAssertNil(s.airTravel(to: hubs[0], by: .ufo, zh: true)) }
        // from the sky city's airport: by plane to an airfield or by saucer to a UFO airport
        _ = s.place(at: Society.skyArrival(c.cx, c.cy, by: .airport), depth: SkyTune.depth)
        guard let here = s.airHubHere(zh: true) else { return XCTFail("the sky city's airport is a place of the network") }
        XCTAssertEqual(here.kind, .sky)
        if let u = ufo {
            XCTAssertNil(s.airTravel(to: u, by: .plane, zh: true), "no runway at a UFO airport")
            let r = s.airTravel(to: u, by: .ufo, zh: true)
            XCTAssertNotNil(r)
            XCTAssertEqual(r?.depth, 0)
            XCTAssertEqual(s.realm.player.depth, 0)
            XCTAssertGreaterThan(r?.km ?? 0, 0)
            // and back up by saucer to the sky city's pad
            let back = s.airTravel(to: hubs.first { $0.kind == .sky && $0.name.hasPrefix(c.name) }!, by: .ufo, zh: true)
            XCTAssertEqual(back?.depth, SkyTune.depth)
            XCTAssertEqual(s.skyWorld().tile(0, back!.pos.tile.x, back!.pos.tile.y), s.content.tid("ufo_pad"))
        }
    }

    func testTeleportAnywhereFromAnyLayerAndRememberPlaces() {
        let s = makeSociety(23)
        let c = firstSky(s)
        let targets = s.teleportTargets(from: TilePos(0, 0), zh: true)
        for g in [TeleportTarget.Group.city, .sky, .air] { XCTAssertTrue(targets.contains { $0.group == g }, "\(g)") }
        let sky = targets.first { $0.group == .sky }!
        XCTAssertNotNil(s.teleport(to: sky))
        XCTAssertEqual(s.realm.player.depth, SkyTune.depth)
        s.saveWaypoint("云上")
        // from the sky straight underground, then to the surface
        XCTAssertNotNil(s.teleport(to: TeleportTarget(group: .under, name: "下", tile: TilePos(c.cx * 32, c.cy * 32 + 600), depth: 1, detail: "")))
        XCTAssertEqual(s.realm.player.depth, 1)
        let town = targets.first { $0.group == .city }!
        XCTAssertNotNil(s.teleport(to: town))
        XCTAssertEqual(s.realm.player.depth, 0)
        let again = s.teleportTargets(from: TilePos(0, 0), zh: true)
        XCTAssertEqual(again.first { $0.group == .saved }?.name, "云上")
        XCTAssertEqual(again.filter { $0.group == .recent }.count, 3, "the last places, newest first")
        XCTAssertEqual(again.first { $0.group == .recent }?.name, town.name)
        // saved places survive saving
        let data = try! JSONEncoder().encode(s.realm)
        let back = try! JSONDecoder().decode(Realm.self, from: data)
        XCTAssertEqual(back.waypoints?.first?.name, "云上")
    }
}
