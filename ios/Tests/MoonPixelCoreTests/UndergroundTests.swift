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

    /// An underground nation with one city at chunk (320, 320) under plain land, `dug` tiles out.
    func underNation(_ s: Society, dug: Double, sea: Bool = false) -> CivCity {
        let c = s.civ
        c.underNations = true
        let n = c.newPolity(origin: sea ? "undersea" : "underground", near: nil)
        if sea { c.polities[n]!.undersea = true } else { c.polities[n]!.underground = true }
        var r = CivRegion(); r.rx = 40; r.ry = 40; r.land = 1; c.regions[r.key] = r
        let city = c.newCity(at: r.key, nation: n, people: CivPeople(adults: 50), firstCount: true, under: !sea, sea: sea)
        city.underAt = (320, 320); city.dug = dug
        return city
    }

    func testTheUnderlandIsOpenLandWithRoadsHousesAndLamps() {
        let s = makeSociety(7)
        _ = underNation(s, dug: 100)                         // a little over three chunks every way
        let u = s.underworld()
        let ct = s.content
        let near = u.chunk(322, 320), far = u.chunk(326, 320)
        let natural = Set(["cave_floor", "cave_water"])
        XCTAssertTrue(near.layers[0].allSatisfy { !natural.contains(ct.tile($0)?.key ?? "") }, "no cave left within reach")
        XCTAssertTrue(near.layers[0].contains(ct.tid("grass")), "grass, as on the surface")
        XCTAssertEqual(near.layers[1][5 * 32 + 15], ct.tid("cobble_road"), "roads in a grid")
        XCTAssertEqual(near.layers[2][14 * 32 + 14], ct.tid("lamp_on"), "lamps for a sky")
        XCTAssertTrue(far.layers[0].contains(ct.tid("cave_floor")) || far.layers[2].contains(ct.tid("cave_wall")), "beyond its reach the cave goes on")
        // the town, the farms and the parks: across the reach there are houses, fields and trees
        var kinds = Set<String>()
        for y in 317...323 { for x in 317...323 { for id in u.chunk(x, y).layers[2] { kinds.insert(ct.tile(id)?.key ?? "") } } }
        XCTAssertTrue(kinds.contains("bed"), "houses")
        XCTAssertTrue(kinds.contains("wheat_2") || kinds.contains("tree_oak") || kinds.contains("tree_willow"), "fields or parks: \(kinds.sorted())")
        // the light down there is the nation's own: bright by day, dimmed at night; none outside the underland
        s.world.time = MP.daySeconds * 0.5
        XCTAssertEqual(s.underSky(at: TilePos(322 * 32, 320 * 32))?.light ?? 0, 1, accuracy: 0.001)
        s.world.time = MP.daySeconds * 2 / 24
        XCTAssertEqual(s.underSky(at: TilePos(322 * 32, 320 * 32))?.light ?? 0, 0.45, accuracy: 0.001)
        XCTAssertNil(s.underSky(at: TilePos(330 * 32, 320 * 32)))
    }

    func testTheUnderlandGrowsIntoChunksInUseAndSparesWhatWasBuilt() {
        let s = makeSociety(8)
        let city = underNation(s, dug: 40)
        let u = s.underworld()
        let ct = s.content
        let ch = u.chunk(323, 320)
        XCTAssertFalse(ch.layers[0].contains(ct.tid("grass")), "out of reach: still cave")
        let x = 323 * 32 + 5, y = 320 * 32 + 5
        u.setTile(2, x, y, ct.tid("wall_stone"))                  // the traveller built a wall here
        city.dug = 130                                            // the nation digs on
        s.underlandCache = nil
        XCTAssertGreaterThan(s.digUnderground(around: TilePos(323 * 32, 320 * 32)), 0)
        XCTAssertEqual(u.tile(0, 323 * 32 + 20, 320 * 32 + 20) == ct.tid("grass") || ct.tile(u.tile(0, 323 * 32 + 20, 320 * 32 + 20))?.built == true || u.tile(0, 323 * 32 + 20, 320 * 32 + 20) == ct.tid("farmland"), true, "the cave became land")
        XCTAssertEqual(u.tile(2, x, y), ct.tid("wall_stone"), "what was built stays")
        XCTAssertEqual(s.digUnderground(around: TilePos(323 * 32, 320 * 32)), 0, "nothing more until it digs again")
    }

    func testSeaFloorNationsHaveADomeStairAndAGlassWalledUnderland() {
        let s = makeSociety(9)
        let city = underNation(s, dug: 40, sea: true)
        let u = s.underworld()
        let ct = s.content
        let home = u.chunk(320, 320)
        XCTAssertTrue(home.layers[0].contains(ct.tid("sand")), "sand underfoot")
        let edge = u.chunk(321, 320)                               // r = 1.25: the next chunk east is the edge
        XCTAssertEqual(edge.layers[2][10 * 32 + 31], ct.tid("wall_glass"), "glass holds the flooded rock out")
        XCTAssertEqual(s.underSky(at: TilePos(320 * 32 + 16, 320 * 32 + 16))?.sea, true)
        // the sea-floor nations dig on, without war
        let before = city.dug
        s.civ.advance(to: s.civ.time + 3 * day)
        XCTAssertGreaterThan(city.dug, before)
        // a sea city on the surface has a dry dome with the stairway down
        let gen = Generator(seed: 3); gen.oceans = true
        var found: (Int, Int)?
        for cy in -80...80 where found == nil { for cx in -80...80 where found == nil && gen.isSeaCity(cx, cy) { found = (cx, cy) } }
        guard let (cx, cy) = found else { return }
        let sc = gen.generate(cx, cy)
        XCTAssertEqual(sc.layers[2][16 * 32 + 16], ct.tid("stairs_down"))
        XCTAssertEqual(sc.layers[0][17 * 32 + 16], ct.tid("sand"), "dry floor in the dome")
    }

    func testCitiesBuildDownLevelByLevelEachNarrowerWithStairsBetween() {
        let s = makeSociety(9)
        let city = underNation(s, dug: 40)
        XCTAssertEqual(Civ.levelsDown(city), 1, "a young city has only its underland")
        XCTAssertTrue(s.underlandZones(level: 2).isEmpty)
        city.dug = 200                                          // it digs on: 1 + (200 - 32) / 40 levels
        s.underlandCache = nil; s.deepCache = [:]
        XCTAssertEqual(Civ.levelsDown(city), 5)
        let z1 = s.underlandZones(level: 1).first!, z3 = s.underlandZones(level: 3).first!, z5 = s.underlandZones(level: 5).first!
        XCTAssertGreaterThan(z1.r, z3.r); XCTAssertGreaterThan(z3.r, z5.r)
        XCTAssertTrue(s.underlandZones(level: 6).isEmpty, "not deeper than it has dug")
        // the deep levels are open land with houses and lamps too, round the same middle
        let ct = s.content
        let b3 = s.deepWorld(3)
        let mid = b3.chunk(320, 320)
        XCTAssertTrue(mid.layers[0].contains(ct.tid("grass")) || mid.layers[0].contains(ct.tid("stone_floor")))
        XCTAssertNotEqual(b3.chunk(321, 320).layers[2], s.underworld().chunk(321, 320).layers[2], "each level has its own streets")
        // the plazas are joined: down from B1 to B2 ... and the stairs up on each level come out where the one
        // above went down
        let (dx, dy) = DeepTune.stairDown(1)
        XCTAssertEqual(s.underworld().tile(2, 320 * 32 + dx, 320 * 32 + dy), ct.tid("stairs_down"), "B1's plaza has a way down")
        _ = s.place(at: TilePos(320 * 32 + dx, 320 * 32 + dy + 1), depth: 1)
        var depth = 1
        for level in 1..<5 {
            let (x, y) = DeepTune.stairDown(level)
            let w = s.layer(level)
            XCTAssertEqual(w.tile(2, 320 * 32 + x, 320 * 32 + y), ct.tid("stairs_down"), "B\(level) goes down")
            guard let r = s.useStairs(at: TilePos(320 * 32 + x, 320 * 32 + y).center) else { return XCTFail("down from B\(level)") }
            depth = r.depth
            XCTAssertEqual(depth, level + 1)
            XCTAssertEqual(s.layer(depth).tile(2, 320 * 32 + x, 320 * 32 + y), ct.tid("stairs_up"))
        }
        XCTAssertNotEqual(s.layer(5).tile(2, 320 * 32 + DeepTune.stairDown(5).0, 320 * 32 + DeepTune.stairDown(5).1), ct.tid("stairs_down"), "B5 is its deepest")
        // and back up, level by level
        let (ux, uy) = DeepTune.stairDown(4)
        let up = s.useStairs(at: TilePos(320 * 32 + ux, 320 * 32 + uy).center)
        XCTAssertEqual(up?.depth, 4)
        XCTAssertEqual(s.realm.player.depth, 4)
        // its people walk the deep levels' roads, and the light is theirs
        XCTAssertFalse(s.folk(depth: 4, center: Vec2(Double(320 * 32 + 16) * 16, Double(320 * 32 + 16) * 16), halfW: 1200, halfH: 1200).isEmpty)
        s.world.time = MP.daySeconds * 0.5
        XCTAssertNotNil(s.underSky(at: TilePos(320 * 32, 320 * 32), level: 4))
        // the deep rock away from the city: caverns, basalt and lava from B4 down; more ore
        let rockB6 = s.deepWorld(6).chunk(300, 300)
        XCTAssertTrue(rockB6.layers[0].contains(ct.tid("basalt")))
        // going straight to a level's plaza
        XCTAssertNotNil(s.deepGate(city.id, level: 4))
        XCTAssertNil(s.deepGate(city.id, level: 6))
        XCTAssertNotNil(s.place(at: s.deepGate(city.id, level: 4)! + TilePos(0, 2), depth: 4))
        XCTAssertEqual(s.realm.player.depth, 4)
        // the map shows the city's terraces and how deep it goes
        var m = WorldMap(); m.layer = .underground
        let (_, marks) = m.renderBelow(s, centre: TilePos(320 * 32, 320 * 32), reach: 12, ppc: 8, zh: true)
        XCTAssertTrue(marks.contains { $0.name.contains("↓5层") }, marks.map { $0.name }.joined(separator: ","))
    }

    func testEachLevelHasItsShareOfTheCityAndTheMapShowsAnyLevel() {
        let s = makeSociety(10)
        let city = underNation(s, dug: 200)
        s.underlandCache = nil; s.deepCache = [:]
        let levels = Civ.levelsDown(city)
        let shares = (1...levels).map { Civ.levelPopulation(city, level: $0) }
        XCTAssertEqual(shares.reduce(0, +), city.livePop, "the levels add up to the city")
        XCTAssertGreaterThan(shares[0], shares[levels - 1], "the wide top level holds more than the narrow bottom one")
        // nearby, on a level: that level's people
        XCTAssertEqual(s.nearbyPopulation(around: TilePos(320 * 32, 320 * 32), depth: 3), shares[2])
        // the map of level 3: the city with that level's people; level 6 (not dug): nothing of it
        let m = WorldMap(); m.layer = .underground; m.level = 3
        let (_, marks) = m.renderBelow(s, centre: TilePos(320 * 32, 320 * 32), reach: 12, ppc: 8, zh: true)
        XCTAssertTrue(marks.contains { $0.name.contains(WorldMap.popText(shares[2], zh: true)) }, marks.map { $0.name }.joined(separator: ","))
        m.level = 6
        XCTAssertFalse(m.renderBelow(s, centre: TilePos(320 * 32, 320 * 32), reach: 12, ppc: 8, zh: true).1.contains { $0.kind == .city || $0.kind == .capital })
    }
}
