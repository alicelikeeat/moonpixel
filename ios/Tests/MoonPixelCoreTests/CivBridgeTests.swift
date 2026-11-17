import XCTest
@testable import MoonPixelCore

/// The civilisation layer inside a real world: the realm's nations are its nations, the towns are its
/// detailed cities (counted once), and the number of nations is whatever history makes it.
final class CivBridgeTests: XCTestCase {
    func hours(_ s: Society, _ n: Int) { for _ in 0..<n { s.tick(Society.hour) } }

    func testAWorldFindsMoreNationsAroundItsTownsAndCountsNobodyTwice() {
        let s = makeSociety(5)
        hours(s, 3)
        let c = s.civ
        for n in s.realm.nations { XCTAssertEqual(c.polities[n.id]?.nameEn, n.nameEn, "the realm's nations keep their ids and names"); XCTAssertTrue(c.polities[n.id]!.detailed) }
        XCTAssertGreaterThan(c.polities.count, 3, "beyond the first three, city-states in the lands around")
        XCTAssertGreaterThan(c.nextNation, c.polities.keys.max()!, "the next id is new")
        let towns = s.settlements.values.filter { !$0.abandoned }.count
        let detailed = c.cities.values.filter { $0.detail != nil }
        XCTAssertGreaterThan(detailed.count, 0); XCTAssertLessThanOrEqual(detailed.count, towns)
        XCTAssertEqual(s.knownPopulation, s.agents.count + c.people, "townsfolk once, regional people once")
        XCTAssertEqual(c.audit(), [])
        // no city-state is made up on top of a real town
        for t in detailed { XCTAssertNil(c.cities.values.first { $0.detail == nil && $0.regionKey == t.regionKey }) }
        // the camera does not find land: only walking does
        let known = c.regions.count
        s.viewer = Vec2(90000, 90000); hours(s, 1)
        XCTAssertEqual(c.regions.count, known)
        s.explorer = TilePos(5600, 5600); hours(s, 1)
        XCTAssertGreaterThan(c.regions.count, known)
    }

    func testTheLayerIsSavedWithTheWorldAndGoesOnTheSame() throws {
        let s = makeSociety(7)
        hours(s, 30)
        let data = try JSONEncoder().encode(s.snapshot())
        let w2 = OpenWorld(seed: s.world.seed, budget: MemoryBudget(overrideMB: 256)); w2.time = s.world.time
        let s2 = Society(world: w2, seed: s.world.seed)
        s2.restore(try JSONDecoder().decode(Society.Snapshot.self, from: data))
        XCTAssertEqual(s2.civ.digest(), s.civ.digest(), "the regional world comes back exactly")
        // a save from before the layer existed opens and gains it, with the old nations as they were
        var old = s.snapshot(); old.realm?.civBox = nil
        let s3 = Society(world: OpenWorld(seed: s.world.seed, budget: MemoryBudget(overrideMB: 256)), seed: s.world.seed)
        s3.restore(old)
        XCTAssertEqual(Set(s3.civ.polities.keys).intersection(s.realm.nations.map { $0.id }), Set(s.realm.nations.map { $0.id }))
        XCTAssertEqual(s3.agents.count, s.agents.count, "no one lost in the migration")
    }

    func testAfterEveryoneIsGoneNewPeoplesComeWithNewNames() {
        let s = makeSociety(9, villages: 3, per: 4)
        hours(s, 2)
        let old = Set(s.realm.nations.map { $0.id })
        for a in Array(s.agents.values) { s.die(a, "illness") }
        s.restart()                                   // the world is empty: say so, and wait out the hold
        s.realm.immigrationHold = 0
        s.restart()                                   // then settlers come
        XCTAssertFalse(s.agents.isEmpty, "settlers came")
        let living = s.realm.nations.filter { ($0.status ?? 0) != 2 }
        XCTAssertFalse(living.isEmpty)
        XCTAssertTrue(Set(living.map { $0.id }).isDisjoint(with: old), "new peoples, not the old three brought back")
        for n in s.realm.nations where old.contains(n.id) { XCTAssertEqual(n.status, 2, "the old ones passed into history") }
        XCTAssertEqual(Set(s.realm.nations.map { $0.id }).count, s.realm.nations.count, "no id given twice")
        hours(s, 1)
        for n in living { XCTAssertNotNil(s.civ.polities[n.id]) }
    }

    func testADividedRealmSplitsIntoAsManyNationsAsThereArePeoples() {
        let s = makeSociety(4)
        hours(s, 2)
        // everyone but one people forgets their old loyalty; a united realm breaks into two, not three
        let towns = s.settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        guard towns.count >= 2 else { return XCTFail("needs towns") }
        for (i, t) in towns.enumerated() { for m in t.members { s.agents[m]?.nation = i == 0 ? 2 : 1 } }
        for t in towns { t.nation = 1 }
        for lg in s.realm.legions { lg.nation = 1 }
        s.landCheck(); hours(s, 1)
        XCTAssertEqual(s.realm.era, 1)
        XCTAssertTrue(s.split())
        let held = Set(s.settlements.values.filter { !$0.abandoned }.compactMap { $0.nation })
        XCTAssertEqual(held, [1, 2], "two peoples, two nations")
        // and with a single people left, there is nothing to divide: unity holds, without a timer forcing it apart
        for t in towns { t.nation = 1; for m in t.members { s.agents[m]?.nation = 1 } }
        s.landCheck(); hours(s, 1)
        XCTAssertFalse(s.split())
        s.realm.cfg.unityMax = 0.01
        s.realm.eraSince = s.world.time - 10 * MP.year
        hours(s, 2)
        XCTAssertEqual(s.realm.era, 1, "no timer splits a realm that holds together")
    }

    /// Walking up to a regional city shows it as a real town under its own flag, with people handed over
    /// from it (not made); walking away folds them back. Nobody is gained or lost either way.
    func testARegionalCityBecomesARealTownWhenNearAndFoldsBackWhenLeft() {
        let s = makeSociety(5)
        hours(s, 3)
        let c = s.civ
        guard let city = c.cities.values.filter({ $0.detail == nil && $0.pop >= 12 }).sorted(by: { $0.id < $1.id }).first else { return XCTFail("no regional city near") }
        let size = c.cfg.regionTiles
        let agents0 = s.agents.count, cityPop = city.pop
        s.explorer = TilePos(city.rx * size + size / 2, city.ry * size + size / 2)
        hours(s, 1)
        guard let town = s.settlements.values.first(where: { $0.fromCiv == city.id && !$0.abandoned }) else { return XCTFail("the city did not come into view") }
        XCTAssertEqual(town.nation, city.nation, "under its own flag")
        XCTAssertEqual(s.realm.nation(city.nation)?.regional, true)
        let shown = town.members.count
        XCTAssertGreaterThan(shown, 0)
        XCTAssertEqual(s.agents.count - agents0, shown, "real residents")
        XCTAssertEqual(city.pop, cityPop - shown, "handed over, not copied")
        XCTAssertEqual(c.totals.toDetail, shown, "the regional ledger counts out exactly who the town counts in")
        XCTAssertEqual(c.audit(), [])
        // walk far away: the town folds back into the regional city
        let living = town.members.count
        s.explorer = TilePos(city.rx * size - 6 * size, city.ry * size)
        hours(s, 1)
        XCTAssertTrue(town.abandoned)
        XCTAssertNil(city.shownAs)
        XCTAssertEqual(c.totals.fromDetail, living, "everyone living there went back into the regional count")
        XCTAssertTrue(s.agents.values.allSatisfy { $0.sid != town.id }, "no resident left behind in an empty town")
        XCTAssertEqual(c.audit(), [])
        let held = c.foodHeld(), want = c.foodExpected()
        for f in CivFood.all { XCTAssertEqual(held[f.key] ?? 0, want[f.key] ?? 0, accuracy: 0.01 + 1e-6 * abs(want[f.key] ?? 0), f.key) }
    }

    /// With the traveller there, the regional layer is real: a tower stands as storeys, a force lends real
    /// soldiers (who go back to it afterwards), machines have pictures, and a battle fought by hand counts once.
    func testNearTheTravellerTowersSoldiersMachinesAndCampaignsAreReal() {
        let s = makeSociety(5)
        hours(s, 3)
        let c = s.civ
        guard let city = c.cities.values.filter({ $0.detail == nil && $0.pop >= 30 }).sorted(by: { $0.id < $1.id }).first else { return XCTFail("no regional city") }
        // the city has a six-floor tower and a force at home
        let home = Blueprint.plan(use: .home, w: 12, d: 10, layout: 0, seed: 1)
        c.towerIndex.plans[home.key] = home
        let t = Tower(base: Cell3(0, 0, 0)); t.id = c.towerIndex.nextTower; c.towerIndex.nextTower += 1
        t.city = city.id; t.nation = city.nation; t.w = 12; t.d = 10; t.material = 2; t.nameEn = "Spire"
        t.floors = (0..<6).map { var f = TowerFloor(z: Int64($0 * 4), plan: home.key); f.stage = .inUse; return f }
        c.towerIndex.towers[t.id] = t
        let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = city.nation; f.region = city.regionKey; f.home = city.id
        var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = "levy"; u.nation = city.nation; u.force = f.id; u.hp = 100
        c.units[u.id] = u; f.units = [u.id]; f.crew = city.people.takeAdults(20); f.food = ["grain": 0]
        c.forces[f.id] = f
        XCTAssertEqual(c.audit(), [])
        let size = c.cfg.regionTiles
        s.explorer = TilePos(city.rx * size + size / 2, city.ry * size + size / 2)
        hours(s, 2)
        guard let town = s.settlements.values.first(where: { $0.fromCiv == city.id && !$0.abandoned }) else { return XCTFail("not shown") }
        XCTAssertEqual(t.real, true, "the tower was built for real")
        XCTAssertGreaterThanOrEqual(s.realm.storeyTop ?? 0, 5, "five storeys above its ground floor")
        XCTAssertNotEqual(s.storeyWorld(5).tile(0, town.center.x + 14, town.center.y - 14), 0, "a floor on its top storey")
        XCTAssertNotNil(f.lent, "the force lent soldiers to the town")
        let soldiers = town.members.compactMap { s.agents[$0] }.filter { $0.legion != nil }.count
        XCTAssertGreaterThan(soldiers, 0, "real soldiers in its garrison")
        XCTAssertEqual(f.crew.total, 20 - (f.lent ?? 0), "counted out of the force")
        XCTAssertEqual(c.audit(), [])
        XCTAssertTrue(s.machinesInView().contains { $0.kind == "levy" }, "its machines are in view")
        for k in CivUnitDef.all { XCTAssertTrue(PixelArt.civUnit(k.key, color: RGBA(200, 60, 60)).px.contains { $0 != 0 }, "a picture of \(k.key)") }
        XCTAssertNotEqual(PixelArt.civUnit("frame", color: RGBA(200, 60, 60)).px, PixelArt.civUnit("carrier", color: RGBA(200, 60, 60)).px)
        // away again: the soldiers are back with their force
        s.explorer = TilePos(city.rx * size - 6 * size, city.ry * size)
        hours(s, 1)
        XCTAssertNil(f.lent); XCTAssertEqual(f.crew.total, 20)
        XCTAssertEqual(c.audit(), [])
        // a campaign: staked once, settled once
        let foe = c.newPolity(origin: "first", near: nil)
        c.polities[city.nation]!.treasury = 1000
        c.declare(city.nation, on: foe)
        guard let camp = c.beginCampaign(city.nation) else { return XCTFail("no campaign") }
        XCTAssertEqual(camp.stake, 200); XCTAssertEqual(c.polities[city.nation]!.treasury, 800)
        XCTAssertEqual(c.beginCampaign(city.nation)?.id, camp.id, "the same battle while it lasts: not staked twice")
        XCTAssertEqual(c.polities[city.nation]!.treasury, 800)
        XCTAssertTrue(c.settleCampaign(won: true)); XCTAssertFalse(c.settleCampaign(won: true), "settled once")
        XCTAssertEqual(c.polities[city.nation]!.treasury, 1200)
    }
}
