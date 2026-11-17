import Foundation

// The transport clock (every step of the society), and the traveller in vehicles: getting in to drive or
// to ride, walking about inside one while it moves, getting out.

extension Society {
    func transportTick(_ dt: Double) {
        let tr = realm.transport
        workT += dt
        if workT >= 1 { workSites(hours: workT / Society.hour); workT = 0 }
        vehiclesStep(dt)
        syncAboard()
        linesStep(dt)
        transferYards()
        commutersStep(dt)
        trafficT += dt
        if trafficT >= 1 { countTraffic(); trafficT = 0 }
        let day = Int(world.time / MP.daySeconds)
        if tr.day < 0 { tr.day = day } else if day > tr.day { tr.day = day; transportDay() }
    }

    /// Once a day: the districts live their day, lines and ways are paid for, power drawn by trains is booked.
    public func transportDay() {
        districtsDay()
        for l in net.lines {
            // crews and stations: a line costs its owner money each day for each vehicle
            let cost = Double(l.vehicles.count) * (l.mode == .air ? 40 : (l.mode == .rail ? 25 : 8))
            if case .district(let id) = l.payer, let d = net.district(id) { d.money -= cost }
            l.costs += cost
        }
        // the ways a district built: their upkeep in parts (unpaid upkeep shows as a debt in the district's notes)
        for s in net.sites where s.finished != nil {
            guard case .district(let id) = s.payer, let d = net.district(id) else { continue }
            let parts = s.cells.reduce(0.0) { $0 + $1.kind.upkeep }
            let got = min(parts, d.store["parts"] ?? 0)
            d.add("parts", -got)
            realm.transport.stats.upkeep += got
            if got + 1e-9 < parts { d.money -= (parts - got) * 20 }
        }
        for d in net.districts { d.trainDraw = 0 }
    }

    // MARK: the traveller and vehicles

    /// The vehicle the traveller is in, if any.
    public var playerVehicle: Vehicle? { realm.player.body?.vehicle.flatMap { net.vehicle($0) } }

    /// Vehicles close enough to get into (standing still, or a ship at its berth).
    public func vehiclesNear(_ p: Vec2, reach: Double = 2.5) -> [Vehicle] {
        net.vehicles.filter { $0.pos.distance(to: p) <= ($0.spec.length / 2 + reach) * 16 }.sorted { $0.pos.distance(to: p) < $1.pos.distance(to: p) }
    }

    /// Get in: to drive (the traveller takes the wheel; the autopilot lets go) or to ride. Only when the
    /// vehicle stands still and the traveller stands beside it on its level. Returns why not, or nil.
    @discardableResult public func board(_ id: Int, drive: Bool) -> String? {
        guard var b = realm.player.body, b.vehicle == nil, let v = net.vehicle(id) else { return "nothing to board" }
        guard v.stopped || v.berthed else { return "it is moving" }
        guard v.pos.distance(to: b.pos) <= (v.spec.length / 2 + 2.5) * 16 else { return "too far" }
        if v.kind.mode == .water && !v.berthed && !quayBeside(Motion.tile(b.x, b.y)) && waterDepth(Motion.tile(b.x, b.y)) == 0 && !quayBeside(v.tile) { return "not at a berth" }
        if drive {
            guard !v.playerDriving else { return "someone drives" }
            guard v.nation == 0 || v.nation == realm.player.nation || realm.player.god == true else { return "not yours to drive" }
        } else if v.seatsFree <= 0 { return "full" }
        b.vehicle = v.id
        b.lx = 0; b.ly = 0; b.lz = 0
        b.seat = drive ? 0 : nil
        b.vx = 0; b.vy = 0; b.vz = 0; b.state = .riding; b.platform = nil
        v.playerAboard = true
        if drive { v.playerDriving = true; setControl(v, .manual); v.input = Controls() }
        let w = v.world(0, 0)
        b.x = w.x; b.y = w.y; b.depth = 0; b.z = floorZ(v)
        realm.player.body = b
        return nil
    }

    /// Hand the controls to the autopilot (or take them back) without getting out. Position, speed, people,
    /// goods and job stay exactly as they are.
    public func handOver(_ v: Vehicle, to c: Control) {
        setControl(v, c)
        if c == .auto { v.input.reverse = false }
    }

    /// Get out: only when the vehicle stands (a ship at a berth or a quay beside it, a plane on the ground),
    /// onto free ground next to it. Returns why not, or nil.
    @discardableResult public func leaveVehicle() -> String? {
        guard var b = realm.player.body, let v = playerVehicle else { return "not in a vehicle" }
        guard v.stopped, v.flight != .air else { return "it is moving" }
        // the nearest free tile beside it
        var spot: TilePos?
        let sides: [(Double, Double)] = [(0, v.spec.deckW / 2 + 0.7), (0, -(v.spec.deckW / 2 + 0.7)), (v.spec.length / 2 + 0.7, 0), (-(v.spec.length / 2 + 0.7), 0)]
        for (f, r) in sides {
            let t = Motion.tile(v.world(f, r).x, v.world(f, r).y)
            if world.isLand(t.x, t.y) && !world.blocked(t.x, t.y) || content.bridge[Int(world.tile(1, t.x, t.y))] { spot = t; break }
        }
        if spot == nil, v.kind.mode == .water {
            for dy in -2...2 { for dx in -2...2 where spot == nil { let t = TilePos(v.tile.x + dx, v.tile.y + dy); if wayKind(at: t) == .quay { spot = t } } }
        }
        guard let t = spot else { return "nowhere to step out" }
        v.playerAboard = false
        if v.playerDriving { v.playerDriving = false; v.input = Controls(); v.input.brake = 1 }
        b.vehicle = nil; b.lx = nil; b.ly = nil; b.lz = nil; b.seat = nil
        b.x = t.center.x; b.y = t.center.y
        b.depth = 0
        b.z = WorldGround(self).floor(0, t) ?? 0
        b.state = .standing; b.vx = 0; b.vy = 0; b.vz = 0
        realm.player.body = b
        return nil
    }

    /// The traveller goes where the vehicle goes (seated, or standing where they stand inside it).
    func syncAboard() {
        guard var b = realm.player.body, let id = b.vehicle else { return }
        guard let v = net.vehicle(id) else {
            // the vehicle is gone: they are on the ground where it was
            b.vehicle = nil; b.lx = nil; b.ly = nil; b.lz = nil; b.seat = nil; b.state = .falling; realm.player.body = b; return
        }
        let w = v.world(b.lx ?? 0, b.ly ?? 0)
        b.x = w.x; b.y = w.y; b.z = floorZ(v) + (b.lz ?? 0)
        realm.player.body = b
    }

    /// The traveller's controls, when driving.
    public func steer(_ c: Controls) {
        guard let v = playerVehicle, v.playerDriving else { return }
        v.input = c
    }

    /// Height of a vehicle's floor (where people stand inside), in the 3D view's units.
    public func floorZ(_ v: Vehicle) -> Double {
        let g = Double(Terrain3D.groundY(world: world, at: v.tile.center))
        let water = waterDepth(v.tile) > 0 ? 0.0 : 0
        return g + water + v.z + v.spec.deckZ
    }

    /// The traveller inside a moving vehicle: walks and jumps on its floor (in the vehicle's own frame, so
    /// a turn or a stop carries them with it); a seated driver or passenger only moves with it.
    @discardableResult public func moveAboard(dt: Double, wish: Vec2, jump: Bool, cfg: MotionConfig = MotionConfig()) -> MotionStep {
        var out = MotionStep()
        guard var b = realm.player.body, let v = playerVehicle else { return out }
        var lx = b.lx ?? 0, ly = b.ly ?? 0, lz = b.lz ?? 0
        let c = cos(v.heading), s = sin(v.heading)
        // the stick in the vehicle's frame (tiles a second)
        let wf = (wish.x * c + wish.y * s) / 16, wr = (-wish.x * s + wish.y * c) / 16
        if jump && b.seat == nil && lz <= 1e-9 { b.vz = cfg.jumpSpeed; b.state = .rising }
        b.acc += min(dt, cfg.maxFrame)
        while b.acc >= cfg.substep - 1e-12 {
            b.acc -= cfg.substep
            let h = cfg.substep
            if b.seat == nil {
                lx = max(-v.spec.deckL / 2, min(v.spec.deckL / 2, lx + wf * h))
                ly = max(-v.spec.deckW / 2, min(v.spec.deckW / 2, ly + wr * h))
            }
            if lz > 0 || b.vz > 0 {
                b.vz -= cfg.gravity * h
                lz += b.vz * h
                if lz <= 0 { lz = 0; out.landed = true; out.impact = -b.vz; b.vz = 0; b.landings += 1 }
            }
            out.peak = max(out.peak, lz)
        }
        b.state = lz > 0 ? (b.vz > 0 ? .rising : .falling) : .riding
        let w = v.world(lx, ly)
        b.x = w.x; b.y = w.y; b.z = floorZ(v) + lz
        b.lx = lx; b.ly = ly; b.lz = lz
        realm.player.body = b
        return out
    }
}
