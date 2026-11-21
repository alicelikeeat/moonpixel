import Foundation

// The air network and the teleport centre.
//
// Air network: every place that has an airport is linked to every other, by plane and by saucer.
// * Airports: the towns' and districts' own (Flights.swift: those can still be flown for real, by charter);
//   the airfields of the nations' cities (the regional layer's cities of fifty people or more); the airports
//   of the sky cities (a runway on the island).
// * UFO ports: every open UFO airport, and the UFO pad of every sky city. The saucers join the airports: a
//   saucer flies from any airport or UFO port to any other, and a plane from any airport to any other
//   airport (a UFO airport has no runway: planes do not go there).
// * To fly, the traveller must be at a place of the network (within 64 tiles of it), on the surface or on a
//   sky island. A flight takes no time from the world (the way there is told: the distance and the time it
//   would take); one arrives on the apron, or on the pad.
//
// Teleport centre: every place the traveller knows, in one list, by kind: saved places, the last places
// teleported to, the nations' cities (on the surface, underground, on the sea floor), the sky cities, the
// airports and UFO airports, the ways down, volcanoes and monuments; or any tile, on any layer. Teleporting
// works from anywhere: in a vehicle (one gets out first), riding a saucer, underground, upstairs or in the sky.

public struct AirHub: Equatable {
    public enum Kind: String { case airport, city, ufo, sky }
    public var kind: Kind
    public var name: String
    public var tile: TilePos
    public var depth: Int
    /// Planes land here (a runway); saucers land everywhere in the network.
    public var runway: Bool { kind != .ufo }
    public var id: String { "\(kind.rawValue):\(tile.x),\(tile.y),\(depth)" }
}

public struct Waypoint: Codable, Equatable {
    public var name: String
    public var x: Int, y: Int
    public var depth: Int
    public init(name: String, x: Int, y: Int, depth: Int) { self.name = name; self.x = x; self.y = y; self.depth = depth }
    public var tile: TilePos { TilePos(x, y) }
}

public struct TeleportTarget: Equatable {
    public enum Group: String, CaseIterable { case saved, recent, city, under, sea, sky, air, landmark }
    public var group: Group
    public var name: String
    public var tile: TilePos
    public var depth: Int
    public var detail: String
    /// A city of the regional layer: going there makes its town real first (and arrives in it).
    public var city: Int?
    public init(group: Group, name: String, tile: TilePos, depth: Int, detail: String, city: Int? = nil) {
        self.group = group; self.name = name; self.tile = tile; self.depth = depth; self.detail = detail; self.city = city
    }
}

extension Society {
    // MARK: the air network

    /// Every place of the air network within `r` chunks of a tile, nearest first.
    public func airHubs(around t: TilePos, within r: Int = 80, zh: Bool) -> [AirHub] {
        var out: [AirHub] = []
        for s in passengerAirports() { out.append(AirHub(kind: .airport, name: s.name, tile: s.tile, depth: 0)) }
        let c = civ, rc = c.cfg.regionTiles
        for city in c.cities.values.sorted(by: { $0.id < $1.id }) where city.detail == nil && city.under != true && city.sea != true && city.pop >= 50 {
            guard c.polities[city.nation]?.status == .active else { continue }
            out.append(AirHub(kind: .city, name: city.name(zh: zh) + (zh ? " 机场" : " Airfield"), tile: TilePos(city.rx * rc + rc / 2, city.ry * rc + rc / 2), depth: 0))
        }
        let pcx = OpenWorld.floorDiv(t.x, 32), pcy = OpenWorld.floorDiv(t.y, 32)
        let n = Generator.ufoSpacing
        for by in OpenWorld.floorDiv(pcy - r, n)...OpenWorld.floorDiv(pcy + r, n) { for bx in OpenWorld.floorDiv(pcx - r, n)...OpenWorld.floorDiv(pcx + r, n) {
            // one candidate in each block: find it
            for y in (by * n)..<(by * n + n) { for x in (bx * n)..<(bx * n + n) where world.gen.isUfoPort(x, y) && ufoPortOpen(x, y) {
                out.append(AirHub(kind: .ufo, name: (zh ? "UFO 机场 " : "UFO airport ") + "(\(x * 32 + 15), \(y * 32 + 13))", tile: TilePos(x * 32 + 15, y * 32 + 16), depth: 0))
            } }
        } }
        for s in skyCities(near: t, within: r, zh: zh) {
            out.append(AirHub(kind: .sky, name: s.name + (zh ? "（天空城）" : " (sky city)"), tile: TilePos(s.cx * 32 + 16, s.cy * 32 + 16), depth: SkyTune.depth))
        }
        return out.sorted { a, b in
            let da = a.tile.distance2(t), db = b.tile.distance2(t)
            return da != db ? da < db : a.id < b.id
        }
    }

    /// The place of the network the traveller is at (within 64 tiles), if any.
    public func airHubHere(zh: Bool) -> AirHub? {
        guard let here = travellerTile else { return nil }
        let d = realm.player.depth ?? 0
        guard d == 0 || d == SkyTune.depth else { return nil }
        return airHubs(around: here, within: 24, zh: zh).first { $0.depth == d && $0.tile.distance2(here) <= 64 * 64 }
    }

    public enum AirMode: String { case plane, ufo }

    /// Fly from where the traveller is to another place of the network. Returns where they arrive (and the
    /// layer), the distance in kilometres and the minutes the flight would take; or why not.
    public func airTravel(to dest: AirHub, by mode: AirMode, zh: Bool) -> (pos: Vec2, depth: Int, km: Double, minutes: Double)? {
        guard let from = airHubHere(zh: zh), from.id != dest.id else { return nil }
        if mode == .plane && (!from.runway || !dest.runway) { return nil }
        let km = Double(from.tile.distance2(dest.tile)).squareRoot() * 2 / 1000         // a tile is two metres
        let speed = mode == .plane ? 700.0 : 3000.0                       // km/h
        let minutes = 20 + km / speed * 60                                 // taxi and climb, then cruise
        var spot = dest.tile
        if dest.kind == .sky { spot = Society.skyArrival(OpenWorld.floorDiv(dest.tile.x, 32), OpenWorld.floorDiv(dest.tile.y, 32), by: mode == .ufo ? .ufo : .airport) }
        guard let pos = place(at: spot, depth: dest.depth) else { return nil }
        return (pos, dest.depth, km, minutes)
    }

    // MARK: teleporting

    /// Put the traveller on a tile of any layer (0 surface, 1 underground, 100 + n a storey, the sky cities'
    /// storey): out of any vehicle or saucer first, on the nearest place one can stand. Returns where, or nil.
    @discardableResult public func place(at t: TilePos, depth: Int) -> Vec2? {
        if playerVehicle != nil { _ = leaveVehicle() }
        realm.player.ufo = nil
        let pos: Vec2
        switch depth {
        case 0:
            guard let s = teleportSpot(for: t) else { return nil }
            pos = s.spot.center
        case 1:
            pos = teleportBelow(to: t)
        case 2..<OpenWorld.storeyBase:
            // a deep level: the nearest free floor there (a small room is cleared in the rock if there is none)
            let d = layer(depth)
            _ = digDeep(around: t, level: depth)
            let f = d.findFree(near: t, maxR: 24)
            if d.blocked(f.x, f.y) {
                for dy in -1...1 { for dx in -1...1 { d.setTile(2, t.x + dx, t.y + dy, 0); if content.water[Int(d.tile(0, t.x + dx, t.y + dy))] || d.tile(0, t.x + dx, t.y + dy) == content.tid("lava") { d.setTile(0, t.x + dx, t.y + dy, content.tid("cave_floor")) } } }
                pos = t.center
            } else { pos = f.center }
        default:
            guard depth >= OpenWorld.storeyBase else { return nil }
            let w = layer(depth)
            // on a storey one stands only on a floor: the nearest floor within 40 tiles
            var best: TilePos?
            search: for r in 0...40 { for dy in -r...r { for dx in -r...r where max(abs(dx), abs(dy)) == r {
                let q = TilePos(t.x + dx, t.y + dy)
                if w.tile(0, q.x, q.y) != 0 && !w.blocked(q.x, q.y) { best = q; break search }
            } } }
            guard let q = best else { return nil }
            pos = q.center
        }
        realm.player.depth = depth
        explorer = pos.tile
        if var b = realm.player.body {
            b.x = pos.x; b.y = pos.y; b.depth = depth; b.vx = 0; b.vy = 0; b.vz = 0; b.state = .standing; b.chute = nil
            b.z = WorldGround(self).floor(depth, pos.tile) ?? b.z
            realm.player.body = b
        }
        return pos
    }

    /// Where the traveller stands (their body, or where the scene last saw them).
    public var travellerTile: TilePos? { realm.player.body?.pos.tile ?? explorer }

    /// Teleport to a target and remember it among the last places.
    @discardableResult public func teleport(to target: TeleportTarget) -> Vec2? {
        // a city far away is only a number until someone comes: its town is made now, and one arrives in it
        var tile = target.tile
        if let id = target.city, target.depth == 0, let t = arriveAtCity(id) { tile = t + TilePos(0, 3) }
        guard let p = place(at: tile, depth: target.depth) else { return nil }
        var log = realm.teleportLog ?? []
        log.removeAll { $0.x == target.tile.x && $0.y == target.tile.y && $0.depth == target.depth }
        log.insert(Waypoint(name: target.name, x: target.tile.x, y: target.tile.y, depth: target.depth), at: 0)
        realm.teleportLog = Array(log.prefix(12))
        return p
    }

    /// Save where the traveller stands, under a name.
    public func saveWaypoint(_ name: String) {
        guard let t = travellerTile else { return }
        var list = realm.waypoints ?? []
        list.append(Waypoint(name: name, x: t.x, y: t.y, depth: realm.player.depth ?? 0))
        realm.waypoints = Array(list.suffix(40))
    }

    public func removeWaypoint(at i: Int) {
        guard var list = realm.waypoints, list.indices.contains(i) else { return }
        list.remove(at: i)
        realm.waypoints = list
    }

    /// The name of a layer, for lists.
    public static func layerName(_ depth: Int, zh: Bool) -> String {
        if depth == 0 { return zh ? "地面" : "surface" }
        if depth == 1 { return zh ? "地下" : "underground" }
        if MP.isBelow(depth) { return zh ? "地下第 \(depth) 层" : "level B\(depth) underground" }
        if depth == SkyTune.depth { return zh ? "天空" : "sky" }
        return zh ? "第 \(depth - OpenWorld.storeyBase) 层" : "storey \(depth - OpenWorld.storeyBase)"
    }

    /// Every place the traveller can teleport to, by group (nearest first in each).
    public func teleportTargets(from t: TilePos, zh: Bool) -> [TeleportTarget] {
        var out: [TeleportTarget] = []
        func dist(_ q: TilePos) -> String { String(format: zh ? "%.1f 公里" : "%.1f km", Double(q.distance2(t)).squareRoot() * 2 / 1000) }
        for w in realm.waypoints ?? [] { out.append(TeleportTarget(group: .saved, name: w.name, tile: w.tile, depth: w.depth, detail: Society.layerName(w.depth, zh: zh) + " · " + dist(w.tile))) }
        for w in realm.teleportLog ?? [] { out.append(TeleportTarget(group: .recent, name: w.name, tile: w.tile, depth: w.depth, detail: Society.layerName(w.depth, zh: zh) + " · " + dist(w.tile))) }
        let c = civ
        var cities: [TeleportTarget] = []
        for city in c.cities.values {
            guard let p = c.polities[city.nation], p.status == .active, let g = cityGate(city.id) else { continue }
            let group: TeleportTarget.Group = city.under == true ? .under : (city.sea == true ? .sea : .city)
            cities.append(TeleportTarget(group: group, name: (p.capital == city.id ? "★" : "") + city.name(zh: zh), tile: g.tile, depth: g.below ? 1 : 0,
                                         detail: p.name(zh: zh) + " · " + L(zh, "\(city.livePop) 人", "\(city.livePop) people") + " · " + dist(g.tile), city: g.below ? nil : city.id))
        }
        for town in settlements.values where !town.abandoned && !c.cities.values.contains(where: { $0.detail == town.id }) {
            cities.append(TeleportTarget(group: .city, name: town.name(zh: zh), tile: town.center, depth: 0, detail: dist(town.center)))
        }
        out += cities.sorted { $0.tile.distance2(t) != $1.tile.distance2(t) ? $0.tile.distance2(t) < $1.tile.distance2(t) : $0.name < $1.name }
        // the ways down: underground cities' gatehouses and the sea-floor cities' pearl domes
        if let u = nearestUnderCity(cx: OpenWorld.floorDiv(t.x, 32), cy: OpenWorld.floorDiv(t.y, 32)) {
            out.append(TeleportTarget(group: .under, name: zh ? "最近的地下城入口" : "Nearest way down", tile: TilePos(u.x, u.y + 6), depth: 0, detail: dist(u)))
        }
        if let s = nearestSeaCity(cx: OpenWorld.floorDiv(t.x, 32), cy: OpenWorld.floorDiv(t.y, 32)) {
            out.append(TeleportTarget(group: .sea, name: zh ? "最近的海底城（珍珠穹顶）" : "Nearest sea-floor city (pearl dome)", tile: TilePos(s.x, s.y + 1), depth: 0, detail: dist(s)))
        }
        for s in skyCities(near: t, within: 80, zh: zh).prefix(20) {
            let a = Society.skyArrival(s.cx, s.cy, by: .sky)
            out.append(TeleportTarget(group: .sky, name: s.name, tile: a, depth: SkyTune.depth, detail: dist(a)))
        }
        for h in airHubs(around: t, within: 60, zh: zh) where h.kind != .sky {
            out.append(TeleportTarget(group: .air, name: h.name, tile: h.tile, depth: h.depth, detail: (h.kind == .ufo ? (zh ? "UFO" : "UFO") : (zh ? "机场" : "airport")) + " · " + dist(h.tile)))
        }
        if let v = nearestVolcano(near: t) { out.append(TeleportTarget(group: .landmark, name: zh ? "最近的火山" : "Nearest volcano", tile: TilePos(v.x, v.y + 30), depth: 0, detail: dist(v))) }
        for m in realm.monuments ?? [] { out.append(TeleportTarget(group: .landmark, name: m.title(zh: zh), tile: m.center, depth: 0, detail: dist(m.center))) }
        return out
    }
}

@inline(__always) func L(_ zh: Bool, _ a: String, _ b: String) -> String { zh ? a : b }
