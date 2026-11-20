import Foundation

// Harbours and shipping lines (a city's own transport, after its airport).
//
// * A coastal city lays a quay on the bank nearest its middle (within 60 tiles) and opens a harbour on the
//   water beside it.
// * Then a passenger line to every other harbour it can really sail to (a route is found once, else it
//   is not tried again): a liner abroad or far, a ferry near; and a freighter between big cities.
// * Lines abroad only with nations at peace; at war they stop (`lineBlocked`).

extension Society {
    /// A district's harbour (a port stop on the water by its quay).
    public func seaPort(_ d: District) -> Stop? { realm.transport.stops.first { $0.kind == .port && $0.district == d.id } }

    /// The nearest bank to a point: a free land tile (no way on it) beside water at least 3 deep. (water, bank)
    func nearestShore(_ c: TilePos, _ r: Int) -> (TilePos, TilePos)? {
        for ring in 1...r {
            var best: (Int, TilePos, TilePos)?
            for dy in -ring...ring { for dx in -ring...ring where max(abs(dx), abs(dy)) == ring {
                let w = TilePos(c.x + dx, c.y + dy)
                guard waterDepth(w) >= 3 else { continue }
                for b in [TilePos(w.x - 1, w.y), TilePos(w.x + 1, w.y), TilePos(w.x, w.y - 1), TilePos(w.x, w.y + 1)]
                where world.isLand(b.x, b.y) && !world.blocked(b.x, b.y) && wayKind(at: b) == nil {
                    let d2 = dx * dx + dy * dy
                    if best == nil || d2 < best!.0 { best = (d2, w, b) }
                }
            } }
            if let b = best { return (b.1, b.2) }
        }
        return nil
    }

    /// One step of a district's harbour and shipping. True when it did something (or is waiting on work).
    @discardableResult public func planShipping(_ d: District) -> Bool {
        var works = d.works ?? [:], tried = Set(d.tried ?? [])
        defer { d.works = works.isEmpty ? nil : works; d.tried = tried.isEmpty ? nil : Array(tried).sorted() }
        func site(_ tag: String) -> WorkSite? { works[tag].flatMap { id in realm.transport.sites.first { $0.id == id } } }
        func buy(_ kind: VehicleKind, at t: TilePos) -> Vehicle? {
            buyShortfall(d, kind.spec.build, keep: 1000)
            return buildVehicle(kind, at: t, heading: 0, payer: .district(d.id), nation: d.nation)
        }
        // the harbour
        if seaPort(d) == nil {
            if tried.contains("port") { return false }
            if let q = site("quay") {
                guard q.finished != nil, let at = q.cells.first?.t else { return true }
                let water = (-1...1).flatMap { dy in (-1...1).map { dx in TilePos(at.x + dx, at.y + dy) } }.filter { waterDepth($0) >= 1.5 }
                    .max { waterDepth($0) < waterDepth($1) }
                if let w = water, addStop(.port, at: w, name: d.name + (zh ? " 港" : " Harbour"), nation: d.nation, district: d.id) != nil {
                    d.note("the harbour opened")
                } else { tried.insert("port") }
                return true
            }
            guard let (_, q) = nearestShore(d.center, 60) else { tried.insert("port"); d.note("no shore near for a quay"); return false }
            let plan = planWay(.quay, from: q, to: q)
            guard plan.ok else { tried.insert("port"); return false }
            buyShortfall(d, plan.cost, keep: 1000)
            guard let id = startWay(plan, payer: .district(d.id), nation: d.nation, by: "district:\(d.id)", rate: 30) else { d.note("saving up for the quay"); return true }
            works["quay"] = id
            d.note("started the quay")
            return true
        }
        // the lines
        guard let home = seaPort(d) else { return false }
        for o in net.districts.sorted(by: { $0.id < $1.id }) where o.id != d.id && borderOpen(d.nation, o.nation) {
            guard let there = seaPort(o), !tried.contains("sea:\(o.id)") else { continue }
            let dist = Double(d.center.distance2(o.center)).squareRoot()
            guard dist <= 1600 else { continue }
            let abroad = o.nation != d.nation
            let joined = realm.transport.lines.filter { $0.kind.mode == .water && $0.stops.contains(home.id) && $0.stops.contains(there.id) }
            if !joined.contains(where: { !$0.freight }) {
                // only where a ship can really sail between the two harbours
                guard route(from: home.node, to: there.node, profile(.ferry)) != nil else { tried.insert("sea:\(o.id)"); d.note("no sea way to \(o.name)"); continue }
                let kind: VehicleKind = abroad || dist > 400 ? .liner : .ferry
                let name = d.name + " – " + o.name + (abroad ? (zh ? " 国际航线 ⚓" : " international ⚓") : (zh ? " 航线 ⚓" : " sea line ⚓"))
                if let l = addLine(kind, stops: [home.id, there.id], name: name, headway: 900, fare: abroad ? 30 : 12, nation: d.nation, payer: .district(d.id)) {
                    d.note("opened the \(kind.name(zh: false)) line to \(o.name)\(abroad ? " (abroad)" : "")")
                    if let v = buy(kind, at: home.tile) { assign(v, to: l) }
                }
                return true
            }
            if d.population + o.population >= 300, !joined.contains(where: { $0.freight }),
               route(from: home.node, to: there.node, profile(.freighter)) != nil {
                let name = d.name + " – " + o.name + (zh ? " 海运 ⚓" : " freight ⚓")
                if let l = addLine(.freighter, stops: [home.id, there.id], name: name, headway: 1800, nation: d.nation, payer: .district(d.id), freight: true) {
                    d.note("opened a freighter line to \(o.name)")
                    if let v = buy(.freighter, at: home.tile) { assign(v, to: l) }
                }
                return true
            }
        }
        return false
    }
}
