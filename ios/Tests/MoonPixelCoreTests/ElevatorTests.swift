import XCTest
@testable import MoonPixelCore

final class ElevatorTests: XCTestCase {
    /// A six-storey house with a two-by-two shaft against its east wall, landings on every level.
    func building(_ seed: Int = 6, levels: Int = 6) -> (Society, Elevator, TilePos) {
        let s = makeSociety(seed)
        let town = s.settlements.values.sorted { $0.id < $1.id }[0]
        let o = s.world.findSite(from: town.center, minR: 14, maxR: 60, salt: 3, avoid: [], avoidDist: 0)
        s.raiseHouse(at: o, storeys: levels, w: 7, d: 7)
        let sx = o.x + 7 + 1, sy = o.y + 2                      // a tile out from the wall; landings between
        for lv in 1..<levels { let w = s.storeyWorld(lv); for y in (sy - 1)...(sy + 2) { w.setTile(0, o.x + 7, y, s.content.tid("wood_floor")) } }
        for yy in sy..<(sy + 2) { for xx in sx..<(sx + 2) { for l in 1...3 { s.world.setTile(l, xx, yy, 0) } } }
        let plan = s.planLift(x: sx, y: sy, levels: Array(0..<levels), landingSide: TilePos(-1, 0))
        XCTAssertTrue(plan.ok, plan.reason)
        for (k, v) in plan.cost { s.carry(k, v) }
        let id = s.buildLift(plan, x: sx, y: sy, town: town.id, tower: nil, planID: 501)!
        return (s, s.lift(id)!, o)
    }
    func run(_ s: Society, _ e: Elevator, _ seconds: Double, powered: Bool = true, dt: Double = 1.0 / 30, each: (() -> Void)? = nil) {
        var t = 0.0
        while t < seconds { s.liftStep(e, dt, powered: powered); s.world.time += dt; t += dt; each?() }
    }

    func testItIsPaidForOnceAndHasALandingOnEveryLevel() {
        let (s, e, _) = building()
        XCTAssertEqual(e.stops.map { $0.level }, [0, 1, 2, 3, 4, 5])
        for i in 1..<e.stops.count { XCTAssertGreaterThan(e.stops[i].z, e.stops[i - 1].z) }
        XCTAssertEqual(s.carried("iron"), 0, "paid from the pack")
        let again = s.planLift(x: e.x + 40, y: e.y, levels: [0, 1], landingSide: TilePos(-1, 0))
        XCTAssertNil(s.buildLift(again, x: e.x + 40, y: e.y, town: e.town, tower: nil, planID: 501), "the same plan is not built twice")
        XCTAssertEqual(s.realm.lifts.count, 1)
        // a shaft into a wall is refused
        let bad = s.planLift(x: e.x - 3, y: e.y, levels: [0, 1, 2], landingSide: TilePos(-1, 0))
        XCTAssertFalse(bad.ok)
    }

    func testDoorsOpenOnlyWhereTheCarStandsAndNeverShutOnSomeone() {
        let (s, e, _) = building()
        e.call(4, at: s.world.time)
        var openedAway = false, maxV = 0.0
        run(s, e, 30) {
            for k in e.stops.indices where e.open(at: k) && abs(e.z - e.stops[k].z) > 1e-9 { openedAway = true }
            if e.state == .moving && e.door > 0 { openedAway = true }
            maxV = max(maxV, abs(e.v))
        }
        XCTAssertFalse(openedAway, "no door opens unless the car is right there and still")
        XCTAssertEqual(e.at, 4); XCTAssertEqual(e.z, e.stops[4].z, accuracy: 1e-12, "stopped exactly at the landing")
        XCTAssertLessThanOrEqual(maxV, s.liftCfg.maxSpeed + 1e-9)
        XCTAssertTrue(e.open(at: 4))
        // someone in the doorway while it shuts: it opens again
        e.call(0, at: s.world.time)
        var n = 0
        while e.state != .closing && n < 1000 { s.liftStep(e, 1.0 / 30, powered: true); s.world.time += 1.0 / 30; n += 1 }
        s.liftStep(e, 0.2, powered: true)
        XCTAssertEqual(e.state, .closing)
        e.blocked = true
        s.liftStep(e, 0.05, powered: true)
        XCTAssertEqual(e.state, .opening, "it opens again instead of shutting on them")
        XCTAssertEqual(e.at, 4)
    }

    func testOverloadedItWillNotGo() {
        let (s, e, _) = building()
        let town = s.settlements[e.town]!
        town.food = 5000
        _ = s.sendByLift(e, key: "food", amount: 5000, from: 0, to: 3, source: .town(town.id), dest: .town(town.id))
        // a crowd boards beside the goods
        let people = town.members.prefix(8).compactMap { s.agents[$0] }
        for a in people { s.ride(e, agent: a.id, from: 0, to: 2) }
        e.state = .opening
        run(s, e, 1.5)
        e.jobs[0].carried = 1100                                   // the car is filled near to the limit
        e.playerAboard = true
        run(s, e, s.liftCfg.dwell + 3)
        XCTAssertGreaterThan(e.load, s.liftCfg.capacity)
        XCTAssertEqual(e.state, .overload, "overloaded: it waits with its doors open")
        XCTAssertEqual(e.z, e.stops[0].z)
        e.playerAboard = false; e.jobs[0].carried = 100
        run(s, e, 8)
        XCTAssertNotEqual(e.state, .overload)
    }

    func testFoodGoesUpOnceAndIsInTheCarAndNowhereElseOnTheWay() throws {
        let (s, e, _) = building()
        let town = s.settlements[e.town]!
        town.food = 300
        let roof = TilePos(e.stops[5].door.x, e.stops[5].door.y)
        _ = roof
        let other = s.foundSettlement(s.world.findSite(from: town.center, minR: 70, maxR: 200, salt: 9, avoid: s.settlements.values.map { $0.center }, avoidDist: 40))
        other.food = 0
        let j = s.sendByLift(e, key: "food", amount: 120, from: 0, to: 5, source: .town(town.id), dest: .town(other.id))
        _ = j
        var seenMoving = false
        run(s, e, 60) {
            let inCar = s.inLifts()["food"] ?? 0
            XCTAssertEqual(town.food + other.food + inCar, 300, accuracy: 1e-9, "every unit is in exactly one place")
            if e.state == .moving && inCar > 0 { seenMoving = true; XCTAssertEqual(other.food, 0) }
        }
        XCTAssertTrue(seenMoving)
        XCTAssertEqual(other.food, 120, accuracy: 1e-9); XCTAssertEqual(town.food, 180, accuracy: 1e-9)
        XCTAssertTrue(e.jobs.isEmpty, "the job is done and gone, not delivered again")
        run(s, e, 30)
        XCTAssertEqual(other.food, 120, accuracy: 1e-9)
    }

    func testSavedHalfWayUpItCarriesOnWithTheSameLoad() throws {
        let (s, e, _) = building()
        let town = s.settlements[e.town]!
        town.food = 100
        _ = s.sendByLift(e, key: "food", amount: 60, from: 0, to: 5, source: .town(town.id), dest: .town(town.id))
        let a = s.agents[town.members[0]]!
        s.ride(e, agent: a.id, from: 0, to: 5)
        while !(e.state == .moving && e.z > e.stops[2].z) { s.liftStep(e, 1.0 / 30, powered: true); s.world.time += 1.0 / 30 }
        XCTAssertTrue(e.rides[0].aboard)
        let data = try JSONEncoder().encode(s.realm.lifts)
        let back = try JSONDecoder().decode([Elevator].self, from: data)
        XCTAssertEqual(back.count, 1)
        let b = back[0]
        XCTAssertEqual(b.z, e.z); XCTAssertEqual(b.v, e.v); XCTAssertEqual(b.jobs, e.jobs); XCTAssertEqual(b.rides, e.rides); XCTAssertEqual(b.state, .moving)
        s.realm.lifts = back
        run(s, b, 30)
        XCTAssertEqual(town.food, 100, accuracy: 1e-9, "the 60 that went up came back into the same store: once")
        XCTAssertTrue(b.rides.isEmpty, "the rider got out")
        XCTAssertEqual(a.pos, b.stops[5].door.center, "at the top landing")
    }

    func testAPowerCutBrakesItAndEmergencyPowerTakesItToALanding() {
        let (s, e, _) = building()
        e.call(5, at: s.world.time)
        while !(e.state == .moving && e.z > e.stops[1].z + 0.5) { s.liftStep(e, 1.0 / 30, powered: true); s.world.time += 1.0 / 30 }
        let z0 = e.z
        run(s, e, 20, powered: false)
        XCTAssertNotNil(e.at, "on battery it went to a landing")
        XCTAssertGreaterThanOrEqual(e.z, z0 - 1e-9, "never down: it does not fall")
        XCTAssertTrue(e.docked); XCTAssertGreaterThan(e.door, 0.9, "and let people out")
        // with an empty battery it stops where it is and holds
        let (s2, e2, _) = building()
        e2.call(5, at: s2.world.time)
        while !(e2.state == .moving && e2.z > e2.stops[1].z + 0.5) { s2.liftStep(e2, 1.0 / 30, powered: true); s2.world.time += 1.0 / 30 }
        e2.battery = 0
        let held = e2.z
        run(s2, e2, 10, powered: false)
        XCTAssertEqual(e2.state, .trapped); XCTAssertEqual(e2.z, held, "held by its brakes, not dropped")
        XCTAssertEqual(e2.door, 0, "doors shut between landings")
        run(s2, e2, 30, powered: true)
        XCTAssertEqual(e2.at, 5, "power back: it goes on")
    }

    func testAFarCallIsNotLeftWaitingForever() {
        let (s, e, _) = building()
        var served5 = false
        var t = 0.0
        e.call(5, at: s.world.time)
        while t < 120 {
            // people keep calling it between the ground and the first storey
            if Int(t * 30) % 90 == 0 { e.call(0, at: s.world.time); e.call(1, at: s.world.time) }
            s.liftStep(e, 1.0 / 30, powered: true); s.world.time += 1.0 / 30; t += 1.0 / 30
            if e.at == 5 { served5 = true; break }
        }
        XCTAssertTrue(served5, "the top floor got its car within the wait limit")
        XCTAssertLessThanOrEqual(t, s.liftCfg.waitLimit + 30)
    }

    func testTheTravellerRidesUpAndWalksOutOnTheirStorey() {
        let (s, e, _) = building()
        let g = WorldGround(s)
        var b = Body(at: Vec2(e.minX + 16, e.minY + 16), z: e.z, depth: 0)
        b.platform = e.id; b.state = .riding; e.playerAboard = true
        e.call(3, at: s.world.time)
        var t = 0.0
        while t < 40 {
            s.liftStep(e, 1.0 / 60, powered: true); s.world.time += 1.0 / 60; t += 1.0 / 60
            let walk = e.open(at: 3) ? Vec2(-90, 0) : .zero
            let r = Motion.advance(&b, dt: 1.0 / 60, wish: walk, jump: false, ground: g, platforms: [e.platform])
            XCTAssertLessThan(abs(b.z - (b.platform != nil ? e.z : b.z)), 1e-9, "never sinks into the car or floats above it")
            if r.leftPlatform != nil { e.playerAboard = false; break }
        }
        XCTAssertEqual(b.depth, OpenWorld.storeyBase + 3, "stepped out on storey 3")
        XCTAssertNil(b.platform)
        XCTAssertNotNil(g.floor(b.depth, b.pos.tile), "onto floor")
    }

    func testALandingTakenAwayOrTheShaftTakenDownLeavesNothingHanging() {
        let (s, e, _) = building()
        let town = s.settlements[e.town]!
        town.food = 100
        _ = s.sendByLift(e, key: "food", amount: 40, from: 0, to: 4, source: .town(town.id), dest: .town(town.id))
        while !(e.state == .moving && (s.inLifts()["food"] ?? 0) > 0) { s.liftStep(e, 1.0 / 30, powered: true); s.world.time += 1.0 / 30 }
        // the floor at the storey-4 landing goes
        let d = e.stops[4].door
        s.storeyWorld(4).setTile(0, d.x, d.y, 0)
        s.checkLifts()
        XCTAssertEqual(e.stops.map { $0.level }, [0, 1, 2, 3, 5])
        XCTAssertTrue(e.jobs.isEmpty); XCTAssertEqual(s.inLifts()["food"] ?? 0, 0)
        XCTAssertEqual(town.food, 100, accuracy: 1e-9, "the goods went back where they came from")
        // the shaft is taken down with the traveller in it
        e.playerAboard = true
        let landing = s.removeLift(e.id)
        XCTAssertNotNil(landing, "the traveller is put on a landing")
        XCTAssertTrue(s.realm.lifts.isEmpty)
    }

    /// A standing tower with a real elevator: the town's granary full, the elevator without power: the
    /// upper floor goes hungry; power back, and its pantry fills as the car actually brings food.
    func testUpstairsGoesHungryWhenTheElevatorCannotRunAndRecoversAsFoodArrives() {
        let (s, e, _) = building()
        for _ in 0..<3 { s.tick(Society.hour) }
        let c = s.civ
        let town = s.settlements[e.town]!
        town.food = 4000
        let home = Blueprint.plan(use: .home, w: 12, d: 10, layout: 0, seed: 1)
        c.towerIndex.plans[home.key] = home
        let t = Tower(base: Cell3(0, 0, 0)); t.id = c.towerIndex.nextTower; c.towerIndex.nextTower += 1
        let city = c.cities.values.filter { $0.detail == nil }.sorted { $0.id < $1.id }.first!
        t.city = city.id; t.nation = city.nation; t.w = 12; t.d = 10; t.material = 2
        t.floors = (0..<6).map { var f = TowerFloor(z: Int64($0 * 4), plan: home.key); f.stage = .inUse; return f }
        t.floors[5].people = CivPeople(adults: 20)
        c.towerIndex.towers[t.id] = t
        e.tower = t.id
        t.realLift = true
        // a day without power: nothing is carried, the regional estimate does not carry it either
        func day(powered: Bool) {
            s.supplyTowers()
            for _ in 0..<(24 * 50) { s.liftStep(e, 1, powered: powered); s.world.time += 1 }
            c.towersDay(city)
        }
        t.floors[5].food = 0
        day(powered: false)
        guard t.floors.count == 6 else { return XCTFail("the tower lost floors: \(t.floors.count)") }
        XCTAssertLessThan(t.floors[5].coverage, 0.05, "the granary was full and still the top floor did not eat")
        XCTAssertGreaterThan(t.floors[5].people.state(0), 0)
        day(powered: false)
        XCTAssertLessThan(t.floors[5].people.state(0), 20, "people grew hungry up there")
        let foodBefore = town.food
        day(powered: true)
        XCTAssertGreaterThan(t.floors[5].coverage, 0.9, "food came up in the car")
        XCTAssertLessThan(town.food, foodBefore, "out of the town's real store")
        let hungry = 20 - t.floors[5].people.state(0)
        day(powered: true)
        XCTAssertLessThan(20 - t.floors[5].people.state(0), hungry, "and they recover a step at a time")
    }
}
