import Foundation

// Where the civilisation layer meets the detailed world of Society.swift.
//
// * The towns of Society are the detailed level: each is a CivCity with `detail` set. Its people are
//   the agents themselves (counted from them, never simulated twice); its food is the town's own.
// * The nations of the realm are nations of the civilisation layer too, with the same ids. New
//   nations take ids from one counter shared by both, so an id is never given twice.
// * Regions around the towns and around the traveller are found as they are explored, once each.
// * Everything advances on the world's clock, in the same fixed steps, whatever is on screen.

extension Society {
    /// The civilisation layer, created on first use (also for saves made before it existed).
    public var civ: Civ {
        if let c = realm.civBox { return c }
        let c = Civ(seed: world.seed)
        c.time = world.time; c.day = Int(world.time / MP.daySeconds)
        c.nextNation = (realm.nations.map { $0.id }.max() ?? 0) + 1
        realm.civBox = c
        mirrorNations()
        return c
    }

    /// Every nation of the realm is a nation of the civilisation layer with the same id and name.
    func mirrorNations() {
        guard let c = realm.civBox else { return }
        for n in realm.nations {
            if c.polities[n.id] == nil {
                var p = CivPolity()
                p.id = n.id; p.nameEn = n.nameEn; p.nameZh = n.nameZh; p.color = n.color
                p.short = String(n.nameEn.prefix(2)).uppercased(); p.shape = n.id % 8; p.mark = n.id % 12
                p.founded = 0; p.origin = "first"; p.detailed = true; p.ai = false
                p.techs = ["farming"] + (n.techCount > 3 ? ["writing", "husbandry"] : [])
                c.polities[n.id] = p
            }
            c.polities[n.id]!.detailed = true
            c.polities[n.id]!.status = n.status == 2 ? .history : (n.exileSince != nil ? .exile : .active)
            c.nextNation = max(c.nextNation, n.id + 1)
        }
    }

    /// A new nation of the detailed world (a restart, a division): its id comes from the shared counter.
    func newRealmNation(origin: String) -> Int {
        let c = civ
        let id = c.newPolity(origin: origin, near: nil)
        let p = c.polities[id]!
        var n = Nation()
        n.id = id; n.nameEn = p.nameEn; n.nameZh = p.nameZh; n.color = p.color; n.techCount = legacyTech
        realm.nations.append(n)
        c.polities[id]!.detailed = true; c.polities[id]!.ai = false
        c.born.removeAll { $0 == id }
        return id
    }

    /// Regions where the detailed towns are: no city-state is made up on top of them.
    func detailedRegions(_ c: Civ) -> Set<Int64> {
        Set(settlements.values.filter { !$0.abandoned }.map { t in let r = Civ.regionOf(tile: t.center, size: c.cfg.regionTiles); return MP.chunkKey(r.0, r.1) })
    }

    /// One hour of the civilisation layer: explore, keep the detailed towns in step, advance.
    public func civHourly() {
        let c = civ
        mirrorNations()
        let detailed = detailedRegions(c)
        // what is known: two regions around every town, three around the traveller
        for t in settlements.values.filter({ !$0.abandoned }).sorted(by: { $0.id < $1.id }) { c.discover(around: t.center, radius: 2, gen: world.gen, detailed: detailed) }
        if let t = explorer { c.discover(around: t, radius: 3, gen: world.gen, detailed: detailed) }
        syncDetailed(c)
        c.advance(to: world.time)
        c.born.removeAll()
    }

    /// The towns of the detailed world as cities of the civilisation layer: same people (by age and by
    /// how hungry they are), same food, same flag. Nothing is added to the layer's own ledger: these
    /// people live and die in Society, and are counted there.
    func syncDetailed(_ c: Civ) {
        let now = world.time
        var seen = Set<Int>()
        for s in settlements.values.sorted(by: { $0.id < $1.id }) where !s.abandoned {
            let (rx, ry) = Civ.regionOf(tile: s.center, size: c.cfg.regionTiles)
            let key = MP.chunkKey(rx, ry)
            let city: CivCity
            if let found = c.cities.values.first(where: { $0.detail == s.id }) { city = found }
            else if c.regions[key]?.city == nil {
                city = CivCity(); city.id = c.nextCity; c.nextCity += 1; city.detail = s.id; city.rx = rx; city.ry = ry; city.founded = now
                c.cities[city.id] = city; c.regions[key]?.city = city.id
            } else { continue }                 // two towns in one region: the first one stands for both in the regional view
            seen.insert(city.id)
            city.nameEn = s.name(zh: false); city.nameZh = s.name(zh: true)
            city.nation = s.nation ?? 0
            var p = CivPeople()
            for id in s.members {
                guard let a = agents[id] else { continue }
                let band = a.stage(now) == "child" ? 0 : (a.stage(now) == "elder" ? 2 : 1)
                // the same states the groups use, from an agent's hunger (0 fed ... 1 starving) and health
                let st = a.hunger < 0.4 ? 0 : (a.hunger < 0.6 ? 1 : (a.hunger < 0.8 ? 2 : (a.hunger < 0.95 ? 3 : (a.health > 0.4 ? 4 : 5))))
                p.n[band * 6 + st] += 1
            }
            city.people = p
            city.stock = ["grain": s.food, "timber": s.wood, "stone": s.stone]
            city.culture = [:]
            for id in s.members { if let n = agents[id]?.nation { city.culture[n, default: 0] += 1 } }
            let tot = city.culture.values.reduce(0, +)
            if tot > 0 { for k in city.culture.keys.sorted() { city.culture[k]! /= tot } } else { city.culture = [city.nation: 1] }
            let need = Double(p.total) * 1.0
            city.dailyNeed = need; city.foodDays = need > 0 ? s.food / need : 99
            city.besieged = s.siege != nil
        }
        // towns that are gone leave the regional view too
        for (id, city) in c.cities.sorted(by: { $0.key < $1.key }) where city.detail != nil && !seen.contains(id) {
            if let k = c.regions.first(where: { $0.value.city == id })?.key { c.regions[k]?.city = nil }
            c.cities[id] = nil
        }
        // the detailed nations' figures, for the panels: their towns' people count too
        for k in c.polities.keys.sorted() where c.polities[k]!.detailed {
            c.polities[k]!.detailPop = agents.values.filter { $0.nation == k }.count
        }
    }

    /// Total people the world knows of: the detailed towns' residents and everyone in the regions found so far.
    /// (Lands not yet found are not counted: their people are not known.)
    public var knownPopulation: Int { agents.count + (realm.civBox?.people ?? 0) }

    /// A nation's name, whichever level it lives on.
    public func nationName(_ id: Int) -> String {
        if let n = realm.nation(id) { return n.name(zh: zh) }
        return realm.civBox?.polities[id]?.name(zh: zh) ?? "—"
    }
}
