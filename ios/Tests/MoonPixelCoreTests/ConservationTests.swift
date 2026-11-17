import XCTest
@testable import MoonPixelCore

/// Nothing is made or lost when the regional layer and the detailed world hand people and goods to each
/// other. Every test here failed on v2.5 (9000c83) for the reason its name gives.
final class ConservationTests: XCTestCase {
    func hours(_ s: Society, _ n: Int) { for _ in 0..<n { s.tick(Society.hour) } }

    /// All nutrition there is: regional stores, roads and forces, plus what the detailed towns hold.
    func nutrition(_ s: Society) -> Double {
        let c = s.civ
        var n = 0.0
        for (k, v) in c.foodHeld() { n += v * (CivFood.byKey[k]?.nutrition ?? 1) }
        for t in s.settlements.values where !t.abandoned { n += t.food }
        return n
    }
    func people(_ s: Society) -> Int { s.agents.count + s.civ.people }

    func nearCity(_ s: Society, pop: Int = 12) -> CivCity? { s.civ.cities.values.filter { $0.detail == nil && $0.pop >= pop }.sorted { $0.id < $1.id }.first }
    func mid(_ s: Society, _ city: CivCity) -> TilePos { let z = s.civ.cfg.regionTiles; return TilePos(city.rx * z + z / 2, city.ry * z + z / 2) }
    /// One city comes into view a step; keep stepping until it is this one.
    func show(_ s: Society, _ city: CivCity) { for _ in 0..<12 where city.shownAs == nil { s.showNearby(s.civ, around: mid(s, city)) } }
    func far(_ s: Society, _ city: CivCity) -> TilePos { let z = s.civ.cfg.regionTiles; return TilePos(city.rx * z - 6 * z, city.ry * z) }

    func testShowingATownAddsNoFood() {
        let s = makeSociety(5)
        hours(s, 3)
        guard let city = nearCity(s) else { return XCTFail("no regional city") }
        let before = nutrition(s)
        s.showNearby(s.civ, around: mid(s, city))
        guard let town = s.settlements.values.first(where: { $0.fromCiv == city.id && !$0.abandoned }) else { return XCTFail("not shown") }
        XCTAssertEqual(nutrition(s), before, accuracy: 1e-6, "v2.5 gave every shown town 10 food from nowhere")
        let handed = (town.goodsFromCiv ?? [:]).reduce(0.0) { $0 + $1.value * (CivFood.byKey[$1.key]?.nutrition ?? 1) }
        XCTAssertEqual(town.food, handed, accuracy: 1e-9, "the town holds exactly what left the city's stores")
    }

    /// With time standing still, a town shown and folded away a hundred times: the same people by age and
    /// hunger, the same food by kind, the same wood and stone. Nothing drifts.
    func testAHundredRoundTripsChangeNothing() {
        let s = makeSociety(5)
        hours(s, 3)
        let c = s.civ
        guard let city = nearCity(s, pop: 30) else { return XCTFail("no regional city") }
        // a mixed, hungry population and mixed stores, so there is something to get wrong
        // (the same number of people, spread over every age and hunger state)
        let n = city.people.total
        city.people = CivPeople()
        for i in 0..<n { city.people.n[(i * 7) % 18] += 1 }
        let had = city.stock
        for k in ["grain", "meat", "bread", "ration"] { let v = 120.0; c.totals.add(\.found, k, v); city.stock[k, default: 0] += v }
        _ = had
        let people0 = city.people, stock0 = city.stock, all0 = people(s), nut0 = nutrition(s)
        for round in 0..<100 {
            s.showNearby(c, around: mid(s, city))
            guard city.shownAs != nil else { return XCTFail("round \(round): not shown") }
            XCTAssertEqual(people(s), all0, "round \(round): shown")
            s.foldAway(c, from: far(s, city))
            XCTAssertNil(city.shownAs, "round \(round)")
            XCTAssertEqual(city.people, people0, "round \(round): the same people by age and hunger")
            for (k, v) in stock0 { XCTAssertEqual(city.stock[k] ?? 0, v, accuracy: 1e-6, "round \(round): \(k)") }
            XCTAssertEqual(nutrition(s), nut0, accuracy: 1e-5, "round \(round)")
        }
        XCTAssertEqual(people(s), all0)
        XCTAssertEqual(c.totals.toDetail, c.totals.fromDetail, "as many handed back as handed over")
        XCTAssertEqual(c.audit(), [], "people \(c.people) newly \(c.totals.newly) to \(c.totals.toDetail ?? 0) from \(c.totals.fromDetail ?? 0)")
        let held = c.foodHeld(), want = c.foodExpected()
        for f in CivFood.all { XCTAssertEqual(held[f.key] ?? 0, want[f.key] ?? 0, accuracy: 0.01, f.key) }
    }

    /// Food eaten in the town is gone; what is left goes back in the kinds it came in, not all as grain.
    func testFoodGoesBackByKindAndOnlyWhatIsLeft() {
        let s = makeSociety(5)
        hours(s, 3)
        let c = s.civ
        guard let city = nearCity(s, pop: 30) else { return XCTFail("no regional city") }
        city.stock = city.stock.filter { !CivFood.isFood($0.key) }
        for (k, v) in c.foodHeld() { _ = k; _ = v }
        c.totals.add(\.found, "ration", 400); city.stock["ration"] = 400      // 2.0 nutrition each: the only food it has
        let grain0 = city.stock["grain"] ?? 0
        s.showNearby(c, around: mid(s, city))
        guard let town = s.settlements.values.first(where: { $0.fromCiv == city.id && !$0.abandoned }) else { return XCTFail("not shown") }
        let handed = town.goodsFromCiv?["ration"] ?? 0
        XCTAssertGreaterThan(handed, 0)
        XCTAssertEqual(town.food, handed * 2, accuracy: 1e-9, "counted by nutrition")
        town.food /= 2                                                           // half of it is eaten
        s.foldAway(c, from: far(s, city))
        XCTAssertEqual(city.stock["ration"] ?? 0, 400 - handed / 2, accuracy: 1e-6, "half came back, as rations")
        XCTAssertEqual(city.stock["grain"] ?? 0, grain0, accuracy: 1e-9, "v2.5 turned every unit of nutrition into one grain")
    }

    func makeFoe(_ s: Society, at city: CivCity, crew: CivPeople, food: [String: Double]) -> CivForce {
        let c = s.civ
        let foe = c.newPolity(origin: "first", near: nil)
        c.polities[foe]!.ai = false; c.polities[city.nation]!.ai = false
        c.declare(foe, on: city.nation)
        let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = foe; f.region = city.regionKey
        var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = "levy"; u.nation = foe; u.force = f.id; u.hp = 100
        c.units[u.id] = u; f.units = [u.id]; f.crew = crew; c.totals.newly += crew.total
        f.food = food; for (k, v) in food { c.totals.add(\.found, k, v) }
        c.forces[f.id] = f
        return f
    }

    /// An enemy camp is supplied by its force and by nothing else, and striking it gives back the soldiers
    /// as hungry as they are and the food that is left.
    func testACampTakesItsFoodFromItsForceAndGivesBackItsHungrySoldiers() {
        let s = makeSociety(5)
        hours(s, 3)
        let c = s.civ
        guard let city = nearCity(s, pop: 30) else { return XCTFail("no regional city") }
        s.showNearby(c, around: mid(s, city))
        var crew = CivPeople(); crew.n[6] = 10; crew.n[8] = 12; crew.n[10] = 8          // fed, hungry, starving
        let f = makeFoe(s, at: city, crew: crew, food: ["grain": 60])
        let nut0 = nutrition(s), all0 = people(s)
        s.showInvaders(c)
        guard let camp = s.settlements.values.first(where: { $0.campOf == f.id }) else { return XCTFail("no camp") }
        XCTAssertEqual(nutrition(s), nut0, accuracy: 1e-6, "v2.5 gave every camp 200 food, 20 wood, 2 engines and a weapon a head")
        XCTAssertEqual(camp.food, 60, accuracy: 1e-9, "all the force had; it wanted more")
        XCTAssertEqual(f.food["grain"] ?? 0, 0, accuracy: 1e-9)
        XCTAssertEqual(camp.wood, 0); XCTAssertEqual(camp.good("engines"), 0, "a force of people brings no engines"); XCTAssertEqual(camp.good("weapons"), 0)
        let soldiers = camp.members.compactMap { s.agents[$0] }
        XCTAssertEqual(soldiers.count, f.lent)
        XCTAssertTrue(soldiers.allSatisfy { $0.lent == f.id }, "each one is bound to the force that lent them")
        XCTAssertTrue(soldiers.contains { $0.hunger > 0.9 }, "the starving came as starving (v2.5 made everyone fed)")
        XCTAssertEqual(people(s), all0)
        // one dies in the detailed world; the rest go back as they are
        let lentStates = soldiers.map { s.peopleSlot($0, s.world.time) % 6 }.sorted()
        camp.food = 20
        s.realm.legions.removeAll { $0.nation == f.nation && $0.state != 0 }
        s.foldCamps(c, from: far(s, city))
        XCTAssertTrue(camp.abandoned)
        XCTAssertNil(f.lent)
        XCTAssertEqual(f.crew.total, 30, "everyone alive went back to the force")
        XCTAssertEqual(f.crew.n[6 + 4] + f.crew.n[6 + 5], 8, "the starving are still starving (v2.5 returned plain adults)")
        XCTAssertEqual(f.food["grain"] ?? 0, 20, accuracy: 1e-9, "what was left of its food went back")
        _ = lentStates
        XCTAssertEqual(c.audit(), [])
    }

    /// Soldiers a force lends to a town of its own go back to that force, however many other forces of
    /// the nation there are, and the ones who died do not come back out of the town's people.
    func testLentSoldiersGoBackToTheForceThatLentThem() {
        let s = makeSociety(5)
        hours(s, 3)
        let c = s.civ
        guard let city = nearCity(s, pop: 40) else { return XCTFail("no regional city") }
        func force(_ n: Int, region: Int64) -> CivForce {
            let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = city.nation; f.region = region; f.home = city.id
            var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = "levy"; u.nation = city.nation; u.force = f.id; u.hp = 100
            c.units[u.id] = u; f.units = [u.id]; f.crew = city.people.takeAdults(n); f.food = [:]
            c.forces[f.id] = f
            return f
        }
        let near = force(16, region: city.regionKey), elsewhere = force(6, region: city.regionKey &+ 977)
        show(s, city)
        s.showForces(c)
        guard let town = s.settlements.values.first(where: { $0.fromCiv == city.id && !$0.abandoned }), let lent = near.lent else { return XCTFail("nothing lent: shown \(String(describing: city.shownAs)) agents \(s.agents.count)/\(s.world.budget.maxAgents) crew \(near.crew.n)") }
        XCTAssertNil(elsewhere.lent); XCTAssertEqual(near.lentTown, town.id)
        let mine = town.members.compactMap { s.agents[$0] }.filter { $0.lent == near.id }
        XCTAssertEqual(mine.count, lent)
        s.die(mine[0], "battle")                                   // one falls while lent
        let cityBefore = city.people.total, residents = town.members.compactMap { s.agents[$0] }.filter { $0.lent == nil }.count
        s.foldAway(c, from: far(s, city))
        XCTAssertEqual(near.crew.total, 16 - 1, "the fallen one is not replaced out of the town's people (v2.5 took the full number back from the city)")
        XCTAssertEqual(elsewhere.crew.total, 6, "another force of the same nation gets nobody (v2.5 matched by nation)")
        XCTAssertEqual(city.people.total, cityBefore + residents, "the town's own people all went back to the city")
        XCTAssertNil(near.lent); XCTAssertNil(near.lentTown)
    }
}
