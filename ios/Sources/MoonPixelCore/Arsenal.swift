import Foundation

/// Weapons, energy arms, spells, divine arts and words of power.
/// Every world arranges them into its own random technology tree; nations
/// research along it, armies fight with what they know, and the player wields
/// what their nation (or a maze artifact) has taught them.
public struct Power {
    public let key: String, en: String, zh: String
    public let school: Int        // 0 arms, 1 energy, 2 arcane, 3 divine, 4 word
    public let tier: Int          // 1...5
    public let damage: Double, range: Double, cooldown: Double
    public let shape: Int         // see Power.Shape
    public let radius: Double     // blast / stun radius, burst count, chain jumps, ward seconds
    public let focus: Double      // focus spent per use (0 for guns)
    public let fx: String
    public func name(zh z: Bool) -> String { z ? zh : en }

    public enum Shape { public static let melee = 0, shot = 1, blast = 2, beam = 3, chain = 4, heal = 5, sky = 6, stun = 7, blink = 8, burst = 9, ward = 10, grow = 11, calm = 12 }
    public static let schoolNames: [(String, String)] = [("Arms", "军械"), ("Energy", "能量武器"), ("Arcane", "魔法"), ("Divine", "神术"), ("Words", "真言")]

    static func p(_ k: String, _ en: String, _ zh: String, _ s: Int, _ t: Int, _ d: Double, _ r: Double, _ c: Double, _ sh: Int, _ rad: Double, _ f: Double, _ fx: String) -> Power {
        Power(key: k, en: en, zh: zh, school: s, tier: t, damage: d, range: r, cooldown: c, shape: sh, radius: rad, focus: f, fx: fx)
    }

    public static let all: [Power] = [
        // --- arms: what a modern army carries
        p("pistol", "Pistol", "手枪", 0, 1, 30, 180, 0.35, Shape.shot, 0, 0, "bullet"),
        p("rifle", "Assault rifle", "突击步枪", 0, 2, 22, 240, 0.5, Shape.burst, 3, 0, "bullet"),
        p("sniper", "Sniper rifle", "狙击步枪", 0, 3, 150, 420, 1.6, Shape.shot, 0, 0, "tracer"),
        p("mg", "Machine gun", "机枪", 0, 3, 16, 220, 0.6, Shape.burst, 6, 0, "bullet"),
        p("grenade", "Grenade launcher", "榴弹发射器", 0, 3, 70, 200, 1.4, Shape.blast, 36, 0, "shell"),
        p("rocket", "Rocket launcher", "火箭筒", 0, 4, 140, 300, 2.2, Shape.blast, 48, 0, "rocket"),
        p("missile", "Guided missile", "制导导弹", 0, 4, 180, 600, 4, Shape.sky, 50, 0, "missile"),
        p("drone", "Drone strike", "无人机打击", 0, 5, 120, 800, 6, Shape.sky, 70, 0, "missile"),
        p("artillery", "Artillery barrage", "炮火覆盖", 0, 5, 100, 900, 9, Shape.sky, 110, 0, "barrage"),
        p("railgun", "Railgun", "电磁轨道炮", 0, 5, 260, 600, 3, Shape.beam, 0, 0, "rail"),
        // --- energy: space-opera hardware
        p("blaster", "Blaster", "爆能枪", 1, 1, 34, 200, 0.4, Shape.shot, 0, 0, "bolt"),
        p("plasma_blade", "Plasma blade", "等离子光刃", 1, 2, 90, 36, 0.45, Shape.melee, 0, 0, "blade"),
        p("plasma_rifle", "Plasma rifle", "等离子步枪", 1, 2, 45, 260, 0.5, Shape.shot, 0, 0, "plasma"),
        p("ion", "Ion cannon", "离子炮", 1, 3, 110, 320, 1.8, Shape.beam, 0, 0, "ion"),
        p("shield", "Energy shield", "能量护盾", 1, 3, 0, 0, 14, Shape.ward, 6, 0, "shield"),
        p("particle", "Particle beam", "粒子束", 1, 4, 170, 500, 2.5, Shape.beam, 0, 0, "particle"),
        p("gravity", "Gravity well", "引力井", 1, 4, 60, 300, 6, Shape.blast, 70, 0, "gravity"),
        p("orbital", "Orbital laser", "轨道激光", 1, 5, 300, 1000, 10, Shape.sky, 60, 0, "orbital"),
        p("antimatter", "Antimatter charge", "反物质弹", 1, 5, 400, 400, 15, Shape.blast, 100, 0, "antimatter"),
        // --- arcane magic
        p("magic_missile", "Magic missile", "魔法飞弹", 2, 1, 28, 220, 0.5, Shape.shot, 0, 4, "orb"),
        p("fireball", "Fireball", "火球术", 2, 2, 80, 240, 1.2, Shape.blast, 40, 10, "fire"),
        p("frost", "Frost nova", "冰霜新星", 2, 2, 40, 0, 4, Shape.stun, 70, 12, "frost"),
        p("arcane_beam", "Arcane ray", "奥术射线", 2, 3, 120, 300, 1.8, Shape.beam, 0, 14, "arcane"),
        p("blink", "Blink", "闪现", 2, 3, 0, 260, 3, Shape.blink, 0, 10, "blink"),
        p("meteor", "Meteor", "陨石术", 2, 4, 220, 500, 6, Shape.sky, 70, 30, "meteor"),
        p("timestop", "Time stop", "时间停止", 2, 5, 0, 0, 30, Shape.stun, 300, 50, "time"),
        p("blackhole", "Black hole", "黑洞", 2, 5, 350, 350, 20, Shape.blast, 90, 60, "blackhole"),
        // --- divine arts and the weapons of myth
        p("heal", "Holy light", "圣光治疗", 3, 1, 50, 0, 3, Shape.heal, 0, 10, "holy"),
        p("smite", "Smite", "惩戒", 3, 2, 90, 260, 1.5, Shape.sky, 20, 10, "pillar"),
        p("sanctuary", "Sanctuary", "庇护圣域", 3, 3, 0, 0, 20, Shape.ward, 8, 25, "sanctuary"),
        p("thunder", "Thunderbolt", "雷霆", 3, 3, 130, 280, 2, Shape.chain, 4, 16, "lightning"),
        p("thunder_hammer", "Thunder hammer", "雷神之锤", 3, 4, 200, 220, 3, Shape.blast, 50, 20, "hammer"),
        p("judgment", "Judgment", "天罚", 3, 4, 240, 500, 7, Shape.sky, 60, 35, "pillar"),
        p("sun_spear", "Sun spear", "太阳神矛", 3, 5, 320, 600, 5, Shape.beam, 0, 40, "sun"),
        p("storm", "Wrath of the storm", "神怒风暴", 3, 5, 160, 600, 14, Shape.sky, 140, 60, "storm"),
        // --- words of power: one syllable, spoken as a command
        p("halt", "Word: Halt", "真言·止", 4, 1, 0, 200, 5, Shape.stun, 60, 10, "word:止"),
        p("mend", "Word: Mend", "真言·愈", 4, 2, 100, 0, 6, Shape.heal, 0, 15, "word:愈"),
        p("scatter", "Word: Scatter", "真言·散", 4, 2, 20, 200, 6, Shape.stun, 90, 14, "word:散"),
        p("grow", "Word: Grow", "真言·生", 4, 3, 0, 160, 10, Shape.grow, 5, 20, "word:生"),
        p("peace", "Word: Peace", "真言·和", 4, 4, 0, 0, 30, Shape.calm, 220, 40, "word:和"),
        p("perish", "Word: Perish", "真言·灭", 4, 5, 500, 300, 12, Shape.shot, 0, 60, "word:灭"),
    ]
    public static let byKey: [String: Power] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    /// Civil technologies a nation needs before it can even study this.
    public var civNeed: Int {
        switch school {
        case 0: return [3, 4, 5, 6, 7][tier - 1]      // from metalworking up to computing
        case 1: return [5, 6, 7, 8, 9][tier - 1]      // electricity and beyond
        default: return [0, 1, 2, 3, 4][tier - 1]     // the old arts ask little of industry
        }
    }
    public var cost: Double { Double(tier) * 110 }
}

/// The tree itself: which earlier powers each one needs. Different in every world.
public struct ArsenalTree: Codable, Equatable {
    public var needs: [String: [String]] = [:]

    public static func generate(seed: Int) -> ArsenalTree {
        var r = RNG(seed: seed &* 7919 &+ 17)
        var t = ArsenalTree()
        for p in Power.all {
            if p.tier == 1 { t.needs[p.key] = []; continue }
            let lower = Power.all.filter { $0.tier == p.tier - 1 }
            let own = lower.filter { $0.school == p.school }
            var picks: [String] = []
            // one root in its own school, sometimes a second from anywhere: that is where worlds differ
            if let a = own.isEmpty ? nil : own[r.index(own.count)] { picks.append(a.key) }
            if r.unit() < 0.45 || picks.isEmpty {
                let b = lower[r.index(lower.count)].key
                if !picks.contains(b) { picks.append(b) }
            }
            t.needs[p.key] = picks
        }
        return t
    }
}

extension Society {
    // MARK: research along the random tree
    public func arsenalTree() -> ArsenalTree {
        if let t = realm.arsenal { return t }
        let t = ArsenalTree.generate(seed: world.seed)
        realm.arsenal = t
        return t
    }

    public func knows(_ nation: Int, _ key: String) -> Bool { realm.nation(nation)?.powers?.contains(key) ?? false }

    /// Powers a nation could start studying now.
    public func researchable(_ nation: Int) -> [Power] {
        guard let n = realm.nation(nation) else { return [] }
        let tree = arsenalTree()
        let known = Set(n.powers ?? [])
        return Power.all.filter { p in !known.contains(p.key) && n.techCount >= p.civNeed && (tree.needs[p.key] ?? []).allSatisfy { known.contains($0) } }
    }

    func arsenalHourly() {
        let cfg = realm.cfg
        for k in realm.nations.indices {
            let id = realm.nations[k].id
            if realm.nations[k].exileSince != nil { continue }
            var rate = 0.0
            for s in settlements.values where !s.abandoned && s.nation == id { rate += researchRate(of: s) }
            realm.nations[k].arsenalPts = (realm.nations[k].arsenalPts ?? 0) + rate * Society.hour * cfg.arsenalScale * (realm.atWar(id) ? cfg.arsenalWar : 1)
            if realm.nations[k].studying == nil || knows(id, realm.nations[k].studying!) {
                let options = researchable(id)
                realm.nations[k].studying = options.isEmpty ? nil : options[realm.rng.index(options.count)].key
            }
            guard let key = realm.nations[k].studying, let p = Power.byKey[key] else { continue }
            if (realm.nations[k].arsenalPts ?? 0) >= p.cost {
                realm.nations[k].arsenalPts! -= p.cost
                realm.nations[k].powers = (realm.nations[k].powers ?? []) + [key]
                realm.nations[k].studying = nil
                emit("arsenal", [realm.nations[k].name(zh: zh), p.name(zh: zh)], towns(of: id).first?.center.center ?? .zero)
            }
        }
        // a united age shares what anyone has learned
        if realm.era == 1 {
            let all = Set(realm.nations.flatMap { $0.powers ?? [] })
            for k in realm.nations.indices { realm.nations[k].powers = Power.all.map { $0.key }.filter { all.contains($0) } }
        }
    }

    /// How much stronger an army is for what its nation has learned.
    func arsenalBonus(_ nation: Int) -> Double {
        let tiers = (realm.nation(nation)?.powers ?? []).reduce(0) { $0 + (Power.byKey[$1]?.tier ?? 0) }
        return 1 + min(realm.cfg.arsenalPowerCap, realm.cfg.arsenalPower * Double(tiers))
    }

    /// The most advanced thing a nation can field, for how its battles look.
    public func signaturePower(_ nation: Int) -> Power? {
        (realm.nation(nation)?.powers ?? []).compactMap { Power.byKey[$0] }.filter { $0.damage > 0 }.max { $0.tier != $1.tier ? $0.tier < $1.tier : $0.key > $1.key }
    }

    // MARK: the player's powers
    public func playerPowers() -> [Power] {
        var keys = Set(realm.player.artifacts ?? [])
        if realm.player.nation != 0 { for k in realm.nation(realm.player.nation)?.powers ?? [] { keys.insert(k) } }
        else { for n in realm.nations { for k in n.powers ?? [] { keys.insert(k) } } }     // a traveller learns wherever they go
        return Power.all.filter { keys.contains($0.key) }
    }

    public struct CastResult {
        public var ok = false
        public var reason = ""                 // "cooldown", "focus", "unknown", "range", "blocked"
        public var power: Power?
        public var hits: [(id: Int, pos: Vec2, damage: Double, dead: Bool)] = []
        public var beasts: [(pos: Vec2, dead: Bool)] = []
        public var path: [Vec2] = []           // start, (chain points...), impact
        public var impact = Vec2.zero
        public var healed = 0.0
        public var stunned = 0, spared = 0
        public var blinkTo: Vec2?
    }

    /// Damage one villager or soldier on the player's behalf; all the consequences follow.
    func playerHurt(_ a: Agent, _ dmg: Double) -> Bool {
        let s = side(of: a)
        let soldier = a.legion != nil
        let hp = (a.hp ?? realm.cfg.civilianHP) - dmg
        if hp <= 0 {
            die(a, "battle")
            realm.player.kills += 1
            addRep(s, soldier ? -0.12 : -0.3)
            if realm.player.nation != 0 {
                if realm.atWar(realm.player.nation, s) { addRep(realm.player.nation, 0.04) } else { shiftRelation(realm.player.nation, s, -0.12) }
            }
            if realm.player.partner == a.id { realm.player.partner = nil }
            return true
        }
        a.hp = hp
        addRep(s, soldier ? -0.04 : -0.1)
        if realm.player.nation != 0 && !realm.atWar(realm.player.nation, s) { shiftRelation(realm.player.nation, s, -0.03) }
        return false
    }

    /// Use a power. `clock` is real time in seconds; each power cools down on its own.
    public func playerCast(_ key: String, from pos: Vec2, target: Vec2, clock: Double) -> CastResult {
        var out = CastResult()
        guard let p = Power.byKey[key], realm.player.god == true || playerPowers().contains(where: { $0.key == key }) else { out.reason = "unknown"; return out }
        out.power = p
        var cds = realm.player.cooldowns ?? [:]
        if clock < (cds[key] ?? 0) { out.reason = "cooldown"; return out }
        let focus = realm.player.focus ?? 100
        if focus < p.focus && realm.player.god != true { out.reason = "focus"; return out }
        var aim = target
        let to = target - pos
        let dir = to.length > 0.01 ? to.normalized : Vec2(0, 1)
        if p.range > 0 && to.length > p.range { aim = pos + dir * p.range }
        if p.shape == Power.Shape.blink {
            let t = world.findFree(near: aim.tile, maxR: 3)
            if world.blocked(t.x, t.y) { out.reason = "blocked"; return out }
            out.blinkTo = t.center
        }
        cds[key] = clock + p.cooldown
        realm.player.cooldowns = cds
        if realm.player.god != true { realm.player.focus = focus - p.focus }
        out.ok = true
        out.impact = aim
        out.path = [pos, aim]
        let near = agents.values.filter { abs($0.pos.x - pos.x) < 1200 && abs($0.pos.y - pos.y) < 1200 }.sorted { $0.id < $1.id }
        let mine = realm.player.nation
        func foe(_ a: Agent) -> Bool { if mine != 0 && side(of: a) == mine { out.spared += 1; return false }; return true }
        func strike(_ list: [Agent], _ dmg: Double) {
            for a in list where foe(a) {
                let at = a.pos
                out.hits.append((a.id, at, dmg, playerHurt(a, dmg)))
            }
        }
        func along(_ maxT: Double, width: Double) -> [(Agent, Double)] {
            var l: [(Agent, Double)] = []
            for a in near {
                let v = a.pos - pos
                let t = v.x * dir.x + v.y * dir.y
                if t < 4 || t > maxT { continue }
                if abs(v.x * dir.y - v.y * dir.x) <= width { l.append((a, t)) }
            }
            return l.sorted { $0.1 < $1.1 }
        }
        switch p.shape {
        case Power.Shape.melee:
            strike(near.filter { let v = $0.pos - pos; return v.length <= p.range && (v.length < 8 || v.normalized.x * dir.x + v.normalized.y * dir.y > 0.3) }, p.damage)
            out.impact = pos + dir * (p.range * 0.7)
        case Power.Shape.shot:
            let reach = p.range > 0 ? p.range : 200
            if let first = along(reach, width: 10).first(where: { foe($0.0) }) { out.impact = first.0.pos; strike([first.0], p.damage) }
            else { out.impact = pos + dir * reach }
            out.path = [pos, out.impact]
        case Power.Shape.burst:
            // several rounds: each finds the first body still standing
            let n = max(1, Int(p.radius))
            for _ in 0..<n {
                guard let first = along(p.range, width: 14).first(where: { agents[$0.0.id] != nil && foe($0.0) }) else { break }
                strike([first.0], p.damage)
            }
            out.impact = pos + dir * p.range
            out.path = [pos, out.impact]
        case Power.Shape.beam:
            strike(along(p.range, width: 12).map { $0.0 }, p.damage)
            out.impact = pos + dir * p.range
            out.path = [pos, out.impact]
        case Power.Shape.blast, Power.Shape.sky:
            strike(near.filter { $0.pos.distance(to: aim) <= p.radius }, p.damage)
            if p.key == "gravity" { for a in near where a.pos.distance(to: aim) <= p.radius { a.stunUntil = world.time + 3; out.stunned += 1 } }
            out.beasts = hurtBeasts(at: aim, radius: p.radius, damage: p.damage)
        case Power.Shape.chain:
            var at = aim
            var done = Set<Int>()
            out.path = [pos]
            for _ in 0..<max(1, Int(p.radius)) {
                guard let next = near.filter({ agents[$0.id] != nil && !done.contains($0.id) && $0.pos.distance(to: at) <= 90 && (mine == 0 || side(of: $0) != mine) })
                        .min(by: { $0.pos.distance(to: at) < $1.pos.distance(to: at) }) else { break }
                done.insert(next.id)
                at = next.pos
                out.path.append(at)
                strike([next], p.damage)
            }
            if out.path.count == 1 { out.path.append(aim) }
            out.impact = out.path.last ?? aim
        case Power.Shape.heal:
            let before = realm.player.hp
            realm.player.hp = min(realm.cfg.playerHP, before + p.damage)
            out.healed = realm.player.hp - before
            out.impact = pos
        case Power.Shape.stun:
            let centre = p.range > 0 ? aim : pos
            out.impact = centre
            let secs = p.key == "timestop" ? 6.0 : (p.key == "halt" ? 4.0 : 2.5)
            for a in near where a.pos.distance(to: centre) <= p.radius && (mine == 0 || side(of: a) != mine) {
                a.stunUntil = world.time + secs
                out.stunned += 1
            }
            if p.damage > 0 { strike(near.filter { $0.pos.distance(to: centre) <= p.radius }, p.damage) }
            out.beasts = hurtBeasts(at: centre, radius: p.radius, damage: p.damage)
        case Power.Shape.ward:
            realm.player.wardUntil = clock + p.radius
            out.impact = pos
        case Power.Shape.grow:
            // crops ripen and saplings shoot up around the spoken word
            let c = aim.tile
            let r = Int(p.radius)
            for dy in -r...r { for dx in -r...r {
                let x = c.x + dx, y = c.y + dy
                let o = world.tile(2, x, y)
                if o == T["wheat_0"] || o == content.tid("wheat_1") { world.setTile(2, x, y, T["wheat_2"]!) }
                else if o == content.tid("sapling") { world.setTile(2, x, y, T["tree_oak"]!) }
                else if o == content.tid("sapling_pine") { world.setTile(2, x, y, content.tid("tree_pine")) }
                else if o == T["berry_bush_empty"] { world.setTile(2, x, y, T["berry_bush"]!) }
            } }
        case Power.Shape.calm:
            // the word of peace: everyone in earshot thinks better of the speaker, and soldiers stand down
            var nations = Set<Int>()
            for a in near where a.pos.distance(to: pos) <= p.radius { nations.insert(side(of: a)); a.stunUntil = world.time + 2 }
            for n in nations where n != 0 { addRep(n, 0.25) }
            out.stunned = nations.count
            out.impact = pos
        default: break
        }
        if p.shape == Power.Shape.melee { out.beasts += hurtBeasts(at: out.impact, radius: 18, damage: p.damage) }
        if p.shape == Power.Shape.shot || p.shape == Power.Shape.beam || p.shape == Power.Shape.burst {
            // animals on the line of fire: a beam goes through them all, a round stops in the first
            let reach = (out.impact - pos).length
            var onLine: [(Vec2, Double)] = []
            for b in realm.fauna.animals {
                let v = b.pos - pos
                let t = v.x * dir.x + v.y * dir.y
                if t >= 4 && t <= reach + 6 && abs(v.x * dir.y - v.y * dir.x) <= 10 + Double(b.species.size) * 2 { onLine.append((b.pos, t)) }
            }
            onLine.sort { $0.1 < $1.1 }
            let targets = p.shape == Power.Shape.beam ? onLine : Array(onLine.prefix(out.hits.isEmpty ? 1 : 0))
            for (at, _) in targets {
                out.beasts += hurtBeasts(at: at, radius: 3, damage: p.shape == Power.Shape.burst ? p.damage * p.radius : p.damage)
                if p.shape != Power.Shape.beam { out.impact = at; out.path = [pos, at] }
            }
        }
        return out
    }
}
