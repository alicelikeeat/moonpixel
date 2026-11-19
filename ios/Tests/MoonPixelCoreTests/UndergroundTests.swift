import XCTest
@testable import MoonPixelCore

/// Machines of their age, and the nations of the underground.
final class UndergroundTests: XCTestCase {
    let day = MP.daySeconds

    func nation(_ c: Civ, techs: [String], facilities: [String: Int]) -> (Int, CivCity) {
        var r = CivRegion(); r.rx = 0; r.ry = 0; r.land = 0.7; r.water = 0.3; r.fertility = 0.7; c.regions[r.key] = r
        let n = c.newPolity(origin: "first", near: nil)
        c.polities[n]!.techs = techs; c.polities[n]!.treasury = 5000
        let city = c.newCity(at: r.key, nation: n, people: CivPeople(adults: 2000, children: 600, elders: 300), firstCount: true)
        city.facilities = facilities.merging(["farm": 500, "house": 600, "well": 4]) { a, _ in a }
        city.stock = ["grain": 1e6, "steel": 5000, "timber": 5000, "parts": 2000, "engine": 200, "electronics": 1000, "weapons": 200, "core": 40, "armor": 500, "fuel": 1000, "ammo": 1000]
        c.totals.add(\.found, "grain", 1e6)
        c.polities[n]!.capital = city.id
        return (n, city)
    }

    func testAnIndustrialNationBuildsACarrierInPeace() {
        let c = Civ(seed: 1)
        let (n, _) = nation(c, techs: ["farming", "metallurgy", "machining", "steam", "steel", "fishing", "naval_eng"], facilities: ["shipyard": 1])
        XCTAssertEqual(c.era(n), 2)
        c.advance(to: c.time + 3 * day)
        XCTAssertTrue(c.projects.values.contains { $0.nation == n && $0.kind == "carrier" } || c.units.values.contains { $0.nation == n && $0.kind == "carrier" }, "a carrier in the age of industry, at peace")
        XCTAssertTrue(c.wars(of: n).isEmpty)
    }

    func testAnAIAgeNationBuildsFramesAndASkyCarrierAndRaisesAGiantess() {
        let c = Civ(seed: 2)
        let (n, _) = nation(c, techs: CivTech.all.map { $0.key }, facilities: ["frame_works": 2, "sky_yard": 1, "shipyard": 1, "plant": 4, "fusion_plant": 2])
        XCTAssertEqual(c.era(n), 5)
        XCTAssertEqual(CivTech.eraNames[5].1, "人工智能时代")
        c.advance(to: c.time + 2 * day)
        XCTAssertEqual(c.giants.filter { $0.nation == n }.count, 1, "the age of AI raises a giantess, once")
        c.advance(to: c.time + 40 * day)
        let made = Set(c.units.values.filter { $0.nation == n }.map { $0.kind } + c.projects.values.filter { $0.nation == n }.map { $0.kind })
        for k in ["carrier", "frame"] { XCTAssertTrue(made.contains(k), "\(k): \(made.sorted())") }
        XCTAssertTrue(made.contains("shifter") || made.contains("sky_carrier"), "more of the age's machines: \(made.sorted())")
        XCTAssertEqual(c.giants.filter { $0.nation == n }.count, 1)
    }

    func testUndergroundNationsAreFoundAndNeverAtWarWithTheSurface() {
        let gen = Generator(seed: 5)
        let c = Civ(seed: 5); c.underNations = true
        c.discover(around: TilePos(0, 0), radius: 10, gen: gen)
        let under = c.undergroundCities()
        XCTAssertFalse(under.isEmpty, "the underground cities of the known land have nations")
        for city in under {
            XCTAssertEqual(c.polities[city.nation]?.underground, true)
            XCTAssertEqual(c.regions[city.regionKey]?.underCity, city.id)
            XCTAssertNotEqual(c.regions[city.regionKey]?.city, city.id, "it does not take the surface's place")
        }
        let u = under[0].nation
        guard let surface = c.polities.values.first(where: { $0.underground != true && $0.status == .active })?.id else { return XCTFail("no surface nation") }
        c.declare(u, on: surface); c.declare(surface, on: u)
        XCTAssertFalse(c.atWar(u, surface), "no war between the underground and the surface")
        XCTAssertEqual(c.envoyBlocked(surface, u), "other_world")
        c.refreshTerritory()
        XCTAssertNotEqual(c.controller(under[0].regionKey), u, "it holds no land up there")
    }

    func testUndergroundCitiesDigAndFoundTownsUnderTheSeaOnlyWithGlass() {
        let c = Civ(seed: 6); c.underNations = true
        for x in 0...2 { var r = CivRegion(); r.rx = x; r.ry = 0; r.land = x == 2 ? 0 : 1; r.water = x == 2 ? 1 : 0; r.fertility = 0.6; c.regions[r.key] = r }
        let n = c.newPolity(origin: "underground", near: nil); c.polities[n]!.underground = true
        let city = c.newCity(at: MP.chunkKey(1, 0), nation: n, people: CivPeople(adults: 200, children: 50), firstCount: true, under: true)
        city.facilities = ["farm": 80, "house": 60, "well": 3, "mine": 2]; city.stock = ["grain": 1e5, "stone": 50]; c.totals.add(\.found, "grain", 1e5)
        city.underAt = (12, 4); city.dug = 12
        c.polities[n]!.capital = city.id
        c.advance(to: c.time + 20 * day)
        XCTAssertGreaterThan(city.dug, 30, "it digs outward")
        let towns = c.undergroundCities()
        XCTAssertGreaterThan(towns.count, 1, "and founds a new town next door")
        let underSea = towns.first { $0.rx == 2 }
        if let s = underSea { XCTAssertEqual(s.sealed, true, "a town under the sea is sealed behind glass") }
        XCTAssertGreaterThan((city.stock["sea_glass"] ?? 0) + (underSea != nil ? UnderTune.glassForSea : 0), 0, "it made sea glass beside the sea")
        XCTAssertEqual(c.audit(), [])
    }

    func testTheHallIsDugRingByRingAndGlassHoldsTheSea() {
        let s = makeSociety(7)
        let c = s.civ
        c.underNations = true
        let n = c.newPolity(origin: "underground", near: nil); c.polities[n]!.underground = true
        var r = CivRegion(); r.rx = 40; r.ry = 40; r.land = 1; c.regions[r.key] = r
        let city = c.newCity(at: r.key, nation: n, people: CivPeople(adults: 50), firstCount: true, under: true)
        city.underAt = (320, 320); city.dug = 24
        let u = s.underworld()
        let centre = TilePos(320 * 32 + 16, 320 * 32 + 16)
        // a pool of water just outside the city's walls, rock elsewhere
        for dy in -30...30 { for dx in -30...30 { let x = centre.x + dx, y = centre.y + dy
            if dx * dx + dy * dy > 16 * 16 { u.setTile(0, x, y, s.content.tid("cave_floor")); u.setTile(2, x, y, s.content.tid("cave_wall")) } } }
        for dy in -3...3 { for dx in 18...26 { u.setTile(0, centre.x + dx, centre.y + dy, s.content.tid("cave_water")); u.setTile(2, centre.x + dx, centre.y + dy, 0) } }
        let n1 = s.digUnderground(around: centre)
        XCTAssertGreaterThan(n1, 0)
        XCTAssertEqual(city.carved, 24)
        XCTAssertEqual(u.tile(2, centre.x - 20, centre.y), 0, "rock dug out of the hall")
        XCTAssertEqual(u.tile(2, centre.x + 20, centre.y), s.content.tid("wall_glass"), "a glass wall where the hall meets water")
        XCTAssertEqual(s.digUnderground(around: centre), 0, "each ring is dug once")
    }
}
