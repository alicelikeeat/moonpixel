import XCTest
@testable import MoonPixelCore

/// The city and its transport working together (task sections 1, 2, 5 and 7).
final class CityTransportTests: XCTestCase {


    func testFoodGoesFromTheFarmByLorryTrainAndLorryAndUpTheLiftToBeEaten() {
        var sc = TransportScene()
        let (_, _, train) = TransportScene.freightNetwork(&sc)
        let s = sc.s
        let tower = TransportScene.eastTower(sc)
        let foodA0 = sc.a.store["food"]!
        let sh = s.ship("food", 600, from: .district(sc.a.id), to: .district(sc.b.id), note: "test")!
        XCTAssertEqual(sh.legs.count, 5, "lorry, change, train, change, lorry: \(sh.legs)")
        XCTAssertEqual(sc.a.store["food"]!, foodA0 - 600, accuracy: 1e-9, "it left the farm district at once")
        var trainNear = false, trainFar = false, inTrain = 0.0
        sc.run(3000, dt: 1.0 / 15) {
            let w = s.whereIs(sh)
            XCTAssertEqual(w.yards + w.aboard + w.delivered, 600, accuracy: 1e-6, "every unit is in exactly one place")
            inTrain = max(inTrain, train.cargo[sh.id] ?? 0)
            if train.pos.distance(to: s.realm.player.body!.pos) <= 96 * 16 { trainNear = true } else { trainFar = true }
            return sh.state == .delivered
        }
        XCTAssertEqual(sh.state, .delivered)
        XCTAssertEqual(sh.delivered, 600, accuracy: 1e-6)
        XCTAssertGreaterThan(inTrain, 0, "it rode the train")
        XCTAssertTrue(trainNear && trainFar, "the train ran both near (physics) and far (along its way), and nothing was lost or doubled")
        XCTAssertGreaterThanOrEqual(sc.b.store["food"] ?? 0, 600 - 1e-6)
        // up the lift to every floor, then eaten
        s.distributeFood(sc.b)
        let top = sc.b.building(tower)!.floors.count - 1
        sc.run(400) { (sc.b.building(tower)!.floors[top].food) >= 29 }
        XCTAssertGreaterThan(sc.b.building(tower)!.floors[top].food, 0, "the twelfth floor's pantry was filled by the lift")
        XCTAssertTrue(s.realm.transport.ledger.contains { $0.note.hasPrefix("deliver shipment") })
        let eaten0 = sc.b.foodEaten
        s.districtDay(sc.b)
        XCTAssertGreaterThan(sc.b.foodEaten, eaten0)
        XCTAssertEqual(sc.b.building(tower)!.floors[top].hungry, 0)
    }

    func testWithTheLiftsDownTheUpperFloorsGoHungryWhileTheWarehouseIsFullThenRecover() {
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        let tower = TransportScene.eastTower(sc)
        sc.b.store["food"] = 5000
        // the power station is lost: the elevator stops
        let pIdx = sc.b.buildings.firstIndex { $0.kind == "power" }!
        let plant = sc.b.buildings.remove(at: pIdx)
        s.refreshServices(sc.b)
        for _ in 0..<3 {
            s.districtDay(sc.b)
            sc.run(200)
        }
        let top = sc.b.building(tower)!.floors.count - 1
        XCTAssertGreaterThan(sc.b.store["food"] ?? 0, 4000, "the warehouse is full")
        XCTAssertGreaterThan(sc.b.building(tower)!.floors[top].hungry, 0, "but the top floor goes short: no lift")
        XCTAssertEqual(sc.b.building(tower)!.floors[1].hungry, 0, "the first floor is carried up the stairs")
        XCTAssertEqual(s.lift(sc.b.building(tower)!.lift!).map { s.liftPowered($0) }, false)
        XCTAssertTrue(sc.b.events.contains { $0.contains("power short") || $0.contains("food short") })
        // power back: food goes up and the hunger ends
        sc.b.buildings.append(plant)
        sc.b.staffing[plant.id] = 1
        s.refreshServices(sc.b)
        for _ in 0..<2 {
            s.districtDay(sc.b)
            sc.run(300)
        }
        XCTAssertEqual(sc.b.building(tower)!.floors[top].hungry, 0, "it recovered as the food arrived")
        XCTAssertEqual(sc.b.population, sc.b.ledger.expected, "everyone accounted for: \(sc.b.ledger)")
    }

    func testAResidentRidesTheLiftDownTakesTheBusAndTheHighSpeedTrainToWork() {
        let (sc, westHSR, eastHSR) = TransportScene.hsrScene()
        let s = sc.s
        let home = TransportScene.eastTower(sc)
        // a bus from the tower to the station, and the high-speed train west
        let tower = s.addStop(.busStop, at: sc.t(108, 60), name: "Tower", nation: 1, district: sc.b.id)!
        let busEnd = s.addStop(.busStop, at: sc.t(150, 60), name: "Station Rd", nation: 1, district: sc.b.id)!
        let bus = s.addLine(.bus, stops: [tower.id, busEnd.id], name: "B1", headway: 90, nation: 1, payer: .district(sc.b.id))!
        s.assign(s.buildVehicle(.bus, at: sc.t(108, 60), heading: 0, payer: .district(sc.b.id), nation: 1)!, to: bus)
        let hsr = s.addLine(.hsr, stops: [eastHSR.id, westHSR.id], name: "Express", headway: 200, nation: 1, payer: .district(sc.a.id))!
        s.assign(s.buildVehicle(.hsr, at: sc.t(152, 66), heading: Double.pi, payer: .district(sc.a.id), nation: 1)!, to: hsr)
        // work: offices by the western station
        let office = s.placeCityBuilding(sc.a, kind: "offices", at: sc.t(12, 70))!
        _ = office
        XCTAssertEqual(s.addCommuters(from: sc.b, to: sc.a, n: 1), 1)
        var c = s.realm.transport.commuters[0]
        XCTAssertEqual(c.homeB, home); XCTAssertGreaterThan(c.homeLevel, 0, "they live upstairs")
        let pop0 = sc.b.population
        // seven in the morning
        let day = Int(s.world.time / MP.daySeconds) + 1
        s.world.time = Double(day) * MP.daySeconds + 7.0 / 24 * MP.daySeconds - 1
        s.realm.transport.day = day
        sc.run(1200, dt: 1.0 / 15) { s.realm.transport.commuters[0].state == .atWork }
        c = s.realm.transport.commuters[0]
        XCTAssertEqual(c.state, .atWork, c.history.joined(separator: "\n"))
        let h = c.history.joined(separator: "|")
        for step in ["lift down", "out of the lift", "waiting at Tower", "off at Station Rd", "waiting at East HSR", "off at West HSR", "arrived"] {
            XCTAssertTrue(h.contains(step), "\(step) missing from: \(h)")
        }
        // the order: lift, bus, train
        XCTAssertLessThan(h.range(of: "lift down")!.lowerBound, h.range(of: "waiting at Tower")!.lowerBound)
        XCTAssertLessThan(h.range(of: "off at Station Rd")!.lowerBound, h.range(of: "waiting at East HSR")!.lowerBound)
        XCTAssertEqual(sc.b.population, pop0, "commuting moves nobody out: they are still counted at home")
        XCTAssertGreaterThan(bus.revenue + hsr.revenue, 0, "fares were paid")
    }

    func testOreLandedAtThePortIsWorkedIntoWaresThatAreSoldAndShippedOut() {
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        sc.lay(.quay, sc.t(73, 10), sc.t(73, 16), payer: .district(sc.a.id))
        sc.lay(.quay, sc.t(82, 40), sc.t(82, 46), payer: .district(sc.b.id))
        let pa = s.addStop(.port, at: sc.t(74, 13), name: "West port", nation: 1, district: sc.a.id)!
        let pb = s.addStop(.port, at: sc.t(81, 43), name: "East port", nation: 1, district: sc.b.id)!
        let line = s.addLine(.freighter, stops: [pa.id, pb.id], name: "Ore boats", headway: 200, nation: 1, payer: .district(sc.a.id), freight: true)!
        s.assign(s.buildVehicle(.freighter, at: sc.t(76, 14), heading: Double.pi / 2, payer: .district(sc.a.id), nation: 1)!, to: line)
        sc.a.store["iron_ore"] = 400
        let sh = s.ship("iron_ore", 400, from: .district(sc.a.id), to: .district(sc.b.id))!
        sc.run(900, dt: 1.0 / 15) { sh.state == .delivered }
        XCTAssertEqual(sh.state, .delivered)
        XCTAssertEqual(sc.b.store["iron_ore"] ?? 0, 400, accuracy: 1e-6)
        // the factory and the shops in the east city, with people to work them
        _ = TransportScene.eastTower(sc, residentsPerFloor: 12)
        XCTAssertNotNil(s.placeCityBuilding(sc.b, kind: "factory", at: sc.t(140, 70)))
        XCTAssertNotNil(s.placeCityBuilding(sc.b, kind: "shops", at: sc.t(128, 70)))
        s.districtDay(sc.b)
        XCTAssertLessThan(sc.b.store["iron_ore"] ?? 0, 400, "the factory used ore")
        let made = (sc.b.store["wares"] ?? 0)
        s.districtDay(sc.b)
        XCTAssertGreaterThan(made, 0, "and made wares")
        // what the city does not sell goes out by the same boats
        sc.b.store["wares"] = (sc.b.store["wares"] ?? 0) + 100
        let out = s.ship("wares", 100, from: .district(sc.b.id), to: .district(sc.a.id))!
        sc.run(900, dt: 1.0 / 15) { out.state == .delivered }
        XCTAssertEqual(out.state, .delivered)
        XCTAssertGreaterThanOrEqual(sc.a.store["wares"] ?? 0, 100 - 1e-6)
    }

    func testCongestionPowerCutsHungerAndWarEachHaveAVisibleCause() {
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        // congestion: lorries crowding one street far from the traveller
        s.realm.player.body = Body(at: sc.t(15, 130).center, z: 0, depth: 0)
        // four cars built a few tiles apart, then queued nose to tail on two tiles
        for k in 0..<4 {
            guard let v = s.buildVehicle(.car, at: sc.t(100 + k * 4, 60), heading: 0, payer: .district(sc.b.id), nation: 1) else { return XCTFail("car \(k): \(String(describing: s.wayKind(at: sc.t(100 + k * 4, 60)))) iron \(sc.b.store["iron"] ?? -1) parts \(sc.b.store["parts"] ?? -1)") }
            v.x = Double(sc.t(120, 60).x * 16) + 3 + Double(k) * 7; v.control = .manual
        }
        s.countTraffic()
        XCTAssertTrue(s.bottlenecks().contains { $0.hasPrefix("jam:") }, "\(s.bottlenecks())")
        // war: a line into a nation at war is suspended, and nobody may wait for it
        let a = s.addStop(.busStop, at: sc.t(10, 60), name: "W", nation: 1, district: sc.a.id)!
        let b = s.addStop(.busStop, at: sc.t(140, 60), name: "E", nation: 2, district: sc.b.id)!
        let l = s.addLine(.bus, stops: [a.id, b.id], name: "Border", headway: 120, nation: 1, payer: .district(sc.a.id))!
        if s.realm.nation(2) == nil { var n = Nation(); n.id = 2; s.realm.nations.append(n) }
        if s.realm.nation(1) == nil { var n = Nation(); n.id = 1; s.realm.nations.append(n) }
        let r = s.realm.meet(1, 2, at: s.world.time); s.realm.relations[r].state = 1
        sc.run(1)
        XCTAssertEqual(l.suspended, "war")
        s.realm.player.nation = 1
        XCTAssertFalse(s.waitAt(a.id, for: b.id, who: .player), "the border is closed")
        XCTAssertTrue(s.bottlenecks().contains { $0.hasPrefix("suspended:Border") })
        s.realm.relations[r].state = 0
        sc.run(1)
        XCTAssertNil(l.suspended, "it runs again when the war ends")
        // hunger: a block with no food loses people to hunger and to leaving, all in the books
        let id = TransportScene.eastTower(sc)
        sc.b.store["food"] = 0
        for i in sc.b.buildings.indices { for f in sc.b.buildings[i].floors.indices { sc.b.buildings[i].floors[f].food = 0 } }
        for _ in 0..<5 { s.districtDay(sc.b) }
        XCTAssertGreaterThan(sc.b.ledger.deaths["hunger"] ?? 0, 0)
        XCTAssertGreaterThan(sc.b.ledger.emigrants.values.reduce(0, +), 0)
        XCTAssertEqual(sc.b.population, sc.b.ledger.expected)
        XCTAssertLessThan(sc.b.building(id)!.residents, 120)
        XCTAssertTrue(sc.b.events.contains { $0.contains("food short") })
    }

    func testAVehicleSavedInMotionCarriesOnExactlyAsIfNeverSaved() throws {
        func world() -> (TransportScene, Vehicle, Shipment) {
            var sc = TransportScene()
            let (_, _, train) = TransportScene.freightNetwork(&sc)
            let sh = sc.s.ship("food", 300, from: .district(sc.a.id), to: .district(sc.b.id))!
            sc.s.realm.transport.stops.first { $0.name == "West farm yard" }!.waiting.append(Rider(who: .agent(-5), from: 0, to: 0))
            return (sc, train, sh)
        }
        let (a, trainA, shA) = world()
        let (b, _, _) = world()
        a.run(120, dt: 1.0 / 15); b.run(120, dt: 1.0 / 15)
        // save b in the middle of everything and load it back
        let data = try JSONEncoder().encode(b.s.snapshot())
        b.s.restore(try JSONDecoder().decode(Society.Snapshot.self, from: data))
        a.run(300, dt: 1.0 / 15); b.run(300, dt: 1.0 / 15)
        let trainB = b.s.net.vehicle(trainA.id)!
        XCTAssertEqual(trainB.x, trainA.x, accuracy: 1e-6); XCTAssertEqual(trainB.y, trainA.y, accuracy: 1e-6)
        XCTAssertEqual(trainB.speed, trainA.speed, accuracy: 1e-6)
        XCTAssertEqual(trainB.fuel, trainA.fuel, accuracy: 1e-6)
        XCTAssertEqual(trainB.cargo, trainA.cargo)
        XCTAssertEqual(trainB.task, trainA.task)
        let shB = b.s.net.shipments.first { $0.id == shA.id }!
        XCTAssertEqual(shB.delivered, shA.delivered, accuracy: 1e-9)
        let wa = a.s.whereIs(shA), wb = b.s.whereIs(shB)
        XCTAssertEqual(wa.yards, wb.yards, accuracy: 1e-9); XCTAssertEqual(wa.aboard, wb.aboard, accuracy: 1e-9)
        XCTAssertEqual(wb.yards + wb.aboard + wb.delivered, 300, accuracy: 1e-6, "nothing lost or doubled by saving")
        XCTAssertEqual(b.s.net.vehicles.count, a.s.net.vehicles.count)
    }

    func testAMetroCityComesIntoTheWorldWithItsPeopleMoneyAndBuildingsOnce() {
        let m = Metro(seed: 1, worldSeed: 7)
        m.layOutDemo()
        for _ in 0..<240 { m.step() }
        let pop = m.population, money = m.money
        XCTAssertGreaterThan(pop, 300)
        let s = makeSociety(7, villages: 2, per: 10)
        s.linkMetro(population: pop, name: m.name)
        let known0 = s.knownPopulation
        let d = s.importMetro(m, nation: 1)!
        XCTAssertEqual(d.population, pop, "every resident has a floor")
        XCTAssertEqual(d.ledger.imported, pop)
        XCTAssertEqual(d.money, money, accuracy: 1e-9)
        let builtTiles = m.level.filter { $0 > 0 }.count
        let covered = d.buildings.filter { $0.fromMetro && $0.def.service == nil }.reduce(0) { $0 + $1.w * $1.d }
        XCTAssertEqual(covered, builtTiles, "every built tile is part of a building")
        XCTAssertNil(s.realm.metroLink, "the people are counted in the district now, not twice")
        XCTAssertEqual(s.knownPopulation - d.population, known0 - pop)
        // streets on the same land
        let roadTiles = m.road.enumerated().filter { $0.element != 0 }.map { TilePos(m.cx * 32 + $0.offset % Metro.size, m.cy * 32 + $0.offset / Metro.size) }
        XCTAssertGreaterThan(roadTiles.filter { s.wayKind(at: $0)?.mode == .road }.count, roadTiles.count * 9 / 10)
        // a second import does nothing
        let again = s.importMetro(m, nation: 1)!
        XCTAssertEqual(again.id, d.id)
        XCTAssertEqual(s.realm.transport.districts.count, 1)
        XCTAssertEqual(d.population, pop)
    }

    func testThePlannerBuildsInOrderAndNeverOnWhatOthersBuilt() {
        var sc = TransportScene()
        sc.cities()
        let s = sc.s
        let d = sc.a!
        d.autoBuild = true
        d.store["food"] = 50
        // something the player built where the planner would like to build
        s.raiseHouse(at: sc.t(18, 52), storeys: 1, w: 5, d: 5)
        let houseTiles = (0..<5).flatMap { y in (0..<5).map { x in sc.t(18 + x, 52 + y) } }
        var order: [String] = []
        for _ in 0..<30 {
            s.districtDay(d)
            s.workSites(hours: 24)
            for b in d.buildings { let key = "\(b.id):\(b.state.rawValue)"; if !order.contains(key) { order.append(key) } }
        }
        let opened = d.buildings.filter { $0.state == .open }
        XCTAssertGreaterThanOrEqual(opened.count, 2, "\(d.events)")
        for b in opened {
            let seen = order.filter { $0.hasPrefix("\(b.id):") }.map { String($0.split(separator: ":")[1]) }
            var at = -1
            for st in ["road", "waiting", "building", "open"] { let k = seen.firstIndex(of: st) ?? -1; XCTAssertGreaterThan(k, at, "building \(b.id) went \(seen)"); at = k }
        }
        XCTAssertTrue(s.realm.transport.sites.contains { $0.by == "district:\(d.id)" } || opened.allSatisfy { s.nearRoad($0.front, 1) }, "streets were brought to the doors")
        let first = d.buildings.first!
        XCTAssertEqual(first.def.service, "power", "power comes first in an empty district")
        // each building went planned/clearing -> road -> waiting -> building -> open, never skipping
        for b in d.buildings where b.state == .open && !b.fromMetro {
            let seen = order.filter { $0.hasPrefix("\(b.id):") }.map { String($0.split(separator: ":")[1]) }
            XCTAssertEqual(seen.last, "open")
        }
        for b in d.buildings { for t in houseTiles { XCTAssertFalse(b.contains(t), "the planner built over the player's house") } }
        XCTAssertEqual(s.world.tile(2, sc.t(18, 52).x, sc.t(18, 52).y), s.content.tid("wall_stone"))
        // no money, no building
        d.money = 0
        let n = d.buildings.filter { $0.state == .open }.count
        for _ in 0..<5 { s.districtDay(d) }
        XCTAssertEqual(d.buildings.filter { $0.state == .open }.count, n)
    }

    func testABusAcrossTheRiverStopsWhenTheBridgeFallsAndGoesRoundByANewOne() {
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        let a = s.addStop(.busStop, at: sc.t(10, 60), name: "W", nation: 1, district: sc.a.id)!
        let b = s.addStop(.busStop, at: sc.t(140, 60), name: "E", nation: 1, district: sc.b.id)!
        let line = s.addLine(.bus, stops: [a.id, b.id], name: "River", headway: 60, nation: 1, payer: .district(sc.a.id))!
        let bus = s.buildVehicle(.bus, at: sc.t(10, 60), heading: 0, payer: .district(sc.a.id), nation: 1)!
        s.assign(bus, to: line)
        a.waiting.append(Rider(who: .agent(-3), from: a.id, to: b.id))
        sc.run(200) { bus.task.at == 1 && bus.task.standing }
        XCTAssertEqual(s.realm.transport.stats.trips, 1, "people and goods cross while the bridge stands")
        // the bus goes back west; the bridge falls before it gets there
        sc.run(30) { !bus.task.standing }
        s.demolishBridge(s.realm.transport.bridges.first!.id)
        sc.run(60)
        XCTAssertEqual(bus.halted, "no way", "it stops and waits: it does not drive into the river")
        XCTAssertTrue(bus.tile.x - sc.o.x > TransportScene.river.upperBound || bus.tile.x - sc.o.x < TransportScene.river.lowerBound)
        XCTAssertTrue(s.bottlenecks().contains { $0.contains("no way") })
        // a new road with its own bridge further south: it goes round by it
        sc.lay(.street, sc.t(36, 60), sc.t(36, 100), payer: .district(sc.a.id))
        sc.lay(.street, sc.t(36, 100), sc.t(100, 100), payer: .district(sc.a.id))
        sc.lay(.street, sc.t(100, 100), sc.t(100, 60), payer: .district(sc.a.id))
        sc.run(400) { bus.task.at == 0 && bus.task.standing }
        XCTAssertNil(bus.halted)
        XCTAssertEqual(bus.task.at, 0, "back in the west, round the long way")
    }

    func testVehiclesBurnFuelDrawFromTheStoreAndAreRepairedWithParts() {
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        let fuel0 = sc.a.store["fuel"]!
        let car = s.buildVehicle(.car, at: sc.t(10, 60), payer: .district(sc.a.id), nation: 1)!
        XCTAssertEqual(sc.a.store["fuel"]!, fuel0 - car.spec.tank, accuracy: 1e-9, "the tank was filled from the store")
        car.control = .manual; car.input.throttle = 1
        sc.run(10)
        XCTAssertLessThan(car.fuel, car.spec.tank)
        let burnt = car.spec.tank - car.fuel
        XCTAssertEqual(s.realm.transport.stats.fuelBurnt, burnt, accuracy: 1e-6)
        s.refuel(car)
        XCTAssertEqual(sc.a.store["fuel"]!, fuel0 - car.spec.tank - burnt, accuracy: 1e-6, "what was burnt was bought from the store, no more")
        // an empty tank: no pull
        car.fuel = 0; car.speed = 0
        sc.run(3)
        XCTAssertEqual(car.speed, 0, accuracy: 1e-9); XCTAssertEqual(car.halted, "no fuel")
        // wear and parts
        car.wear = 0.5
        let parts0 = sc.a.store["parts"]!
        XCTAssertTrue(s.repair(car))
        XCTAssertEqual(car.wear, 0)
        XCTAssertEqual(sc.a.store["parts"]!, parts0 - 5, accuracy: 1e-9)
        sc.a.store["parts"] = 0
        car.wear = 1
        XCTAssertFalse(s.repair(car), "no parts, no repair")
        car.fuel = 10; car.input.throttle = 1
        sc.run(2)
        XCTAssertEqual(car.halted, "broken down")
    }
}

final class TransportDemoTests: XCTestCase {
    func testTheDemoIsBuiltOnRealLandByTheSameRulesAndItsVehiclesWork() {
        let s = makeSociety(5, villages: 2, per: 10)
        s.realm.player.body = Body(at: TilePos(0, 0).center, z: 0, depth: 0)
        let d = s.transportDemo(near: TilePos(0, 0))
        XCTAssertNotNil(d.car, "\(d.notes)"); XCTAssertNotNil(d.bus, "\(d.notes)")
        // no vehicle stands on another
        let vs = s.net.vehicles
        for a in vs { for b in vs where a.id < b.id && a.kind.mode == b.kind.mode && a.kind.mode == .road { XCTAssertGreaterThan(a.pos.distance(to: b.pos), (a.spec.radius + b.spec.radius) * 16, "\(a.kind) and \(b.kind) built on top of each other") } }
        let car = s.net.vehicle(d.car!)!
        XCTAssertGreaterThan(car.fuel, 0)
        XCTAssertTrue(s.realm.transport.ledger.contains { $0.note.hasPrefix("build") }, "paid like any other way")
        // the player drives it
        s.realm.player.body = Body(at: car.pos, z: 0, depth: 0)
        XCTAssertNil(s.board(car.id, drive: true))
        var c = Controls(); c.throttle = 1
        s.steer(c)
        let p0 = car.pos
        for _ in 0..<60 { s.transportTick(1.0 / 30); s.world.time += 1.0 / 30 }
        XCTAssertNotNil(d.plane, "\(d.notes)"); XCTAssertNotNil(d.train, "\(d.notes)")
        XCTAssertGreaterThan(car.speed, 3, "halted \(car.halted ?? "-") at \(car.tile) way \(String(describing: s.wayKind(at: car.tile))) next \(String(describing: s.wayKind(at: TilePos(car.tile.x + 1, car.tile.y)))) blocked \(s.world.blocked(car.tile.x + 1, car.tile.y)) notes \(d.notes) input \(car.input) ctl \(car.control)")
        // the demo street gives a straight run to drive: the UI test reads the speed after a second or two
        for _ in 0..<60 { s.transportTick(1.0 / 30); s.world.time += 1.0 / 30 }
        XCTAssertGreaterThan(car.pos.distance(to: p0) / 16, 8, "it drove along the street instead of into something")
        XCTAssertNil(car.halted)
        // and the same in the world the UI tests use (seed 7), through the society's whole tick
        let s7 = makeSociety(7)
        let home = s7.settlements.values.sorted { $0.id < $1.id }[0].center
        s7.realm.player.body = Body(at: home.center, z: 0, depth: 0)
        let d7 = s7.transportDemo(near: home)
        let car7 = s7.net.vehicle(d7.car!)!
        s7.realm.player.body = Body(at: car7.world(0, 1.2), z: 0, depth: 0)
        XCTAssertNil(s7.board(car7.id, drive: true))
        let q0 = car7.pos
        var c7 = Controls(); c7.throttle = 0.9
        for _ in 0..<30 { s7.steer(c7); s7.tick(1.0 / 15) }
        XCTAssertGreaterThan(car7.speed * 7.2, 10, "km/h after two seconds")
        XCTAssertGreaterThan(car7.pos.distance(to: q0) / 16, 3)
        // the app's own start: beside the first village, the game running a few seconds before the demo
        let s8 = makeSociety(7)
        let start8 = s8.world.findFree(near: s8.settlements[1]!.center + TilePos(0, 4), maxR: 8).center
        s8.realm.player.body = Body(at: start8, z: 0, depth: 0)
        for _ in 0..<(6 * 30) { s8.tick(1.0 / 30) }
        let d8 = s8.transportDemo(near: start8.tile)
        XCTAssertNotNil(d8.bus, "\(d8.notes)"); XCTAssertNotNil(d8.train, "\(d8.notes)")
        let car8 = s8.net.vehicle(d8.car!)!
        s8.realm.player.body = Body(at: car8.world(0, 1.2), z: 0, depth: 0)
        for _ in 0..<(9 * 30) { s8.tick(1.0 / 30) }
        XCTAssertNil(s8.board(car8.id, drive: true))
        var c8 = Controls(); c8.throttle = 1
        let r0 = car8.pos
        for _ in 0..<60 { s8.steer(c8); s8.tick(1.0 / 30) }
        XCTAssertGreaterThan(car8.speed * 7.2, 10); XCTAssertGreaterThan(car8.pos.distance(to: r0) / 16, 2)
        // the 3D models have the vehicles' own size
        for k in VehicleKind.allCases { XCTAssertFalse(Figure3D.vehicle(k).isEmpty, "\(k)") }
    }
}
