import Foundation

/// The player is a free traveller who may join a nation. Everything here changes
/// the simulation itself: stocks, supply lines, armies and how nations feel.
extension Society {
    public struct NationInfo {
        public var id = 0, name = "", color = "", leader = "", tech = ""
        public var pop = 0, identity = 0, towns = 0, soldiers = 0
        public var food = 0.0, pressure = 0.0, pFood = 0.0, pHousing = 0.0, pJobs = 0.0, pLand = 0.0, fatigue = 0.0, rep = 0.0, share = 0.0
        public var landless = false, atWar = false
    }
    public struct RelationInfo { public var a = "", b = "", ca = "", cb = "", state = 0, value = 0.0, pact = false, years = 0.0 }

    public func nationInfos() -> [NationInfo] {
        realm.nations.map { n in
            var i = NationInfo()
            i.id = n.id; i.name = n.name(zh: zh); i.color = n.color
            i.leader = agents[n.leader]?.name(zh: zh) ?? "-"
            i.tech = n.techCount > 0 ? techName(n.techCount - 1) : "-"
            i.pop = n.pop; i.identity = n.identity; i.towns = n.towns; i.soldiers = n.soldiers; i.food = n.food
            i.pressure = n.pressure; i.pFood = n.pFood; i.pHousing = n.pHousing; i.pJobs = n.pJobs; i.pLand = n.pLand
            i.fatigue = n.fatigue; i.rep = n.rep; i.share = powerShare(n.id); i.landless = n.exileSince != nil; i.atWar = realm.atWar(n.id)
            return i
        }
    }

    public func relationInfos() -> [RelationInfo] {
        realm.relations.map { r in
            let a = realm.nation(r.a), b = realm.nation(r.b)
            return RelationInfo(a: a?.name(zh: zh) ?? "", b: b?.name(zh: zh) ?? "", ca: a?.color ?? "", cb: b?.color ?? "",
                                state: r.state, value: r.value, pact: r.pact, years: (world.time - r.since) / MP.year)
        }
    }

    /// 0 three nations, 1 unified, 2 restarting; with years in that state and unity's fracture.
    public var eraInfo: (era: Int, years: Double, unifier: String, fracture: Double, intensity: Double) {
        (realm.era, (world.time - realm.eraSince) / MP.year, realm.nation(realm.unifier)?.name(zh: zh) ?? "", realm.fracture,
         realm.intensity / Double(max(1, agents.count)))
    }

    /// Nation in charge of an agent right now: the army they serve, else the town they live in.
    public func side(of a: Agent) -> Int {
        if let l = a.legion, let lg = realm.legion(l) { return lg.nation }
        return settlements[a.sid]?.nation ?? 0
    }

    public func hostileToPlayer(_ nation: Int) -> Bool {
        guard nation != 0, let n = realm.nation(nation) else { return false }
        if realm.player.nation != 0 && realm.atWar(realm.player.nation, nation) { return true }
        return n.rep <= realm.cfg.hostileRep
    }

    func addRep(_ nation: Int, _ v: Double) { if let k = realm.ni(nation) { realm.nations[k].rep = min(1, max(-1, realm.nations[k].rep + v)) } }
    func shiftRelation(_ a: Int, _ b: Int, _ v: Double) { if let r = realm.ri(a, b) { realm.relations[r].value = min(1, max(-1, realm.relations[r].value + v)) } }

    public func playerJoin(_ nation: Int) {
        guard nation == 0 || realm.nation(nation) != nil else { return }
        let old = realm.player.nation
        realm.player.nation = nation
        if old != 0 && old != nation { addRep(old, -0.2) }
        if nation != 0 { addRep(nation, 0.2) }
    }

    // MARK: fighting
    /// (damage, reach in pixels, cooldown in seconds, kind: 0 melee arc, 1 arrow, 2 blast)
    public static let weaponStats: [String: (Double, Double, Double, Int)] = [
        "": (12, 20, 0.45, 0), "sword": (48, 30, 0.5, 0), "axe": (36, 26, 0.6, 0), "pick": (30, 26, 0.6, 0),
        "bow": (34, 170, 0.8, 1), "staff": (42, 110, 1.1, 2),
    ]
    public struct StrikeResult {
        public var onCooldown = false
        public var hits: [(id: Int, pos: Vec2, damage: Double, dead: Bool)] = []
        public var spared = 0                  // allies in the way: no friendly fire
        public var gained = "", amount = 0.0   // harvested resource
        public var demolished = ""
        public var impact = Vec2.zero
    }

    /// One attack with the held weapon. `clock` is real time in seconds.
    public func playerStrike(from pos: Vec2, dir: Vec2, weapon: String, clock: Double) -> StrikeResult {
        var out = StrikeResult()
        let st = Society.weaponStats[weapon] ?? Society.weaponStats[""]!
        if clock < realm.player.nextAttack { out.onCooldown = true; return out }
        realm.player.nextAttack = clock + st.2
        let d = dir.length > 0.01 ? dir.normalized : Vec2(0, 1)
        var victims: [Agent] = []
        let all = agents.values.filter { abs($0.pos.x - pos.x) < 220 && abs($0.pos.y - pos.y) < 220 }.sorted { $0.id < $1.id }
        switch st.3 {
        case 0:
            out.impact = pos + d * (st.1 * 0.7)
            victims = all.filter { let v = $0.pos - pos; return v.length <= st.1 && (v.length < 8 || (v.normalized.x * d.x + v.normalized.y * d.y) > 0.35) }
        case 1:
            // first body along the arrow's path
            var best: Agent?, bestT = st.1
            for a in all {
                let v = a.pos - pos
                let t = v.x * d.x + v.y * d.y
                if t < 4 || t > bestT { continue }
                let off = abs(v.x * d.y - v.y * d.x)
                if off <= 9 { best = a; bestT = t }
            }
            out.impact = pos + d * bestT
            if let b = best { victims = [b] }
        default:
            out.impact = pos + d * st.1
            victims = all.filter { $0.pos.distance(to: out.impact) <= 26 }
        }
        for a in victims {
            let s = side(of: a)
            if realm.player.nation != 0 && s == realm.player.nation { out.spared += 1; continue }
            let hp = (a.hp ?? realm.cfg.civilianHP) - st.0
            let soldier = a.legion != nil
            if hp <= 0 {
                out.hits.append((a.id, a.pos, st.0, true))
                die(a, "battle")
                realm.player.kills += 1
                addRep(s, soldier ? -0.12 : -0.3)
                if realm.player.nation != 0 {
                    if realm.atWar(realm.player.nation, s) { addRep(realm.player.nation, 0.04) } else { shiftRelation(realm.player.nation, s, -0.12) }
                }
            } else {
                a.hp = hp
                out.hits.append((a.id, a.pos, st.0, false))
                addRep(s, soldier ? -0.04 : -0.1)
                if realm.player.nation != 0 && !realm.atWar(realm.player.nation, s) { shiftRelation(realm.player.nation, s, -0.03) }
            }
        }
        if !victims.isEmpty || st.3 != 0 { return out }
        // nothing to fight: tools work on the tile in front
        let t = (pos + d * 16).tile
        let o = world.tile(2, t.x, t.y)
        if (weapon == "axe" || weapon == "sword"), o != 0, let td = content.tile(o), td.big || o == T["cactus"] {
            world.setTile(2, t.x, t.y, content.tid(td.after))
            realm.player.wood += 3; out.gained = "wood"; out.amount = 3
        } else if weapon == "pick" && o == T["rock"] {
            world.setTile(2, t.x, t.y, 0)
            world.schedule(t.x, t.y, layer: 2, to: T["rock"]!, delay: 700, expect: 0)
            realm.player.stone += 3; out.gained = "stone"; out.amount = 3
        } else if o == T["berry_bush"] {
            world.setTile(2, t.x, t.y, T["berry_bush_empty"]!)
            realm.player.food += 3; out.gained = "food"; out.amount = 3
        } else if weapon == "pick" || weapon == "axe" {
            out.demolished = playerDemolish(at: t)
        }
        return out
    }

    public struct Threat { public var damage = 0.0, attackers = 0, died = false; public init() {} }
    /// Set by the scene from its own clock while a ward lasts.
    public var playerWarded: Bool { get { wardActive } set { wardActive = newValue } }

    /// Hostile soldiers near the player hurt them. Call every frame with real `dt`.
    public func playerThreat(at pos: Vec2, dt: Double) -> Threat {
        var out = Threat()
        for lg in realm.legions where hostileToPlayer(lg.nation) {
            for id in lg.members { if let a = agents[id], a.pos.distance(to: pos) <= 34 { out.attackers += 1 } }
        }
        if out.attackers == 0 {
            realm.player.hp = min(realm.cfg.playerHP, realm.player.hp + realm.cfg.playerRegen * dt)
            return out
        }
        out.damage = realm.cfg.soldierHit * Double(min(4, out.attackers)) * dt
        return harmPlayer(out)
    }

    /// Focus returns with time. Call every frame.
    public func playerRest(_ dt: Double) { realm.player.focus = min(100, (realm.player.focus ?? 100) + 6 * dt) }

    /// Apply damage to the player unless a ward or god mode stands in the way.
    public func harmPlayer(_ t: Threat, clock: Double = Date().timeIntervalSinceReferenceDate) -> Threat {
        var out = t
        if realm.player.god == true || playerWarded { out.damage = 0; return out }
        realm.player.hp -= out.damage
        if realm.player.hp <= 0 {
            out.died = true
            realm.player.deaths += 1
            realm.player.hp = realm.cfg.playerHP
            realm.player.food = (realm.player.food / 2).rounded(.down); realm.player.wood = (realm.player.wood / 2).rounded(.down); realm.player.stone = (realm.player.stone / 2).rounded(.down)
        }
        return out
    }

    /// A safe place for the player: their nation's oldest town, else any town that is not hostile.
    public func spawnPoint(near pos: Vec2 = .zero) -> Vec2 {
        let towns = settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        var pick = towns.first { $0.nation == realm.player.nation && realm.player.nation != 0 }
        if pick == nil { pick = towns.filter { !hostileToPlayer($0.nation ?? 0) }.min { $0.center.center.distance(to: pos) < $1.center.center.distance(to: pos) } }
        if pick == nil { pick = towns.first }
        guard let s = pick else { return world.findFree(near: pos.tile, maxR: 24).center }
        return world.findFree(near: s.center + TilePos(0, 4), maxR: 10).center
    }

    public func town(near pos: Vec2, radius: Double = 520) -> Settlement? {
        settlements.values.filter { !$0.abandoned && $0.center.center.distance(to: pos) <= radius }
            .min { $0.center.center.distance(to: pos) != $1.center.center.distance(to: pos) ? $0.center.center.distance(to: pos) < $1.center.center.distance(to: pos) : $0.id < $1.id }
    }

    // MARK: giving, building, breaking, sheltering
    /// Hand carried goods to a town. Feeds people, pleases its nation and, for a
    /// player who belongs to another nation, warms relations between the two.
    @discardableResult public func playerDonate(sid: Int, kind: String, amount: Double) -> Double {
        guard let s = settlements[sid], !s.abandoned, amount > 0 else { return 0 }
        var give = 0.0
        switch kind {
        case "food": give = min(amount, realm.player.food); realm.player.food -= give
        case "wood": give = min(amount, realm.player.wood); realm.player.wood -= give
        case "stone": give = min(amount, realm.player.stone); realm.player.stone -= give
        default: return 0
        }
        if give <= 0 { return 0 }
        s.addStock(kind, give)
        let n = s.nation ?? 0
        addRep(n, give / 60)
        if realm.player.nation != 0 && realm.player.nation != n { shiftRelation(realm.player.nation, n, give / 150) }
        s.unrest = max(0, (s.unrest ?? 0) - give / 200)
        return give
    }

    /// "road", "bridge" or "depot". Returns nil on success, otherwise why not.
    public func playerBuild(_ kind: String, at t: TilePos) -> String? {
        let cfg = realm.cfg
        let water = content.water[Int(world.tile(0, t.x, t.y))]
        switch kind {
        case "road":
            if water { return "water" }
            if realm.player.stone < cfg.roadCost { return "stone" }
            if world.tile(1, t.x, t.y) != 0 || world.tile(2, t.x, t.y) != 0 { return "occupied" }
            realm.player.stone -= cfg.roadCost
            world.setTile(1, t.x, t.y, T["cobble_road"]!)
        case "bridge":
            if !water { return "land" }
            if realm.player.wood < cfg.bridgeCost { return "wood" }
            if world.tile(1, t.x, t.y) != 0 { return "occupied" }
            realm.player.wood -= cfg.bridgeCost
            world.setTile(1, t.x, t.y, content.tid("bridge_wood"))
            world.setTile(3, t.x, t.y, 0)
        case "depot":
            if water || world.blocked(t.x, t.y) || world.tile(2, t.x, t.y) != 0 { return "occupied" }
            if realm.player.wood < cfg.depotWood { return "wood" }
            if realm.player.stone < cfg.depotStone { return "stone" }
            realm.player.wood -= cfg.depotWood; realm.player.stone -= cfg.depotStone
            world.setTile(2, t.x, t.y, T["crate"]!)
            let owner = realm.player.nation != 0 ? realm.player.nation : (town(near: t.center, radius: 4000)?.nation ?? 0)
            realm.depots.removeAll { $0.x == t.x && $0.y == t.y }
            realm.depots.append(Depot(x: t.x, y: t.y, nation: owner))
        default: return "unknown"
        }
        for lg in realm.legions { lg.supplyT = 0 }       // supply lines notice at the next army update
        return nil
    }

    /// Break a road, a bridge or a supply depot. Returns what was destroyed ("" if nothing).
    @discardableResult public func playerDemolish(at t: TilePos) -> String {
        var what = ""
        if let i = realm.depots.firstIndex(where: { $0.x == t.x && $0.y == t.y }) {
            let owner = realm.depots[i].nation
            realm.depots.remove(at: i)
            world.setTile(2, t.x, t.y, 0)
            if owner != realm.player.nation { addRep(owner, -0.1) }
            what = "depot"
        } else {
            let l1 = world.tile(1, t.x, t.y)
            if l1 == content.tid("bridge_wood") || l1 == content.tid("bridge_stone") { world.setTile(1, t.x, t.y, 0); what = "bridge" }
            else if l1 == T["cobble_road"] || l1 == T["path"] { world.setTile(1, t.x, t.y, 0); what = "road" }
        }
        if !what.isEmpty { for lg in realm.legions { lg.supplyT = 0 } }
        return what
    }

    public var refugeeCount: Int { agents.values.filter { $0.refugee != nil }.count }

    /// Take refugees into a town: they stop being refugees there and become residents.
    @discardableResult public func playerAcceptRefugees(sid: Int, limit: Int = 12) -> Int {
        guard let s = settlements[sid], !s.abandoned, !hostileToPlayer(s.nation ?? 0) else { return 0 }
        let list = agents.values.filter { $0.refugee != nil }
            .sorted { let da = $0.pos.distance(to: s.center.center), db = $1.pos.distance(to: s.center.center); return da != db ? da < db : $0.id < $1.id }
        var n = 0
        for a in list.prefix(limit) {
            move(a, to: s)
            a.refugee = nil
            a.travelling = true
            a.travelTo = world.findFree(near: s.center + TilePos(a.id % 7 - 3, 3 + a.id % 3), maxR: 6).center
            if let idn = a.nation { addRep(idn, 0.04) }
            n += 1
        }
        if n > 0 { addRep(s.nation ?? 0, 0.02 * Double(n)); s.planT = 0 }
        return n
    }
}
