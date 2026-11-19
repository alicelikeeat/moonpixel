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
        // the coast rule is for worlds made now, not for old saves meeting this layer for the first time
        c.coastRule = world.gen.oceans && world.time < MP.daySeconds
        c.envoys = c.coastRule
        realm.civBox = c
        mirrorNations()
        return c
    }

    /// Every nation of the realm is a nation of the civilisation layer with the same id and name.
    func mirrorNations() {
        guard let c = realm.civBox else { return }
        for n in realm.nations where n.regional != true {
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
        // a traveller whose nation has passed into history is without a nation from then on (they keep
        // their pack, their place and their name; the nation's own history stays readable)
        let pn = realm.player.nation
        if pn != 0 && (c.polities[pn]?.status == .history || realm.nation(pn)?.status == 2) {
            realm.player.nation = 0
            emit("player_stateless", [nationName(pn)], explorer?.center ?? .zero)
        }
        let detailed = detailedRegions(c)
        // what is known: two regions around every town, three around the traveller
        for t in settlements.values.filter({ !$0.abandoned }).sorted(by: { $0.id < $1.id }) { c.discover(around: t.center, radius: 2, gen: world.gen, detailed: detailed) }
        if let t = explorer { c.discover(around: t, radius: 3, gen: world.gen, detailed: detailed) }
        syncDetailed(c)
        c.applyCoastRule(gen: world.gen)
        // the nations of the underground cities (worlds from v2.16 on; old worlds meet them as they explore)
        if !c.underNations { c.underNations = true; for k in c.regions.keys.sorted() { c.foundUnder(k, gen: world.gen); c.foundSea(k, gen: world.gen) } }
        if let t = explorer { showNearby(c, around: t); showForces(c); showInvaders(c); foldCamps(c, from: t); foldAway(c, from: t) }
        syncShownOwners(c)
        // towers with real elevators get their food by them, and only while they stand
        let served = liftServedTowers
        for t in c.towerIndex.towers.values { let want: Bool? = served.contains(t.id) ? true : nil; if t.realLift != want { t.realLift = want } }
        supplyTowers()
        c.advance(to: world.time)
        // underground, near the player, the nations' digging is carved into the rock as it goes
        if realm.player.depth == 1, let t = explorer { digUnderground(around: t) }
        refreshStanding(c)
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
            c.polities[k]!.detailPop = agents.values.filter { $0.nation == k }.count + (realm.metroLink?.nation == k ? realm.metroLink!.population : 0) + (realm.transportBox?.districts.filter { $0.nation == k }.reduce(0) { $0 + $1.population } ?? 0)
        }
    }

    /// Total people the world knows of: the detailed towns' residents and everyone in the regions found so far.
    /// (Lands not yet found are not counted: their people are not known.)
    public var knownPopulation: Int { agents.count + (realm.civBox?.people ?? 0) + (realm.metroLink?.population ?? 0) + (realm.transportBox?.districts.reduce(0) { $0 + $1.population } ?? 0) }

    /// The metro city belongs to a nation: its people are counted there (and nowhere else).
    public func linkMetro(population: Int, name: String) {
        let n = realm.player.nation != 0 ? realm.player.nation : (realm.nations.first { ($0.status ?? 0) != 2 }?.id ?? 0)
        guard n != 0 else { return }
        realm.metroLink = MetroLink(nation: realm.metroLink?.nation ?? n, population: population, name: name)
    }

    /// A nation's name, whichever level it lives on.
    public func nationName(_ id: Int) -> String {
        if let n = realm.nation(id) { return n.name(zh: zh) }
        return realm.civBox?.polities[id]?.name(zh: zh) ?? "—"
    }

    // MARK: - regional cities become real towns near the traveller

    /// A regional city within a region of the traveller is shown as a real town: a place is found in its
    /// region, part of its people (by age and hunger) are handed over as residents under its flag, with food
    /// for them. Nobody is made: the regional city counts them out, the town counts them in.
    func showNearby(_ c: Civ, around t: TilePos) {
        let (rx, ry) = Civ.regionOf(tile: t, size: c.cfg.regionTiles)
        guard agents.count + 40 < world.budget.maxAgents, settlements.values.filter({ !$0.abandoned }).count < world.budget.maxSettlements else { return }
        for city in c.cities.values.sorted(by: { $0.id < $1.id }) where city.detail == nil && city.shownAs == nil && city.under != true && city.sea != true && abs(city.rx - rx) <= 1 && abs(city.ry - ry) <= 1 {
            guard let p = c.polities[city.nation], p.status == .active, city.pop >= 12 else { continue }
            let size = c.cfg.regionTiles
            let mid = TilePos(city.rx * size + size / 2, city.ry * size + size / 2)
            let site = world.findSite(from: mid, minR: 0, maxR: Double(size / 2 - 20), salt: 7000 + city.id, avoid: settlements.values.filter { !$0.abandoned }.map { $0.center }, avoidDist: 60)
            if site.isNone { continue }
            // the nation joins the detailed world's diplomacy, as itself
            if realm.nation(city.nation) == nil {
                var n = Nation(); n.id = p.id; n.nameEn = p.nameEn; n.nameZh = p.nameZh; n.color = p.color; n.techCount = legacyTech; n.regional = true
                realm.nations.append(n)
            }
            // the same place as last time, if it was shown before (its houses still stand)
            let s: Settlement
            if let old = settlements.values.filter({ $0.abandoned && $0.fromCiv == city.id }).min(by: { $0.id < $1.id }) { old.abandoned = false; attach(old); s = old }
            else { s = foundSettlement(site) }
            s.nation = city.nation; s.fromCiv = city.id
            s.nameEn = city.nameEn; s.nameZh = city.nameZh
            let k = min(max(8, city.pop / 4), 36, world.budget.maxAgents - agents.count - 10, city.people.total)
            let group = city.people.take(k)
            var made = 0
            for b in 0..<3 { for st in 0..<6 { for _ in 0..<group.n[b * 6 + st] {
                let age = b == 0 ? rng.range(2, 13) : (b == 1 ? rng.range(18, 55) : rng.range(63, 75))
                let a = newAgent(s, age: age, female: made % 2 == 0)
                a.nation = city.nation
                setHunger(a, state: st)
                made += 1
            } } }
            city.sick = min(city.sick, city.people.total)
            c.totals.toDetail = (c.totals.toDetail ?? 0) + made
            city.ledger.migOut += made
            // their food comes with them
            var goods: [String: Double] = [:]
            var food = 0.0
            for f in CivFood.eatOrder.reversed() where food < Double(made) * 12 {
                guard let def = CivFood.byKey[f] else { continue }
                let u = min(city.free(f), (Double(made) * 12 - food) / def.nutrition)
                guard u > 0 else { continue }
                city.stock[f, default: 0] -= u; goods[f] = u; food += u * def.nutrition
            }
            for (k, v) in goods { c.totals.goodsToDetail = c.totals.goodsToDetail ?? [:]; c.totals.goodsToDetail![k, default: 0] += v }
            s.food = food; s.goodsFromCiv = goods          // exactly what left the city's stores: nothing is added on the way
            let wood = min(city.free("timber"), 40), stone = min(city.free("stone"), 20)
            city.stock["timber", default: 0] -= wood; city.stock["stone", default: 0] -= stone
            s.wood = wood; s.stone = stone
            city.shownAs = s.id
            reflag(s)
            raiseTowers(of: city, in: s, c)
            emit("civ_town_seen", [s.name(zh: zh), p.name(zh: zh)], site.center)
            return                                                          // one a step: never a sudden crowd
        }
    }

    /// Towns of regional cities the traveller has left far behind go back to being counted as groups: the
    /// people (and any born meanwhile) return to the regional city with their hunger, and the food left.
    func foldAway(_ c: Civ, from t: TilePos) {
        let (rx, ry) = Civ.regionOf(tile: t, size: c.cfg.regionTiles)
        let now = world.time
        for s in settlements.values.sorted(by: { $0.id < $1.id }) where !s.abandoned {
            guard let cid = s.fromCiv, let city = c.cities[cid] else { continue }
            guard abs(city.rx - rx) > 3 || abs(city.ry - ry) > 3 else { continue }
            // not while it is fought over
            if s.siege != nil || realm.legions.contains(where: { $0.target == s.id && $0.state != 0 }) || realm.legions.contains(where: { $0.home == s.id && !$0.members.isEmpty && $0.state != 0 }) { continue }
            // everyone goes back as who they are (age band and hunger): residents to the city, soldiers
            // a force lent to the very force that lent them
            var back = CivPeople(), toForce: [Int: CivPeople] = [:]
            for id in s.members {
                guard let a = agents[id] else { continue }
                let slot = peopleSlot(a, now)
                if let fid = a.lent, c.forces[fid] != nil { toForce[fid, default: CivPeople()].n[slot] += 1 } else { back.n[slot] += 1 }
            }
            for id in s.members { if let a = agents[id] { abort(a, s); leaveHome(a, s); agents[id] = nil } }
            s.members = []
            city.people.add(back)
            city.ledger.migIn += back.total
            var returned = back.total
            for (fid, grp) in toForce.sorted(by: { $0.key < $1.key }) { c.forces[fid]!.crew.add(grp); returned += grp.total }
            c.totals.fromDetail = (c.totals.fromDetail ?? 0) + returned
            // the food left goes back in the kinds it came in (what was eaten is gone; what the town grew is grain)
            for (k, v) in foodBack(s).sorted(by: { $0.key < $1.key }) where v > 0 {
                city.stock[k, default: 0] += v
                c.totals.goodsFromDetail = c.totals.goodsFromDetail ?? [:]; c.totals.goodsFromDetail![k, default: 0] += v
            }
            city.stock["timber", default: 0] += s.wood; city.stock["stone", default: 0] += s.stone
            s.food = 0; s.wood = 0; s.stone = 0; s.goodsFromCiv = nil
            s.abandoned = true; detach(s)
            city.shownAs = nil
            for f in c.forces.values where f.lentTown == s.id { f.lent = nil; f.lentTown = nil }
            invalidateGrid()
            repairReferences()
        }
    }

    /// Where a resident is counted in a regional group: age band x hunger state (the same thresholds both ways).
    func peopleSlot(_ a: Agent, _ now: Double) -> Int {
        let b = a.stage(now) == "child" ? 0 : (a.stage(now) == "elder" ? 2 : 1)
        let st = a.hunger < 0.4 ? 0 : (a.hunger < 0.6 ? 1 : (a.hunger < 0.8 ? 2 : (a.hunger < 0.95 ? 3 : (a.health > 0.4 ? 4 : 5))))
        return b * 6 + st
    }

    /// The hunger and health a member of a regional group has as a resident (the inverse of `peopleSlot`).
    func setHunger(_ a: Agent, state st: Int) {
        a.hunger = [0.1, 0.45, 0.65, 0.85, 0.97, 1.0][st]
        if st >= 4 { a.health = st == 4 ? 0.6 : 0.3 }
    }

    /// What goes back to the regional stores when a shown town folds away: of each kind of food that was
    /// handed over, the share that is still there (by nutrition); anything beyond that was grown here and
    /// goes back as grain of the same nutrition. Never more nutrition than the town holds.
    func foodBack(_ s: Settlement) -> [String: Double] {
        let handed = s.goodsFromCiv ?? [:]
        let nut = handed.reduce(0.0) { $0 + $1.value * (CivFood.byKey[$1.key]?.nutrition ?? 1) }
        let left = max(0, s.food)
        var out: [String: Double] = [:]
        let share = nut > 0 ? min(1, left / nut) : 0
        for (k, v) in handed { out[k] = v * share }
        let extra = left - nut * share
        if extra > 1e-9 { out["grain", default: 0] += extra / (CivFood.byKey["grain"]?.nutrition ?? 1) }
        return out
    }
}
