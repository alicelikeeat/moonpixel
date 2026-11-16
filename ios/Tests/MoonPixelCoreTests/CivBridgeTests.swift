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
}
