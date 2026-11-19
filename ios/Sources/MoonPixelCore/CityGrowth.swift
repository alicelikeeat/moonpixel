import Foundation

// Towns grow into cities on their own, and cities build their own transport.
//
// Once a day: every building of three levels or more gets a lift (`fitLifts`); a big town founds a district
// beside it (`urbanize`) whose people come from the nation's cities; each district is supplied with building
// materials by its nation's regional cities, out of their stocks (`nationSupply`); and each district builds
// its transport in order (`planTransport`): a main street, a street to the town it grew from, a bus line along
// it, cars for its residents, and a railway with a train to every other district of its nation in reach.
// Every way is planned, paid, felled and built by the same calls the player uses; every vehicle is bought.

extension Society {
    /// A town needs this many people to found a district.
    public static var urbanizeAt = 20
    /// At most this many districts grow out of towns (imported and demo districts do not count).
    public static var maxGrownDistricts = 6

    /// Every game hour (50 seconds at 1x): each new town takes its next building step and its next transport
    /// step, and a town big enough founds one. (The day still pays taxes, upkeep and supplies.)
    func cityGrowthHour() {
        guard realm.transportBox != nil || settlements.values.contains(where: { !$0.abandoned && $0.members.count >= Society.urbanizeAt }) else { return }
        if net.districts.filter({ $0.fromTown != nil }).isEmpty { urbanize() }
        guard realm.transportBox != nil else { return }
        for d in net.districts.sorted(by: { $0.id < $1.id }) where d.fromTown != nil && d.autoBuild {
            planDistrict(d)
            planTransport(d)
        }
    }

    func cityGrowthDay() {
        fitLifts()
        urbanize()
        guard realm.transportBox != nil else { return }
        for d in net.districts.sorted(by: { $0.id < $1.id }) where d.fromTown != nil {
            // a growing city spreads: land for an airport may be found farther out later, so it looks again every ten days
            if d.day % 10 == 0, var t = d.tried, t.contains("airport") { t.removeAll { $0 == "airport" }; d.tried = t }
            // a building that opened when the money or materials for its lift were short gets it now
            for bi in d.buildings.indices where d.buildings[bi].state == .open && d.buildings[bi].floors.count >= 3 && d.buildings[bi].lift == nil { liftFor(bi, d) }
            nationSupply(d)
            planTransport(d)
        }
    }

    // MARK: towns become cities

    /// The first big town with no district near it founds one, 40-90 tiles out (one a day at most). Its money
    /// is a grant from the nation's treasury (what the treasury can spare, and a founding bond of 12000 when it
    /// cannot: money, not goods, is not conserved anywhere in the game). It builds itself from then on.
    @discardableResult public func urbanize() -> District? {
        let grown = net.districts.filter { $0.fromTown != nil }
        guard grown.count < Society.maxGrownDistricts else { return nil }
        for s in settlements.values.sorted(by: { $0.id < $1.id }) where !s.abandoned && s.members.count >= Society.urbanizeAt {
            guard let nation = s.nation else { continue }
            if net.districts.contains(where: { $0.fromTown == s.id || $0.center.distance2(s.center) < 150 * 150 }) { continue }
            // land outside every town's area, with room round it for the district's own streets and buildings
            let live = settlements.values.filter { !$0.abandoned }
            var site = TilePos.none
            for k in 0..<16 {
                let o = world.findSite(from: s.center, minR: 50 + Double(k) * 8, maxR: 110 + Double(k) * 10, salt: 4040 + s.id * 31 + k, avoid: live.map { $0.center }, avoidDist: 40)
                if o.isNone { continue }
                let clear = !live.contains { t in [(0, 0), (-28, 0), (28, 0), (0, -28), (0, 28), (-28, -28), (28, 28), (-28, 28), (28, -28)].contains { t.inArea(TilePos(o.x + $0.0, o.y + $0.1)) } }
                if clear && !net.districts.contains(where: { $0.center.distance2(o) < 120 * 120 }) { site = o; break }
            }
            if site.isNone { continue }
            var grant = 12000.0
            if let c = realm.civBox, var p = c.polities[nation] {
                let paid = max(0, min(p.treasury * 0.5, 8000))
                p.treasury -= paid; c.polities[nation] = p
                grant = max(grant, paid)
            }
            let name = zh ? s.nameZh + "新城" : s.nameEn + " New Town"
            let d = foundDistrict(name: name, at: site, nation: nation, money: grant)
            d.fromTown = s.id
            d.note("founded by the people of \(s.nameEn)")
            emit("district_founded", [s.name(zh: zh), name], site.center)
            return d
        }
        return nil
    }

    // MARK: materials from the nation

    /// Building materials a growing district keeps in store, and what the regional cities call them.
    static let supplyTargets: [(key: String, from: String, target: Double)] = [
        ("stone", "stone", 300), ("planks", "timber", 160), ("iron", "steel", 60), ("parts", "parts", 60), ("fuel", "fuel", 200),
    ]

    /// Prices of what a district imports from outside the map when nobody in its nation can spare it.
    static let importPrice: [String: Double] = ["stone": 2, "planks": 3, "iron": 8, "parts": 12, "fuel": 3, "food": 2]

    /// When a district runs low: first the town it grew from sends what it can spare (a fifth of its stone,
    /// wood sawn into planks, its iron and parts), then the nation's regional cities (a fifth of their stock at
    /// most each, best-stocked first) - moved, never made: their stocks go down by as much. What is still
    /// missing is imported and paid for with the district's money (keeping 1500 for building).
    func nationSupply(_ d: District) {
        let cities = realm.civBox.map { c in c.cities.values.filter { $0.nation == d.nation }.sorted { $0.id < $1.id } } ?? []
        // a young town is paid for by its nation until it can pay its own way (400 people): what the treasury
        // can give, the rest as development bonds (money; the game's goods are never made from nothing)
        // a well-fed town whose homes are full is growing faster than its taxes can build for: the nation lends it
        // money to build with (growth bonds, scaled to its size) until the world nears its growth target
        let pop = Double(d.population)
        let growing = Society.growthBrake(totalPopulation) > 0.5 && plenty(d) > 0.5 && d.population + 10 >= d.homes
        if (d.population < 400 && d.money < 6000) || (growing && d.money < 3000 + pop * 4) {
            var paid = 0.0
            if let c = realm.civBox, var p = c.polities[d.nation] { paid = max(0, min(400, p.treasury * 0.1)); p.treasury -= paid; c.polities[d.nation] = p }
            let bond = growing ? pop * 3 : 0
            d.money += 400 + bond
            d.note(bond > 0 ? "growth bonds: \(Int(400 + bond))" : (paid >= 399 ? "development grant from the treasury" : "development bonds"))
        }
        feed(d, cities)
        if let tid = d.fromTown, let town = settlements[tid], !town.abandoned {
            for (key, from, target) in [("stone", "stone", 300.0), ("planks", "wood", 160), ("iron", "iron", 60), ("parts", "parts", 60)] {
                let need = target - (d.store[key] ?? 0)
                guard need >= 1 else { continue }
                let n = min(need, town.good(from) * 0.2)
                guard n >= 1 else { continue }
                town.addGood(from, -n); d.add(key, n)
                record([(key, n)], from: town.holding.name, to: d.holding.name, note: from == key ? "from the home town" : "from the home town (\(from) sawn into \(key))")
            }
        }
        // fuel for its own fleet too: enough to fill every tank it runs (aircraft hold thousands)
        let fleet = realm.transport.vehicles.filter { $0.owner == .district(d.id) && $0.spec.energy.good == "fuel" }.reduce(0.0) { $0 + $1.spec.tank }
        func target(_ key: String, _ base: Double) -> Double { key == "fuel" ? min(30000, base + fleet) : base }
        for (key, from, base) in Society.supplyTargets {
            let target = target(key, base)
            let have = d.store[key] ?? 0
            guard have < target * 0.5 else { continue }
            var need = target - have
            for city in cities.sorted(by: { $0.free(from) != $1.free(from) ? $0.free(from) > $1.free(from) : $0.id < $1.id }) {
                let n = min(need, city.free(from) * 0.2)
                guard n >= 1 else { continue }
                city.stock[from, default: 0] -= n
                d.add(key, n)
                record([(key, n)], from: "city \(city.nameEn)", to: d.holding.name, note: "regional supply (\(from))")
                need -= n
                if need < 1 { break }
            }
        }
        // what nobody could spare is bought from outside
        for (key, _, base) in Society.supplyTargets {
            let target = target(key, base)
            let need = target * 0.5 - (d.store[key] ?? 0)
            guard need >= 1, let price = Society.importPrice[key] else { continue }
            let n = min(need, max(0, d.money - 1500) / price)
            guard n >= 1 else { continue }
            d.money -= n * price; d.add(key, n)
            record([(key, n)], from: "imports", to: d.holding.name, note: "bought for \(Int(n * price))")
        }
    }

    /// Food for the people it has: from the home town, then the regional cities, then bought (before anything else).
    func feed(_ d: District, _ cities: [CivCity]) {
        let food = Double(d.population) * 8 + 60
        if let tid = d.fromTown, let town = settlements[tid], !town.abandoned, (d.store["food"] ?? 0) < food * 0.5 {
            let n = min(food - (d.store["food"] ?? 0), town.food * 0.1)
            if n >= 1 { town.addGood("food", -n); d.add("food", n); record([("food", n)], from: town.holding.name, to: d.holding.name, note: "from the home town") }
        }
        if (d.store["food"] ?? 0) < food * 0.5 {
            var need = food - (d.store["food"] ?? 0)
            for city in cities {
                for k in ["grain", "rice", "fish", "meat", "food"] where need >= 1 {
                    let n = min(need, city.free(k) * 0.2)
                    guard n >= 1 else { continue }
                    city.stock[k, default: 0] -= n
                    d.add("food", n)
                    record([("food", n)], from: "city \(city.nameEn)", to: d.holding.name, note: "regional supply (\(k))")
                    need -= n
                }
            }
            if need >= 1 {
                let n = min(need, max(0, d.money) / 2)
                if n >= 1 { d.money -= n * 2; d.add("food", n); record([("food", n)], from: "imports", to: d.holding.name, note: "bought for \(Int(n * 2))") }
            }
        }
    }

    // MARK: the district's own transport

    /// One step a day, in order. Each work is started once (a work site under way is waited for).
    public func planTransport(_ d: District) {
        var works = d.works ?? [:], tried = Set(d.tried ?? [])
        defer { d.works = works.isEmpty ? nil : works; d.tried = tried.isEmpty ? nil : Array(tried).sorted() }
        func site(_ tag: String) -> WorkSite? { works[tag].flatMap { id in realm.transport.sites.first { $0.id == id } } }
        func underWay(_ tag: String) -> Bool { site(tag).map { $0.finished == nil } ?? false }
        func done(_ tag: String) -> Bool { site(tag)?.finished != nil }
        func start(_ tag: String, _ plan: WayPlan) -> Bool {
            guard plan.ok else { tried.insert(tag); d.note("no way for the \(tag): \(plan.reason)"); return false }
            // what the store lacks for it is ordered (imported at the going price) when the money is there
            var id = startWay(plan, payer: .district(d.id), nation: d.nation, by: "district:\(d.id)", rate: 30)
            if id == nil {
                let lack = plan.cost.compactMap { k, v -> (String, Double)? in let n = v - (d.store[k] ?? 0); return n > 1e-9 ? (k, n) : nil }
                let price = lack.reduce(0.0) { $0 + $1.1 * (Society.importPrice[$1.0] ?? 10) }
                if !lack.isEmpty && price <= d.money - 1000 {
                    d.money -= price
                    for (k, n) in lack { d.add(k, n) }
                    record(lack, from: "imports", to: d.holding.name, note: "ordered for the \(tag), \(Int(price))")
                    id = startWay(plan, payer: .district(d.id), nation: d.nation, by: "district:\(d.id)", rate: 30)
                }
            }
            guard let id else {
                d.note("saving up for the \(tag)"); return false
            }
            works[tag] = id
            d.note("started the \(tag) (\(plan.cells.count) tiles)")
            return true
        }
        /// Buy a vehicle, ordering what the store lacks for it first (like the materials of a way).
        func buy(_ kind: VehicleKind, at t: TilePos, heading: Double) -> Vehicle? {
            let lack = kind.spec.build.compactMap { k, v -> (String, Double)? in let n = v - (d.store[k] ?? 0); return n > 1e-9 ? (k, n) : nil }
            if !lack.isEmpty {
                let price = lack.reduce(0.0) { $0 + $1.1 * (Society.importPrice[$1.0] ?? 10) }
                guard price <= d.money - 1000 else { d.note("saving up for a \(kind.rawValue)"); return nil }
                d.money -= price
                for (k, n) in lack { d.add(k, n) }
                record(lack, from: "imports", to: d.holding.name, note: "ordered for a \(kind.rawValue), \(Int(price))")
            }
            // an aircraft is made facing down the runway (the long way from where it stands)
            return buildVehicle(kind, at: t, heading: kind.mode == .air ? runwayAxis(at: t) : heading, payer: .district(d.id), nation: d.nation)
        }
        // a line of its own with no vehicle (bought when the money was short): buy one now
        for l in realm.transport.lines where l.payer == .district(d.id) && l.vehicles.isEmpty {
            guard let s0 = l.stops.first.flatMap({ net.stop($0) }), let s1 = l.stops.last.flatMap({ net.stop($0) }) else { continue }
            let kind: VehicleKind = l.kind
            // (where its stop is taken, by another vehicle standing there, it is tried again tomorrow)
            if let v = buy(kind, at: s0.tile, heading: atan2(Double(s1.tile.y - s0.tile.y), Double(s1.tile.x - s0.tile.x))) {
                assign(v, to: l); d.note("bought \(kind.rawValue) \(v.id) for \(l.name)")
                return
            }
        }
        if works.values.contains(where: { id in realm.transport.sites.contains { $0.id == id && $0.finished == nil } }) { return }

        // 1. a main street across the district, east-west through its middle (or a row near it)
        if site("spine") == nil && !tried.contains("spine") {
            for dy in [0, 4, -4, 8, -8, 12, -12] {
                let a = TilePos(d.center.x - 20, d.center.y + dy), b = TilePos(d.center.x + 20, d.center.y + dy)
                let plan = planStraightWay(.street, from: a, to: b)
                if plan.ok { _ = start("spine", plan); return }
            }
            _ = start("spine", planWay(.street, from: TilePos(d.center.x - 20, d.center.y), to: TilePos(d.center.x + 20, d.center.y)))
            return
        }
        guard done("spine"), let spine = site("spine") else { return }
        let street = paved(spine).filter { wayKind(at: $0) == .street && bridge(at: $0) == nil && tunnel(at: $0) == nil }
        guard street.count >= 6 else { return }

        // 2. a street to the town it grew from
        // (while it waits for materials, the steps after it go on)
        if let tid = d.fromTown, let town = settlements[tid], site("town") == nil && !tried.contains("town") {
            let near = street.min { $0.distance2(town.center) < $1.distance2(town.center) }!
            let goal = world.findSite(from: town.center, minR: 3, maxR: 14, salt: 77, avoid: [], avoidDist: 0)
            if start("town", planWay(.street, from: near, to: goal.isNone ? town.center : goal)) { return }
        }

        // 3. a bus line along the main street once there are buildings to serve
        let open = d.buildings.filter { $0.state == .open }.count
        let mine = realm.transport.lines.filter { $0.payer == .district(d.id) }
        if open >= 2 && !mine.contains(where: { $0.kind == .bus }) {
            let a = street[1], b = street[street.count - 2]
            if let s0 = addStop(.busStop, at: a, name: d.name + (zh ? " 西站" : " West"), nation: d.nation, district: d.id),
               let s1 = addStop(.busStop, at: b, name: d.name + (zh ? " 东站" : " East"), nation: d.nation, district: d.id),
               let l = addLine(.bus, stops: [s0.id, s1.id], name: d.name + (zh ? " 公交" : " bus"), headway: 120, nation: d.nation, payer: .district(d.id)),
               let v = buy(.bus, at: a, heading: atan2(Double(b.y - a.y), Double(b.x - a.x))) {
                assign(v, to: l)
                d.note("opened a bus line with bus \(v.id)")
            } else { d.note("could not open a bus line yet") }
            return
        }

        // 4. cars for the residents: one for every 25 people, eight at most
        let cars = realm.transport.vehicles.filter { $0.kind == .car && $0.owner == .district(d.id) }
        if cars.count < min(8, d.population / 25) {
            let free = street.filter { t in !realm.transport.vehicles.contains { $0.tile == t } }
            if let t = free.isEmpty ? nil : free[d.rng.index(free.count)], let v = buy(.car, at: t, heading: 0) {
                v.name = (zh ? "居民车 " : "Resident's car ") + "\(cars.count + 1)"
                d.note("a resident bought car \(v.id)")
            }
            return
        }

        // 5. a railway and a train to each other district of the nation (or across an open border) within reach
        for o in net.districts.sorted(by: { $0.id < $1.id }) where o.id != d.id && (o.nation == d.nation || borderOpen(d.nation, o.nation)) {
            guard o.center.distance2(d.center) <= 700 * 700, d.population >= 100 || open >= 4 else { continue }
            let tag = "rail:\(o.id)"
            // one railway per pair: the district with the lower id lays it
            if (o.works?["rail:\(d.id)"]) != nil || tried.contains(tag) { continue }
            if site(tag) == nil {
                // each railway has its own stations, apart from the others' (a terminus each, never a shared track)
                let slot = (o.id % 5) * 7 - 14, back = (d.id % 5) * 7 - 14
                let from = TilePos(d.center.x + slot, d.center.y - 16), to = TilePos(o.center.x + back, o.center.y - 22)
                // (saving up for it does not hold back the steps after it)
                if start(tag, planWay(.rail, from: from, to: to, join: false)) || tried.contains(tag) { return }
                continue
            }
            guard done(tag), !realm.transport.lines.contains(where: { $0.kind == .train && $0.payer == .district(d.id) && $0.name.hasSuffix("#\(o.id)") }) else { continue }
            let track = site(tag)!.cells.map { $0.t }.filter { wayKind(at: $0) == .rail && bridge(at: $0) == nil && tunnel(at: $0) == nil }
            guard track.count >= 4 else { tried.insert(tag); continue }
            let a = track[1], b = track[track.count - 2]
            if let s0 = addStop(.station, at: a, name: d.name + (zh ? " 火车站" : " Station"), nation: d.nation, district: d.id),
               let s1 = addStop(.station, at: b, name: o.name + (zh ? " 火车站" : " Station"), nation: o.nation, district: o.id),
               let l = addLine(.train, stops: [s0.id, s1.id], name: d.name + " – " + o.name + " #\(o.id)", headway: 300, nation: d.nation, payer: .district(d.id), freight: true) {
                d.note("opened the railway to \(o.name)")
                if let v = buy(.train, at: a, heading: atan2(Double(track[2].y - a.y), Double(track[2].x - a.x))) { assign(v, to: l); d.note("train \(v.id) runs to \(o.name)") }
            } else { d.note("could not open the railway to \(o.name) yet") }
            return
        }
        // 6. an airport (a runway three tiles wide, a taxiway and an apron) once it has 150 people
        if (d.population >= 150 || open >= 6) && !tried.contains("airport") && site("runway1") == nil {
            if let field = airfield(d, length: 64, avoid: nil) {
                // all of it or nothing: a runway started alone would block every site found later. What the
                // store lacks for the whole field is bought in first, when the money is there; else it saves up.
                var total: [String: Double] = [:]
                for p in field { for (k, v) in p.cost { total[k, default: 0] += v } }
                let lack = total.reduce(0.0) { $0 + max(0, $1.value - (d.store[$1.key] ?? 0)) * (Society.importPrice[$1.key] ?? 10) }
                guard lack <= d.money - 1000 else { d.note("saving up for the airport"); return }
                buyShortfall(d, total, keep: 1000)
                for (k, p) in field.enumerated() { _ = start(["runway0", "runway1", "runway2", "taxiway", "apron"][k], p) }
            } else { tried.insert("airport"); d.note("no level ground for an airport (looking again in ten days)") }
            return
        }
        if done("runway1"), done("apron"), let rw = site("runway1"), airport(d) == nil {
            let cells = paved(rw)
            _ = addStop(.airport, at: cells[0], name: d.name + (zh ? " 机场" : " Airport"), nation: d.nation, district: d.id)
            _ = addStop(.airport, at: cells[cells.count - 1], name: d.name + (zh ? " 机场货运区" : " Air Cargo"), nation: d.nation, district: d.id)
            d.note("the airport opened")
            return
        }
        // 7. air routes: to every other airport of the nation, and abroad to nations at peace with it; the type of
        // aircraft by distance and by how many people the two cities have; a cargo route between big cities
        if let (pax, cargo) = airport(d) {
            for o in net.districts.sorted(by: { $0.id < $1.id }) where o.id != d.id && borderOpen(d.nation, o.nation) {
                guard let (opax, ocargo) = airport(o) else { continue }
                let both = d.population + o.population, dist = Double(d.center.distance2(o.center)).squareRoot()
                let abroad = o.nation != d.nation
                if !realm.transport.lines.contains(where: { $0.kind.mode == .air && !$0.freight && $0.stops.contains(pax.id) && $0.stops.contains(opax.id) }) {
                    let kind = Society.aircraft(forDistance: dist, people: both)
                    let name = d.name + " – " + o.name + (abroad ? (zh ? " 国际航线" : " international") : "")
                    if let l = addLine(kind, stops: [pax.id, opax.id], name: name, headway: 600, fare: abroad ? 40 : 20, nation: d.nation, payer: .district(d.id)) {
                        d.note("opened the \(kind.name(zh: false)) route to \(o.name)\(abroad ? " (abroad)" : "")")
                        if let v = buy(kind, at: pax.tile, heading: 0) { assign(v, to: l) }
                    }
                    return
                }
                if both >= 600 && !realm.transport.lines.contains(where: { $0.kind == .cargoPlane && $0.stops.contains(cargo.id) && $0.stops.contains(ocargo.id) }) {
                    if let l = addLine(.cargoPlane, stops: [cargo.id, ocargo.id], name: d.name + " – " + o.name + (zh ? " 货运" : " cargo"), headway: 900, nation: d.nation, payer: .district(d.id), freight: true) {
                        d.note("opened an air cargo route to \(o.name)")
                        if let v = buy(.cargoPlane, at: cargo.tile, heading: 0) { assign(v, to: l) }
                    }
                    return
                }
            }
            // a route flown by too small an aircraft for the cities it joins now: a bigger one is bought for it
            for l in realm.transport.lines where l.payer == .district(d.id) && l.kind.mode == .air && !l.freight && l.kind != .fighter {
                let ss = l.stops.compactMap { net.stop($0) }
                guard ss.count == 2, let od = ss[1].district.flatMap({ net.district($0) }) else { continue }
                let want = Society.aircraft(forDistance: Double(d.center.distance2(od.center)).squareRoot(), people: d.population + od.population)
                guard let wi = VehicleKind.civilAircraft.firstIndex(of: want), let hi = VehicleKind.civilAircraft.firstIndex(of: l.kind), wi > hi else { continue }
                // a bigger aircraft joins the route (the smaller one keeps flying it too)
                if let v = buy(want, at: ss[1].tile, heading: 0) ?? buy(want, at: ss[0].tile, heading: 0) {
                    l.kind = want; assign(v, to: l)
                    d.note("\(l.name) now also has a \(want.name(zh: false))")
                }
                return
            }
        }

        // 8. the nation's air force: its biggest district builds a military airbase, apart from the airport, and its fighters
        if d.population >= 250, airport(d) != nil, d.id == net.districts.filter({ $0.nation == d.nation }).max(by: { ($0.population, -$0.id) < ($1.population, -$1.id) })?.id {
            if site("base1") == nil && !tried.contains("airbase") {
                let civil = site("runway1")?.cells.map { $0.t } ?? []
                if let field = airfield(d, length: 56, avoid: civil) {
                    for (k, p) in field.enumerated() { _ = start(["base0", "base1", "base2", "basetaxi", "baseapron"][k], p) }
                    d.note("began a military airbase")
                } else { tried.insert("airbase"); d.note("no room for an airbase") }
                return
            }
            if done("base1"), let base = site("base1") {
                let fighters = realm.transport.vehicles.filter { $0.kind == .fighter && $0.nation == d.nation }
                let want = min(6, 2 + d.population / 500)
                if fighters.count < want {
                    // the ends of the base's three runway rows, in turn (never two fighters on one spot)
                    let rows = ["base1", "base0", "base2"].compactMap { site($0).map { paved($0) } }.filter { !$0.isEmpty }
                    let spots = rows.flatMap { [$0[0], $0[$0.count - 1]] }
                    let free = spots.filter { t in !realm.transport.vehicles.contains { $0.kind.mode == .air && $0.tile.distance2(t) < 9 } }
                    guard let at = free.first else { return }
                    if let v = buy(.fighter, at: at, heading: 0) { v.name = (zh ? "战斗机 " : "Fighter ") + "\(fighters.count + 1)"; d.note("the air force took fighter \(v.id)") }
                    return
                }
            }
        }

    }

    /// The aircraft for a route: a turboprop between small towns close together, a regional jet, the narrow-body,
    /// and a wide-body between big cities or far apart.
    public static func aircraft(forDistance d: Double, people: Int) -> VehicleKind {
        if d > 700 || people >= 3000 { return .widebody }
        if people >= 900 { return .airliner }
        if people >= 400 || d > 350 { return .regionalJet }
        return .turboprop
    }

    /// The tiles a work site paves, in order (a runway's site also lists the margins it fells, after them).
    func paved(_ s: WorkSite) -> [TilePos] { s.cells.filter { $0.bridge != -1 }.map { $0.t } }

    /// A district's airport stops: passengers at the west end of the middle runway, cargo at the east end.
    func airport(_ d: District) -> (Stop, Stop)? {
        let ss = net.stops.filter { $0.kind == .airport && $0.district == d.id }.sorted { $0.id < $1.id }
        return ss.count >= 2 ? (ss[0], ss[1]) : nil
    }

    /// Plans for an airfield near a district: three parallel runway rows `length` long, a taxiway down from the
    /// western end and an apron beside it; all on free level land outside the towns (nil if there is none near).
    func airfield(_ d: District, length: Int, avoid: [TilePos]?) -> [WayPlan]? {
        let live = settlements.values.filter { !$0.abandoned }
        for r in stride(from: 30, through: 240, by: 12) {
            for (dx, dy) in [(0, r), (0, -r), (-r, 0), (r, 0), (-r, r), (r, r), (-r, -r), (r, -r)] {
                let x0 = d.center.x + dx - length / 2, y0 = d.center.y + dy
                if let a = avoid, a.contains(where: { abs($0.y - y0) < 30 && $0.x > x0 - 20 && $0.x < x0 + length + 20 }) { continue }
                if live.contains(where: { $0.inArea(TilePos(x0, y0)) || $0.inArea(TilePos(x0 + length, y0 + 6)) }) { continue }
                // its own ground: no way of any kind on or beside it (another airfield, a street, a railway)
                if ((y0 - 3)...(y0 + 8)).contains(where: { y in ((x0 - 4)...(x0 + length + 4)).contains { x in wayKind(at: TilePos(x, y)) != nil } }) { continue }
                // never across a building of any district (built, or planned and not yet raised)
                if net.districts.contains(where: { o in o.buildings.contains { $0.x < x0 + length + 3 && x0 - 3 < $0.x + $0.w && $0.y < y0 + 8 && y0 - 3 < $0.y + $0.d } }) { continue }
                var plans: [WayPlan] = []
                for k in 0..<3 { plans.append(planStraightWay(.runway, from: TilePos(x0, y0 + k), to: TilePos(x0 + length, y0 + k))) }
                plans.append(planStraightWay(.taxiway, from: TilePos(x0, y0 + 3), to: TilePos(x0, y0 + 5)))
                plans.append(planStraightWay(.apron, from: TilePos(x0 + 1, y0 + 5), to: TilePos(x0 + 10, y0 + 5)))
                // nothing but open land: no bridge, tunnel or other way to cross
                if plans.allSatisfy({ $0.ok && $0.spans.isEmpty && $0.tunnels.isEmpty }) { return plans }
            }
        }
        return nil
    }

    /// The air force on patrol: a fighter that has landed and stood a while at its base refuels and takes off
    /// again for the other end of the runway, flying a circuit out over the country and back in to land.
    func fighterPatrols() {
        for v in realm.transport.vehicles where v.kind == .fighter && v.control == .auto && v.flight == .ground {
            guard case .district(let did) = v.owner, let d = net.district(did), let base = (d.works?["base1"]).flatMap({ id in realm.transport.sites.first { $0.id == id } }) else { continue }
            let ends = paved(base)
            if let g = v.task.goal, v.tile.distance2(g.tile) > 9, v.halted == nil { continue }      // still on a sortie
            guard abs(v.speed) < 0.3 else { continue }
            v.task.dwell -= 5
            guard v.task.dwell <= 0 else { continue }
            v.task.dwell = 60                                    // a minute on the ground between sorties
            refuel(v)
            guard v.fuel >= v.spec.tank * 0.4 else { v.halted = "waiting for fuel"; continue }
            if v.wear > 0.3 { repair(v) }
            let far = v.tile.distance2(ends[0]) < v.tile.distance2(ends[ends.count - 1]) ? ends[ends.count - 1] : ends[0]
            v.task.goal = NetNode(far.x, far.y, 0); v.task.phase = nil; v.halted = nil
            v.path = []; v.pathI = 0; v.replan = true
        }
    }

    /// Residents drive: a district's own cars that stand idle go somewhere on its streets (or to the town it
    /// grew from). Called every few seconds; the autopilot drives them by the same rules as any car.
    func carErrands() {
        for d in net.districts where d.fromTown != nil {
            let streets = (d.works ?? [:]).values.compactMap { id in realm.transport.sites.first { $0.id == id && $0.finished != nil } }
                .flatMap { $0.cells.map { $0.t } }.filter { wayKind(at: $0)?.mode == .road }
            let car = profile(.car)
            let drivable = streets.filter { bridge(at: $0) == nil && tunnel(at: $0) == nil && passable(NetNode($0.x, $0.y, 0), car) }
            guard drivable.count >= 4 else { continue }
            let streetsOK = drivable
            for v in realm.transport.vehicles where v.kind == .car && v.owner == .district(d.id) && v.control == .auto && v.task.line == nil {
                // somewhere it cannot get to: another errand
                if v.halted == "no way" { v.halted = nil; v.task.goal = nil }
                if let g = v.task.goal, v.tile.distance2(g.tile) > 4, v.halted != "no fuel" { continue }
                // between errands it fills up at home, from the district's fuel
                if v.fuel < v.spec.tank * 0.5 || v.halted == "no fuel" {
                    refuel(v)
                    if v.halted == "no fuel" && v.fuel > 1 { v.halted = nil }
                    if v.fuel <= 1 { continue }
                }
                let streets = streetsOK
                let t = streets[d.rng.index(streets.count)]
                if t.distance2(v.tile) < 25 { continue }
                v.task.goal = NetNode(t.x, t.y, 0)
                v.path = []; v.pathI = 0
            }
        }
    }
}
