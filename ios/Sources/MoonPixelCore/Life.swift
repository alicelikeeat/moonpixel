import Foundation

/// Weather, animals, romance with the player, leisure, cheats and maze treasure.
public struct Weather: Codable {
    public var kind = 0            // 0 clear, 1 cloudy, 2 rain, 3 storm, 4 fog, 5 heat
    public var until = 0.0
    public var rng = RNG(seed: 9)
    public static let names: [(String, String)] = [("Clear", "晴"), ("Cloudy", "多云"), ("Rain", "雨"), ("Thunderstorm", "雷暴"), ("Fog", "雾"), ("Heatwave", "酷热")]
    public init() {}
}

public struct Species {
    public let key: String, en: String, zh: String
    public let hp: Double, speed: Double, meat: Double
    public let hostile: Bool, tameable: Bool
    public let size: Int
    public let body: String, accent: String
    public static let all: [Species] = [
        Species(key: "rabbit", en: "Rabbit", zh: "兔子", hp: 20, speed: 60, meat: 2, hostile: false, tameable: true, size: 0, body: "#d8d0c4", accent: "#f4b8c0"),
        Species(key: "deer", en: "Deer", zh: "鹿", hp: 50, speed: 62, meat: 6, hostile: false, tameable: false, size: 2, body: "#b07a48", accent: "#f0e0c0"),
        Species(key: "boar", en: "Boar", zh: "野猪", hp: 70, speed: 44, meat: 7, hostile: false, tameable: false, size: 1, body: "#6a4a3a", accent: "#e8e0d0"),
        Species(key: "wolf", en: "Wolf", zh: "狼", hp: 60, speed: 58, meat: 2, hostile: true, tameable: false, size: 1, body: "#7a7f8a", accent: "#e0e4ea"),
        Species(key: "bear", en: "Bear", zh: "熊", hp: 160, speed: 40, meat: 10, hostile: true, tameable: false, size: 3, body: "#5a4030", accent: "#8a6a50"),
        Species(key: "sheep", en: "Sheep", zh: "羊", hp: 40, speed: 34, meat: 5, hostile: false, tameable: true, size: 1, body: "#f0ece0", accent: "#4a4040"),
        Species(key: "cow", en: "Cow", zh: "牛", hp: 90, speed: 30, meat: 10, hostile: false, tameable: true, size: 3, body: "#f4f0e8", accent: "#3a3030"),
        Species(key: "chicken", en: "Chicken", zh: "鸡", hp: 12, speed: 36, meat: 2, hostile: false, tameable: true, size: 0, body: "#f8f4ec", accent: "#e04838"),
        Species(key: "fox", en: "Fox", zh: "狐狸", hp: 35, speed: 64, meat: 2, hostile: false, tameable: true, size: 1, body: "#e07830", accent: "#f8f0e8"),
        Species(key: "camel", en: "Camel", zh: "骆驼", hp: 100, speed: 36, meat: 8, hostile: false, tameable: true, size: 3, body: "#d0a868", accent: "#a88048"),
        Species(key: "horse", en: "Horse", zh: "马", hp: 90, speed: 70, meat: 8, hostile: false, tameable: true, size: 3, body: "#8a5a38", accent: "#3a2a20"),
        Species(key: "golem", en: "Maze golem", zh: "迷宫石像", hp: 180, speed: 30, meat: 0, hostile: true, tameable: false, size: 3, body: "#7a8088", accent: "#60e0ff"),
    ]
    static let byBiome: [String: [String]] = [
        "grassland": ["rabbit", "sheep", "cow", "horse", "chicken", "rabbit", "wolf"], "forest": ["deer", "boar", "rabbit", "wolf", "deer", "fox"],
        "taiga": ["deer", "wolf", "bear", "fox"], "snow": ["fox", "wolf"], "desert": ["camel"], "canyon": ["camel"],
        "wetland": ["boar", "chicken"], "beach": ["chicken"],
    ]
    public static func index(_ key: String) -> Int { all.firstIndex { $0.key == key } ?? 0 }
}

public struct Animal: Codable {
    public var id = 0, kind = 0
    public var pos = Vec2.zero, to = Vec2.zero
    public var hp = 10.0
    public var tame = false
    public var facing = 1.0
    public var think = 0.0
    public var moving = false
    public var species: Species { Species.all[min(kind, Species.all.count - 1)] }
}

public struct Fauna: Codable {
    public var animals: [Animal] = []
    public var nextID = 1
    public var rng = RNG(seed: 5)
    public var acc = 0.0
    public var maxNear = 16
    public init() {}
}

/// Something that happened and deserves an effect on screen (lightning, fireworks...). Never saved.
public struct WorldFX { public var kind: String; public var pos: Vec2 }

extension Society {
    // MARK: weather
    public var weatherName: String { let n = Weather.names[min(realm.weather.kind, Weather.names.count - 1)]; return zh ? n.1 : n.0 }

    /// What falls here: 0 nothing, 1 rain, 2 snow, 3 fog, 4 heat shimmer; and whether there is thunder.
    public func weather(at pos: Vec2) -> (fall: Int, thunder: Bool, dim: Double) {
        let k = realm.weather.kind
        let cold = world.gen.climate(pos.tile.x, pos.tile.y).1 < 0.3
        switch k {
        case 1: return (0, false, 0.12)
        case 2: return (cold ? 2 : 1, false, 0.22)
        case 3: return (cold ? 2 : 1, true, 0.38)
        case 4: return (3, false, 0.15)
        case 5: return (4, false, 0)
        default: return (0, false, 0)
        }
    }

    func marchWeather() -> Double { [1.0, 1.0, 0.85, 0.7, 0.9, 0.9][min(realm.weather.kind, 5)] }

    public func setWeather(_ kind: Int, hours: Double = 8) {
        realm.weather.kind = max(0, min(5, kind))
        realm.weather.until = world.time + hours * Society.hour
    }

    func weatherHourly() {
        let cfg = realm.cfg
        if realm.weather.until == 0 { realm.weather.rng = RNG(seed: world.seed &+ 4242) }
        if world.time >= realm.weather.until {
            // weighted, seeded: mostly fair, sometimes wet, now and then wild
            let w = [42.0, 22, 16, 6, 7, 7]
            var x = realm.weather.rng.unit() * w.reduce(0, +)
            var k = 0
            for i in 0..<w.count { k = i; x -= w[i]; if x < 0 { break } }
            realm.weather.kind = k
            realm.weather.until = world.time + realm.weather.rng.range(3, 10) * Society.hour
        }
        let k = realm.weather.kind
        let towns = settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        if k == 2 || k == 3 { for s in towns { s.food += cfg.rainFood * Double(s.count("farm", done: true)) } }
        if k == 5 { for s in towns { s.food *= 1 - cfg.heatSpoil } }
        if k == 3, !towns.isEmpty, realm.weather.rng.unit() < cfg.lightningChance {
            // lightning finds a tree; now and then a roof
            let s = towns[realm.weather.rng.index(towns.count)]
            if let t = s.trees.isEmpty ? nil : s.trees[realm.weather.rng.index(s.trees.count)], isTree(t) {
                world.setTile(2, t.x, t.y, content.tid("dead_tree"))
                pushFX("lightning", t.center)
            }
            if realm.weather.rng.unit() < cfg.lightningDamage { damage(s, buildings: 1) }
        }
    }

    func pushFX(_ kind: String, _ pos: Vec2) {
        if pendingFX.count < realm.cfg.maxEffects { pendingFX.append(WorldFX(kind: kind, pos: pos)) }
    }

    /// Effects waiting to be drawn. The scene takes them; nothing accumulates when nobody is watching.
    public func takeFX() -> [WorldFX] { let l = pendingFX; pendingFX.removeAll(); return l }

    // MARK: animals (they live around whoever is watching; herds far away are not simulated)
    func biomeKey(_ t: TilePos) -> String { content.biomes[world.gen.biome(t.x, t.y)].key }

    @discardableResult public func spawnAnimal(_ key: String, at pos: Vec2, tame: Bool = false) -> Int {
        var a = Animal()
        a.id = realm.fauna.nextID; realm.fauna.nextID += 1
        a.kind = Species.index(key)
        a.pos = pos; a.to = pos
        a.hp = a.species.hp
        a.tame = tame
        realm.fauna.animals.append(a)
        return a.id
    }

    public func faunaTick(_ dt: Double, viewer: Vec2, mazeHere: Bool) -> Double {
        var bite = 0.0
        var f = realm.fauna
        f.acc += dt
        if f.acc >= 2 {
            f.acc = 0
            f.animals.removeAll { !$0.tame && $0.pos.distance(to: viewer) > 1500 }
            let wild = f.animals.filter { !$0.tame }.count
            if wild < f.maxNear {
                // new arrivals appear just out of sight, of a kind that lives in that country
                let ang = f.rng.unit() * 2 * Double.pi
                let p = viewer + Vec2(cos(ang), sin(ang)) * f.rng.range(520, 760)
                let t = p.tile
                if !world.blocked(t.x, t.y), let list = Species.byBiome[biomeKey(t)], world.gen.isMaze(t.x >> 5, t.y >> 5) == false {
                    let key = list[f.rng.index(list.count)]
                    realm.fauna = f
                    let herd = Species.all[Species.index(key)].hostile ? 1 : f.rng.int(1, 3)
                    for i in 0..<herd { spawnAnimal(key, at: world.findFree(near: TilePos(t.x + i, t.y), maxR: 3).center) }
                    f = realm.fauna
                }
            }
            if mazeHere && f.animals.filter({ $0.species.key == "golem" }).count < 3 {
                let t = world.findFree(near: (viewer + Vec2(f.rng.range(-140, 140), f.rng.range(-140, 140))).tile, maxR: 4)
                if !world.blocked(t.x, t.y) && t.center.distance(to: viewer) > 60 { realm.fauna = f; spawnAnimal("golem", at: t.center); f = realm.fauna }
            }
        }
        for i in f.animals.indices {
            var a = f.animals[i]
            let sp = a.species
            let d = a.pos.distance(to: viewer)
            a.think -= dt
            if a.tame { if d > 34 { a.to = viewer } else { a.to = a.pos } }
            else if sp.hostile && d < 170 {
                a.to = viewer
                if d < 18 { bite += (sp.key == "bear" || sp.key == "golem" ? 14 : 8) * dt }
            } else if !sp.hostile && d < 64 {
                a.to = a.pos + (a.pos - viewer).normalized * 90            // prey bolts
            } else if a.think <= 0 {
                a.think = f.rng.range(1.5, 5)
                a.to = a.pos + Vec2(f.rng.range(-70, 70), f.rng.range(-70, 70))
            }
            let to = a.to - a.pos
            a.moving = to.length > 2
            if a.moving {
                let step = sp.speed * (a.tame || (sp.hostile && d < 170) || (!sp.hostile && d < 64) ? 1.0 : 0.45) * dt
                let np = to.length <= step ? a.to : a.pos + to.normalized * step
                // slide along whatever is in the way, one axis at a time
                var moved = false
                for cand in [np, Vec2(np.x, a.pos.y), Vec2(a.pos.x, np.y), Vec2(a.pos.x + (to.y >= 0 ? step : -step), a.pos.y), Vec2(a.pos.x, a.pos.y + (to.x >= 0 ? step : -step))] {
                    let t = cand.tile
                    if !world.blocked(t.x, t.y) { a.pos = cand; moved = true; break }
                }
                if !moved { a.to = a.pos } else if abs(to.x) > 0.5 { a.facing = to.x < 0 ? -1 : 1 }
            }
            f.animals[i] = a
        }
        realm.fauna = f
        return bite
    }

    /// Damage every animal in a circle. Meat from the dead goes into the player's pack.
    func hurtBeasts(at p: Vec2, radius: Double, damage: Double) -> [(pos: Vec2, dead: Bool)] {
        if damage <= 0 { return [] }
        var out: [(pos: Vec2, dead: Bool)] = []
        var keep: [Animal] = []
        for var a in realm.fauna.animals {
            if a.pos.distance(to: p) > radius + Double(a.species.size) * 3 { keep.append(a); continue }
            a.hp -= damage
            if a.hp <= 0 { realm.player.food += a.species.meat; out.append((a.pos, true)) }
            else { a.tame = false; out.append((a.pos, false)); keep.append(a) }
        }
        realm.fauna.animals = keep
        return out
    }

    /// Befriend the nearest gentle animal with food: it follows the player from then on.
    public func playerTame(near pos: Vec2) -> String? {
        guard let i = realm.fauna.animals.indices.filter({ !realm.fauna.animals[$0].tame && realm.fauna.animals[$0].pos.distance(to: pos) < 60 })
                .min(by: { realm.fauna.animals[$0].pos.distance(to: pos) < realm.fauna.animals[$1].pos.distance(to: pos) }) else { return "none" }
        if !realm.fauna.animals[i].species.tameable { return "wild" }
        if realm.player.food < 3 { return "food" }
        realm.player.food -= 3
        realm.fauna.animals[i].tame = true
        return nil
    }

    func petsHourly() {
        // tame livestock earn their keep
        for a in realm.fauna.animals where a.tame && ["cow", "sheep", "chicken"].contains(a.species.key) { realm.player.food += 0.25 }
    }

    // MARK: leisure
    func leisureHourly() {
        let cfg = realm.cfg
        for s in settlements.values.filter({ !$0.abandoned }).sorted(by: { $0.id < $1.id }) {
            let pop = s.members.count
            guard pop >= 8, world.time >= (realm.cool["festival:\(s.id)"] ?? 0), !realm.atWar(s.nation ?? 0),
                  s.food >= Double(pop) * cfg.festivalFood, world.hour >= 17, world.hour < 21 else { continue }
            // a feast when the stores are full: everyone eats, laughs, and remembers it
            realm.cool["festival:\(s.id)"] = world.time + cfg.festivalEvery * MP.year
            s.food -= Double(pop)
            s.unrest = max(0, (s.unrest ?? 0) - 0.2)
            for id in s.members { if let a = agents[id] { a.fun = 0; a.social = 0; a.hunger = max(0, a.hunger - 0.3); a.think(world.time, "t_festival") } }
            emit("festival", [s.name(zh: zh)], s.center.center)
            for k in 0..<6 { pushFX("firework", s.center.center + Vec2(Double(k * 40 - 100), -60 - Double(k % 3) * 30)) }
        }
    }

    public struct DiceResult { public var you = 0, them = 0, won = 0.0, reason = "" }

    /// Dice against a villager for food. Both sides stake the same; the town's pot pays their side.
    public func playerDice(_ id: Int, stake: Double = 5) -> DiceResult {
        var r = DiceResult()
        guard let a = agents[id], a.stage(world.time) != "child", let s = settlements[a.sid] else { r.reason = "nobody"; return r }
        if realm.player.food < stake { r.reason = "food"; return r }
        if s.food < stake * 2 { r.reason = "poor"; return r }
        r.you = realm.rng.int(1, 6) + realm.rng.int(1, 6)
        r.them = realm.rng.int(1, 6) + realm.rng.int(1, 6)
        if r.you > r.them { r.won = stake; s.food -= stake; realm.player.food += stake }
        else if r.you < r.them { r.won = -stake; s.food += stake; realm.player.food -= stake }
        a.fun = 0
        a.rel[0] = min(1, (a.rel[0] ?? 0) + 0.05)
        return r
    }

    // MARK: romance with the player
    public func affection(_ id: Int) -> Double { agents[id]?.rel[0] ?? 0 }

    /// "flower" or "food". Returns nil on success.
    public func playerGift(_ id: Int, _ kind: String) -> String? {
        guard let a = agents[id] else { return "nobody" }
        if kind == "flower" {
            if (realm.player.flowers ?? 0) < 1 { return "flower" }
            realm.player.flowers! -= 1
            a.rel[0] = min(1, (a.rel[0] ?? 0) + 0.18)
        } else {
            if realm.player.food < 2 { return "food" }
            realm.player.food -= 2
            a.hunger = max(0, a.hunger - 0.5)
            a.rel[0] = min(1, (a.rel[0] ?? 0) + 0.12)
        }
        a.think(world.time, "t_gift")
        return nil
    }

    /// Pick the flower on this tile, if there is one.
    @discardableResult public func playerPick(at t: TilePos) -> Bool {
        let d = world.tile(3, t.x, t.y)
        guard d == content.tid("flower_red") || d == content.tid("flower_yellow") || d == content.tid("flower_blue") else { return false }
        world.setTile(3, t.x, t.y, 0)
        realm.player.flowers = (realm.player.flowers ?? 0) + 1
        return true
    }

    /// A walk together: they keep the player company for a while.
    public func playerDate(_ id: Int) -> String? {
        guard let a = agents[id] else { return "nobody" }
        if a.stage(world.time) == "child" { return "child" }
        if (a.rel[0] ?? 0) < 0.5 { return "stranger" }
        if world.time < (realm.cool["date:\(id)"] ?? 0) { return "soon" }
        realm.cool["date:\(id)"] = world.time + 6 * Society.hour
        a.followUntil = world.time + 3 * Society.hour
        a.fun = 0; a.social = 0
        a.rel[0] = min(1, (a.rel[0] ?? 0) + 0.12)
        a.think(world.time, "t_date")
        return nil
    }

    public func playerPropose(_ id: Int) -> String? {
        guard let a = agents[id] else { return "nobody" }
        if realm.player.partner != nil && agents[realm.player.partner!] != nil { return "married" }
        if a.age(world.time) < 18 { return "child" }
        if a.partner != 0 { return "taken" }
        if (a.rel[0] ?? 0) < 0.85 { return "notyet" }
        realm.player.partner = id
        a.rel[0] = 1
        a.think(world.time, "t_love", [zh ? "你" : "you"])
        emit("wedding_player", [a.name(zh: zh)], a.pos)
        for k in 0..<5 { pushFX("firework", a.pos + Vec2(Double(k * 30 - 60), -70)) }
        return nil
    }

    public func playerPartUp() {
        if let id = realm.player.partner, let a = agents[id] { a.rel[0] = 0.2; a.grief = min(1, a.grief + 0.5); a.think(world.time, "t_breakup") }
        realm.player.partner = nil
    }

    /// The player's spouse keeps a little food aside for them.
    func spouseHourly() {
        guard let id = realm.player.partner else { return }
        guard let a = agents[id] else { realm.player.partner = nil; return }
        if a.hunger < 0.6 { realm.player.food += 0.5 }
    }

    // MARK: cheats (always marked on the save)
    @discardableResult public func cheat(_ what: String, at pos: Vec2 = .zero) -> Bool {
        realm.player.cheated = true
        switch what {
        case "god": realm.player.god = !(realm.player.god ?? false)
        case "rich": realm.player.food += 200; realm.player.wood += 200; realm.player.stone += 200; realm.player.flowers = (realm.player.flowers ?? 0) + 20
        case "powers": realm.player.artifacts = Power.all.map { $0.key }
        case "tech": for k in realm.nations.indices { realm.nations[k].techCount = min(Society.techs.count, realm.nations[k].techCount + 1) }; legacyTech = techCount
        case "peace": for r in realm.relations.indices where realm.relations[r].state == 1 { setState(r, 2) }
        case "dawn":
            let day = MP.daySeconds
            let into = world.time.truncatingRemainder(dividingBy: day)
            world.time += (into < 0.27 * day ? 0.27 * day - into : day - into + 0.27 * day)
        case "heal": realm.player.hp = realm.cfg.playerHP; realm.player.focus = 100
        case "animals": for k in ["horse", "cow", "sheep", "chicken", "fox", "rabbit"] { spawnAnimal(k, at: world.findFree(near: (pos + Vec2(Double(k.count * 9 - 40), 30)).tile, maxR: 4).center, tame: true) }
        case "people":
            guard let s = town(near: pos, radius: 5000) else { return false }
            for i in 0..<10 { newAgent(s, age: rng.range(17, 34), female: i % 2 == 0).nation = s.nation }
        case "love": if let a = agent(near: pos, radius: 80) { a.rel[0] = 1 } else { return false }
        default:
            if what.hasPrefix("weather:"), let k = Int(what.dropFirst(8)) { setWeather(k) } else { return false }
        }
        return true
    }

    // MARK: mazes
    /// Open the treasure at the heart of a maze. Each chest gives once.
    public func playerOpenChest(at t: TilePos) -> (ok: Bool, power: Power?) {
        guard world.tile(2, t.x, t.y) == T["chest"], world.gen.isMaze(t.x >> 5, t.y >> 5) else { return (false, nil) }
        world.setTile(2, t.x, t.y, content.tid("altar_pure"))          // an opened chest stays opened
        realm.player.food += 30; realm.player.wood += 30; realm.player.stone += 30
        var r = RNG(seed: world.seed &+ t.x &* 31 &+ t.y)
        let have = Set(realm.player.artifacts ?? [])
        let pool = Power.all.filter { !have.contains($0.key) && $0.tier >= 3 }
        guard !pool.isEmpty else { return (true, nil) }
        let p = pool[r.index(pool.count)]
        realm.player.artifacts = (realm.player.artifacts ?? []) + [p.key]
        return (true, p)
    }

    /// Nearest maze to a chunk, searching outwards.
    public func nearestMaze(cx: Int, cy: Int, within r: Int = 24) -> (Int, Int)? {
        var best: (Int, Int)?, bestD = Int.max
        for y in (cy - r)...(cy + r) { for x in (cx - r)...(cx + r) where world.gen.isMaze(x, y) {
            let d = (x - cx) * (x - cx) + (y - cy) * (y - cy)
            if d < bestD { bestD = d; best = (x, y) }
        } }
        return best
    }
}

extension PixelArt {
    /// Small side-view sprite for an animal (facing right), two walking frames.
    public static func animal(_ sp: Species, frame: Int, tame: Bool) -> Bitmap {
        let body = RGBA(hex: sp.body), accent = RGBA(hex: sp.accent), ink = RGBA(hex: "#2a2233")
        let dims: [(Int, Int, Int)] = [(8, 5, 2), (11, 6, 4), (12, 6, 5), (14, 8, 6)]     // body w, body h, leg length
        let (bw, bh, leg) = dims[min(sp.size, 3)]
        var b = Bitmap(24, 22)
        let x0 = 4, y0 = 20 - leg - bh
        if sp.key == "chicken" {
            b.rect(9, 12, 6, 5, body); b.rect(13, 9, 4, 4, body); b.set(17, 11, RGBA(hex: "#f0a020")); b.rect(14, 8, 2, 1, accent)
            b.set(15, 10, ink); b.rect(7, 12, 2, 3, body.darkened(0.12))
            b.rect(10 + frame % 2, 17, 1, 3, RGBA(hex: "#f0a020")); b.rect(13 - frame % 2, 17, 1, 3, RGBA(hex: "#f0a020"))
        } else if sp.key == "golem" {
            b.rect(7, 4, 10, 11, body); b.rect(9, 1, 6, 4, body.lightened(0.1)); b.rect(10, 2, 1, 1, accent); b.rect(13, 2, 1, 1, accent)
            b.rect(5, 6, 2, 8, body.darkened(0.15)); b.rect(17, 6, 2, 8, body.darkened(0.15)); b.rect(11, 8, 2, 3, accent)
            b.rect(8 + frame % 2, 15, 3, 5, body.darkened(0.2)); b.rect(13 - frame % 2, 15, 3, 5, body.darkened(0.2))
        } else {
            b.rect(x0, y0, bw, bh, body)
            b.rect(x0, y0 + bh - 2, bw, 2, body.darkened(0.12))
            // head, towards the right
            let hx = x0 + bw - 1, hy = y0 - (sp.size >= 2 ? 3 : 1)
            b.rect(hx, hy, 4, 4, sp.key == "sheep" || sp.key == "cow" ? accent.lerp(body, sp.key == "cow" ? 0.0 : 0.2) : body)
            b.set(hx + 2, hy + 1, ink)
            switch sp.key {
            case "rabbit": b.rect(hx + 1, hy - 3, 1, 3, body); b.rect(hx + 2, hy - 3, 1, 3, accent); b.rect(x0 - 1, y0 + 1, 1, 2, .white)
            case "deer": b.rect(hx + 1, hy - 3, 1, 3, accent); b.rect(hx + 3, hy - 3, 1, 3, accent); b.set(hx, hy - 3, accent); b.set(hx + 4, hy - 3, accent); b.rect(x0 + 2, y0 + 1, 2, 1, accent)
            case "boar": b.rect(hx + 3, hy + 2, 2, 1, accent); b.rect(x0 + 1, y0 - 1, bw - 2, 1, body.darkened(0.3))
            case "wolf", "fox": b.set(hx, hy - 1, body); b.set(hx + 2, hy - 1, body); b.rect(x0 - 3, y0 + 1, 3, 2, sp.key == "fox" ? accent : body.darkened(0.2)); b.rect(hx + 2, hy + 3, 2, 1, accent)
            case "bear": b.set(hx, hy - 1, body); b.set(hx + 3, hy - 1, body); b.rect(hx + 3, hy + 2, 1, 1, accent)
            case "cow": b.rect(x0 + 3, y0 + 1, 3, 3, accent); b.rect(x0 + 9, y0, 2, 2, accent); b.set(hx, hy - 1, .white); b.set(hx + 3, hy - 1, .white)
            case "camel": b.rect(x0 + 3, y0 - 3, 3, 3, body); b.rect(x0 + 8, y0 - 3, 3, 3, body); b.rect(hx + 1, hy - 3, 2, 4, body)
            case "horse": b.rect(hx - 1, hy - 1, 2, 5, accent); b.rect(x0 - 2, y0, 2, 5, accent); b.rect(hx + 1, hy - 2, 2, 2, body)
            default: break
            }
            let step = frame % 2
            let lc = body.darkened(0.25)
            b.rect(x0 + 1 + step, y0 + bh, 1 + sp.size / 2, leg, lc); b.rect(x0 + 4 - step, y0 + bh, 1 + sp.size / 2, leg, lc)
            b.rect(x0 + bw - 5 + step, y0 + bh, 1 + sp.size / 2, leg, lc); b.rect(x0 + bw - 2 - step, y0 + bh, 1 + sp.size / 2, leg, lc)
        }
        // dark outline, like the villagers
        var out = b
        for y in 0..<22 { for x in 0..<24 where b.get(x, y).a < 128 {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                if nx >= 0 && ny >= 0 && nx < 24 && ny < 22 && b.get(nx, ny).a >= 128 { out.set(x, y, ink); break }
            }
        } }
        if tame { out.rect(1, 1, 3, 2, RGBA(hex: "#ff6088")); out.set(2, 3, RGBA(hex: "#ff6088")) }
        return out
    }
}
