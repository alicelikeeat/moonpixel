import XCTest
@testable import MoonPixelCore

final class CivTests: XCTestCase {
    let day = MP.daySeconds

    /// A strip of flat, fertile land regions (and optional terrain overrides), with nothing generated in them.
    func land(_ c: Civ, _ xs: ClosedRange<Int>, y: Int = 0, _ tweak: (inout CivRegion) -> Void = { _ in }) {
        for x in xs {
            var r = CivRegion(); r.rx = x; r.ry = y; r.land = 1; r.fertility = 0.7; r.forest = 0.5; r.ore = 0.6; r.coal = 0.5; r.river = true
            tweak(&r)
            c.regions[r.key] = r
        }
    }
    func city(_ c: Civ, _ x: Int, _ y: Int = 0, nation: Int, adults: Int, farms: Int, houses: Int, grain: Double) -> CivCity {
        let k = c.newCity(at: MP.chunkKey(x, y), nation: nation, people: CivPeople(adults: adults, children: adults / 3, elders: adults / 6), firstCount: true)
        k.facilities = ["farm": farms, "house": houses, "well": 2]
        k.stock = ["grain": grain, "timber": 0, "stone": 0]
        c.totals.add(\.found, "grain", grain)
        return k
    }
    func run(_ c: Civ, days: Double, check: Bool = true, file: StaticString = #file, line: UInt = #line) {
        let end = c.time + days * day
        while c.time < end {
            c.advance(to: min(end, c.time + day))
            if check { let a = c.audit(); XCTAssertEqual(a, [], "day \(c.day)", file: file, line: line); if !a.isEmpty { return } }
        }
    }
    func state(_ c: Civ) -> String { c.digest() }

    // MARK: places

    func testRegionsAreFoundOnceAndTheSameEveryTime() {
        let gen = Generator(seed: 77)
        let a = Civ(seed: 77), b = Civ(seed: 77)
        a.discover(around: TilePos(0, 0), radius: 6, gen: gen)
        let people = a.people, n = a.polities.count
        XCTAssertGreaterThan(n, 3, "more than three nations once enough land is known: \(n)")
        XCTAssertEqual(a.discover(around: TilePos(0, 0), radius: 6, gen: gen), 0, "looking again finds nothing new")
        XCTAssertEqual(a.people, people, "and makes no one")
        // the same land, found in a different order, holds the same places and people
        for r in (0...6).reversed() { b.discover(around: TilePos(0, 0), radius: r, gen: gen) }
        XCTAssertEqual(b.people, a.people)
        XCTAssertEqual(Set(b.regions.values.compactMap { $0.city.flatMap { b.cities[$0]?.pop } }), Set(a.regions.values.compactMap { $0.city.flatMap { a.cities[$0]?.pop } }))
        XCTAssertEqual(a.totals.newly, a.people, "everyone so far is a first count, not a birth")
        XCTAssertEqual(Set(a.polities.keys).count, a.polities.count, "ids are never shared")
    }

    // MARK: people and food

    func testPeopleAndFoodAddUpEveryDayOverYears() {
        for seed in [3, 11, 29] {
            let gen = Generator(seed: seed)
            let c = Civ(seed: seed)
            c.discover(around: TilePos(0, 0), radius: 5, gen: gen)
            for p in c.polities.keys.sorted() { c.polities[p]!.techs += ["husbandry", "writing", "medicine", "irrigation"] }
            run(c, days: 120)
            let held = c.foodHeld(), want = c.foodExpected()
            for f in CivFood.all { XCTAssertEqual(held[f.key] ?? 0, want[f.key] ?? 0, accuracy: 0.01 + 1e-6 * abs(want[f.key] ?? 0), "\(f.key), seed \(seed)") }
            XCTAssertGreaterThan(c.totals.births, 0); XCTAssertGreaterThan(c.totals.deathTotal, 0)
            for city in c.cities.values { XCTAssertGreaterThanOrEqual(city.pop, 0) }
        }
    }

    func testMoreFoodAndRoomGrowTheTownButRoomAloneDoesNot() {
        func town(farms: Int, houses: Int) -> Int {
            let c = Civ(seed: 5); land(c, 0...0)
            let n = c.newPolity(origin: "first", near: nil)
            c.polities[n]!.techs = ["farming", "irrigation", "medicine"]
            c.polities[n]!.builds = false                                  // what it is given, nothing more
            let t = city(c, 0, nation: n, adults: 60, farms: farms, houses: houses, grain: 900)
            run(c, days: 160)
            return t.pop
        }
        let start = 60 + 20 + 10
        let fed = town(farms: 30, houses: 80), roomOnly = town(farms: 1, houses: 80), cramped = town(farms: 30, houses: 4)
        XCTAssertGreaterThan(fed, Int(Double(start) * 1.3), "food and room: it grows")
        XCTAssertLessThan(roomOnly, fed, "room without food does not make people")
        XCTAssertLessThan(cramped, fed, "food without room grows less")
    }

    func testABesiegedCityStarvesThoughItsNationHasFoodAndRecoversWhenFreed() {
        let c = Civ(seed: 9); land(c, 0...3)
        let a = c.newPolity(origin: "first", near: nil), b = c.newPolity(origin: "first", near: nil)
        let rich = city(c, 0, nation: a, adults: 80, farms: 40, houses: 40, grain: 50000)
        let held = city(c, 3, nation: a, adults: 80, farms: 0, houses: 40, grain: 300)
        _ = rich
        // the enemy stands in the city's region, with nobody to throw them out
        c.declare(b, on: a)
        let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = b; f.region = held.regionKey
        var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = "infantry"; u.nation = b; u.force = f.id; u.hp = 1e9
        c.units[u.id] = u; f.units = [u.id]; f.crew = CivPeople(adults: 20); c.totals.newly += 20; f.food = ["ration": 1e6]; c.totals.add(\.found, "ration", 1e6)
        c.forces[f.id] = f
        c.polities[b]!.fatigue = -100                  // they will not give up
        held.occupier = nil
        // block taking the city (so it stays theirs, besieged)
        let guardF = CivForce(); guardF.id = c.nextForce; c.nextForce += 1; guardF.nation = a; guardF.region = held.regionKey
        c.forces[guardF.id] = guardF
        var g = CivUnit(); g.id = c.nextUnit; c.nextUnit += 1; g.kind = "infantry"; g.nation = a; g.force = guardF.id; g.hp = 1e9; c.units[g.id] = g; guardF.units = [g.id]
        guardF.crew = CivPeople(adults: 20); c.totals.newly += 20; guardF.food = ["ration": 1e6]; c.totals.add(\.found, "ration", 1e6)
        let before = held.pop
        run(c, days: 14)
        XCTAssertTrue(held.besieged)
        XCTAssertGreaterThan(held.people.hungerIndex, 0.2, "no food gets in, though the capital is full of grain")
        XCTAssertGreaterThan(held.ledger.deaths["hunger"] ?? 0, 0)
        XCTAssertGreaterThan(held.ledger.migOut, 0, "some get out")
        XCTAssertFalse(c.trips.values.contains { $0.to == held.id && $0.leg + 1 >= $0.route.count }, "relief waits outside")
        // the siege lifts: food comes, hunger eases step by step
        c.forces[f.id] = nil; c.units[u.id] = nil
        c.totals.deaths["battle", default: 0] += 20                    // (the besiegers marched off this map)
        c.makePeace(a, b)
        let worst = held.people.hungerIndex
        run(c, days: 30)
        XCTAssertLessThan(held.people.hungerIndex, worst, "fed again, they recover")
        XCTAssertLessThan(held.pop, before + 20)
    }

    func testRationsShareFoodByPolicyAndAPolicyTakesADay() {
        let c = Civ(seed: 2); land(c, 0...0)
        let n = c.newPolity(origin: "first", near: nil)
        let t = city(c, 0, nation: n, adults: 60, farms: 0, houses: 40, grain: 30)
        c.setRation(t, .childrenFirst)
        XCTAssertEqual(t.ration, .normal, "not yet")
        run(c, days: 3)
        XCTAssertEqual(t.ration, .childrenFirst)
        let kids = (0..<6).map { t.people.n[$0] }, adults = (0..<6).map { t.people.n[6 + $0] }
        let kidHunger = Double(zip(kids, 0..<6).reduce(0) { $0 + $1.0 * $1.1 }) / Double(max(1, kids.reduce(0, +)))
        let adultHunger = Double(zip(adults, 0..<6).reduce(0) { $0 + $1.0 * $1.1 }) / Double(max(1, adults.reduce(0, +)))
        XCTAssertLessThan(kidHunger, adultHunger, "children are fed first")
    }

    func testHungerComesOnSlowlyAndPassesSlowly() {
        let c = Civ(seed: 4); land(c, 0...0)
        let n = c.newPolity(origin: "first", near: nil)
        c.cfg.leave = [0, 0, 0, 0, 0, 0]; c.cfg.forage = 0
        let t = city(c, 0, nation: n, adults: 100, farms: 0, houses: 40, grain: 0)
        run(c, days: 1)
        XCTAssertEqual(t.ledger.deaths["hunger"] ?? 0, 0, "one missed day kills no one")
        XCTAssertEqual(t.people.state(4) + t.people.state(5), 0)
        run(c, days: 6)
        XCTAssertGreaterThan(t.people.state(3) + t.people.state(4) + t.people.state(5), 0, "a week without food: famine")
        t.stock["grain"] = 5000; c.totals.add(\.found, "grain", 5000)
        let low = t.people.state(0)
        run(c, days: 1)
        XCTAssertLessThan(t.people.state(0) - low, t.pop / 2, "one meal does not make everyone well at once")
        run(c, days: 14)
        XCTAssertGreaterThan(t.people.state(0), t.pop * 7 / 10, "but they do recover")
    }

    // MARK: time

    func testTheSameDaysGiveTheSameWorldAtAnySpeedAndAcrossASave() throws {
        func world() -> Civ { let c = Civ(seed: 13); c.discover(around: TilePos(0, 0), radius: 4, gen: Generator(seed: 13)); return c }
        let a = world(), b = world(), s = world()
        run(a, days: 30, check: false)                                    // one day at a time
        b.advance(to: 30 * day)                                         // all at once (capped steps are not hit: 30 days)
        XCTAssertEqual(state(a), state(b), "speed does not change the outcome")
        run(s, days: 12, check: false)
        let saved = try JSONDecoder().decode(Civ.self, from: try JSONEncoder().encode(s))
        run(saved, days: 18, check: false)
        XCTAssertEqual(state(saved), state(a), "saved and loaded halfway: the same")
    }

    // MARK: arms

    func makeIndustrialNation(_ c: Civ, x: Int = 0, _ tweak: (inout CivRegion) -> Void = { _ in }) -> (Int, CivCity) {
        land(c, x...x, tweak)
        let n = c.newPolity(origin: "first", near: nil)
        c.polities[n]!.techs = CivTech.all.map { $0.key }
        c.polities[n]!.ai = false                                          // the test gives the orders
        let t = city(c, x, nation: n, adults: 3000, farms: 600, houses: 700, grain: 1e6)
        for f in ["frame_works", "deep_yard", "aircraft_works", "sky_yard", "motor_works", "barracks", "airfield", "plant", "fusion_plant"] { t.facilities[f] = 2 }
        for (k, v) in ["steel": 5000.0, "armor": 500, "parts": 2000, "engine": 200, "electronics": 1000, "weapons": 200, "core": 40, "fuel": 5000, "ammo": 5000] { t.stock[k] = v }
        return (n, t)
    }

    func testAFrameIsBuiltStageByStageCrewedAndCannotCrossAMountainPass() {
        let c = Civ(seed: 1)
        let (n, home) = makeIndustrialNation(c)
        land(c, 1...1) { $0.mountain = 0.8 }                               // a pass: people get through, frames do not
        land(c, 2...2)
        guard let pid = c.order("frame", nation: n, city: home.id) else { return XCTFail("frame order refused") }
        run(c, days: 1)
        XCTAssertEqual(c.projects[pid]?.invested["steel"], 60, "the first stage takes its materials, and only those")
        XCTAssertEqual(c.projects[pid]?.stage, 0)
        run(c, days: 12)
        XCTAssertNil(c.projects[pid], "done")
        guard let frame = c.units.values.first(where: { $0.kind == "frame" }) else { return XCTFail("no frame") }
        XCTAssertEqual(frame.depot, home.id, "it waits, uncrewed and empty, in the depot")
        XCTAssertEqual(frame.energy, 0)
        let adults = home.people.band(1)
        guard let fid = c.deploy(frame.id) else { return XCTFail("deploy failed") }
        XCTAssertEqual(home.people.band(1), adults - 1, "its pilot came from the city")
        XCTAssertFalse(c.send(fid, to: MP.chunkKey(2, 0)), "the pass is too narrow for a frame")
        let squad = CivForce(); squad.id = c.nextForce; c.nextForce += 1; squad.nation = n; squad.region = home.regionKey
        c.forces[squad.id] = squad
        var inf = CivUnit(); inf.id = c.nextUnit; c.nextUnit += 1; inf.kind = "infantry"; inf.nation = n; inf.force = squad.id; c.units[inf.id] = inf; squad.units = [inf.id]
        XCTAssertTrue(c.send(squad.id, to: MP.chunkKey(2, 0)), "riflemen climb through")
        c.forces[squad.id] = nil; c.units[inf.id] = nil
        XCTAssertEqual(c.audit(), [])
    }

    func testACarrierKeepsToDeepWaterAndRiflesCannotReachHighAircraft() {
        let c = Civ(seed: 1)
        let (n, home) = makeIndustrialNation(c) { $0.water = 0.5; $0.deep = 0.4; $0.land = 0.5 }
        land(c, 1...1) { $0.land = 0; $0.water = 1; $0.deep = 0.9 }
        land(c, 2...2)                                                     // dry land beyond
        guard c.order("carrier", nation: n, city: home.id) != nil else { return XCTFail("carrier order refused") }
        run(c, days: 20)
        guard let carrier = c.units.values.first(where: { $0.kind == "carrier" }), let fid = c.deploy(carrier.id) else { return XCTFail("no carrier") }
        XCTAssertEqual(c.forces[fid]?.layer, .sea)
        XCTAssertTrue(c.send(fid, to: MP.chunkKey(1, 0)), "out to sea")
        XCTAssertFalse(c.send(fid, to: MP.chunkKey(2, 0)), "never onto land")
        let rifle = CivUnitDef.byKey["infantry"]!.weapons[0], sam = CivUnitDef.byKey["air_defence"]!.weapons[0]
        XCTAssertFalse(rifle.layers.contains(.highAir), "small arms cannot reach a high fighter")
        XCTAssertTrue(sam.layers.contains(.highAir))
        XCTAssertFalse(sam.layers.contains(.nearSpace), "a cruising sky carrier needs long-range missiles")
    }

    func testCarrierAircraftFlyAStrikeAndComeBackAndLoseTheirDeckGracefully() {
        let c = Civ(seed: 1)
        let (n, home) = makeIndustrialNation(c) { $0.water = 0.5; $0.deep = 0.4; $0.land = 0.5 }
        land(c, 1...3) { $0.land = 0; $0.water = 1; $0.deep = 0.9 }
        let foe = c.newPolity(origin: "first", near: nil)
        land(c, 4...4)
        let enemy = city(c, 4, nation: foe, adults: 50, farms: 20, houses: 20, grain: 900)
        c.order("carrier", nation: n, city: home.id)
        for _ in 0..<4 { c.order("fighter", nation: n, city: home.id) }
        run(c, days: 24)
        let made = c.units.values.filter { $0.nation == n }.map { $0.kind }.sorted()
        XCTAssertEqual(made.filter { $0 == "carrier" }.count, 1); XCTAssertEqual(made.filter { $0 == "fighter" }.count, 4)
        let carrier = c.units.values.first { $0.kind == "carrier" }!
        guard let fid = c.deploy(carrier.id) else { return XCTFail("carrier not deployed") }
        for u in c.units.values.filter({ $0.kind == "fighter" }).sorted(by: { $0.id < $1.id }) { XCTAssertEqual(c.deploy(u.id, joining: fid), fid, "aboard") }
        XCTAssertEqual(c.forces[fid]!.units.count, 5)
        XCTAssertTrue(c.send(fid, to: MP.chunkKey(3, 0)))
        c.declare(n, on: foe)
        var launched = false, landed = false
        for _ in 0..<(24 * 6) {
            c.advance(to: c.time + day / 24)
            launched = launched || c.fights.contains { $0.kind == "launch" }
            landed = landed || c.fights.contains { $0.kind == "land" }
            if launched && landed { break }
        }
        XCTAssertTrue(launched, "aircraft took off on a mission"); XCTAssertTrue(landed, "and came back aboard")
        _ = enemy
        // the carrier is sunk with aircraft in the air: they divert to the home airfield or come down; nobody vanishes
        let before = c.audit()
        XCTAssertEqual(before, [])
        if let a = c.units.values.first(where: { $0.kind == "fighter" && $0.air == .parked }) {
            var b = a; b.air = .airborne; b.at = MP.chunkKey(2, 0); b.aloft = 8; c.units[a.id] = b
        }
        c.destroyed(carrier.id, by: foe, region: c.forces[fid]?.region ?? 0)
        XCTAssertNil(c.units[carrier.id])
        XCTAssertEqual(c.audit(), [], "crew, aircraft and pilots all accounted for")
        XCTAssertTrue(c.fights.contains { $0.kind == "divert" || $0.kind == "ditch" })
    }

    func testStrikesHurtWhenTheyLandAndOnlyIfTheTargetIsStillThere() {
        let c = Civ(seed: 1)
        land(c, 0...2)
        let a = c.newPolity(origin: "first", near: nil), b = c.newPolity(origin: "first", near: nil)
        c.polities[a]!.techs.append("radio")                              // radar: it sees a region away
        c.declare(a, on: b)
        func force(_ n: Int, _ kind: String, _ x: Int) -> (CivForce, Int) {
            let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = n; f.region = MP.chunkKey(x, 0)
            var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = kind; u.nation = n; u.force = f.id; u.hp = u.def.hp; u.ammo = 100; u.fuel = 100
            for p in u.def.parts { u.parts[p] = 1 }
            c.units[u.id] = u; f.units = [u.id]; f.crew = CivPeople(adults: u.def.crew); c.totals.newly += u.def.crew
            c.forces[f.id] = f
            return (f, u.id)
        }
        let (_, gun) = force(a, "artillery", 0)
        let (target, t) = force(b, "armour", 1)
        c.advance(to: c.time + day / 24 + 1)
        let fired = c.strikes.first { $0.shooter == gun }
        XCTAssertNotNil(fired, "the battery fired")
        XCTAssertEqual(c.units[t]!.hp, c.units[t]!.def.hp, "nothing hurts while the shell flies")
        target.region = MP.chunkKey(2, 0)                                // it drove off
        c.advance(to: c.time + day / 24)
        XCTAssertEqual(c.units[t]!.hp, c.units[t]!.def.hp, "the shell lands where it was, and misses")
        XCTAssertTrue(c.fights.contains { $0.kind == "miss" })
    }

    // MARK: nations

    func testRebelCitiesFormNewNationsAndOldNamesComeBack() {
        let c = Civ(seed: 21); land(c, 0...6)
        let empire = c.newPolity(origin: "first", near: nil), old = c.newPolity(origin: "first", near: nil)
        let cap = city(c, 0, nation: empire, adults: 200, farms: 80, houses: 80, grain: 9000)
        let far1 = city(c, 5, nation: empire, adults: 80, farms: 40, houses: 40, grain: 3000)
        let far2 = city(c, 6, nation: empire, adults: 80, farms: 40, houses: 40, grain: 3000)
        let mid = city(c, 2, nation: empire, adults: 80, farms: 40, houses: 40, grain: 3000)
        _ = cap
        c.polities[old]!.status = .exile; c.polities[old]!.exileSince = 0
        mid.culture = [old: 0.8, empire: 0.2]
        for t in [far1, far2, mid] { t.unrest = 1.2 }
        let before = c.activePolities().count
        run(c, days: 1)
        XCTAssertEqual(mid.nation, old, "a city that still feels it belongs to a fallen nation brings it back")
        XCTAssertEqual(c.polities[old]!.status, .active)
        XCTAssertEqual(far1.nation, far2.nation, "two neighbouring rebel cities go together")
        XCTAssertNotEqual(far1.nation, empire)
        XCTAssertEqual(c.activePolities().count, before + 2)
        XCTAssertEqual(c.audit(), [], "people were not moved or made by changing flags")
    }

    /// Several worlds left alone for a long time: every day adds up, nobody goes negative, no id is
    /// reused, nothing piles up without end, and the history that unfolds has nations rising and falling.
    func testLongRunsKeepTheBooksAndMakeHistory() {
        var events: [String: Int] = [:]
        for seed in [3, 8, 21] {
            let c = Civ(seed: seed)
            c.discover(around: TilePos(0, 0), radius: 8, gen: Generator(seed: seed))
            for d in 1...400 {
                c.advance(to: Double(d) * day)
                let a = c.audit()
                XCTAssertEqual(a, [], "seed \(seed) day \(d)")
                if !a.isEmpty { break }
            }
            let held = c.foodHeld(), want = c.foodExpected()
            for f in CivFood.all { XCTAssertEqual(held[f.key] ?? 0, want[f.key] ?? 0, accuracy: 0.05 + 1e-6 * abs(want[f.key] ?? 0), "\(f.key) seed \(seed)") }
            XCTAssertLessThanOrEqual(c.projects.count, c.polities.count, "no endless order book")
            XCTAssertLessThan(c.trips.count, 500)
            XCTAssertGreaterThan(c.polities.count, 3)
            XCTAssertGreaterThan(c.polities.values.map { $0.techs.count }.max()!, 12, "research moves on")
            for (k, v) in c.happened { events[k, default: 0] += v }
        }
        for k in ["war", "captured", "exile", "city_founded", "tech"] { XCTAssertGreaterThan(events[k] ?? 0, 0, "\(k) happened somewhere") }
        XCTAssertGreaterThan((events["restored"] ?? 0) + (events["seceded"] ?? 0) + (events["submitted"] ?? 0) + (events["federated"] ?? 0), 0, "nations broke away, came back or joined")
    }

    /// From the ground up, with no stock of anything made: ore and coal are mined, steel smelted, parts,
    /// engines, electronics, armour, weapons and reactor cores made, and from them a frame, a carrier with
    /// its aircraft and a sky carrier, each crewed from the city and put into service.
    func testFromOreToFrameCarrierAndSkyCarrier() {
        let c = Civ(seed: 1)
        land(c, 0...0) { $0.ore = 1; $0.coal = 1; $0.water = 0.5; $0.deep = 0.5; $0.land = 0.6; $0.oil = 1 }
        let n = c.newPolity(origin: "first", near: nil)
        c.polities[n]!.techs = CivTech.all.map { $0.key }
        c.polities[n]!.ai = false; c.polities[n]!.builds = false
        let t = city(c, 0, nation: n, adults: 6000, farms: 1500, houses: 1600, grain: 2e6)
        t.facilities = ["farm": 1500, "house": 1600, "well": 200, "granary": 2, "mine": 40, "oilwell": 4, "refinery": 4, "steelworks": 20, "factory": 30, "fab": 30,
                        "plant": 20, "fusion_plant": 3, "frame_works": 1, "deep_yard": 1, "aircraft_works": 1, "sky_yard": 1, "airfield": 1, "clinic": 30]
        XCTAssertNil(t.stock["steel"]); XCTAssertNil(t.stock["parts"])
        for k in ["frame", "carrier", "fighter", "fighter", "sky_carrier"] { XCTAssertNotNil(c.order(k, nation: n, city: t.id), k) }
        var done: Set<String> = []
        for _ in 0..<200 {
            run(c, days: 2)
            done = Set(c.units.values.map { $0.kind })
            if done.isSuperset(of: ["frame", "carrier", "fighter", "sky_carrier"]) && c.units.count == 5 { break }
        }
        XCTAssertEqual(done, ["frame", "carrier", "fighter", "sky_carrier"], "all made from mined ore (waiting on: \(c.projects.values.map { "\($0.kind):\($0.waiting)" }))")
        XCTAssertGreaterThan(t.ledger.made["steel"] ?? 0, 400, "the steel was smelted here")
        XCTAssertGreaterThan(t.ledger.made["core"] ?? 0, 6, "and the reactor cores made here")
        // into service: crews from the city, aircraft aboard the carrier
        let adults = t.people.band(1)
        guard let carrier = c.units.values.first(where: { $0.kind == "carrier" }), let fleet = c.deploy(carrier.id) else { return XCTFail("carrier") }
        for f in c.units.values.filter({ $0.kind == "fighter" }) { XCTAssertEqual(c.deploy(f.id, joining: fleet), fleet) }
        guard let frame = c.units.values.first(where: { $0.kind == "frame" }), let sky = c.units.values.first(where: { $0.kind == "sky_carrier" }) else { return XCTFail("missing") }
        XCTAssertNotNil(c.deploy(frame.id))
        XCTAssertNotNil(c.deploy(sky.id))
        XCTAssertEqual(adults - t.people.band(1), 400 + 2 * 2 + 1 + 300, "every crew member came from the city")
        XCTAssertEqual(c.audit(), [])
    }
}
