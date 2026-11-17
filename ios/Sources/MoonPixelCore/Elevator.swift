import Foundation

// Outside elevators: a shaft up the wall of a building, a car that really moves in it, doors that open
// only where the car stands, people and goods that are in the car (and nowhere else) while it moves.
//
// One elevator is one object in the realm (`realm.liftBox`). The car's height, speed, doors, riders,
// cargo and jobs are its own and are saved with it, in the same snapshot as everyone it carries.
// A standing tower with a real elevator gets its food up by that elevator only: the regional estimate of
// what its lifts could carry is not used for it while it stands (see `Civ.towersDay`).

public enum LiftState: String, Codable, Equatable { case idle, closing, moving, opening, open, overload, noPower, trapped }

public struct LiftStop: Codable, Equatable {
    public var level: Int                 // 0 the ground, n storey n
    public var z: Double                  // height of the car floor here
    public var door: TilePos              // the landing tile in front of the doors
    public var depth: Int { level == 0 ? 0 : OpenWorld.storeyBase + level }
}

/// Where a job takes goods from or to.
public enum LiftPlace: Codable, Equatable {
    case town(Int)                        // a town's store (Settlement id)
    case towerFloor(Int, Int)             // a standing tower's floor: tower id, level (its pantry, by nutrition)
}

public struct LiftJob: Codable, Equatable {
    public enum Stage: String, Codable { case waiting, loaded, done, cancelled }
    public var id = 0
    public var key = "food", amount = 0.0
    public var from = 0, to = 0           // stop indexes
    public var source: LiftPlace, dest: LiftPlace
    public var stage = Stage.waiting
    public var carried = 0.0              // units in the car now
    public var delivered = 0.0
}

public struct LiftRide: Codable, Equatable {
    public var who = 0                    // agent id (the player rides by standing in the car: see Motion)
    public var from = 0, to = 0
    public var aboard = false
}

public final class Elevator: Codable {
    public var id = 0, nation = 0
    public var town = 0                   // the town it stands in
    public var tower: Int?                // the standing tower it serves, if any
    /// The shaft: x, y of its north-west tile, w x d tiles (outside the wall).
    public var x = 0, y = 0, w = 2, d = 2
    public var stops: [LiftStop] = []
    public var z = 0.0, v = 0.0
    public var state = LiftState.idle
    public var door = 0.0                 // 0 shut ... 1 open
    public var at: Int?                   // stop the car stands at (doors may open only here)
    public var target: Int?
    public var dwell = 0.0
    public var calls: [Int: Double] = [:] // stop -> when it was called (the oldest is served first past the wait limit)
    public var rides: [LiftRide] = []
    public var jobs: [LiftJob] = []
    public var nextJob = 1
    public var battery = 120.0            // seconds of emergency power
    public var playerAboard = false
    /// Something stands in the doorway this step (set by whoever knows: the scene, the riders' update).
    public var blocked = false
    public init() {}
}

public struct LiftConfig: Codable, Equatable {
    public var maxSpeed = 3.0             // tiles a second
    public var accel = 1.5
    public var doorTime = 1.2             // seconds to open or shut
    public var dwell = 3.0
    public var capacity = 1200.0          // load
    public var personLoad = 80.0, unitLoad = 1.0
    public var waitLimit = 45.0           // a call this old is served before any other
    public var emergencySpeed = 0.6
    public var batteryFull = 120.0
    public var draw = 2.0                 // power a day per car (regional units)
    public var costPerStop: [String: Double] = ["iron": 2, "parts": 1, "planks": 4]
    public var costBase: [String: Double] = ["iron": 6, "parts": 4, "planks": 10]
    public init() {}
}

extension Realm {
    public var lifts: [Elevator] { get { liftBox ?? [] } set { liftBox = newValue.isEmpty ? nil : newValue } }
}

extension Elevator {
    public var load: Double { let c = LiftConfig(); return Double(rides.filter { $0.aboard }.count + (playerAboard ? 1 : 0)) * c.personLoad + jobs.reduce(0) { $0 + $1.carried } * c.unitLoad }
    public var docked: Bool { at != nil && v == 0 && abs(z - stops[at!].z) < 1e-9 }
    /// The doors at this stop are open (enough to pass).
    public func open(at k: Int) -> Bool { docked && at == k && door >= 0.95 }
    public var minX: Double { Double(x * 16) }
    public var minY: Double { Double(y * 16) }
    public var maxX: Double { Double((x + w) * 16) - 0.001 }
    public var maxY: Double { Double((y + d) * 16) - 0.001 }
    /// The car as a moving floor for `Motion`.
    public var platform: Platform {
        Platform(id: id, minX: minX, minY: minY, maxX: maxX, maxY: maxY, floorZ: z, vz: v, open: at.map { open(at: $0) } ?? false, stopDepth: at.map { stops[$0].depth })
    }
    public func call(_ k: Int, at t: Double) { if calls[k] == nil, k >= 0, k < stops.count { calls[k] = t } }
}

extension Society {
    public var liftCfg: LiftConfig { LiftConfig() }

    // MARK: building one

    public struct LiftPlan { public var ok = false; public var reason = ""; public var stops: [LiftStop] = []; public var cost: [String: Double] = [:] }

    /// An elevator up the outside of a building: the shaft's tiles (w x d at x, y) must be free on the ground
    /// and on every storey it serves, and each served level must have floor at the landing tile beside it.
    /// Levels are those of `levels` that pass; at least two are needed.
    public func planLift(x: Int, y: Int, w: Int = 2, d: Int = 2, levels: [Int], landingSide: TilePos) -> LiftPlan {
        var p = LiftPlan()
        let g = WorldGround(self)
        for lv in levels.sorted() {
            let depth = lv == 0 ? 0 : OpenWorld.storeyBase + lv
            let lw = layer(depth)
            var free = true
            for yy in y..<(y + d) { for xx in x..<(x + w) where lv == 0 ? lw.blocked(xx, yy) : (lw.tile(2, xx, yy) != 0 || lw.tile(0, xx, yy) != 0) { free = false } }
            if !free { p.reason = "shaft blocked on level \(lv)"; return p }
            let door = TilePos(x + (landingSide.x > 0 ? w : (landingSide.x < 0 ? -1 : 0)), y + (landingSide.y > 0 ? d : (landingSide.y < 0 ? -1 : 0)))
            guard let f = g.floor(depth, door), !(lv == 0 && lw.blocked(door.x, door.y)) else { continue }
            p.stops.append(LiftStop(level: lv, z: f, door: door))
        }
        if p.stops.count < 2 { p.reason = "fewer than two landings"; return p }
        var cost = liftCfg.costBase
        for (k, v) in liftCfg.costPerStop { cost[k, default: 0] += v * Double(p.stops.count) }
        p.cost = cost
        p.ok = true
        return p
    }

    /// Build it: paid once, from the pack. Returns the new elevator's id.
    @discardableResult public func buildLift(_ plan: LiftPlan, x: Int, y: Int, w: Int = 2, d: Int = 2, town: Int, tower: Int?, planID: Int) -> Int? {
        guard plan.ok else { return nil }
        if (realm.player.plans ?? []).contains(planID) { return nil }
        if Goods.take(plan.cost, from: pack) != nil { return nil }
        realm.player.plans = (realm.player.plans ?? []) + [planID]
        let e = Elevator()
        e.id = (realm.lifts.map { $0.id }.max() ?? 0) + 1
        e.x = x; e.y = y; e.w = w; e.d = d; e.town = town; e.tower = tower
        e.nation = settlements[town]?.nation ?? 0
        e.stops = plan.stops
        e.z = plan.stops[0].z; e.at = 0; e.state = .idle; e.battery = liftCfg.batteryFull
        // a door in the wall beside each landing
        for s in plan.stops {
            let lw = layer(s.depth)
            let side = [TilePos(1, 0), TilePos(-1, 0), TilePos(0, 1), TilePos(0, -1)].map { TilePos(s.door.x + $0.x, s.door.y + $0.y) }
            for t in side where !(t.x >= x && t.x < x + w && t.y >= y && t.y < y + d) {
                if let k = content.tile(lw.tile(2, t.x, t.y))?.key, k.hasPrefix("wall") { lw.setTile(2, t.x, t.y, content.tid("door_wood")); break }
            }
        }
        realm.lifts = realm.lifts + [e]
        emit("lift_built", ["\(plan.stops.count)"], TilePos(x, y).center)
        return e.id
    }

    public func lift(_ id: Int) -> Elevator? { realm.lifts.first { $0.id == id } }

    /// Power for a car: the regional city its town stands for has spare power, or a generator (a machine)
    /// stands within six tiles of its ground landing.
    public func liftPowered(_ e: Elevator) -> Bool {
        if let s = settlements[e.town], let cid = s.fromCiv, let c = realm.civBox?.cities[cid], c.energyMade - c.energyUsed >= liftCfg.draw { return true }
        guard let g = e.stops.first else { return false }
        let m = content.tid("machine")
        for dy in -6...6 { for dx in -6...6 where world.tile(2, g.door.x + dx, g.door.y + dy) == m { return true } }
        return false
    }

    // MARK: running

    /// Every elevator, a step of real or game time. `powered` overrides the power check (tests, laws).
    public func liftsStep(_ dt: Double, powered: ((Elevator) -> Bool)? = nil) {
        for e in realm.lifts.sorted(by: { $0.id < $1.id }) { liftStep(e, dt, powered: powered?(e) ?? liftPowered(e)) }
    }

    func liftStep(_ e: Elevator, _ dt: Double, powered: Bool) {
        let cfg = liftCfg
        e.rides.removeAll { agents[$0.who] == nil }           // someone who is gone rides no more
        if powered { e.battery = min(cfg.batteryFull, e.battery + dt * 2) }
        // jobs make their own calls
        for j in e.jobs where j.stage == .waiting { e.call(j.from, at: world.time) }
        for j in e.jobs where j.stage == .loaded { e.call(j.to, at: world.time) }
        for r in e.rides { e.call(r.aboard ? r.to : r.from, at: world.time) }
        if !powered {
            switch e.state {
            case .moving:
                // brakes; on emergency power it creeps to the nearest landing in the way it was going and opens
                if e.battery > 0 {
                    let dir: Double = e.v >= 0 ? 1 : -1
                    let next = e.stops.indices.filter { dir > 0 ? e.stops[$0].z >= e.z - 1e-9 : e.stops[$0].z <= e.z + 1e-9 }
                        .min { abs(e.stops[$0].z - e.z) < abs(e.stops[$1].z - e.z) }
                    if let k = next {
                        e.battery -= dt
                        let dz = e.stops[k].z - e.z, stepZ = cfg.emergencySpeed * dt
                        if abs(dz) <= stepZ { arrive(e, k) } else { e.v = (dz > 0 ? 1 : -1) * cfg.emergencySpeed; e.z += e.v * dt }
                        return
                    }
                }
                e.v = 0; e.state = .trapped; e.target = nil
                return
            case .trapped: e.v = 0; return
            case .open, .opening, .idle, .closing, .overload, .noPower:
                if e.docked { e.state = .noPower; e.door = min(1, e.door + dt / cfg.doorTime); serveStop(e) }     // standing at a landing: the doors let people out
                else { e.state = .trapped; e.v = 0 }
                return
            }
        }
        switch e.state {
        case .noPower, .trapped:
            e.state = e.docked ? .open : .moving
            if !e.docked && e.target == nil { e.target = nearest(e) }
            e.dwell = cfg.dwell
        case .opening:
            e.door = min(1, e.door + dt / cfg.doorTime)
            if e.door >= 1 { e.state = .open; e.dwell = cfg.dwell; serveStop(e) }
        case .open:
            serveStop(e)
            e.dwell -= dt
            if e.dwell <= 0 && !e.blocked && (!e.calls.isEmpty || e.jobs.contains { $0.stage == .loaded || $0.stage == .waiting } || e.rides.contains { $0.aboard }) { e.state = .closing }
            else if e.dwell <= 0 && e.calls.isEmpty { e.state = .idle }
        case .closing:
            if e.blocked { e.state = .opening; break }                         // something in the doorway: open again, never shut on it
            e.door = max(0, e.door - dt / cfg.doorTime)
            if e.door <= 0 {
                if e.load > cfg.capacity + 1e-9 { e.state = .overload; break }
                if let k = pick(e) { e.target = k; e.state = .moving; e.at = nil } else { e.state = .idle }
            }
        case .overload:
            e.door = min(1, e.door + dt / cfg.doorTime)
            if e.load <= cfg.capacity + 1e-9 { e.state = .open; e.dwell = cfg.dwell }
        case .idle:
            if e.docked, let k = e.at, e.calls[k] != nil { e.state = .opening; e.calls[k] = nil; break }
            if pick(e) != nil { e.state = e.door > 0 ? .closing : .closing }
        case .moving:
            guard let k = e.target else { e.state = .idle; break }
            let dz = e.stops[k].z - e.z
            let dir: Double = dz >= 0 ? 1 : -1
            // speed for a stop exactly there: never faster than the brakes allow
            let stopSpeed = (2 * cfg.accel * abs(dz)).squareRoot()
            let want = dir * min(cfg.maxSpeed, stopSpeed)
            let dv = max(-cfg.accel * dt, min(cfg.accel * dt, want - e.v))
            e.v += dv
            let step = e.v * dt
            if abs(dz) <= abs(step) || abs(dz) < 1e-6 { arrive(e, k) } else { e.z += step }
        }
        e.blocked = false
    }

    func arrive(_ e: Elevator, _ k: Int) {
        e.z = e.stops[k].z; e.v = 0; e.at = k; e.target = nil
        e.calls[k] = nil
        e.state = .opening
    }

    /// The nearest landing to where the car is.
    func nearest(_ e: Elevator) -> Int? { e.stops.indices.min { abs(e.stops[$0].z - e.z) < abs(e.stops[$1].z - e.z) } }

    /// Which call next: one waiting past the limit (oldest first) before anything else; otherwise the nearest.
    func pick(_ e: Elevator) -> Int? {
        let calls = e.calls.filter { $0.key != e.at || !e.docked }
        guard !calls.isEmpty else { return nil }
        if let late = calls.filter({ world.time - $0.value >= liftCfg.waitLimit }).min(by: { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }) { return late.key }
        return calls.keys.min { let a = abs(e.stops[$0].z - e.z), b = abs(e.stops[$1].z - e.z); return a != b ? a < b : $0 < $1 }
    }

    // MARK: people and goods at a landing

    /// At an open landing: riders for here get out, riders waiting here get in (as capacity allows),
    /// goods for here are unloaded into their store, goods waiting here are loaded.
    func serveStop(_ e: Elevator) {
        guard let k = e.at, e.docked, e.door >= 0.95 else { return }
        let cfg = liftCfg
        for i in e.rides.indices where e.rides[i].aboard && e.rides[i].to == k {
            e.rides[i].aboard = false
            if let a = agents[e.rides[i].who] { a.pos = e.stops[k].door.center }
            e.rides[i].who = -e.rides[i].who - 1                       // marked done
        }
        e.rides.removeAll { $0.who < 0 }
        for i in e.rides.indices where !e.rides[i].aboard && e.rides[i].from == k && e.load + cfg.personLoad <= cfg.capacity {
            e.rides[i].aboard = true
        }
        for i in e.jobs.indices {
            if e.jobs[i].stage == .loaded && e.jobs[i].to == k {
                put(e.jobs[i].key, e.jobs[i].carried, into: e.jobs[i].dest)
                e.jobs[i].delivered += e.jobs[i].carried; e.jobs[i].carried = 0
                e.jobs[i].stage = e.jobs[i].delivered + 1e-9 >= e.jobs[i].amount ? .done : .waiting
            }
            if e.jobs[i].stage == .waiting && e.jobs[i].from == k {
                let room = max(0, (cfg.capacity - e.load) / cfg.unitLoad)
                let want = min(e.jobs[i].amount - e.jobs[i].delivered, room)
                let got = take(e.jobs[i].key, want, from: e.jobs[i].source)
                if got > 0 { e.jobs[i].carried = got; e.jobs[i].stage = .loaded }
                else if available(e.jobs[i].key, e.jobs[i].source) <= 0 { e.jobs[i].stage = .cancelled }
            }
        }
        e.jobs.removeAll { $0.stage == .done || $0.stage == .cancelled }
    }

    func available(_ key: String, _ p: LiftPlace) -> Double {
        switch p {
        case .town(let id): return settlements[id]?.good(key) ?? 0
        case .towerFloor: return 0
        }
    }

    func take(_ key: String, _ n: Double, from p: LiftPlace) -> Double {
        guard n > 0 else { return 0 }
        switch p {
        case .town(let id):
            guard let s = settlements[id] else { return 0 }
            let got = min(n, s.good(key))
            if got > 0 { s.addGood(key, -got) }
            return got
        case .towerFloor: return 0
        }
    }

    /// Goods arriving: into a town's store, or into a tower floor's pantry (as nutrition: what goes up a
    /// tower is eaten up there, as in the regional rules).
    func put(_ key: String, _ n: Double, into p: LiftPlace) {
        guard n > 0 else { return }
        switch p {
        case .town(let id): settlements[id]?.addGood(key, n)
        case .towerFloor(let tid, let level):
            guard let c = realm.civBox, let t = c.towerIndex.towers[tid], level < t.floors.count else { return }
            let nut = key == "food" ? 1.0 : (key == "meal" ? 1.5 : 0)
            t.floors[level].food += n * nut
        }
    }

    /// Send goods from one landing's store to another by this elevator. Returns the job id.
    @discardableResult public func sendByLift(_ e: Elevator, key: String, amount: Double, from: Int, to: Int, source: LiftPlace, dest: LiftPlace) -> Int {
        let j = LiftJob(id: e.nextJob, key: key, amount: amount, from: from, to: to, source: source, dest: dest)
        e.nextJob += 1
        e.jobs.append(j)
        return j.id
    }

    /// A resident rides from one landing to another: waits at the first, is in the car (and nowhere
    /// else) on the way, and steps out at the second.
    public func ride(_ e: Elevator, agent: Int, from: Int, to: Int) {
        guard agents[agent] != nil, !e.rides.contains(where: { $0.who == agent }) else { return }
        e.rides.append(LiftRide(who: agent, from: from, to: to, aboard: false))
    }

    /// Food for the floors of a standing tower that has its own elevators: each day, what every floor
    /// needs is sent up from the town's store, by those elevators and nothing else.
    func supplyTowers() {
        guard let c = realm.civBox else { return }
        for e in realm.lifts.sorted(by: { $0.id < $1.id }) {
            guard let tid = e.tower, let t = c.towerIndex.towers[tid], let s = settlements[e.town], !s.abandoned else { continue }
            for (k, stop) in e.stops.enumerated() where stop.level > 0 && stop.level < t.floors.count {
                let f = t.floors[stop.level]
                guard f.people.total > 0 else { continue }
                var need = 0.0
                for b in 0..<3 { need += Double(f.people.band(b)) * c.cfg.need[b] }
                let pending = e.jobs.filter { $0.dest == .towerFloor(tid, stop.level) }.reduce(0.0) { $0 + $1.amount - $1.delivered }
                let want = max(0, need * 1.5 - f.food - pending)
                if want > 0.5 { sendByLift(e, key: "food", amount: want, from: 0, to: k, source: .town(e.town), dest: .towerFloor(tid, stop.level)) }
            }
        }
    }

    /// Towers whose food goes up by real elevators while they stand (the regional estimate leaves them alone).
    public var liftServedTowers: Set<Int> { Set(realm.lifts.compactMap { $0.tower }) }

    // MARK: when things are taken away

    /// A landing whose floor is gone (fallen, taken down, a law): the stop is closed; goods on their way
    /// there go back to where they came from; riders bound for it get out at the next stop instead.
    func closeStop(_ e: Elevator, _ k: Int) {
        guard k < e.stops.count else { return }
        for i in e.jobs.indices where e.jobs[i].to == k || e.jobs[i].from == k {
            if e.jobs[i].carried > 0 { put(e.jobs[i].key, e.jobs[i].carried, into: e.jobs[i].source); e.jobs[i].carried = 0 }
            e.jobs[i].stage = .cancelled
        }
        e.jobs.removeAll { $0.stage == .cancelled }
        e.rides.removeAll { !$0.aboard && $0.from == k }
        e.stops.remove(at: k)
        func shift(_ i: Int) -> Int { i > k ? i - 1 : i }
        for i in e.rides.indices { e.rides[i].from = shift(e.rides[i].from); e.rides[i].to = e.rides[i].to == k ? max(0, k - 1) : shift(e.rides[i].to) }
        for i in e.jobs.indices { e.jobs[i].from = shift(e.jobs[i].from); e.jobs[i].to = shift(e.jobs[i].to) }
        var calls: [Int: Double] = [:]; for (c, t) in e.calls where c != k { calls[shift(c)] = t }; e.calls = calls
        if let a = e.at { e.at = a == k ? nil : shift(a) }
        if let tg = e.target { e.target = tg == k ? nil : shift(tg) }
        if e.at == nil && e.state != .moving { e.state = .moving; e.target = nearest(e) }
    }

    /// The whole elevator is gone (taken down, wrecked, a law). Goods in the car go back to their source;
    /// riders step out at the nearest landing; the player, if aboard, is put on that landing's floor.
    /// Returns where the player was put, if they were aboard.
    @discardableResult public func removeLift(_ id: Int) -> Vec2? {
        guard let e = lift(id) else { return nil }
        let k = nearest(e) ?? 0
        let landing = e.stops.isEmpty ? TilePos(e.x - 1, e.y).center : e.stops[k].door.center
        for j in e.jobs where j.carried > 0 { put(j.key, j.carried, into: j.source) }
        for r in e.rides where r.aboard { agents[r.who]?.pos = landing }
        realm.lifts = realm.lifts.filter { $0.id != id }
        return e.playerAboard ? landing : nil
    }

    /// After building or demolition on a level: landings with no floor any more are closed; an elevator
    /// left with fewer than two is taken away.
    func checkLifts() {
        let g = WorldGround(self)
        for e in realm.lifts.sorted(by: { $0.id < $1.id }) {
            var k = e.stops.count - 1
            while k >= 0 { if g.floor(e.stops[k].depth, e.stops[k].door) == nil { closeStop(e, k) }; k -= 1 }
            if e.stops.count < 2 { removeLift(e.id) }
        }
    }

    /// Everything carried by elevators now, by key (for checks: it is in no store while it is in a car).
    public func inLifts() -> [String: Double] {
        var out: [String: Double] = [:]
        for e in realm.lifts { for j in e.jobs where j.carried > 0 { out[j.key, default: 0] += j.carried } }
        return out
    }
}
