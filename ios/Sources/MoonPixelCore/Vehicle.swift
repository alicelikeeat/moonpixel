import Foundation

// Vehicles: cars, buses, lorries, trains, high-speed trains, airliners, cargo planes, ferries, liners and
// freighters. One vehicle is one object with one position, speed, fuel, load and job, whoever drives it.
//
// Control: the same physics moves a vehicle whether the player or the autopilot sets the controls. The
// autopilot only works the throttle, brake, wheel (rudder, stick) as a driver would; taking the controls
// over, or handing them back, changes who sets them and nothing else: position, speed, passengers,
// cargo and job are where they were (no teleport). A vehicle far from the traveller is not stepped by
// physics but moved along its planned way at the speed it would have (the same object: the same people
// and goods are in it, and it arrives at the same stops).
//
// Units: x, y in simulation units (16 a tile); speed in tiles a second; heading in radians (0 east,
// pi/2 south, the way y grows); z in tiles above the ground (a plane's height, a bridge deck's top).

public enum VehicleKind: String, Codable, CaseIterable {
    case car, bus, truck, train, hsr, airliner, cargoPlane, ferry, liner, freighter

    public var mode: TravelMode {
        switch self {
        case .car, .bus, .truck: return .road
        case .train, .hsr: return .rail
        case .airliner, .cargoPlane: return .air
        case .ferry, .liner, .freighter: return .water
        }
    }
    public var spec: VehicleSpec { VehicleSpec.table[self]! }
    public func name(zh: Bool) -> String {
        let n: [VehicleKind: (String, String)] = [.car: ("Car", "汽车"), .bus: ("Bus", "公交车"), .truck: ("Lorry", "货车"), .train: ("Train", "列车"), .hsr: ("High-speed train", "高铁"),
            .airliner: ("Airliner", "客机"), .cargoPlane: ("Cargo plane", "货机"), .ferry: ("Ferry", "渡轮"), .liner: ("Liner", "客轮"), .freighter: ("Freighter", "货轮")]
        return zh ? n[self]!.1 : n[self]!.0
    }
}

public enum Energy: String, Codable { case diesel, electric, jet, bunker
    /// The good a vehicle is filled with (electric: none, it draws from the grid).
    public var good: String? { self == .electric ? nil : "fuel" }
}

public struct VehicleSpec: Equatable {
    static let table: [VehicleKind: VehicleSpec] = Dictionary(uniqueKeysWithValues: VehicleKind.allCases.map { ($0, VehicleSpec.of($0)) })
    /// At most this many vehicles get full physics at once (the nearest to the traveller); the rest move along their way.
    public static let physicsCap = 40
    public var maxSpeed: Double, reverseMax: Double, accel: Double, brake: Double, emergency: Double
    public var wheelbase: Double, maxSteer: Double, radius: Double, length: Double
    public var seats: Int, cargo: Double
    public var energy: Energy, tank: Double, burn: Double         // fuel units per tile at full throttle (electric: power units)
    public var draft: Double, airDraft: Double
    public var vr: Double, stall: Double, cruise: Double          // planes
    public var deckW: Double, deckL: Double                       // the walkable inside, tiles
    public var deckZ: Double                                      // floor height inside above the wheels, tiles
    public var build: [String: Double]
    public var wearPerTile: Double

    public static func of(_ k: VehicleKind) -> VehicleSpec {
        switch k {
        case .car: return VehicleSpec(maxSpeed: 16, reverseMax: 3, accel: 3.5, brake: 8, emergency: 10, wheelbase: 0.5, maxSteer: 0.8, radius: 0.2, length: 1,
                                      seats: 4, cargo: 20, energy: .diesel, tank: 40, burn: 0.004, draft: 0, airDraft: 0.8, vr: 0, stall: 0, cruise: 0, deckW: 0.6, deckL: 0.8, deckZ: 0.3,
                                      build: ["iron": 4, "parts": 3], wearPerTile: 0.00002)
        case .bus: return VehicleSpec(maxSpeed: 12, reverseMax: 2, accel: 1.8, brake: 5, emergency: 7, wheelbase: 0.8, maxSteer: 0.8, radius: 0.24, length: 2.5,
                                      seats: 40, cargo: 0, energy: .diesel, tank: 150, burn: 0.012, draft: 0, airDraft: 1.6, vr: 0, stall: 0, cruise: 0, deckW: 0.8, deckL: 2.2, deckZ: 0.4,
                                      build: ["iron": 10, "parts": 8], wearPerTile: 0.00002)
        case .truck: return VehicleSpec(maxSpeed: 12, reverseMax: 2, accel: 1.5, brake: 4.5, emergency: 6, wheelbase: 0.8, maxSteer: 0.8, radius: 0.24, length: 2.5,
                                        seats: 2, cargo: 200, energy: .diesel, tank: 200, burn: 0.015, draft: 0, airDraft: 1.8, vr: 0, stall: 0, cruise: 0, deckW: 0.8, deckL: 2.2, deckZ: 0.5,
                                        build: ["iron": 10, "parts": 6], wearPerTile: 0.00003)
        case .train: return VehicleSpec(maxSpeed: 16, reverseMax: 0, accel: 0.6, brake: 1.2, emergency: 2.0, wheelbase: 0, maxSteer: 0, radius: 0.4, length: 8,
                                        seats: 300, cargo: 1200, energy: .diesel, tank: 2000, burn: 0.06, draft: 0, airDraft: 2.2, vr: 0, stall: 0, cruise: 0, deckW: 1.2, deckL: 7.5, deckZ: 0.6,
                                        build: ["iron": 40, "parts": 25, "planks": 10], wearPerTile: 0.00001)
        case .hsr: return VehicleSpec(maxSpeed: 40, reverseMax: 0, accel: 0.7, brake: 1.0, emergency: 1.8, wheelbase: 0, maxSteer: 0, radius: 0.4, length: 10,
                                      seats: 500, cargo: 0, energy: .electric, tank: 0, burn: 0.05, draft: 0, airDraft: 2.2, vr: 0, stall: 0, cruise: 0, deckW: 1.2, deckL: 9.5, deckZ: 0.6,
                                      build: ["iron": 60, "parts": 50, "moonsteel": 4], wearPerTile: 0.00001)
        case .airliner: return VehicleSpec(maxSpeed: 55, reverseMax: 1, accel: 10, brake: 10, emergency: 12, wheelbase: 1.5, maxSteer: 0.6, radius: 1.2, length: 5,
                                           seats: 180, cargo: 60, energy: .jet, tank: 3000, burn: 0.08, draft: 0, airDraft: 4, vr: 22, stall: 18, cruise: 40, deckW: 1, deckL: 4.5, deckZ: 1,
                                           build: ["iron": 60, "parts": 60, "moonsteel": 8], wearPerTile: 0.000005)
        case .cargoPlane: return VehicleSpec(maxSpeed: 50, reverseMax: 1, accel: 9, brake: 10, emergency: 12, wheelbase: 1.5, maxSteer: 0.6, radius: 1.2, length: 5,
                                             seats: 4, cargo: 600, energy: .jet, tank: 3200, burn: 0.09, draft: 0, airDraft: 4, vr: 23, stall: 19, cruise: 38, deckW: 1, deckL: 4.5, deckZ: 1,
                                             build: ["iron": 60, "parts": 60, "moonsteel": 8], wearPerTile: 0.000005)
        case .ferry: return VehicleSpec(maxSpeed: 5, reverseMax: 2, accel: 0.25, brake: 0.35, emergency: 0.5, wheelbase: 0, maxSteer: 1, radius: 0.6, length: 3,
                                        seats: 120, cargo: 150, energy: .bunker, tank: 600, burn: 0.03, draft: 1.5, airDraft: 2.5, vr: 0, stall: 0, cruise: 0, deckW: 1.4, deckL: 2.8, deckZ: 0.6,
                                        build: ["iron": 20, "planks": 30, "parts": 10], wearPerTile: 0.00001)
        case .liner: return VehicleSpec(maxSpeed: 6, reverseMax: 2, accel: 0.2, brake: 0.3, emergency: 0.45, wheelbase: 0, maxSteer: 1, radius: 0.8, length: 5,
                                        seats: 400, cargo: 100, energy: .bunker, tank: 1500, burn: 0.05, draft: 2.5, airDraft: 4, vr: 0, stall: 0, cruise: 0, deckW: 1.6, deckL: 4.6, deckZ: 1,
                                        build: ["iron": 50, "planks": 30, "parts": 30], wearPerTile: 0.00001)
        case .freighter: return VehicleSpec(maxSpeed: 4, reverseMax: 1.5, accel: 0.12, brake: 0.2, emergency: 0.3, wheelbase: 0, maxSteer: 1, radius: 0.8, length: 6,
                                            seats: 6, cargo: 3000, energy: .bunker, tank: 2500, burn: 0.07, draft: 4, airDraft: 5, vr: 0, stall: 0, cruise: 0, deckW: 1.6, deckL: 5.6, deckZ: 1,
                                            build: ["iron": 60, "planks": 20, "parts": 30], wearPerTile: 0.00001)
        }
    }
}

public enum Control: String, Codable { case auto, manual }

/// What a driver (the player, or the autopilot) asks of the vehicle this step.
public struct Controls: Codable, Equatable {
    public var throttle = 0.0            // 0...1 (ships: -1...1, astern below 0)
    public var brake = 0.0               // 0...1
    public var steer = 0.0               // -1 (left) ... 1 (right); rudder; plane: bank
    public var reverse = false           // cars and planes on the ground: the gear is in reverse
    public var pitch = 0.0               // planes: -1 nose down ... 1 nose up
    public var assist = true             // planes: hold height and heading, never below stall speed
    public init() {}
}

public enum Flight: String, Codable { case ground, air, crashed }

/// Who is aboard: a resident on a commute, a villager, or the traveller.
public enum RiderRef: Codable, Equatable, Hashable { case commuter(Int), agent(Int), player }

public struct Rider: Codable, Equatable {
    public var who: RiderRef
    public var from = 0, to = 0          // stop ids
    public var boarded = 0.0
    public init(who: RiderRef, from: Int, to: Int) { self.who = who; self.from = from; self.to = to }
}

/// A vehicle's job: a line it runs (stops in order, back and forth), or a single trip to a place.
public struct VehicleTask: Codable, Equatable {
    public var line: Int?
    public var at = 0                    // index of the stop it is going to (or standing at) on the line
    public var dir = 1
    public var dwell = 0.0
    public var standing = false          // at the stop with doors open
    public var due = 0.0                 // when it was due at that stop (timetable)
    public var goal: NetNode?            // a single trip: where to
    /// Aircraft: where in the flight it is (nil: at the stand; taxi, lineup, roll, air, final, landed, taxiIn).
    public var phase: String?
    public init() {}
}

public final class Vehicle: Codable {
    public var id = 0
    public var kind = VehicleKind.car
    public var nation = 0
    public var owner = Payer.pack        // who pays for its fuel and repairs
    public var name = ""
    public var x = 0.0, y = 0.0, z = 0.0
    public var heading = 0.0
    public var speed = 0.0               // tiles/s along the heading (negative: backwards)
    public var vz = 0.0
    public var level = 0
    public var control = Control.auto
    public var input = Controls()
    public var flight = Flight.ground
    public var fuel = 0.0
    public var wear = 0.0
    public var odometer = 0.0
    public var riders: [Rider] = []
    /// Goods aboard, by shipment (Lines.swift): the same goods are never both here and anywhere else.
    public var cargo: [Int: Double] = [:]
    public var task = VehicleTask()
    public var path: [NetNode] = []
    public var pathI = 0
    public var replan = false
    public var halted: String?           // why it stands still (no way, no fuel, no power, bridge gone, red signal...)
    public var playerAboard = false
    public var playerDriving = false
    public var berthed = false
    public var delay = 0.0               // seconds behind its timetable
    public var acc = 0.0                 // time not yet stepped
    public var lockWait = 0.0
    public var crashes = 0
    /// Tiles just passed (newest last): a train covers these behind its front.
    public var trail: [TilePos] = []
    /// The network revision its way was last planned on (a vehicle with no way tries again when the network changes).
    public var plannedRev = 0
    public init() {}

    public var spec: VehicleSpec { kind.spec }
    public var pos: Vec2 { Vec2(x, y) }
    public var tile: TilePos { Motion.tile(x, y) }
    public var node: NetNode { NetNode(tile.x, tile.y, level) }
    public var stopped: Bool { abs(speed) < 0.3 && (kind.mode != .air || flight == .ground) }
    public var load: Double { cargo.values.reduce(0, +) }
    public var seatsFree: Int { spec.seats - riders.count - (playerAboard && !playerDriving ? 1 : 0) }
    func place(at p: Vec2, level l: Int) { x = p.x; y = p.y; level = l }
    func halt(_ why: String) { halted = why }
    /// The point in the world of a spot inside (tiles from the middle, forward and to the right).
    public func world(_ fwd: Double, _ right: Double) -> Vec2 {
        let c = cos(heading), s = sin(heading)
        return Vec2(x + (fwd * c - right * s) * 16, y + (fwd * s + right * c) * 16)
    }
    /// A world point as forward/right tiles inside the vehicle.
    public func local(_ p: Vec2) -> (Double, Double) {
        let dx = (p.x - x) / 16, dy = (p.y - y) / 16, c = cos(heading), s = sin(heading)
        return (dx * c + dy * s, -dx * s + dy * c)
    }
}

/// A short record of something that happened to a vehicle (shown to the player and kept for tests).
public struct VehicleEvent: Codable, Equatable { public var t: Double; public var vehicle: Int; public var what: String }

extension Society {
    public var vehicleSubstep: Double { 1.0 / 60 }

    // MARK: making one

    /// Build a vehicle from materials at a place it can stand on. Nothing is made from nothing: the
    /// materials come from the payer and it starts with the fuel the payer can give (up to a full tank).
    @discardableResult public func buildVehicle(_ kind: VehicleKind, at t: TilePos, heading: Double = 0, payer: Payer, nation: Int = 0, level: Int = 0, fill: Bool = true) -> Vehicle? {
        let p = profile(kind)
        let n = NetNode(t.x, t.y, level)
        let standable = kind.mode == .air ? (wayKind(at: t)?.mode == .air) : (passable(n, p) || (kind.mode == .road && passableOffRoad(t, level)))
        guard standable, let h = holding(payer) else { return nil }
        // never made on top of another vehicle of the same element (it could not move off it)
        let here = t.center
        if realm.transportBox?.vehicles.contains(where: { $0.kind.mode == kind.mode && $0.level == level && $0.pos.distance(to: here) < ($0.spec.radius + kind.spec.radius + 0.3) * 16 + ($0.kind.mode == .rail ? $0.spec.length * 16 : 0) }) == true { return nil }
        if Goods.take(kind.spec.build, from: h) != nil { return nil }
        let tr = realm.transport
        record(kind.spec.build.map { ($0.key, $0.value) }, from: h.name, to: "vehicle works", note: "build \(kind.rawValue)")
        let v = Vehicle()
        v.id = tr.take(); v.kind = kind; v.nation = nation; v.owner = payer
        v.name = kind.name(zh: false) + " \(v.id)"
        v.place(at: t.center, level: level); v.heading = heading
        if level == 1, let b = bridge(at: t) { v.z = b.deckZ }
        if fill { refuel(v) }
        tr.vehicles.append(v)
        return v
    }

    /// Fill the tank from the owner's store (as much as there is): fuel is a real good, made and moved.
    @discardableResult public func refuel(_ v: Vehicle) -> Double {
        guard let g = v.spec.energy.good, let h = holding(v.owner) else { return 0 }
        let want = max(0, v.spec.tank - v.fuel)
        let got = min(want, h.free(g))
        if got > 0 { h.change(g, -got); v.fuel += got; record([(g, got)], from: h.name, to: "tank of \(v.id)", note: "refuel") }
        return got
    }

    /// Repair at a depot or terminus from the owner's parts.
    @discardableResult public func repair(_ v: Vehicle) -> Bool {
        guard v.wear > 0.05, let h = holding(v.owner) else { return false }
        let need = (v.wear * 10).rounded(.up)
        guard Goods.take([("parts", need)], from: h) == nil else { return false }
        record([("parts", need)], from: h.name, to: "repair of \(v.id)", note: "maintenance")
        v.wear = 0
        if v.halted == "broken down" { v.halted = nil }
        return true
    }

    public func profile(_ k: VehicleKind) -> Profile {
        Profile(mode: k.mode, draft: k.spec.draft, airDraft: k.spec.airDraft, hsrOnly: k == .hsr)
    }

    /// Off the road, a car may go slowly on open land (never into water, a wall or a tree).
    func passableOffRoad(_ t: TilePos, _ level: Int) -> Bool {
        level == 0 && world.isLand(t.x, t.y) && !world.blocked(t.x, t.y) && bridge(at: t).map { _ in waterDepth(t) == 0 } ?? true
    }

    // MARK: control

    /// Take the controls (the player) or hand them back (the autopilot). Nothing else changes.
    public func setControl(_ v: Vehicle, _ c: Control) {
        guard v.control != c else { return }
        v.control = c
        if c == .auto {
            v.replan = true                     // the autopilot finds its way from exactly where it is
            v.input.reverse = false
        }
    }

    // MARK: stepping

    /// Step every vehicle: those near the traveller by physics, the rest along their way.
    public func vehiclesStep(_ dt: Double) {
        let tr = realm.transport
        bridgesStep(dt)
        holdTrack()
        bucketVehicles()
        let me = realm.player.body.map { Vec2($0.x, $0.y) }
        // full physics for the vehicles nearest the traveller (and any driven by hand), within reach, up to the cap
        var close: Set<Int> = []
        if let p = me {
            let inReach = tr.vehicles.filter { $0.pos.distance(to: p) <= 96 * 16 }
            for v in inReach.sorted(by: { ($0.pos.distance(to: p), $0.id) < ($1.pos.distance(to: p), $1.id) }).prefix(VehicleSpec.physicsCap) { close.insert(v.id) }
        }
        for v in tr.vehicles.sorted(by: { $0.id < $1.id }) {
            if v.halted == "no way" && v.plannedRev != tr.revision && v.control == .auto { v.replan = true }
            let near = v.playerAboard || close.contains(v.id) || v.control == .manual
            if near { physics(v, dt) } else { farStep(v, dt) }
        }
    }

    /// Vehicles by 4 x 4 tile cell, for the checks between neighbours (never every pair).
    func bucketVehicles() {
        var b: [Int64: [Vehicle]] = [:]
        for v in realm.transport.vehicles { b[MP.chunkKey(v.tile.x >> 2, v.tile.y >> 2), default: []].append(v) }
        vehicleBuckets = b
    }

    /// Vehicles within about 8 tiles of a point (from the cells around it).
    func vehiclesAround(_ p: Vec2) -> [Vehicle] {
        let t = Motion.tile(p.x, p.y)
        var out: [Vehicle] = []
        for dy in -2...2 { for dx in -2...2 { if let l = vehicleBuckets[MP.chunkKey((t.x >> 2) + dx, (t.y >> 2) + dy)] { out += l } } }
        return out
    }

    /// Fixed substeps of real physics; the controls come from the driver (autopilot or player).
    func physics(_ v: Vehicle, _ dt: Double) {
        let h = vehicleSubstep
        v.acc += min(dt, 0.25)
        while v.acc >= h - 1e-12 {
            v.acc -= h
            if v.control == .auto { autopilot(v, h) }
            switch v.kind.mode {
            case .road: drive(v, h)
            case .rail: runTrain(v, h)
            case .air: fly(v, h)
            case .water: sail(v, h)
            case .foot: break
            }
        }
    }

    // --- shared: the engine and the tank
    /// Can the engine pull? Burns fuel (or draws power) for the work done; an empty tank or a dead grid
    /// gives no pull at all (the vehicle rolls to a stop on its brakes and drag).
    func engine(_ v: Vehicle, _ throttle: Double, _ dist: Double) -> Bool {
        if v.wear >= 1 { v.halted = "broken down"; return false }
        let need = v.spec.burn * abs(throttle) * dist + v.spec.burn * 0.02 * abs(throttle)
        if v.spec.energy == .electric {
            guard gridPower(for: v) else { v.halted = "no power"; return false }
            realm.transport.stats.powerUsed += need
            if case .district(let id) = v.owner { net.district(id)?.trainDraw += need }
            if v.halted == "no power" { v.halted = nil }
            return true
        }
        guard v.fuel > need || need == 0 else { v.fuel = 0; v.halted = "no fuel"; return false }
        v.fuel -= need
        realm.transport.stats.fuelBurnt += need
        if v.halted == "no fuel" { v.halted = nil }
        return true
    }

    /// Electric traction draws from the grid of the district the vehicle belongs to (or of the nearest
    /// district on the way); without spare power there is none.
    public func gridPower(for v: Vehicle) -> Bool {
        if case .district(let id) = v.owner, let d = net.district(id) { return d.spareGrid > 0 }
        return net.districts.contains { $0.nation == v.nation && $0.spareGrid > 0 }
    }

    // --- road vehicles
    func drive(_ v: Vehicle, _ h: Double) {
        let s = v.spec, c = v.input
        let dir: Double = c.reverse ? -1 : 1
        let pulling = c.throttle > 0 && engine(v, c.throttle, abs(v.speed) * h)
        var a = pulling ? dir * c.throttle * s.accel * (1 - abs(v.speed) / (c.reverse ? s.reverseMax : s.maxSpeed)) : 0
        if c.brake > 0 { a -= (v.speed > 0 ? 1 : (v.speed < 0 ? -1 : 0)) * c.brake * s.brake }
        a -= v.speed * 0.02                                                            // rolling and air
        var nv = v.speed + a * h
        if v.speed != 0 && nv * v.speed < 0 { nv = 0 }                                 // brakes stop, they do not reverse
        // off the road a vehicle is slow
        if wayKind(at: v.tile) == nil && v.level == 0 && bridge(at: v.tile) == nil { nv = max(-2, min(4, nv)) }
        v.speed = nv
        v.heading += v.speed / s.wheelbase * tan(c.steer * s.maxSteer) * h
        moveFlat(v, h)
    }

    /// Move along the heading by `speed`, through the world's tiles and levels; walls, water, trees, a
    /// closed bridge and other vehicles stop it.
    func moveFlat(_ v: Vehicle, _ h: Double) {
        let d = v.speed * h
        guard d != 0 else { return }
        let nx = v.x + cos(v.heading) * d * 16, ny = v.y + sin(v.heading) * d * 16
        let from = v.tile, to = Motion.tile(nx, ny)
        var level = v.level
        if to != from {
            guard let l = enter(v, from: from, to: to) else { bump(v); return }
            level = l
        }
        // other vehicles on the same level: never closer than both their sizes (moving apart is allowed)
        for o in vehiclesAround(v.pos) where o !== v && o.level == level && o.kind.mode == v.kind.mode && (o.kind.mode != .air || o.flight == v.flight) {
            let r = (o.spec.radius + v.spec.radius) * 16
            let dNow = o.pos.distance(to: v.pos), dNew = o.pos.distance(to: Vec2(nx, ny))
            if dNew < r && dNew < dNow { bump(v, other: o); return }
        }
        v.x = nx; v.y = ny
        if level != v.level { v.level = level; v.z = level == 1 ? (bridge(at: to)?.deckZ ?? 0) : 0 }
        v.odometer += abs(d)
        v.wear += abs(d) * v.spec.wearPerTile
    }

    /// The level a vehicle is on after stepping from one tile to the next, or nil if it cannot.
    func enter(_ v: Vehicle, from: TilePos, to: TilePos) -> Int? {
        let p = profile(v.kind)
        // onto or along a bridge deck
        if v.level == 1 {
            // along the deck (while it carries traffic), or down the ramp at an end, in line with the span
            if let b = bridge(at: from), b.cells.contains(to) { return b.carries && deckServes(b.deck, p) ? 1 : nil }
            if let b = bridge(at: from), b.ramps(from).contains(to) {
                return groundOK(v, to) ? 0 : nil
            }
            return nil                                                                  // the railing
        }
        if v.level == -1 {
            if let u = tunnel(at: from), u.cells.contains(to) { return 1 - 2 }
            if let u = tunnel(at: from), u.cells.first == from || u.cells.last == from { return groundOK(v, to) ? 0 : nil }
            return nil
        }
        if let b = bridge(at: to), b.ramps(to).contains(from) {
            // up the ramp only from the abutment (in line with the span)
            return passable(NetNode(to.x, to.y, 1), p) ? 1 : nil
        }
        if let u = tunnel(at: to), u.cells.first == to || u.cells.last == to {
            let inner = u.cells.count > 1 ? (u.cells.first == to ? u.cells[1] : u.cells[u.cells.count - 2]) : to
            if from == TilePos(2 * to.x - inner.x, 2 * to.y - inner.y) { return -1 }
        }
        return groundOK(v, to) && !rampSplits(from, to) ? 0 : nil
    }

    func groundOK(_ v: Vehicle, _ t: TilePos) -> Bool {
        let p = profile(v.kind)
        if passable(NetNode(t.x, t.y, 0), p) { return true }
        return v.kind.mode == .road && passableOffRoad(t, 0)
    }

    func bump(_ v: Vehicle, other: Vehicle? = nil) {
        let impact = abs(v.speed)
        if impact > 6 { v.crashes += 1; realm.transport.stats.crashes += 1; v.wear += impact * 0.01; event(v, "collision") }
        v.wear += impact * 0.002
        v.speed = 0
        if let o = other, impact > 6 { o.wear += impact * 0.005 }
    }

    // --- trains: along the planned track only
    func runTrain(_ v: Vehicle, _ h: Double) {
        let s = v.spec, c = v.input
        guard v.pathI < v.path.count else {
            // no track ahead planned: brakes on
            v.speed = max(0, v.speed - s.brake * h); return
        }
        let pulling = c.throttle > 0 && engine(v, c.throttle, v.speed * h)
        var a = pulling ? c.throttle * s.accel * (1 - v.speed / s.maxSpeed) : 0
        a -= c.brake * s.brake + v.speed * 0.004
        // the track's own limit on this tile (a train on ordinary track is no faster than it allows)
        let lim = wayKind(at: v.tile)?.limit ?? bridge(at: v.tile)?.deck.limit ?? s.maxSpeed
        if v.speed > lim + 0.5 { a = min(a, -s.brake * 0.5) }
        // the signal: the protection system stops the train before track that another train holds
        let red = signalAhead(v)
        if let dist = red {
            let stopNeed = v.speed * v.speed / (2 * s.emergency)
            if stopNeed >= dist - 0.5 { a = min(a, -s.emergency); if v.control == .manual && v.halted != "red signal" { event(v, "train protection braked at a red signal") }; v.halted = "red signal" }
        } else if v.halted == "red signal" { v.halted = nil }
        v.speed = max(0, v.speed + a * h)
        if let dist = red, dist <= 0.05 { v.speed = 0 }
        advanceOnPath(v, v.speed * h)
    }

    /// Move a distance along the planned path (trains always; anything when far away).
    func advanceOnPath(_ v: Vehicle, _ dist: Double) {
        var left = dist
        while left > 1e-9 && v.pathI < v.path.count {
            let n = v.path[v.pathI]
            let target = n.tile.center
            let dx = (target.x - v.x) / 16, dy = (target.y - v.y) / 16
            let d = (dx * dx + dy * dy).squareRoot()
            if d < 1e-9 { v.pathI += 1; continue }
            v.heading = atan2(dy, dx)
            if d <= left {
                if v.trail.last != n.tile { v.trail.append(n.tile); if v.trail.count > Int(v.spec.length) + 2 { v.trail.removeFirst(v.trail.count - Int(v.spec.length) - 2) } }
                v.x = target.x; v.y = target.y; left -= d
                v.level = n.l
                v.z = n.l == 1 ? (bridge(at: n.tile)?.deckZ ?? 0) : 0
                v.pathI += 1
            } else {
                v.x += dx / d * left * 16; v.y += dy / d * left * 16; left = 0
            }
        }
        v.odometer += dist
        v.wear += dist * v.spec.wearPerTile
    }

    /// Track held by trains: every tile a train covers, and the tiles it needs to stop in, are its own.
    func holdTrack() {
        var hold: [Int64: Int] = [:]
        for v in realm.transport.vehicles where v.kind.mode == .rail {
            if v.trail.isEmpty { v.trail = trackBehind(v) }
            var cells = [v.tile]
            // behind it, its length, along the track it came by
            cells += v.trail.suffix(Int(v.spec.length) + 1)
            for t in cells { hold[MP.chunkKey(t.x, t.y)] = v.id }
        }
        trackHold = hold
    }

    /// The track behind a train that has not moved yet (just built or placed): back along the rails from its front.
    func trackBehind(_ v: Vehicle) -> [TilePos] {
        var out: [TilePos] = []
        var t = v.tile
        var from = TilePos(t.x + Int(cos(v.heading).rounded()), t.y + Int(sin(v.heading).rounded()))
        for _ in 0..<Int(v.spec.length) {
            let next = [TilePos(t.x + 1, t.y), TilePos(t.x - 1, t.y), TilePos(t.x, t.y + 1), TilePos(t.x, t.y - 1)]
                .filter { $0 != from && (wayKind(at: $0)?.mode == .rail || bridge(at: $0)?.deck.mode == .rail) && !out.contains($0) }
            guard let n = next.first else { break }
            out.insert(n, at: 0); from = t; t = n
        }
        return out
    }

    /// Distance (tiles) to the first track ahead held by another train, within what it needs to stop plus a margin.
    func signalAhead(_ v: Vehicle) -> Double? {
        let look = v.speed * v.speed / (2 * v.spec.emergency) + 6
        var dist = v.pos.distance(to: v.pathI < v.path.count ? v.path[v.pathI].tile.center : v.pos) / 16
        var i = v.pathI
        while i < v.path.count && dist <= look {
            if let o = trackHold[MP.chunkKey(v.path[i].x, v.path[i].y)], o != v.id { return max(0, dist - 1) }
            dist += 1; i += 1
        }
        return nil
    }

    // --- aircraft
    func fly(_ v: Vehicle, _ h: Double) {
        let s = v.spec
        var c = v.input
        if v.flight == .crashed { v.speed = 0; return }
        if v.flight == .ground {
            // taxi and take-off roll: a car on the runway, taxiways and stands only
            let pulling = c.throttle > 0 && engine(v, c.throttle, abs(v.speed) * h)
            let dir: Double = c.reverse ? -1 : 1
            var a = pulling ? dir * c.throttle * s.accel * (1 - abs(v.speed) / s.maxSpeed) : 0
            if c.brake > 0 { a -= (v.speed > 0 ? 1 : -1) * c.brake * s.brake }
            a -= v.speed * 0.01
            var nv = v.speed + a * h
            if v.speed != 0 && nv * v.speed < 0 { nv = 0 }
            if c.reverse { nv = max(-s.reverseMax, nv) }
            v.speed = nv
            // the nose wheel steers less as speed rises
            let steer = c.steer * s.maxSteer * max(0.08, 1 - abs(v.speed) / 20)
            v.heading += v.speed / s.wheelbase * tan(steer) * h
            // at walking pace it can pivot on its main wheels (differential brakes, or a tug)
            if abs(v.speed) < 0.6 { v.heading += c.steer * 0.5 * h }
            let nx = v.x + cos(v.heading) * v.speed * h * 16, ny = v.y + sin(v.heading) * v.speed * h * 16
            let to = Motion.tile(nx, ny)
            if to != v.tile && wayKind(at: to)?.mode != .air {
                // off the paved area
                if abs(v.speed) > 4 { crash(v, "ran off the runway") } else { v.speed = 0 }
                return
            }
            v.x = nx; v.y = ny; v.odometer += abs(v.speed * h)
            if v.speed >= s.vr && c.pitch > 0.2 && wayKind(at: v.tile) == .runway {
                v.flight = .air; v.vz = 2; v.task.phase = "air"; event(v, "took off")
            }
            return
        }
        // in the air: bank turns, the stick climbs or descends, the throttle sets the speed
        if c.assist {
            if v.speed < s.stall + 3 { c.throttle = max(c.throttle, 0.9); c.pitch = min(c.pitch, 0) }
        }
        let pulling = engine(v, c.throttle, v.speed * h)
        let target = pulling ? s.stall * 0.8 + (s.maxSpeed - s.stall * 0.8) * c.throttle : 0
        v.speed += (target - v.speed) * 0.25 * h - max(0, c.pitch) * 2 * h
        v.heading += c.steer * 0.6 * h
        var wantVz = c.pitch * 8
        if c.assist && abs(c.pitch) < 0.05 { wantVz = 0 }
        if v.speed < s.stall { wantVz = min(wantVz, -6 * (1 - v.speed / s.stall) - 2) }       // stalling: it sinks
        v.vz += (wantVz - v.vz) * (c.assist ? 3.0 : 1.5) * h
        v.z += v.vz * h
        v.x += cos(v.heading) * v.speed * h * 16; v.y += sin(v.heading) * v.speed * h * 16
        v.odometer += v.speed * h
        if v.z <= 0 {
            v.z = 0
            // a landing: on a runway, along it, gently, not too fast; anything else is a crash
            if let k = wayKind(at: v.tile), k == .runway, v.vz > -4, v.speed < s.vr + 12, runwayAligned(v) {
                v.flight = .ground; v.vz = 0; v.task.phase = "landed"; v.task.dwell = 0; event(v, "landed")
            } else { crash(v, wayKind(at: v.tile) == .runway ? "hard landing" : "came down off the runway") }
        }
    }

    /// The runway at the plane's tile runs along its heading (within 20 degrees).
    func runwayAligned(_ v: Vehicle) -> Bool {
        let t = v.tile
        let ax: Double = (wayKind(at: TilePos(t.x + 1, t.y)) == .runway || wayKind(at: TilePos(t.x - 1, t.y)) == .runway) ? 0 : Double.pi / 2
        let d = abs(remainder(v.heading - ax, Double.pi))
        return d < 0.35
    }

    func crash(_ v: Vehicle, _ why: String) {
        v.flight = .crashed; v.speed = 0; v.vz = 0; v.z = 0; v.wear = 1; v.crashes += 1
        realm.transport.stats.crashes += 1
        v.halted = why
        event(v, why)
    }

    // --- ships
    func sail(_ v: Vehicle, _ h: Double) {
        let s = v.spec, c = v.input
        if v.lockWait > 0 { v.lockWait -= h; v.speed = 0; return }
        let thrust = max(-1, min(1, c.throttle * (c.reverse ? -1 : 1)))
        let pulling = thrust != 0 && engine(v, thrust, abs(v.speed) * h)
        var a = pulling ? thrust * s.accel * (thrust > 0 ? (1 - v.speed / s.maxSpeed) : (1 + v.speed / s.reverseMax)) : 0
        a -= v.speed * abs(v.speed) * 0.004 + v.speed * 0.005
        if c.brake > 0 && v.speed != 0 { a -= (v.speed > 0 ? 1 : -1) * c.brake * s.brake }
        var nv = v.speed + a * h
        if c.brake > 0 && v.speed != 0 && nv * v.speed < 0 { nv = 0 }
        v.speed = nv
        // the rudder needs way on; at low speed the bow thrusters turn her slowly
        let thrusters = abs(v.speed) < 1.5 ? 0.15 * (1 - abs(v.speed) / 1.5) : 0
        v.heading += c.steer * (0.35 * max(-1, min(1, v.speed / 2)) + thrusters) * h
        let nx = v.x + cos(v.heading) * v.speed * h * 16, ny = v.y + sin(v.heading) * v.speed * h * 16
        let to = Motion.tile(nx, ny)
        if to != v.tile {
            let p = profile(v.kind)
            if !passable(NetNode(to.x, to.y, 0), p) {
                if let b = bridge(at: to), b.kind == .opening, b.state != .open {
                    v.speed = 0                                                       // waits for the span to rise
                    requestOpening(b.id)
                    return
                }
                if abs(v.speed) > 1.5 { realm.transport.stats.groundings += 1; v.wear += abs(v.speed) * 0.02; event(v, "ran aground") }
                v.speed = 0; return
            }
            if let lk = realm.transport.locks.firstIndex(where: { $0.cell == to }) {
                let L = realm.transport.locks[lk]
                let wait = max(L.cycle, L.busyUntil - world.time)
                realm.transport.locks[lk].busyUntil = world.time + wait + L.cycle
                realm.transport.locks[lk].passed += 1
                v.lockWait = wait
            }
        }
        for o in vehiclesAround(v.pos) where o !== v && o.kind.mode == .water {
            let r = (o.spec.radius + v.spec.radius) * 16
            if o.pos.distance(to: Vec2(nx, ny)) < r && o.pos.distance(to: Vec2(nx, ny)) < o.pos.distance(to: v.pos) { bump(v, other: o); return }
        }
        v.x = nx; v.y = ny; v.odometer += abs(v.speed * h)
        v.wear += abs(v.speed * h) * s.wearPerTile
        v.berthed = abs(v.speed) < 0.6 && quayBeside(v.tile)
    }

    func quayBeside(_ t: TilePos) -> Bool {
        for dy in -1...1 { for dx in -1...1 where wayKind(at: TilePos(t.x + dx, t.y + dy)) == .quay { return true } }
        return false
    }

    // MARK: the autopilot

    /// A driver's hands on the controls: follow the planned way, keep to the limit and the gap, stop at
    /// stops and signals. It never moves the vehicle itself.
    func autopilot(_ v: Vehicle, _ h: Double) {
        if v.replan || (v.path.isEmpty && (v.task.goal != nil || v.task.line != nil)) { plan(v) }
        var c = Controls(); c.assist = true
        let s = v.spec
        guard v.pathI < v.path.count || v.kind.mode == .air else {
            c.brake = 1; v.input = c; return
        }
        switch v.kind.mode {
        case .rail:
            let stopDist = distanceToEnd(v)
            let want = min(s.maxSpeed, (2 * s.brake * 0.8 * max(0, stopDist - 0.3)).squareRoot(), lineLimitAhead(v))
            if v.speed < want - 0.3 { c.throttle = min(1, (want - v.speed) / 3 + 0.3) } else if v.speed > want + 0.1 { c.brake = min(1, (v.speed - want) / 2 + 0.2) }
        case .road, .water:
            let follow = pursuit(v)
            c.steer = follow.steer
            let want = min(follow.speed, (2 * s.brake * 0.7 * max(0, distanceToEnd(v) - 0.2)).squareRoot())
            let gapSpeed = gapLimit(v)
            let target = min(want, gapSpeed)
            if v.kind.mode == .water {
                c.throttle = target > v.speed + 0.05 ? 1 : (target < v.speed - 0.2 ? -0.6 : 0.3 * target / max(1, s.maxSpeed))
                if target < 0.05 && v.speed < 0.3 { c.throttle = 0; c.brake = 1 }
            } else {
                if v.speed < target - 0.2 { c.throttle = min(1, (target - v.speed) / 2 + 0.25) } else if v.speed > target + 0.1 { c.brake = min(1, (v.speed - target) + 0.3) }
            }
        case .air:
            autoFly(v, &c)
        case .foot: break
        }
        v.input = c
    }

    /// Where to aim (a point ahead on the path, kept to the right-hand side of the way) and how fast to go.
    func pursuit(_ v: Vehicle) -> (steer: Double, speed: Double) {
        // drop the points already passed
        while v.pathI < v.path.count && v.path[v.pathI].tile.center.distance(to: v.pos) < 0.45 * 16 && v.pathI < v.path.count - 1 { v.pathI += 1 }
        if v.pathI < v.path.count && v.pathI == v.path.count - 1 && v.path[v.pathI].tile.center.distance(to: v.pos) < 0.3 * 16 { v.pathI += 1; return (0, 0) }
        guard v.pathI < v.path.count else { return (0, 0) }
        let n = v.path[v.pathI]
        var target = n.tile.center
        // keep right of the centre line on roads (oncoming traffic passes on the other side)
        if v.kind.mode == .road, v.pathI > 0 {
            let prev = v.path[v.pathI - 1].tile.center
            let d = (target - prev).normalized
            target = target + Vec2(-d.y, d.x) * (0.22 * 16)
        }
        let ang = atan2(target.y - v.y, target.x - v.x)
        var err = remainder(ang - v.heading, 2 * Double.pi)
        if v.speed < 0 { err = -err }
        let steer = max(-1, min(1, err * 2))
        // slow for a turn ahead
        var speed = v.kind.spec.maxSpeed
        if let k = wayKind(at: n.tile) { speed = min(speed, k.limit) } else if v.kind.mode == .road { speed = min(speed, 4) }
        if v.pathI + 1 < v.path.count {
            let a = v.path[v.pathI].tile, b = v.path[v.pathI + 1].tile
            let prev = v.pathI > 0 ? v.path[v.pathI - 1].tile : v.tile
            if (b.x - a.x) * (a.y - prev.y) != (b.y - a.y) * (a.x - prev.x) { speed = min(speed, v.kind.mode == .water ? 2.5 : 2.5) }
        }
        if abs(err) > 0.6 { speed = min(speed, 1.5) }
        // a ship with its goal behind it stops and comes round on her thrusters first
        if v.kind.mode == .water && abs(err) > 1.0 { speed = 0 }
        return (steer, speed)
    }

    /// Never closer to the vehicle ahead than it takes to stop (same direction, same level).
    func gapLimit(_ v: Vehicle) -> Double {
        var lim = Double.infinity
        let fwd = Vec2(cos(v.heading), sin(v.heading))
        for o in vehiclesAround(v.pos) where o !== v && o.level == v.level && o.kind.mode == v.kind.mode {
            let rel = (o.pos - v.pos) * (1.0 / 16)
            let along = rel.x * fwd.x + rel.y * fwd.y
            let side = abs(-rel.x * fwd.y + rel.y * fwd.x)
            guard along > 0, along < 8, side < (o.spec.radius + v.spec.radius) + 0.15 else { continue }
            if cos(o.heading - v.heading) < 0.3 { continue }        // crossing or oncoming: not ahead in this lane
            let gap = along - (o.spec.radius + v.spec.radius) - 0.4
            lim = min(lim, max(0, (2 * v.spec.brake * 0.6 * max(0, gap)).squareRoot()))
        }
        return lim
    }

    func distanceToEnd(_ v: Vehicle) -> Double {
        guard v.pathI < v.path.count else { return 0 }
        var d = v.pos.distance(to: v.path[v.pathI].tile.center) / 16
        if v.pathI + 1 < v.path.count { d += Double(v.path.count - v.pathI - 1) }
        return d
    }

    func lineLimitAhead(_ v: Vehicle) -> Double {
        var lim = v.spec.maxSpeed
        var i = v.pathI, dist = 0.0
        while i < v.path.count && dist < 30 {
            let n = v.path[i]
            let k = n.l == 1 ? bridge(at: n.tile)?.deck : wayKind(at: n.tile)
            if let k = k { lim = min(lim, (k.limit * k.limit + 2 * v.spec.brake * 0.8 * dist).squareRoot()) }
            i += 1; dist += 1
        }
        return lim
    }

    /// The autopilot of an aircraft: taxi, line up, roll, climb, cruise, approach, land, taxi in.
    func autoFly(_ v: Vehicle, _ c: inout Controls) {
        let s = v.spec
        c.assist = true
        if v.flight == .crashed { return }
        guard let goal = v.task.goal ?? lineGoal(v) else { c.brake = 1; return }
        if v.flight == .ground {
            switch v.task.phase ?? "" {
            case "landed":
                // brake on the runway, then taxi to the stand
                c.brake = 1; c.steer = alignSteer(v)
                if abs(v.speed) < 0.3 { v.task.phase = "taxiIn"; v.replan = true }
            case "taxiIn":
                if v.pathI < v.path.count { taxi(v, &c) } else { c.brake = 1 }
            default:
                if v.pathI < v.path.count { v.task.phase = "taxi"; taxi(v, &c); break }
                guard wayKind(at: v.tile) == .runway, !arrived(v, goal) || v.task.phase == "roll" else { c.brake = 1; break }
                let axis = takeoffAxis(v)
                let err = remainder(axis - v.heading, 2 * Double.pi)
                if v.task.phase != "roll" && abs(err) > 0.12 {
                    // line up: turn on the nose wheel at walking pace
                    v.task.phase = "lineup"
                    c.steer = err > 0 ? 1 : -1
                    if v.speed < 1.2 { c.throttle = 0.3 } else { c.brake = 0.5 }
                } else {
                    v.task.phase = "roll"
                    c.throttle = 1; c.steer = alignSteer(v)
                    if v.speed >= s.vr { c.pitch = 0.6 }
                }
            }
            return
        }
        // in the air: to the runway's extended centre line, down it on a glide path, flare, touch down
        let (_, threshold, axis) = approachFix(goal)
        let ax = Vec2(cos(axis), sin(axis))
        let rel = (threshold - v.pos) * (1.0 / 16)
        let along = rel.x * ax.x + rel.y * ax.y               // tiles before the threshold (negative: over the runway)
        let cross = -rel.x * ax.y + rel.y * ax.x
        let headingErr = abs(remainder(axis - v.heading, 2 * Double.pi))
        if v.task.phase != "final" && along > 6 && along < Society.approachTiles + 40 && abs(cross) < 8 && headingErr < 0.6 { v.task.phase = "final" }
        if v.task.phase == "final" && (along < -60 || (along > 0 && abs(cross) > 14)) { v.task.phase = "air" }       // go round
        var aim: Vec2, targetZ: Double, targetV: Double
        if v.task.phase == "final" {
            aim = threshold - ax * (max(along - 8, -80) * 16)       // a point on the centre line ahead
            targetZ = max(0, (along + 3) * 0.08)                     // aiming at a touchdown point three tiles in
            targetV = s.stall + 4
        } else {
            let fix = threshold - ax * (Society.approachTiles * 16)
            let toFix = (fix - v.pos).length / 16
            aim = toFix < 6 ? threshold : fix
            targetZ = max(4, min(40, toFix * 0.08))
            targetV = toFix < 40 ? s.stall + 8 : s.cruise
        }
        let ang = atan2(aim.y - v.y, aim.x - v.x)
        c.steer = max(-1, min(1, remainder(ang - v.heading, 2 * Double.pi) * 2))
        var wantVz = max(-4, min(2.5, (targetZ - v.z) * 2.0))
        if v.task.phase == "final" && v.z < 0.6 { wantVz = max(wantVz, -1.2) }     // the flare
        if v.task.phase == "final" && along < 2 { wantVz = min(max(wantVz, -1.2), -0.9) }   // over the runway: down onto it, firmly
        c.pitch = wantVz / 8
        c.throttle = max(0.05, min(1, (targetV - 0.8 * s.stall) / (s.maxSpeed - 0.8 * s.stall) + (targetV - v.speed) * 0.05))
    }

    func taxi(_ v: Vehicle, _ c: inout Controls) {
        let f = pursuit(v)
        c.steer = f.steer
        // facing away from where it must go: stop and pivot first
        if v.pathI < v.path.count {
            let t = v.path[v.pathI].tile.center
            let err = remainder(atan2(t.y - v.y, t.x - v.x) - v.heading, 2 * Double.pi)
            if abs(err) > 0.5 && v.pos.distance(to: t) > 0.3 * 16 { c.steer = err > 0 ? 1 : -1; if abs(v.speed) > 0.3 { c.brake = 1 }; return }
        }
        let want = min(f.speed, 5, (2 * v.spec.brake * 0.6 * max(0, distanceToEnd(v) - 0.2)).squareRoot())
        if v.speed < want - 0.2 { c.throttle = 0.5 } else if v.speed > want + 0.1 { c.brake = 0.8 }
    }

    /// The direction along the runway with the most runway ahead of the plane.
    func takeoffAxis(_ v: Vehicle) -> Double {
        var best = (0, 0.0)
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            var n = 0, t = v.tile
            while wayKind(at: TilePos(t.x + dx, t.y + dy)) == .runway && n < 600 { t = TilePos(t.x + dx, t.y + dy); n += 1 }
            if n > best.0 { best = (n, atan2(Double(dy), Double(dx))) }
        }
        return best.1
    }
    func alignSteer(_ v: Vehicle) -> Double {
        let t = v.tile
        let horiz = wayKind(at: TilePos(t.x + 1, t.y)) == .runway || wayKind(at: TilePos(t.x - 1, t.y)) == .runway
        let ax: Double = horiz ? (cos(v.heading) >= 0 ? 0 : Double.pi) : (sin(v.heading) >= 0 ? Double.pi / 2 : -Double.pi / 2)
        let lateral = horiz ? (v.y - Double(t.y * 16 + 8)) / 16 : (v.x - Double(t.x * 16 + 8)) / 16
        let sideSign: Double = horiz ? (cos(ax) > 0 ? -1 : 1) : (sin(ax) > 0 ? 1 : -1)
        return max(-1, min(1, remainder(ax - v.heading, 2 * Double.pi) * 3 + sideSign * lateral * 0.5))
    }

    func arrived(_ v: Vehicle, _ goal: NetNode) -> Bool { v.tile.distance2(goal.tile) <= 4 }

    /// For a runway end tile: the point 60 tiles out on its line (where the approach starts), the threshold, and the landing heading.
    func approachFix(_ goal: NetNode) -> (Vec2, Vec2, Double) {
        let t = goal.tile
        // the runway's direction and its far end from the goal
        var axis = 0.0, far = t
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            var e = t, n = 0
            while wayKind(at: TilePos(e.x + dx, e.y + dy)) == .runway && n < 400 { e = TilePos(e.x + dx, e.y + dy); n += 1 }
            if n > far.distance2(t).squareRootInt { far = e; axis = atan2(Double(dy), Double(dx)) }
        }
        let thr = t.center
        let app = thr - Vec2(cos(axis), sin(axis)) * (Society.approachTiles * 16)
        return (app, thr, axis)
    }

    func lineGoal(_ v: Vehicle) -> NetNode? {
        guard let lid = v.task.line, let l = net.line(lid), v.task.at < l.stops.count, let st = net.stop(l.stops[v.task.at]) else { return nil }
        return st.node
    }

    /// Find the way to the job's next goal from exactly where the vehicle is.
    func plan(_ v: Vehicle) {
        v.replan = false
        v.plannedRev = realm.transport.revision
        guard let goal = v.task.goal ?? lineGoal(v) else { v.path = []; v.pathI = 0; return }
        var from = v.node
        if v.kind.mode == .air {
            if v.flight == .air { v.path = [goal]; v.pathI = 0; return }
            // on the ground: taxi to the start of the runway nearest, facing the long way
            let target = v.task.phase == "taxiIn" ? goal : (runwayStart(near: v.tile) ?? goal)
            if let r = route(from: from, to: target, profile(v.kind)) { v.path = r; v.pathI = r.count > 1 ? 1 : r.count } else { v.path = []; v.halted = "no way" }
            return
        }
        if !passable(from, profile(v.kind)), v.kind.mode == .road, let near = nearestWay(v) { from = near }
        if let r = route(from: from, to: goal, profile(v.kind)) {
            v.path = r; v.pathI = r.count > 1 ? 1 : r.count               // the first node is where it stands
            if v.halted == "no way" || v.halted == "bridge gone" { v.halted = nil }
        } else {
            v.path = []; v.pathI = 0
            v.halted = "no way"
        }
    }

    func runwayStart(near t: TilePos) -> NetNode? {
        var best: (Int, TilePos)?
        for dy in -30...30 { for dx in -30...30 {
            let p = TilePos(t.x + dx, t.y + dy)
            guard wayKind(at: p) == .runway else { continue }
            // an end: a long run of runway one way and none the other way
            var isEnd = false
            for (ax, ay) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where wayKind(at: TilePos(p.x - ax, p.y - ay)) != .runway {
                var n = 0; var q = p
                while wayKind(at: TilePos(q.x + ax, q.y + ay)) == .runway && n < 30 { q = TilePos(q.x + ax, q.y + ay); n += 1 }
                if n >= 20 { isEnd = true }
            }
            if isEnd, best == nil || p.distance2(t) < best!.0 { best = (p.distance2(t), p) }
        } }
        return best.map { NetNode($0.1.x, $0.1.y, 0) }
    }

    func nearestWay(_ v: Vehicle) -> NetNode? {
        var best: (Int, NetNode)?
        for dy in -4...4 { for dx in -4...4 {
            let n = NetNode(v.tile.x + dx, v.tile.y + dy, 0)
            if passable(n, profile(v.kind)), best == nil || dx * dx + dy * dy < best!.0 { best = (dx * dx + dy * dy, n) }
        } }
        return best?.1
    }

    // MARK: far away: along the way at the speed it would have

    func farStep(_ v: Vehicle, _ dt: Double) {
        if v.replan || (v.path.isEmpty && (v.task.goal != nil || v.task.line != nil)) { plan(v) }
        guard v.pathI < v.path.count, v.halted != "broken down" else { v.speed = 0; return }
        if v.kind.mode == .air {
            // far planes are moved by the same physics, but in bigger steps (they have the whole sky)
            physics(v, dt); return
        }
        if v.kind.mode == .rail, let d = signalAhead(v), d < 1 { v.speed = 0; v.halted = "red signal"; return }
        // the speed it would hold here: the way's limit, slowed by traffic on the tile
        let n = v.path[v.pathI]
        let k = n.l == 1 ? bridge(at: n.tile)?.deck : wayKind(at: n.tile)
        var sp = min(v.spec.maxSpeed, k?.limit ?? v.spec.maxSpeed)
        if v.kind.mode == .road { sp /= max(1, Double(congestion[MP.chunkKey(n.x, n.y)] ?? 0) / (k?.capacity ?? 1)) }
        guard engine(v, 0.6, sp * dt) else { v.speed = 0; return }
        var d = min(sp * dt, distanceToEnd(v))
        if v.kind.mode == .rail, let red = signalAhead(v) { d = min(d, max(0, red - 0.2)) }
        v.speed = d / max(dt, 1e-9)
        advanceOnPath(v, d)
        if v.kind.mode == .water { v.berthed = v.pathI >= v.path.count && quayBeside(v.tile) }
    }

    func event(_ v: Vehicle, _ what: String) {
        vehicleEvents.append(VehicleEvent(t: world.time, vehicle: v.id, what: what))
        if vehicleEvents.count > 200 { vehicleEvents.removeFirst(vehicleEvents.count - 200) }
    }
}

extension Int { var squareRootInt: Int { Int(Double(self).squareRoot()) } }

extension Society { static let approachTiles = 24.0 }
