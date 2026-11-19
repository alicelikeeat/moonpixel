import XCTest
@testable import MoonPixelCore

/// Humanoid frames and shifters (task book phase 4).
final class MechTests: XCTestCase {
    let day = MP.daySeconds

    func put(_ c: Civ, _ x: Int, _ y: Int = 0, _ tweak: (inout CivRegion) -> Void = { _ in }) {
        var r = CivRegion(); r.rx = x; r.ry = y; r.land = 1; r.fertility = 0.6
        tweak(&r); c.regions[r.key] = r
    }

    func unit(_ c: Civ, _ kind: String, nation: Int = 1, at k: Int64) -> (CivForce, Int) {
        let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = nation; f.region = k
        var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = kind; u.nation = nation; u.force = f.id; u.hp = u.def.hp
        u.fuel = 1e6; u.energy = 1e6; u.ammo = 100
        for p in u.def.parts { u.parts[p] = 1 }
        c.units[u.id] = u; f.units = [u.id]; f.crew = CivPeople(adults: u.def.crew)
        c.forces[f.id] = f
        return (f, u.id)
    }

    func testTanksAndFramesReachDifferentLand() {
        let c = Civ(seed: 1)
        // west: plain; a narrow pass to the north-east; a shallow strait to the east
        put(c, 0); put(c, 1)
        put(c, 2) { $0.land = 0.15; $0.water = 0.85; $0.deep = 0.05 }       // a shallow strait
        put(c, 3)
        put(c, 1, 1) { $0.mountain = 0.5 }; put(c, 1, 2)                       // a narrow pass, then a valley
        let a = MP.chunkKey(0, 0)
        XCTAssertNil(c.route(from: a, to: MP.chunkKey(3, 0), size: .vehicle), "a tank cannot cross the strait")
        XCTAssertNotNil(c.route(from: a, to: MP.chunkKey(3, 0), size: .large), "a frame wades across")
        XCTAssertNotNil(c.route(from: a, to: MP.chunkKey(1, 2), size: .vehicle), "a tank takes the narrow pass")
        XCTAssertNil(c.route(from: a, to: MP.chunkKey(1, 2), size: .large), "a frame does not fit through it")
        put(c, 2) { $0.land = 0.15; $0.water = 0.85; $0.deep = 0.6 }
        XCTAssertNil(c.route(from: a, to: MP.chunkKey(3, 0), size: .large), "deep water stops a frame too")
    }

    func testAShifterIsOneMachineInTwoForms() throws {
        let c = Civ(seed: 2)
        for x in 0...8 { put(c, x) }
        put(c, 2, 1) { $0.mountain = 0.5 }
        let (f, id) = unit(c, "shifter", at: MP.chunkKey(0, 0))
        // as a vehicle it runs faster than as a humanoid
        XCTAssertNil(c.shift(id, to: "vehicle"))
        XCTAssertTrue(c.shifting(c.units[id]!))
        XCTAssertEqual(c.shift(id, to: "robot"), "shifting", "one change at a time")
        // mid-change it does not move
        XCTAssertTrue(c.send(f.id, to: MP.chunkKey(8, 0)))
        c.advance(to: c.time + day / 48)
        XCTAssertEqual(f.region, MP.chunkKey(0, 0), "changing form: it stays put")
        c.advance(to: c.time + day)
        XCTAssertFalse(c.shifting(c.units[id]!))
        XCTAssertEqual(c.formSize(c.units[id]!), .vehicle)
        XCTAssertEqual(c.formSpeed(c.units[id]!), c.units[id]!.def.speed * c.cfg.war.vehicleSpeed, accuracy: 1e-9)
        // damage carries over from form to form
        var u = c.units[id]!; u.hp = u.def.hp * 0.6; c.units[id] = u
        f.path = []; f.region = MP.chunkKey(4, 0)
        XCTAssertNil(c.shift(id, to: "robot"))
        c.advance(to: c.time + day / 12)
        XCTAssertEqual(c.units[id]!.hp, c.units[id]!.def.hp * 0.6, accuracy: 1e-9, "the same hull, the same damage")
        XCTAssertEqual(c.formSize(c.units[id]!), .large)
        // no room to stand up in a narrow pass: it says so and stays a vehicle
        XCTAssertNil(c.shift(id, to: "vehicle")); c.advance(to: c.time + day / 12)
        f.region = MP.chunkKey(2, 1)
        XCTAssertEqual(c.shift(id, to: "robot"), "no_room")
        XCTAssertEqual(Civ.shiftReason("no_room", zh: true), "空间不足：山口太窄，无法展开人形")
        XCTAssertEqual(c.units[id]!.form, "vehicle")
        // saved and opened again: still one machine, same id, form and damage
        let back = try JSONDecoder().decode(Civ.self, from: try JSONEncoder().encode(c))
        XCTAssertEqual(back.units.values.filter { $0.kind == "shifter" }.count, 1)
        XCTAssertEqual(back.units[id]?.form, "vehicle")
        XCTAssertEqual(back.units[id]!.hp, c.units[id]!.hp, accuracy: 1e-9)
    }

    func testAShifterMidChangeTakesNoPlace() {
        let c = Civ(seed: 3); c.envoys = true
        for x in 0...3 { put(c, x) }
        let a = c.newPolity(origin: "first", near: nil), b = c.newPolity(origin: "first", near: nil)
        let home = c.newCity(at: MP.chunkKey(0, 0), nation: a, people: CivPeople(adults: 50), firstCount: true)
        let place = c.newCity(at: MP.chunkKey(3, 0), nation: b, people: CivPeople(), firstCount: true)
        _ = c.newCity(at: MP.chunkKey(2, 0), nation: b, people: CivPeople(adults: 10), firstCount: true)
        c.polities[a]!.capital = home.id; c.polities[b]!.capital = place.id
        c.refreshTerritory()
        let (_, id) = unit(c, "shifter", nation: a, at: place.regionKey)
        c.declare(a, on: b)
        let wid = c.startTargetWar(a, on: b, target: place.id, kind: "city", envoy: nil)!
        let w = c.targetWars.first { $0.id == wid }!
        XCTAssertTrue(c.attack(on: w).ground, "standing there, it can take the place")
        XCTAssertNil(c.shift(id, to: "vehicle"))
        XCTAssertFalse(c.attack(on: w).ground, "mid-change it takes nothing")
    }
}
