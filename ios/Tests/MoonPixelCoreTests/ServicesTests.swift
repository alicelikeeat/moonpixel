import XCTest
@testable import MoonPixelCore

/// The services shared by every mode: goods change hands all or nothing, wherever they are kept;
/// a blow is worked out the same way in command mode and in the regional wars.
final class ServicesTests: XCTestCase {
    func testGoodsAreTakenAllOrNothingInEveryKindOfStore() {
        let s = makeSociety(5)
        let town = s.settlements.values.sorted { $0.id < $1.id }.first!
        town.food = 10; town.wood = 3
        XCTAssertEqual(Goods.take([("food", 5), ("wood", 4)], from: town.holding), "wood", "the town lacks wood: nothing is taken")
        XCTAssertEqual(town.food, 10)
        XCTAssertNil(Goods.take([("food", 5), ("wood", 3)], from: town.holding)); XCTAssertEqual(town.food, 5); XCTAssertEqual(town.wood, 0)
        s.realm.player.food = 2
        XCTAssertEqual(Goods.move([("food", 3)], from: s.pack, to: town.holding), "food")
        XCTAssertNil(Goods.move([("food", 2)], from: s.pack, to: town.holding)); XCTAssertEqual(town.food, 7); XCTAssertEqual(s.realm.player.food, 0)
        // a city of the regional layer: what is held aside for a project is not free
        let c = Civ(seed: 1); var r = CivRegion(); r.land = 1; c.regions[r.key] = r
        let n = c.newPolity(origin: "first", near: nil)
        let city = c.newCity(at: r.key, nation: n, people: CivPeople(adults: 10), firstCount: true)
        city.stock = ["steel": 10]; city.reserved = ["steel": 8]
        XCTAssertEqual(Goods.take([("steel", 3)], from: city.holding), "steel")
        XCTAssertNil(Goods.take([("steel", 2)], from: city.holding)); XCTAssertEqual(city.stock["steel"], 8)
        // a side in command mode
        let k = Skirmish(seed: 3, worldSeed: 7, player: ("A", "#fff"), enemy: ("B", "#000"), credits: 250)
        XCTAssertFalse(k.queue(0, SkKind.named("reactor")) && k.queue(0, SkKind.named("reactor")) && k.sides[0].credits < 0, "never below zero")
        XCTAssertGreaterThanOrEqual(k.sides[0].credits, 0)
    }

    func testABlowIsWorkedOutTheSameWayInEveryMode() {
        XCTAssertEqual(Combat.damage(40, vs: [1, 0.5, 0.25], armor: 1), 20)
        XCTAssertEqual(Combat.damage(40, vs: [1, 0.5, 0.25, 0.1], armor: 3, aim: 0.5), 2)
        XCTAssertEqual(Combat.damage(40, vs: [1, 0.5], armor: 9), 20, "an unknown class reads as the toughest listed")
        XCTAssertEqual(Combat.wear(part: 1, hit: 100, hp: 600), 0.5, accuracy: 1e-9)
        // command mode's rifles against a vehicle hit exactly as the service says
        let rifle = SkKind.all[SkKind.named("rifle")]
        XCTAssertEqual(Combat.damage(rifle.damage, vs: rifle.vs, armor: SkArmor.vehicle.rawValue), rifle.damage * rifle.vs[1])
    }

    /// The sky carrier: charged from a friendly city's power, it stays aloft; away from power it runs
    /// down and must come to the ground (it cannot hang in the sky on nothing).
    func testASkyCarrierIsSuppliedByItsCityAndComesDownWithoutPower() {
        let c = Civ(seed: 1)
        for x in 0...6 { var r = CivRegion(); r.rx = x; r.land = 1; r.fertility = 0.6; c.regions[r.key] = r }
        let n = c.newPolity(origin: "first", near: nil)
        c.polities[n]!.techs = CivTech.all.map { $0.key }; c.polities[n]!.ai = false; c.polities[n]!.builds = false
        let t = c.newCity(at: MP.chunkKey(0, 0), nation: n, people: CivPeople(adults: 3000, children: 500, elders: 300), firstCount: true)
        t.facilities = ["farm": 900, "house": 700, "well": 100, "sky_yard": 1, "fusion_plant": 4, "airfield": 1]
        t.stock = ["grain": 1e6, "steel": 500, "armor": 80, "parts": 200, "engine": 20, "electronics": 200, "weapons": 20, "core": 10]
        c.totals.add(\.found, "grain", 1e6)
        guard c.order("sky_carrier", nation: n, city: t.id) != nil else { return XCTFail("order") }
        for _ in 0..<30 where c.units.values.first(where: { $0.kind == "sky_carrier" }) == nil { c.advance(to: c.time + MP.daySeconds) }
        guard let u = c.units.values.first(where: { $0.kind == "sky_carrier" }), let fid = c.deploy(u.id) else { return XCTFail("no sky carrier") }
        XCTAssertEqual(c.forces[fid]!.layer, .highAir)
        // at home its reactors are kept charged by the city's fusion plants
        for _ in 0..<3 { c.advance(to: c.time + MP.daySeconds) }
        XCTAssertGreaterThan(c.units[u.id]!.energy, 0, "supplied at home")
        XCTAssertEqual(c.forces[fid]?.layer, .highAir)
        // sent far beyond any supply, it runs down and comes to the ground
        XCTAssertTrue(c.send(fid, to: MP.chunkKey(6, 0)))
        var landed = false
        for _ in 0..<(24 * 8) { c.advance(to: c.time + MP.daySeconds / 24); if c.forces[fid]?.layer == .ground { landed = true; break } }
        XCTAssertTrue(landed, "out of power, it came down")
        XCTAssertTrue(c.fights.contains { $0.kind == "descend" })
        XCTAssertEqual(c.audit(), [])
    }
}
