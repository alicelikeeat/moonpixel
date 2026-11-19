import XCTest
@testable import MoonPixelCore

final class AllyFavorTests: XCTestCase {
    func testAWolfBitesThenBacksOffAndGivesUpInsteadOfBitingForever() {
        let s = makeSociety(5)
        let me = s.world.findFree(near: TilePos(400, -300), maxR: 30).center
        s.realm.fauna.animals = []
        s.realm.fauna.maxNear = 0
        s.spawnAnimal("wolf", at: me + Vec2(10, 0))
        var bitten = 0.0, bites = 0
        for _ in 0..<(60 * 4) {
            let b = s.faunaTick(0.25, viewer: me, mazeHere: false)
            if b > 0 { bites += 1 }
            bitten += b
        }
        XCTAssertGreaterThan(bites, 1, "it does bite")
        XCTAssertLessThan(bites, 25, "but with pauses between bites, and not for ever (\(bites) bites)")
        XCTAssertLessThan(bitten, 150, "a minute near a wolf does not kill outright")
        let w = s.realm.fauna.animals.first { $0.species.key == "wolf" }!
        XCTAssertGreaterThan(w.pos.distance(to: me), 18, "in the end it keeps away")
    }

    func testRanchCattleStayOnTheRanch() {
        let s = makeSociety(5)
        let o = s.world.findFree(near: TilePos(-300, 260), maxR: 40)
        let d = s.foundDistrict(name: "Ranch", at: o, nation: 1, money: 1_000_000, store: ["stone": 50_000, "planks": 50_000, "iron": 9000, "parts": 9000])
        guard let id = nycPut(s, d, "ranch"), let b = d.building(id) else { return XCTFail("ranch") }
        let home = TilePos(b.x + b.w / 2, b.y + b.d / 2).center
        let far = home + Vec2(3000, 0)                 // the traveller is far away
        for _ in 0..<200 { _ = s.faunaTick(0.5, viewer: far, mazeHere: false) }
        let herd = s.realm.fauna.animals.filter { $0.home != nil }
        XCTAssertGreaterThanOrEqual(herd.count, 6)
        for a in herd { XCTAssertLessThan(a.pos.distance(to: home), 16 * 14, "grazing at home") }
    }

    func testAlliesComeToTheDefenceAndFightHarderTogether() {
        let s = makeSociety(7)
        let ids = s.realm.nations.filter { $0.exileSince == nil }.map { $0.id }.sorted()
        guard ids.count >= 3 else { return XCTFail("three nations") }
        let a = ids[0], b = ids[1], c = ids[2]
        // make peace all round, then b and c allies
        for r in s.realm.relations.indices { s.realm.relations[r].state = 0; s.realm.relations[r].pact = false; s.realm.relations[r].value = 0 }
        if let r = s.realm.ri(b, c) { s.realm.relations[r].pact = true }
        XCTAssertEqual(s.allies(of: b), [c])
        XCTAssertEqual(s.allianceBonus(c), 1, "no bonus at peace")
        s.declare(a, on: b)
        XCTAssertTrue(s.realm.atWar(a, b))
        XCTAssertTrue(s.realm.atWar(c, a), "the ally went to war with the attacker")
        XCTAssertTrue((s.realm.chron ?? []).contains { $0.kind == "ally_aid" })
        XCTAssertGreaterThan(s.allianceBonus(b), 1.2, "fighting side by side, they fight harder")
        XCTAssertGreaterThan(s.allianceBonus(c), 1.2)
        XCTAssertEqual(s.allianceBonus(a), 1, "the attacker has no ally in this")
    }

    func testPlacesNearTheTravellerThriveAndNobodyDiesThereUntilTheyLeave() {
        let s = makeSociety(7)
        guard let t = s.settlements.values.filter({ !$0.abandoned }).min(by: { $0.id < $1.id }) else { return XCTFail("town") }
        var b = s.realm.player.body ?? Body(at: t.center.center, z: 0, depth: 0)
        b.x = t.center.center.x; b.y = t.center.center.y
        s.realm.player.body = b
        s.favorHour()
        XCTAssertTrue(s.favored(town: t.id), "the town by the traveller is favoured")
        // nobody there dies of hunger
        if let a = t.members.compactMap({ s.agents[$0] }).first {
            a.health = 0; a.hunger = 1
            s.realmTick(1)
            XCTAssertTrue(a.alive)
        }
        // the traveller goes far away: the favour lasts a few days, then lapses
        b.x += 30_000 * 16; s.realm.player.body = b
        s.world.time += MP.daySeconds
        s.favorHour()
        XCTAssertTrue(s.favored(town: t.id), "still favoured a day after leaving")
        s.world.time += (Society.favorDays + 0.5) * MP.daySeconds
        s.favorHour()
        XCTAssertFalse(s.favored(town: t.id), "lapsed once the traveller has been gone long enough")
    }

    func testTheDetailedMapNamesBuildings() {
        let s = makeSociety(5)
        let o = s.world.findFree(near: TilePos(-300, 260), maxR: 40)
        let d = s.foundDistrict(name: "Named", at: o, nation: 1, money: 1_000_000, store: ["stone": 50_000, "planks": 50_000, "iron": 9000, "parts": 9000])
        XCTAssertNotNil(nycPut(s, d, "pool"))
        var b = s.realm.player.body ?? Body(at: o.center, z: 0, depth: 0); b.x = o.center.x; b.y = o.center.y; s.realm.player.body = b
        let map = WorldMap()
        let coarse = map.render(s, centre: o, reach: 30, zh: false).1
        XCTAssertFalse(coarse.contains { $0.kind == .building }, "the whole map does not name every house")
        let fine = map.render(s, centre: o, reach: 6, ppc: 96, zh: false).1
        XCTAssertTrue(fine.contains { $0.kind == .building && $0.name == "Swimming pool" }, "the detailed map names the pool at its door")
    }
}
