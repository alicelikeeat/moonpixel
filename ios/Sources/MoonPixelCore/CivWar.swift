import Foundation

// Industry and arms of the civilisation layer. A machine is made stage by stage from materials really
// in store; it is crewed by people really taken from a city; it runs on fuel, energy, ammunition and
// food it really carries; it fights only what its side has seen and can reach on its layer; it is
// damaged in its key parts; and when it is lost, its crew, its cargo and the aircraft it carried are
// each accounted for. One model of battle serves near and far: the view never changes an outcome.

public struct CivUnit: Codable, Equatable {
    public enum Air: Int, Codable { case none = 0, parked, airborne, returning }
    public var id = 0, kind = "", nation = 0
    public var hp = 1.0
    public var parts: [String: Double] = [:]          // 1 whole ... 0 knocked out
    public var fuel = 0.0, ammo = 0.0, energy = 0.0, heat = 0.0
    public var force: Int?                             // the force it belongs to (crew and stores are the force's)
    public var depot: Int?                             // the city it waits in, built but not yet crewed
    public var air = Air.none
    public var at: Int64?                              // where an aircraft in flight is
    public var target: Int64?                          // where it is flying to strike or look
    public var aloft = 0.0                             // hours of flight left
    public var cruising = false                        // a sky carrier high in near space: unseen by most, harmless to all
    public var ready: [String: Double] = [:]           // weapon -> game time it can fire again
    public var def: CivUnitDef { CivUnitDef.byKey[kind]! }
    public func ok(_ part: String) -> Bool { (parts[part] ?? 1) > 0 }
    public var layer: CivLayer {
        if cruising { return .nearSpace }
        if air == .parked { return def.layer == .lowAir || def.layer == .highAir ? .ground : def.layer }
        return def.layer
    }
}

public final class CivForce: Codable {
    public enum Order: Equatable, Codable { case hold, move(Int64), attack(Int64) }
    public var id = 0, nation = 0
    public var region: Int64 = 0
    public var layer = CivLayer.ground
    public var units: [Int] = []
    public var crew = CivPeople()                      // the people serving in it (counted in its nation's population)
    public var home = 0                                // the city its people came from
    public var food: [String: Double] = [:]
    public var order = Order.hold
    public var path: [Int64] = []
    public var progress = 0.0
    public var morale = 0.8
    public init() {}
}

public struct CivProject: Codable, Equatable {
    public var id = 0, nation = 0, city = 0
    public var kind = ""
    public var stage = 0, taken = false, hours = 0.0
    public var invested: [String: Double] = [:]
    public var waiting = ""                            // why it is not moving: "materials", "facility", "energy"
    var heldBox: [String: Double]?
    /// The next stage's materials, held aside in the city for it.
    public var held: [String: Double] { get { heldBox ?? [:] } set { heldBox = newValue.isEmpty ? nil : newValue } }
}

/// A shot in the air: it lands at `impact`, and only then does it hurt (and only if the target is still there).
public struct CivStrike: Codable, Equatable {
    public var shooter = 0, nation = 0, target = 0
    public var weapon = ""
    public var region: Int64 = 0
    public var fired = 0.0, impact = 0.0
    public var damage = 0.0
}

public struct CivWreck: Codable, Equatable { public var region: Int64 = 0, kind = "", nation = 0, at = 0.0 }

/// Something that happened in a battle, for the panels and the 2D/3D views to show. Nothing depends on it.
public struct CivFight: Codable, Equatable {
    public var t = 0.0, kind = ""                      // fire, hit, miss, destroyed, part, launch, land, ditch, captured, descend
    public var a = "", b = ""                          // unit kinds
    public var nations: [Int] = []
    public var region: Int64 = 0
    public var part = ""
}

public struct CivSighting: Codable, Equatable { public var region: Int64 = 0, at = 0.0, live = false }

extension Civ {
    func dist(_ a: Int64, _ b: Int64) -> Int { abs(MP.keyCX(a) - MP.keyCX(b)) + abs(MP.keyCY(a) - MP.keyCY(b)) }
    func fight(_ kind: String, _ a: String, _ b: String, _ nations: [Int], _ region: Int64, part: String = "") {
        fights.append(CivFight(t: time, kind: kind, a: a, b: b, nations: nations, region: region, part: part))
        if fights.count > 300 { fights.removeFirst(fights.count - 300) }
    }

    // MARK: - industry

    /// Order a machine made in a city. Nothing is taken yet: each stage takes its own materials when it starts.
    @discardableResult public func order(_ kind: String, nation: Int, city: Int) -> Int? {
        guard let def = CivUnitDef.byKey[kind], let c = cities[city], c.nation == nation, c.has(def.facility) > 0,
              def.tech.allSatisfy({ knows(nation, $0) }) else { return nil }
        var p = CivProject(); p.id = nextProject; nextProject += 1
        p.nation = nation; p.city = city; p.kind = kind
        projects[p.id] = p
        reserveNextStage(p.id)
        return p.id
    }

    /// Give a project up: part of what went into it comes back, the rest is gone (and booked as such).
    @discardableResult public func cancel(project id: Int) -> [String: Double] {
        guard var p = projects[id] else { return [:] }
        release(&p, from: cities[p.city])
        var back: [String: Double] = [:]
        if let c = cities[p.city], c.nation == p.nation {
            for (k, v) in p.invested.sorted(by: { $0.key < $1.key }) {
                let r = v * cfg.refund
                c.stock[k, default: 0] += r; back[k] = r
                totals.add(\.lost, k, v - r)
            }
        } else { for (k, v) in p.invested { totals.add(\.lost, k, v) } }
        projects[id] = nil
        return back
    }

    func industryDaily() {
        for id in cities.keys.sorted() { if let c = cities[id], c.detail == nil { finishBuilds(c) } }
        for id in projects.keys.sorted() {
            guard var p = projects[id], let def = CivUnitDef.byKey[p.kind] else { continue }
            guard let c = cities[p.city], c.nation == p.nation else { _ = cancel(project: id); continue }     // the yard was lost
            guard c.has(def.facility) > 0 else { p.waiting = "facility"; projects[id] = p; continue }
            if !p.taken && !p.held.isEmpty {
                // what was held aside for this stage is used now
                let need = p.held
                release(&p, from: c)
                for (k, v) in need { c.stock[k, default: 0] -= v; p.invested[k, default: 0] += v; c.today.add(\.used, k, v) }
                p.taken = true; p.waiting = ""
            }
            if !p.taken {
                let need = def.stages[p.stage]
                if need.allSatisfy({ c.free($0.key) >= $0.value }) {
                    for (k, v) in need { c.stock[k, default: 0] -= v; p.invested[k, default: 0] += v; c.today.add(\.used, k, v) }
                    p.taken = true; p.waiting = ""
                } else { p.waiting = "materials"; projects[id] = p; continue }
            }
            let power = c.energyUsed <= 0 ? 1 : min(1, c.energyMade / c.energyUsed)
            if power < 0.5 { p.waiting = "energy" }
            p.hours += 24 * max(0.1, power) * (1 - c.people.hungerIndex)
            if p.hours >= def.hours {
                p.hours = 0; p.stage += 1; p.taken = false
                projects[id] = p
                reserveNextStage(id)
                p = projects[id]!
                if p.stage >= def.stages.count {
                    var u = CivUnit(); u.id = nextUnit; nextUnit += 1
                    u.kind = p.kind; u.nation = p.nation; u.depot = c.id
                    for part in def.parts { u.parts[part] = 1 }
                    if def.carrierBased || def.layer == .lowAir || def.layer == .highAir && def.hangar == 0 { u.air = .parked }
                    units[u.id] = u
                    projects[id] = nil
                    say("built_unit", [def.en, def.zh, c.nameEn, c.nameZh], [p.nation], region: c.regionKey)
                    continue
                }
            }
            projects[id] = p
        }
    }

    /// Put a finished machine into service: its crew is taken from the city's adults (they stay the
    /// nation's people), its tanks and racks filled from the city's stores. A machine with no one to crew
    /// it stays in the depot. Aircraft join a carrier or an airfield force in the same place.
    @discardableResult public func deploy(_ unitID: Int, joining force: Int? = nil) -> Int? {
        guard var u = units[unitID], let cid = u.depot, let c = cities[cid], c.nation == u.nation else { return nil }
        let def = u.def
        guard c.people.band(1) >= def.crew + 5 else { return nil }
        var f: CivForce
        if let fid = force, let ff = forces[fid], ff.nation == u.nation, ff.region == c.regionKey { f = ff }
        else if (def.carrierBased || def.layer == .lowAir) && def.hangar == 0 {
            // aircraft: a carrier in the city's waters with room, else the city's airfield
            if let carrier = forces.values.filter({ $0.nation == u.nation && $0.region == c.regionKey && hangarRoom($0) > 0 }).min(by: { $0.id < $1.id }) { f = carrier }
            else if c.has("airfield") > 0 { f = airfieldForce(c) } else { return nil }
        } else {
            f = CivForce(); f.id = nextForce; nextForce += 1; f.nation = u.nation; f.region = c.regionKey; f.layer = def.layer == .lowAir || def.layer == .highAir ? .highAir : def.layer
            f.home = c.id
            forces[f.id] = f
        }
        if (def.carrierBased || def.layer == .lowAir) && def.hangar == 0 && f.units.contains(where: { units[$0]?.def.hangar ?? 0 > 0 }) && hangarRoom(f) <= 0 { return nil }
        let crew = c.people.takeAdults(def.crew)
        f.crew.add(crew)
        c.ledger.enlisted += crew.total; c.today.enlisted += crew.total; totals.enlisted += crew.total
        c.sick = min(c.sick, c.pop)
        u.fuel = min(def.fuelCap, c.free("fuel")); c.stock["fuel", default: 0] -= u.fuel
        u.ammo = min(def.ammoCap, c.free("ammo")); c.stock["ammo", default: 0] -= u.ammo
        u.energy = def.energyPerDay * 2
        let foodWant = def.foodCap
        for (k, v) in takeFood(from: c, nutrition: foodWant) { f.food[k, default: 0] += v }
        u.depot = nil; u.force = f.id
        f.units.append(u.id)
        units[u.id] = u
        return f.id
    }

    func airfieldForce(_ c: CivCity) -> CivForce {
        if let f = forces.values.filter({ $0.nation == c.nation && $0.region == c.regionKey && $0.layer == .ground && $0.units.allSatisfy { units[$0]?.def.carrierBased ?? false } && !$0.units.isEmpty }).min(by: { $0.id < $1.id }) { return f }
        let f = CivForce(); f.id = nextForce; nextForce += 1; f.nation = c.nation; f.region = c.regionKey; f.layer = .ground; f.home = c.id
        forces[f.id] = f
        return f
    }

    public func hangarRoom(_ f: CivForce) -> Int {
        let cap = f.units.compactMap { units[$0] }.filter { $0.def.hangar > 0 && $0.ok("hangar") }.reduce(0) { $0 + $1.def.hangar }
        let used = f.units.compactMap { units[$0] }.filter { $0.def.carrierBased || $0.def.layer == .lowAir }.count
        return cap - used
    }

    /// Stand a machine down: its crew goes home to the city, part of it is salvaged.
    @discardableResult public func retire(_ unitID: Int) -> Bool {
        guard let u = units[unitID], let fid = u.force, let f = forces[fid], let c = cities.values.filter({ $0.nation == u.nation && $0.regionKey == f.region }).min(by: { $0.id < $1.id }) else { return false }
        let back = f.crew.takeAdults(u.def.crew)
        c.people.add(back)
        c.ledger.discharged += back.total; c.today.discharged += back.total; totals.discharged += back.total
        for (k, v) in u.def.stages.first ?? [:] { c.stock[k, default: 0] += v * cfg.salvage }
        f.units.removeAll { $0 == unitID }; units[unitID] = nil
        if f.units.isEmpty { disband(f) }
        return true
    }

    /// A force with no machines left: its people go home (or to the nearest city of theirs), its food with them.
    func disband(_ f: CivForce) {
        let home = cities[f.home].flatMap { $0.nation == f.nation ? $0 : nil } ?? cities.values.filter { $0.nation == f.nation && $0.detail == nil }.min { dist($0.regionKey, f.region) != dist($1.regionKey, f.region) ? dist($0.regionKey, f.region) < dist($1.regionKey, f.region) : $0.id < $1.id }
        if let c = home {
            c.people.add(f.crew)
            c.ledger.discharged += f.crew.total; c.today.discharged += f.crew.total; totals.discharged += f.crew.total
            put(f.food, into: c)
        } else {
            // no city of theirs is left: they scatter, and are counted as lost with the war
            if f.crew.total > 0 { totals.deaths["battle", default: 0] += f.crew.total }
            for (k, v) in f.food { totals.add(\.lost, k, v) }
        }
        f.crew = CivPeople(); f.food = [:]
        forces[f.id] = nil
    }

    // MARK: - forces: food, fuel, energy, rest

    func forcesDaily() {
        let cfg = self.cfg
        for id in forces.keys.sorted() {
            guard let f = forces[id] else { continue }
            // supply from a friendly city: in the same region in full, or over a clear road a little way off,
            // where part of it is lost on the way (and booked as lost). Cut off, a force lives on what it carries.
            let hostile = hostileRegions(of: f.nation)
            let supplier = cities.values.filter { $0.nation == f.nation && $0.detail == nil && !$0.besieged && dist($0.regionKey, f.region) <= cfg.supplyReach }
                .sorted { dist($0.regionKey, f.region) != dist($1.regionKey, f.region) ? dist($0.regionKey, f.region) < dist($1.regionKey, f.region) : $0.id < $1.id }
                .first { $0.regionKey == f.region || route(from: $0.regionKey, to: f.region, avoid: hostile.subtracting([f.region])) != nil }
            if let c = supplier {
                let need = Double(f.crew.total) * (1 + cfg.needSoldier) * 5
                let have = f.food.keys.sorted().reduce(0.0) { $0 + f.food[$1]! * (CivFood.byKey[$1]?.nutrition ?? 0) }
                let keep = c.regionKey == f.region ? 1 : 1 - cfg.supplyLoss
                if have < need { for (k, v) in takeFood(from: c, nutrition: (need - have) / keep) { f.food[k, default: 0] += v * keep; totals.add(\.lost, k, v * (1 - keep)) } }
                for uid in f.units {
                    guard var u = units[uid] else { continue }
                    let d = u.def
                    let fu = min(d.fuelCap - u.fuel, c.free("fuel")); if fu > 0 { c.stock["fuel", default: 0] -= fu; u.fuel += fu }
                    let am = min(d.ammoCap - u.ammo, c.free("ammo")); if am > 0 { c.stock["ammo", default: 0] -= am; u.ammo += am }
                    // reactors and lift are charged from the city's power when it has some to spare
                    if d.energyPerDay > 0 { let spare = max(0, c.energyMade - c.energyUsed) * 4; u.energy = min(d.energyPerDay * 3, u.energy + spare) }
                    // repairs: a little each day at home, with parts
                    if c.regionKey == f.region && u.hp < d.hp && c.free("parts") >= 1 { c.stock["parts", default: 0] -= 1; u.hp = min(d.hp, u.hp + d.hp * 0.05) }
                    for p in u.parts.keys.sorted() where c.regionKey == f.region && u.parts[p]! < 1 && c.free("parts") >= 2 { c.stock["parts", default: 0] -= 2; u.parts[p] = min(1, u.parts[p]! + 0.25) }
                    units[uid] = u
                }
            }
            // on campaign an army lives partly off the land it crosses (what it finds is booked as made there)
            if let r = regions[f.region], f.layer == .ground, r.land > 0.3 {
                let found = Double(f.crew.total) * cfg.armyForage * (0.3 + r.fertility)
                f.food["vegetable", default: 0] += found / 0.5; totals.add(\.made, "vegetable", found / 0.5)
            }
            // the crew eats what the force carries
            let need = Double(f.crew.total) * (1 + cfg.needSoldier)
            var left = need
            for k in CivFood.eatOrder where left > 1e-9 {
                guard let food = CivFood.byKey[k], let v = f.food[k], v > 0 else { continue }
                let u = min(v, left / food.nutrition); f.food[k] = v - u; left -= u * food.nutrition
                totals.add(\.eaten, k, u)
            }
            let cover = need > 0 ? (need - left) / need : 1
            shift(&f.crew, band: 1, coverage: cover)
            for st in 4..<6 {
                let k = stochastic(Double(f.crew.n[6 + st]) * cfg.starveDeath[st])
                let gone = f.crew.take(k, from: [6 + st]).total
                if gone > 0 { totals.deaths["hunger", default: 0] += gone }
            }
            f.morale = max(0.1, min(1, f.morale + (cover >= 0.95 ? 0.05 : -0.1)))
            // a machine whose crew has starved away cannot be worked
            while f.crew.total * 2 < f.units.compactMap({ units[$0]?.def.crew }).reduce(0, +), let last = f.units.last(where: { (units[$0]?.def.crew ?? 0) > 0 }) {
                guard var u = units[last] else { break }
                u.force = nil
                if let c = cities.values.filter({ $0.nation == f.nation && $0.regionKey == f.region }).min(by: { $0.id < $1.id }) { u.depot = c.id; units[last] = u }
                else { wreck(u, at: f.region); units[last] = nil }
                f.units.removeAll { $0 == last }
            }
            if f.units.isEmpty { disband(f) }
        }
    }

    // MARK: - the hour of war

    func warHourly() {
        let hour = MP.daySeconds / 24
        // shells and missiles in the air land now, and only now do they hurt
        let due = strikes.filter { $0.impact <= time }
        strikes.removeAll { $0.impact <= time }
        for s in due { land(s) }
        move(hour)
        energyAndHeat()
        airOps()
        look()
        battle()
        occupation()
    }

    func move(_ hour: Double) {
        for id in forces.keys.sorted() {
            guard let f = forces[id], !f.path.isEmpty else { continue }
            let ms = f.units.compactMap { units[$0] }
            guard !ms.isEmpty else { continue }
            // the slowest sets the pace; no fuel, no power or no crew to work it: no movement
            let canGo = ms.allSatisfy { u in (u.def.fuelPerDay == 0 || u.fuel > 0) && (u.def.energyPerDay == 0 || u.energy > 0) && u.ok("power") && u.air != .airborne }
            guard canGo else { continue }
            let speed = ms.map { $0.def.speed }.min() ?? 1
            f.progress += speed / 24
            for i in f.units.indices { if var u = units[f.units[i]] { u.fuel = max(0, u.fuel - u.def.fuelPerDay / 24); units[u.id] = u } }
            while f.progress >= 1 && !f.path.isEmpty {
                f.progress -= 1
                let next = f.path.removeFirst()
                guard let a = regions[f.region], let b = regions[next], ms.allSatisfy({ passable(a, b, size: $0.def.size, layer: f.layer) }) else { f.path = []; f.progress = 0; break }
                f.region = next
                if f.layer == .ground || f.layer == .sea { _ = discoverNear(next) }
            }
            if f.path.isEmpty { f.order = .hold }
        }
        _ = hour
    }

    func discoverNear(_ k: Int64) -> Bool { false }        // regions are found by the bridge (it has the world generator)

    /// Size and layer of a force for routing: the largest machine in it decides.
    func moveRules(_ f: CivForce) -> (CivSize, CivLayer) {
        let ms = f.units.compactMap { units[$0] }.filter { !($0.def.carrierBased && $0.def.hangar == 0 && f.units.contains { units[$0]?.def.hangar ?? 0 > 0 }) }
        let size = ms.map { $0.def.size }.max { $0.rawValue < $1.rawValue } ?? .person
        return (size, f.layer)
    }

    /// Send a force somewhere. Refused when no way exists for what it is (a carrier over land, a frame through a pass).
    @discardableResult public func send(_ fid: Int, to k: Int64, attack: Bool = false) -> Bool {
        guard let f = forces[fid] else { return false }
        let (size, layer) = moveRules(f)
        guard let path = route(from: f.region, to: k, size: size, layer: layer) else { return false }
        f.path = Array(path.dropFirst()); f.progress = 0
        f.order = attack ? .attack(k) : .move(k)
        return true
    }

    func energyAndHeat() {
        for id in units.keys.sorted() {
            guard var u = units[id], u.force != nil else { continue }
            let d = u.def
            u.heat = max(0, u.heat - d.cool / 24 * (u.ok("cooling") ? 1 : 0.4))
            if d.energyPerDay > 0 {
                u.energy = max(0, u.energy - d.energyPerDay / 24 * (u.cruising ? 0.6 : 1))
                // a sky carrier that runs out of power comes down: it cannot stay up on nothing
                if u.energy <= 0 && d.layer == .highAir && d.hangar > 0, let fid = u.force, let f = forces[fid], f.layer != .ground {
                    u.cruising = false
                    f.layer = (regions[f.region]?.land ?? 0) >= 0.3 ? .ground : .sea
                    fight("descend", d.key, "", [u.nation], f.region)
                    for o in f.units where o != id { if var a = units[o], a.air == .airborne || a.air == .returning { a.air = .returning; units[o] = a } }
                }
            }
            units[id] = u
        }
    }

    // MARK: - seeing

    func look() {
        for n in polities.keys.sorted() where polities[n]?.status == .active {
            let foes = Set(wars(of: n))
            guard !foes.isEmpty else { continue }
            var eyes: [(Int64, Int, Bool)] = []                // place, range, sonar
            for f in forces.values where f.nation == n {
                for u in f.units.compactMap({ units[$0] }) {
                    let at = u.at ?? f.region
                    let r = u.def.sensor + ((polities[n]?.knows("radio") ?? false) ? 1 : 0)
                    eyes.append((at, u.air == .parked ? 0 : r, u.def.weapons.contains { $0.layers.contains(.underwater) }))
                }
            }
            for c in cities.values where c.nation == n { eyes.append((c.regionKey, (polities[n]?.knows("radio") ?? false) ? 2 : 1, false)) }
            for f in forces.values where foes.contains(f.nation) {
                for u in f.units.compactMap({ units[$0] }) {
                    let at = u.at ?? f.region
                    let seen = eyes.contains { e in
                        let d = dist(e.0, at)
                        switch u.layer {
                        case .underwater: return e.2 && d == 0
                        case .nearSpace: return e.1 >= 3 && d <= e.1 - 2
                        default: return d <= max(0, e.1 - (u.def.stealth >= 2 ? 1 : 0))
                        }
                    }
                    let key = "\(n):\(u.id)"
                    if seen { intel[key] = CivSighting(region: at, at: time, live: true) }
                    else if var s = intel[key] { s.live = false; intel[key] = s }
                }
            }
        }
        // old reports are dropped
        for k in intel.keys.sorted() where time - intel[k]!.at > MP.daySeconds * 3 { intel[k] = nil }
    }

    /// Whether a nation sees a unit right now (only then can it be aimed at).
    public func sees(_ n: Int, _ unitID: Int) -> Bool { intel["\(n):\(unitID)"]?.live == true }

    // MARK: - fighting

    func battle() {
        for fid in forces.keys.sorted() {
            guard let f = forces[fid] else { continue }
            let foes = Set(wars(of: f.nation))
            guard !foes.isEmpty else { continue }
            for uid in f.units {
                guard var u = units[uid], u.air != .parked, !u.cruising, u.ok("weapons"), u.hp > 0 else { continue }
                let at = u.at ?? f.region
                let d = u.def
                for w in d.weapons {
                    guard (u.ready[w.key] ?? 0) <= time else { continue }
                    if w.ammo > 0 && u.ammo < w.ammo { continue }
                    if w.energy > 0 && (u.energy < w.energy || !u.ok("power")) { continue }
                    if w.heat > 0 && u.heat + w.heat > d.heatCap * (u.ok("cooling") ? 1 : 0.5) { continue }
                    // the nearest seen enemy this weapon can reach on its layers, lowest id first
                    var best: (CivUnit, Int)?
                    for of in forces.values where foes.contains(of.nation) {
                        for oid in of.units {
                            guard let o = units[oid], w.layers.contains(o.layer), o.air != .parked || o.layer == .ground, sees(f.nation, oid) else { continue }
                            let dd = dist(at, o.at ?? of.region)
                            guard dd <= w.range else { continue }
                            if best == nil || dd < best!.1 || (dd == best!.1 && oid < best!.0.id) { best = (o, dd) }
                        }
                    }
                    guard let (t, _) = best else { continue }
                    u.ammo -= w.ammo; u.energy -= w.energy; u.heat += w.heat
                    u.ready[w.key] = time + w.cooldown * MP.daySeconds / 24
                    let hungry = 1 - f.crew.hungerIndex * 0.8
                    let aim = (u.ok("control") ? 1.0 : 0.5) * hungry * (0.6 + 0.4 * f.morale)
                    let dmg = w.damage * w.vs[min(3, t.def.armor)] * aim
                    let tAt = t.at ?? forces[t.force ?? 0]?.region ?? at
                    fight("fire", d.key, t.def.key, [f.nation, t.nation], at)
                    if w.flight > 0 {
                        strikes.append(CivStrike(shooter: uid, nation: f.nation, target: t.id, weapon: w.key, region: tAt, fired: time, impact: time + w.flight * MP.daySeconds / 24, damage: dmg))
                    } else { hit(t.id, dmg, by: f.nation, weapon: w.key, shooterKind: d.key, region: tAt) }
                }
                units[uid] = u
            }
        }
    }

    /// A strike comes down where its target was. It hurts only if the target is still there.
    func land(_ s: CivStrike) {
        guard let t = units[s.target] else { fight("miss", s.weapon, "", [s.nation], s.region); return }
        let now = t.at ?? forces[t.force ?? -1]?.region
        guard now == s.region, !t.cruising || s.weapon == "long_sam" else { fight("miss", s.weapon, t.kind, [s.nation, t.nation], s.region); return }
        hit(t.id, s.damage, by: s.nation, weapon: s.weapon, shooterKind: units[s.shooter]?.kind ?? s.weapon, region: s.region)
    }

    /// Damage, and the blast seen for it, happen together. Big machines lose key parts before they are lost.
    func hit(_ id: Int, _ dmg: Double, by n: Int, weapon: String, shooterKind: String, region: Int64) {
        guard var t = units[id] else { return }
        let d = t.def
        t.hp -= dmg
        fight("hit", shooterKind, d.key, [n, t.nation], region)
        if !d.parts.isEmpty && t.hp > 0 {
            let part = d.parts[rng.index(d.parts.count)]
            let before = t.parts[part] ?? 1
            t.parts[part] = max(0, before - dmg / d.hp * 3)
            if before > 0 && t.parts[part]! <= 0 { fight("part", shooterKind, d.key, [n, t.nation], region, part: part) }
        }
        units[id] = t
        if t.hp <= 0 { destroyed(id, by: n, region: region) }
    }

    func wreck(_ u: CivUnit, at k: Int64) {
        wrecks.append(CivWreck(region: k, kind: u.kind, nation: u.nation, at: time))
        if wrecks.count > 200 { wrecks.removeFirst(wrecks.count - 200) }
    }

    /// A machine is lost: its crew dies with it (once), a carrier takes its parked aircraft down with it and
    /// its aircraft in the air look for somewhere else to land.
    func destroyed(_ id: Int, by n: Int, region: Int64) {
        guard let u = units[id], let fid = u.force, let f = forces[fid] else { units[id] = nil; return }
        let d = u.def
        fight("destroyed", "", d.key, [n, u.nation], region)
        wreck(u, at: region)
        var lost = d.crew
        f.units.removeAll { $0 == id }
        units[id] = nil
        if d.hangar > 0 {
            let room = hangarRoom(f)
            if room < 0 || !f.units.contains(where: { units[$0]?.def.hangar ?? 0 > 0 }) {
                for a in f.units.compactMap({ units[$0] }) where a.def.carrierBased || a.def.layer == .lowAir {
                    if a.air == .parked { lost += a.def.crew; f.units.removeAll { $0 == a.id }; units[a.id] = nil; wreck(a, at: region) }
                    else { divert(a.id, from: f) }
                }
            }
        }
        let gone = f.crew.takeAdults(lost)
        totals.deaths["battle", default: 0] += gone.total
        if f.units.isEmpty { disband(f) }
    }

    /// An aircraft whose deck is gone flies to another carrier of its side or an airfield in reach,
    /// with its crew; failing that it comes down where it is.
    func divert(_ id: Int, from f: CivForce) {
        guard var a = units[id] else { return }
        let at = a.at ?? f.region
        let reach = Int(a.aloft * a.def.speed / 24)
        let options = forces.values.filter { g in
            guard g.id != f.id, g.nation == a.nation, dist(g.region, at) <= reach else { return false }
            return hangarRoom(g) > 0 || cities.values.contains { c in c.nation == a.nation && c.regionKey == g.region && c.has("airfield") > 0 }
        }
            .sorted { dist($0.region, at) != dist($1.region, at) ? dist($0.region, at) < dist($1.region, at) : $0.id < $1.id }
        let airfield = cities.values.filter { $0.nation == a.nation && $0.has("airfield") > 0 && dist($0.regionKey, at) <= reach }.min { dist($0.regionKey, at) != dist($1.regionKey, at) ? dist($0.regionKey, at) < dist($1.regionKey, at) : $0.id < $1.id }
        let crew = f.crew.takeAdults(a.def.crew)
        f.units.removeAll { $0 == id }
        if let g = options.first ?? airfield.map({ airfieldForce($0) }) {
            g.crew.add(crew); g.units.append(id)
            a.force = g.id; a.air = .returning; a.target = g.region
            units[id] = a
            fight("divert", a.kind, "", [a.nation], at)
        } else {
            // down in the sea or a field: the machine is lost; its crew lives if it is among friends
            let friendly = cities.values.first { $0.nation == a.nation && $0.regionKey == at }
            if let c = friendly { c.people.add(crew); c.ledger.discharged += crew.total; totals.discharged += crew.total }
            else { totals.deaths["accident", default: 0] += crew.total }
            fight("ditch", a.kind, "", [a.nation], at)
            wreck(a, at: at); units[id] = nil
        }
    }

    // MARK: - aircraft

    func airOps() {
        for fid in forces.keys.sorted() {
            guard let f = forces[fid] else { continue }
            let decks = f.units.compactMap { units[$0] }.filter { $0.def.hangar > 0 && $0.ok("hangar") && !$0.cruising }
            let field = cities.values.contains { $0.nation == f.nation && $0.regionKey == f.region && $0.has("airfield") > 0 }
            var slots = decks.reduce(0) { $0 + $1.def.deckPerHour } + (field ? 4 : 0)
            for uid in f.units.sorted() {
                guard var a = units[uid], a.def.carrierBased || a.def.layer == .lowAir, a.def.hangar == 0 else { continue }
                switch a.air {
                case .airborne:
                    a.aloft -= 1
                    let back = Double(dist(a.at ?? f.region, f.region)) / (a.def.speed / 24) + 1
                    if let t = a.target, a.at != t { a.at = step(a.at ?? f.region, toward: t, speed: a.def.speed / 24) }
                    if a.aloft <= back || a.ammo < 1 { a.air = .returning; a.target = f.region }
                case .returning:
                    a.aloft -= 1
                    a.at = step(a.at ?? f.region, toward: f.region, speed: a.def.speed / 24)
                    if a.at == f.region && slots > 0 { slots -= 1; a.air = .parked; a.at = nil; a.target = nil; fight("land", a.kind, "", [a.nation], f.region) }
                    if a.aloft <= 0 && a.air != .parked { units[uid] = a; divert(uid, from: f); continue }
                case .parked:
                    // missions: strike what has been seen within reach, or look around when nothing is known
                    guard slots > 0, a.fuel > 0 || a.def.fuelCap == 0 else { break }
                    let reach = Int(a.def.endurance * a.def.speed / 24 / 2)
                    let seen = intel.filter { $0.key.hasPrefix("\(f.nation):") && $0.value.live && dist($0.value.region, f.region) <= reach }.map { $0.value.region }.sorted()
                    if let t = seen.first ?? (wars(of: f.nation).isEmpty ? nil : nearestFoeCity(f)) {
                        if dist(t, f.region) > reach { break }
                        slots -= 1
                        a.air = .airborne; a.at = f.region; a.target = t; a.aloft = a.def.endurance
                        a.fuel = max(0, a.fuel - a.def.fuelCap * 0.5)
                        fight("launch", a.kind, "", [a.nation], f.region)
                    }
                case .none: break
                }
                units[uid] = a
            }
        }
    }

    func step(_ a: Int64, toward b: Int64, speed: Double) -> Int64 {
        if a == b { return a }
        var x = MP.keyCX(a), y = MP.keyCY(a)
        let n = max(1, Int(speed.rounded(.up)))
        for _ in 0..<n { let tx = MP.keyCX(b), ty = MP.keyCY(b); if x != tx { x += x < tx ? 1 : -1 } else if y != ty { y += y < ty ? 1 : -1 } }
        return MP.chunkKey(x, y)
    }

    func nearestFoeCity(_ f: CivForce) -> Int64? {
        let foes = Set(wars(of: f.nation))
        return cities.values.filter { foes.contains($0.nation) }.min { dist($0.regionKey, f.region) != dist($1.regionKey, f.region) ? dist($0.regionKey, f.region) < dist($1.regionKey, f.region) : $0.id < $1.id }?.regionKey
    }

    // MARK: - taking cities

    func occupation() {
        for c in cities.values.sorted(by: { $0.id < $1.id }) where c.detail == nil {
            let here = forces.values.filter { $0.region == c.regionKey && $0.layer == .ground && !$0.units.isEmpty }
            let foes = here.filter { atWar($0.nation, c.nation) }
            let defenders = here.filter { $0.nation == c.nation }
            c.besieged = !foes.isEmpty
            guard let taker = foes.min(by: { $0.id < $1.id }), defenders.isEmpty else { c.occupier = nil; c.occupyHours = 0; continue }
            if c.occupier != taker.nation { c.occupier = taker.nation; c.occupyHours = 0 }
            c.occupyHours += 1
            if c.occupyHours >= 12 {
                let old = c.nation
                transfer(c, to: taker.nation)
                fight("captured", "", "", [taker.nation, old], c.regionKey)
                say("captured", [polities[taker.nation]?.nameEn ?? "", polities[taker.nation]?.nameZh ?? "", c.nameEn, c.nameZh, polities[old]?.nameEn ?? "", polities[old]?.nameZh ?? ""], [taker.nation, old], region: c.regionKey)
                // machines waiting in its depot change hands; studying them teaches something
                for (uid, var u) in units.sorted(by: { $0.key < $1.key }) where u.depot == c.id && u.nation == old { u.nation = taker.nation; units[uid] = u; studyCaptured(taker.nation, u.kind) }
                for (pid, p) in projects.sorted(by: { $0.key < $1.key }) where p.city == c.id { _ = cancel(project: pid) }
            }
        }
    }

    // MARK: - strength and choices

    func forcePower(_ f: CivForce) -> Double {
        f.units.compactMap { units[$0] }.reduce(0.0) { acc, u in acc + u.hp / u.def.hp * u.def.weapons.reduce(0.0) { $0 + $1.damage } } * (1 - f.crew.hungerIndex) * f.morale
    }

    func warChoices(_ id: Int) {
        guard let p = polities[id] else { return }
        // war: only when it is worth its cost, against a weaker neighbour, while the people are pressed
        let pressed = p.foodDays < 12 || cities(of: id).contains { $0.crowding > 1.0 }
        for r in relations.values.sorted(by: { $0.a != $1.a ? $0.a < $1.a : $0.b < $1.b }) where (r.a == id || r.b == id) {
            let o = r.a == id ? r.b : r.a
            guard let q = polities[o], q.status == .active else { continue }
            // an old quarrel or deep resentment can start a war without hunger, if it looks winnable
            let grudge = r.value < -0.5 || (r.claim && r.value < -0.3)
            if r.state == 0 && (pressed || grudge) && r.value < -0.1 && p.power > q.power * 1.3 && p.treasury > 0 && p.fatigue < 0.5 && p.power > 5 {
                if rng.unit() < cfg.warChance / yearDays { declare(id, on: o) }
            }
            if r.state == 1 && (p.fatigue > 0.8 || p.power < q.power * 0.5) && (time - r.since) / MP.daySeconds > 4 { makePeace(id, o) }
        }
        // a giant among its neighbours makes the others stand together
        let near = relations.values.filter { $0.a == id || $0.b == id }.map { $0.a == id ? $0.b : $0.a }.compactMap { polities[$0] }.filter { $0.status == .active }
        if let giant = near.max(by: { $0.power < $1.power }), giant.power > (p.power + near.filter { $0.id != giant.id }.reduce(0) { $0 + $1.power }) {
            for q in near where q.id != giant.id && q.id > id {
                let k = touch(id, q.id)
                if !relations[k]!.pact && relations[k]!.state == 0 { relations[k]!.pact = true; relations[k]!.pactSince = time; relations[k]!.value = max(relations[k]!.value, 0.3); say("pact", [p.nameEn, p.nameZh, q.nameEn, q.nameZh], [id, q.id]) }
            }
        }
        // arms: only with money, a works and a reason
        let atWar = !wars(of: id).isEmpty
        // a nation keeps some force under arms: more in war, more when its neighbours resent it
        let threatened = relations.values.contains { ($0.a == id || $0.b == id) && $0.value < -0.3 }
        // machines counted wherever they are: in service, or built and waiting in a depot
        let armed = units.values.filter { $0.nation == id }.count
        let cap = (atWar ? 3 : 1) + p.cityCount + p.pop / 400
        if (atWar || threatened || armed == 0 || p.leaning == "mecha" || p.leaning == "naval" || p.leaning == "air") && armed < cap && p.treasury > 20 && projects.values.filter({ $0.nation == id }).isEmpty {
            for kind in ["frame", "sky_carrier", "carrier", "fighter", "air_defence", "escort", "armour", "artillery", "infantry", "levy"] {
                guard let def = CivUnitDef.byKey[kind], def.tech.allSatisfy(p.knows) else { continue }
                if let c = cities(of: id).first(where: { $0.has(def.facility) > 0 }) { order(kind, nation: id, city: c.id); break }
            }
        }
        for u in units.values.sorted(by: { $0.id < $1.id }) where u.nation == id && u.depot != nil { _ = deploy(u.id) }
        // forces: march on the nearest enemy city they can reach
        if atWar {
            for f in forces.values.sorted(by: { $0.id < $1.id }) where f.nation == id && f.path.isEmpty && f.layer != .highAir {
                if let t = nearestFoeCity(f) { _ = send(f.id, to: t, attack: true) }
            }
        }
    }
}
