import Foundation

/// Three nations that rise, fight, tire, unite and break apart again.
/// Everything tunable lives in `RealmConfig`; all randomness comes from the
/// realm's own seeded generator, so a snapshot replays identically.

public struct LogLine: Codable { public var t: Double; public var text: String }

public struct EventRule: Codable, Equatable {
    public var chance: Double      // per year, while the condition holds
    public var duration: Double    // years the effect lasts
    public var cooldown: Double    // years before it can happen to the same nation again
}

public struct RealmConfig: Codable, Equatable {
    // --- population pressure (weights sum to 1)
    public var wFood = 0.35, wHousing = 0.25, wJobs = 0.20, wLand = 0.20
    public var foodPerHead = 6.0           // stock per resident that counts as "enough"
    public var landPerTown = 36.0          // residents one town's land carries comfortably
    public var expansionPressure = 0.45    // above this, towns send settlers out earlier
    public var softPerTown = 24.0, hardPerTown = 32.0   // residents per town: crowding starts / hard cap
    public var hardPopHold = 0.5           // years above the hard cap before a war cycle is forced
    // --- war and peace (years)
    public var warPressure = 0.15          // pressure needed before a nation considers war
    public var warPressureFull = 0.6       // pressure at which the yearly chance below applies in full
    public var warChance = 0.8             // per year at full pressure
    public var minWar = 0.5, minTruce = 1.0, peaceCooldown = 0.5
    public var fatigueDeclareMax = 0.35    // too tired to start a war above this
    public var fatigueSoft = 0.7           // truce once the minimum war time has passed
    public var fatigueHard = 1.0           // truce immediately
    public var intensityHard = 0.12        // recent battle deaths / world population: truce everywhere
    public var intensityHalfLife = 0.4
    public var fatigueDeath = 2.0          // per battle death, divided by the nation's population
    public var fatigueWarYear = 0.25, fatigueHunger = 0.5, fatigueDamage = 0.04, fatigueLostTown = 0.2
    public var fatigueRecovery = 0.5       // per year while not at war
    // --- armies
    public var conscriptBase = 0.12, conscriptPressure = 0.15, conscriptWar = 0.22, conscriptUnified = 0.05
    public var soldierHP = 140.0, civilianHP = 100.0
    public var step = 2.0                  // seconds between army updates (same near and far)
    public var marchSpeed = 34.0           // pixels per second at full supply
    public var lethality = 0.012           // losses per second per point of enemy power
    public var fortify = 1.25              // defenders' advantage
    public var techPower = 0.08            // per technology
    public var minAttack = 3
    public var attackShare = 0.65          // share of a garrison that marches
    public var retreatShare = 0.25         // attackers fall back below this share of their starting strength
    public var fieldUpkeep = 0.012         // food per soldier per second in the field
    public var starveLoss = 0.004          // soldiers lost per soldier-second without food
    public var supplyInterval = 30.0
    public var supplyDistance = 400.0      // tiles at which distance alone halves supply
    public var supplyRoad = 0.25, supplyWater = 0.06, supplyDepot = 0.15, supplyMin = 0.15, supplyMax = 1.2
    public var depotRange = 12
    public var captureDamage = 2, refugeeShare = 0.2, refugeeIntegrate = 1.0
    // --- balance of power
    public var dominance = 0.5, dominanceRelease = 0.42
    public var pactWar = 2.0               // allies declare on the strong nation this much more readily
    public var ambition = 0.5              // yearly chance that a dominant nation presses on, whatever its pressure
    public var governFood = 0.6            // food per occupied resident per year
    public var strongUnrest = 1.5, strongSupply = 0.85
    public var submitFatigue = 0.6, submitShare = 0.15
    // --- unrest, exile, unification
    public var unrestRate = 0.35            // per year at full identity mismatch
    public var unrestGarrison = 2.0        // soldiers per resident that cancel unrest
    public var exileMax = 2.0
    public var restartDelay = 0.25         // years an empty world stays empty before settlers return
    public var unityMin = 1.5, unityMax = 5.0
    public var fractureBase = 0.15, fractureIdentity = 0.6, fractureSuccession = 0.3, fractureIndependence = 0.25
    public var unityResearch = 1.3, unityTrade = 0.05
    public var splitIdentity = 1.0, splitGeography = 0.6, splitMilitary = 0.4
    // --- research
    public var researchScale = 1.5, catchUp = 1.5, breakthroughBoost = 3.0
    // --- events
    public var events: [String: EventRule] = [
        "harvest_good": EventRule(chance: 0.5, duration: 0.5, cooldown: 1.5),
        "harvest_bad": EventRule(chance: 0.35, duration: 0.5, cooldown: 2.0),
        "general": EventRule(chance: 0.4, duration: 1.0, cooldown: 3.0),
        "leader_died": EventRule(chance: 0.25, duration: 0.5, cooldown: 1.0),
        "breakthrough": EventRule(chance: 0.3, duration: 0.3, cooldown: 2.0),
        "town_defect": EventRule(chance: 1.0, duration: 0, cooldown: 1.0),
        "alliance_broken": EventRule(chance: 0.6, duration: 0, cooldown: 1.5),
    ]
    public var harvestBonus = 1.5, harvestLoss = 0.02, generalPower = 1.25
    // --- player
    public var playerHP = 100.0, playerRegen = 2.0, soldierHit = 9.0, hostileRep = -0.5
    public var roadCost = 1.0, bridgeCost = 3.0, depotWood = 8.0, depotStone = 4.0
    // --- technical limits (never left to the war system)
    public var maxGraves = 24, maxLog = 60, maxRuinsPerTown = 40, maxEffects = 120
    public init() {}
}

public struct Nation: Codable {
    public var id = 0
    public var nameEn = "", nameZh = "", color = "#ffffff"
    public var leader = 0
    public var techCount = 0, research = 0.0
    public var fatigue = 0.0
    public var overT = 0.0
    public var exileSince: Double?
    public var rep = 0.0                   // the player's standing with this nation, -1...1
    // refreshed every game hour
    public var pressure = 0.0, pFood = 0.0, pHousing = 0.0, pJobs = 0.0, pLand = 0.0
    public var pop = 0, identity = 0, towns = 0, soldiers = 0, food = 0.0
    public func name(zh: Bool) -> String { zh ? nameZh : nameEn }
}

public struct Relation: Codable {
    public var a = 0, b = 0
    public var value = 0.0                 // -1 hostile ... 1 friendly
    public var state = 0                   // 0 peace, 1 war, 2 truce
    public var since = 0.0
    public var pact = false
}

public final class Legion: Codable {
    public var id = 0, nation = 0, home = 0, target = 0
    public var state = 0                   // 0 garrison, 1 marching, 2 besieging, 3 returning
    public var members: [Int] = []
    public var pos = Vec2.zero
    public var supply = 1.0, supplyT = 0.0, lossAcc = 0.0, defLossAcc = 0.0
    public var startN = 0
    public init() {}
}

public struct Depot: Codable, Equatable { public var x: Int, y: Int, nation: Int }
public struct RealmMod: Codable { public var kind: String, nation: Int, until: Double }
public struct RealmCounts: Codable, Equatable { public var wars = 0, truces = 0, unifications = 0, splits = 0, captures = 0, defections = 0, events = 0 }

public struct PlayerState: Codable {
    public var nation = 0                  // 0 = free traveller
    public var hp = 100.0
    public var food = 0.0, wood = 0.0, stone = 0.0
    public var nextAttack = 0.0
    public var kills = 0, deaths = 0
}

public struct Realm: Codable {
    public var cfg = RealmConfig()
    public var nations: [Nation] = []
    public var relations: [Relation] = []
    public var legions: [Legion] = []
    public var nextLegion = 1
    public var era = 0                     // 0 three nations, 1 unified, 2 civilisation restarting
    public var eraSince = 0.0
    public var unifier = 0
    public var fracture = 0.0
    public var intensity = 0.0
    public var mods: [RealmMod] = []
    public var cool: [String: Double] = [:]
    public var depots: [Depot] = []
    public var counts = RealmCounts()
    public var immigrationHold = 0.0
    public var rng = RNG(seed: 1)
    public var acc = 0.0
    public var player = PlayerState()
    public init() {}

    public func nation(_ id: Int) -> Nation? { nations.first { $0.id == id } }
    func ni(_ id: Int) -> Int? { nations.firstIndex { $0.id == id } }
    public func legion(_ id: Int) -> Legion? { legions.first { $0.id == id } }
    func ri(_ a: Int, _ b: Int) -> Int? { relations.firstIndex { ($0.a == a && $0.b == b) || ($0.a == b && $0.b == a) } }
    public func relation(_ a: Int, _ b: Int) -> Relation? { ri(a, b).map { relations[$0] } }
    public func atWar(_ a: Int, _ b: Int) -> Bool { relation(a, b)?.state == 1 }
    public func atWar(_ a: Int) -> Bool { relations.contains { $0.state == 1 && ($0.a == a || $0.b == a) } }
    public func active(_ kind: String, _ nation: Int, _ now: Double) -> Bool { mods.contains { $0.kind == kind && $0.nation == nation && $0.until > now } }
}

extension Society {
    static let realmText: [String: (String, String)] = [
        "war": ("%@ declared war on %@", "%@ 向 %@ 宣战"), "truce": ("%@ and %@ agreed a truce", "%@ 与 %@ 休战"),
        "peace": ("%@ and %@ are at peace again", "%@ 与 %@ 恢复和平"), "siege": ("%@'s army reached %@", "%@ 的军队兵临 %@"),
        "captured": ("%@ took %@ from %@", "%@ 从 %@ 手中夺取了 %@"), "repelled": ("%@ held against %@", "%@ 击退了 %@ 的进攻"),
        "fell": ("%@ has lost all its land; its people remember", "%@ 失去了全部领土，但国人未忘故国"),
        "unified": ("%@ united the land. An age of unity begins", "%@ 统一了天下，统一时代开始"),
        "split": ("The united realm broke apart: %@, %@ and %@ stand again", "统一王朝分裂：%@、%@、%@ 再度鼎立"),
        "revived": ("%@ rose again at %@", "%@ 在 %@ 复国"), "submitted": ("%@ submitted to %@", "%@ 归附于 %@"),
        "pact": ("%@ and %@ joined against %@", "%@ 与 %@ 结盟对抗 %@"), "alliance_broken": ("The alliance of %@ and %@ fell apart", "%@ 与 %@ 的联盟破裂"),
        "harvest_good": ("Bumper harvest in %@", "%@ 喜获丰收"), "harvest_bad": ("Poor harvest in %@", "%@ 遭遇歉收"),
        "general": ("%@ rose as a general of %@", "%@ 成为 %@ 的名将"), "leader_died": ("%@, leader of %@, has died; %@ succeeds", "%@ 的领袖 %@ 去世，%@ 继位"),
        "breakthrough": ("A breakthrough quickens research in %@", "%@ 出现技术突破"), "town_defect": ("%@ went over to %@", "%@ 倒戈归于 %@"),
        "succession": ("A succession dispute shakes the united realm", "继承争议动摇了统一王朝"), "independence": ("%@ demands independence", "%@ 要求独立"),
        "refugees": ("%@ people fled %@", "%@ 人逃离了 %@"), "restart": ("No one is left. Civilisation must begin again", "世间已无人烟，文明将重新开始"),
        "resettled": ("New settlers begin again as three peoples", "新的移民以三国之名重新开始"), "soldier": ("soldier", "士兵"), "refugee": ("refugee", "难民"),
    ]
    static let nationSeeds: [(String, String, String)] = [("Azure", "青曜", "#4a8af0"), ("Crimson", "赤焰", "#e8504a"), ("Golden", "金穗", "#e8b83a")]

    // MARK: founding
    /// Create the three nations (once) and divide the living towns between them by geography.
    func foundNations() {
        if realm.nations.isEmpty {
            realm.rng = RNG(seed: Int(truncatingIfNeeded: rng.state) ^ 0x5eed)
            for (i, n) in Society.nationSeeds.enumerated() {
                var nat = Nation()
                nat.id = i + 1; nat.nameEn = n.0; nat.nameZh = n.1; nat.color = n.2; nat.techCount = legacyTech
                realm.nations.append(nat)
            }
            realm.relations = [(1, 2), (1, 3), (2, 3)].map { var r = Relation(); r.a = $0.0; r.b = $0.1; r.since = world.time; return r }
            realm.eraSince = world.time
        }
        let towns = settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        let open = towns.filter { ($0.nation ?? 0) == 0 }
        if !open.isEmpty {
            // farthest-point seeds, then nearest seed
            var seeds: [Settlement] = []
            for n in realm.nations { if let t = towns.first(where: { $0.nation == n.id }) { seeds.append(t) } }
            var free = realm.nations.map { $0.id }.filter { id in !towns.contains { $0.nation == id } }
            var pool = open
            while !free.isEmpty && !pool.isEmpty {
                let pick: Settlement
                if seeds.isEmpty { pick = pool[0] }
                else { pick = pool.max { a, b in
                    let da = seeds.map { ($0.center - a.center).lengthSquared }.min()!, db = seeds.map { ($0.center - b.center).lengthSquared }.min()!
                    return da != db ? da < db : a.id > b.id }! }
                pick.nation = free.removeFirst()
                seeds.append(pick)
                pool.removeAll { $0 === pick }
            }
            for t in pool {
                let near = seeds.min { a, b in
                    let da = (a.center - t.center).lengthSquared, db = (b.center - t.center).lengthSquared
                    return da != db ? da < db : a.id < b.id }
                t.nation = near?.nation ?? realm.nations[0].id
            }
        }
        for a in agents.values where a.nation == nil { a.nation = settlements[a.sid]?.nation }
        for k in realm.nations.indices {
            let id = realm.nations[k].id
            if !towns.contains(where: { $0.nation == id }) { if realm.nations[k].exileSince == nil { realm.nations[k].exileSince = world.time } }
            else { realm.nations[k].exileSince = nil }
            if realm.nations[k].leader == 0 || agents[realm.nations[k].leader] == nil { realm.nations[k].leader = pickLeader(id) }
        }
        refreshNations()
    }

    func expeditionNation(_ group: [Agent], _ from: Settlement) -> Int {
        // settlers who mostly belong to a landless nation raise its banner again
        for n in realm.nations where n.exileSince != nil {
            let own = group.filter { $0.nation == n.id }.count
            if own * 2 > group.count {
                if let k = realm.ni(n.id) { realm.nations[k].exileSince = nil }
                emit("revived", [n.name(zh: zh), from.name(zh: zh)], from.center.center)
                return n.id
            }
        }
        return from.nation ?? 0
    }

    func pickLeader(_ nation: Int) -> Int {
        let now = world.time
        let adults = agents.values.filter { $0.stage(now) != "child" }
        var cands = adults.filter { $0.nation == nation && settlements[$0.sid]?.nation == nation }
        if cands.isEmpty { cands = adults.filter { $0.nation == nation } }
        if cands.isEmpty { cands = adults.filter { settlements[$0.sid]?.nation == nation } }   // lawful succession by the residents
        let prime = cands.filter { $0.age(now) < 58 }
        let pool = prime.isEmpty ? cands : prime
        return pool.min { $0.birth != $1.birth ? $0.birth < $1.birth : $0.id < $1.id }?.id ?? 0
    }

    // MARK: queries
    func towns(of nation: Int) -> [Settlement] { settlements.values.filter { !$0.abandoned && $0.nation == nation }.sorted { $0.id < $1.id } }
    func garrison(_ s: Settlement, create: Bool) -> Legion? {
        if let g = realm.legions.first(where: { $0.home == s.id && $0.state == 0 }) { return g }
        guard create else { return nil }
        let g = Legion()
        g.id = realm.nextLegion; realm.nextLegion += 1
        g.nation = s.nation ?? 0; g.home = s.id; g.pos = s.center.center
        realm.legions.append(g)
        return g
    }
    func identityShare(_ s: Settlement, _ nation: Int) -> Double {
        if s.members.isEmpty { return 0 }
        return Double(s.members.filter { agents[$0]?.nation == nation }.count) / Double(s.members.count)
    }
    func majorityIdentity(_ s: Settlement) -> Int {
        var c: [Int: Int] = [:]
        for id in s.members { if let n = agents[id]?.nation { c[n, default: 0] += 1 } }
        return c.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? (s.nation ?? 0)
    }
    func power(_ n: Nation) -> Double { Double(n.pop) + 2 * Double(n.soldiers) }
    func powerShare(_ id: Int) -> Double {
        let total = realm.nations.reduce(0) { $0 + power($1) }
        guard total > 0, let n = realm.nation(id) else { return 0 }
        return power(n) / total
    }

    /// Population pressure is about food, housing, work and land together, not head count.
    func refreshNations() {
        let cfg = realm.cfg
        let now = world.time
        for k in realm.nations.indices {
            let id = realm.nations[k].id
            let ts = towns(of: id)
            var pop = 0, homeless = 0, workers = 0, soldiers = 0
            var food = 0.0, slots = 0.0
            for s in ts {
                food += s.food
                slots += Double(s.count("farm", done: true)) * 2 + min(20, Double(s.trees.count + s.rocks.count + s.berries.count) / 2) + 3
                for mid in s.members {
                    guard let a = agents[mid] else { continue }
                    pop += 1
                    if a.home < 0 { homeless += 1 }
                    if a.legion != nil { soldiers += 1 } else if a.stage(now) == "adult" { workers += 1 }
                }
            }
            for lg in realm.legions where lg.nation == id && lg.state != 0 { soldiers += lg.members.filter { agents[$0] != nil && !(settlements[agents[$0]!.sid]?.nation == id) }.count }
            let p = max(1, Double(pop))
            var n = realm.nations[k]
            n.pop = pop; n.towns = ts.count; n.soldiers = soldiers; n.food = food
            n.identity = agents.values.filter { $0.nation == id }.count
            n.pFood = pop == 0 ? 0 : min(1, max(0, 1 - food / (p * cfg.foodPerHead)))
            n.pHousing = pop == 0 ? 0 : Double(homeless) / p
            n.pJobs = workers == 0 ? 0 : min(1, max(0, (Double(workers) - slots) / Double(workers)))
            n.pLand = ts.isEmpty ? 0 : min(1, max(0, p / (Double(ts.count) * cfg.landPerTown) - 0.4) / 0.8)
            n.pressure = cfg.wFood * n.pFood + cfg.wHousing * n.pHousing + cfg.wJobs * n.pJobs + cfg.wLand * n.pLand
            let soft = cfg.softPerTown * Double(max(1, ts.count)), hard = cfg.hardPerTown * Double(max(1, ts.count))
            if p > soft { n.pressure += 0.3 * min(1, (p - soft) / max(1, hard - soft)) }
            realm.nations[k] = n
        }
    }

    // MARK: armies (one model for near and far: the camera never changes an outcome)
    func follow(_ a: Agent, _ lg: Legion, _ dt: Double) {
        // soldiers in the field keep formation around their legion; fighting itself is resolved per legion
        let k = lg.members.firstIndex(of: a.id) ?? 0
        let ring = 10.0 + Double(k / 8) * 9
        let ang = Double(k % 8) / 8 * 2 * Double.pi + (lg.state == 2 ? world.time * 0.9 + Double(a.id) : 0)
        let slot = lg.pos + Vec2(cos(ang) * ring, sin(ang) * ring * 0.7)
        let to = slot - a.pos
        let stepLen = Society.speed * 1.6 * dt
        a.sleeping = false
        if to.length > 600 { a.pos = slot; return }          // far behind (e.g. just loaded): catch up at once
        if to.length <= stepLen { a.pos = slot } else { a.pos = a.pos + to.normalized * stepLen; a.moving = true; a.facing = to.normalized }
        a.hunger = min(a.hunger, 0.5)                         // fed from the supply line, not from the village pot
    }

    func move(_ a: Agent, to ns: Settlement) {
        guard let s = settlements[a.sid], s !== ns else { return }
        abort(a, s)
        leaveHome(a, s)
        s.members.removeAll { $0 == a.id }
        ns.members.append(a.id)
        a.sid = ns.id
    }

    func enlist(_ a: Agent, _ g: Legion) {
        if let s = settlements[a.sid] { abort(a, s) }
        a.legion = g.id; a.job = "soldier"; a.hp = realm.cfg.soldierHP
        g.members.append(a.id)
    }

    func discharge(_ a: Agent) {
        if let lid = a.legion, let g = realm.legion(lid) { g.members.removeAll { $0 == a.id } }
        a.legion = nil; a.job = ""; a.hp = nil
    }

    func conscription() {
        let cfg = realm.cfg
        let now = world.time
        for s in settlements.values.filter({ !$0.abandoned }).sorted(by: { $0.id < $1.id }) {
            guard let nid = s.nation, let n = realm.nation(nid) else { continue }
            let adults = s.members.compactMap { agents[$0] }.filter { let g = $0.age(now); return g >= 18 && g <= 50 && $0.refugee == nil }
            let serving = adults.filter { $0.legion != nil }
            var rate = cfg.conscriptBase + cfg.conscriptPressure * min(1, n.pressure) + (realm.atWar(nid) ? cfg.conscriptWar : 0)
            if realm.era == 1 { rate = cfg.conscriptUnified }
            let target = adults.count >= 8 ? max(2, Int(Double(adults.count) * rate)) : 0
            if serving.count < target {
                let g = garrison(s, create: true)!
                g.nation = nid
                var need = min(2, target - serving.count)
                for a in adults.sorted(by: { $0.id < $1.id }) where need > 0 && a.legion == nil && a.pregnantDue < 0 && !a.travelling && a.age(now) <= 45 {
                    enlist(a, g); need -= 1
                }
            } else if serving.count > target + 1 && !realm.atWar(nid), let g = garrison(s, create: false), let last = g.members.last, let a = agents[last] {
                discharge(a)
            }
        }
    }

    /// Supply along the straight line home: distance hurts, roads and depots help,
    /// water without a bridge hurts. Players change this by building or breaking them.
    public func supply(from: TilePos, to: TilePos, nation: Int) -> Double {
        let cfg = realm.cfg
        let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
        let dist = max(1, (dx * dx + dy * dy).squareRoot())
        let n = Int(dist)
        var road = 0, wetRuns = 0
        var inWater = false
        let px = -dy / dist, py = dx / dist
        let roadIDs: Set<UInt8> = [T["cobble_road"]!, T["path"]!, content.tid("bridge_wood"), content.tid("bridge_stone")]
        for i in 0...n {
            let x = Double(from.x) + dx * Double(i) / dist, y = Double(from.y) + dy * Double(i) / dist
            var onRoad = false, wet = false
            let cx = Int(x.rounded()), cy = Int(y.rounded())
            wet = content.water[Int(world.tile(0, cx, cy))]
            for o in [0.0, 1, -1, 2, -2] {
                let tx = Int((x + px * o).rounded()), ty = Int((y + py * o).rounded())
                if roadIDs.contains(world.tile(1, tx, ty)) { onRoad = true; break }
            }
            if onRoad { road += 1; inWater = false }
            else if wet { if !inWater { wetRuns += 1 }; inWater = true }
            else { inWater = false }
        }
        var v = 1 - min(0.5, dist / cfg.supplyDistance * 0.5)
        v += cfg.supplyRoad * Double(road) / Double(n + 1)
        v -= min(0.5, cfg.supplyWater * Double(wetRuns))
        var depots = 0
        for d in realm.depots where d.nation == nation {
            // distance from the depot to the segment
            let t = max(0, min(1, (Double(d.x - from.x) * dx + Double(d.y - from.y) * dy) / (dist * dist)))
            let ex = Double(from.x) + dx * t - Double(d.x), ey = Double(from.y) + dy * t - Double(d.y)
            if ex * ex + ey * ey <= Double(cfg.depotRange * cfg.depotRange) { depots += 1 }
        }
        v += cfg.supplyDepot * Double(min(2, depots))
        if powerShare(nation) > cfg.dominance { v *= cfg.strongSupply }
        return min(cfg.supplyMax, max(cfg.supplyMin, v))
    }

    func legionPower(_ lg: Legion, defending: Bool) -> Double {
        let cfg = realm.cfg
        guard let n = realm.nation(lg.nation) else { return 0 }
        var p = Double(lg.members.count) * (1 + cfg.techPower * Double(n.techCount)) * (1 - 0.3 * min(1, n.fatigue))
        if realm.active("general", lg.nation, world.time) { p *= cfg.generalPower }
        p *= defending ? cfg.fortify : lg.supply
        return p
    }

    func addFatigue(_ nation: Int, _ v: Double) {
        if let k = realm.ni(nation) { realm.nations[k].fatigue = min(1.5, max(0, realm.nations[k].fatigue + v)) }
    }

    func kill(from lg: Legion, _ count: Int) {
        for _ in 0..<count {
            guard !lg.members.isEmpty else { return }
            let id = lg.members[realm.rng.index(lg.members.count)]
            if let a = agents[id] { die(a, "battle") } else { lg.members.removeAll { $0 == id } }
        }
    }

    func muster(_ nid: Int, against enemy: Int) {
        let cfg = realm.cfg
        if realm.legions.contains(where: { $0.nation == nid && $0.state != 0 }) { return }
        let mine = towns(of: nid), theirs = towns(of: enemy)
        guard !mine.isEmpty, !theirs.isEmpty else { return }
        var best: (Settlement, Settlement, Int)?
        for h in mine {
            guard let g = garrison(h, create: false), g.members.count >= cfg.minAttack + 1 else { continue }
            for t in theirs {
                let d = (h.center - t.center).lengthSquared
                if best == nil || d < best!.2 { best = (h, t, d) }
            }
        }
        guard let (home, target, _) = best else { return }
        // every garrison sends its share; the army gathers at the town nearest the enemy
        var moving: [Int] = []
        for h in mine {
            guard let g = garrison(h, create: false), g.members.count >= 2 else { continue }
            let take = min(g.members.count - 1, Int((Double(g.members.count) * cfg.attackShare).rounded()))
            let ids = Array(g.members.sorted().prefix(take))
            g.members.removeAll { ids.contains($0) }
            moving += ids
        }
        if moving.count < cfg.minAttack {
            for id in moving { if let a = agents[id], let h = settlements[a.sid], let g = garrison(h, create: true) { g.members.append(id) } }
            return
        }
        let lg = Legion()
        lg.id = realm.nextLegion; realm.nextLegion += 1
        lg.nation = nid; lg.home = home.id; lg.target = target.id; lg.state = 1; lg.pos = home.center.center
        for id in moving { if let a = agents[id] { if let s = settlements[a.sid] { abort(a, s) }; a.legion = lg.id; lg.members.append(id) } }
        lg.startN = lg.members.count
        lg.supply = supply(from: home.center, to: target.center, nation: nid)
        lg.supplyT = world.time + cfg.supplyInterval
        realm.legions.append(lg)
    }

    func sendHome(_ lg: Legion) { if lg.state == 1 || lg.state == 2 { lg.state = 3; lg.target = 0 } }

    func disband(_ lg: Legion, into s: Settlement) {
        let g = garrison(s, create: true)!
        if g === lg { return }
        g.nation = s.nation ?? g.nation
        for id in lg.members { if let a = agents[id] { move(a, to: s); a.legion = g.id; if !g.members.contains(id) { g.members.append(id) } } }
        lg.members = []
        realm.legions.removeAll { $0 === lg }
    }

    public func realmTick(_ dt: Double) {
        guard !realm.nations.isEmpty else { return }
        realm.acc += dt
        let cfg = realm.cfg
        while realm.acc >= cfg.step {
            realm.acc -= cfg.step
            for lg in realm.legions.sorted(by: { $0.id < $1.id }) where lg.state != 0 { stepLegion(lg, cfg.step) }
        }
    }

    func stepLegion(_ lg: Legion, _ dt: Double) {
        let cfg = realm.cfg
        lg.members.removeAll { agents[$0] == nil }
        if lg.members.isEmpty { realm.legions.removeAll { $0 === lg }; return }
        // where is home now?
        var home = settlements[lg.home]
        if home == nil || home!.abandoned || home!.nation != lg.nation {
            home = towns(of: lg.nation).min { ($0.center.center - lg.pos).length < ($1.center.center - lg.pos).length }
            if let h = home { lg.home = h.id }
        }
        guard let hm = home else {
            // a landless army lays down its arms where it stands
            if let near = settlements.values.filter({ !$0.abandoned }).min(by: { ($0.center.center - lg.pos).length < ($1.center.center - lg.pos).length }) {
                for id in lg.members { if let a = agents[id] { move(a, to: near); discharge(a); a.refugee = world.time + cfg.refugeeIntegrate * MP.year } }
            }
            realm.legions.removeAll { $0 === lg }
            return
        }
        // supply and upkeep
        if world.time >= lg.supplyT, let t = settlements[lg.target] {
            lg.supply = supply(from: hm.center, to: t.center, nation: lg.nation)
            lg.supplyT = world.time + cfg.supplyInterval
        }
        let need = Double(lg.members.count) * cfg.fieldUpkeep * dt * (2 - min(1, lg.supply))
        if hm.food >= need { hm.food -= need } else {
            hm.food = 0
            lg.lossAcc += Double(lg.members.count) * cfg.starveLoss * dt
            addFatigue(lg.nation, cfg.fatigueHunger * dt / MP.year)
        }
        if lg.state == 3 {
            let to = hm.center.center - lg.pos
            let stepLen = cfg.marchSpeed * dt
            if to.length <= max(40, stepLen) { disband(lg, into: hm) } else { lg.pos = lg.pos + to.normalized * stepLen }
            return
        }
        guard let target = settlements[lg.target], !target.abandoned, let enemy = target.nation, enemy != lg.nation, realm.atWar(lg.nation, enemy) else { sendHome(lg); return }
        if lg.state == 1 {
            let to = target.center.center - lg.pos
            let stepLen = cfg.marchSpeed * (0.5 + 0.5 * min(1, lg.supply)) * dt
            if to.length <= max(48, stepLen) {
                lg.state = 2
                emit("siege", [realm.nation(lg.nation)?.name(zh: zh) ?? "", target.name(zh: zh)], target.center.center)
            } else { lg.pos = lg.pos + to.normalized * stepLen }
            return
        }
        // siege: both sides lose in proportion to the other's power
        let def = garrison(target, create: false)
        def?.members.removeAll { agents[$0] == nil }
        let ap = legionPower(lg, defending: false), dp = def.map { legionPower($0, defending: true) } ?? 0
        lg.lossAcc += cfg.lethality * dp * dt
        lg.defLossAcc += cfg.lethality * ap * dt
        let dl = min(def?.members.count ?? 0, Int(lg.defLossAcc)), al = Int(lg.lossAcc)
        if dl > 0, let d = def { kill(from: d, dl); lg.defLossAcc -= Double(dl) }
        if al > 0 { kill(from: lg, al); lg.lossAcc -= Double(al) }
        if lg.members.isEmpty { realm.legions.removeAll { $0 === lg }; emit("repelled", [target.name(zh: zh), realm.nation(lg.nation)?.name(zh: zh) ?? ""], target.center.center); return }
        if (def?.members.count ?? 0) == 0 { capture(target, by: lg); return }
        if Double(lg.members.count) < max(1, Double(lg.startN) * cfg.retreatShare) {
            emit("repelled", [target.name(zh: zh), realm.nation(lg.nation)?.name(zh: zh) ?? ""], target.center.center)
            sendHome(lg)
        }
    }

    /// Knock holes into finished buildings; builders have to pay and work to repair them.
    @discardableResult func damage(_ s: Settlement, buildings n: Int) -> Int {
        var done = s.buildings.filter { $0.done && $0.type != "farm" }.sorted { $0.id < $1.id }
        var hit = 0
        let rubble = content.tid("rubble")
        var ruins = s.buildings.reduce(0) { $0 + $1.retry.count }
        for _ in 0..<n where !done.isEmpty {
            let b = done.remove(at: realm.rng.index(done.count))
            var solid = b.cells.indices.filter { b.cells[$0].layer == 2 && !b.cells[$0].key.isEmpty && !b.retry.contains($0) }
            var broke = 0
            while broke < 5 && !solid.isEmpty && ruins < realm.cfg.maxRuinsPerTown {
                let ci = solid.remove(at: realm.rng.index(solid.count))
                let t = TilePos(b.x + b.cells[ci].dx, b.y + b.cells[ci].dy)
                world.setTile(2, t.x, t.y, 0)
                if world.tile(3, t.x, t.y) == 0 { world.setTile(3, t.x, t.y, rubble) }
                b.retry.append(ci); b.placed -= 1
                broke += 1; ruins += 1
            }
            if broke > 0 { b.done = false; hit += 1 }
        }
        if hit > 0, let nid = s.nation { addFatigue(nid, realm.cfg.fatigueDamage * Double(hit)); s.planT = 0 }
        return hit
    }

    func flee(_ s: Settlement, share: Double, from old: Int, captor: Int) -> Int {
        let now = world.time
        var dests = towns(of: old).filter { $0 !== s }
        if dests.isEmpty { dests = settlements.values.filter { !$0.abandoned && $0 !== s && $0.nation != captor }.sorted { $0.id < $1.id } }
        guard let dest = dests.min(by: { ($0.center - s.center).lengthSquared < ($1.center - s.center).lengthSquared }) else { return 0 }
        var houses: [Int: [Agent]] = [:]
        for a in s.members.compactMap({ agents[$0] }) where a.legion == nil && a.nation != captor { houses[household(a, now), default: []].append(a) }
        var fled = 0
        let quota = Int(Double(s.members.count) * share)
        for hid in houses.keys.sorted() where fled < quota {
            if realm.rng.unit() > 0.6 { continue }
            for a in houses[hid]! {
                move(a, to: dest)
                a.refugee = now + realm.cfg.refugeeIntegrate * MP.year
                a.job = ""
                a.travelling = true
                a.travelTo = world.findFree(near: dest.center + TilePos(realm.rng.int(-12, 12), realm.rng.int(9, 13)), maxR: 8).center
                fled += 1
            }
        }
        if fled > 0 { emit("refugees", ["\(fled)", s.name(zh: zh)], s.center.center) }
        return fled
    }

    func capture(_ s: Settlement, by lg: Legion) {
        let cfg = realm.cfg
        let old = s.nation ?? 0
        if let g = garrison(s, create: false) { realm.legions.removeAll { $0 === g } }
        s.nation = lg.nation
        s.unrest = 0.3
        damage(s, buildings: cfg.captureDamage)
        _ = flee(s, share: cfg.refugeeShare, from: old, captor: lg.nation)
        // the army stays as the garrison: occupation costs soldiers
        lg.home = s.id; lg.target = 0; lg.state = 0; lg.pos = s.center.center
        for id in lg.members { if let a = agents[id] { move(a, to: s) } }
        addFatigue(old, cfg.fatigueLostTown)
        if let r = realm.ri(old, lg.nation) { realm.relations[r].value = max(-1, realm.relations[r].value - 0.2) }
        realm.counts.captures += 1
        emit("captured", [realm.nation(lg.nation)?.name(zh: zh) ?? "", realm.nation(old)?.name(zh: zh) ?? "", s.name(zh: zh)], s.center.center)
        s.planT = 0
        landCheck()
    }

    /// After any change of ownership: who is landless, is anyone alone on the map?
    func landCheck() {
        let now = world.time
        for k in realm.nations.indices {
            let id = realm.nations[k].id
            let has = !towns(of: id).isEmpty
            if !has && realm.nations[k].exileSince == nil {
                realm.nations[k].exileSince = now
                emit("fell", [realm.nations[k].name(zh: zh)], .zero)
                for r in realm.relations.indices where realm.relations[r].a == id || realm.relations[r].b == id {
                    if realm.relations[r].state == 1 { realm.relations[r].state = 2; realm.relations[r].since = now }
                    realm.relations[r].pact = false
                }
                for lg in realm.legions where lg.state != 0 && settlements[lg.target]?.nation == nil { sendHome(lg) }
            } else if has { realm.nations[k].exileSince = nil }
        }
        let landed = realm.nations.filter { $0.exileSince == nil }
        if realm.era == 0 && landed.count == 1 && livingSettlements >= 1 && agents.count > 0 { startUnity(landed[0].id) }
    }

    // MARK: diplomacy
    func setState(_ r: Int, _ state: Int) {
        let rel = realm.relations[r]
        if rel.state == state { return }
        realm.relations[r].state = state
        realm.relations[r].since = world.time
        let a = realm.nation(rel.a)?.name(zh: zh) ?? "", b = realm.nation(rel.b)?.name(zh: zh) ?? ""
        if state == 1 {
            realm.counts.wars += 1
            realm.relations[r].value = max(-1, rel.value - 0.3)
            realm.relations[r].pact = false
        } else if state == 2 {
            realm.counts.truces += 1
            for lg in realm.legions where lg.state == 1 || lg.state == 2 {
                if let tn = settlements[lg.target]?.nation, (lg.nation == rel.a && tn == rel.b) || (lg.nation == rel.b && tn == rel.a) { sendHome(lg) }
            }
            emit("truce", [a, b], .zero)
        } else { emit("peace", [a, b], .zero) }
    }

    func declare(_ a: Int, on b: Int) {
        guard let r = realm.ri(a, b), realm.relations[r].state == 0 else { return }
        setState(r, 1)
        emit("war", [realm.nation(a)?.name(zh: zh) ?? "", realm.nation(b)?.name(zh: zh) ?? ""], towns(of: b).first?.center.center ?? .zero)
        muster(a, against: b)
    }

    func canDeclare(_ a: Int, on b: Int) -> Bool {
        let cfg = realm.cfg
        guard let r = realm.relation(a, b), r.state == 0, world.time - r.since >= cfg.peaceCooldown * MP.year,
              let na = realm.nation(a), let nb = realm.nation(b), na.exileSince == nil, nb.exileSince == nil else { return false }
        return na.fatigue < cfg.fatigueDeclareMax && na.soldiers >= cfg.minAttack + 1
    }

    func diplomacy(_ dty: Double) {
        let cfg = realm.cfg
        let now = world.time
        let totalPop = max(1, agents.count)
        let hardEverywhere = realm.intensity / Double(totalPop) >= cfg.intensityHard
        // wars end in a truce: tired nations, or a world that has bled too much
        for r in realm.relations.indices where realm.relations[r].state == 1 {
            let rel = realm.relations[r]
            let fa = realm.nation(rel.a)?.fatigue ?? 0, fb = realm.nation(rel.b)?.fatigue ?? 0
            let long = now - rel.since >= cfg.minWar * MP.year
            if hardEverywhere || max(fa, fb) >= cfg.fatigueHard || (long && max(fa, fb) >= cfg.fatigueSoft) { setState(r, 2) }
        }
        // truces become peace after the minimum rest
        for r in realm.relations.indices where realm.relations[r].state == 2 && now - realm.relations[r].since >= cfg.minTruce * MP.year { setState(r, 0) }
        // balance of power: the two weaker nations lean on each other
        let landed = realm.nations.filter { $0.exileSince == nil }
        if landed.count == 3, let strong = landed.max(by: { power($0) < power($1) }) {
            let share = powerShare(strong.id)
            let others = landed.filter { $0.id != strong.id }
            if let r = realm.ri(others[0].id, others[1].id) {
                if share > cfg.dominance && !realm.relations[r].pact && now >= (realm.cool["pact"] ?? 0) {
                    realm.relations[r].pact = true
                    realm.relations[r].value = min(1, realm.relations[r].value + 0.4)
                    if realm.relations[r].state == 1 { setState(r, 2) }
                    emit("pact", [others[0].name(zh: zh), others[1].name(zh: zh), strong.name(zh: zh)], .zero)
                }
            }
            // an overstretched giant pays to govern what it holds
            if share > cfg.dominance {
                for s in towns(of: strong.id) where majorityIdentity(s) != strong.id { s.food = max(0, s.food - cfg.governFood * Double(s.members.count) * dty) }
            }
        }
        // a nation with one exhausted town may submit to a giant instead of being stormed
        for w in landed where w.towns == 1 && w.fatigue >= cfg.submitFatigue && powerShare(w.id) < cfg.submitShare {
            guard let d = landed.first(where: { $0.id != w.id && realm.atWar($0.id, w.id) && powerShare($0.id) > cfg.dominance }), let s = towns(of: w.id).first else { continue }
            if let g = garrison(s, create: false) { g.nation = d.id }
            s.nation = d.id; s.unrest = 0.2
            emit("submitted", [w.name(zh: zh), d.name(zh: zh)], s.center.center)
            landCheck()
            return
        }
        if realm.era != 0 { return }
        // declarations
        for n in realm.nations where n.exileSince == nil {
            var targets = realm.nations.filter { $0.id != n.id && canDeclare(n.id, on: $0.id) }
            if targets.isEmpty { continue }
            targets.sort { a, b in
                let ra = realm.relation(n.id, a.id)?.value ?? 0, rb = realm.relation(n.id, b.id)?.value ?? 0
                return ra != rb ? ra < rb : power(a) < power(b) }
            // allies do not attack each other
            targets.removeAll { realm.relation(n.id, $0.id)?.pact == true }
            guard let t = targets.first else { continue }
            let forced = n.overT >= cfg.hardPopHold * MP.year
            var chance = cfg.warChance * min(1, max(0, n.pressure - cfg.warPressure) / max(0.05, cfg.warPressureFull - cfg.warPressure))
            chance *= 1 - 0.5 * (realm.relation(n.id, t.id)?.value ?? 0)
            let allied = realm.relations.contains { $0.pact && ($0.a == n.id || $0.b == n.id) }
            if allied && powerShare(t.id) > cfg.dominanceRelease { chance = max(chance, 0.3) * cfg.pactWar }
            if powerShare(n.id) > cfg.dominance { chance = max(chance, cfg.ambition) }
            if forced || realm.rng.unit() < chance * dty {
                declare(n.id, on: t.id)
                if let k = realm.ni(n.id) { realm.nations[k].overT = 0 }
                // an ally joins against the strong nation
                if let pr = realm.relations.first(where: { $0.pact && ($0.a == n.id || $0.b == n.id) }) {
                    let ally = pr.a == n.id ? pr.b : pr.a
                    if ally != t.id && canDeclare(ally, on: t.id) { declare(ally, on: t.id) }
                }
            }
        }
        // keep armies in the field while a war lasts
        for rel in realm.relations where rel.state == 1 {
            muster(rel.a, against: rel.b)
            muster(rel.b, against: rel.a)
        }
        // exiles come home: a town that still feels theirs rises, or their people settle anew
        for n in realm.nations {
            guard let since = n.exileSince, now - since >= cfg.exileMax * MP.year else { continue }
            if restoreNation(n.id) { break }
        }
    }

    /// Give a landless nation land again without inventing people: a town where
    /// its identity is strong changes flag, otherwise existing residents secede and settle.
    @discardableResult func restoreNation(_ id: Int) -> Bool {
        guard let n = realm.nation(id) else { return false }
        let all = settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        let cand = all.filter { s in towns(of: s.nation ?? 0).count > 1 }.max { identityShare($0, id) < identityShare($1, id) }
        if let s = cand, identityShare(s, id) >= 0.34 {
            flip(s, to: id)
            emit("revived", [n.name(zh: zh), s.name(zh: zh)], s.center.center)
            return true
        }
        return secede(id)
    }

    func flip(_ s: Settlement, to id: Int) {
        let old = s.nation ?? 0
        if let g = garrison(s, create: false) {
            // loyal soldiers withdraw to the nearest town their nation still holds; the rest change sides
            if let back = towns(of: old).filter({ $0 !== s }).min(by: { ($0.center - s.center).lengthSquared < ($1.center - s.center).lengthSquared }) {
                let loyal = g.members.filter { agents[$0]?.nation == old }
                let bg = garrison(back, create: true)!
                for mid in loyal { if let a = agents[mid] { move(a, to: back); a.legion = bg.id; bg.members.append(mid); a.travelling = true; a.travelTo = back.center.center } }
                g.members.removeAll { loyal.contains($0) }
            }
            g.nation = id
        }
        s.nation = id
        s.unrest = 0
        if let r = realm.ri(old, id) { realm.relations[r].value = max(-1, realm.relations[r].value - 0.3) }
        landCheck()
    }

    @discardableResult func secede(_ id: Int) -> Bool {
        guard let n = realm.nation(id) else { return false }
        let now = world.time
        guard let src = settlements.values.filter({ !$0.abandoned && $0.members.count >= 9 })
                .max(by: { $0.members.count != $1.members.count ? $0.members.count < $1.members.count : $0.id > $1.id }) else { return false }
        let site = world.findSite(from: src.center, minR: 80, maxR: 170, salt: 5000 + nextSID * 17, avoid: settlements.values.map { $0.center }, avoidDist: 70)
        if site.isNone { return false }
        var houses: [Int: [Agent]] = [:]
        for a in src.members.compactMap({ agents[$0] }) where a.legion == nil { houses[household(a, now), default: []].append(a) }
        let order = houses.keys.sorted { a, b in
            let ia = houses[a]!.filter { $0.nation == id }.count, ib = houses[b]!.filter { $0.nation == id }.count
            return ia != ib ? ia > ib : a < b }
        let want = min(12, max(3, src.members.count / 3))
        var group: [Agent] = []
        for h in order where group.count < want { group += houses[h]! }
        if group.count < 3 { return false }
        let ns = foundSettlement(site)
        ns.nation = id
        let food = min(src.food * 0.3, Double(group.count) * 8), wood = min(src.wood * 0.3, 30)
        src.food -= food; src.wood -= wood
        ns.food = food; ns.wood = wood
        for a in group {
            move(a, to: ns)
            a.nation = id                                   // they take up the old banner
            a.travelling = true
            a.travelTo = world.findFree(near: site + TilePos(realm.rng.int(-4, 4), realm.rng.int(2, 5)), maxR: 6).center
        }
        if let k = realm.ni(id) { realm.nations[k].exileSince = nil; realm.nations[k].leader = pickLeader(id) }
        stats.founded += 1
        emit("revived", [n.name(zh: zh), ns.name(zh: zh)], site.center)
        return true
    }

    // MARK: unity and division
    func startUnity(_ id: Int) {
        realm.era = 1; realm.eraSince = world.time; realm.unifier = id; realm.fracture = 0
        realm.counts.unifications += 1
        for r in realm.relations.indices { realm.relations[r].state = 0; realm.relations[r].since = world.time; realm.relations[r].pact = false }
        for lg in realm.legions where lg.state != 0 { sendHome(lg) }
        // what was learned anywhere is now known everywhere
        let best = realm.nations.map { $0.techCount }.max() ?? 0
        for k in realm.nations.indices { realm.nations[k].techCount = best; realm.nations[k].fatigue *= 0.5 }
        emit("unified", [realm.nation(id)?.name(zh: zh) ?? ""], .zero)
    }

    func unity(_ dty: Double) {
        let cfg = realm.cfg
        let towns = settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        // trade: stocks flow towards towns that have less per head
        let heads = max(1, towns.reduce(0) { $0 + $1.members.count })
        for key in ["food", "wood", "stone"] {
            let total = towns.reduce(0.0) { $0 + $1.stock(key) }
            for s in towns {
                let fair = total * Double(s.members.count) / Double(heads)
                s.addStock(key, (fair - s.stock(key)) * cfg.unityTrade)
            }
        }
        let minority = 1 - Double(agents.values.filter { $0.nation == realm.unifier }.count) / Double(max(1, agents.count))
        realm.fracture += dty * (cfg.fractureBase + cfg.fractureIdentity * minority)
        for s in towns where (s.unrest ?? 0) >= 1 && world.time >= (realm.cool["independence"] ?? 0) {
            realm.fracture += cfg.fractureIndependence
            s.unrest = 0.5
            realm.cool["independence"] = world.time + 0.5 * MP.year
            realm.counts.events += 1
            emit("independence", [s.name(zh: zh)], s.center.center)
        }
        let age = (world.time - realm.eraSince) / MP.year
        if (realm.fracture >= 1 && age >= cfg.unityMin) || age >= cfg.unityMax { split() }
    }

    /// End of a united age: three nations that really hold land, drawn from where
    /// people's loyalties, the map and the garrisons are now - not from old borders.
    @discardableResult func split() -> Bool {
        let cfg = realm.cfg
        var towns = settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        var guardN = 0
        while towns.count < 3 && guardN < 3 {
            guardN += 1
            // not enough towns: people leave the biggest one and found another
            let lacking = realm.nations.map { $0.id }.filter { $0 != realm.unifier }
            for s in towns { s.nation = realm.unifier }
            if !secede(lacking[min(guardN - 1, lacking.count - 1)]) { break }
            towns = settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        }
        if towns.count < 3 { return false }           // too few people to divide; tried again next hour
        func military(_ s: Settlement, _ n: Int) -> Double {
            guard let g = garrison(s, create: false), !g.members.isEmpty else { return 0 }
            return Double(g.members.filter { agents[$0]?.nation == n }.count) / Double(g.members.count)
        }
        var owner: [Int: Int] = [:]
        var seed: [Int: Settlement] = [:]
        let order = realm.nations.sorted { $0.identity != $1.identity ? $0.identity > $1.identity : $0.id < $1.id }
        for n in order {
            let free = towns.filter { owner[$0.id] == nil }
            let pick = free.max { a, b in
                let sa = cfg.splitIdentity * identityShare(a, n.id) + cfg.splitMilitary * military(a, n.id)
                let sb = cfg.splitIdentity * identityShare(b, n.id) + cfg.splitMilitary * military(b, n.id)
                return sa != sb ? sa < sb : a.id > b.id }!
            owner[pick.id] = n.id; seed[n.id] = pick
        }
        for s in towns where owner[s.id] == nil {
            var best = 0, bestScore = -1.0
            for n in realm.nations {
                let d = (seed[n.id]!.center.center - s.center.center).length
                let score = cfg.splitIdentity * identityShare(s, n.id) + cfg.splitGeography / (1 + d / 1500) + cfg.splitMilitary * military(s, n.id)
                if score > bestScore { bestScore = score; best = n.id }
            }
            owner[s.id] = best
        }
        for lg in realm.legions where lg.state != 0 { if let h = settlements[lg.home] { disband(lg, into: h) } }
        for s in towns {
            s.nation = owner[s.id]
            s.unrest = 0
            if let g = garrison(s, create: false) { g.nation = s.nation ?? 0 }
        }
        realm.era = 0; realm.eraSince = world.time; realm.unifier = 0; realm.fracture = 0
        realm.counts.splits += 1
        for r in realm.relations.indices { realm.relations[r].state = 2; realm.relations[r].since = world.time; realm.relations[r].value = 0; realm.relations[r].pact = false }
        for k in realm.nations.indices { realm.nations[k].exileSince = nil; realm.nations[k].leader = pickLeader(realm.nations[k].id); realm.nations[k].overT = 0 }
        let names = realm.nations.map { $0.name(zh: zh) }
        emit("split", names, .zero)
        refreshNations()
        return true
    }

    // MARK: events
    func fire(_ kind: String, _ nation: Int) {
        guard let rule = realm.cfg.events[kind] else { return }
        realm.cool["\(kind):\(nation)"] = world.time + rule.cooldown * MP.year
        if rule.duration > 0 { realm.mods.append(RealmMod(kind: kind, nation: nation, until: world.time + rule.duration * MP.year)) }
        realm.counts.events += 1
    }
    func ready(_ kind: String, _ nation: Int) -> Bool { world.time >= (realm.cool["\(kind):\(nation)"] ?? 0) }

    func events(_ dty: Double) {
        let cfg = realm.cfg
        let now = world.time
        realm.mods.removeAll { $0.until <= now }
        for n in realm.nations where n.exileSince == nil {
            let ts = towns(of: n.id)
            let farms = ts.reduce(0) { $0 + $1.count("farm", done: true) }
            func roll(_ kind: String, _ cond: Bool) -> Bool {
                guard cond, ready(kind, n.id), let rule = cfg.events[kind] else { return false }
                return realm.rng.unit() < rule.chance * dty
            }
            let center = ts.first?.center.center ?? .zero
            if roll("harvest_good", farms >= 1 && !realm.active("harvest_bad", n.id, now)) { fire("harvest_good", n.id); emit("harvest_good", [n.name(zh: zh)], center) }
            if roll("harvest_bad", farms >= 1 && !realm.active("harvest_good", n.id, now)) { fire("harvest_bad", n.id); emit("harvest_bad", [n.name(zh: zh)], center) }
            if roll("general", n.soldiers >= 5), let g = realm.legions.filter({ $0.nation == n.id }).flatMap({ $0.members }).sorted().first, let a = agents[g] {
                fire("general", n.id); emit("general", [a.name(zh: zh), n.name(zh: zh)], a.pos)
            }
            let places = ts.reduce(0) { $0 + $1.count("school", done: true) + $1.count("lab", done: true) }
            if roll("breakthrough", n.techCount < Society.techs.count && (places >= 1 || n.techCount < 2)) { fire("breakthrough", n.id); emit("breakthrough", [n.name(zh: zh)], center) }
            if let l = agents[n.leader], roll("leader_died", l.age(now) >= 55) { die(l, "ill") }
            // effects that last
            if realm.active("harvest_good", n.id, now) { for s in ts { s.food += cfg.harvestBonus * Double(s.count("farm", done: true)) } }
            if realm.active("harvest_bad", n.id, now) { for s in ts { s.food *= 1 - cfg.harvestLoss } }
        }
        // an alliance only lasts while the giant is a giant
        for r in realm.relations.indices where realm.relations[r].pact {
            let rel = realm.relations[r]
            let third = realm.nations.first { $0.id != rel.a && $0.id != rel.b }!
            let weak = powerShare(third.id) < cfg.dominanceRelease
            guard weak, world.time >= (realm.cool["alliance_broken"] ?? 0), let rule = cfg.events["alliance_broken"] else { continue }
            if realm.rng.unit() < rule.chance * dty * 6 {
                realm.relations[r].pact = false
                realm.relations[r].value = max(-1, rel.value - 0.3)
                realm.cool["alliance_broken"] = world.time + rule.cooldown * MP.year
                realm.cool["pact"] = world.time + rule.cooldown * MP.year
                realm.counts.events += 1
                emit("alliance_broken", [realm.nation(rel.a)?.name(zh: zh) ?? "", realm.nation(rel.b)?.name(zh: zh) ?? ""], .zero)
            }
        }
    }

    func unrest(_ dty: Double) {
        let cfg = realm.cfg
        for s in settlements.values.filter({ !$0.abandoned }).sorted(by: { $0.id < $1.id }) {
            guard let nid = s.nation, !s.members.isEmpty else { continue }
            let mismatch = 1 - identityShare(s, nid)
            var u = s.unrest ?? 0
            if mismatch > 0.5 {
                let soldiers = Double(garrison(s, create: false)?.members.count ?? 0)
                var grow = cfg.unrestRate * mismatch * (1 - min(0.9, cfg.unrestGarrison * soldiers / Double(s.members.count)))
                if powerShare(nid) > cfg.dominance { grow *= cfg.strongUnrest }
                if s.food < Double(s.members.count) * 2 { grow *= 1.5 }
                u += grow * dty
            } else { u = max(0, u - 0.5 * dty) }
            s.unrest = u
            // a town that has had enough goes over to the nation most of its people belong to
            if realm.era == 0 && u >= 1 && ready("town_defect", s.id + 1000) {
                let to = majorityIdentity(s)
                if to != nid, let tn = realm.nation(to) {
                    fire("town_defect", s.id + 1000)
                    realm.counts.defections += 1
                    emit("town_defect", [s.name(zh: zh), tn.name(zh: zh)], s.center.center)
                    flip(s, to: to)
                }
            }
        }
    }

    // MARK: hourly
    public func realmHourly() {
        guard !realm.nations.isEmpty else { return }
        let cfg = realm.cfg
        let dty = Society.hour / MP.year
        let now = world.time
        if agents.isEmpty { restart(); return }
        if realm.era == 2 { realm.era = 0; realm.eraSince = now }
        refreshNations()
        realm.intensity *= pow(0.5, dty / cfg.intensityHalfLife)
        for k in realm.nations.indices {
            var n = realm.nations[k]
            if realm.atWar(n.id) { n.fatigue = min(1.5, n.fatigue + cfg.fatigueWarYear * dty) } else { n.fatigue = max(0, n.fatigue - cfg.fatigueRecovery * dty) }
            if n.pFood >= 0.95 && n.pop > 0 { n.fatigue = min(1.5, n.fatigue + cfg.fatigueHunger * dty) }
            n.overT = n.towns > 0 && Double(n.pop) > cfg.hardPerTown * Double(n.towns) ? n.overT + Society.hour : max(0, n.overT - Society.hour)
            if n.leader == 0 || agents[n.leader] == nil { n.leader = pickLeader(n.id) }
            realm.nations[k] = n
        }
        conscription()
        unrest(dty)
        landCheck()
        if realm.era == 1 { unity(dty) } else { diplomacy(dty) }
        events(dty)
        for a in agents.values { if let r = a.refugee, now >= r { a.refugee = nil } }
        realm.depots.removeAll { world.tile(2, $0.x, $0.y) != T["crate"] }
    }

    /// Nobody is left. Say so, wait out any hold, then let new settlers begin as three peoples.
    func restart() {
        if realm.era != 2 {
            realm.era = 2; realm.eraSince = world.time
            realm.legions = []; realm.mods = []; realm.fracture = 0; realm.unifier = 0; realm.intensity = 0
            for r in realm.relations.indices { realm.relations[r].state = 0; realm.relations[r].pact = false; realm.relations[r].since = world.time }
            for k in realm.nations.indices { realm.nations[k].leader = 0; realm.nations[k].fatigue = 0; realm.nations[k].exileSince = world.time }
            realm.immigrationHold = max(realm.immigrationHold, world.time + realm.cfg.restartDelay * MP.year)
            emit("restart", [], .zero)
        }
        if world.time < realm.immigrationHold || minPopulation <= 0 { return }
        let origin = settlements.values.sorted { $0.id < $1.id }.last?.center ?? TilePos(0, 0)
        for s in settlements.values where !s.abandoned { s.abandoned = true; detach(s) }
        bootstrap(origin: origin, villages: 3, per: 4)
        if !agents.isEmpty { realm.era = 0; realm.eraSince = world.time; emit("resettled", [], origin.center) }
    }

    /// Called for every death: armies shrink, nations tire, leaders are succeeded.
    func realmDeath(_ a: Agent, _ s: Settlement, _ cause: String) {
        var side = s.nation ?? 0
        if let lid = a.legion, let lg = realm.legion(lid) { lg.members.removeAll { $0 == a.id }; side = lg.nation }
        if cause == "battle" {
            realm.intensity += 1
            let pop = Double(max(20, realm.nation(side)?.pop ?? 20))
            addFatigue(side, realm.cfg.fatigueDeath / pop)
        }
        for k in realm.nations.indices where realm.nations[k].leader == a.id {
            let heir = pickLeader(realm.nations[k].id)
            realm.nations[k].leader = heir
            fire("leader_died", realm.nations[k].id)
            emit("leader_died", [realm.nations[k].name(zh: zh), a.name(zh: zh), agents[heir]?.name(zh: zh) ?? "-"], a.pos)
            if realm.era == 1 && realm.nations[k].id == realm.unifier {
                realm.fracture += realm.cfg.fractureSuccession
                emit("succession", [], a.pos)
            }
        }
    }

    // MARK: integrity
    /// Canonical text of the whole simulation state (order-independent), for
    /// comparing two runs or a save with its reload.
    public func digest() -> String {
        func f(_ v: Double) -> String { String(format: "%.4f", v) }
        var out: [String] = ["t=\(f(world.time)) era=\(realm.era) unifier=\(realm.unifier) fr=\(f(realm.fracture)) next=\(nextID),\(nextSID),\(nextBID) rng=\(rng.state),\(realm.rng.state)"]
        for a in agents.values.sorted(by: { $0.id < $1.id }) {
            out.append("a\(a.id) s\(a.sid) n\(a.nation ?? 0) h\(a.home) p\(a.partner) l\(a.legion ?? 0) j\(a.job) \(f(a.pos.x)),\(f(a.pos.y)) \(f(a.hunger)) \(f(a.health)) hp\(f(a.hp ?? -1)) r\(f(a.refugee ?? -1)) c\(a.children.count)")
        }
        for s in settlements.values.sorted(by: { $0.id < $1.id }) {
            out.append("s\(s.id) n\(s.nation ?? 0) ab\(s.abandoned) m\(s.members.sorted()) \(f(s.food)) \(f(s.wood)) \(f(s.stone)) u\(f(s.unrest ?? 0)) b\(s.buildings.map { "\($0.id):\($0.type):\($0.placed):\($0.done)" })")
        }
        for n in realm.nations { out.append("n\(n.id) L\(n.leader) t\(n.techCount) \(f(n.research)) f\(f(n.fatigue)) rep\(f(n.rep)) ex\(f(n.exileSince ?? -1))") }
        for r in realm.relations { out.append("r\(r.a)\(r.b) \(r.state) \(f(r.value)) \(f(r.since)) \(r.pact)") }
        for l in realm.legions.sorted(by: { $0.id < $1.id }) { out.append("L\(l.id) n\(l.nation) h\(l.home) t\(l.target) st\(l.state) \(l.members.sorted()) \(f(l.pos.x)),\(f(l.pos.y)) \(f(l.supply))") }
        out.append("counts \(realm.counts) depots \(realm.depots.count) log \(log.count)")
        return out.joined(separator: "\n")
    }

    /// Every reference that points at something that no longer exists.
    public func audit() -> [String] {
        var out: [String] = []
        for a in agents.values.sorted(by: { $0.id < $1.id }) {
            guard let s = settlements[a.sid] else { out.append("agent \(a.id): settlement \(a.sid)"); continue }
            if !s.members.contains(a.id) { out.append("agent \(a.id): not a member of \(s.id)") }
            if a.partner != 0 && agents[a.partner] == nil { out.append("agent \(a.id): partner \(a.partner)") }
            if a.home >= 0 && s.building(a.home) == nil { out.append("agent \(a.id): home \(a.home)") }
            if let l = a.legion { if realm.legion(l)?.members.contains(a.id) != true { out.append("agent \(a.id): legion \(l)") } }
            if let t = a.task, t.bid != 0, s.building(t.bid) == nil { out.append("agent \(a.id): task building \(t.bid)") }
        }
        for s in settlements.values.sorted(by: { $0.id < $1.id }) where !s.abandoned {
            for m in s.members where agents[m]?.sid != s.id { out.append("settlement \(s.id): member \(m)") }
            for b in s.buildings { for r in b.residents where agents[r] == nil { out.append("building \(b.id): resident \(r)") } }
            if let n = s.nation, n != 0, realm.nation(n) == nil { out.append("settlement \(s.id): nation \(n)") }
        }
        for lg in realm.legions {
            for m in lg.members where agents[m]?.legion != lg.id { out.append("legion \(lg.id): member \(m)") }
            if settlements[lg.home] == nil { out.append("legion \(lg.id): home \(lg.home)") }
        }
        for n in realm.nations where n.leader != 0 && agents[n.leader] == nil { out.append("nation \(n.id): leader \(n.leader)") }
        return out
    }

    /// Mend everything `audit` would report. Returns how many references were fixed.
    @discardableResult public func repairReferences() -> Int {
        var fixed = 0
        for a in agents.values.sorted(by: { $0.id < $1.id }) {
            guard let s = settlements[a.sid] else { agents[a.id] = nil; fixed += 1; continue }
            if !s.members.contains(a.id) { s.members.append(a.id); fixed += 1 }
            if a.partner != 0 && agents[a.partner] == nil { a.partner = 0; fixed += 1 }
            let kids = a.children.filter { agents[$0] != nil }
            if kids.count != a.children.count { a.children = kids }
            if a.home >= 0 && s.building(a.home) == nil { a.home = -1; fixed += 1 }
            if let l = a.legion {
                if let lg = realm.legion(l) { if !lg.members.contains(a.id) { lg.members.append(a.id); fixed += 1 } }
                else { a.legion = nil; a.job = ""; a.hp = nil; fixed += 1 }
            }
            if let t = a.task, t.bid != 0, s.building(t.bid) == nil { a.task = nil; a.path = []; fixed += 1 }
            a.rel = a.rel.filter { $0.key == 0 || agents[$0.key] != nil }
        }
        for s in settlements.values {
            let m = s.members.filter { agents[$0]?.sid == s.id }
            if m.count != s.members.count { fixed += s.members.count - m.count; s.members = m }
            for b in s.buildings {
                let r = b.residents.filter { agents[$0] != nil }
                if r.count != b.residents.count { fixed += b.residents.count - r.count; b.residents = r }
                if let o = b.owner, agents[o] == nil, r.isEmpty { b.owner = nil }
            }
            s.claims = s.claims.filter { agents[$0.value] != nil }
        }
        for lg in realm.legions {
            let m = lg.members.filter { agents[$0]?.legion == lg.id }
            if m.count != lg.members.count { fixed += lg.members.count - m.count; lg.members = m }
        }
        let before = realm.legions.count
        realm.legions.removeAll { settlements[$0.home] == nil || ($0.members.isEmpty && $0.state != 0) }
        fixed += before - realm.legions.count
        for k in realm.nations.indices where realm.nations[k].leader != 0 && agents[realm.nations[k].leader] == nil {
            realm.nations[k].leader = pickLeader(realm.nations[k].id); fixed += 1
        }
        return fixed
    }
}
