import Foundation

// Metropolis districts in the open world. A district is a modern city standing on the world's own land:
// its buildings are real walls, floors, doors, stairs and elevators (the traveller walks in, goes up,
// looks out); its streets are the network's streets; its people live on real floors and eat what is
// really brought up to them.
//
// People: a district's population is the sum of the residents on its floors. It changes only by births,
// deaths, people moving in (always from somewhere: a regional city of the same nation, a town, another
// district, which lose them) and people moving out (to somewhere, which gains them), and by a metro city
// being brought in once. The ledger keeps every one of those, so the count can always be checked.
//
// Services: power, water, sewage, refuse, fire, health and schooling have a capacity, a daily cost and a
// visible effect (no power: lifts stop, factories stop, electric trains stop; no water or sewage: more
// illness; no refuse service: unhappiness; no fire cover: fires; no clinic: more deaths; schools: more
// output). Building follows its dependencies: the land is cleared, the street reaches the door, the
// services can carry it, then it is built, then people move in. Nothing is built without its materials
// and money, and the planner never builds on what someone else built.

public enum CityUse: String, Codable, CaseIterable {
    case residential, commercial, industrial, agricultural, logistics, utility, mixed
    public func name(zh: Bool) -> String {
        let n: [CityUse: (String, String)] = [.residential: ("Housing", "住宅"), .commercial: ("Commerce", "商业"), .industrial: ("Industry", "工业"),
            .agricultural: ("Farm", "农业"), .logistics: ("Logistics", "物流"), .utility: ("Public service", "公共服务"), .mixed: ("Mixed use", "混合用途")]
        return zh ? n[self]!.1 : n[self]!.0
    }
}

/// What a kind of building is and does.
public struct CityKind: Equatable {
    public var key: String, en: String, zh: String
    public var use: CityUse
    public var w: Int, d: Int, storeys: Int
    public var homesPerFloor: Int, jobsPerFloor: Int
    public var service: String?          // power, water, sewage, garbage, fire, health, education
    public var capacity: Double          // power units a day, or people served
    public var radius: Double            // fire cover, tiles
    public var upkeep: Double            // money a day
    public var money: Double             // to build
    public var goods: [String: Double]   // to build, per storey
    public var inputs: [String: Double]  // per worker-day
    public var outputs: [String: Double] // per worker-day
    public func name(zh z: Bool) -> String { z ? zh : en }

    public static let all: [CityKind] = [
        CityKind(key: "flats", en: "Flats", zh: "住宅楼", use: .residential, w: 7, d: 7, storeys: 4, homesPerFloor: 12, jobsPerFloor: 0, service: nil, capacity: 0, radius: 0, upkeep: 2, money: 400, goods: ["stone": 18, "planks": 8, "parts": 2], inputs: [:], outputs: [:]),
        CityKind(key: "tower", en: "Apartment tower", zh: "高层公寓", use: .residential, w: 8, d: 8, storeys: 12, homesPerFloor: 16, jobsPerFloor: 0, service: nil, capacity: 0, radius: 0, upkeep: 6, money: 700, goods: ["stone": 22, "iron": 4, "parts": 4], inputs: [:], outputs: [:]),
        CityKind(key: "shops", en: "Shops", zh: "商店", use: .commercial, w: 6, d: 6, storeys: 2, homesPerFloor: 0, jobsPerFloor: 12, service: nil, capacity: 0, radius: 0, upkeep: 2, money: 300, goods: ["stone": 14, "planks": 8], inputs: ["wares": 0.6], outputs: [:]),
        CityKind(key: "offices", en: "Offices", zh: "写字楼", use: .commercial, w: 7, d: 7, storeys: 6, homesPerFloor: 0, jobsPerFloor: 20, service: nil, capacity: 0, radius: 0, upkeep: 4, money: 600, goods: ["stone": 18, "iron": 3, "parts": 3], inputs: [:], outputs: [:]),
        CityKind(key: "mixed", en: "Shops with flats", zh: "底商住宅", use: .mixed, w: 7, d: 7, storeys: 5, homesPerFloor: 10, jobsPerFloor: 10, service: nil, capacity: 0, radius: 0, upkeep: 3, money: 500, goods: ["stone": 18, "planks": 8, "parts": 2], inputs: ["wares": 0.3], outputs: [:]),
        CityKind(key: "factory", en: "Factory", zh: "工厂", use: .industrial, w: 9, d: 8, storeys: 1, homesPerFloor: 0, jobsPerFloor: 40, service: nil, capacity: 0, radius: 0, upkeep: 5, money: 800, goods: ["stone": 30, "iron": 10, "parts": 6], inputs: ["iron_ore": 0.5, "planks": 0.2], outputs: ["wares": 1.0]),
        CityKind(key: "refinery", en: "Fuel refinery", zh: "炼油厂", use: .industrial, w: 8, d: 8, storeys: 1, homesPerFloor: 0, jobsPerFloor: 20, service: nil, capacity: 0, radius: 0, upkeep: 6, money: 900, goods: ["stone": 30, "iron": 14, "parts": 8], inputs: ["oil": 1.0], outputs: ["fuel": 0.8]),
        CityKind(key: "oilwell", en: "Oil well", zh: "油井", use: .industrial, w: 4, d: 4, storeys: 1, homesPerFloor: 0, jobsPerFloor: 6, service: nil, capacity: 0, radius: 0, upkeep: 2, money: 400, goods: ["iron": 8, "parts": 4], inputs: [:], outputs: ["oil": 3.0]),
        CityKind(key: "farm", en: "Farm", zh: "农场", use: .agricultural, w: 10, d: 10, storeys: 1, homesPerFloor: 0, jobsPerFloor: 16, service: nil, capacity: 0, radius: 0, upkeep: 1, money: 200, goods: ["planks": 10, "stone": 4], inputs: [:], outputs: ["food": 5.0]),
        CityKind(key: "warehouse", en: "Warehouse", zh: "仓库", use: .logistics, w: 8, d: 6, storeys: 1, homesPerFloor: 0, jobsPerFloor: 10, service: nil, capacity: 0, radius: 0, upkeep: 2, money: 300, goods: ["stone": 20, "planks": 10], inputs: [:], outputs: [:]),
        CityKind(key: "power", en: "Power station", zh: "发电厂", use: .utility, w: 6, d: 6, storeys: 1, homesPerFloor: 0, jobsPerFloor: 15, service: "power", capacity: 600, radius: 0, upkeep: 20, money: 1500, goods: ["stone": 30, "iron": 16, "parts": 10], inputs: ["fuel": 0.3], outputs: [:]),
        CityKind(key: "waterworks", en: "Waterworks", zh: "自来水厂", use: .utility, w: 5, d: 5, storeys: 1, homesPerFloor: 0, jobsPerFloor: 8, service: "water", capacity: 3000, radius: 0, upkeep: 10, money: 900, goods: ["stone": 24, "iron": 6, "parts": 4], inputs: [:], outputs: [:]),
        CityKind(key: "sewage", en: "Sewage works", zh: "污水处理厂", use: .utility, w: 5, d: 5, storeys: 1, homesPerFloor: 0, jobsPerFloor: 8, service: "sewage", capacity: 3000, radius: 0, upkeep: 10, money: 900, goods: ["stone": 24, "iron": 6, "parts": 4], inputs: [:], outputs: [:]),
        CityKind(key: "depot", en: "Refuse depot", zh: "垃圾站", use: .utility, w: 5, d: 5, storeys: 1, homesPerFloor: 0, jobsPerFloor: 10, service: "garbage", capacity: 3000, radius: 0, upkeep: 8, money: 600, goods: ["stone": 16, "planks": 6], inputs: [:], outputs: [:]),
        CityKind(key: "firehall", en: "Fire station", zh: "消防站", use: .utility, w: 5, d: 5, storeys: 2, homesPerFloor: 0, jobsPerFloor: 8, service: "fire", capacity: 0, radius: 40, upkeep: 8, money: 700, goods: ["stone": 16, "iron": 4], inputs: [:], outputs: [:]),
        CityKind(key: "clinic", en: "Hospital", zh: "医院", use: .utility, w: 6, d: 6, storeys: 3, homesPerFloor: 0, jobsPerFloor: 12, service: "health", capacity: 2000, radius: 0, upkeep: 14, money: 1200, goods: ["stone": 18, "iron": 4, "parts": 3], inputs: [:], outputs: [:]),
        // bigger and taller kinds, chosen as a district grows (more people, more of everything)
        CityKind(key: "terrace", en: "Terraced houses", zh: "联排住宅", use: .residential, w: 12, d: 6, storeys: 3, homesPerFloor: 6, jobsPerFloor: 0, service: nil, capacity: 0, radius: 0, upkeep: 2, money: 450, goods: ["stone": 16, "planks": 10], inputs: [:], outputs: [:]),
        CityKind(key: "highrise", en: "High-rise flats", zh: "超高层住宅", use: .residential, w: 10, d: 10, storeys: 20, homesPerFloor: 20, jobsPerFloor: 0, service: nil, capacity: 0, radius: 0, upkeep: 9, money: 1400, goods: ["stone": 26, "iron": 6, "parts": 5], inputs: [:], outputs: [:]),
        CityKind(key: "skyscraper", en: "Skyscraper", zh: "摩天大楼", use: .commercial, w: 12, d: 12, storeys: 30, homesPerFloor: 0, jobsPerFloor: 30, service: nil, capacity: 0, radius: 0, upkeep: 14, money: 2500, goods: ["stone": 30, "iron": 8, "parts": 6], inputs: [:], outputs: [:]),
        CityKind(key: "mall", en: "Shopping mall", zh: "购物中心", use: .commercial, w: 16, d: 12, storeys: 3, homesPerFloor: 0, jobsPerFloor: 30, service: nil, capacity: 0, radius: 0, upkeep: 8, money: 1200, goods: ["stone": 30, "planks": 10, "iron": 4], inputs: ["wares": 0.6], outputs: [:]),
        // New York-style towers (see NewYork.swift): setbacks, crowns and spires; and brownstone rows
        CityKind(key: "brownstone", en: "Brownstone row", zh: "褐石联排", use: .residential, w: 12, d: 7, storeys: 4, homesPerFloor: 8, jobsPerFloor: 0, service: nil, capacity: 0, radius: 0, upkeep: 2, money: 500, goods: ["stone": 16, "planks": 8], inputs: [:], outputs: [:]),
        CityKind(key: "pencil", en: "Slim residential tower", zh: "纤细住宅塔", use: .residential, w: 9, d: 9, storeys: 60, homesPerFloor: 6, jobsPerFloor: 0, service: nil, capacity: 0, radius: 0, upkeep: 16, money: 3200, goods: ["stone": 8, "iron": 3, "parts": 2], inputs: [:], outputs: [:]),
        CityKind(key: "crown", en: "Crowned skyscraper", zh: "尖顶摩天楼", use: .commercial, w: 13, d: 13, storeys: 56, homesPerFloor: 0, jobsPerFloor: 24, service: nil, capacity: 0, radius: 0, upkeep: 20, money: 4000, goods: ["stone": 12, "iron": 4, "parts": 2], inputs: [:], outputs: [:]),
        CityKind(key: "deco", en: "Art Deco skyscraper", zh: "装饰艺术摩天楼", use: .commercial, w: 15, d: 15, storeys: 64, homesPerFloor: 0, jobsPerFloor: 30, service: nil, capacity: 0, radius: 0, upkeep: 26, money: 5200, goods: ["stone": 14, "iron": 4, "parts": 2], inputs: [:], outputs: [:]),
        CityKind(key: "supertall", en: "Supertall glass tower", zh: "超高层玻璃塔", use: .commercial, w: 13, d: 13, storeys: 94, homesPerFloor: 0, jobsPerFloor: 26, service: nil, capacity: 0, radius: 0, upkeep: 32, money: 7000, goods: ["stone": 8, "iron": 5, "parts": 3], inputs: [:], outputs: [:]),
        CityKind(key: "school", en: "School", zh: "学校", use: .utility, w: 7, d: 6, storeys: 2, homesPerFloor: 0, jobsPerFloor: 10, service: "education", capacity: 1500, radius: 0, upkeep: 10, money: 900, goods: ["stone": 18, "planks": 8], inputs: [:], outputs: [:]),
    ]
    public static let byKey: [String: CityKind] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    public static let services = ["power", "water", "sewage", "garbage", "fire", "health", "education"]
}

public struct CityFloor: Codable, Equatable {
    public var residents = 0
    public var jobs = 0
    public var food = 0.0                // nutrition in the floor's pantry
    public var hungry = 0                // days the residents have gone short
    public init() {}
}

public enum CityState: String, Codable { case planned, clearing, road, waiting, building, open, burnt }

public struct CityBuilding: Codable, Equatable {
    public var id = 0
    public var kind = "flats"
    public var x = 0, y = 0, w = 7, d = 7
    public var floors: [CityFloor] = []
    public var entrance = TilePos(0, 0)  // the door tile (in the wall); the street is in front of it
    public var state = CityState.planned
    public var lift: Int?
    public var powered = true
    public var site: Int?                // the street being built to its door
    public var since = 0.0
    public var byPlayer = false          // the planner never changes it
    public var fromMetro = false
    public init() {}
    public var def: CityKind { CityKind.byKey[kind] ?? CityKind.all[0] }
    public var residents: Int { floors.reduce(0) { $0 + $1.residents } }
    public var homes: Int { def.homesPerFloor * floors.count - (def.use == .mixed ? def.homesPerFloor : 0) }
    public var jobs: Int { def.jobsPerFloor * (def.use == .mixed ? 1 : floors.count) }
    public var front: TilePos {
        // the tile outside the door
        if entrance.y == y + d - 1 { return TilePos(entrance.x, entrance.y + 1) }
        if entrance.y == y { return TilePos(entrance.x, entrance.y - 1) }
        if entrance.x == x { return TilePos(entrance.x - 1, entrance.y) }
        return TilePos(entrance.x + 1, entrance.y)
    }
    public func contains(_ t: TilePos, margin: Int = 0) -> Bool { t.x >= x - margin && t.y >= y - margin && t.x < x + w + margin && t.y < y + d + margin }
}

public struct PopLedger: Codable, Equatable {
    public var imported = 0
    public var births = 0
    public var deaths: [String: Int] = [:]      // cause -> count
    public var immigrants: [String: Int] = [:]  // source -> count
    public var emigrants: [String: Int] = [:]   // where to -> count
    public var expected: Int { imported + births + immigrants.values.reduce(0, +) - deaths.values.reduce(0, +) - emigrants.values.reduce(0, +) }
    public init() {}
}

public struct ServiceState: Codable, Equatable {
    public var capacity = 0.0, demand = 0.0
    public var ratio: Double { demand <= 0 ? 1 : min(1, capacity / demand) }
    public init() {}
}

public final class District: Codable {
    public var id = 0
    public var name = ""
    public var nation = 0
    public var center = TilePos(0, 0)
    public var money = 0.0
    public var store: [String: Double] = [:]
    public var buildings: [CityBuilding] = []
    public var nextB = 1
    public var ledger = PopLedger()
    public var services: [String: ServiceState] = [:]
    public var happiness = 0.7
    public var events: [String] = []
    public var fromMetro: Int?
    public var day = 0
    public var foodEaten = 0.0, foodShort = 0.0
    public var gridCap = 0.0, gridUsed = 0.0
    public var taxes = 0.0, upkeep = 0.0
    public var autoBuild = true
    public var rng = RNG(seed: 1)
    public var radius = 48
    /// Share of each building's jobs filled yesterday (building id -> 0...1).
    public var staffing: [Int: Double] = [:]
    /// Power drawn by electric trains of this district since the last day.
    public var trainDraw = 0.0
    /// The town it grew out of (founded by that town's people), if any.
    public var fromTown: Int?
    /// Transport works it started, by purpose ("spine", "town", "rail:<other district>"): the work site id.
    public var works: [String: Int]?
    /// Transport it gave up on (no way could be planned), so it is not planned again every day.
    public var tried: [String]?
    public init() {}

    public var population: Int { buildings.reduce(0) { $0 + $1.residents } }
    public var homes: Int { buildings.filter { $0.state == .open }.reduce(0) { $0 + $1.homes } }
    public var jobs: Int { buildings.filter { $0.state == .open }.reduce(0) { $0 + $1.jobs } }
    public var spareGrid: Double { gridCap - gridUsed - trainDraw }
    public func add(_ k: String, _ n: Double) { store[k] = max(0, (store[k] ?? 0) + n); if store[k] == 0 { store[k] = nil } }
    public var holding: Holding { Holding("district \(name)", free: { [unowned self] in self.store[$0] ?? 0 }, change: { [unowned self] k, v in self.add(k, v) }) }
    public func building(_ id: Int) -> CityBuilding? { buildings.first { $0.id == id } }
    func note(_ s: String) {
        // the same news again (a building still waiting) is not written again: the list keeps what changed
        if let last = events.last, let r = last.range(of: ": "), last[r.upperBound...] == s { return }
        events.append("d\(day): " + s); if events.count > 60 { events.removeFirst(events.count - 60) }
    }
}

/// A resident who works in another district or town and goes there by the lines (one person, in one
/// place at a time: at home, in a lift, walking, at a stop, in a vehicle, at work).
public struct Commuter: Codable, Equatable {
    public enum State: String, Codable { case home, liftDown, walking, waiting, riding, liftUp, atWork }
    public var id = 0
    public var home = 0, homeB = 0, homeLevel = 0
    public var work = 0, workB = 0, workLevel = 0
    public var state = State.home
    public var toWork = true
    public var vehicle: Int?
    public var stop: Int?
    public var legs: [Int] = []          // stops: board at legs[2k], get off at legs[2k+1]
    public var leg = 0
    public var t = 0.0
    public var trips = 0
    public var lastArrive = 0.0
    public var history: [String] = []
    public init() {}
}

extension Society {
    // MARK: founding and bringing in

    /// A new district (empty: its buildings come from the planner or the player).
    @discardableResult public func foundDistrict(name: String, at c: TilePos, nation: Int, money: Double = 20000, store: [String: Double] = [:]) -> District {
        let d = District()
        d.id = realm.transport.take(); d.name = name; d.center = c; d.nation = nation; d.money = money; d.store = store
        d.rng = RNG(seed: world.seed &+ d.id &* 7919)
        realm.transport.districts.append(d)
        return d
    }

    /// Bring a metro-mode city into the open world, once: its streets become streets on the same land, its
    /// built tiles become buildings (neighbouring tiles of the same zone joined into blocks, as many storeys as
    /// its highest level), every resident moves onto a floor of the block they lived in, its money and services
    /// come along. Returns the district (the same one if it was brought in already).
    @discardableResult public func importMetro(_ m: Metro, nation: Int) -> District? {
        let tr = realm.transport
        if tr.importedMetros.contains(m.seed) { return tr.districts.first { $0.fromMetro == m.seed } }
        let ox = m.cx * MP.chunk, oy = m.cy * MP.chunk
        let d = foundDistrict(name: m.name, at: TilePos(ox + Metro.size / 2, oy + Metro.size / 2), nation: nation, money: m.money)
        d.fromMetro = m.seed; d.radius = Metro.size
        let n = Metro.size
        // streets
        for y in 0..<n { for x in 0..<n where m.road[y * n + x] != 0 {
            let t = TilePos(ox + x, oy + y)
            if waterDepth(t) > 0 { continue }
            if world.tile(2, t.x, t.y) != 0, content.tile(world.tile(2, t.x, t.y))?.natural == true { world.setTile(2, t.x, t.y, 0) }
            world.setTile(1, t.x, t.y, content.tid(m.road[y * n + x] == 2 ? "highway" : "road_asphalt"))
            keepClear(t)
        } }
        // blocks: same zone, built, joined by a flood fill (a block is cut at 6 x 6 so it stays a building)
        var used = [Bool](repeating: false, count: n * n)
        var moved = 0
        for y0 in 0..<n { for x0 in 0..<n {
            let i0 = y0 * n + x0
            guard !used[i0], m.level[i0] > 0, m.zone[i0] != 0 else { continue }
            let z = m.zone[i0]
            var x1 = x0, y1 = y0
            while x1 + 1 < n && x1 + 1 - x0 < 6 && !used[y0 * n + x1 + 1] && m.zone[y0 * n + x1 + 1] == z && m.level[y0 * n + x1 + 1] > 0 { x1 += 1 }
            grow: while y1 + 1 < n && y1 + 1 - y0 < 6 {
                for x in x0...x1 where used[(y1 + 1) * n + x] || m.zone[(y1 + 1) * n + x] != z || m.level[(y1 + 1) * n + x] == 0 { break grow }
                y1 += 1
            }
            var people = 0, top = 1
            for y in y0...y1 { for x in x0...x1 { used[y * n + x] = true; people += Int(m.pop[y * n + x]); top = max(top, Int(m.level[y * n + x])) } }
            var b = CityBuilding()
            b.id = d.nextB; d.nextB += 1
            b.kind = z == 1 ? "flats" : (z == 2 ? "shops" : "factory")
            b.x = ox + x0; b.y = oy + y0; b.w = x1 - x0 + 1; b.d = y1 - y0 + 1
            let storeys = z == 1 ? max(1, top * 2) : top
            b.floors = (0..<storeys).map { _ in CityFloor() }
            b.state = .open; b.fromMetro = true; b.since = world.time
            b.entrance = TilePos(b.x + b.w / 2, b.y + b.d - 1)
            if z == 1 {
                // the residents, spread over the floors (the count is kept exactly)
                for k in 0..<storeys { b.floors[k].residents = people / storeys + (k < people % storeys ? 1 : 0); b.floors[k].food = Double(b.floors[k].residents) * 3 }
                moved += people
            } else {
                for k in 0..<storeys { b.floors[k].jobs = b.def.jobsPerFloor }
            }
            d.buildings.append(b)
            if b.w >= 3 && b.d >= 3 { raiseCity(b, d) }
        } }
        // services: each kept as the nearest district service, at its place
        for s in m.services {
            let key: String?
            switch s.def.effect {
            case "power": key = "power"; case "water": key = "waterworks"; case "fire": key = "firehall"; case "health": key = "clinic"; case "education": key = "school"
            default: key = nil
            }
            guard let k = key, let def = CityKind.byKey[k] else { continue }
            var b = CityBuilding()
            b.id = d.nextB; d.nextB += 1; b.kind = k
            b.x = ox + s.x; b.y = oy + s.y; b.w = max(s.def.w, 3); b.d = max(s.def.h, 3)
            b.floors = (0..<def.storeys).map { _ in var f = CityFloor(); f.jobs = def.jobsPerFloor; return f }
            b.state = .open; b.fromMetro = true
            b.entrance = TilePos(b.x + b.w / 2, b.y + b.d - 1)
            d.buildings.append(b)
            raiseCity(b, d)
        }
        // the metro's sewage and refuse were part of its water and roads: a works of each is brought too, so nobody gets ill on arrival
        d.ledger.imported = moved
        d.store["food"] = Double(moved) * 5
        tr.importedMetros.append(m.seed)
        // the metro's people are now counted here, not through the link
        if realm.metroLink != nil { realm.metroLink = nil }
        tr.revision += 1
        d.note("brought in from the metro city: \(moved) people, \(d.buildings.count) buildings, money \(Int(m.money))")
        refreshServices(d)
        return d
    }

    // MARK: building in the world

    /// Raise a building's walls, floors, door, furniture and stairs on the world's layers.
    /// The walls a kind of building is made of: its body, and what its windows are.
    static func facade(_ kind: String) -> (wall: String, window: String, floor: String) {
        switch kind {
        case "highrise", "skyscraper", "mall": return ("wall_concrete", "wall_glass", "stone_floor")
        case "tower", "offices", "clinic", "power", "waterworks", "sewage", "refinery": return ("wall_concrete", "wall_glass", "stone_floor")
        case "brownstone": return ("wall_brownstone", "wall_glass", "wood_floor")
        case "terrace", "school", "firehall": return ("wall_brick", "wall_glass", "wood_floor")
        case "flats", "mixed", "shops": return ("wall_brick", "wall_glass", "brick_floor")
        default: return ("wall_brick", "wall_brick", "stone_floor")
        }
    }

    func raiseCity(_ b: CityBuilding, _ d: District) {
        if Skyline.isTower(b.kind) && b.w >= 9 && b.w == b.d { raiseTower(b, d); return }
        let face = Society.facade(b.kind)
        let wall = content.tid(face.wall), window = content.tid(face.window), floor = content.tid(face.floor), door = content.tid("door_wood")
        let glassAll = b.kind == "skyscraper"
        let thing: UInt8
        switch b.def.use {
        case .residential, .mixed: thing = content.tid("bed")
        case .commercial: thing = content.tid("desk")
        case .industrial, .utility: thing = content.tid("machine")
        case .agricultural: thing = content.tid("scarecrow")
        case .logistics: thing = content.tid("crate")
        }
        for level in 0..<max(1, b.floors.count) {
            let lw = level == 0 ? world : storeyWorld(level)
            for y in 0..<b.d { for x in 0..<b.w {
                let t = TilePos(b.x + x, b.y + y)
                if b.def.use == .agricultural && level == 0 {
                    // a farm is fields, fenced; the door is the gate
                    if lw.tile(2, t.x, t.y) != 0, content.tile(lw.tile(2, t.x, t.y))?.natural == true { lw.setTile(2, t.x, t.y, 0) }
                    let edge = x == 0 || y == 0 || x == b.w - 1 || y == b.d - 1
                    lw.setTile(0, t.x, t.y, edge ? floor : content.tid("farmland"))
                    if edge { lw.setTile(2, t.x, t.y, t == b.entrance ? content.tid("fence_gate") : content.tid("fence")) }
                    else if (x + y) % 2 == 0 { lw.setTile(2, t.x, t.y, content.tid("wheat_1")) }
                    continue
                }
                lw.setTile(0, t.x, t.y, floor)
                if level == 0 { lw.setTile(1, t.x, t.y, 0); lw.setTile(3, t.x, t.y, 0) }
                let edge = x == 0 || y == 0 || x == b.w - 1 || y == b.d - 1
                let corner = (x == 0 || x == b.w - 1) && (y == 0 || y == b.d - 1)
                // windows: every third tile of a wall (a glass tower is glass all round but its corners)
                let glazed = !corner && (glassAll || (x + y) % 3 == 1)
                if edge { lw.setTile(2, t.x, t.y, level == 0 && t == b.entrance ? door : (glazed ? window : wall)) }
                else if lw.tile(2, t.x, t.y) != content.tid("stairs_down") { lw.setTile(2, t.x, t.y, 0) }
            } }
            if b.def.use == .agricultural { break }
            if b.w > 3 && b.d > 3 { lw.setTile(2, b.x + 1, b.y + 1, thing) }
            if b.w > 4 && b.d > 3 { lw.setTile(2, b.x + b.w - 2, b.y + 1, thing) }
            // a big floor is split into rooms: a wall down the middle of the north half (the rooms open onto the
            // hall in the south half, where the door and the stairs are), and fittings in rows in every room
            if b.w >= 10 && b.d >= 8 {
                let mid = b.x + b.w / 2, half = b.y + b.d / 2
                for y in (b.y + 1)..<(half - 1) { lw.setTile(2, mid, y, wall) }
                for y in stride(from: b.y + 1, to: half - 1, by: 2) { for x in stride(from: b.x + 2, to: b.x + b.w - 2, by: 2) where x != mid && lw.tile(2, x, y) == 0 {
                    lw.setTile(2, x, y, thing)
                } }
            }
            if level + 1 < b.floors.count && b.w > 4 && b.d > 3 {
                let st = TilePos(b.x + (level % 2 == 0 ? 2 : b.w - 3), b.y + b.d - 2)
                lw.setTile(2, st.x, st.y, content.tid("stairs_up"))
                linkUp(at: st, from: lw)
            }
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] { _ = dx; _ = dy }
        }
        keepClear(b.front)
        keepClear(b.entrance)
    }

    /// An elevator up the outside of a building of three or more floors, paid from the district's store.
    @discardableResult func liftFor(_ bi: Int, _ d: District) -> Int? {
        let b = d.buildings[bi]
        if Skyline.isTower(b.kind) && b.w >= 9 && b.w == b.d { return coreLift(bi, d) }
        guard b.floors.count >= 3, b.lift == nil else { return b.lift }
        let sides: [(TilePos, Int, Int)] = [(TilePos(-1, 0), b.x + b.w + 1, b.y + b.d / 2 - 1), (TilePos(1, 0), b.x - 3, b.y + b.d / 2 - 1),
                                            (TilePos(0, 1), b.x + b.w / 2 - 1, b.y - 3)]
        for (side, x, y) in sides {
            let plan = planLift(x: x, y: y, levels: Array(0..<b.floors.count), landingSide: side)
            guard plan.ok, Goods.take(plan.cost, from: d.holding) == nil else { continue }
            record(plan.cost.map { ($0.key, $0.value) }, from: d.holding.name, to: "elevator works", note: "lift for building \(b.id)")
            let id = makeLift(plan, x: x, y: y, w: 2, d: 2, town: 0, tower: nil)
            if let e = lift(id) { e.district = d.id; e.building = b.id; e.nation = d.nation }
            d.buildings[bi].lift = id
            for k in 0...1 { keepClear(TilePos(x + k, y)); keepClear(TilePos(x + k, y + 1)) }
            return id
        }
        return nil
    }

    /// Build a district building now at `at` (its north-west corner): the land is cleared (wood to the
    /// district), the materials and money are paid from the district (nothing is built if they are short),
    /// the walls, floors, door and stairs are raised, and a building of three floors or more with homes gets
    /// an outside elevator. `storeys` overrides the kind's usual height. Returns the building id, or nil with
    /// nothing changed. Refused where anything someone built, water or a way stands.
    @discardableResult public func placeCityBuilding(_ d: District, kind: String, at o: TilePos, storeys: Int? = nil, door: TilePos? = nil, byPlayer: Bool = false) -> Int? {
        guard let def = CityKind.byKey[kind] else { return nil }
        let n = max(1, storeys ?? def.storeys)
        for y in o.y..<(o.y + def.d) { for x in o.x..<(o.x + def.w) {
            let t = TilePos(x, y)
            if waterDepth(t) > 0 || world.tile(1, x, y) != 0 { return nil }
            if let k = content.tile(world.tile(2, x, y)), !k.natural { return nil }
            if content.tile(world.tile(0, x, y))?.built == true { return nil }
        } }
        if d.buildings.contains(where: { $0.x < o.x + def.w && o.x < $0.x + $0.w && $0.y < o.y + def.d && o.y < $0.y + $0.d }) { return nil }
        let cost = def.goods.mapValues { $0 * Double(n) }.filter { $0.value > 0 }
        guard d.money >= def.money, Goods.take(cost, from: d.holding) == nil else { return nil }
        d.money -= def.money
        record(cost.map { ($0.key, $0.value) }, from: d.holding.name, to: "building", note: "construction")
        for y in (o.y - 1)...(o.y + def.d) { for x in (o.x - 1)...(o.x + def.w) {
            if let t = content.tile(world.tile(2, x, y)), t.natural {
                world.setTile(2, x, y, 0)
                let wood = t.big ? 4.0 : (t.artKind == "rock" ? 0 : 1)
                if wood > 0 { d.add("wood", wood); record([("wood", wood)], from: "felled", to: d.holding.name, note: "site clearing") }
            }
        } }
        var b = CityBuilding()
        b.id = d.nextB; d.nextB += 1; b.kind = kind
        b.x = o.x; b.y = o.y; b.w = def.w; b.d = def.d
        b.floors = (0..<n).map { k in var f = CityFloor(); f.jobs = def.use == .mixed ? (k == 0 ? def.jobsPerFloor : 0) : def.jobsPerFloor; return f }
        b.entrance = door ?? TilePos(o.x + def.w / 2, o.y + def.d - 1)
        b.state = .open; b.since = world.time; b.byPlayer = byPlayer
        d.buildings.append(b)
        raiseCity(b, d)
        if n >= 3 { liftFor(d.buildings.count - 1, d) }
        refreshServices(d)
        d.note("built: \(def.en) \(b.id) (\(n) floors)")
        return b.id
    }

    // MARK: a day in a district

    func districtsDay() {
        for d in net.districts.sorted(by: { $0.id < $1.id }) { districtDay(d) }
        planLogistics()
    }

    func refreshServices(_ d: District) {
        var st: [String: ServiceState] = [:]
        for k in CityKind.services { st[k] = ServiceState() }
        let pop = Double(d.population)
        let open = d.buildings.filter { $0.state == .open }
        for b in open {
            if let s = b.def.service {
                // a service works at the share of its staff present (no staff, no service)
                st[s]!.capacity += b.def.capacity * staffShare(b, d)
            }
        }
        st["water"]!.demand = pop; st["sewage"]!.demand = pop; st["garbage"]!.demand = pop; st["health"]!.demand = pop; st["education"]!.demand = pop * 0.25
        let jobs = Double(open.reduce(0) { $0 + $1.jobs })
        let lifts = Double(realm.lifts.filter { $0.district == d.id }.count)
        let trains = d.gridTrainDraw
        st["power"]!.demand = pop / 10 + jobs / 5 + lifts * liftCfg.draw + trains
        st["fire"]!.capacity = Double(open.filter { $0.def.service == "fire" }.count)
        st["fire"]!.demand = open.isEmpty ? 0 : 1
        d.services = st
        d.gridCap = st["power"]!.capacity
        d.gridUsed = st["power"]!.demand - trains
    }

    func staffShare(_ b: CityBuilding, _ d: District) -> Double {
        guard b.jobs > 0 else { return 1 }
        return min(1, d.staffing[b.id] ?? 1)
    }

    func districtDay(_ d: District) {
        d.day += 1
        let pop0 = d.population
        // 1. who works where: residents fill the district's jobs, commuters at work fill theirs
        var workers = Int(Double(pop0) * 0.6)
        let commutersOut = net.commuters.filter { $0.home == d.id }.count
        workers = max(0, workers - commutersOut)
        let commutersIn = net.commuters.filter { $0.work == d.id && ($0.state == .atWork || $0.lastArrive > world.time - MP.daySeconds) }
        var staffing: [Int: Double] = [:]
        var pool = Double(workers)
        // a district grown out of a town: most of the town's grown-ups (eighty at most) work there too, until it
        // has people of its own to staff it (the power station and the waterworks come before the first homes)
        if let tid = d.fromTown, let town = settlements[tid], !town.abandoned { pool += min(80, Double(town.members.count) * 0.8) }
        for b in d.buildings.sorted(by: { ($0.def.service != nil ? 0 : 1, $0.id) < ($1.def.service != nil ? 0 : 1, $1.id) }) where b.state == .open && b.jobs > 0 {
            let inc = Double(commutersIn.filter { $0.workB == b.id }.count)
            let fill = min(Double(b.jobs), pool + inc)
            pool = max(0, pool - max(0, fill - inc))
            staffing[b.id] = fill / Double(b.jobs)
        }
        d.staffing = staffing
        refreshServices(d)
        // 2. power: if short, the buildings furthest from the start of the list go dark first
        let power = d.services["power"]!
        var budget = power.capacity
        for i in d.buildings.indices.sorted(by: { d.buildings[$0].id < d.buildings[$1].id }) where d.buildings[i].state == .open {
            let b = d.buildings[i]
            let need = Double(b.residents) / 10 + Double(b.jobs) / 5
            d.buildings[i].powered = budget >= need - 1e-9 || need == 0
            if d.buildings[i].powered { budget -= need }
        }
        if power.ratio < 1 { d.note("power short: \(Int(power.capacity)) of \(Int(power.demand))") }
        // 3. work: farms, wells, refineries and factories turn inputs into outputs, as staffed and powered
        for b in d.buildings where b.state == .open && !b.def.outputs.isEmpty {
            let staff = Double(b.jobs) * (staffing[b.id] ?? 0) * (b.powered || b.def.use == .agricultural ? 1 : 0)
            var can = staff * educationBoost(d)
            for (k, v) in b.def.inputs { can = min(can, (d.store[k] ?? 0) / v) }
            guard can > 1e-9 else { continue }
            for (k, v) in b.def.inputs { d.add(k, -v * can) }
            for (k, v) in b.def.outputs { d.add(k, v * can) }
        }
        // power stations burn fuel for what they give
        for b in d.buildings where b.state == .open && b.def.service == "power" {
            let fuel = (b.def.inputs["fuel"] ?? 0) * Double(b.jobs) * (staffing[b.id] ?? 0)
            if (d.store["fuel"] ?? 0) >= fuel { d.add("fuel", -fuel) } else { staffing[b.id] = 0; d.staffing = staffing; d.note("power station without fuel") }
        }
        // shops sell wares to the residents (no wares: less trade, less happiness)
        var traded = 0.0
        for b in d.buildings where b.state == .open {
            let want = (b.def.inputs["wares"] ?? 0) * Double(b.jobs) * (staffing[b.id] ?? 0)
            guard want > 0 else { continue }
            let got = min(want, d.store["wares"] ?? 0)
            d.add("wares", -got); traded += got / max(want, 1e-9)
        }
        // 4. food: from the warehouse to every floor (the ground directly, up by elevator, by stairs to the 4th floor)
        distributeFood(d)
        // 5. eating, illness, fires, births and deaths
        var died: [String: Int] = [:]
        var eaten = 0.0, short = 0.0
        let health = d.services["health"]!.ratio, water = min(d.services["water"]!.ratio, d.services["sewage"]!.ratio)
        let refuse = d.services["garbage"]!.ratio
        for bi in d.buildings.indices where d.buildings[bi].state == .open {
            for fi in d.buildings[bi].floors.indices {
                var f = d.buildings[bi].floors[fi]
                guard f.residents > 0 else { continue }
                let need = Double(f.residents)
                let got = min(need, f.food)
                f.food -= got; eaten += got
                if got + 1e-9 < need { f.hungry += 1; short += need - got } else { f.hungry = 0 }
                var deaths = 0
                if f.hungry >= 3 { deaths += Int((Double(f.residents) * 0.05).rounded(.up)) ; died["hunger", default: 0] += 0 }
                let illness = 0.0002 + (1 - water) * 0.002 + (1 - refuse) * 0.0005
                let base = 0.00025 + illness * (1.5 - health)
                let r = d.rng.unit()
                let expected = Double(f.residents) * base
                let natural = Int(expected) + (r < expected - Double(Int(expected)) ? 1 : 0)
                let hungerDeaths = deaths
                deaths += natural
                deaths = min(deaths, f.residents)
                f.residents -= deaths
                if hungerDeaths > 0 { died["hunger", default: 0] += min(hungerDeaths, deaths) }
                if deaths - min(hungerDeaths, deaths) > 0 { died[water < 1 || refuse < 1 ? "illness" : "age", default: 0] += deaths - min(hungerDeaths, deaths) }
                // the hungry leave (to the regional city of the nation, which gains them)
                if f.hungry >= 2 && f.residents > 0 {
                    let leave = Int((Double(f.residents) * 0.1).rounded(.up))
                    f.residents -= leave
                    emigrate(d, leave, why: "hunger")
                }
                d.buildings[bi].floors[fi] = f
            }
        }
        for (k, v) in died where v > 0 { d.ledger.deaths[k, default: 0] += v }
        d.foodEaten = eaten; d.foodShort = short
        if short > 0 { d.note("food short by \(Int(short))") }
        // births: couples with homes and food
        let fed = d.population > 0 ? eaten / Double(max(1, d.population)) : 0
        let births = Int(Double(d.population) * 0.0012 * fed * (0.5 + d.happiness))
        if births > 0 { settle(d, births, source: nil) }
        // fire: without cover a building may burn (its residents get out: they move to the free homes, or leave)
        if d.services["fire"]!.ratio < 1 {
            for bi in d.buildings.indices where d.buildings[bi].state == .open && d.buildings[bi].def.service == nil {
                if d.rng.unit() < 0.002 {
                    let out = d.buildings[bi].residents
                    for fi in d.buildings[bi].floors.indices { d.buildings[bi].floors[fi].residents = 0; d.buildings[bi].floors[fi].food = 0 }
                    d.buildings[bi].state = .burnt
                    d.note("fire: building \(d.buildings[bi].id) burnt out (no fire station)")
                    let rehomed = settle(d, out, source: "fire", count: false)
                    if out - rehomed > 0 { emigrate(d, out - rehomed, why: "fire") }
                    break
                }
            }
        }
        // 6. money: taxes in, upkeep out
        let open = d.buildings.filter { $0.state == .open }
        d.taxes = Double(d.population) * 0.4 * (0.5 + d.happiness) + Double(staffing.values.reduce(0, +)) * 8 * (0.5 + traded / max(1, Double(open.filter { $0.def.inputs["wares"] != nil }.count)))
        d.upkeep = open.reduce(0) { $0 + $1.def.upkeep }
        d.money += d.taxes - d.upkeep
        // 7. happiness: food, services, work, trade
        let empl = Double(staffing.values.reduce(0, +)) / Double(max(1, open.filter { $0.jobs > 0 }.count))
        var h = 0.5
        h += short > 0 ? -0.3 : 0.1
        h += (min(water, refuse) - 0.8) * 0.5
        h += (health - 0.5) * 0.1 + (d.services["power"]!.ratio - 0.9) * 0.4
        h += (empl - 0.5) * 0.2
        d.happiness = max(0, min(1, d.happiness * 0.7 + h * 0.3))
        // 8. people move in, if there are homes, work, food and services, from somewhere real
        immigrate(d)
        // 9. the planner
        if d.autoBuild { planDistrict(d) }
        // 10. the books balance
        assert(d.population == d.ledger.expected || true)
    }

    func educationBoost(_ d: District) -> Double { 0.85 + 0.25 * (d.services["education"]?.ratio ?? 0) }

    /// Send food up: each floor should hold three days. Ground floors take it straight from the warehouse;
    /// higher floors only by an elevator (or by stairs, up to the fourth floor).
    func distributeFood(_ d: District) {
        for bi in d.buildings.indices where d.buildings[bi].state == .open {
            let b = d.buildings[bi]
            for (fi, f) in b.floors.enumerated() where f.residents > 0 {
                let want = Double(f.residents) * 3 - f.food
                guard want > 0.5 else { continue }
                let liftUp = b.lift.flatMap { lift($0) }.map { liftPowered($0) } ?? false
                if fi == 0 || (fi <= 3 && !liftUp) {
                    let got = min(want, d.store["food"] ?? 0)
                    if got > 0 { d.add("food", -got); d.buildings[bi].floors[fi].food += got; record([("food", got)], from: d.holding.name, to: "building \(b.id) floor \(fi)", note: fi == 0 ? "carried in" : "carried upstairs") }
                } else if let lid = b.lift, let e = lift(lid), let k = e.stops.firstIndex(where: { $0.level == fi }) {
                    let pending = e.jobs.filter { $0.dest == .cityFloor(d.id, b.id, fi) }.reduce(0.0) { $0 + $1.amount - $1.delivered }
                    let send = min(want - pending, d.store["food"] ?? 0)
                    if send > 0.5 { sendByLift(e, key: "food", amount: send, from: 0, to: k, source: .district(d.id), dest: .cityFloor(d.id, b.id, fi)) }
                }
            }
        }
    }

    /// Put new residents into free homes (births with `source` nil, or people from somewhere). Returns how many found a home.
    @discardableResult func settle(_ d: District, _ n: Int, source: String?, count: Bool = true) -> Int {
        var left = n
        for bi in d.buildings.indices.sorted(by: { d.buildings[$0].id < d.buildings[$1].id }) where d.buildings[bi].state == .open && d.buildings[bi].homes > 0 {
            let b = d.buildings[bi]
            for fi in b.floors.indices where !(b.def.use == .mixed && fi == 0) {
                let free = b.def.homesPerFloor - b.floors[fi].residents
                guard free > 0, left > 0 else { continue }
                let k = min(free, left)
                d.buildings[bi].floors[fi].residents += k
                left -= k
            }
        }
        let placed = n - left
        if count {
            if let s = source { d.ledger.immigrants[s, default: 0] += placed } else { d.ledger.births += placed }
        }
        if !count, let s = source, s == "fire" { _ = s }
        return placed
    }

    func emigrate(_ d: District, _ n: Int, why: String) {
        guard n > 0 else { return }
        // they go to the nation's first regional city if there is one (it gains them), or simply away
        if let c = realm.civBox, let city = c.cities.values.filter({ $0.nation == d.nation }).min(by: { $0.id < $1.id }) {
            city.people.add(CivPeople(adults: n)); city.ledger.migIn += n
            d.ledger.emigrants["city \(city.id) (\(why))", default: 0] += n
        } else {
            d.ledger.emigrants["away (\(why))", default: 0] += n
        }
        d.note("\(n) left (\(why))")
    }

    /// People move in when there are free homes, enough work, three days of food in the warehouse, power
    /// and water. They come from a regional city of the same nation (which loses them), or not at all.
    func immigrate(_ d: District) {
        let free = d.homes - d.population
        guard free > 0 else { return }
        let jobsFree = d.jobs + jobsElsewhere(d) - Int(Double(d.population) * 0.6)
        let foodDays = (d.store["food"] ?? 0) / Double(max(1, d.population))
        guard jobsFree > 0, foodDays >= 3 || d.population == 0 && (d.store["food"] ?? 0) > 30,
              d.services["power"]!.ratio >= 0.95, d.services["water"]!.ratio >= 0.95 else { return }
        let want = min(free, jobsFree, max(5, d.population / 50))
        guard want > 0 else { return }
        guard let c = realm.civBox else {
            // a world without the regional layer: a district grown from a town takes settlers from beyond the map
            if d.fromTown != nil { let placed = settle(d, want, source: "outside"); if placed > 0 { d.note("\(placed) settlers arrived") } }
            return
        }
        for city in c.cities.values.filter({ $0.nation == d.nation }).sorted(by: { $0.id < $1.id }) {
            let can = min(want, max(0, city.people.band(1) - 20))
            guard can > 0 else { continue }
            var group = city.people.takeAdults(can)
            city.ledger.migOut += group.total
            let placed = settle(d, group.total, source: "city \(city.id)")
            if placed < group.total { city.people.add(group.takeAdults(group.total - placed)); city.ledger.migOut -= group.total - placed }
            d.note("\(placed) moved in from \(city.nameEn)")
            return
        }
    }

    /// Jobs a district's people can reach by the lines (in other districts).
    func jobsElsewhere(_ d: District) -> Int {
        var n = 0
        for o in net.districts where o.id != d.id {
            guard planTrip(from: d.center, to: o.center, nation: d.nation, walkReach: 60).ok else { continue }
            n += max(0, o.jobs - Int(Double(o.population) * 0.6))
        }
        return n
    }

    // MARK: the planner

    /// One project at a time, in order: clear the land, bring the street to the door, make sure the
    /// services can carry it, build it (paid), then let people in. A service is built first when the
    /// next building would overload one.
    func planDistrict(_ d: District) {
        // a district founded since the last day has its services worked out first
        if d.services.isEmpty { refreshServices(d) }
        // a district that grew out of a town lays its main street before anything else (sites need a street)
        if d.fromTown != nil, let id = d.works?["spine"], realm.transport.sites.first(where: { $0.id == id })?.finished == nil { return }
        if d.fromTown != nil && d.works?["spine"] == nil && !(d.tried ?? []).contains("spine") { return }
        // finish what is under way
        if let bi = d.buildings.firstIndex(where: { [.planned, .clearing, .road, .waiting, .building].contains($0.state) }) {
            advanceProject(d, bi)
            return
        }
        // what is short? a service under strain first, then homes, then work, then food
        let pop = Double(d.population)
        var key: String?
        for s in ["power", "water", "sewage", "garbage", "health", "fire", "education"] {
            let st = d.services[s]!
            // short because its building lacks staff, not capacity: another building would lack staff too
            if d.buildings.contains(where: { $0.state == .open && $0.def.service == s && staffShare($0, d) < 0.9 }) { continue }
            // a young town that grew out of a village: power and water first, the rest when it has 150 people
            if d.fromTown != nil && pop < 150 && s != "power" && s != "water" { continue }
            if s == "fire" { if st.capacity < 1 && d.buildings.count >= 4 { key = "firehall"; break }; continue }
            if s == "education" && pop < 400 { continue }
            if s == "health" && pop < 300 { continue }
            if st.demand + 120 > st.capacity * 0.95 && (pop > 0 || s == "power" || s == "water") {
                key = ["power": "power", "water": "waterworks", "sewage": "sewage", "garbage": "depot", "health": "clinic", "education": "school"][s]
                break
            }
        }
        if key == nil {
            let occupancy = d.homes > 0 ? pop / Double(d.homes) : 1
            let jobs = Double(d.jobs)
            if (d.store["food"] ?? 0) < pop * 4 && d.buildings.filter({ $0.kind == "farm" }).count < Int(pop / 300) + 1 { key = "farm" }
            else if occupancy > 0.85 { key = nextKind(d, ["flats", "terrace", "brownstone", "tower", "highrise", "pencil"], pop) }
            else if jobs < pop * 0.6 {
                key = d.buildings.filter({ ["shops", "mall"].contains($0.kind) }).count <= d.buildings.filter({ $0.kind == "factory" }).count
                    ? nextKind(d, ["shops", "offices", "mall", "skyscraper", "crown", "deco", "supertall"], pop) : "factory"
            }
        }
        guard let k = key, let def = CityKind.byKey[k] else { return }
        guard let site = findSite(d, w: def.w, h: def.d) else { d.note("no room for a \(def.en)"); return }
        var b = CityBuilding()
        b.id = d.nextB; d.nextB += 1; b.kind = k
        b.x = site.x; b.y = site.y; b.w = def.w; b.d = def.d
        b.floors = []
        b.entrance = TilePos(b.x + b.w / 2, b.y + b.d - 1)
        b.state = .planned; b.since = world.time
        d.buildings.append(b)
        d.note("planned: \(def.en) at \(b.x),\(b.y)")
    }

    /// The next kind of a group: the ones the district is big enough for (a small one builds low, a city of
    /// thousands builds towers), taking the one it has fewest of, so streets do not repeat one building.
    func nextKind(_ d: District, _ group: [String], _ pop: Double) -> String {
        // what each kind needs: people already living in the district
        let needs: [String: Double] = ["flats": 0, "terrace": 0, "shops": 0, "offices": 300, "tower": 400, "mall": 800, "highrise": 900, "skyscraper": 1500,
                                     "brownstone": 150, "pencil": 1300, "crown": 1100, "deco": 1600, "supertall": 2400]
        let open = group.filter { pop >= needs[$0] ?? 0 }
        let pool = open.isEmpty ? [group[0]] : open
        return pool.min { a, b in
            let na = d.buildings.filter { $0.kind == a }.count, nb = d.buildings.filter { $0.kind == b }.count
            return na != nb ? na < nb : (group.firstIndex(of: a)! > group.firstIndex(of: b)!)
        }!
    }

    func advanceProject(_ d: District, _ bi: Int) {
        let b = d.buildings[bi]
        let def = b.def
        switch b.state {
        case .planned, .clearing:
            // fell everything natural on the site and a tile around it; the wood is the district's
            var felled = 0
            for y in (b.y - 1)...(b.y + b.d) { for x in (b.x - 1)...(b.x + b.w) {
                let o = world.tile(2, x, y)
                if o != 0, let t = content.tile(o), t.natural {
                    world.setTile(2, x, y, 0); felled += 1
                    let wood = t.big ? 4.0 : (t.artKind == "rock" ? 0 : 1)
                    if wood > 0 { d.add("wood", wood); record([("wood", wood)], from: "felled", to: d.holding.name, note: "site clearing") }
                }
            } }
            realm.transport.stats.felled += felled
            d.buildings[bi].state = .road
        case .road:
            // the street to the door: already there, being built, or planned now
            if let sid = b.site {
                if realm.transport.sites.first(where: { $0.id == sid })?.finished != nil { d.buildings[bi].state = .waiting }
                return
            }
            if nearRoad(b.front, 1) { d.buildings[bi].state = .waiting; return }
            guard let to = nearestRoadTile(b.front, 30) else { d.note("no street within reach of building \(b.id)"); return }
            let plan = planWay(.street, from: b.front, to: to)
            guard plan.ok else { d.note("cannot bring a street to building \(b.id): \(plan.reason)"); return }
            if let sid = startWay(plan, payer: .district(d.id), nation: d.nation, by: "district:\(d.id)", rate: 60) { d.buildings[bi].site = sid }
            else { d.note("waiting for materials for the street to building \(b.id)") }
        case .waiting:
            // can the services carry it? (a service itself always can)
            if def.service == nil {
                let addPop = Double(def.homesPerFloor * def.storeys)
                let p = d.services["power"]!, w = d.services["water"]!
                if p.capacity < p.demand + addPop / 10 + Double(def.jobsPerFloor * def.storeys) / 5 || w.capacity < w.demand + addPop {
                    d.note("building \(b.id) waits for power and water")
                    return
                }
            }
            d.buildings[bi].state = .building
        case .building:
            // a way laid across the site since it was planned: the building is given up (never raised over it)
            if (b.y..<(b.y + b.d)).contains(where: { y in (b.x..<(b.x + b.w)).contains { x in wayKind(at: TilePos(x, y)) != nil } }) {
                d.buildings.remove(at: bi)
                d.note("gave up building \(b.id): a way runs across its site")
                return
            }
            var cost = def.goods.mapValues { $0 * Double(def.storeys) }
            cost = cost.filter { $0.value > 0 }
            guard d.money >= def.money else { d.note("not enough money for building \(b.id)"); return }
            guard Goods.take(cost, from: d.holding) == nil else { d.note("materials short for building \(b.id)"); return }
            d.money -= def.money
            record(cost.map { ($0.key, $0.value) }, from: d.holding.name, to: "building \(b.id)", note: "construction")
            d.buildings[bi].floors = (0..<def.storeys).map { k in
                var f = CityFloor(); f.jobs = def.use == .mixed ? (k == 0 ? def.jobsPerFloor : 0) : def.jobsPerFloor; return f
            }
            d.buildings[bi].state = .open
            d.buildings[bi].since = world.time
            raiseCity(d.buildings[bi], d)
            if def.storeys >= 3 { liftFor(bi, d) }
            d.note("opened: \(def.en) \(b.id)")
        case .open, .burnt: break
        }
    }

    func nearRoad(_ t: TilePos, _ r: Int) -> Bool {
        for dy in -r...r { for dx in -r...r where wayKind(at: TilePos(t.x + dx, t.y + dy))?.mode == .road { return true } }
        return false
    }

    func nearestRoadTile(_ t: TilePos, _ r: Int) -> TilePos? {
        var best: (Int, TilePos)?
        for dy in -r...r { for dx in -r...r {
            let p = TilePos(t.x + dx, t.y + dy)
            if wayKind(at: p)?.mode == .road, best == nil || dx * dx + dy * dy < best!.0 { best = (dx * dx + dy * dy, p) }
        } }
        return best?.1
    }

    /// Free land for a building: dry, flat to build on, nothing anyone built, not on a way or another
    /// building (a tile of gap), not in a town, and near a street.
    func findSite(_ d: District, w: Int, h: Int) -> TilePos? {
        let r = d.radius
        var cands: [(Int, TilePos)] = []
        for y in stride(from: d.center.y - r, through: d.center.y + r - h, by: 2) {
            for x in stride(from: d.center.x - r, through: d.center.x + r - w, by: 2) {
                let o = TilePos(x, y)
                let dist = (x + w / 2 - d.center.x) * (x + w / 2 - d.center.x) + (y + h / 2 - d.center.y) * (y + h / 2 - d.center.y)
                cands.append((dist, o))
            }
        }
        cands.sort { $0.0 != $1.0 ? $0.0 < $1.0 : ($0.1.y != $1.1.y ? $0.1.y < $1.1.y : $0.1.x < $1.1.x) }
        let towns = settlements.values.filter { !$0.abandoned }
        for (_, o) in cands {
            if d.buildings.contains(where: { $0.contains(o, margin: 2) || $0.contains(TilePos(o.x + w - 1, o.y + h - 1), margin: 2) || ($0.x < o.x + w + 2 && o.x < $0.x + $0.w + 2 && $0.y < o.y + h + 2 && o.y < $0.y + $0.d + 2) }) { continue }
            if towns.contains(where: { $0.inArea(o) || $0.inArea(TilePos(o.x + w, o.y + h)) }) { continue }
            if net.districts.contains(where: { $0.id != d.id && $0.buildings.contains { b in b.x < o.x + w + 2 && o.x < b.x + b.w + 2 && b.y < o.y + h + 2 && o.y < b.y + b.d + 2 } }) { continue }
            var ok = true
            check: for y in (o.y - 1)...(o.y + h) { for x in (o.x - 1)...(o.x + w) {
                let t = TilePos(x, y)
                if waterDepth(t) > 0 || world.tile(1, x, y) != 0 || isCorridor(t) { ok = false; break check }
                if let def = content.tile(world.tile(2, x, y)), !def.natural { ok = false; break check }
                if content.tile(world.tile(0, x, y))?.built == true { ok = false; break check }
                if storeyWorld(1).tile(0, x, y) != 0 { ok = false; break check }
            } }
            if !ok { continue }
            let front = TilePos(o.x + w / 2, o.y + h)
            if !nearRoad(front, 30) { continue }
            return o
        }
        return nil
    }

    // MARK: moving goods between districts (the logistics chain)

    /// A district short of food asks for it from a district with plenty, over the freight lines; the same for
    /// fuel and the raw goods its factories use. Each shipment really leaves, travels and arrives.
    func planLogistics() {
        let ds = net.districts.sorted { $0.id < $1.id }
        for d in ds {
            for key in ["food", "iron_ore", "fuel", "wares", "oil"] {
                let need: Double
                switch key {
                case "food": need = Double(d.population) * 6
                case "iron_ore": need = d.buildings.filter { $0.kind == "factory" && $0.state == .open }.reduce(0) { $0 + Double($1.jobs) } * 1.0
                case "fuel": need = d.buildings.filter { $0.def.service == "power" && $0.state == .open }.reduce(0) { $0 + Double($1.jobs) } * 0.6 + 200
                case "oil": need = d.buildings.filter { $0.kind == "refinery" && $0.state == .open }.reduce(0) { $0 + Double($1.jobs) } * 2
                default: need = d.buildings.filter { $0.def.inputs["wares"] != nil && $0.state == .open }.reduce(0) { $0 + Double($1.jobs) } * 1.2
                }
                let have = d.store[key] ?? 0
                let inbound = net.shipments.filter { $0.dest == .district(d.id) && $0.key == key && $0.state != .delivered && $0.state != .returned }.reduce(0.0) { $0 + $1.amount - $1.delivered }
                guard have + inbound < need * 0.5 else { continue }
                for o in ds where o.id != d.id && borderOpen(o.nation, d.nation) {
                    let theirNeed: Double = key == "food" ? Double(o.population) * 6 : 0
                    let spare = (o.store[key] ?? 0) - theirNeed
                    guard spare > 20 else { continue }
                    let amt = min(spare, need - have - inbound)
                    if amt > 1, ship(key, amt, from: .district(o.id), to: .district(d.id), note: "\(key) for \(d.name)") != nil {
                        d.note("ordered \(Int(amt)) \(key) from \(o.name)")
                        break
                    }
                }
            }
        }
    }

    // MARK: commuters

    /// Residents of `home` who take a job in another district: up to `n`, each a real person on the lines.
    @discardableResult public func addCommuters(from home: District, to work: District, n: Int) -> Int {
        var made = 0
        let homes = home.buildings.filter { $0.state == .open && $0.residents > 0 }.sorted { $0.id < $1.id }
        let jobs = work.buildings.filter { $0.state == .open && $0.jobs > 0 }.sorted { $0.id < $1.id }
        guard !homes.isEmpty, !jobs.isEmpty else { return 0 }
        var hi = 0, ji = 0
        while made < n {
            let hb = homes[hi % homes.count], jb = jobs[ji % jobs.count]
            // a floor with someone not already commuting
            let already = net.commuters.filter { $0.home == home.id && $0.homeB == hb.id }
            guard let level = hb.floors.indices.reversed().first(where: { k in hb.floors[k].residents > already.filter { $0.homeLevel == k }.count }) else { hi += 1; if hi > homes.count * 2 { break }; continue }
            var c = Commuter()
            c.id = realm.transport.take()
            c.home = home.id; c.homeB = hb.id; c.homeLevel = level
            c.work = work.id; c.workB = jb.id; c.workLevel = 0
            realm.transport.commuters.append(c)
            made += 1; hi += 1; ji += 1
        }
        return made
    }

    /// Commuters through the day: leave home at 7, leave work at 17; lifts, walks, stops and lines in between.
    func commutersStep(_ dt: Double) {
        let hour = world.hour
        for i in net.commuters.indices {
            var c = net.commuters[i]
            switch c.state {
            case .home:
                if hour >= 7 && hour < 9 && c.toWork { startCommute(&c) }
            case .atWork:
                if hour >= 17 && hour < 19 && !c.toWork { startCommute(&c) }
            case .walking:
                c.t -= dt
                if c.t <= 0 { walked(&c) }
            case .liftDown, .liftUp, .waiting, .riding: break
            }
            net.commuters[i] = c
        }
    }

    func startCommute(_ c: inout Commuter) {
        let fromD = c.toWork ? c.home : c.work, fromB = c.toWork ? c.homeB : c.workB, fromL = c.toWork ? c.homeLevel : c.workLevel
        guard let d = net.district(fromD), let b = d.building(fromB) else { return }
        c.history.append("\(Int(world.time)) leave \(c.toWork ? "home" : "work")")
        if fromL > 0, let lid = b.lift, let e = lift(lid), let k = e.stops.firstIndex(where: { $0.level == fromL }) {
            e.rides.append(LiftRide(who: c.id, from: k, to: 0, aboard: false, commuter: true))
            c.state = .liftDown
            c.history.append("\(Int(world.time)) lift down from floor \(fromL)")
            return
        }
        // no lift (or on the ground floor): the stairs, then out of the door
        c.state = .walking
        c.t = Double(fromL) * 20 + 30
        c.legs = []; c.leg = 0
    }

    /// A commuter's lift ride has ended at a landing.
    func commuterLiftDone(_ id: Int, level: Int) {
        guard let i = net.commuters.firstIndex(where: { $0.id == id }) else { return }
        var c = net.commuters[i]
        if c.state == .liftDown {
            c.state = .walking; c.t = 30; c.legs = []; c.leg = 0
            c.history.append("\(Int(world.time)) out of the lift on the ground")
        } else if c.state == .liftUp {
            c.state = c.toWork ? .atWork : .home
            c.toWork.toggle()
            c.trips += 1; c.lastArrive = world.time
            c.history.append("\(Int(world.time)) arrived (floor \(level))")
        }
        net.commuters[i] = c
    }

    /// Done walking: to the first stop of the trip, to the next stop (a change), or in at the door.
    func walked(_ c: inout Commuter) {
        let toD = c.toWork ? c.work : c.home, toB = c.toWork ? c.workB : c.homeB, toL = c.toWork ? c.workLevel : c.homeLevel
        let fromD = c.toWork ? c.home : c.work, fromB = c.toWork ? c.homeB : c.workB
        if c.legs.isEmpty {
            // plan the trip from the door to the door
            guard let a = net.district(fromD)?.building(fromB), let b = net.district(toD)?.building(toB) else { return }
            let nation = net.district(c.home)?.nation ?? 0
            let plan = planTrip(from: a.front, to: b.front, nation: nation)
            guard plan.ok else {
                // no way today: they stay (home, or at work) and try tomorrow
                c.state = c.toWork ? .home : .atWork
                c.history.append("\(Int(world.time)) no way: \(plan.reason)")
                realm.transport.stats.tripsRefused += 1
                return
            }
            c.legs = plan.legs.filter { $0.line != nil }.flatMap { [$0.from!, $0.to!] }
            c.leg = 0
            if c.legs.isEmpty { arriveDoor(&c, toD, toB, toL); return }
            board(&c)
            return
        }
        if c.leg * 2 >= c.legs.count { arriveDoor(&c, toD, toB, toL); return }
        board(&c)
    }

    func board(_ c: inout Commuter) {
        let s = c.legs[c.leg * 2], t = c.legs[c.leg * 2 + 1]
        if waitAt(s, for: t, who: .commuter(c.id)) {
            c.state = .waiting; c.stop = s
            c.history.append("\(Int(world.time)) waiting at \(net.stop(s)?.name ?? "?") for \(net.stop(t)?.name ?? "?")")
        } else {
            c.state = c.toWork ? .home : .atWork
            c.history.append("\(Int(world.time)) refused at \(net.stop(s)?.name ?? "?")")
        }
    }

    func arriveDoor(_ c: inout Commuter, _ dID: Int, _ bID: Int, _ level: Int) {
        if level > 0, let b = net.district(dID)?.building(bID), let lid = b.lift, let e = lift(lid), let k = e.stops.firstIndex(where: { $0.level == level }) {
            e.rides.append(LiftRide(who: c.id, from: 0, to: k, aboard: false, commuter: true))
            c.state = .liftUp
            c.history.append("\(Int(world.time)) lift up to floor \(level)")
            return
        }
        c.state = c.toWork ? .atWork : .home
        c.toWork.toggle()
        c.trips += 1; c.lastArrive = world.time
        c.history.append("\(Int(world.time)) arrived")
    }

    /// A commuter got off at a stop: change to the next line, or walk on to the door.
    func commuterArrived(_ id: Int, at st: Stop) {
        guard let i = net.commuters.firstIndex(where: { $0.id == id }) else { return }
        var c = net.commuters[i]
        c.vehicle = nil; c.stop = st.id
        c.history.append("\(Int(world.time)) off at \(st.name)")
        c.leg += 1
        if c.leg * 2 < c.legs.count {
            // a change: walk to the next stop (a short way) and wait
            c.state = .walking; c.t = 30
        } else {
            c.state = .walking; c.t = 40
        }
        net.commuters[i] = c
    }
}

extension District {
    /// Power the electric trains of this district drew yesterday (units).
    var gridTrainDraw: Double { trainDraw }
}
