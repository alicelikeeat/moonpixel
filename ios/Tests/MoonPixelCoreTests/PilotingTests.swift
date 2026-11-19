import XCTest
@testable import MoonPixelCore

/// One unit, one id, whoever is at the controls.
final class PilotingTests: XCTestCase {
    let day = MP.daySeconds

    func put(_ c: Civ, _ x: Int, _ y: Int = 0, _ tweak: (inout CivRegion) -> Void = { _ in }) {
        var r = CivRegion(); r.rx = x; r.ry = y; r.land = 1; r.fertility = 0.6
        tweak(&r); c.regions[r.key] = r
    }
    @discardableResult func unit(_ c: Civ, _ kind: String, nation: Int, at k: Int64, into: CivForce? = nil, layer: CivLayer = .ground) -> (CivForce, Int) {
        let f = into ?? { let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = nation; f.region = k; f.layer = layer; c.forces[f.id] = f; return f }()
        var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = kind; u.nation = nation; u.force = f.id; u.hp = u.def.hp
        u.fuel = u.def.fuelCap > 0 ? u.def.fuelCap : 1e6; u.energy = 1e6; u.ammo = 100
        for p in u.def.parts { u.parts[p] = 1 }
        c.units[u.id] = u; f.units.append(u.id)
        f.crew.add(CivPeople(adults: u.def.crew)); c.totals.newly += u.def.crew
        f.food["ration", default: 0] += 1e4; c.totals.add(\.found, "ration", 1e4)
        return (f, u.id)
    }

    func testTheComputerLeavesAPilotedUnitAloneAndCarriesOnWhenLetGo() {
        let c = Civ(seed: 1)
        for x in 0...8 { put(c, x) }
        let a = c.newPolity(origin: "first", near: nil), b = c.newPolity(origin: "first", near: nil)
        let home = c.newCity(at: MP.chunkKey(0, 0), nation: a, people: CivPeople(adults: 300), firstCount: true)
        home.facilities = ["farm": 80, "house": 80, "well": 2]; home.stock = ["grain": 1e5]; c.totals.add(\.found, "grain", 1e5)
        let foe = c.newCity(at: MP.chunkKey(8, 0), nation: b, people: CivPeople(adults: 40), firstCount: true)
        c.polities[a]!.capital = home.id; c.polities[b]!.capital = foe.id
        c.polities[a]!.treasury = 1000; c.polities[a]!.fatigue = -10
        let (f, id) = unit(c, "frame", nation: a, at: home.regionKey)
        c.declare(a, on: b)
        XCTAssertNil(c.takeControl(id, nation: a))
        XCTAssertEqual(c.takeControl(id, nation: b), "not_ours")
        c.advance(to: c.time + 2 * day)
        XCTAssertTrue(f.path.isEmpty, "with the player at the controls, the computer gives no orders")
        XCTAssertEqual(f.region, home.regionKey)
        // the player drives it out; halfway, lets go: the computer carries on from there
        XCTAssertNil(c.pilotGo(to: MP.chunkKey(4, 0), attack: false))
        c.advance(to: c.time + day / 2)
        let midway = f.region, left = f.path.count
        XCTAssertNotEqual(midway, home.regionKey)
        c.releaseControl()
        XCTAssertNil(c.pilotedUnit)
        XCTAssertEqual(f.path.count, left, "its way is kept, not restarted")
        c.advance(to: c.time + 6 * day)
        XCTAssertNotNil(c.units[id], "the same unit, the same id")
        XCTAssertTrue(f.region == foe.regionKey || !f.path.isEmpty || f.region == MP.chunkKey(4, 0), "and the computer takes it on: \(MP.keyCX(f.region))")
        XCTAssertEqual(c.audit(), [])
    }

    func testFromTheCarrierToAnAircraftAndBack() {
        let c = Civ(seed: 2)
        put(c, 0) { $0.water = 0.5; $0.deep = 0.4; $0.land = 0.5 }
        for x in 1...5 { put(c, x) { $0.land = 0; $0.water = 1; $0.deep = 0.9 } }
        put(c, 6)
        let a = c.newPolity(origin: "first", near: nil)
        let (f, carrier) = unit(c, "carrier", nation: a, at: MP.chunkKey(2, 0), layer: .sea)
        var jets: [Int] = []
        for _ in 0..<2 { let (_, j) = unit(c, "fighter", nation: a, at: f.region, into: f); var u = c.units[j]!; u.air = .parked; c.units[j] = u; jets.append(j) }
        XCTAssertNil(c.takeControl(carrier, nation: a))
        XCTAssertTrue(c.unitLine(carrier, zh: true).contains("机库 2 架"), c.unitLine(carrier, zh: true))
        guard let jet = c.switchToAircraft() else { return XCTFail("no aircraft on deck") }
        XCTAssertTrue(jets.contains(jet))
        XCTAssertEqual(c.pilotedUnit, jet, "the player is in the aircraft now")
        XCTAssertNil(c.pilotGo(to: MP.chunkKey(4, 0)))
        XCTAssertEqual(c.units[jet]?.air, .airborne)
        // the carrier sails on; the aircraft flies its mission and comes back to it where it is
        XCTAssertTrue(c.send(f.id, to: MP.chunkKey(3, 0)))
        for _ in 0..<(24 * 3) where c.units[jet]?.air != .parked { c.advance(to: c.time + day / 24) }
        XCTAssertEqual(c.units[jet]?.air, .parked, "back on the deck")
        XCTAssertEqual(c.units[jet]?.force, f.id)
        XCTAssertEqual(c.switchToCarrier(), carrier)
        XCTAssertEqual(c.units.values.filter { $0.kind == "fighter" }.count, 2, "no aircraft made or lost")
        XCTAssertEqual(c.audit(), [])
    }
}
