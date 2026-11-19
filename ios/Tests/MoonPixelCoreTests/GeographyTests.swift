import XCTest
@testable import MoonPixelCore

/// Seas, land ownership, the coast rule and the ground nations stand on (task book section 2).
final class GeographyTests: XCTestCase {
    // MARK: building blocks

    func put(_ c: Civ, _ x: Int, _ y: Int, _ tweak: (inout CivRegion) -> Void = { _ in }) {
        var r = CivRegion(); r.rx = x; r.ry = y; r.land = 1; r.fertility = 0.7; r.forest = 0.3
        tweak(&r)
        c.regions[r.key] = r
    }
    func sea(_ c: Civ, _ x: Int, _ y: Int, deep: Double = 0.6) { put(c, x, y) { $0.land = 0; $0.water = 1; $0.deep = deep; $0.fertility = 0 } }
    func city(_ c: Civ, _ x: Int, _ y: Int, nation: Int) -> CivCity {
        let k = c.newCity(at: MP.chunkKey(x, y), nation: nation, people: CivPeople(adults: 40, children: 10, elders: 5), firstCount: true)
        k.facilities = ["farm": 10, "house": 10, "well": 1]
        return k
    }
    func nation(_ c: Civ) -> Int { c.newPolity(origin: "first", near: nil) }
    func key(_ x: Int, _ y: Int) -> Int64 { MP.chunkKey(x, y) }

    // MARK: sea

    func testOpenSeaAndLakesAndPortSites() {
        let c = Civ(seed: 1)
        for x in 0..<8 { put(c, x, 0) }
        for x in 0..<6 { sea(c, x, 1) }              // open sea: six regions
        sea(c, 7, 1); put(c, 6, 1)                   // a lake of one region
        let b = c.waterBodies()
        XCTAssertTrue(c.isOpenSea(b.of[key(0, 1)]!, b.size))
        XCTAssertFalse(c.isOpenSea(b.of[key(7, 1)]!, b.size), "a one-region lake is not open sea")
        XCTAssertNotNil(c.portSite(key(2, 0), bodies: b), "land beside open sea is a port site")
        XCTAssertTrue(c.portSite(key(2, 0), bodies: b)!.deep)
        XCTAssertNil(c.portSite(key(7, 0), bodies: b), "land beside a lake only is no port site")
        XCTAssertNil(c.portSite(key(0, 1), bodies: b), "the sea itself is no port site")
    }

    // MARK: land

    func testLandHasAnOwnerAndAHolderAndOnlyATruceChangesTheOwner() {
        let c = Civ(seed: 2)
        for x in 0..<9 { put(c, x, 0) }
        sea(c, 4, 1)
        let a = nation(c), b = nation(c)
        let ca = city(c, 1, 0, nation: a), cb = city(c, 7, 0, nation: b)
        c.refreshTerritory()
        XCTAssertEqual(c.legalOwner(key(0, 0)), a); XCTAssertEqual(c.legalOwner(key(3, 0)), a)
        XCTAssertEqual(c.legalOwner(key(8, 0)), b); XCTAssertEqual(c.legalOwner(key(5, 0)), b)
        XCTAssertNil(c.legalOwner(key(4, 1)), "the sea belongs to no one")
        XCTAssertEqual(c.controller(key(3, 0)), a)
        // b takes a's city: it holds the city and its land at once; a still owns them by right
        c.declare(b, on: a)
        ca.nation = b
        c.refreshTerritory()
        XCTAssertEqual(c.controller(key(1, 0)), b); XCTAssertEqual(c.controller(key(0, 0)), b)
        XCTAssertEqual(c.legalOwner(key(1, 0)), a, "occupation does not change the border")
        XCTAssertTrue(c.occupied().contains(key(1, 0)))
        // a truce cedes it: now the border moves
        c.makePeace(a, b)
        c.cede(city: ca.id)
        XCTAssertEqual(c.legalOwner(key(1, 0)), b); XCTAssertEqual(c.legalOwner(key(0, 0)), b)
        XCTAssertFalse(c.occupied().contains(key(1, 0)))
        _ = cb
        // land too far from any city stays empty
        put(c, 30, 0)
        c.refreshTerritory()
        XCTAssertNil(c.legalOwner(key(30, 0)), "undeveloped land may belong to no one")
    }

    func testCoastRuleGivesAnInlandNationAPortItCanReach() {
        let c = Civ(seed: 3)
        for x in 0..<10 { put(c, x, 0) }
        for x in 0..<10 { sea(c, x, 1) }
        for x in 0..<10 { for y in -6 ... -1 { put(c, x, y) } }
        let inland = nation(c), coastal = nation(c)
        let home = city(c, 2, -6, nation: inland); c.polities[inland]!.capital = home.id
        let port = city(c, 8, 0, nation: coastal); c.polities[coastal]!.capital = port.id
        c.refreshTerritory()
        XCTAssertNil(c.seaAccess(inland), "far from the sea at first")
        XCTAssertNotNil(c.seaAccess(coastal))
        c.coastRule = true
        let left = c.applyCoastRule(gen: nil)
        XCTAssertEqual(left, [])
        let p = c.seaAccess(inland)
        XCTAssertNotNil(p, "every starting nation reaches open sea from its capital")
        XCTAssertEqual(c.legalOwner(p!), inland)
        XCTAssertEqual(c.legalOwner(key(8, 0)), coastal, "no one else's land is taken for it")
        // looked at once: asking again changes nothing
        let before = c.regions
        c.applyCoastRule(gen: nil)
        XCTAssertEqual(c.regions, before)
        // the port survives the daily refresh
        c.refreshTerritory()
        XCTAssertNotNil(c.seaAccess(inland))
    }

    func testCoastRuleOnlyForNewWorlds() {
        let c = Civ(seed: 3)
        for x in 0..<6 { put(c, x, 0) }
        for x in 0..<6 { sea(c, x, 5) }
        for x in 0..<6 { for y in 1...4 { put(c, x, y) } }
        let n = nation(c)
        c.polities[n]!.capital = city(c, 1, 0, nation: n).id
        c.refreshTerritory()
        c.coastRule = false
        XCTAssertEqual(c.applyCoastRule(gen: nil), [])
        XCTAssertNil(c.seaAccess(n), "an old world keeps its land as it was")
        // and the flag is saved
        c.coastRule = true
        let d = try! JSONDecoder().decode(Civ.self, from: try! JSONEncoder().encode(c))
        XCTAssertTrue(d.coastRule)
        // a save from before the rule existed opens without it
        var json = try! JSONSerialization.jsonObject(with: try! JSONEncoder().encode(c)) as! [String: Any]
        json.removeValue(forKey: "coastRule"); json.removeValue(forKey: "seaChecked")
        let old = try! JSONDecoder().decode(Civ.self, from: try! JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(old.coastRule)
    }

    func testEveryStartingNationReachesTheSeaOnFixedSeeds() {
        for seed in [3, 11, 29, 77] {
            let gen = Generator(seed: seed); gen.oceans = true
            func make() -> Civ {
                let c = Civ(seed: seed); c.coastRule = true
                c.discover(around: TilePos(0, 0), radius: 4, gen: gen)
                c.refreshTerritory()
                c.applyCoastRule(gen: gen)
                c.refreshTerritory()
                return c
            }
            let c = make()
            let b = c.waterBodies()
            var reached = 0
            for id in c.polities.keys.sorted() where c.polities[id]!.status == .active {
                if c.seaAccess(id, bodies: b) != nil { reached += 1 }
            }
            let active = c.polities.values.filter { $0.status == .active }.count
            let corridor = c.regions.values.filter { $0.legal != nil && $0.city == nil && $0.claim != nil }.count
            print("GEO seed=\(seed) nations=\(active) reach_sea=\(reached) open_seas=\(b.size.values.filter { $0 >= c.cfg.openSeaRegions }.count) land_held=\(corridor) traits=\(c.polities.keys.sorted().flatMap { c.traits(of: $0, bodies: b).map { $0.kind.rawValue } })")
            XCTAssertEqual(reached, active, "seed \(seed): every nation has a port on open sea")
            XCTAssertEqual(make().regions, c.regions, "seed \(seed): the same every time")
        }
    }

    func testCoastRuleHoldsOnSixtySeeds() {
        var total = 0
        for seed in 100..<160 {
            let gen = Generator(seed: seed); gen.oceans = true
            let c = Civ(seed: seed); c.coastRule = true
            c.discover(around: TilePos(0, 0), radius: 4, gen: gen)
            XCTAssertEqual(c.applyCoastRule(gen: gen), [], "seed \(seed)")
            total += c.polities.values.filter { $0.status == .active }.count
        }
        XCTAssertGreaterThan(total, 300)
    }

    func testOceanWorldsKeepTheLandRoundTheStart() {
        // the start area of an ocean world is exactly the land of any world; far out, there are seas
        let a = Generator(seed: 5), b = Generator(seed: 5); b.oceans = true
        for (x, y) in [(0, 0), (120, -80), (-250, 40), (200, 200)] { XCTAssertEqual(a.climate(x, y).0, b.climate(x, y).0) }
        let c = Civ(seed: 5)
        for ry in -12...12 { for rx in -12...12 { let r = Civ.survey(b, rx, ry, size: 256); c.regions[r.key] = r } }
        let w = c.waterBodies()
        XCTAssertTrue(w.size.values.contains { $0 >= 20 }, "an ocean world has wide open seas")
    }

    // MARK: ground

    /// A fertile 3x3 basin ringed by high mountains, with mountain passes at three places.
    func basin(_ c: Civ, passes: [(Int, Int)], plainGap: (Int, Int)? = nil) {
        for y in -3...3 { for x in -3...3 {
            let inner = abs(x) <= 1 && abs(y) <= 1
            put(c, x, y) { r in
                if !inner { r.mountain = 0.9; r.fertility = 0.1 }
            }
        } }
        // the passes: the ring cell becomes a valley (rough but passable) and so does the land outside it
        for (x, y) in passes {
            put(c, x, y) { $0.mountain = 0.45; $0.fertility = 0.2 }
            let ox = x == 0 ? 0 : (x > 0 ? 1 : -1), oy = y == 0 ? 0 : (y > 0 ? 1 : -1)
            put(c, x + ox, y + oy) { $0.mountain = 0.45 }
        }
        if let (x, y) = plainGap { put(c, x, y) { $0.mountain = 0 } }
    }

    func testThreePassBasinAndTakingAPassOpensTheWay() {
        let c = Civ(seed: 4)
        c.cfg.claimRadius = 2
        basin(c, passes: [(2, 0), (-2, 0), (0, 2)])
        let a = nation(c), foe = nation(c)
        c.polities[a]!.capital = city(c, 0, 0, nation: a).id
        // a fort town in each pass
        let forts = [city(c, 2, 0, nation: a), city(c, -2, 0, nation: a), city(c, 0, 2, nation: a)]
        // the enemy camps outside the east pass
        put(c, 6, 0); put(c, 5, 0) { $0.mountain = 0.2 }; put(c, 4, 0) { $0.mountain = 0.2 }
        c.polities[foe]!.capital = city(c, 6, 0, nation: foe).id
        c.refreshTerritory()
        let t = c.traits(of: a).first { $0.kind == .basin }
        XCTAssertNotNil(t, "fertile land reached only through passes is a basin")
        XCTAssertEqual(t?.places.count, 3)
        XCTAssertEqual(t?.held, 3)
        XCTAssertEqual(t?.line(zh: true), "三关仍控制三关")
        c.declare(foe, on: a)
        c.refreshTerritory()
        XCTAssertNil(c.landRoute(for: foe, from: key(6, 0), to: key(0, 0)), "the passes held: no way in")
        // the east pass falls
        forts[0].nation = foe
        c.refreshTerritory()
        let t2 = c.traits(of: a).first { $0.kind == .basin }
        XCTAssertEqual(t2?.held, 2)
        XCTAssertEqual(t2?.line(zh: true), "三关仍控制两关")
        XCTAssertNotNil(c.landRoute(for: foe, from: key(6, 0), to: key(0, 0)), "taking the pass opens the way at once")
        XCTAssertEqual(c.legalOwner(key(2, 0)), a, "the border is unchanged until a truce")
    }

    func testABasinWithAPlainWayInIsNoBasin() {
        let c = Civ(seed: 5)
        basin(c, passes: [(2, 0), (-2, 0), (0, 2)], plainGap: (0, -2))
        put(c, 0, -3) { $0.mountain = 0 }
        let a = nation(c)
        c.polities[a]!.capital = city(c, 0, 0, nation: a).id
        c.refreshTerritory()
        XCTAssertNil(c.traits(of: a).first { $0.kind == .basin }, "an open plain way in: no three-pass bonus")
    }

    func testTwoSeaStrait() {
        // two seas, north and south, joined by nothing among the known regions; a nation on the land between
        let c = Civ(seed: 6)
        for x in 0..<6 { sea(c, x, 0); put(c, x, 1); put(c, x, 2); sea(c, x, 3) }
        let a = nation(c)
        c.polities[a]!.capital = city(c, 2, 1, nation: a).id
        c.refreshTerritory()
        let t = c.traits(of: a).first { $0.kind == .strait }
        XCTAssertNotNil(t, "ports on two seas make a strait")
        XCTAssertEqual(t?.held, 2)
    }

    func testOneSeaRoundALongCapeIsAStrait() {
        // one sea that wraps round a long cape: across the cape is 1 region, round it by water is far
        let c = Civ(seed: 7)
        for y in 0..<10 { sea(c, 0, y); put(c, 1, y); put(c, 2, y); sea(c, 3, y) }
        for x in 0..<4 { sea(c, x, 10) }
        let a = nation(c)
        c.polities[a]!.capital = city(c, 1, 1, nation: a).id
        _ = city(c, 2, 1, nation: a)
        c.refreshTerritory()
        let t = c.traits(of: a).first { $0.kind == .strait }
        XCTAssertNotNil(t)
        XCTAssertGreaterThanOrEqual(t!.value, Double(c.cfg.straitDetour))
    }

    func testRiverDeltaAndIslandChain() {
        let c = Civ(seed: 8)
        for x in 0..<4 { put(c, x, 0) { $0.river = true; $0.water = 0.3; $0.land = 0.7 } }
        let a = nation(c)
        c.polities[a]!.capital = city(c, 1, 0, nation: a).id
        c.refreshTerritory()
        XCTAssertNotNil(c.traits(of: a).first { $0.kind == .delta })

        let d = Civ(seed: 9)
        d.cfg.claimRadius = 1
        for x in 0..<12 { sea(d, x, 0); sea(d, x, 2) }
        for x in 0..<12 { if x % 4 == 0 { put(d, x, 1) } else { sea(d, x, 1) } }
        let b = nation(d)
        for x in stride(from: 0, to: 12, by: 4) { let k = city(d, x, 1, nation: b); if x == 0 { d.polities[b]!.capital = k.id } }
        d.refreshTerritory()
        let t = d.traits(of: b).first { $0.kind == .islands }
        XCTAssertNotNil(t)
        XCTAssertEqual(t?.places.count, 3)
        XCTAssertEqual(t?.value, 4)
    }
}
