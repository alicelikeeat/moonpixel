import XCTest
@testable import MoonPixelCore

/// The four realms: copies of the ground below, glass elevators, domes in the sea, sky nations, and trade,
/// migration and war between them.
final class RealmsTests: XCTestCase {
    let day = MP.daySeconds

    func nation(_ c: Civ, _ kind: String, at rx: Int, _ ry: Int, adults: Int = 80) -> CivCity {
        c.underNations = true
        let n = c.newPolity(origin: kind, near: nil)
        switch kind {
        case "underground": c.polities[n]!.underground = true
        case "undersea": c.polities[n]!.undersea = true
        case "sky": c.polities[n]!.sky = true
        default: break
        }
        var r = c.regions[MP.chunkKey(rx, ry)] ?? { var r = CivRegion(); r.rx = rx; r.ry = ry; r.land = 1; r.fertility = 0.6; return r }()
        r.skySeen = true
        c.regions[r.key] = r
        let city = c.newCity(at: r.key, nation: n, people: CivPeople(adults: adults, children: adults / 4), firstCount: true,
                              under: kind == "underground", sea: kind == "undersea", sky: kind == "sky")
        city.facilities = ["farm": adults / 3, "house": adults / 4, "well": 1]
        city.stock = ["grain": kind == "sky" ? 2000 : 30]
        if kind == "underground" { city.stock["ore"] = 90; city.stock["stone"] = 90 }
        c.polities[n]!.capital = city.id
        return city
    }

    func testOnlyTheNationsOfTheGroundGoToWar() {
        let s = makeSociety(5)
        let c = s.civ
        let a = nation(c, "first", at: 50, 50), b = nation(c, "first", at: 52, 50)
        let u = nation(c, "underground", at: 54, 50), v = nation(c, "underground", at: 56, 50)
        let sea = nation(c, "undersea", at: 58, 50), sky = nation(c, "sky", at: 60, 50)
        c.declare(a.nation, on: b.nation)
        XCTAssertTrue(c.atWar(a.nation, b.nation), "the ground fights the ground")
        for (x, y) in [(a, u), (u, v), (a, sea), (a, sky), (u, sky), (sky, sea), (sky, a)] {
            c.declare(x.nation, on: y.nation)
            XCTAssertFalse(c.atWar(x.nation, y.nation), "no war with or between the realms off the ground")
        }
        XCTAssertTrue(c.polities[a.nation]!.onSurface)
        XCTAssertFalse(c.polities[u.nation]!.onSurface); XCTAssertFalse(c.polities[sea.nation]!.onSurface); XCTAssertFalse(c.polities[sky.nation]!.onSurface)
    }

    func testTheRealmsTradeAndMovePeopleByAirShipElevatorAndTrain() {
        let s = makeSociety(5)
        let c = s.civ
        let ground = nation(c, "first", at: 50, 50), under = nation(c, "underground", at: 51, 50)
        let sea = nation(c, "undersea", at: 53, 52), sky = nation(c, "sky", at: 50, 53)
        let under2 = nation(c, "underground", at: 49, 48)
        XCTAssertEqual(c.realmWay(from: ground, to: sky)?.mode, "air")
        XCTAssertEqual(c.realmWay(from: sea, to: under)?.mode, "ship")
        XCTAssertEqual(c.realmWay(from: ground, to: under)?.mode, "lift")
        XCTAssertEqual(c.realmWay(from: under, to: under2)?.mode, "rail")
        XCTAssertNil(c.realmWay(from: ground, to: ground))
        XCTAssertLessThan(c.realmWay(from: ground, to: sky)!.days, c.realmWay(from: ground, to: under)!.days + 2, "planes are quick")
        // a fortnight: each realm makes its own goods and sells them to the others
        for _ in 0..<20 { c.realmsDaily(); c.resourcesDailyForTests() }
        let modes = Set(c.tradeRoutes.compactMap { $0.mode })
        XCTAssertTrue(modes.contains("air"), "the sky's grain flies: \(modes)")
        XCTAssertTrue(modes.contains("ship"), "the sea floor's fish sails: \(modes)")
        XCTAssertTrue(modes.contains("lift") || modes.contains("rail"), "the underground's ore goes up the elevators or along the trains: \(modes)")
        XCTAssertGreaterThan((ground.stock["fish"] ?? 0) + (under.stock["fish"] ?? 0) + (sky.stock["fish"] ?? 0), 0, "fish arrived from the sea floor")
        XCTAssertGreaterThan((ground.stock["ore"] ?? 0) + (sea.stock["ore"] ?? 0) + (sky.stock["ore"] ?? 0), 0, "ore arrived from below")
        XCTAssertFalse(c.realmTraffic().isEmpty)
        // a crowded city sends people to another realm
        under2.people.add(CivPeople(adults: 400)); under2.crowding = 1.4
        for c2 in [ground, sea, sky] { c2.crowding = 0.3; c2.foodDays = 40 }
        for _ in 0..<Int(RealmTune.moveEvery) + 1 { c.day += 1; c.realmsDaily() }
        let moving = c.trips.values.filter { $0.from == under2.id && $0.mode != nil }
        XCTAssertFalse(moving.isEmpty, "people set out for another realm")
        let before = moving.first.flatMap { c.cities[$0.to]?.pop } ?? 0
        let to = moving.first!.to
        for _ in 0..<6 { c.tripsDaily() }
        XCTAssertGreaterThan(c.cities[to]!.pop, before, "and arrive")
    }

    func testSkyIslandsAreNationsAndTheirElevatorGoesDown() {
        let s = makeSociety(21)
        let gen = s.world.gen
        var found: (Int, Int)?
        for cy in -60...60 where found == nil { for cx in -60...60 where found == nil && gen.isSkyCity(cx, cy) { found = (cx, cy) } }
        guard let (cx, cy) = found else { return XCTFail("a sky island") }
        let c = s.civ
        c.underNations = true
        let rc = c.cfg.regionTiles / 32
        let key = MP.chunkKey(OpenWorld.floorDiv(cx, rc), OpenWorld.floorDiv(cy, rc))
        c.regions[key] = Civ.survey(gen, MP.keyCX(key), MP.keyCY(key), size: c.cfg.regionTiles)
        c.foundSky(key, gen: gen)
        guard let city = c.skyCities().first else { return XCTFail("a sky nation") }
        XCTAssertTrue(c.polities[city.nation]!.sky == true)
        XCTAssertEqual(city.skyAt?.0, cx); XCTAssertEqual(city.skyAt?.1, cy)
        XCTAssertEqual(city.nameZh, gen.skyCityName(cx, cy, zh: true))
        c.foundSky(key, gen: gen)
        XCTAssertEqual(c.skyCities().count, 1, "once")
        // its glass elevator: from the island's plaza to the ground under it and back
        let lift = TilePos(cx * 32 + 16, cy * 32 + 16)
        XCTAssertEqual(s.skyWorld().tile(2, lift.x, lift.y), s.content.tid("glass_lift"))
        XCTAssertTrue(s.liftFloors(at: lift).contains { $0.depth == SkyTune.depth })
        s.realm.player.depth = SkyTune.depth
        XCTAssertNotNil(s.rideLift(at: lift, to: 0))
        XCTAssertEqual(s.realm.player.depth, 0)
        XCTAssertEqual(s.world.tile(2, lift.x, lift.y), s.content.tid("glass_lift"), "a landing on the ground")
        XCTAssertFalse(s.content.water[Int(s.world.tile(0, lift.x, lift.y + 1))], "dry floor to step out on")
        XCTAssertNotNil(s.rideLift(at: lift, to: SkyTune.depth))
        XCTAssertEqual(s.realm.player.depth, SkyTune.depth)
        // a sky nation's city is in the teleport list, on its island
        XCTAssertTrue(s.teleportTargets(from: lift, zh: true).contains { $0.group == .sky && $0.name.contains(city.nameZh) && $0.depth == SkyTune.depth })
    }

    func testTheSeaSwimsRoundTheDomesOfTheSeaFloor() {
        let s = makeSociety(9)
        let c = s.civ
        c.underNations = true
        let city = nation(c, "undersea", at: 40, 40)
        city.underAt = (320, 320); city.dug = 64
        s.underlandCache = nil
        let u = s.underworld()
        let ct = s.content
        XCTAssertEqual(u.tile(2, 320 * 32 + 16, 320 * 32 + 16), ct.tid("glass_lift"))
        // the sea round the dome, beyond the city's chunks too
        let z = s.underlandZones().first { $0.sea }!
        let beyond = Int(z.r.rounded(.up)) + 1
        XCTAssertNotNil(s.seaHalo(320 + beyond, 320))
        XCTAssertEqual(u.chunk(320 + beyond, 320).layers[0][16 * 32 + 16], ct.tid("water"))
        // creatures swim past, in the water only, and move with time
        let p = Vec2(Double(320 * 32 + 16) * 16, Double(320 * 32 + 16) * 16)
        let now = s.domeLife(around: p, time: 100), later = s.domeLife(around: p, time: 160)
        XCTAssertGreaterThan(now.count, 5, "a sea full of life")
        for a in now { XCTAssertTrue(ct.water[Int(u.tile(0, a.pos.tile.x, a.pos.tile.y))], a.species.key) }
        XCTAssertGreaterThan(Set(now.map { $0.species.key }).count, 2, "of several kinds")
        let moved = now.filter { a in later.contains { $0.id == a.id && $0.pos.distance(to: a.pos) > 4 } }
        XCTAssertFalse(moved.isEmpty, "they swim")
        XCTAssertTrue(s.liftFloors(at: TilePos(320 * 32 + 16, 320 * 32 + 16)).contains { $0.depth == 1 && $0.zh == "海底城" })
    }

    func testBelowIsACopyOfTheGroundAbove() {
        let s = makeSociety(7)
        let c = s.civ
        c.underNations = true
        // a house built on the ground (its walls round a room, a door), then a city digs under it
        let (tx, ty) = (301, 300)
        let wall = s.content.tid("wall_brick")
        let ox = tx * 32, oy = ty * 32
        for y in 2...8 { for x in 2...10 where x == 2 || x == 10 || y == 2 || y == 8 { s.world.setTile(2, ox + x, oy + y, wall) } }
        for y in 2...8 { for x in 2...10 { s.world.setTile(0, ox + x, oy + y, s.content.tid("wood_floor")) } }
        s.world.setTile(2, ox + 6, oy + 8, s.content.tid("door_wood"))
        let city = nation(c, "underground", at: 70, 70)
        city.underAt = (tx - 1, ty); city.dug = 90
        s.underlandCache = nil
        let above = s.world.chunk(tx, ty), below = s.underworld().chunk(tx, ty)
        var built = 0, same = 0
        for k in 0..<MP.chunkArea {
            let o = above.layers[2][k]
            guard o != 0, let t = s.content.tile(o), t.built, t.solid else { continue }
            built += 1
            if below.layers[2][k] == o && below.layers[0][k] == above.layers[0][k] { same += 1 }
        }
        XCTAssertGreaterThan(built, 12, "the house on the ground")
        XCTAssertGreaterThan(same, built * 3 / 4, "the same house below: \(same) of \(built)")
        XCTAssertEqual(below.layers[2][8 * 32 + 6], s.content.tid("door_wood"), "with its door")
        // the glass elevator over the city's middle is put on the ground
        XCTAssertGreaterThanOrEqual(s.placeGroundLifts(around: TilePos((tx - 1) * 32, ty * 32)), 0)
        let lift = TilePos((tx - 1) * 32 + RealmLift.x, ty * 32 + RealmLift.y)
        let o = s.world.tile(2, lift.x, lift.y)
        XCTAssertTrue(o == s.content.tid("glass_lift") || s.content.tile(o)?.built == true, "an elevator, unless something was built there")
    }
}

extension Civ {
    /// The day's trade shipping (without envoys or spies), for tests.
    func resourcesDailyForTests() { tradeChoices(); shipping(); time += MP.daySeconds }
}
