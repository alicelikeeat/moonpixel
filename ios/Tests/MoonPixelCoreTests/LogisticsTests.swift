import XCTest
@testable import MoonPixelCore

/// Fleets, ports and carriers (task book phase 3).
final class LogisticsTests: XCTestCase {
    let day = MP.daySeconds

    func put(_ c: Civ, _ x: Int, _ y: Int, _ tweak: (inout CivRegion) -> Void = { _ in }) {
        var r = CivRegion(); r.rx = x; r.ry = y; r.land = 1; r.fertility = 0.7
        tweak(&r); c.regions[r.key] = r
    }

    /// Two islands with sea between: the attacker west, the defender's port east.
    func islands() -> (Civ, Int, Int, CivCity, CivCity) {
        let c = Civ(seed: 3); c.envoys = true
        for x in 0...10 { for y in -1...1 { put(c, x, y) { $0.land = 0; $0.water = 1; $0.deep = 0.7; $0.fertility = 0 } } }
        put(c, 0, 0); put(c, 1, 0); put(c, 9, 0); put(c, 10, 0)
        let a = c.newPolity(origin: "first", near: nil), b = c.newPolity(origin: "first", near: nil)
        let home = c.newCity(at: MP.chunkKey(0, 0), nation: a, people: CivPeople(adults: 300), firstCount: true)
        let port = c.newCity(at: MP.chunkKey(9, 0), nation: b, people: CivPeople(adults: 40), firstCount: true)
        _ = c.newCity(at: MP.chunkKey(10, 0), nation: b, people: CivPeople(adults: 20), firstCount: true)
        c.polities[a]!.capital = home.id; c.polities[b]!.capital = port.id
        c.refreshTerritory()
        return (c, a, b, home, port)
    }

    func troops(_ c: Civ, _ n: Int, count: Int, at k: Int64) {
        let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = n; f.region = k
        for _ in 0..<count {
            var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = "infantry"; u.nation = n; u.force = f.id; u.hp = u.def.hp
            c.units[u.id] = u; f.units.append(u.id)
        }
        f.crew = CivPeople(adults: 10 * count); c.totals.newly += 10 * count
        c.forces[f.id] = f
    }

    func testMoreShipsLandNoMoreWhenThePortIsTheBottleneck() {
        let (c, a, b, home, port) = islands()
        c.polities[a]!.techs += ["deep_yard"]
        home.facilities["shipyard"] = 1
        troops(c, a, count: 200, at: port.regionKey)                    // 20,000 points waiting off the port
        c.declare(a, on: b)
        let id = c.startTargetWar(a, on: b, target: port.id, kind: "port", envoy: nil)!
        let w = c.targetWars.first { $0.id == id }!
        let r1 = c.landingRound(a, at: port)
        XCTAssertEqual(r1.lift, 10_000, "one yard with ocean shipping: 4,000 x 2.5")
        XCTAssertEqual(r1.intake, 1_500, "an enemy quay stormed from the boats: half a port")
        let landed1 = c.attack(on: w)
        // more ships, the same port: the same number lands
        let yard2 = c.newCity(at: MP.chunkKey(1, 0), nation: a, people: CivPeople(adults: 50), firstCount: true)
        yard2.facilities["shipyard"] = 1
        XCTAssertEqual(c.landingRound(a, at: port).lift, 20_000)
        let landed2 = c.attack(on: w)
        XCTAssertEqual(landed1.points, landed2.points, accuracy: 1e-9, "only more hold space and the same port: no more arrive")
        XCTAssertLessThanOrEqual(landed1.points, 1_500 * c.cfg.war.landing + 1e-9)
        XCTAssertTrue(landed2.lines.contains { $0.contains("still on the ships") })
        XCTAssertTrue(c.bottleneck(a, at: port, zh: true).contains("港口是瓶颈"), c.bottleneck(a, at: port, zh: true))
        // the port in friendly hands and expanded: much more lands
        port.nation = a; c.polities[a]!.techs += ["naval_eng"]
        XCTAssertEqual(c.landingRound(a, at: port).intake, 6_000, "port expansion doubles the quay")
        XCTAssertTrue(c.techPreview(a, zh: true).contains { $0.hasPrefix("✓ 港口扩建") })
    }

    func testCarrierAircraftFindTheirCarrierWhereverItWentAndNoneAreLost() {
        let c = Civ(seed: 1)
        func land(_ xs: ClosedRange<Int>, _ tweak: (inout CivRegion) -> Void = { _ in }) { for x in xs { put(c, x, 0) { r in r.forest = 0.5; r.ore = 0.6; r.coal = 0.5; r.river = true; tweak(&r) } } }
        land(0...0) { $0.water = 0.5; $0.deep = 0.4; $0.land = 0.5 }
        land(1...4) { $0.land = 0; $0.water = 1; $0.deep = 0.9 }
        land(5...5)
        let n = c.newPolity(origin: "first", near: nil)
        c.polities[n]!.techs = CivTech.all.map { $0.key }; c.polities[n]!.ai = false
        let home = c.newCity(at: MP.chunkKey(0, 0), nation: n, people: CivPeople(adults: 3000, children: 1000, elders: 500), firstCount: true)
        home.facilities = ["farm": 600, "house": 700, "well": 2]
        home.stock = ["grain": 1e6]; c.totals.add(\.found, "grain", 1e6)
        for f in ["deep_yard", "aircraft_works", "airfield", "plant", "fusion_plant", "barracks"] { home.facilities[f] = 2 }
        for (k, v) in ["steel": 5000.0, "armor": 500, "parts": 2000, "engine": 200, "electronics": 1000, "weapons": 200, "core": 40, "fuel": 5000, "ammo": 5000] { home.stock[k] = v }
        let foe = c.newPolity(origin: "first", near: nil)
        _ = c.newCity(at: MP.chunkKey(5, 0), nation: foe, people: CivPeople(adults: 50), firstCount: true)
        c.order("carrier", nation: n, city: home.id)
        for _ in 0..<4 { c.order("fighter", nation: n, city: home.id) }
        c.advance(to: c.time + 24 * day)
        guard let carrier = c.units.values.first(where: { $0.kind == "carrier" }), let fid = c.deploy(carrier.id) else { return XCTFail("no carrier") }
        for u in c.units.values.filter({ $0.kind == "fighter" }).sorted(by: { $0.id < $1.id }) { _ = c.deploy(u.id, joining: fid) }
        let fighters = Set(c.units.values.filter { $0.kind == "fighter" }.map { $0.id })
        XCTAssertEqual(fighters.count, 4)
        XCTAssertTrue(c.send(fid, to: MP.chunkKey(4, 0)))
        c.declare(n, on: foe)
        // once aircraft are up, the carrier moves away
        var moved = false
        for _ in 0..<(24 * 8) {
            c.advance(to: c.time + day / 24)
            if !moved && c.units.values.contains(where: { fighters.contains($0.id) && $0.air == .airborne }) {
                moved = true
                XCTAssertTrue(c.send(fid, to: MP.chunkKey(2, 0)), "the carrier sails on while its aircraft are up")
            }
            if moved && c.forces[fid]?.region == MP.chunkKey(2, 0) && fighters.allSatisfy({ c.units[$0]?.air == .parked }) { break }
        }
        XCTAssertTrue(moved, "aircraft took off")
        XCTAssertEqual(c.forces[fid]?.region, MP.chunkKey(2, 0))
        let left = fighters.filter { c.units[$0] != nil }
        XCTAssertEqual(left.count + c.wrecks.filter { $0.kind == "fighter" }.count, 4, "every aircraft is accounted for")
        for id in left { XCTAssertEqual(c.units[id]?.air, .parked, "back on the deck"); XCTAssertEqual(c.units[id]?.force, fid, "on its carrier, where it is now") }
        XCTAssertEqual(c.audit(), [])
    }
}
