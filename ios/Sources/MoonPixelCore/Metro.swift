import Foundation

// Metro mode: build a modern city on a piece of the same generated land. Lay streets and avenues,
// zone land for homes, shops and industry, keep power and water flowing along the roads, place
// services, set taxes and watch the city grow (or empty out). Buildings rise by themselves where
// there is demand, a road, power and water; they level up where land is worth more, and are
// abandoned where people are unhappy for too long.
//
// One step is one day and every step is deterministic for a seed. The city is saved as JSON; the
// land under it is generated again from the seed when it is loaded. Nothing here touches the open
// world. Tiles are 16 units like everywhere else; x east, y south; index = y * size + x.

public enum MetroZone: UInt8, Codable { case none = 0, residential = 1, commercial = 2, industrial = 3 }

public enum MetroRoad: UInt8, Codable { case none = 0, street = 1, avenue = 2
    public var capacity: Double { self == .avenue ? 90 : 30 }
    public var cost: Double { self == .avenue ? 220 : 70 }
    public var upkeep: Double { self == .avenue ? 1.4 : 0.5 }
}

/// A service building: what it costs, what it does and from what population it can be built.
public struct MetroService {
    public let key: String, en: String, zh: String
    public let cost: Double, upkeep: Double
    public let w: Int, h: Int
    public let effect: String            // power, water, police, fire, health, education, park, landmark
    public let radius: Double            // tiles (coverage services)
    public let capacity: Double          // power or water units
    public let pollution: Double
    public let unlock: Int               // population needed
    public func name(zh z: Bool) -> String { z ? zh : en }

    public static let all: [MetroService] = [
        MetroService(key: "wind", en: "Wind turbines", zh: "风力发电", cost: 3200, upkeep: 14, w: 2, h: 2, effect: "power", radius: 0, capacity: 45, pollution: 0, unlock: 0),
        MetroService(key: "coal", en: "Coal plant", zh: "燃煤电厂", cost: 9000, upkeep: 38, w: 3, h: 3, effect: "power", radius: 0, capacity: 260, pollution: 45, unlock: 0),
        MetroService(key: "water", en: "Water tower", zh: "水塔", cost: 3600, upkeep: 20, w: 2, h: 2, effect: "water", radius: 0, capacity: 150, pollution: 0, unlock: 0),
        MetroService(key: "park", en: "Park", zh: "公园", cost: 1400, upkeep: 5, w: 2, h: 2, effect: "park", radius: 6, capacity: 0, pollution: 0, unlock: 0),
        MetroService(key: "police", en: "Police station", zh: "警察局", cost: 6000, upkeep: 28, w: 2, h: 2, effect: "police", radius: 11, capacity: 0, pollution: 0, unlock: 250),
        MetroService(key: "fire", en: "Fire station", zh: "消防站", cost: 6000, upkeep: 28, w: 2, h: 2, effect: "fire", radius: 11, capacity: 0, pollution: 0, unlock: 250),
        MetroService(key: "clinic", en: "Clinic", zh: "诊所", cost: 5000, upkeep: 26, w: 2, h: 2, effect: "health", radius: 9, capacity: 0, pollution: 0, unlock: 250),
        MetroService(key: "school", en: "School", zh: "学校", cost: 9000, upkeep: 40, w: 3, h: 2, effect: "education", radius: 12, capacity: 0, pollution: 0, unlock: 900),
        MetroService(key: "hospital", en: "Hospital", zh: "医院", cost: 18000, upkeep: 70, w: 3, h: 3, effect: "health", radius: 20, capacity: 0, pollution: 0, unlock: 2500),
        MetroService(key: "tower", en: "Moon tower", zh: "月光塔", cost: 30000, upkeep: 60, w: 2, h: 2, effect: "landmark", radius: 14, capacity: 0, pollution: 0, unlock: 5000),
    ]
    public static let index: [String: Int] = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1.key, $0) })
}

public struct MetroBuilding: Codable, Equatable {
    public var id = 0, kind = 0, x = 0, y = 0
    public var def: MetroService { MetroService.all[kind] }
}

/// Something worth telling the player.
public struct MetroEvent { public var text: String; public var good: Bool }

public final class Metro: Codable {
    public static let size = 64
    static let n = Metro.size

    // what is saved
    public let seed: Int, worldSeed: Int
    public let cx: Int, cy: Int
    public var name: String
    public private(set) var road: [UInt8]
    public private(set) var zone: [UInt8]
    public private(set) var level: [UInt8]                // 0: no building
    public private(set) var pop: [Int16]                  // residents (R) or workers (C, I)
    public private(set) var abandoned: [UInt8]            // days left before an abandoned building falls; 0 = in use
    var unhappy: [UInt8]
    public private(set) var owner: [Int32]                // service building on a tile
    public private(set) var services: [MetroBuilding] = []
    public private(set) var cleared: [Bool]               // trees and rocks taken away
    public private(set) var money: Double
    public private(set) var day = 0
    public var taxes: [Double] = [0.09, 0.09, 0.09]       // residential, commercial, industrial
    public private(set) var peak = 0
    var rng: RNG
    var nextID = 1

    // worked out again after loading
    public private(set) var layers: [[[UInt8]]] = []       // the four chunks of land (trees cleared where built)
    public private(set) var blocked: [Bool] = []
    public private(set) var waterNear: [Bool] = []
    var access: [Int32] = []                               // road tile a tile reaches, or -1
    var comp: [Int32] = []                                 // road network of a road tile
    public private(set) var powered: [Bool] = [], watered: [Bool] = []
    public private(set) var coverage: [String: [Float]] = [:]
    public private(set) var pollution: [Float] = [], noise: [Float] = [], landValue: [Float] = [], load: [Float] = [], happiness: [Float] = []
    var commute: [Float] = []
    var dirty = true
    public private(set) var events: [MetroEvent] = []
    public private(set) var demand: (r: Double, c: Double, i: Double) = (100, 50, 50)
    public private(set) var income = 0.0, expense = 0.0
    public private(set) var powerMade = 0.0, powerUsed = 0.0, waterMade = 0.0, waterUsed = 0.0
    public private(set) var unemployed = 0
    var acc = 0.0

    @inline(__always) static func idx(_ x: Int, _ y: Int) -> Int { y * n + x }
    @inline(__always) static func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < n && y < n }

    public init(seed: Int, worldSeed: Int, name: String = "Moonhaven", money: Double = 70000) {
        self.seed = seed; self.worldSeed = worldSeed; self.name = name; self.money = money
        rng = RNG(seed: seed &* 131 &+ 5)
        let count = Metro.n * Metro.n
        road = [UInt8](repeating: 0, count: count); zone = road; level = road; abandoned = road; unhappy = road
        pop = [Int16](repeating: 0, count: count); owner = [Int32](repeating: 0, count: count); cleared = [Bool](repeating: false, count: count)
        // a piece of land far from the villages with room to build, some water welcome
        let gen = Generator(seed: worldSeed)
        var probe = RNG(seed: seed &+ worldSeed &* 17)
        var best: (Double, Int, Int)?
        for _ in 0..<12 {
            let x = (320 + Int(probe.unit() * 500)) * (probe.unit() < 0.5 ? -1 : 1), y = (320 + Int(probe.unit() * 500)) * (probe.unit() < 0.5 ? -1 : 1)
            let ls = (0..<4).map { gen.generate(x + $0 % 2, y + $0 / 2).layers }
            let (bl, _) = Metro.terrain(ls)
            let free = Double(bl.filter { !$0 }.count) / Double(count)
            let score = free >= 0.97 ? 0.9 : (free < 0.55 ? free * 0.5 : free)         // a little water is nicer than none
            if best == nil || score > best!.0 { best = (score, x, y) }
            if score > 0.82 { break }
        }
        cx = best!.1; cy = best!.2
        rebuild()
    }

    static func terrain(_ ls: [[[UInt8]]]) -> (blocked: [Bool], water: [Bool]) {
        let c = Content.shared
        var bl = [Bool](repeating: false, count: n * n), wa = bl
        for (k, ch) in ls.enumerated() {
            for t in 0..<MP.chunkArea {
                let x = (k % 2) * 32 + t % 32, y = (k / 2) * 32 + t / 32
                let g = Int(ch[0][t]), s = Int(ch[1][t])
                let w = c.water[g]
                bl[idx(x, y)] = w || c.solid[g] || (s != 0 && c.solid[s])
                wa[idx(x, y)] = w
            }
        }
        return (bl, wa)
    }

    /// Everything that is not saved: the land and every map worked out from the saved state.
    func rebuild() {
        let gen = Generator(seed: worldSeed)
        layers = (0..<4).map { gen.generate(cx + $0 % 2, cy + $0 / 2).layers }
        let t = Metro.terrain(layers)
        blocked = t.blocked
        waterNear = [Bool](repeating: false, count: t.water.count)
        for y in 0..<Metro.n { for x in 0..<Metro.n where !t.water[Metro.idx(x, y)] {
            search: for dy in -3...3 { for dx in -3...3 where Metro.inside(x + dx, y + dy) && t.water[Metro.idx(x + dx, y + dy)] { waterNear[Metro.idx(x, y)] = true; break search } }
        } }
        for i in cleared.indices where cleared[i] { clearLand(i) }
        let count = Metro.n * Metro.n
        powered = [Bool](repeating: false, count: count); watered = powered
        pollution = [Float](repeating: 0, count: count); noise = pollution; landValue = pollution; load = pollution; happiness = pollution; commute = pollution
        access = [Int32](repeating: -1, count: count); comp = access
        dirty = true
        refresh()
    }

    func clearLand(_ i: Int) {
        cleared[i] = true
        let x = i % Metro.n, y = i / Metro.n
        let k = (y / 32) * 2 + x / 32, t = (y % 32) * 32 + x % 32
        layers[k][2][t] = 0; layers[k][3][t] = 0
    }

    // MARK: saving

    enum Key: String, CodingKey { case v, seed, worldSeed, cx, cy, name, road, zone, level, pop, abandoned, unhappy, owner, services, cleared, money, day, taxes, peak, rng, nextID }

    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: Key.self)
        try c.encode(1, forKey: .v)
        try c.encode(seed, forKey: .seed); try c.encode(worldSeed, forKey: .worldSeed); try c.encode(cx, forKey: .cx); try c.encode(cy, forKey: .cy)
        try c.encode(name, forKey: .name)
        try c.encode(Data(road), forKey: .road); try c.encode(Data(zone), forKey: .zone); try c.encode(Data(level), forKey: .level)
        try c.encode(pop, forKey: .pop); try c.encode(Data(abandoned), forKey: .abandoned); try c.encode(Data(unhappy), forKey: .unhappy)
        try c.encode(owner, forKey: .owner); try c.encode(services, forKey: .services); try c.encode(cleared, forKey: .cleared)
        try c.encode(money, forKey: .money); try c.encode(day, forKey: .day); try c.encode(taxes, forKey: .taxes); try c.encode(peak, forKey: .peak)
        try c.encode(rng, forKey: .rng); try c.encode(nextID, forKey: .nextID)
    }

    public required init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Key.self)
        guard try c.decode(Int.self, forKey: .v) == 1 else { throw DecodingError.dataCorruptedError(forKey: .v, in: c, debugDescription: "unknown city format") }
        seed = try c.decode(Int.self, forKey: .seed); worldSeed = try c.decode(Int.self, forKey: .worldSeed)
        cx = try c.decode(Int.self, forKey: .cx); cy = try c.decode(Int.self, forKey: .cy)
        name = try c.decode(String.self, forKey: .name)
        road = [UInt8](try c.decode(Data.self, forKey: .road)); zone = [UInt8](try c.decode(Data.self, forKey: .zone)); level = [UInt8](try c.decode(Data.self, forKey: .level))
        pop = try c.decode([Int16].self, forKey: .pop); abandoned = [UInt8](try c.decode(Data.self, forKey: .abandoned)); unhappy = [UInt8](try c.decode(Data.self, forKey: .unhappy))
        owner = try c.decode([Int32].self, forKey: .owner); services = try c.decode([MetroBuilding].self, forKey: .services); cleared = try c.decode([Bool].self, forKey: .cleared)
        money = try c.decode(Double.self, forKey: .money); day = try c.decode(Int.self, forKey: .day); taxes = try c.decode([Double].self, forKey: .taxes); peak = try c.decode(Int.self, forKey: .peak)
        rng = try c.decode(RNG.self, forKey: .rng); nextID = try c.decode(Int.self, forKey: .nextID)
        let count = Metro.n * Metro.n
        guard [road.count, zone.count, level.count, pop.count, abandoned.count, unhappy.count, owner.count, cleared.count].allSatisfy({ $0 == count }) else {
            throw DecodingError.dataCorruptedError(forKey: .road, in: c, debugDescription: "the city's maps have the wrong size")
        }
        rebuild()
    }

    // MARK: reading

    public var population: Int { var s = 0; for i in zone.indices where zone[i] == 1 { s += Int(pop[i]) }; return s }
    public var jobs: (c: Int, i: Int) {
        var c = 0, i = 0
        for t in zone.indices { if zone[t] == 2 { c += Int(pop[t]) } else if zone[t] == 3 { i += Int(pop[t]) } }
        return (c, i)
    }
    public func unlocked(_ k: Int) -> Bool { peak >= MetroService.all[k].unlock }
    public var avenueUnlocked: Bool { peak >= 900 }

    public static func capacity(_ z: UInt8, _ lv: UInt8) -> Int {
        guard lv > 0 else { return 0 }
        switch z {
        case 1: return [0, 6, 16, 40][Int(lv)]
        case 2: return [0, 4, 10, 24][Int(lv)]
        case 3: return [0, 8, 16, 28][Int(lv)]
        default: return 0
        }
    }

    public func takeEvents() -> [MetroEvent] { let e = events; events.removeAll(); return e }

    /// Calendar: twelve months of thirty days.
    public var date: (year: Int, month: Int, day: Int) { (1 + day / 360, 1 + (day / 30) % 12, 1 + day % 30) }

    public func isRoad(_ x: Int, _ y: Int) -> Bool { Metro.inside(x, y) && road[Metro.idx(x, y)] != 0 }

    /// What a tile is, in a few words.
    public func describe(_ x: Int, _ y: Int, zh: Bool) -> [String] {
        guard Metro.inside(x, y) else { return [] }
        let i = Metro.idx(x, y)
        func pct(_ v: Float) -> String { "\(Int((v * 100).rounded()))%" }
        if owner[i] != 0, let b = services.first(where: { $0.id == Int(owner[i]) }) {
            let d = b.def
            var out = [d.name(zh: zh), (zh ? "维护 " : "upkeep ") + String(format: "%.0f/", d.upkeep) + (zh ? "天" : "day")]
            let a = Int(access[Metro.idx(b.x, b.y)])
            if a < 0 { out.append(zh ? "⚠ 未连通道路" : "⚠ not on a road") }
            if d.effect == "power" { out.append(String(format: zh ? "电力 %.0f / %.0f" : "power %.0f of %.0f", powerUsed, powerMade)) }
            if d.effect == "water" { out.append(String(format: zh ? "供水 %.0f / %.0f" : "water %.0f of %.0f", waterUsed, waterMade)) }
            return out
        }
        if road[i] != 0 {
            let r = MetroRoad(rawValue: road[i]) ?? .street
            return [r == .avenue ? (zh ? "大道" : "Avenue") : (zh ? "街道" : "Street"), (zh ? "车流 " : "traffic ") + pct(load[i] / Float(r.capacity))]
        }
        if blocked[i] { return [zh ? "水域" : "Water"] }
        let z = zone[i]
        guard z != 0 else { return [(zh ? "空地 · 地价 " : "Open land · value ") + "\(Int(landValue[i]))"] }
        let kind = [zh ? "住宅" : "Residential", zh ? "商业" : "Commercial", zh ? "工业" : "Industrial"][Int(z) - 1]
        guard level[i] > 0 else { return [kind + (zh ? "区（空）" : " zone (empty)"), access[i] < 0 ? (zh ? "⚠ 离道路太远" : "⚠ too far from a road") : (zh ? "等待需求" : "waiting for demand")] }
        var out = [kind + " · " + (zh ? "等级 " : "level ") + "\(level[i])"]
        if abandoned[i] > 0 { out.append(zh ? "已废弃" : "Abandoned") }
        out.append((z == 1 ? (zh ? "居民 " : "residents ") : (zh ? "岗位 " : "workers ")) + "\(pop[i])/\(Metro.capacity(z, level[i]))")
        out.append((zh ? "幸福 " : "happiness ") + "\(Int(happiness[i]))  " + (zh ? "地价 " : "value ") + "\(Int(landValue[i]))")
        var lacks: [String] = []
        if !powered[i] { lacks.append(zh ? "电" : "power") }
        if !watered[i] { lacks.append(zh ? "水" : "water") }
        if pollution[i] > 30 { lacks.append(zh ? "污染" : "pollution") }
        if commute[i] > 1.2 { lacks.append(zh ? "拥堵" : "traffic jams") }
        if z == 1 && commute[i] < 0 { lacks.append(zh ? "无法通勤" : "no way to work") }
        if !lacks.isEmpty { out.append((zh ? "问题：" : "problems: ") + lacks.joined(separator: zh ? "、" : ", ")) }
        return out
    }

    // MARK: building

    /// The tiles of a road from one tile to another: along x first, then along y.
    public static func path(_ a: TilePos, _ b: TilePos) -> [TilePos] {
        var out: [TilePos] = []
        let sx = b.x >= a.x ? 1 : -1, sy = b.y >= a.y ? 1 : -1
        var x = a.x
        while true { out.append(TilePos(x, a.y)); if x == b.x { break }; x += sx }
        var y = a.y
        while y != b.y { y += sy; out.append(TilePos(b.x, y)) }
        return out
    }

    /// What a road would cost, and whether it can be laid at all (water and services are in the way).
    public func roadPlan(_ a: TilePos, _ b: TilePos, _ kind: MetroRoad) -> (cost: Double, ok: Bool, tiles: [TilePos]) {
        let tiles = Metro.path(a, b).filter { Metro.inside($0.x, $0.y) }
        var cost = 0.0, ok = !tiles.isEmpty && (kind != .avenue || avenueUnlocked)
        for t in tiles {
            let i = Metro.idx(t.x, t.y)
            if blocked[i] || owner[i] != 0 { ok = false; continue }
            let have = MetroRoad(rawValue: road[i]) ?? .none
            if have == kind || (have == .avenue && kind == .street) { continue }
            cost += kind.cost - (have == .street ? MetroRoad.street.cost : 0)
        }
        return (cost, ok && cost <= money, tiles)
    }

    @discardableResult public func buildRoad(_ a: TilePos, _ b: TilePos, _ kind: MetroRoad) -> Bool {
        let p = roadPlan(a, b, kind)
        guard p.ok else { return false }
        for t in p.tiles {
            let i = Metro.idx(t.x, t.y)
            if road[i] == MetroRoad.avenue.rawValue && kind == .street { continue }
            clearLot(i)
            road[i] = kind.rawValue
            clearLand(i)
        }
        money -= p.cost
        dirty = true
        refresh()
        return true
    }

    func clearLot(_ i: Int) { zone[i] = 0; level[i] = 0; pop[i] = 0; abandoned[i] = 0; unhappy[i] = 0 }

    func rect(_ a: TilePos, _ b: TilePos) -> [Int] {
        var out: [Int] = []
        for y in max(0, min(a.y, b.y))...min(Metro.n - 1, max(a.y, b.y)) { for x in max(0, min(a.x, b.x))...min(Metro.n - 1, max(a.x, b.x)) { out.append(Metro.idx(x, y)) } }
        return out
    }

    /// Zone the land in a rectangle (only land a road reaches; roads, water and services stay). Free, like in most cities.
    @discardableResult public func setZone(_ a: TilePos, _ b: TilePos, _ z: MetroZone) -> Int {
        if dirty { network() }
        var n = 0
        for i in rect(a, b) where !blocked[i] && road[i] == 0 && owner[i] == 0 && (access[i] >= 0 || z == .none) {
            if zone[i] == z.rawValue { continue }
            clearLot(i)
            zone[i] = z.rawValue
            n += 1
        }
        if n > 0 { refresh() }
        return n
    }

    /// Clear everything in a rectangle: roads, buildings, services. Nothing is paid back.
    @discardableResult public func bulldoze(_ a: TilePos, _ b: TilePos) -> Int {
        var n = 0
        var gone = Set<Int32>()
        for i in rect(a, b) {
            if road[i] != 0 { road[i] = 0; dirty = true; n += 1 }
            if level[i] != 0 || zone[i] != 0 { clearLot(i); n += 1 }
            if owner[i] != 0 { gone.insert(owner[i]) }
        }
        for id in gone { removeService(Int(id)); n += 1 }
        if n > 0 { refresh() }
        return n
    }

    func removeService(_ id: Int) {
        services.removeAll { $0.id == id }
        for i in owner.indices where owner[i] == Int32(id) { owner[i] = 0 }
        dirty = true
    }

    public func canPlace(_ kind: Int, at t: TilePos) -> Bool {
        let d = MetroService.all[kind]
        guard unlocked(kind), money >= d.cost else { return false }
        for y in t.y..<(t.y + d.h) { for x in t.x..<(t.x + d.w) {
            guard Metro.inside(x, y) else { return false }
            let i = Metro.idx(x, y)
            if blocked[i] || road[i] != 0 || owner[i] != 0 { return false }
        } }
        return true
    }

    @discardableResult public func placeService(_ kind: Int, at t: TilePos) -> Bool {
        guard canPlace(kind, at: t) else { return false }
        let d = MetroService.all[kind]
        let b = MetroBuilding(id: nextID, kind: kind, x: t.x, y: t.y)
        nextID += 1
        services.append(b)
        for y in t.y..<(t.y + d.h) { for x in t.x..<(t.x + d.w) { let i = Metro.idx(x, y); clearLot(i); owner[i] = Int32(b.id); clearLand(i) } }
        money -= d.cost
        dirty = true
        refresh()
        return true
    }

    public func setTax(_ z: Int, _ rate: Double) { taxes[z] = min(0.25, max(0.01, rate)) }

    // MARK: maps

    /// Which road each tile reaches (lots up to three tiles from a road; a service by any side) and which network each road is in.
    func network() {
        let n = Metro.n
        access = [Int32](repeating: -1, count: n * n)
        comp = [Int32](repeating: -1, count: n * n)
        var c: Int32 = 0
        for s in 0..<(n * n) where road[s] != 0 && comp[s] < 0 {
            var q = [s]; comp[s] = c
            var h = 0
            while h < q.count {
                let i = q[h]; h += 1
                for j in neighbours(i) where road[j] != 0 && comp[j] < 0 { comp[j] = c; q.append(j) }
            }
            c += 1
        }
        // lots: a flood from every road, three steps over free land
        var dist = [UInt8](repeating: 255, count: n * n)
        var q: [Int] = []
        for i in 0..<(n * n) where road[i] != 0 { access[i] = Int32(i); dist[i] = 0; q.append(i) }
        var h = 0
        while h < q.count {
            let i = q[h]; h += 1
            if dist[i] >= 3 { continue }
            for j in neighbours(i) where road[j] == 0 && !blocked[j] && owner[j] == 0 && dist[j] == 255 {
                dist[j] = dist[i] + 1; access[j] = access[i]; q.append(j)
            }
        }
        // services: every tile of one is reached through a road beside any side of it
        for b in services {
            let d = b.def
            var a: Int32 = -1
            outer: for y in (b.y - 1)...(b.y + d.h) { for x in (b.x - 1)...(b.x + d.w) where Metro.inside(x, y) && road[Metro.idx(x, y)] != 0 { a = Int32(Metro.idx(x, y)); break outer } }
            for y in b.y..<(b.y + d.h) { for x in b.x..<(b.x + d.w) { access[Metro.idx(x, y)] = a } }
        }
        dirty = false
    }

    @inline(__always) func neighbours(_ i: Int) -> [Int] {
        let n = Metro.n, x = i % n, y = i / n
        var out: [Int] = []
        out.reserveCapacity(4)
        if x + 1 < n { out.append(i + 1) }
        if x > 0 { out.append(i - 1) }
        if y + 1 < n { out.append(i + n) }
        if y > 0 { out.append(i - n) }
        return out
    }

    func networkOf(_ i: Int) -> Int32 { let a = Int(access[i]); return a >= 0 ? comp[a] : -1 }

    /// Power and water run along the roads: each network shares what its plants and towers make.
    func utilities() {
        var made: [Int32: (p: Double, w: Double)] = [:], used: [Int32: (p: Double, w: Double)] = [:]
        powerMade = 0; waterMade = 0; powerUsed = 0; waterUsed = 0
        for b in services {
            let c = networkOf(Metro.idx(b.x, b.y))
            guard c >= 0 else { continue }
            var m = made[c] ?? (0, 0)
            if b.def.effect == "power" { m.p += b.def.capacity; powerMade += b.def.capacity }
            if b.def.effect == "water" { m.w += b.def.capacity; waterMade += b.def.capacity }
            made[c] = m
        }
        for i in level.indices where level[i] > 0 && abandoned[i] == 0 {
            let c = networkOf(i)
            guard c >= 0 else { continue }
            let need = Double(level[i]) * (zone[i] == 3 ? 2 : 1)
            var u = used[c] ?? (0, 0)
            u.p += need; u.w += need
            used[c] = u
            powerUsed += need; waterUsed += need
        }
        for i in level.indices {
            powered[i] = false; watered[i] = false
            let c = networkOf(i)
            guard c >= 0 else { continue }
            let m = made[c] ?? (0, 0), u = used[c] ?? (0, 0)
            // short supply reaches only part of the network: the same lots each day, picked by place
            let share = Double(MP.h2(seed, i, 7) % 1000) / 1000
            powered[i] = m.p > 0 && (u.p <= m.p || share < m.p / u.p)
            watered[i] = m.w > 0 && (u.w <= m.w || share < m.w / u.w)
        }
    }

    func spread(_ into: inout [Float], at b: MetroBuilding, radius: Double, value: Float, falloff: Bool) {
        let d = b.def
        let cx = Double(b.x) + Double(d.w) / 2, cy = Double(b.y) + Double(d.h) / 2
        let r = Int(radius.rounded(.up))
        for y in max(0, Int(cy) - r - 1)...min(Metro.n - 1, Int(cy) + r) { for x in max(0, Int(cx) - r - 1)...min(Metro.n - 1, Int(cx) + r) {
            let dist = ((Double(x) + 0.5 - cx) * (Double(x) + 0.5 - cx) + (Double(y) + 0.5 - cy) * (Double(y) + 0.5 - cy)).squareRoot()
            guard dist <= radius else { continue }
            let v = falloff ? value * Float(1 - dist / (radius + 1)) : value * Float(1 - 0.5 * dist / radius)
            let i = Metro.idx(x, y)
            into[i] = max(into[i], v)
        } }
    }

    func maps() {
        let count = Metro.n * Metro.n
        var cov: [String: [Float]] = [:]
        for k in ["police", "fire", "health", "education", "park", "landmark"] { cov[k] = [Float](repeating: 0, count: count) }
        pollution = [Float](repeating: 0, count: count)
        for b in services {
            let on = networkOf(Metro.idx(b.x, b.y)) >= 0 && (b.def.effect == "park" || b.def.effect == "power" || b.def.effect == "water" || powered[Metro.idx(b.x, b.y)])
            if b.def.pollution > 0 { var p = pollution; spread(&p, at: b, radius: 9, value: Float(b.def.pollution), falloff: true); pollution = zip(pollution, p).map { max($0, $1) } }
            guard on, b.def.radius > 0, cov[b.def.effect] != nil else { continue }
            spread(&cov[b.def.effect]!, at: b, radius: b.def.radius, value: 1, falloff: false)
        }
        // industry pollutes around itself
        var add = [Float](repeating: 0, count: count)
        for i in level.indices where zone[i] == 3 && level[i] > 0 && abandoned[i] == 0 {
            let x = i % Metro.n, y = i / Metro.n, e = Float(5 + 4 * Int(level[i]))
            for dy in -5...5 { for dx in -5...5 where Metro.inside(x + dx, y + dy) {
                let d = Float((dx * dx + dy * dy)).squareRoot()
                if d <= 5 { add[Metro.idx(x + dx, y + dy)] += e * (1 - d / 6) }
            } }
        }
        for i in 0..<count { pollution[i] = min(100, pollution[i] + add[i]) }
        // noise: busy roads are heard next to them
        noise = [Float](repeating: 0, count: count)
        for i in 0..<count where road[i] != 0 {
            let r = MetroRoad(rawValue: road[i]) ?? .street
            let v = min(100, load[i] / Float(r.capacity) * 40 + (r == .avenue ? 10 : 0))
            for j in neighbours(i) + [i] { noise[j] = max(noise[j], v) }
        }
        coverage = cov
        landValue = (0..<count).map { i in
            var v: Float = 46
            v += cov["park"]![i] * 25 + cov["landmark"]![i] * 30
            v += (cov["police"]![i] + cov["health"]![i] + cov["education"]![i] + cov["fire"]![i]) * 5
            if waterNear[i] { v += 12 }
            v -= pollution[i] * 0.6 + noise[i] * 0.15
            return min(100, max(0, v))
        }
    }

    /// Everyone who works goes to the nearest job by road; shoppers go to the nearest shop. Each trip is
    /// laid on every road it uses, which gives the traffic on each road and how jammed each commute is.
    func traffic() {
        let count = Metro.n * Metro.n
        load = [Float](repeating: 0, count: count)
        commute = [Float](repeating: 0, count: count)
        func field(_ zones: Set<UInt8>) -> [Int32] {
            var dist = [Int32](repeating: -1, count: count)
            var q: [Int] = []
            for i in 0..<count where zones.contains(zone[i]) && level[i] > 0 && abandoned[i] == 0 && pop[i] > 0 {
                let a = Int(access[i]); if a >= 0 && dist[a] < 0 { dist[a] = 0; q.append(a) }
            }
            var h = 0
            while h < q.count {
                let i = q[h]; h += 1
                for j in neighbours(i) where road[j] != 0 && dist[j] < 0 { dist[j] = dist[i] + 1; q.append(j) }
            }
            return dist
        }
        let work = field([2, 3]), shops = field([2])
        func walk(from start: Int, _ f: [Int32], trips: Float) -> (Float, Int) {
            var i = start, jam: Float = 0, steps = 0
            while f[i] > 0 && steps < 400 {
                load[i] += trips
                let r = MetroRoad(rawValue: road[i]) ?? .street
                jam += load[i] / Float(r.capacity)
                var next = -1, bestCap = -1.0
                for j in neighbours(i) where road[j] != 0 && f[j] == f[i] - 1 {
                    let c = (MetroRoad(rawValue: road[j]) ?? .street).capacity
                    if c > bestCap { bestCap = c; next = j }               // the bigger road when there is a choice
                }
                if next < 0 { break }
                i = next; steps += 1
            }
            if f[i] == 0 { load[i] += trips }
            return (jam, steps + 1)
        }
        unemployed = 0
        for i in 0..<count where zone[i] == 1 && level[i] > 0 && abandoned[i] == 0 && pop[i] > 0 {
            let a = Int(access[i])
            let workers = Float(pop[i]) * 0.6
            guard a >= 0, work[a] >= 0 else { commute[i] = -1; unemployed += Int(workers); continue }
            let (jam, steps) = walk(from: a, work, trips: workers)
            _ = walk(from: a, shops, trips: Float(pop[i]) * 0.25)
            commute[i] = jam / Float(max(1, steps))
        }
    }

    func moods() {
        let tax = taxes
        happiness = (0..<(Metro.n * Metro.n)).map { i in
            guard level[i] > 0 else { return 0 }
            let z = Int(zone[i])
            var h: Float = 52
            h += powered[i] ? 8 : -30
            h += watered[i] ? 8 : -30
            h += (coverage["police"]?[i] ?? 0) * 8 + (coverage["fire"]?[i] ?? 0) * 6 + (coverage["health"]?[i] ?? 0) * 8
            if z == 1 { h += (coverage["education"]?[i] ?? 0) * 6 }
            h += (landValue[i] - 50) * 0.25
            if z != 3 { h -= pollution[i] * 0.45 }
            if z == 1 { h -= noise[i] * 0.2 }
            if commute[i] < 0 { h -= 15 } else if commute[i] > 1 { h -= min(25, (commute[i] - 1) * 18) }
            h -= Float(max(0, tax[z - 1] - 0.09)) * 220
            h += Float(max(0, 0.09 - tax[z - 1])) * 80
            return min(100, max(0, h))
        }
    }

    func demands() {
        let r = Double(population), j = jobs
        let workers = r * 0.6
        let jobsAll = Double(j.c + j.i)
        var dr = (jobsAll * 1.15 + 40 - workers) / max(30, workers) * 100
        var dc = (workers * 0.3 + r * 0.08 + 12 - Double(j.c)) / max(15, workers * 0.3) * 100
        var di = (workers * 0.7 + 20 - Double(j.i)) / max(20, workers * 0.7) * 100
        dr -= (taxes[0] - 0.09) * 500; dc -= (taxes[1] - 0.09) * 500; di -= (taxes[2] - 0.09) * 500
        if unemployed > Int(workers * 0.2) { dr -= 20 }
        demand = (min(100, max(-100, dr)), min(100, max(-100, dc)), min(100, max(-100, di)))
    }

    /// Work out every map from the city as it stands (after a change, without a day passing).
    func refresh() {
        if dirty { network() }
        utilities(); traffic(); maps(); moods(); demands()          // noise needs today's traffic
    }

    // MARK: a day

    public func tick(_ seconds: Double, daysPerSecond: Double) {
        acc += seconds * daysPerSecond
        var budget = 8                                          // never more than eight days in one frame
        while acc >= 1 && budget > 0 { acc -= 1; budget -= 1; step() }
        if budget == 0 { acc = min(acc, 1) }
    }

    /// One day: buildings grow or empty, money comes and goes, then every map is worked out again, so
    /// what is shown and saved at the end of a day is always consistent with the city.
    public func step() {
        day += 1
        grow()
        pay()
        refresh()
        let p = population
        if p > peak {
            for (k, s) in MetroService.all.enumerated() where s.unlock > peak && s.unlock <= p {
                events.append(MetroEvent(text: s.zh + "|" + s.en, good: true)); _ = k
            }
            if peak < 900 && p >= 900 { events.append(MetroEvent(text: "大道|Avenues", good: true)) }
            peak = p
        }
    }

    func grow() {
        let n = Metro.n * Metro.n
        // every lot is looked at each day, in an order shuffled by the seed
        var order = Array(0..<n)
        for k in stride(from: n - 1, to: 0, by: -1) { order.swapAt(k, rng.index(k + 1)) }
        let want: [Double] = [0, demand.r, demand.c, demand.i]
        for i in order where zone[i] != 0 {
            let z = Int(zone[i])
            let d = want[z]
            if abandoned[i] > 0 {
                abandoned[i] -= 1
                if abandoned[i] == 0 { level[i] = 0; pop[i] = 0 }      // the empty building is pulled down; the lot can grow again
                continue
            }
            if level[i] == 0 {
                // a new building needs a road, power, water and someone who wants it
                if access[i] >= 0 && powered[i] && watered[i] && d > 0 && rng.unit() < 0.01 + d / 100 * 0.05 {
                    level[i] = 1; pop[i] = 1; unhappy[i] = 0
                }
                continue
            }
            let cap = Metro.capacity(zone[i], level[i])
            if d > -10 && Int(pop[i]) < cap && rng.unit() < 0.35 + max(0, d) / 200 { pop[i] += Int16(max(1, cap / 8)) ; pop[i] = Int16(min(cap, Int(pop[i]))) }
            if d < -40 && pop[i] > 1 && rng.unit() < 0.2 { pop[i] -= 1 }
            // better land, happy people and (for homes and shops) schooling lift a building
            let lv = Int(level[i])
            let need: Float = [0, 45, 65, 101][lv]
            let schooled = z == 3 || lv < 2 || (coverage["education"]?[i] ?? 0) > 0.3
            if lv < 3 && Int(pop[i]) >= cap && landValue[i] >= need && happiness[i] >= 55 && schooled && rng.unit() < 0.03 { level[i] += 1 }
            if lv > 1 && landValue[i] < [0, 0, 30, 50][lv] && rng.unit() < 0.01 { level[i] -= 1; pop[i] = Int16(min(Int(pop[i]), Metro.capacity(zone[i], level[i]))) }
            // too long unhappy: they leave
            if happiness[i] < 25 { unhappy[i] = min(255, unhappy[i] + 1) } else { unhappy[i] = 0 }
            if unhappy[i] >= 12 { abandoned[i] = 20; pop[i] = 0; unhappy[i] = 0 }
        }
    }

    func pay() {
        let j = jobs
        income = Double(population) * 3.6 * taxes[0] + Double(j.c) * 4.4 * taxes[1] + Double(j.i) * 3.4 * taxes[2]
        var out = 0.0
        for i in road.indices where road[i] != 0 { out += (MetroRoad(rawValue: road[i]) ?? .street).upkeep }
        for b in services { out += b.def.upkeep }
        expense = out
        let was = money
        money += income - expense
        if was >= 0 && money < 0 { events.append(MetroEvent(text: "资金为负|The city is in debt", good: false)) }
    }

    // MARK: overlays

    /// One number per tile for an overlay, 0...1 (higher is the stronger colour), and whether it is good.
    public func overlay(_ k: String) -> [Float] {
        switch k {
        case "traffic": return road.indices.map { road[$0] == 0 ? -1 : min(1, load[$0] / Float((MetroRoad(rawValue: road[$0]) ?? .street).capacity) / 1.5) }
        case "pollution": return pollution.map { $0 / 100 }
        case "value": return landValue.map { $0 / 100 }
        case "happiness": return level.indices.map { level[$0] > 0 ? happiness[$0] / 100 : -1 }
        case "power": return level.indices.map { zone[$0] == 0 && owner[$0] == 0 ? -1 : (powered[$0] ? 1 : 0) }
        case "water": return level.indices.map { zone[$0] == 0 && owner[$0] == 0 ? -1 : (watered[$0] ? 1 : 0) }
        default: return coverage[k] ?? []
        }
    }

    /// A line that two runs can be compared by.
    public var summary: String {
        let j = jobs
        let built = level.filter { $0 > 0 }.count
        return String(format: "d%d pop %d jobs %d/%d lots %d money %.0f R%.0f C%.0f I%.0f", day, population, j.c, j.i, built, money, demand.r, demand.c, demand.i)
    }

    // MARK: a ready-made town

    /// Lay out a small town the same way every time: a grid of streets with an avenue through it, power,
    /// water, a park, homes on one side, shops in the middle and industry downwind. For tests and the demo.
    public func layOutDemo() {
        money = max(money, 150000)
        // find the largest open square for the grid
        var c = TilePos(Metro.n / 2, Metro.n / 2)
        var best = -1
        for y in stride(from: 14, to: Metro.n - 14, by: 4) { for x in stride(from: 14, to: Metro.n - 14, by: 4) {
            var free = 0
            for dy in -12...12 { for dx in -12...12 where !blocked[Metro.idx(x + dx, y + dy)] { free += 1 } }
            if free > best { best = free; c = TilePos(x, y) }
        } }
        let x0 = c.x - 12, x1 = c.x + 12, y0 = c.y - 12, y1 = c.y + 12
        for y in stride(from: y0, through: y1, by: 6) { buildRoad(TilePos(x0, y), TilePos(x1, y), .street) }
        for x in stride(from: x0, through: x1, by: 6) { buildRoad(TilePos(x, y0), TilePos(x, y1), .street) }
        let coal = MetroService.index["coal"]!, wt = MetroService.index["water"]!, park = MetroService.index["park"]!
        for (k, p) in [(coal, TilePos(x1 + 1, y0 + 14)), (MetroService.index["wind"]!, TilePos(x1 + 1, y0 + 18)), (MetroService.index["wind"]!, TilePos(x1 + 1, y0 + 21)), (wt, TilePos(x1 + 1, y0 + 2)), (wt, TilePos(x1 + 1, y0 + 6)), (wt, TilePos(x1 + 1, y0 + 9)), (park, TilePos(x0 + 2, y0 + 2)), (park, TilePos(x0 + 2, y0 + 14))] {
            if !placeService(k, at: p) {
                // something is in the way: anywhere along the east street
                for yy in y0..<y1 where placeService(k, at: TilePos(x1 + 1, yy)) { break }
            }
        }
        setZone(TilePos(x0, y0), TilePos(c.x - 1, y1), .residential)
        setZone(TilePos(c.x, y0), TilePos(c.x + 5, y1), .commercial)
        setZone(TilePos(c.x + 6, y0), TilePos(x1, y1), .industrial)
        setZone(TilePos(x0 + 2, y0 + 2), TilePos(x0 + 3, y0 + 3), .none)
        setZone(TilePos(x0 + 2, y0 + 14), TilePos(x0 + 3, y0 + 15), .none)
    }
}

public extension PixelArt {
    /// A building of metro mode seen like everything else (a front and a top), 16 pixels wide per tile
    /// and as tall as it is. variant picks colours so a street does not look copied.
    static func metro(zone: Int, level: Int, variant: Int, abandoned: Bool) -> Bitmap {
        let walls = [["#e8d8c0", "#d8c0a8", "#f0e6d0", "#c8b8a8"], ["#d0d8e8", "#e0e4ec", "#c0d0e0", "#e8e0d8"], ["#a8a49c", "#b8b0a0", "#989ca0", "#a0988c"]]
        let roofs = ["#b04a38", "#5a6c88", "#4a7a4a", "#8a5a30", "#6a4a7a"]
        let z = max(1, min(3, zone)), lv = max(1, min(3, level))
        var wall = RGBA(hex: walls[z - 1][variant % 4])
        var roof = RGBA(hex: roofs[(variant / 4) % roofs.count])
        let glass = RGBA(hex: z == 2 ? "#7ad0f0" : "#5a7a9a"), dark = RGBA(hex: "#2a2e38")
        if abandoned { wall = wall.lerp(RGBA(hex: "#6a6460"), 0.6); roof = roof.lerp(RGBA(hex: "#4a4440"), 0.6) }
        let heights = [[0, 20, 28, 44], [0, 20, 34, 52], [0, 20, 28, 32]]
        let h = heights[z - 1][lv]
        var b = Bitmap(16, h)
        let top = h - 16                       // the top of the building is drawn above the tile
        switch (z, lv) {
        case (1, 1):
            b.rect(2, top + 4, 12, 12, wall); b.rect(1, top, 14, 6, roof); b.rect(2, top + 1, 12, 1, roof.lightened(0.2))
            b.rect(4, top + 9, 3, 3, glass); b.rect(9, top + 10, 3, 6, dark.lerp(roof, 0.3))
        case (1, 2):
            b.rect(1, 6, 14, h - 6, wall); b.rect(0, 2, 16, 5, roof); b.rect(1, 3, 14, 1, roof.lightened(0.2))
            for y in stride(from: 9, to: h - 6, by: 6) { for x in [3, 7, 11] { b.rect(x, y, 2, 3, glass) } }
            b.rect(7, h - 5, 3, 5, dark)
        case (1, 3):
            b.rect(2, 2, 12, h - 2, wall); b.rect(1, 0, 14, 3, wall.darkened(0.25))
            for y in stride(from: 5, to: h - 4, by: 4) { for x in [4, 7, 10] { b.rect(x, y, 2, 2, glass.lightened(Double((x + y + variant) % 3) * 0.15)) } }
            b.rect(6, h - 4, 4, 4, dark)
        case (2, 1):
            b.rect(1, top + 4, 14, 12, wall); b.rect(1, top + 3, 14, 3, roof); for x in stride(from: 1, to: 15, by: 3) { b.rect(x, top + 6, 2, 2, roof.lightened(0.3)) }
            b.rect(2, top + 9, 12, 5, glass); b.rect(6, top + 10, 3, 6, dark)
        case (2, 2):
            b.rect(1, 2, 14, h - 2, wall.darkened(0.1)); b.rect(1, 0, 14, 3, dark)
            for y in stride(from: 4, to: h - 6, by: 4) { b.rect(2, y, 12, 2, glass) }
            b.rect(3, h - 6, 10, 6, glass.darkened(0.3))
        case (2, _):
            b.rect(2, 0, 12, h, glass.darkened(0.15)); b.rect(2, 0, 3, h, glass.lightened(0.25))
            for y in stride(from: 2, to: h, by: 3) { b.rect(2, y, 12, 1, glass.darkened(0.35)) }
            b.rect(7, 0, 2, 2, RGBA(hex: "#ff5a5a"))
        case (3, 1):
            b.rect(1, top + 5, 14, 11, wall); b.rect(1, top + 3, 14, 3, wall.darkened(0.3)); b.rect(3, top + 9, 6, 7, dark.lerp(wall, 0.3))
        case (3, 2):
            b.rect(1, 12, 14, h - 12, wall); b.rect(1, 10, 14, 3, wall.darkened(0.3)); b.rect(10, 0, 3, 12, RGBA(hex: "#8a5a4a")); b.rect(9, 0, 5, 2, RGBA(hex: "#6a4a3a"))
            b.rect(3, 17, 5, 11, dark.lerp(wall, 0.3))
        default:
            b.rect(0, 10, 16, h - 10, wall); b.rect(0, 8, 16, 3, wall.darkened(0.3))
            b.rect(2, 0, 3, 10, RGBA(hex: "#8a8a8a")); b.rect(8, 2, 3, 8, RGBA(hex: "#8a8a8a")); b.disc(9.5, 13, 3, RGBA(hex: "#c8c8c8"))
            b.rect(3, 20, 10, h - 20, dark.lerp(wall, 0.3))
        }
        if abandoned { for k in 0..<5 { b.set((variant * 7 + k * 5) % 14 + 1, (variant * 3 + k * 9) % max(1, h - 2) + 1, dark) } }
        return b
    }

    /// A service building of metro mode, as wide as its footprint.
    static func metroService(_ s: MetroService) -> Bitmap {
        let w = s.w * 16, h = s.h * 16 + 14
        var b = Bitmap(w, h)
        let concrete = RGBA(hex: "#b8bcc4"), dark = RGBA(hex: "#3a3e48"), white = RGBA.white
        func base(_ c: RGBA) { b.rect(1, 14, w - 2, h - 15, c); b.rect(1, 12, w - 2, 3, c.lightened(0.25)); b.rect(1, h - 4, w - 2, 3, c.darkened(0.3)) }
        switch s.key {
        case "wind":
            b.rect(0, h - 16, w, 16, RGBA(hex: "#7aa860"))
            for (x, y) in [(8, 4), (22, 10)] { b.rect(x, y, 2, h - y - 4, white); b.disc(Double(x) + 1, Double(y), 2, white); b.rect(x - 6, y - 1, 6, 1, white); b.rect(x + 2, y, 5, 1, white); b.rect(x, y - 7, 1, 6, white) }
        case "coal":
            base(RGBA(hex: "#7a6a5a")); b.rect(6, 0, 6, 16, RGBA(hex: "#9a8a7a")); b.rect(16, 4, 6, 12, RGBA(hex: "#9a8a7a")); b.rect(5, 0, 8, 2, RGBA(hex: "#c84a3a"))
            b.rect(w - 16, 20, 12, 12, dark); b.disc(Double(w) - 10, 26, 4, RGBA(hex: "#ff9a3a"))
        case "water":
            b.rect(12, 18, 2, h - 18, dark); b.rect(w - 14, 18, 2, h - 18, dark); b.disc(Double(w) / 2, 12, 11, RGBA(hex: "#4a90d8")); b.disc(Double(w) / 2 - 3, 9, 4, RGBA(hex: "#9ac8f0"))
        case "park":
            b.rect(0, 14, w, h - 14, RGBA(hex: "#5fa84a")); b.rect(w / 2 - 1, 14, 3, h - 14, RGBA(hex: "#d8c890"))
            for (x, y) in [(6, 18), (24, 22), (8, 34), (25, 38)] { b.disc(Double(x), Double(y), 5, RGBA(hex: "#2f7030")); b.disc(Double(x) - 1, Double(y) - 1, 3, RGBA(hex: "#4e9440")) }
            b.disc(Double(w) / 2, 30, 4, RGBA(hex: "#4a90d8"))
        case "police":
            base(RGBA(hex: "#3a5a9a")); b.rect(6, 18, w - 12, 6, RGBA(hex: "#c8d8f0")); b.rect(w / 2 - 3, 4, 6, 10, RGBA(hex: "#3a5a9a")); b.rect(w / 2 - 2, 2, 2, 3, RGBA(hex: "#ff4040")); b.rect(w / 2 + 1, 2, 2, 3, RGBA(hex: "#4080ff"))
        case "fire":
            base(RGBA(hex: "#b03a30")); b.rect(4, h - 18, 10, 14, dark); b.rect(w - 14, h - 18, 10, 14, dark); b.rect(w / 2 - 3, 2, 6, 12, RGBA(hex: "#c84a3a"))
        case "clinic", "hospital":
            base(white.darkened(0.06)); b.rect(w / 2 - 6, 18, 12, 4, RGBA(hex: "#e84a4a")); b.rect(w / 2 - 2, 14, 4, 12, RGBA(hex: "#e84a4a"))
            for x in stride(from: 4, to: w - 4, by: 6) { b.rect(x, h - 14, 3, 4, RGBA(hex: "#7ab0d8")) }
        case "school":
            base(RGBA(hex: "#c88a4a")); b.rect(w / 2 - 6, 2, 12, 12, RGBA(hex: "#c88a4a")); b.disc(Double(w) / 2, 8, 3, white)
            for x in stride(from: 4, to: w - 4, by: 6) { b.rect(x, 20, 3, 4, RGBA(hex: "#7ab0d8")) }
        default:
            b.rect(w / 2 - 4, 0, 8, h - 4, RGBA(hex: "#c8d0e8")); b.rect(w / 2 - 2, 0, 4, h - 4, RGBA(hex: "#9fe8ff")); b.disc(Double(w) / 2, 6, 5, RGBA(hex: "#9fe8ff")); b.rect(4, h - 6, w - 8, 5, dark)
        }
        return b
    }

    /// A road tile: which sides it joins (1 north, 2 east, 4 south, 8 west) and whether it is an avenue.
    static func metroRoad(mask: Int, avenue: Bool) -> Bitmap {
        var b = Bitmap(16, 16, fill: RGBA(hex: "#c8c4bc"))
        let asphalt = RGBA(hex: avenue ? "#3a3c44" : "#4a4c54"), line = RGBA(hex: avenue ? "#f0d060" : "#e8e8e8")
        let m = avenue ? 0 : 2
        b.rect(m, m, 16 - 2 * m, 16 - 2 * m, asphalt)
        if mask & 1 != 0 { b.rect(m, 0, 16 - 2 * m, m, asphalt) }
        if mask & 4 != 0 { b.rect(m, 16 - m, 16 - 2 * m, m, asphalt) }
        if mask & 8 != 0 { b.rect(0, m, m, 16 - 2 * m, asphalt) }
        if mask & 2 != 0 { b.rect(16 - m, m, m, 16 - 2 * m, asphalt) }
        let ns = mask & 5 != 0, ew = mask & 10 != 0
        if ns && !ew { for y in stride(from: 1, to: 16, by: 5) { b.rect(7, y, 2, 3, line) } }
        if ew && !ns { for x in stride(from: 1, to: 16, by: 5) { b.rect(x, 7, 3, 2, line) } }
        if avenue && ns && !ew { b.rect(7, 0, 2, 16, RGBA(hex: "#5fa84a")) }
        if avenue && ew && !ns { b.rect(0, 7, 16, 2, RGBA(hex: "#5fa84a")) }
        return b
    }
}
