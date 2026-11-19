import XCTest
@testable import MoonPixelCore

/// Envoys, vassals, wars for a place and the tenfold rule (task book sections 3 and 4).
final class DiplomacyTests: XCTestCase {
    let day = MP.daySeconds

    // MARK: the table

    func testWinChanceTableAndTheWorkedExample() {
        let b = WarBalance()
        for (r, p) in zip(b.ratioNodes, b.winNodes) { XCTAssertEqual(b.winChance(r), p, accuracy: 1e-9, "node \(r)") }
        XCTAssertEqual(b.winChance(0.25), 0.10, accuracy: 1e-9, "below 0.5 : 1 it falls to nothing")
        XCTAssertEqual(b.winChance(0), 0)
        // the task book's example: 6,000 of 12,000 arrive, supply 0.8, landing 0.75, against 1,000
        let first = WarBalance.contribution(count: 6000, base: 1, supply: 0.8, terrain: b.landing)
        XCTAssertEqual(first / 1000, 3.6, accuracy: 1e-9)
        XCTAssertEqual(b.winChance(3.6), 0.7567, accuracy: 0.0005, "about 76 %")
        XCTAssertEqual(b.chanceText(3.6, zh: true), "76%")
        // a bigger port takes all 10,000 the fleet carries: 6 : 1; supply restored: 7.5 : 1
        XCTAssertEqual(WarBalance.contribution(count: 10000, base: 1, supply: 0.8, terrain: b.landing) / 1000, 6, accuracy: 1e-9)
        XCTAssertEqual(WarBalance.contribution(count: 10000, base: 1, supply: 1, terrain: b.landing) / 1000, 7.5, accuracy: 1e-9)
        // with the port taken there is no landing: only then ten to one
        XCTAssertEqual(WarBalance.contribution(count: 10000, base: 1) / 1000, 10, accuracy: 1e-9)
        XCTAssertEqual(b.winChance(10), 1)
        // just under ten never reads as certain
        XCTAssertLessThan(b.winChance(9.9), 1)
        XCTAssertEqual(b.chanceText(9.9, zh: true), "约 99%，仍可能撤军")
        XCTAssertEqual(b.chanceText(10, zh: true), "100%（十倍兵力，必胜）")
    }

    // MARK: a small world: a strong nation in the west, a small port nation in the east

    struct World { let c: Civ; let big: Int; let small: Int; let capital: CivCity; let port: CivCity }

    func world(seed: Int = 1) -> World {
        let c = Civ(seed: seed)
        c.envoys = true
        for x in 0...12 {
            var r = CivRegion(); r.rx = x; r.ry = 0; r.land = 1; r.fertility = 0.7; c.regions[r.key] = r
            var s = CivRegion(); s.rx = x; s.ry = 1; s.water = 1; s.deep = 0.6; c.regions[s.key] = s
        }
        let big = c.newPolity(origin: "first", near: nil), small = c.newPolity(origin: "first", near: nil)
        let cap = c.newCity(at: MP.chunkKey(0, 0), nation: big, people: CivPeople(adults: 200), firstCount: true)
        let port = c.newCity(at: MP.chunkKey(10, 0), nation: small, people: CivPeople(adults: 40), firstCount: true)
        _ = c.newCity(at: MP.chunkKey(12, 0), nation: small, people: CivPeople(adults: 20), firstCount: true)     // a second town: it lives on
        c.polities[big]!.capital = cap.id; c.polities[small]!.capital = port.id
        c.polities[big]!.treasury = 1000; c.polities[small]!.treasury = 500
        c.refreshTerritory()
        return World(c: c, big: big, small: small, capital: cap, port: port)
    }

    @discardableResult func force(_ c: Civ, _ n: Int, _ kind: String, count: Int, at k: Int64, layer: CivLayer = .ground) -> CivForce {
        let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = n; f.region = k; f.layer = layer
        for _ in 0..<count {
            var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = kind; u.nation = n; u.force = f.id; u.hp = u.def.hp; u.ammo = 100; u.fuel = 100
            for p in u.def.parts { u.parts[p] = 1 }
            c.units[u.id] = u; f.units.append(u.id)
        }
        f.crew = CivPeople(adults: 10 * count); c.totals.newly += 10 * count
        f.food = ["ration": 1e5]; c.totals.add(\.found, "ration", 1e5)
        c.forces[f.id] = f
        return f
    }

    // MARK: envoys

    func testAnEnvoyGoesOnlyWhenThreeTimesStrongerAndIsAnsweredOnce() {
        let w = world()
        let c = w.c
        force(c, w.small, "infantry", count: 1, at: w.port.regionKey)
        force(c, w.big, "infantry", count: 2, at: w.capital.regionKey)
        XCTAssertNil(c.sendEnvoy(w.big, to: w.small), "not three times stronger: no envoy")
        force(c, w.big, "infantry", count: 4, at: w.capital.regionKey)
        let id = c.sendEnvoy(w.big, to: w.small)
        XCTAssertNotNil(id)
        XCTAssertNil(c.sendEnvoy(w.big, to: w.small), "one envoy at a time")
        let e = c.envoysOut.first { $0.id == id }!
        XCTAssertEqual(e.targetKind, "port", "a port is wanted first")
        XCTAssertEqual(e.target, w.port.id)
        XCTAssertGreaterThan(e.arrives, c.time)
        // saved on the way and opened again: answered once, the same way, in both
        let copy = try! JSONDecoder().decode(Civ.self, from: try! JSONEncoder().encode(c))
        for x in [c, copy] { x.advance(to: e.arrives + day * 2) }
        for x in [c, copy] {
            let answered = x.envoysOut.filter { $0.id == id && $0.state != .travelling }
            XCTAssertEqual(answered.count, 1)
            XCTAssertEqual((x.happened["vassal"] ?? 0) + (x.happened["envoy_refused"] ?? 0), 1, "answered exactly once")
        }
        XCTAssertEqual(c.envoysOut.first { $0.id == id }!.state, copy.envoysOut.first { $0.id == id }!.state)
    }

    func testSubmissionMakesATributaryVassalAndNeverACircle() {
        let w = world()
        let c = w.c
        c.cfg.war.refuse = 0; c.cfg.war.refuseFortified = 0
        force(c, w.big, "infantry", count: 8, at: w.capital.regionKey)
        let id = c.sendEnvoy(w.big, to: w.small)!
        c.advance(to: c.envoysOut[0].arrives + day * 3)
        XCTAssertEqual(c.envoysOut.first { $0.id == id }!.state, .submitted)
        XCTAssertEqual(c.suzerain(of: w.small), w.big)
        XCTAssertEqual(w.port.nation, w.small, "it keeps its towns")
        XCTAssertEqual(c.polities[w.small]!.capital, w.port.id, "and its capital")
        XCTAssertEqual(c.polities[w.small]!.status, .active, "and its name")
        XCTAssertGreaterThan(c.vassals[0].paid, 0, "tribute is paid")
        XCTAssertFalse(c.makeVassal(w.big, of: w.small), "no circle of vassals")
        let third = c.newPolity(origin: "first", near: nil)
        XCTAssertTrue(c.makeVassal(third, of: w.small))
        XCTAssertTrue(c.vassalCycle(w.big, third), "a longer circle is refused too")
        XCTAssertNotNil(c.envoyBlocked(w.big, w.small), "no envoy to one's own vassal")
        // the suzerain passes into history: the vassal is free
        c.polities[w.big]!.status = .history
        c.advance(to: c.time + day * 2)
        XCTAssertNil(c.suzerain(of: w.small))
    }

    // MARK: wars for a place

    func testARefusalBecomesAWarForThePortAndAirAloneCannotTakeIt() {
        let w = world()
        let c = w.c
        c.cfg.war.refuse = 1; c.cfg.war.refuseFortified = 1
        force(c, w.big, "infantry", count: 8, at: w.capital.regionKey)
        _ = c.sendEnvoy(w.big, to: w.small)!
        c.advance(to: c.envoysOut[0].arrives + day * 0.2)
        XCTAssertEqual(c.envoysOut[0].state, .refused)
        XCTAssertTrue(c.atWar(w.big, w.small))
        XCTAssertEqual(c.targetWars.count, 1)
        XCTAssertEqual(c.targetWars[0].target, w.port.id)
        // fighters over the port, nobody on the ground there: the city cannot be taken
        let air = force(c, w.big, "fighter", count: 4, at: w.port.regionKey, layer: .highAir)
        _ = air
        c.forces.values.filter { $0.nation == w.big && $0.layer == .ground }.forEach { $0.path = []; $0.region = w.capital.regionKey }
        var i = 0
        while c.targetWars[0].stage == .muster && i < 100 { c.advance(to: c.time + day / 24); i += 1 }
        // keep the ground forces home for a day: only the fighters are there
        for f in c.forces.values where f.nation == w.big && f.layer == .ground { f.path = []; f.region = w.capital.regionKey }
        c.advance(to: c.time + day / 6)
        XCTAssertEqual(w.port.nation, w.small, "command of the air takes no city")
        XCTAssertTrue(c.targetWars[0].contests.isEmpty, "no contest without anyone on the ground")
        // the infantry marches in: ten to one and more, the port is taken once, then a truce cedes it
        for f in c.forces.values where f.nation == w.big && f.layer == .ground { _ = c.send(f.id, to: w.port.regionKey, attack: true) }
        var n = 0
        while c.targetWars[0].ended == nil && n < 24 * 30 { c.advance(to: c.time + day / 24); n += 1 }
        XCTAssertEqual(c.targetWars[0].stage, .truce)
        XCTAssertEqual(c.targetWars[0].contests.count, 1, "settled once")
        XCTAssertGreaterThanOrEqual(c.targetWars[0].contests[0].ratio, 10)
        XCTAssertEqual(w.port.nation, w.big)
        XCTAssertEqual(c.legalOwner(w.port.regionKey), w.big, "the truce cedes it")
        XCTAssertEqual(c.relation(w.big, w.small)?.state, 2)
        XCTAssertEqual(c.envoyBlocked(w.big, w.small), "truce", "no new war while the truce holds")
    }

    /// A contest at a given ratio (attacker and defender both infantry on open ground, fully supplied).
    func contest(ratio tenths: Int, seed: Int, steep: Bool) -> CivContest {
        let w = world(seed: seed)
        let c = w.c
        if steep { c.cfg.war.winNodes = [0.2, 0.4, 0.5, 0.5, 0.5, 1.0] }      // so that 9.9 : 1 loses often enough to see
        w.port.people = CivPeople()                                            // no town guard: only the troops count
        force(c, w.small, "infantry", count: 10, at: w.port.regionKey)
        let n = tenths                                                         // 100 points each: n / 10 to one
        let f = force(c, w.big, "infantry", count: n, at: w.port.regionKey)
        _ = f
        c.declare(w.big, on: w.small)
        let id = c.startTargetWar(w.big, on: w.small, target: w.port.id, kind: "port", envoy: nil)!
        let i = c.targetWars.firstIndex { $0.id == id }!
        return c.contest(i)!
    }

    func testTenToOneAlwaysWinsAndJustUnderMayWithdraw() {
        var lostUnder = 0
        for seed in 1...40 {
            let sure = contest(ratio: 100, seed: seed, steep: true)
            XCTAssertEqual(sure.ratio, 10, accuracy: 1e-9)
            XCTAssertTrue(sure.won, "ten to one: certain (seed \(seed))")
            let under = contest(ratio: 99, seed: seed, steep: true)
            XCTAssertEqual(under.ratio, 9.9, accuracy: 1e-9)
            if !under.won { lostUnder += 1 }
        }
        XCTAssertGreaterThan(lostUnder, 0, "9.9 : 1 can still end in withdrawal")
    }

    func testTheReportSaysTheResultFirstAndCanBeTracedBackToTheRatio() {
        let w = world()
        let c = w.c
        w.port.people = CivPeople()
        force(c, w.small, "infantry", count: 10, at: w.port.regionKey)
        force(c, w.big, "infantry", count: 100, at: w.port.regionKey)
        c.declare(w.big, on: w.small)
        let id = c.startTargetWar(w.big, on: w.small, target: w.port.id, kind: "port", envoy: nil)!
        let i = c.targetWars.firstIndex { $0.id == id }!
        let before = c.warLines(c.targetWars[i], zh: true)
        XCTAssertTrue(before.head.contains("集结"), before.head)
        XCTAssertTrue(before.details[0].contains("空域") && before.details[0].contains("运输") && before.details[0].contains("地面"), "air, transport and ground side by side")
        _ = c.contest(i)
        let after = c.warLines(c.targetWars[i], zh: true)
        XCTAssertTrue(after.head.contains("失守") && after.head.contains("10.0∶1"), after.head)
        XCTAssertTrue(after.details.contains { $0.contains("攻方 1000.0，守方 100.0") || $0.contains("攻方 10000.0，守方 1000.0") }, "\(after.details)")
        XCTAssertTrue(after.details.contains { $0.contains("十倍兵力，必胜") })
        // the nation card
        let facts = c.nationFacts(w.small, zh: true)
        XCTAssertTrue(facts[0].contains("城市 2 · 港口 2"), facts[0])
    }

    func testPeaceWorldsWithoutEnvoysAreUnchanged() {
        // a world made before envoys: the old rules decide war, and nothing here runs
        let w = world()
        w.c.envoys = false
        force(w.c, w.big, "infantry", count: 8, at: w.capital.regionKey)
        w.c.advance(to: w.c.time + day * 20)
        XCTAssertTrue(w.c.envoysOut.isEmpty)
        XCTAssertTrue(w.c.targetWars.isEmpty)
    }
}
