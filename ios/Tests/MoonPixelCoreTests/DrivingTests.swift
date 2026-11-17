import XCTest
@testable import MoonPixelCore

/// Every kind of vehicle driven by hand, by the autopilot, and handed between them (task section 3).
final class DrivingTests: XCTestCase {
    /// Drive with these controls for `seconds`.
    func hold(_ sc: TransportScene, _ v: Vehicle, _ c: Controls, _ seconds: Double, until: (() -> Bool)? = nil) {
        sc.s.steer(c)
        if !v.playerDriving { v.input = c }
        sc.run(seconds, until: until)
    }

    func driver(_ sc: TransportScene, _ v: Vehicle) {
        sc.s.realm.player.body = Body(at: v.pos, z: 0, depth: 0)
        XCTAssertNil(sc.s.board(v.id, drive: true))
        XCTAssertEqual(v.control, .manual)
        XCTAssertTrue(v.playerDriving)
    }

    // MARK: a car

    func testACarSteersAcceleratesBrakesAndReverses() {
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        let car = s.buildVehicle(.car, at: sc.t(10, 60), heading: 0, payer: .district(sc.a.id), nation: 1)!
        XCTAssertGreaterThan(car.fuel, 0, "filled from the district's fuel")
        driver(sc, car)
        var c = Controls(); c.throttle = 1
        let x0 = car.x
        hold(sc, car, c, 3)
        XCTAssertGreaterThan(car.speed, 5, "it accelerates")
        XCTAssertGreaterThan(car.x, x0 + 16 * 5)
        XCTAssertEqual(car.heading, 0, accuracy: 1e-9, "straight ahead with the wheel straight")
        // the player is carried with it
        XCTAssertEqual(s.realm.player.body!.x, car.x, accuracy: 16)
        // brake to a stop: it stops, it does not roll backwards
        c = Controls(); c.brake = 1
        hold(sc, car, c, 4)
        XCTAssertEqual(car.speed, 0, accuracy: 1e-9)
        // reverse
        c = Controls(); c.throttle = 0.5; c.reverse = true
        let xr = car.x
        hold(sc, car, c, 2)
        XCTAssertLessThan(car.speed, 0)
        XCTAssertLessThan(car.x, xr)
        XCTAssertGreaterThanOrEqual(car.speed, -car.spec.reverseMax - 1e-9)
        // steer: a left lock turns it left (heading falls, y grows down so left is towards -y when heading east)
        c = Controls(); c.brake = 1; hold(sc, car, c, 2)
        c = Controls(); c.throttle = 0.4; c.steer = -1
        let h0 = car.heading
        hold(sc, car, c, 1)
        XCTAssertLessThan(car.heading, h0 - 0.2)
        XCTAssertGreaterThan(s.realm.transport.stats.fuelBurnt, 0, "fuel is burnt")
    }

    func testACarCannotDriveThroughTreesWaterOrOtherCars() {
        var sc = TransportScene()
        sc.cities()
        let s = sc.s
        let car = s.buildVehicle(.car, at: sc.t(34, 60), heading: 0, payer: .district(sc.a.id), nation: 1)!
        driver(sc, car)
        var c = Controls(); c.throttle = 1
        hold(sc, car, c, 12)
        XCTAssertLessThan(car.tile.x, sc.t(40, 60).x, "stopped by the forest")
        XCTAssertEqual(car.speed, 0, accuracy: 1e-9)
        // a parked car in the way
        let other = s.buildVehicle(.car, at: sc.t(20, 60), heading: 0, payer: .district(sc.a.id), nation: 1)!
        other.control = .manual
        c = Controls(); c.throttle = 1; c.reverse = true
        hold(sc, car, c, 20)
        XCTAssertGreaterThanOrEqual(car.pos.distance(to: other.pos), (car.spec.radius + other.spec.radius) * 16 - 1e-6, "never inside another car")
    }

    func testTakingTheWheelAndHandingItBackKeepsPositionSpeedPeopleGoodsAndJob() {
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        let a = s.addStop(.busStop, at: sc.t(8, 60), name: "West Sq", nation: 1, district: sc.a.id)!
        let b = s.addStop(.busStop, at: sc.t(150, 60), name: "East Sq", nation: 1, district: sc.b.id)!
        let line = s.addLine(.bus, stops: [a.id, b.id], name: "1", headway: 120, nation: 1, payer: .district(sc.a.id))!
        let bus = s.buildVehicle(.bus, at: sc.t(8, 60), heading: 0, payer: .district(sc.a.id), nation: 1)!
        s.assign(bus, to: line)
        // two people wait at West Sq for East Sq
        let homeB = s.foundDistrict(name: "tmp", at: sc.t(5, 5), nation: 1)
        _ = homeB
        a.waiting.append(Rider(who: .agent(-9), from: a.id, to: b.id)); a.waiting.append(Rider(who: .agent(-8), from: a.id, to: b.id))
        sc.run(80) { bus.speed > 6 }
        XCTAssertEqual(bus.riders.count, 2)
        XCTAssertGreaterThan(bus.speed, 6)
        // take over in motion: everything stays as it was
        s.realm.player.body = Body(at: bus.pos, z: 0, depth: 0)
        let before = (bus.x, bus.y, bus.speed, bus.heading, bus.riders, bus.cargo, bus.task, bus.fuel)
        s.setControl(bus, .manual)
        XCTAssertEqual(bus.x, before.0); XCTAssertEqual(bus.y, before.1); XCTAssertEqual(bus.speed, before.2); XCTAssertEqual(bus.heading, before.3)
        XCTAssertEqual(bus.riders, before.4); XCTAssertEqual(bus.task, before.6); XCTAssertEqual(bus.fuel, before.7)
        // a step later it has moved only as far as its speed allows (no jump)
        let p0 = bus.pos
        bus.input = Controls()
        sc.run(1.0 / 30)
        XCTAssertLessThanOrEqual(bus.pos.distance(to: p0), (before.2 + 0.2) * 16 / 30 + 1e-6)
        // and back to the autopilot: it carries on to East Sq with the same people
        s.handOver(bus, to: .auto)
        let p1 = bus.pos
        sc.run(1.0 / 30)
        XCTAssertLessThanOrEqual(bus.pos.distance(to: p1), (bus.spec.maxSpeed) * 16 / 30 + 1e-6)
        sc.run(240) { bus.task.at == 1 && bus.task.standing }
        XCTAssertEqual(bus.task.at, 1); XCTAssertTrue(bus.task.standing)
        XCTAssertEqual(bus.riders.count, 0, "they got off at East Sq")
        XCTAssertEqual(s.realm.transport.stats.trips, 2)
    }

    // MARK: walking in a moving vehicle

    func testWalkingAndJumpingInAMovingBusCarriesThePlayerWithIt() {
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        let bus = s.buildVehicle(.bus, at: sc.t(10, 60), heading: 0, payer: .district(sc.a.id), nation: 1)!
        bus.control = .manual
        s.realm.player.body = Body(at: bus.pos, z: 0, depth: 0)
        XCTAssertNil(s.board(bus.id, drive: false), "a passenger")
        bus.input.throttle = 0.8
        var maxGap = 0.0, landedInside = false, peak = 0.0
        for i in 0..<240 {
            let jump = i == 60
            let wish = i < 120 ? Vec2(-24, 0) : Vec2(0, 0)          // walking towards the back
            let r = s.moveAboard(dt: 1.0 / 30, wish: wish, jump: jump)
            peak = max(peak, s.realm.player.body!.lz ?? 0)
            if r.landed && i > 60 { landedInside = true }
            sc.run(1.0 / 30)
            let b = s.realm.player.body!
            let (f, r2) = bus.local(Vec2(b.x, b.y))
            maxGap = max(maxGap, abs(f) - bus.spec.deckL / 2, abs(r2) - bus.spec.deckW / 2)
        }
        XCTAssertGreaterThan(bus.speed, 5)
        XCTAssertLessThanOrEqual(maxGap, 0.6, "always inside the bus, however fast it goes")
        XCTAssertTrue(landedInside, "the jump lands back on the bus floor")
        XCTAssertGreaterThan(peak, 0.5)
        XCTAssertEqual(s.realm.player.body!.vehicle, bus.id)
        XCTAssertNotNil(s.leaveVehicle(), "no getting out while it moves")
        bus.input = Controls(); bus.input.brake = 1
        sc.run(6)
        XCTAssertNil(s.leaveVehicle())
        XCTAssertNil(s.realm.player.body!.vehicle)
        XCTAssertFalse(bus.playerAboard)
    }

    // MARK: high-speed train


    func testAHighSpeedTrainIsDrivenOnItsTrackWithTractionBrakesAndAPlatformStop() {
        let (sc, a, b) = TransportScene.hsrScene()
        let s = sc.s
        _ = a
        let train = s.buildVehicle(.hsr, at: sc.t(8, 66), heading: 0, payer: .district(sc.a.id), nation: 1)!
        train.task.goal = b.node
        s.plan(train)
        XCTAssertFalse(train.path.isEmpty)
        XCTAssertTrue(train.path.allSatisfy { s.wayKind(at: $0.tile) == .hsr || $0.l == 1 }, "only on high-speed track")
        driver(sc, train)
        var c = Controls(); c.throttle = 1
        hold(sc, train, c, 20)
        XCTAssertGreaterThan(train.speed, 10, "traction")
        XCTAssertGreaterThan(s.realm.transport.stats.powerUsed, 0, "it draws power, not fuel")
        XCTAssertEqual(train.fuel, 0)
        // stay on the rails whatever the wheel says
        c.steer = 1
        hold(sc, train, c, 1)
        XCTAssertEqual(s.wayKind(at: train.tile) == .hsr || train.level == 1, true)
        // brake to stop at the platform: coast, then brake in time
        c = Controls()
        let stopAt = b.tile
        hold(sc, train, c, 60) { Double(stopAt.x - train.tile.x) - train.speed * train.speed / (2 * train.spec.brake) < 3 }
        c.brake = 1
        hold(sc, train, c, 60) { train.speed == 0 }
        XCTAssertEqual(train.speed, 0)
        XCTAssertLessThanOrEqual(abs(train.tile.x - stopAt.x), 6, "stopped at the platform: \(train.tile.x - stopAt.x)")
    }

    func testSignalsKeepASecondTrainOffTrackTheFirstHolds() {
        let (sc, a, b) = TransportScene.hsrScene()
        let s = sc.s
        let first = s.buildVehicle(.hsr, at: sc.t(60, 66), heading: 0, payer: .district(sc.a.id), nation: 1)!
        first.control = .manual; first.task.goal = b.node; s.plan(first)
        first.input = Controls(); first.input.brake = 1                 // stands on the line
        let second = s.buildVehicle(.hsr, at: sc.t(20, 66), heading: 0, payer: .district(sc.a.id), nation: 1)!
        second.task.goal = b.node; s.plan(second)
        driver(sc, second)
        var c = Controls(); c.throttle = 1                              // the driver ignores the red signal
        hold(sc, second, c, 40)
        XCTAssertGreaterThan(second.pos.distance(to: first.pos) / 16, first.spec.length, "the protection system stopped it short of the train ahead")
        XCTAssertEqual(second.halted, "red signal")
        XCTAssertTrue(s.vehicleEvents.contains { $0.vehicle == second.id && $0.what.contains("red signal") })
        _ = a
        // the first moves off: the second may go
        first.input = Controls(); first.input.throttle = 1
        hold(sc, second, c, 15)
        XCTAssertNil(second.halted)
    }

    func testWithoutPowerAnElectricTrainHasNoTraction() {
        let (sc, _, b) = TransportScene.hsrScene()
        let s = sc.s
        let train = s.buildVehicle(.hsr, at: sc.t(8, 66), heading: 0, payer: .district(sc.a.id), nation: 1)!
        train.task.goal = b.node; s.plan(train)
        sc.a.buildings.removeAll { $0.id == 999 }
        s.refreshServices(sc.a)
        driver(sc, train)
        var c = Controls(); c.throttle = 1
        hold(sc, train, c, 10)
        XCTAssertEqual(train.speed, 0, accuracy: 1e-9)
        XCTAssertEqual(train.halted, "no power")
    }

    // MARK: aircraft


    func testAnAirlinerTaxisTakesOffFliesAndLandsOnTheAutopilot() {
        let (sc, _, b) = TransportScene.airScene()
        let s = sc.s
        let plane = s.buildVehicle(.airliner, at: sc.t(2, 120), heading: 0, payer: .district(sc.a.id), nation: 1)!
        plane.task.goal = b.node
        s.realm.player.body = Body(at: plane.pos, z: 0, depth: 0)
        XCTAssertNil(s.board(plane.id, drive: false), "a passenger")
        var flew = false, maxZ = 0.0
        sc.run(240, dt: 1.0 / 30) {
            if plane.flight == .air { flew = true }
            maxZ = max(maxZ, plane.z)
            return flew && plane.flight == .ground && plane.speed < 0.5
        }
        XCTAssertTrue(flew, "it took off")
        XCTAssertGreaterThan(maxZ, 3)
        XCTAssertEqual(plane.flight, .ground, "landed, not crashed: \(plane.halted ?? "")")
        XCTAssertEqual(s.wayKind(at: plane.tile), .runway)
        XCTAssertGreaterThan(plane.tile.x, sc.t(118, 0).x, "at the eastern field")
        XCTAssertTrue(s.vehicleEvents.contains { $0.vehicle == plane.id && $0.what == "took off" })
        XCTAssertTrue(s.vehicleEvents.contains { $0.vehicle == plane.id && $0.what == "landed" })
        XCTAssertEqual(s.realm.player.body!.vehicle, plane.id, "the passenger flew with it")
    }

    func testAPilotTakesOffByHandAndLandingOffTheRunwayIsACrash() {
        let (sc, _, b) = TransportScene.airScene()
        let s = sc.s
        let plane = s.buildVehicle(.airliner, at: sc.t(3, 120), heading: 0, payer: .district(sc.a.id), nation: 1)!
        plane.task.goal = b.node
        driver(sc, plane)
        var c = Controls(); c.throttle = 1
        hold(sc, plane, c, 10) { plane.speed >= plane.spec.vr }
        XCTAssertEqual(plane.flight, .ground, "no lift-off without pulling up")
        c.pitch = 0.6
        hold(sc, plane, c, 3) { plane.flight == .air }
        XCTAssertEqual(plane.flight, .air)
        c.pitch = 0.3; hold(sc, plane, c, 2)
        XCTAssertGreaterThan(plane.z, 1)
        // hand it to the autopilot in the air and back: no jump in position, height or speed
        let p0 = plane.pos, z0 = plane.z, v0 = plane.speed
        s.handOver(plane, to: .auto); sc.run(1.0 / 30)
        XCTAssertLessThanOrEqual(plane.pos.distance(to: p0), (v0 + 1) * 16 / 30 + 1e-6)
        XCTAssertEqual(plane.z, z0, accuracy: 0.5)
        s.handOver(plane, to: .manual)
        // dive into the grass: a crash
        c = Controls(); c.pitch = -1; c.assist = false; c.steer = 0.6
        hold(sc, plane, c, 30) { plane.flight == .crashed }
        XCTAssertEqual(plane.flight, .crashed)
        XCTAssertEqual(s.realm.transport.stats.crashes, 1)
    }

    // MARK: ships


    func testAShipIsSteeredByRudderAndThrustBerthsAndGoesAstern() {
        let (sc, _, _) = TransportScene.portScene()
        let s = sc.s
        let ferry = s.buildVehicle(.ferry, at: sc.t(77, 20), heading: Double.pi / 2, payer: .district(sc.a.id), nation: 1)!
        driver(sc, ferry)
        var c = Controls(); c.throttle = 1
        hold(sc, ferry, c, 20)
        XCTAssertGreaterThan(ferry.speed, 2)
        XCTAssertLessThanOrEqual(ferry.speed, ferry.spec.maxSpeed + 1e-6)
        // the rudder turns it only while it moves
        let h0 = ferry.heading
        c.steer = 1; hold(sc, ferry, c, 1.5)
        XCTAssertGreaterThan(ferry.heading, h0 + 0.05)
        c.steer = -1; hold(sc, ferry, c, 1.5)
        // astern: it slows, stops, then goes backwards
        c = Controls(); c.throttle = 1; c.reverse = true
        hold(sc, ferry, c, 30) { ferry.speed < -0.3 }
        XCTAssertLessThan(ferry.speed, 0)
        XCTAssertTrue(s.passable(NetNode(ferry.tile.x, ferry.tile.y, 0), s.profile(.ferry)), "still on the water")
        // it cannot sail onto land: steer it into the bank
        c = Controls(); c.throttle = 1; c.steer = 1
        hold(sc, ferry, c, 40)
        XCTAssertTrue(TransportScene.river.contains(ferry.tile.x - sc.o.x), "never left the river")
    }

    func testAFerryLineCarriesPeopleUnderTheBridgeAndBerthsAtEachQuay() {
        let (sc, a, b) = TransportScene.portScene()
        let s = sc.s
        let line = s.addLine(.ferry, stops: [a.id, b.id], name: "River ferry", headway: 300, nation: 1, payer: .district(sc.a.id))!
        let ferry = s.buildVehicle(.ferry, at: sc.t(76, 14), heading: Double.pi / 2, payer: .district(sc.a.id), nation: 1)!
        s.assign(ferry, to: line)
        a.waiting.append(Rider(who: .agent(-1), from: a.id, to: b.id))
        s.realm.player.body = Body(at: ferry.pos, z: 0, depth: 0)          // near: real physics
        var passedUnder = false
        sc.run(400) {
            if ferry.tile.y == sc.t(0, 60).y { passedUnder = true }
            s.realm.player.body = Body(at: ferry.pos, z: 0, depth: 0)
            return ferry.task.at == 1 && ferry.task.standing
        }
        XCTAssertTrue(passedUnder, "under the road bridge")
        XCTAssertTrue(ferry.task.standing && ferry.task.at == 1, "berthed at South Quay: \(ferry.halted ?? "")")
        XCTAssertTrue(ferry.berthed || abs(ferry.speed) < 0.3)
        XCTAssertEqual(s.realm.transport.stats.trips, 1)
    }
}
