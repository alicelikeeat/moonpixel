import XCTest
@testable import MoonPixelCore

/// Sky carriers putting frames down, and the giantess (task book phase 5).
final class AirborneTests: XCTestCase {
    let day = MP.daySeconds

    func put(_ c: Civ, _ x: Int, _ y: Int = 0, _ tweak: (inout CivRegion) -> Void = { _ in }) {
        var r = CivRegion(); r.rx = x; r.ry = y; r.land = 1; r.fertility = 0.6
        tweak(&r); c.regions[r.key] = r
    }
    @discardableResult func unit(_ c: Civ, _ kind: String, nation: Int, at k: Int64, into: CivForce? = nil) -> (CivForce, Int) {
        let f = into ?? { let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = nation; f.region = k; c.forces[f.id] = f; return f }()
        var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = kind; u.nation = nation; u.force = f.id; u.hp = u.def.hp
        u.fuel = 1e6; u.energy = 1e6; u.ammo = 100
        for p in u.def.parts { u.parts[p] = 1 }
        c.units[u.id] = u; f.units.append(u.id)
        f.crew.add(CivPeople(adults: u.def.crew)); c.totals.newly += u.def.crew
        return (f, u.id)
    }

    func testASkyCarrierDropsOneFrameThatFightsOnlyOnceDown() throws {
        let c = Civ(seed: 1); c.envoys = true
        for x in 0...4 { put(c, x) }
        let a = c.newPolity(origin: "first", near: nil), b = c.newPolity(origin: "first", near: nil)
        let home = c.newCity(at: MP.chunkKey(0, 0), nation: a, people: CivPeople(adults: 30), firstCount: true)
        let target = c.newCity(at: MP.chunkKey(4, 0), nation: b, people: CivPeople(), firstCount: true)
        _ = c.newCity(at: MP.chunkKey(3, 0), nation: b, people: CivPeople(adults: 10), firstCount: true)
        c.polities[a]!.capital = home.id; c.polities[b]!.capital = target.id
        c.refreshTerritory()
        let (sky, _) = unit(c, "sky_carrier", nation: a, at: home.regionKey)
        sky.layer = .highAir
        let (_, frame) = unit(c, "frame", nation: a, at: home.regionKey)
        XCTAssertNil(c.board(frame, carrier: sky.id))
        XCTAssertEqual(c.units[frame]?.force, sky.id)
        XCTAssertEqual(c.audit(), [])
        // over the target: drop
        sky.region = target.regionKey
        c.declare(a, on: b)
        let wid = c.startTargetWar(a, on: b, target: target.id, kind: "city", envoy: nil)!
        let w = { c.targetWars.first { $0.id == wid }! }
        XCTAssertFalse(c.attack(on: w()).ground, "in the hangar, the frame takes nothing")
        XCTAssertNil(c.drop(frame))
        XCTAssertEqual(c.drop(frame), "not_aboard", "it is dropped once")
        XCTAssertFalse(c.attack(on: w()).ground, "falling, it takes nothing yet")
        // saved while it falls: when opened, still one frame, landing once
        let saved = try JSONDecoder().decode(Civ.self, from: try JSONEncoder().encode(c))
        for x in [c, saved] {
            x.advance(to: x.time + day / 6)
            XCTAssertEqual(x.units.values.filter { $0.kind == "frame" }.count, 1, "one frame, never two")
            let held = x.forces.values.filter { $0.units.contains(frame) }
            XCTAssertEqual(held.count, 1)
            XCTAssertEqual(held.first?.region, target.regionKey)
            XCTAssertEqual(held.first?.layer, .ground)
            XCTAssertTrue(x.drops.isEmpty)
            XCTAssertEqual(x.audit(), [])
        }
        XCTAssertTrue(c.attack(on: w()).ground, "down on the ground, it can take the place")
    }

    func testTheGiantessGuardsRescuesAndClearsAndEachIsCreditedOnce() {
        let c = Civ(seed: 2)
        put(c, 0); put(c, 1) { $0.land = 0.15; $0.water = 0.85; $0.deep = 0.05 }; put(c, 2)
        let n = c.newPolity(origin: "first", near: nil)
        let east = c.newCity(at: MP.chunkKey(2, 0), nation: n, people: CivPeople(adults: 60, children: 20), firstCount: true)
        let west = c.newCity(at: MP.chunkKey(0, 0), nation: n, people: CivPeople(adults: 30), firstCount: true)
        let g = c.raiseGiant(nation: n, at: west.regionKey, en: "Aurelia", zh: "奥蕾莉亚")
        XCTAssertNil(c.giantGo(g, to: east.regionKey), "she wades the shallow strait")
        // guard: her strength counts in the city's defence
        let before = c.defence(of: east).points
        XCTAssertNil(c.giantGuard(g))
        XCTAssertEqual(c.defence(of: east).points - before, WarBalance.giantPoints, accuracy: 1e-9)
        c.advance(to: c.time + day / 4)
        let guardHours = c.giants[0].guardHours
        XCTAssertGreaterThan(guardHours, 0)
        // a rescue: people carried to the other city; credited as a rescue, and it ends the watch
        let people = c.people
        let moved = c.giantRescue(g, people: 25)
        XCTAssertEqual(moved, 25)
        XCTAssertEqual(c.people, people, "nobody made or lost")
        XCTAssertEqual(west.people.total, 30 + 25)
        XCTAssertEqual(c.giants[0].rescued, 25)
        XCTAssertEqual(c.giants[0].task, "", "a rescue is not a watch")
        c.advance(to: c.time + day / 4)
        XCTAssertEqual(c.giants[0].guardHours, guardHours, "no watch hours while she is not on watch")
        XCTAssertEqual(c.defence(of: east).points, Double(east.pop) / 20, accuracy: 1e-6, "her strength is gone from the defence; the guard is what is left of the town"); _ = before
        XCTAssertTrue(c.giants[0].history.contains { $0.contains("carried 25 people") })
        XCTAssertEqual(c.audit(), [])
    }

    func testTheGiantessClearsAWayThatIsThenOpen() {
        let s = makeSociety(7)
        let o = TilePos(6000, 6000)
        let grass = s.content.tid("grass")
        for dx in 0..<6 { s.world.setTile(0, o.x + dx, o.y, grass); for l in 1...3 { s.world.setTile(l, o.x + dx, o.y, 0) } }
        let way = (0..<6).map { TilePos(o.x + $0, o.y) }
        s.world.setTile(2, way[1].x, way[1].y, s.content.tid("rock"))
        s.world.setTile(2, way[3].x, way[3].y, s.content.tid("dead_tree"))
        s.world.setTile(3, way[4].x, way[4].y, s.content.tid("rubble"))
        XCTAssertTrue(s.world.blocked(way[1].x, way[1].y))
        let g = s.civ.raiseGiant(nation: 1, at: 0, en: "Aurelia", zh: "奥蕾莉亚")
        let n = s.giantClear(g, tiles: way)
        XCTAssertEqual(n, 3)
        for t in way { XCTAssertFalse(s.world.blocked(t.x, t.y), "the way is open at \(t)") }
        XCTAssertEqual(s.giantClear(g, tiles: way), 0, "nothing left to clear: nothing credited twice")
        XCTAssertEqual(s.civ.giants[0].cleared, 3)
    }
}
