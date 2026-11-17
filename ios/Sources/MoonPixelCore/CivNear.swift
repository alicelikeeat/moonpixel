import Foundation

// What the regional layer becomes when the traveller is there: sleepers upstairs, towers as real
// buildings, forces as real soldiers, machines as pictures, and a war fought by hand in command mode.

public struct CivCampaign: Codable, Equatable {
    public var id = 0, nation = 0, foe = 0
    public var stake = 0.0
    public var settled = false
    public var won: Bool?
}

extension Civ {
    /// Begin a battle for a real war of this nation: a fifth of its treasury (2000 at most) is staked
    /// and becomes extra moonstone in the battle. Nil when it has no war, or one is already being fought.
    public func beginCampaign(_ nation: Int) -> CivCampaign? {
        if let c = campaign, !c.settled { return c.nation == nation ? c : nil }
        guard let p = polities[nation], p.status == .active, let foe = wars(of: nation).first else { return nil }
        let stake = max(0, min(2000, p.treasury * 0.2))
        polities[nation]!.treasury -= stake
        let c = CivCampaign(id: (campaign?.id ?? 0) + 1, nation: nation, foe: foe, stake: stake)
        campaign = c
        return c
    }

    /// The battle is over: its result reaches the world once (asking again changes nothing). A win returns
    /// the stake doubled, wears the enemy down and may end the war; a loss loses the stake and wears us down.
    @discardableResult public func settleCampaign(won: Bool) -> Bool {
        guard var c = campaign, !c.settled else { return false }
        c.settled = true; c.won = won
        campaign = c
        if won {
            polities[c.nation]?.treasury += c.stake * 2
            polities[c.foe]?.fatigue += 0.5
            if (polities[c.foe]?.fatigue ?? 0) > 0.8 { makePeace(c.nation, c.foe) }
        } else { polities[c.nation]?.fatigue += 0.3 }
        say(won ? "campaign_won" : "campaign_lost", [polities[c.nation]?.nameEn ?? "", polities[c.nation]?.nameZh ?? "", polities[c.foe]?.nameEn ?? "", polities[c.foe]?.nameZh ?? ""], [c.nation, c.foe])
        return true
    }
}

extension Society {
    /// Who is to be seen on a storey: families living on that storey of a house, asleep in its beds.
    /// (Awake, they are about the town on the ground like everyone else.)
    public func storeyView(storey n: Int, center: Vec2, halfW: Double, halfH: Double) -> (shown: [Agent], at: [Int: Vec2]) {
        var shown: [Agent] = [], at: [Int: Vec2] = [:]
        guard n > 0 else { return (shown, at) }
        let now = world.time
        for s in settlements.values.sorted(by: { $0.id < $1.id }) where !s.abandoned {
            guard abs(s.center.center.x - center.x) < halfW + 800, abs(s.center.center.y - center.y) < halfH + 800 else { continue }
            for b in s.buildings where b.type == "house" && (b.levels ?? 1) > n {
                guard let up = b.upstairs, n - 1 < up.count else { continue }
                let hid = up[n - 1]
                var k = 0
                for id in b.residents.sorted() {
                    guard let a = agents[id], a.sleeping, a.home == b.id, household(a, now) == hid else { continue }
                    // the two beds first, then the floor beside them
                    let spots = [TilePos(b.x + b.w - 2, b.y + 1), TilePos(b.x + 1, b.y + b.h - 2), TilePos(b.x + b.w - 3, b.y + 1), TilePos(b.x + 2, b.y + b.h - 2), TilePos(b.x + b.w / 2, b.y + b.h / 2)]
                    let p = spots[min(k, spots.count - 1)].center
                    k += 1
                    if abs(p.x - center.x) <= halfW && abs(p.y - center.y) <= halfH { shown.append(a); at[a.id] = p }
                }
            }
        }
        return (shown, at)
    }

    /// A shown city's towers stand in its town as real buildings, every level of them: the ground floor
    /// and the first storey are built at once; the rest are the tower's own floors, made storey by storey
    /// as someone comes near them (`stampTowers`). A tower of 400 floors has a 400th storey you can stand
    /// on, and looking at it builds none of the 398 under it.
    func raiseTowers(of city: CivCity, in s: Settlement, _ c: Civ) {
        var k = (realm.standing ?? []).filter { $0.town == s.id }.count
        for t in c.towers(of: city.id) where t.real != true && k < 2 {
            let n = t.floors.filter { $0.stage == .inUse }.count
            guard n >= 2 else { continue }
            let o = TilePos(s.center.x + 12 + k * 16, s.center.y - 16)
            let st = StandingTower(tower: t.id, city: city.id, town: s.id, x: o.x, y: o.y, w: 12, d: 10, levels: n)
            realm.standing = (realm.standing ?? []) + [st]
            raiseHouse(at: o, storeys: 2, w: 12, d: 10)
            realm.storeyTop = max(realm.storeyTop ?? 0, n - 1)
            t.real = true
            k += 1
            emit("tower_seen", [t.nameZh.isEmpty || !zh ? t.nameEn : t.nameZh, "\(n)"], o.center)
        }
    }

    /// A force standing in the region of its own nation's shown town lends some of its people to the
    /// town's garrison: real soldiers, counted out of the force and into the town.
    func showForces(_ c: Civ) {
        for f in c.forces.values.sorted(by: { $0.id < $1.id }) where f.layer == .ground && f.lent == nil {
            guard let city = c.cities.values.filter({ $0.nation == f.nation && $0.regionKey == f.region && $0.shownAs != nil }).min(by: { $0.id < $1.id }),
                  let s = settlements[city.shownAs!], !s.abandoned, agents.count + 12 < world.budget.maxAgents else { continue }
            let k = min(8, f.crew.band(1) / 2)
            guard k >= 2, let g = garrison(s, create: true) else { continue }
            let lent = f.crew.takeAdults(k)
            for st in 0..<6 { for i in 0..<lent.n[6 + st] {
                let a = newAgent(s, age: rng.range(19, 40), female: i % 2 == 1)
                a.nation = f.nation; a.lent = f.id
                setHunger(a, state: st)
                enlist(a, g)
            } }
            f.lent = lent.total; f.lentTown = s.id
            c.totals.toDetail = (c.totals.toDetail ?? 0) + lent.total
        }
    }

    /// An enemy force standing in the region of a shown town it is at war with makes camp near it: its
    /// soldiers become real, under their own flag, the two nations are at war here too, and from then on
    /// the army that forms, the march, the siege and the storming are the detailed world's own.
    func showInvaders(_ c: Civ) {
        for f in c.forces.values.sorted(by: { $0.id < $1.id }) where f.layer == .ground && f.lent == nil {
            guard let city = c.cities.values.filter({ $0.regionKey == f.region && $0.shownAs != nil && c.atWar($0.nation, f.nation) }).min(by: { $0.id < $1.id }),
                  let town = settlements[city.shownAs!], !town.abandoned, let p = c.polities[f.nation],
                  agents.count + 14 < world.budget.maxAgents, settlements.values.filter({ !$0.abandoned }).count < world.budget.maxSettlements else { continue }
            let k = min(12, f.crew.band(1) * 2 / 3)
            guard k >= realm.cfg.minAttack + 2 else { continue }
            let site = world.findSite(from: town.center, minR: 45, maxR: 90, salt: 9100 + f.id, avoid: settlements.values.filter { !$0.abandoned }.map { $0.center }, avoidDist: 40)
            if site.isNone { continue }
            if realm.nation(f.nation) == nil {
                var n = Nation(); n.id = p.id; n.nameEn = p.nameEn; n.nameZh = p.nameZh; n.color = p.color; n.techCount = legacyTech; n.regional = true
                realm.nations.append(n)
            }
            let camp = foundSettlement(site)
            camp.nation = f.nation; camp.campOf = f.id
            camp.nameEn = p.nameEn + " camp"; camp.nameZh = p.nameZh + "军营"
            guard let g = garrison(camp, create: true) else { continue }
            let lent = f.crew.takeAdults(k)
            var i = 0
            for st in 0..<6 { for _ in 0..<lent.n[6 + st] {
                let a = newAgent(camp, age: rng.range(19, 40), female: i % 3 == 0); a.nation = f.nation; a.lent = f.id
                setHunger(a, state: st)
                enlist(a, g); i += 1
            } }
            // the camp eats what the force carries: twelve days for those who came, out of its own rations
            var goods: [String: Double] = [:], food = 0.0
            for key in CivFood.eatOrder.reversed() where food < Double(k) * 12 {
                guard let def = CivFood.byKey[key], let have = f.food[key], have > 0 else { continue }
                let u = min(have, (Double(k) * 12 - food) / def.nutrition)
                f.food[key] = have - u; goods[key] = u; food += u * def.nutrition
                c.totals.goodsToDetail = c.totals.goodsToDetail ?? [:]; c.totals.goodsToDetail![key, default: 0] += u
            }
            camp.food = food; camp.wood = 0; camp.goodsFromCiv = goods
            // its guns are the guns of its own machines (a force of people alone brings none); they are
            // the machines' own and go back with them, never into anyone's stores
            let guns = f.units.compactMap { c.units[$0] }.filter { (CivUnitDef.byKey[$0.kind]?.size ?? .person) != .person && $0.layer == .ground }.count
            if guns > 0 { camp.addGood("engines", Double(min(2, guns))) }
            f.lent = lent.total; f.lentTown = camp.id
            c.totals.toDetail = (c.totals.toDetail ?? 0) + lent.total
            // the war is fought here as well
            let r = realm.meet(f.nation, town.nation ?? 0, at: world.time)
            if realm.relations[r].state != 1 { realm.relations[r].since = -1e9; setState(r, 1) }
            if let k2 = realm.ni(f.nation) { realm.nations[k2].exileSince = nil; realm.nations[k2].fatigue = 0 }
            refreshNations()
            emit("invaders", [p.name(zh: zh), town.name(zh: zh)], site.center, nations: [f.nation, town.nation ?? 0], city: town.id, cause: "regional war", result: "camp")
            return
        }
    }

    /// A camp left far behind (with no army of its own in the field) is struck: its survivors go back to their force.
    func foldCamps(_ c: Civ, from t: TilePos) {
        let (rx, ry) = Civ.regionOf(tile: t, size: c.cfg.regionTiles)
        for s in settlements.values.sorted(by: { $0.id < $1.id }) where !s.abandoned {
            guard let fid = s.campOf else { continue }
            let (sx, sy) = Civ.regionOf(tile: s.center, size: c.cfg.regionTiles)
            guard abs(sx - rx) > 3 || abs(sy - ry) > 3 else { continue }
            if realm.legions.contains(where: { $0.nation == s.nation && $0.state != 0 }) { continue }
            let alive = agents.values.filter { $0.sid == s.id }.sorted { $0.id < $1.id }
            // they go back as hungry (or as fed) as they are
            var back = CivPeople()
            for a in alive { back.n[6 + peopleSlot(a, world.time) % 6] += 1 }
            for a in alive { abort(a, s); leaveHome(a, s); agents[a.id] = nil }
            s.members = []
            c.totals.fromDetail = (c.totals.fromDetail ?? 0) + alive.count
            let left = foodBack(s)
            if let f = c.forces[fid] {
                f.crew.add(back); f.lent = nil; f.lentTown = nil
                for (k, v) in left.sorted(by: { $0.key < $1.key }) where v > 0 { f.food[k, default: 0] += v; c.totals.goodsFromDetail = c.totals.goodsFromDetail ?? [:]; c.totals.goodsFromDetail![k, default: 0] += v }
            }
            else if let home = c.cities.values.filter({ $0.nation == s.nation && $0.detail == nil }).min(by: { $0.id < $1.id }) {
                home.people.add(back)
                for (k, v) in left.sorted(by: { $0.key < $1.key }) where v > 0 { home.stock[k, default: 0] += v; c.totals.goodsFromDetail = c.totals.goodsFromDetail ?? [:]; c.totals.goodsFromDetail![k, default: 0] += v }
            }
            else { c.totals.deaths["battle", default: 0] += alive.count }
            s.food = 0; s.goodsFromCiv = nil; s.goods?["engines"] = nil
            s.abandoned = true; detach(s)
            invalidateGrid(); repairReferences()
        }
    }

    /// A shown town that changed hands in the detailed world changes hands in the regional layer too
    /// (taken by storm, gone over, handed back): one owner, in both.
    func syncShownOwners(_ c: Civ) {
        for s in settlements.values.sorted(by: { $0.id < $1.id }) where !s.abandoned {
            guard let cid = s.fromCiv, let city = c.cities[cid], let n = s.nation, n != city.nation, c.polities[n] != nil else { continue }
            let old = city.nation
            c.transfer(city, to: n)
            c.say("captured", [c.polities[n]?.nameEn ?? "", c.polities[n]?.nameZh ?? "", city.nameEn, city.nameZh, c.polities[old]?.nameEn ?? "", c.polities[old]?.nameZh ?? ""], [n, old], region: city.regionKey)
        }
    }

    /// Machines of forces standing where a shown town is, for the views to draw: kind, nation colour, place.
    public func machinesInView() -> [(id: Int, kind: String, color: String, pos: Vec2, layer: CivLayer)] {
        guard let c = realm.civBox else { return [] }
        var out: [(Int, String, String, Vec2, CivLayer)] = []
        for f in c.forces.values.sorted(by: { $0.id < $1.id }) {
            guard let city = c.cities.values.filter({ $0.regionKey == f.region && $0.shownAs != nil }).min(by: { $0.id < $1.id }), let s = settlements[city.shownAs!], !s.abandoned else { continue }
            let col = c.polities[f.nation]?.color ?? "#ffffff"
            for (i, uid) in f.units.sorted().enumerated() {
                guard let u = c.units[uid] else { continue }
                let p = TilePos(s.center.x - 14 + (i % 5) * 6, s.center.y + 14 + (i / 5) * 6 + (f.nation == city.nation ? 0 : 12))
                out.append((uid, u.kind, col, p.center, u.layer))
            }
        }
        return out
    }
}

public extension PixelArt {
    /// A machine of the regional wars seen from above, 48 x 48, in its nation's colour: the frame is a
    /// tall figure with shoulders and a lance, a carrier a long hull with a deck line and island, a sky
    /// carrier a broad winged hull, aircraft darts, ships hulls, vehicles boxes with a barrel, people a squad of dots.
    static func civUnit(_ kind: String, color: RGBA) -> Bitmap {
        var b = Bitmap(48, 48)
        let dark = color.darkened(0.35), light = color.lightened(0.3), steel = RGBA(120, 126, 140), ink = RGBA(30, 32, 44)
        let def = CivUnitDef.byKey[kind]
        if def?.hangarBay != nil && def?.layer == .sea {
            b.rect(6, 18, 36, 12, steel); b.rect(4, 21, 2, 6, steel); b.rect(42, 20, 3, 8, steel)
            b.rect(8, 23, 32, 1, .white); b.rect(30, 14, 6, 4, dark); b.rect(10, 19, 4, 3, color); b.rect(18, 26, 4, 3, color)
        } else if def?.hangarBay != nil {
            b.rect(10, 16, 28, 16, steel); b.rect(2, 20, 8, 8, dark); b.rect(38, 20, 8, 8, dark)
            b.rect(14, 12, 20, 4, light); b.rect(20, 22, 8, 4, color); b.rect(12, 30, 4, 4, RGBA(120, 220, 255)); b.rect(32, 30, 4, 4, RGBA(120, 220, 255))
        } else if kind.hasSuffix("frame") || def?.size == .large {
            b.rect(20, 6, 8, 7, light); b.rect(14, 13, 20, 6, color); b.rect(18, 19, 12, 12, dark)
            b.rect(10, 14, 4, 14, steel); b.rect(34, 14, 4, 14, steel); b.rect(18, 31, 5, 12, steel); b.rect(25, 31, 5, 12, steel)
            b.rect(38, 4, 2, 22, RGBA(255, 120, 90)); b.rect(22, 8, 4, 2, RGBA(120, 255, 200))
        } else if def?.layer.air == true {
            b.rect(22, 8, 4, 30, steel); b.rect(10, 22, 28, 4, color); b.rect(18, 34, 12, 3, dark); b.rect(23, 6, 2, 4, light)
        } else if def?.layer == .sea || def?.layer == .underwater {
            b.rect(10, 20, 28, 9, def?.layer == .underwater ? ink : steel); b.rect(6, 22, 4, 5, steel); b.rect(22, 16, 6, 4, color)
        } else if def?.size == .vehicle {
            b.rect(12, 18, 24, 16, dark); b.rect(16, 20, 16, 10, color); b.rect(23, 6, 3, 16, steel); b.rect(10, 16, 4, 20, ink); b.rect(34, 16, 4, 20, ink)
        } else {
            for (x, y) in [(14, 16), (24, 14), (34, 16), (18, 28), (30, 28), (24, 36)] { b.disc(Double(x), Double(y), 3.2, color); b.disc(Double(x), Double(y) - 3, 2, RGBA(240, 210, 180)) }
        }
        return b
    }
}
