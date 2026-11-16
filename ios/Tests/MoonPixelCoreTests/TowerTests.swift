import XCTest
@testable import MoonPixelCore

final class TowerTests: XCTestCase {
    let day = MP.daySeconds

    // MARK: space

    func testCoordinatesDivideDownRefuseToWrapAndDrawFarAwayWithoutJitter() {
        XCTAssertEqual(Space.floorDiv(-1, 32), -1); XCTAssertEqual(Space.floorDiv(-32, 32), -1); XCTAssertEqual(Space.floorDiv(-33, 32), -2); XCTAssertEqual(Space.floorDiv(31, 32), 0)
        XCTAssertEqual(Space.chunk(Cell3(-1, 0, -1)), Chunk3(cx: -1, cy: 0, cz: -1))
        XCTAssertNil(Space.add(Space.limit, 1), "past the edge: refused")
        XCTAssertNil(Space.add(Int64.max, 1), "and never wrapped round")
        XCTAssertNotNil(Space.add(Space.limit - 1, 1))
        // far above a thousand floors: drawn relative to an origin near the camera, exactly
        let high: Int64 = 1 << 39
        let a = Cell3(1_000_003, -2_000_001, high + 7), o = Cell3(1_000_000, -2_000_000, high)
        XCTAssertEqual(Space.render(a, origin: o), SIMD3<Float>(3, 7, -1), "integer difference first: no Float rounding at 2^39")
        XCTAssertNil(Space.render(Cell3(0, 0, high), origin: Cell3(0, 0, 0)), "too far from the origin to draw: the caller must move the origin")
        XCTAssertEqual(Space.openWorld(tile: TilePos(5, 6), depth: 1).z, Space.undergroundTop, "the old underground is just below the surface")
    }

    // MARK: plans

    func testBlueprintsPassTheirChecksAndDiffer() {
        var layouts = Set<[Part]>()
        for use in RoomUse.allCases { for layout in 0..<3 { for seed in 0..<4 { for (w, d) in [(10, 10), (12, 10), (14, 12)] {
            let p = Blueprint.plan(use: use, w: w, d: d, layout: layout, seed: seed)
            XCTAssertEqual(Blueprint.check(p), [], "\(p.key)")
            XCTAssertGreaterThan(p.columns, 3)
            if use == .home { layouts.insert(p.parts) }
        } } } }
        XCTAssertGreaterThan(layouts.count, 10, "many different homes, not one plan recoloured")
        // a room walled off from the stairs is caught
        var p = Blueprint.plan(use: .home, w: 12, d: 10, layout: 0, seed: 1)
        for x in 1..<11 { p.parts[2 * 12 + x] = .wall; p.parts[7 * 12 + x] = .wall }
        XCTAssertFalse(Blueprint.check(p).isEmpty)
    }

    func makeTower(_ c: Civ, city: CivCity, floors n: Int, material: Int = 3, lifts: Int = 0, z: Int64 = 0, use: RoomUse = .home) -> Tower {
        let lobby = Blueprint.plan(use: .lobby, w: 12, d: 10, layout: 0, seed: 1), home = Blueprint.plan(use: use, w: 12, d: 10, layout: 0, seed: 2)
        let pump = Blueprint.plan(use: .pump, w: 12, d: 10, layout: 0, seed: 3)
        c.towerIndex.plans[lobby.key] = lobby; c.towerIndex.plans[home.key] = home; c.towerIndex.plans[pump.key] = pump
        let t = Tower(base: Cell3(Int64(city.rx * 256 + 20), Int64(city.ry * 256 + 20), z))
        t.id = c.towerIndex.nextTower; c.towerIndex.nextTower += 1
        t.city = city.id; t.nation = city.nation; t.w = 12; t.d = 10; t.material = material; t.lifts = lifts
        t.floors = (0..<n).map { k in
            var f = TowerFloor(z: z + Int64(k * 4), plan: k == 0 ? lobby.key : (k % TowerRules.pumpEvery == TowerRules.pumpEvery - 1 ? pump.key : home.key)); f.stage = .inUse; return f }
        c.towerIndex.towers[t.id] = t; c.towerIndex.index(t)
        c.restructure(t)
        return t
    }

    func city(_ c: Civ, adults: Int, grain: Double, extra: [String: Double] = [:]) -> CivCity {
        var r = CivRegion(); r.land = 1; r.fertility = 0.6; r.river = true; c.regions[r.key] = r
        let n = c.newPolity(origin: "first", near: nil)
        c.polities[n]!.techs = CivTech.all.map { $0.key }; c.polities[n]!.ai = false
        let t = c.newCity(at: r.key, nation: n, people: CivPeople(adults: adults, children: adults / 4, elders: adults / 8), firstCount: true)
        t.facilities = ["farm": adults / 2, "house": 4, "well": adults / 30 + 2, "plant": 20, "fusion_plant": 4]
        t.stock = ["grain": grain, "timber": 5000, "stone": 5000].merging(extra) { a, _ in a }
        c.totals.add(\.found, "grain", grain)
        return t
    }

    func testFloorsShareAPlanButEachKeepsItsOwnChanges() {
        let c = Civ(seed: 1); let k = city(c, adults: 100, grain: 1000)
        let t = makeTower(c, city: k, floors: 5)
        let cell = Cell3(t.base.x + 3, t.base.y + 4, t.floors[2].z)
        let before = c.towerIndex.at(cell)!.part
        XCTAssertTrue(c.towerIndex.set(cell, .machine))
        XCTAssertEqual(c.towerIndex.at(cell)?.part, .machine)
        XCTAssertEqual(c.towerIndex.at(Cell3(cell.x, cell.y, t.floors[3].z))?.part, before, "the floor above, same plan, untouched")
        XCTAssertEqual(c.towerIndex.plans[t.floors[2].plan]?.parts[4 * 12 + 3], before, "the shared plan itself untouched")
        XCTAssertNil(c.towerIndex.at(Cell3(cell.x + 50, cell.y, cell.z)), "empty space is nothing")
    }

    // MARK: building for themselves

    func testACrowdedCityBuildsATowerSaysWhyAndMovesPeopleIn() {
        let c = Civ(seed: 2); let k = city(c, adults: 400, grain: 60000, extra: ["steel": 3000, "parts": 500])
        XCTAssertGreaterThan(c.towerNeeds(k).first?.score ?? 0, 20)
        XCTAssertEqual(c.towerNeeds(k).first?.kind, "new_tower")
        let stone = k.stock["stone"]!
        for _ in 0..<40 { c.advance(to: c.time + day) }
        let ts = c.towers(of: k.id)
        XCTAssertFalse(ts.isEmpty, "a tower went up")
        XCTAssertTrue(ts[0].history.first?.contains("no bed") ?? false, "with its reason: \(ts[0].history.first ?? "")")
        XCTAssertLessThan(k.stock["stone"] ?? 0, stone, "paid for with real materials")
        XCTAssertGreaterThan(ts[0].floors.filter { $0.stage == .inUse }.count, 1)
        XCTAssertGreaterThan(k.upstairs, 0, "people live in it")
        for f in ts[0].floors where f.people.total > 0 { XCTAssertEqual(f.stage, .inUse, "only on finished floors") }
        XCTAssertEqual(c.audit(), [], "moving in made no one and lost no one")
    }

    func testFoodThatCannotGetUpstairsStarvesTheTopAndALiftFixesIt() {
        let c = Civ(seed: 3); let k = city(c, adults: 6000, grain: 2e6, extra: ["steel": 3000, "parts": 3000, "electronics": 500])
        c.polities[k.nation]!.builds = false
        let t = makeTower(c, city: k, floors: 61, lifts: 0)
        for _ in 0..<10 { c.advance(to: c.time + day) }
        XCTAssertGreaterThan(k.upstairs, 300, "people moved up")
        let top = t.floors.last(where: { $0.people.total > 0 })!
        XCTAssertLessThan(top.coverage, 0.95, "the stairs cannot carry enough up sixty floors")
        XCTAssertGreaterThan(k.foodDays, 30, "while the cellars are full")
        let needs = c.towerNeeds(k).map { $0.kind }
        XCTAssertTrue(needs.contains("lift") || needs.contains("sky_lobby"), "it is seen as a carrying problem: \(needs)")
        XCTAssertFalse(needs.contains("farm_floors"), "not as a lack of food")
        c.propose(TowerProposal(reasonEn: "", reasonZh: "", kind: "lift", score: 80), in: k)
        c.propose(TowerProposal(reasonEn: "", reasonZh: "", kind: "lift", score: 80), in: k)
        c.propose(TowerProposal(reasonEn: "", reasonZh: "", kind: "sky_lobby", score: 80), in: k)
        for _ in 0..<12 { c.advance(to: c.time + day) }
        XCTAssertGreaterThanOrEqual(t.floors.filter { $0.people.total > 0 }.map { $0.coverage }.min() ?? 0, 0.95, "fed again, floor by floor")
        XCTAssertEqual(c.audit(), [])
    }

    func testTakingOutColumnsBringsDownWhatIsAboveOnceAndOnlyThat() {
        let c = Civ(seed: 4); let k = city(c, adults: 2000, grain: 1e6)
        c.polities[k.nation]!.builds = false
        let t = makeTower(c, city: k, floors: 30, material: 2)            // steel
        for _ in 0..<6 { c.advance(to: c.time + day) }
        let inside = t.floors.reduce(0) { $0 + $1.people.total }
        XCTAssertGreaterThan(inside, 0)
        c.restructure(t, from: 29); XCTAssertEqual(t.recomputed, 30, "a change at the top: every floor below")
        c.restructure(t, from: 4); XCTAssertEqual(t.recomputed, 5, "a change at floor 5: five floors, nothing above")
        // knock out every column of floor 3
        let p = c.towerIndex.plans[t.floors[3].plan]!
        for i in p.parts.indices where p.parts[i] == .column { t.floors[3].diff[i] = .slab }
        let above = t.floors[3...].reduce(0) { $0 + $1.people.total }
        c.advance(to: c.time + day)
        XCTAssertEqual(t.floors.count, 3, "floor 4 and everything over it came down")
        XCTAssertEqual(k.ledger.deaths["collapse"] ?? 0, above, "those inside died, counted once")
        c.advance(to: c.time + day)
        XCTAssertEqual(k.ledger.deaths["collapse"] ?? 0, above, "and not again the next day")
        XCTAssertEqual(c.audit(), [])
    }

    func testAProtectedTowerIsNeverAddedToByThePlanner() {
        let c = Civ(seed: 5); let k = city(c, adults: 900, grain: 1e5, extra: ["steel": 3000])
        let t = makeTower(c, city: k, floors: 3); t.protected = true
        let n = t.floors.count
        XCTAssertFalse(c.propose(TowerProposal(reasonEn: "", reasonZh: "", kind: "add_floors", score: 100), in: k))
        XCTAssertEqual(t.floors.count, n)
    }

    // MARK: scale

    func testTenAHundredAndAThousandFloorsWorkAndSaveAndSitFarUp() throws {
        for n in [10, 100, 1000] {
            let c = Civ(seed: 6); let k = city(c, adults: n * 40, grain: Double(n) * 2e4)
            c.polities[k.nation]!.builds = false
            let t = makeTower(c, city: k, floors: n, material: n >= 1000 ? 4 : 3, lifts: max(1, n / 25), z: n == 1000 ? (1 << 38) : 0)   // a thousand floors need field-lift (and its power)
            t.skyLobbyEvery = n >= 100 ? 30 : 0
            let t0 = Date()
            for _ in 0..<6 { c.advance(to: c.time + day) }
            let per = Date().timeIntervalSince(t0) / 6 * 1000
            guard t.floors.count == n else { XCTFail("\(n) floors: it came down to \(t.floors.count)"); continue }
            // the top floor is found, and works
            let topCell = Cell3(t.base.x + 5, t.base.y + 5, t.floors[n - 1].z)
            XCTAssertEqual(c.towerIndex.at(topCell)?.floor, n - 1, "\(n) floors: the top is found by its cell")
            XCTAssertGreaterThan(k.upstairs, 0)
            XCTAssertEqual(t.floors.count, n, "it stands")
            XCTAssertEqual(c.audit(), [])
            // saved and read back
            let back = try JSONDecoder().decode(Civ.self, from: JSONEncoder().encode(c))
            XCTAssertEqual(back.towerIndex.towers[t.id]?.floors.count, n)
            XCTAssertEqual(back.towerIndex.at(topCell)?.floor, n - 1)
            XCTAssertEqual(back.people, c.people)
            let plans = Set(t.floors.map { $0.plan }).count
            print(String(format: "TOWER %4d floors: %.2f ms a day, %d plans shared by all floors, base z %lld", n, per, plans, t.base.z))
        }
    }
}
