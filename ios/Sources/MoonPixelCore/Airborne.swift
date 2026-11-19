import Foundation

// Sky carriers that put frames down, and the giantess (world warfare task book, phase 5).
//
// * A frame or shifter boards a sky carrier where both stand (two to a hangar of eight). Over a place, not
//   cruising, with power and its hangar whole, the carrier drops one: the frame leaves the carrier (it is moved,
//   never copied) and lands after `dropHours`; only then is it on the ground and able to take a place. A save
//   in between keeps it falling, once.
// * The giantess is a person of the world: a name, a nation, a place, stamina and a history. She wades shallow
//   water, guards a city (her strength counts in its defence while she has stamina), rescues people from a
//   city (they move to another of her nation's), and clears great obstacles (in the detailed world: rubble,
//   rocks and fallen trees on a way, so that the way is really open). Rescues and guarding are credited
//   apart, each once, and written into the city's history.

public struct CivDrop: Codable, Equatable {
    public var id = 0, unit = 0, nation = 0
    public var region: Int64 = 0
    public var lands = 0.0
    public var crew = CivPeople()
}

public struct CivGiant: Codable, Equatable {
    public var id = 0, nameEn = "", nameZh = "", nation = 0
    public var region: Int64 = 0
    public var stamina = 1.0
    public var task = ""                         // "", "guard"
    public var guarding: Int?                    // city
    /// What she has done, credited once each: rescued people, hours on guard, obstacles cleared.
    public var rescued = 0, guardHours = 0.0, cleared = 0
    public var history: [String] = []
    public func name(zh: Bool) -> String { zh ? nameZh : nameEn }
}

extension WarBalance {
    public static let dropHours = 2.0
    public static let giantPoints = 900.0
}

extension Civ {
    // MARK: - sky carriers

    /// Frames a sky carrier's hangar holds (a quarter of its aircraft bays each).
    func frameRoom(_ f: CivForce) -> Int {
        let bays = f.units.compactMap { units[$0] }.filter { $0.kind == "sky_carrier" && $0.ok("hangar") }.reduce(0) { $0 + $1.def.hangar / 4 }
        let aboard = f.units.compactMap { units[$0] }.filter { ["frame", "shifter"].contains($0.kind) }.count
        return bays - aboard
    }

    /// A frame (or shifter) boards a sky carrier's force where both are. Nil when done, or why not.
    @discardableResult public func board(_ uid: Int, carrier fid: Int) -> String? {
        guard let u = units[uid], ["frame", "shifter"].contains(u.kind), let from = u.force.flatMap({ forces[$0] }), let to = forces[fid] else { return "not_a_frame" }
        guard to.nation == u.nation, to.units.contains(where: { units[$0]?.kind == "sky_carrier" }) else { return "not_a_sky_carrier" }
        guard from.region == to.region else { return "not_here" }
        guard frameRoom(to) > 0 else { return "hangar_full" }
        from.units.removeAll { $0 == uid }
        to.crew.add(from.crew.take(u.def.crew, from: Array(6..<12)))
        to.units.append(uid)
        var v = u; v.force = fid; v.air = .parked; units[uid] = v
        if from.units.isEmpty { to.crew.add(from.crew); from.crew = CivPeople(); forces[from.id] = nil }
        return nil
    }

    /// Drop a frame from a sky carrier over the place it is: one frame, landing after `dropHours`.
    @discardableResult public func drop(_ uid: Int) -> String? {
        guard var u = units[uid], ["frame", "shifter"].contains(u.kind), let f = u.force.flatMap({ forces[$0] }) else { return "not_aboard" }
        guard let carrier = f.units.compactMap({ units[$0] }).first(where: { $0.kind == "sky_carrier" }) else { return "not_aboard" }
        if carrier.cruising { return "cruising" }
        if carrier.energy <= 0 { return "no_power" }
        if !carrier.ok("hangar") { return "hangar_broken" }
        guard let r = regions[f.region], isLand(r) else { return "no_ground" }
        if drops.contains(where: { $0.unit == uid }) { return "already_falling" }
        f.units.removeAll { $0 == uid }
        var d = CivDrop(); d.id = nextDrop; nextDrop += 1
        d.unit = uid; d.nation = u.nation; d.region = f.region; d.lands = time + WarBalance.dropHours * MP.daySeconds / 24
        d.crew = f.crew.take(u.def.crew, from: Array(6..<12))
        u.force = nil; u.air = .airborne
        units[uid] = u
        drops.append(d)
        return nil
    }

    /// Frames that have come down stand on the ground in a force of their own.
    func dropsHourly() {
        guard !drops.isEmpty else { return }
        var left: [CivDrop] = []
        for d in drops {
            guard d.lands <= time else { left.append(d); continue }
            guard var u = units[d.unit] else { continue }
            let f = CivForce(); f.id = nextForce; nextForce += 1; f.nation = d.nation; f.region = d.region; f.layer = .ground
            f.units = [d.unit]; f.crew = d.crew
            forces[f.id] = f
            u.force = f.id; u.air = .none; u.dropped = true
            units[d.unit] = u
            fight("landed", u.kind, "", [d.nation], d.region)
            record("frame_landed", nations: [d.nation], region: d.region, ids: [d.unit])
        }
        drops = left
    }

    // MARK: - the giantess

    @discardableResult public func raiseGiant(nation: Int, at k: Int64, en: String, zh: String) -> Int {
        var g = CivGiant(); g.id = nextGiant; nextGiant += 1
        g.nation = nation; g.region = k; g.nameEn = en; g.nameZh = zh
        g.history.append("day \(day): came to \(polities[nation]?.nameEn ?? "the world")")
        giants.append(g)
        return g.id
    }

    func giantIndex(_ id: Int) -> Int? { giants.firstIndex { $0.id == id } }

    /// She walks (and wades shallow water) to a region. Nil when on her way there, or why not.
    @discardableResult public func giantGo(_ id: Int, to k: Int64) -> String? {
        guard let i = giantIndex(id) else { return "no_giant" }
        guard route(from: giants[i].region, to: k, size: .large) != nil || route(from: giants[i].region, to: k, size: .person) != nil else { return "no_way" }
        giants[i].region = k                         // at her stride a region is an hour: the world level moves her at once
        giants[i].task = ""; giants[i].guarding = nil
        return nil
    }

    /// She guards the city she stands in.
    @discardableResult public func giantGuard(_ id: Int) -> String? {
        guard let i = giantIndex(id) else { return "no_giant" }
        guard let c = cities.values.first(where: { $0.regionKey == giants[i].region }) else { return "no_city" }
        if giants[i].stamina < 0.2 { return "tired" }
        giants[i].task = "guard"; giants[i].guarding = c.id
        return nil
    }

    /// She carries up to `n` people out of the city she stands in to the nearest other city of her nation.
    /// Returns how many she carried (credited once, as a rescue, apart from guarding).
    @discardableResult public func giantRescue(_ id: Int, people n: Int) -> Int {
        guard let i = giantIndex(id), giants[i].stamina >= 0.3 else { return 0 }
        guard let from = cities.values.first(where: { $0.regionKey == giants[i].region }), from.detail == nil else { return 0 }
        guard let to = cities(of: giants[i].nation).filter({ $0.id != from.id && $0.detail == nil }).min(by: { dist($0.regionKey, from.regionKey) < dist($1.regionKey, from.regionKey) }) else { return 0 }
        var moved = from.people.take(n, from: Array(6..<12))
        moved.add(from.people.take(max(0, n - moved.total), from: Array(0..<6)))
        guard moved.total > 0 else { return 0 }
        to.people.add(moved)
        from.ledger.migOut += moved.total; from.today.migOut += moved.total
        to.ledger.migIn += moved.total; to.today.migIn += moved.total
        giants[i].stamina -= 0.3
        giants[i].rescued += moved.total
        giants[i].task = ""; giants[i].guarding = nil                 // a rescue is not a watch
        giants[i].history.append("day \(day): carried \(moved.total) people from \(from.nameEn) to \(to.nameEn)")
        say("giant_rescue", [giants[i].nameEn, giants[i].nameZh, "\(moved.total)", from.nameEn, from.nameZh], [giants[i].nation], region: from.regionKey)
        return moved.total
    }

    /// Her strength in a city's defence while she guards it (nothing when spent).
    public func giantDefence(_ c: CivCity) -> Double {
        giants.filter { $0.guarding == c.id && $0.task == "guard" && $0.stamina >= 0.2 && $0.nation == c.nation }.count > 0 ? WarBalance.giantPoints : 0
    }

    /// Every hour: guarding tires her and is credited; resting restores her.
    func giantsHourly() {
        for i in giants.indices {
            if giants[i].task == "guard" {
                giants[i].stamina = max(0, giants[i].stamina - 0.01)          // about four days on watch
                giants[i].guardHours += 1
                if giants[i].stamina < 0.2 { giants[i].task = ""; giants[i].guarding = nil; giants[i].history.append("day \(day): too tired to keep watch") }
            } else {
                giants[i].stamina = min(1, giants[i].stamina + 0.04)
            }
        }
    }
}

extension Society {
    /// The giantess clears a way through the detailed world: every rubble heap, rock and fallen tree on the
    /// given tiles goes, and the way is open. Returns how many she cleared (credited to her once).
    @discardableResult public func giantClear(_ id: Int, tiles: [TilePos]) -> Int {
        let c = civ
        guard let i = c.giantIndex(id) else { return 0 }
        var n = 0
        for t in tiles {
            for _ in 0..<4 where (1...3).contains(where: { world.tile($0, t.x, t.y) != 0 && Content.shared.material(world.tile($0, t.x, t.y)) != nil }) {
                let r = hitTile(t, power: 100, by: .player)
                if r.broke { n += 1 }
            }
        }
        c.giants[i].cleared += n
        if n > 0 { c.giants[i].history.append("day \(c.day): cleared \(n) obstacles") }
        return n
    }
}
