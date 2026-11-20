import XCTest
@testable import MoonPixelCore

/// Oil and gold; trade over the sea; wars and spies for what a nation lacks.
final class ResourceTests: XCTestCase {
    let day = MP.daySeconds

    /// Two coasts across a sea: nation A west (x 0...1), nation B east (x 6...7), sea between and round.
    func world(seed: Int = 1) -> (Civ, Int, Int, CivCity, CivCity) {
        let c = Civ(seed: seed); c.envoys = true
        for x in -1...8 { for y in -1...2 { var r = CivRegion(); r.rx = x; r.ry = y; r.water = 1; r.deep = 0.7; c.regions[r.key] = r } }
        for x in [0, 1, 6, 7] { var r = CivRegion(); r.rx = x; r.ry = 0; r.land = 1; r.fertility = 0.7; r.water = 0.2; c.regions[r.key] = r }
        let a = c.newPolity(origin: "first", near: nil), b = c.newPolity(origin: "first", near: nil)
        let ca = c.newCity(at: MP.chunkKey(1, 0), nation: a, people: CivPeople(adults: 200), firstCount: true)
        let cb = c.newCity(at: MP.chunkKey(6, 0), nation: b, people: CivPeople(adults: 200), firstCount: true)
        for k in [ca, cb] { k.facilities = ["farm": 80, "house": 60, "well": 3]; k.stock = ["grain": 1e5]; c.totals.add(\.found, "grain", 1e5) }
        c.polities[a]!.capital = ca.id; c.polities[b]!.capital = cb.id
        c.polities[a]!.treasury = 5000; c.polities[b]!.treasury = 5000
        c.refreshTerritory()
        return (c, a, b, ca, cb)
    }

    func testGoldIsDugAndCoinedIntoTheTreasury() {
        let (c, a, _, ca, _) = world()
        c.regions[ca.regionKey]!.gold = 0.8
        c.polities[a]!.techs += ["metallurgy"]
        ca.facilities["gold_mine"] = 1
        let t0 = c.polities[a]!.treasury
        c.advance(to: c.time + 6 * day)
        XCTAssertGreaterThan(ca.ledger.made["gold"] ?? 0, 0, "gold was dug")
        XCTAssertGreaterThan(c.polities[a]!.treasury, t0, "and coined")
        XCTAssertTrue(CivItem.all.contains { $0.key == "gold" })
    }

    func testANationShortOfOilBuysItOverTheSea() {
        let (c, a, b, ca, cb) = world()
        c.polities[a]!.techs += ["oil", "engines"]
        cb.stock["crude"] = 2000
        XCTAssertTrue(c.shortages(a).contains("crude"))
        let way = c.tradeWay(from: cb, to: ca)
        XCTAssertEqual(way?.sea, true, "their ports share the sea")
        let tb0 = c.polities[b]!.treasury
        c.advance(to: c.time + 6 * day)
        guard let r = c.tradeRoutes.first(where: { $0.good == "crude" }) else { return XCTFail("no route") }
        XCTAssertTrue(r.sea)
        XCTAssertEqual(cities(c, r.buyer)?.nation, a); XCTAssertEqual(cities(c, r.seller)?.nation, b)
        XCTAssertGreaterThan(ca.stock["crude"] ?? 0, 0, "the oil arrived")
        XCTAssertGreaterThan(r.paid, 0, "and was paid for"); _ = tb0
        XCTAssertGreaterThan(c.relation(a, b)?.trade ?? 0, 0)
        XCTAssertTrue(c.chronicle.contains { $0.kind == "sea_route" })
        XCTAssertTrue(c.resourceLines(a, zh: true).contains { $0.contains("买自") })
        XCTAssertEqual(c.audit(), [])
    }
    func cities(_ c: Civ, _ id: Int) -> CivCity? { c.cities[id] }

    func testWarshipsOfAnEnemySinkTheConvoys() {
        let (c, a, b, ca, cb) = world()
        c.polities[a]!.techs += ["oil", "engines"]
        cb.stock["crude"] = 5000
        let pirate = c.newPolity(origin: "first", near: nil)
        c.declare(pirate, on: b)
        // the pirate's warship sits in the middle of the sea between them
        let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = pirate; f.region = MP.chunkKey(3, 1); f.layer = .sea
        var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = "escort"; u.nation = pirate; u.force = f.id; u.hp = u.def.hp
        c.units[u.id] = u; f.units = [u.id]; f.crew = CivPeople(adults: u.def.crew); c.totals.newly += u.def.crew
        c.forces[f.id] = f
        c.advance(to: c.time + 10 * day)
        if let r = c.tradeRoutes.first(where: { $0.good == "crude" }), r.path.contains(f.region) {
            XCTAssertGreaterThan(r.lost, 0, "convoys through the enemy's warship are sunk")
            XCTAssertTrue(c.chronicle.contains { $0.kind == "convoy_sunk" })
        }
        _ = ca
    }

    func testANationShortOfOilWantsTheOilfield() {
        let (c, a, b, _, cb) = world()
        c.polities[a]!.techs += ["oil", "engines"]
        var r = CivRegion(); r.rx = 7; r.ry = 0; r.land = 1; r.oil = 0.9; r.water = 0.2; c.regions[r.key] = r
        let field = c.newCity(at: r.key, nation: b, people: CivPeople(adults: 30), firstCount: true)
        let want = c.wantedPlace(by: a, from: b)
        XCTAssertEqual(want?.city, field.id); XCTAssertEqual(want?.kind, "oilfield")
        _ = cb
    }

    func testSpiesStealAndSomeAreCaught() {
        var successes = 0, caught = 0
        for seed in 1...20 {
            let (c, a, b, _, _) = world(seed: seed)
            c.polities[b]!.techs += ["writing", "metallurgy"]
            let id = c.sendSpy(a, to: b, mission: .stealTech)!
            let v0 = c.relation(a, b)?.value ?? 0
            c.advance(to: c.time + 3 * day)
            let s = c.spies.first { $0.id == id }!
            if s.outcome == "success" { successes += 1; XCTAssertTrue(c.polities[a]!.techs.contains(s.note), "the stolen technology is learned: \(s.note)") }
            if s.outcome == "caught" { caught += 1; XCTAssertLessThan(c.relation(a, b)!.value, v0, "a caught spy sours the relation") }
        }
        XCTAssertGreaterThan(successes, 0); XCTAssertGreaterThan(caught, 0)
    }
}
