import Foundation

// A small working transport set laid on the real land near the traveller, for trying the vehicles and for the
// UI tests: a street with a car and a bus line, a high-speed line with its stations, a runway with an airliner,
// and (where there is water near) a quay with a ferry. Everything is planned, paid (from a district stocked for
// the demonstration), felled and built by the same calls the player and the planner use: no tile is painted.

public struct TransportDemo: Equatable {
    public var district: Int?
    public var car: Int?, bus: Int?, train: Int?, plane: Int?, ship: Int?
    public var lines: [Int] = []
    public var notes: [String] = []
    public init() {}
}

extension Society {
    @discardableResult public func transportDemo(near p: TilePos) -> TransportDemo {
        var out = TransportDemo()
        let nation = realm.player.nation
        let o0 = world.findSite(from: p, minR: 6, maxR: 80, salt: 717, avoid: [], avoidDist: 0)
        let o = o0.isNone ? p + TilePos(6, 0) : o0
        let d = foundDistrict(name: "Demo", at: o, nation: nation, money: 200_000,
                              store: ["stone": 20_000, "planks": 5000, "iron": 5000, "parts": 5000, "moonsteel": 200, "fuel": 20_000, "tools": 50, "food": 5000])
        d.autoBuild = false
        out.district = d.id
        var laid: [TilePos] = []
        /// A tile of the laid way that is the way itself (not a bridge deck or a tunnel), searching from `i` towards `towards`.
        func onWay(_ cells: [TilePos], _ k: WayKind, from i: Int, towards end: Int) -> TilePos? {
            let step = end >= i ? 1 : -1
            var j = max(0, min(cells.count - 1, i))
            while j >= 0 && j < cells.count {
                if wayKind(at: cells[j]) == k && bridge(at: cells[j]) == nil && tunnel(at: cells[j]) == nil { return cells[j] }
                if j == end { break }
                j += step
            }
            return nil
        }
        func lay(_ k: WayKind, _ a: TilePos, _ b: TilePos) -> Bool {
            let plan = planWay(k, from: a, to: b)
            guard plan.ok, let id = startWay(plan, payer: .district(d.id), nation: nation, by: "district:\(d.id)") else { out.notes.append("\(k.rawValue): \(plan.reason)"); return false }
            finishSite(id)
            laid = plan.cells
            return true
        }
        // a street with a car and a bus
        let s0 = TilePos(o.x, o.y + 2), s1 = TilePos(o.x + 40, o.y + 2)
        if lay(.street, s0, s1) {
            // the car on a straight street of its own (the bus line has the first one), clear of everything:
            // the first row near the demo where 24 tiles can be laid in a straight line
            let busStreet = laid
            let busStop = onWay(busStreet, .street, from: 6, towards: busStreet.count - 1) ?? busStreet[0]
            let busEnd = onWay(busStreet, .street, from: busStreet.count - 3, towards: 0) ?? busStreet[busStreet.count - 1]
            var road: [TilePos] = []
            search: for r in 0..<40 {
                for (dy, dx) in [(-4 - r, 0), (4 + r, 0), (-4 - r, 8), (-4 - r, -8)] {
                    let a = TilePos(o.x + dx, o.y + dy), b = TilePos(a.x + 24, a.y)
                    if busStreet.contains(where: { $0.y >= a.y - 1 && $0.y <= a.y + 1 && $0.x >= a.x - 1 && $0.x <= b.x + 1 }) { continue }
                    let plan = planStraightWay(.street, from: a, to: b)
                    guard plan.ok, let id = startWay(plan, payer: .district(d.id), nation: nation, by: "district:\(d.id)") else { continue }
                    finishSite(id)
                    road = plan.cells
                    break search
                }
            }
            if road.isEmpty { road = busStreet; out.notes.append("car: no straight row for its own street") }
            let c = road[min(1, road.count - 2)], n = road[min(2, road.count - 1)]
            out.car = buildVehicle(.car, at: c, heading: atan2(Double(n.y - c.y), Double(n.x - c.x)), payer: .district(d.id), nation: nation)?.id
            if let a = addStop(.busStop, at: busStop, name: "Demo Sq", nation: nation, district: d.id),
               let b = addStop(.busStop, at: busEnd, name: "Demo End", nation: nation, district: d.id),
               let l = addLine(.bus, stops: [a.id, b.id], name: "Demo bus", headway: 90, nation: nation, payer: .district(d.id)),
               let v = buildVehicle(.bus, at: busStop, heading: 0, payer: .district(d.id), nation: nation) {
                assign(v, to: l); out.bus = v.id; out.lines.append(l.id)
            } else { out.notes.append("bus: stops \(busStop) \(busEnd) on \(String(describing: wayKind(at: busStop)))/\(String(describing: wayKind(at: busEnd))), \(realm.transport.stops.count) stops") }
        }
        // a high-speed line, powered by a station of the district (staffed by its people)
        if lay(.hsr, TilePos(o.x, o.y + 6), TilePos(o.x + 60, o.y + 6)) {
            _ = placeCityBuilding(d, kind: "power", at: TilePos(o.x, o.y + 30))
            if let f = placeCityBuilding(d, kind: "flats", at: TilePos(o.x + 8, o.y + 30)), let fi = d.buildings.firstIndex(where: { $0.id == f }) {
                for k in d.buildings[fi].floors.indices { d.buildings[fi].floors[k].residents = 12; d.buildings[fi].floors[k].food = 300 }
                d.ledger.imported = d.population
            }
            d.staffing = Dictionary(uniqueKeysWithValues: d.buildings.map { ($0.id, 1.0) })
            refreshServices(d)
            let track = laid
            let w = onWay(track, .hsr, from: 2, towards: track.count - 1) ?? track[0]
            let e = onWay(track, .hsr, from: track.count - 3, towards: 0) ?? track[track.count - 1]
            let wi = track.firstIndex(of: w) ?? 0
            let nx = track[min(wi + 1, track.count - 1)]
            if let a = addStop(.station, at: w, name: "Demo HSR", nation: nation, district: d.id),
               let b = addStop(.station, at: e, name: "Demo HSR East", nation: nation, district: d.id),
               let l = addLine(.hsr, stops: [a.id, b.id], name: "Demo express", headway: 240, nation: nation, payer: .district(d.id)),
               let v = buildVehicle(.hsr, at: w, heading: atan2(Double(nx.y - w.y), Double(nx.x - w.x)), payer: .district(d.id), nation: nation) {
                assign(v, to: l); out.train = v.id; out.lines.append(l.id)
            } else { out.notes.append("train: stations \(w) \(e) on \(String(describing: wayKind(at: w)))/\(String(describing: wayKind(at: e))), vehicles \(realm.transport.vehicles.map { "\($0.kind)@\($0.tile)" })") }
        }
        // a runway, three tiles wide, and an airliner at its western end
        var runway = true, middle: [TilePos] = []
        for y in (o.y + 12)...(o.y + 14) { runway = lay(.runway, TilePos(o.x, y), TilePos(o.x + 50, y)) && runway; if y == o.y + 13 { middle = laid } }
        if runway, middle.count > 2 {
            out.plane = buildVehicle(.airliner, at: middle[1], heading: atan2(Double(middle[2].y - middle[1].y), Double(middle[2].x - middle[1].x)), payer: .district(d.id), nation: nation)?.id
        }
        if out.plane == nil { out.notes.append("airliner: no runway laid") }
        // a quay and a ferry where there is deep enough water near
        if let w = nearestWater(o, 40) {
            let land = [TilePos(w.x - 1, w.y), TilePos(w.x + 1, w.y), TilePos(w.x, w.y - 1), TilePos(w.x, w.y + 1)].first { world.isLand($0.x, $0.y) && !world.blocked($0.x, $0.y) }
            if let q = land, lay(.quay, q, q) {
                out.ship = buildVehicle(.ferry, at: w, heading: 0, payer: .district(d.id), nation: nation)?.id
            } else { out.notes.append("ferry: no bank to build a quay on") }
        } else { out.notes.append("ferry: no deep water within 40 tiles") }
        return out
    }
}
