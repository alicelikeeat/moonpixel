import Foundation

// Command mode: a real-time skirmish on a piece of the same generated land. Two sides each start
// with a headquarters and a harvester; they mine moonstone, keep their power up, build structures,
// train soldiers and vehicles, and win by leaving the other side without a structure.
//
// It is a simulation of its own: it reads the terrain from the generator (never from the open
// world, so nothing there is touched or loaded) and keeps everything it adds in its own state. It is
// deterministic for a seed and has no graphics in it; the app draws it and sends the orders.
//
// Positions are in the same units as the rest of the game (16 per tile), relative to the arena's
// own corner; x east, y south.

/// What something is hit as; weapons do different damage to each.
public enum SkArmor: Int { case infantry = 0, vehicle = 1, structure = 2 }

/// One kind of structure or unit.
public struct SkKind {
    public let key: String, en: String, zh: String
    public let structure: Bool
    public let cost: Double, time: Double            // moonstone and seconds to make
    public let hp: Double
    public let armor: SkArmor
    public let speed: Double                         // units a second (0 for structures)
    public let range: Double, damage: Double, cooldown: Double
    public let vs: [Double]                          // damage multiplier against infantry, vehicles, structures
    public let w: Int, h: Int                        // footprint in tiles (structures)
    public let power: Double                         // made (+) or used (-)
    public let needs: [String]                       // structures a side must own first
    public let line: Int                             // which queue makes it: 0 structures, 1 infantry, 2 vehicles
    public func name(zh z: Bool) -> String { z ? zh : en }

    static func s(_ k: String, _ en: String, _ zh: String, _ cost: Double, _ time: Double, _ hp: Double, _ w: Int, _ h: Int, _ power: Double, _ needs: [String],
                  range: Double = 0, damage: Double = 0, cooldown: Double = 0, vs: [Double] = [1, 1, 1]) -> SkKind {
        SkKind(key: k, en: en, zh: zh, structure: true, cost: cost, time: time, hp: hp, armor: .structure, speed: 0, range: range, damage: damage, cooldown: cooldown, vs: vs, w: w, h: h, power: power, needs: needs, line: 0)
    }
    static func u(_ k: String, _ en: String, _ zh: String, _ cost: Double, _ time: Double, _ hp: Double, _ armor: SkArmor, _ speed: Double, _ range: Double, _ damage: Double, _ cooldown: Double,
                  _ vs: [Double], _ needs: [String], _ line: Int) -> SkKind {
        SkKind(key: k, en: en, zh: zh, structure: false, cost: cost, time: time, hp: hp, armor: armor, speed: speed, range: range, damage: damage, cooldown: cooldown, vs: vs, w: 1, h: 1, power: 0, needs: needs, line: line)
    }

    public static let all: [SkKind] = [
        s("hq", "Headquarters", "指挥部", 2500, 30, 1500, 3, 3, 0, ["hq"]),
        s("reactor", "Moon reactor", "月能炉", 300, 8, 400, 2, 2, 100, []),
        s("refinery", "Refinery", "精炼厂", 1400, 14, 800, 3, 2, -30, ["reactor"]),
        s("barracks", "Barracks", "兵营", 400, 9, 600, 2, 2, -20, ["reactor"]),
        s("works", "Engine works", "机械厂", 1600, 18, 900, 3, 3, -40, ["refinery"]),
        s("turret", "Watch turret", "哨戒炮", 500, 9, 500, 1, 1, -25, ["barracks"], range: 96, damage: 26, cooldown: 0.8, vs: [1, 0.8, 0.2]),
        u("rifle", "Rifleman", "步枪兵", 100, 4, 60, .infantry, 34, 72, 9, 0.6, [1, 0.35, 0.25], ["barracks"], 1),
        u("lancer", "Lancer", "破甲兵", 250, 6, 70, .infantry, 30, 88, 34, 1.8, [0.3, 1, 0.7], ["barracks"], 1),
        u("harvester", "Harvester", "采矿车", 900, 12, 500, .vehicle, 30, 0, 0, 0, [0, 0, 0], ["refinery"], 2),
        u("scout", "Scout tank", "轻坦克", 600, 9, 280, .vehicle, 52, 80, 22, 0.9, [0.7, 1, 0.6], ["works"], 2),
        u("bastion", "Bastion tank", "重坦克", 1100, 15, 620, .vehicle, 32, 88, 48, 1.4, [0.6, 1, 0.8], ["works"], 2),
        u("mortar", "Mortar carrier", "迫击炮车", 900, 13, 180, .vehicle, 34, 168, 60, 3.2, [0.8, 0.5, 1.6], ["works"], 2),
    ]
    public static let index: [String: Int] = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1.key, $0) })
    public static func named(_ k: String) -> Int { index[k] ?? 0 }
}

public struct SkEntity {
    public enum Order: Equatable { case idle, move(Vec2), attack(Int), attackMove(Vec2), harvest, deliver }
    public var id = 0, kind = 0, side = 0
    public var pos = Vec2.zero
    public var hp = 1.0
    public var order = Order.idle
    public var cooldown = 0.0
    public var facing = Vec2(0, 1)
    public var cargo = 0.0
    /// For a structure: the tile of its north-west corner.
    public var tile = TilePos(0, 0)
    public var moving = false
    /// Seconds since this fired (for drawing a muzzle flash) and since it was hurt.
    public var sinceShot = 9.0, sinceHurt = 9.0
    var targetID = 0
    public var def: SkKind { SkKind.all[kind] }
}

public struct SkSide {
    public var name = "", color = "#ffffff"
    public var credits = 0.0
    /// One thing being made on each line (0 structures, 1 infantry, 2 vehicles) and how far along it is (0...1).
    public var making: [Int?] = [nil, nil, nil]
    public var progress: [Double] = [0, 0, 0]
    /// What waits behind the one being made, per line.
    public var queued: [[Int]] = [[], [], []]
    /// A finished structure waiting to be put down.
    public var ready: Int?
    public var powerMade = 0.0, powerUsed = 0.0
    public var lowPower: Bool { powerUsed > powerMade }
    public var lost = 0, killed = 0, mined = 0.0
    public var computer = false
    var thinkT = 0.0, wave = 0, step = 0
}

/// Something that happened this step, for the app to draw or announce. Nothing depends on it.
public struct SkEvent {
    public var kind: String          // "shot", "died", "built", "placed", "trained", "lowpower", "attack"
    public var a: Vec2, b: Vec2
    public var side: Int, what: Int
}

public final class Skirmish {
    public static let size = 96                        // tiles a side: three chunks
    public let seed: Int
    /// Chunk of the generated world the arena's corner is at, and its terrain (what is drawn under it).
    public let cx: Int, cy: Int
    public private(set) var layers: [[[UInt8]]]        // nine chunks, row by row, four layers each (cleared ground is cleared here too)
    public private(set) var blocked: [Bool]            // terrain a unit cannot cross
    public private(set) var occupied: [Int]            // structure id on a tile, or 0
    public private(set) var ore: [Double]              // moonstone left on a tile
    public private(set) var entities: [Int: SkEntity] = [:]
    public var sides: [SkSide]
    public private(set) var time = 0.0
    public private(set) var winner: Int?
    public private(set) var events: [SkEvent] = []
    var rng: RNG
    var nextID = 1
    var fields: [Int: [UInt16]] = [:]                  // distance to a goal tile, by goal
    var fieldAge: [Int: Int] = [:]
    var mapVersion = 0
    var acc = 0.0
    var ids: [Int] = []

    static let n = Skirmish.size
    @inline(__always) static func idx(_ x: Int, _ y: Int) -> Int { y * n + x }
    @inline(__always) static func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < n && y < n }

    /// Find a piece of generated land far from where anyone lives, with room for two bases, and set them up.
    public init(seed: Int, worldSeed: Int, player: (name: String, color: String), enemy: (name: String, color: String), credits: Double = 3000) {
        self.seed = seed
        rng = RNG(seed: seed &* 31 &+ 7)
        let gen = Generator(seed: worldSeed)
        let n = Skirmish.n
        var best: (score: Int, cx: Int, cy: Int, layers: [[[UInt8]]], blocked: [Bool])?
        var probe = RNG(seed: seed &+ worldSeed &* 13)
        for _ in 0..<10 {
            // far from the origin, where the villages are
            let ccx = (300 + Int(probe.unit() * 600)) * (probe.unit() < 0.5 ? -1 : 1), ccy = (300 + Int(probe.unit() * 600)) * (probe.unit() < 0.5 ? -1 : 1)
            var ls: [[[UInt8]]] = []
            var bl = [Bool](repeating: false, count: n * n)
            let c = Content.shared
            for j in 0..<3 { for i in 0..<3 {
                let ch = gen.generate(ccx + i, ccy + j).layers
                ls.append(ch)
                for t in 0..<MP.chunkArea {
                    let o = Int(ch[2][t]), s = Int(ch[1][t])
                    var b = c.solid[Int(ch[0][t])]
                    if s != 0 { if c.solid[s] { b = true } else if c.bridge[s] { b = false } }
                    if o != 0 && c.solid[o] { b = true }
                    bl[Skirmish.idx(i * 32 + t % 32, j * 32 + t / 32)] = b
                }
            } }
            let free = bl.filter { !$0 }.count
            if best == nil || free > best!.score { best = (free, ccx, ccy, ls, bl) }
            if free > n * n * 3 / 4 { break }
        }
        cx = best!.cx; cy = best!.cy; layers = best!.layers; blocked = best!.blocked
        occupied = [Int](repeating: 0, count: n * n)
        ore = [Double](repeating: 0, count: n * n)
        var a = SkSide(); a.name = player.name; a.color = player.color; a.credits = credits
        var b = SkSide(); b.name = enemy.name; b.color = enemy.color; b.credits = credits; b.computer = true
        sides = [a, b]
        // bases in opposite corners; the ground under and around each is cleared so there is room to build
        let homes = [TilePos(16, n - 20), TilePos(n - 20, 16)]
        for (s, h) in homes.enumerated() {
            clear(around: h, radius: 9)
            let hq = place(SkKind.named("hq"), side: s, at: TilePos(h.x - 1, h.y - 1), free: true)
            _ = hq
            spawn(SkKind.named("harvester"), side: s, at: TilePos(h.x + 3, h.y + 1).center)
            for k in 0..<3 { spawn(SkKind.named("rifle"), side: s, at: TilePos(h.x - 2 + k, h.y + 3).center) }
        }
        // moonstone: a field by each base, one each on the two free corners, one in the middle
        for p in [TilePos(30, n - 14), TilePos(n - 34, 12), TilePos(14, 22), TilePos(n - 16, n - 26), TilePos(n / 2, n / 2)] { seedOre(p) }
        clearLanes()
        recount()
    }

    func clear(around c: TilePos, radius: Int) {
        for y in (c.y - radius)...(c.y + radius) { for x in (c.x - radius)...(c.x + radius) where Skirmish.inside(x, y) { open(x, y) } }
    }

    /// Make a tile crossable, in the terrain picture as well: whatever stood there is gone and water becomes ground.
    func open(_ x: Int, _ y: Int) {
        blocked[Skirmish.idx(x, y)] = false
        let ch = (y / 32) * 3 + x / 32, t = (y % 32) * 32 + x % 32
        let c = Content.shared
        if c.solid[Int(layers[ch][0][t])] { layers[ch][0][t] = c.tid("dirt") }
        for l in 1...3 { let v = Int(layers[ch][l][t]); if v != 0 && (l == 3 || c.solid[v]) { layers[ch][l][t] = 0 } }
    }

    func seedOre(_ c: TilePos) {
        clear(around: c, radius: 4)
        for y in (c.y - 3)...(c.y + 3) { for x in (c.x - 3)...(c.x + 3) where Skirmish.inside(x, y) {
            let d = abs(x - c.x) + abs(y - c.y)
            if d <= 4 && rng.unit() < 0.8 { ore[Skirmish.idx(x, y)] = 500 + Double(Int(rng.unit() * 5)) * 100 }
        } }
    }

    /// Whatever the land looks like, the two bases can always reach each other and the middle: a
    /// wide path is opened along the diagonal and the two edges.
    func clearLanes() {
        let n = Skirmish.n
        for i in 8..<(n - 8) {
            for w in -2...2 {
                let x = i, y = n - 1 - i + w
                if Skirmish.inside(x, y) { open(x, y) }
            }
        }
        mapVersion += 1
    }

    // MARK: reading

    public func kindCount(_ side: Int, _ key: String) -> Int {
        let k = SkKind.named(key)
        return entities.values.filter { $0.side == side && $0.kind == k }.count
    }

    public func owns(_ side: Int, _ key: String) -> Bool { kindCount(side, key) > 0 }

    /// Can this side start making this now (it has what it needs first)? Money is asked for when it is ordered.
    public func available(_ side: Int, _ kind: Int) -> Bool {
        let d = SkKind.all[kind]
        if d.key == "hq" { return false }
        return d.needs.allSatisfy { owns(side, $0) } && owns(side, "hq")
    }

    public func walkable(_ x: Int, _ y: Int) -> Bool {
        Skirmish.inside(x, y) && !blocked[Skirmish.idx(x, y)] && occupied[Skirmish.idx(x, y)] == 0
    }

    /// May a structure of this kind stand with its corner here: free ground, no moonstone, and next to something this side owns.
    public func canPlace(_ kind: Int, side: Int, at t: TilePos) -> Bool {
        let d = SkKind.all[kind]
        var near = false
        for y in t.y..<(t.y + d.h) { for x in t.x..<(t.x + d.w) {
            guard walkable(x, y), ore[Skirmish.idx(x, y)] <= 0 else { return false }
        } }
        for e in entities.values where e.side == side && e.def.structure {
            let dx = max(e.tile.x - (t.x + d.w), t.x - (e.tile.x + e.def.w)), dy = max(e.tile.y - (t.y + d.h), t.y - (e.tile.y + e.def.h))
            if max(dx, dy) <= 3 { near = true; break }
        }
        if !near { return false }
        // nobody may be standing there
        let x0 = Double(t.x * 16), y0 = Double(t.y * 16), x1 = Double((t.x + d.w) * 16), y1 = Double((t.y + d.h) * 16)
        return !entities.values.contains { !$0.def.structure && $0.pos.x > x0 && $0.pos.x < x1 && $0.pos.y > y0 && $0.pos.y < y1 }
    }

    public func entity(at p: Vec2, radius: Double = 12) -> SkEntity? {
        var best: (SkEntity, Double)?
        for e in entities.values {
            if e.def.structure {
                if p.x >= Double(e.tile.x * 16) && p.x < Double((e.tile.x + e.def.w) * 16) && p.y >= Double(e.tile.y * 16) && p.y < Double((e.tile.y + e.def.h) * 16) { return e }
            } else {
                let d = e.pos.distance(to: p)
                if d < radius && d < (best?.1 ?? .infinity) { best = (e, d) }
            }
        }
        return best?.0
    }

    public func units(of side: Int, in a: Vec2, _ b: Vec2) -> [Int] {
        let x0 = min(a.x, b.x), x1 = max(a.x, b.x), y0 = min(a.y, b.y), y1 = max(a.y, b.y)
        return entities.values.filter { $0.side == side && !$0.def.structure && $0.pos.x >= x0 && $0.pos.x <= x1 && $0.pos.y >= y0 && $0.pos.y <= y1 }.map { $0.id }.sorted()
    }

    public func takeEvents() -> [SkEvent] { let e = events; events.removeAll(); return e }

    // MARK: orders

    /// Ask a line to make something. The price is taken now and given back if it is cancelled.
    @discardableResult public func queue(_ side: Int, _ kind: Int) -> Bool {
        let d = SkKind.all[kind]
        guard winner == nil, available(side, kind), sides[side].credits >= d.cost else { return false }
        if d.line == 0 && (sides[side].ready != nil || sides[side].making[0] != nil) { return false }       // one structure at a time
        if sides[side].queued[d.line].count >= 9 { return false }
        sides[side].credits -= d.cost
        if sides[side].making[d.line] == nil { sides[side].making[d.line] = kind; sides[side].progress[d.line] = 0 }
        else { sides[side].queued[d.line].append(kind) }
        return true
    }

    /// Drop the last thing asked of a line (or what it is making, or the finished structure) and take the price back.
    @discardableResult public func cancel(_ side: Int, line: Int) -> Bool {
        if line == 0, let r = sides[side].ready { sides[side].ready = nil; sides[side].credits += SkKind.all[r].cost; return true }
        if let k = sides[side].queued[line].popLast() { sides[side].credits += SkKind.all[k].cost; return true }
        if let k = sides[side].making[line] { sides[side].making[line] = nil; sides[side].progress[line] = 0; sides[side].credits += SkKind.all[k].cost; return true }
        return false
    }

    /// Put the finished structure down.
    @discardableResult public func placeReady(_ side: Int, at t: TilePos) -> Bool {
        guard let k = sides[side].ready, canPlace(k, side: side, at: t) else { return false }
        sides[side].ready = nil
        place(k, side: side, at: t, free: false)
        return true
    }

    public func order(_ ids: [Int], move to: Vec2, attacking: Bool = false) {
        let mine = ids.compactMap { entities[$0] }.filter { !$0.def.structure }
        // the group spreads out around the place instead of all wanting the same spot
        let cols = max(1, Int(Double(mine.count).squareRoot().rounded(.up)))
        for (i, e) in mine.enumerated() {
            let off = Vec2(Double(i % cols) - Double(cols - 1) / 2, Double(i / cols) - Double((mine.count - 1) / cols) / 2) * 14
            var p = to + off
            p = Vec2(min(Double(Skirmish.n * 16 - 8), max(8, p.x)), min(Double(Skirmish.n * 16 - 8), max(8, p.y)))
            if !walkable(p.tile.x, p.tile.y) { p = to }
            entities[e.id]?.order = attacking && e.def.damage > 0 ? .attackMove(p) : .move(p)
            entities[e.id]?.targetID = 0
        }
    }

    public func order(_ ids: [Int], attack target: Int) {
        guard let t = entities[target] else { return }
        for id in ids { guard let e = entities[id], !e.def.structure, e.side != t.side else { continue }
            if e.def.damage > 0 { entities[id]?.order = .attack(target) } else { entities[id]?.order = .move(t.pos) }
        }
    }

    public func orderHarvest(_ ids: [Int]) {
        let h = SkKind.named("harvester")
        for id in ids where entities[id]?.kind == h { entities[id]?.order = .harvest }
    }

    public func stop(_ ids: [Int]) { for id in ids where entities[id]?.def.structure == false { entities[id]?.order = .idle; entities[id]?.targetID = 0 } }

    // MARK: making things

    @discardableResult func spawn(_ kind: Int, side: Int, at p: Vec2) -> Int {
        var e = SkEntity()
        e.id = nextID; nextID += 1
        e.kind = kind; e.side = side; e.pos = p; e.hp = SkKind.all[kind].hp
        e.facing = side == 0 ? Vec2(0, -1) : Vec2(0, 1)
        if SkKind.all[kind].key == "harvester" { e.order = .harvest }
        entities[e.id] = e
        return e.id
    }

    @discardableResult func place(_ kind: Int, side: Int, at t: TilePos, free: Bool) -> Int {
        let d = SkKind.all[kind]
        var e = SkEntity()
        e.id = nextID; nextID += 1
        e.kind = kind; e.side = side; e.tile = t; e.hp = d.hp
        e.pos = Vec2(Double(t.x * 16) + Double(d.w) * 8, Double(t.y * 16) + Double(d.h) * 8)
        entities[e.id] = e
        for y in t.y..<(t.y + d.h) { for x in t.x..<(t.x + d.w) where Skirmish.inside(x, y) { occupied[Skirmish.idx(x, y)] = e.id; blocked[Skirmish.idx(x, y)] = false } }
        mapVersion += 1
        fields.removeAll(); fieldAge.removeAll()
        if !free {
            events.append(SkEvent(kind: "placed", a: e.pos, b: e.pos, side: side, what: kind))
            if d.key == "refinery" { spawn(SkKind.named("harvester"), side: side, at: exit(of: e)) }      // a refinery comes with its own harvester
        }
        recount()
        return e.id
    }

    /// A free tile next to a structure, for what comes out of it.
    func exit(of s: SkEntity) -> Vec2 {
        let d = s.def
        for r in 1...4 {
            for x in (s.tile.x - r)...(s.tile.x + d.w - 1 + r) { for y in [s.tile.y + d.h - 1 + r, s.tile.y - r] where walkable(x, y) { return TilePos(x, y).center } }
            for y in (s.tile.y - r)...(s.tile.y + d.h - 1 + r) { for x in [s.tile.x + d.w - 1 + r, s.tile.x - r] where walkable(x, y) { return TilePos(x, y).center } }
        }
        return s.pos
    }

    func recount() {
        for s in sides.indices {
            var made = 0.0, used = 0.0
            for e in entities.values where e.side == s && e.def.structure { if e.def.power > 0 { made += e.def.power } else { used -= e.def.power } }
            let was = sides[s].lowPower
            sides[s].powerMade = made; sides[s].powerUsed = used
            if sides[s].lowPower && !was { events.append(SkEvent(kind: "lowpower", a: .zero, b: .zero, side: s, what: 0)) }
        }
    }

    // MARK: moving

    /// Steps to a goal tile from every tile that can reach it (a flood from the goal); shared by everyone going there.
    func field(to goal: TilePos) -> [UInt16] {
        let n = Skirmish.n
        let key = Skirmish.idx(min(n - 1, max(0, goal.x)), min(n - 1, max(0, goal.y)))
        if let f = fields[key] { fieldAge[key] = Int(time * 10); return f }
        if fields.count > 48, let old = fieldAge.min(by: { $0.value < $1.value })?.key { fields[old] = nil; fieldAge[old] = nil }
        var dist = [UInt16](repeating: .max, count: n * n)
        var queue = [key]
        dist[key] = 0
        // a goal inside a structure means "get to that structure": the flood starts from all of it
        // (from its middle alone it could never get out past the structure's own tiles)
        if occupied[key] != 0 {
            for i in occupied.indices where occupied[i] == occupied[key] && i != key { dist[i] = 0; queue.append(i) }
        }
        var head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let x = i % n, y = i / n, d = dist[i] + 1
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard Skirmish.inside(nx, ny) else { continue }
                let j = Skirmish.idx(nx, ny)
                if dist[j] != .max || blocked[j] || occupied[j] != 0 { continue }
                dist[j] = d
                queue.append(j)
            }
        }
        fields[key] = dist; fieldAge[key] = Int(time * 10)
        return dist
    }

    /// One step of a unit towards a place. Returns true when it is as near as `near`.
    func walk(_ id: Int, to goal: Vec2, near: Double, dt: Double) -> Bool {
        guard var e = entities[id] else { return true }
        let d = e.pos.distance(to: goal)
        if d <= near { e.moving = false; entities[id] = e; return true }
        var dir = (goal - e.pos).normalized
        let t = e.pos.tile, g = goal.tile
        if t != g {
            // follow the flood downhill; a goal inside a structure is approached through its nearest free tile
            let f = field(to: g)
            var bestD = UInt16.max, bestT = t
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)] {
                let nx = t.x + dx, ny = t.y + dy
                guard walkable(nx, ny) else { continue }
                if dx != 0 && dy != 0 && (!walkable(t.x + dx, t.y) || !walkable(t.x, t.y + dy)) { continue }     // no cutting corners
                let v = f[Skirmish.idx(nx, ny)]
                if v < bestD { bestD = v; bestT = TilePos(nx, ny) }
            }
            let here = Skirmish.inside(t.x, t.y) ? f[Skirmish.idx(t.x, t.y)] : .max
            if bestD < here || (here == .max && bestD != .max) { dir = (bestT.center - e.pos).normalized }
            else if here == .max && bestD == .max { e.moving = false; entities[id] = e; return d <= near + 40 }   // no way there
        }
        // keep a little apart from the others
        var push = Vec2.zero
        for oid in ids where oid != id {                    // in id order, so the sum is the same every run
            guard let o = entities[oid], !o.def.structure else { continue }
            let v = e.pos - o.pos
            let l = v.length
            if l < 10 && l > 0.01 { push = push + v.normalized * ((10 - l) / 10) }
        }
        let step = (dir + push * 0.6).normalized * (e.def.speed * dt)
        let np = e.pos + step
        if walkable(np.tile.x, np.tile.y) || np.tile == t { e.pos = np }
        else if walkable(Vec2(np.x, e.pos.y).tile.x, e.pos.tile.y) { e.pos = Vec2(np.x, e.pos.y) }
        else if walkable(e.pos.tile.x, Vec2(e.pos.x, np.y).tile.y) { e.pos = Vec2(e.pos.x, np.y) }
        e.facing = dir
        e.moving = true
        entities[id] = e
        return false
    }

    // MARK: one step

    /// Advance by real seconds in fixed steps (so the same orders always give the same battle).
    public func tick(_ dt: Double) {
        acc += min(0.5, dt)
        while acc >= 1.0 / 20 { acc -= 1.0 / 20; step(1.0 / 20) }
    }

    func step(_ dt: Double) {
        guard winner == nil else { return }
        time += dt
        // the lines
        for s in sides.indices {
            for line in 0..<3 {
                guard let k = sides[s].making[line] else { continue }
                let d = SkKind.all[k]
                // a unit needs its building; without it the line waits
                let maker = line == 1 ? "barracks" : (line == 2 ? "works" : "hq")
                let makers = entities.values.filter { $0.side == s && $0.def.key == maker }.sorted { $0.id < $1.id }
                guard let m = makers.first else { continue }
                sides[s].progress[line] += dt / d.time * (sides[s].lowPower ? 0.4 : 1) * (1 + 0.25 * Double(makers.count - 1))
                if sides[s].progress[line] >= 1 {
                    if d.structure { sides[s].ready = k; events.append(SkEvent(kind: "built", a: m.pos, b: m.pos, side: s, what: k)) }
                    else {
                        let id = spawn(k, side: s, at: exit(of: m))
                        events.append(SkEvent(kind: "trained", a: m.pos, b: m.pos, side: s, what: k))
                        if d.damage > 0, let at = entities[id]?.pos { entities[id]?.order = .move(at + Vec2(Double((id * 7) % 5 - 2) * 10, s == 0 ? -26 : 26)) }
                    }
                    sides[s].progress[line] = 0
                    sides[s].making[line] = sides[s].queued[line].isEmpty ? nil : sides[s].queued[line].removeFirst()
                }
            }
            if sides[s].computer { think(s, dt) }
        }
        // everyone
        ids = entities.keys.sorted()
        for id in ids {
            guard var e = entities[id] else { continue }
            e.cooldown = max(0, e.cooldown - dt); e.sinceShot += dt; e.sinceHurt += dt
            entities[id] = e
            let d = e.def
            if d.key == "harvester" { harvest(id, dt); continue }
            if d.damage <= 0 { if case .move(let p) = e.order, walk(id, to: p, near: 5, dt: dt) { entities[id]?.order = .idle }; continue }
            if d.structure && sides[e.side].lowPower { continue }          // turrets need power
            switch e.order {
            case .move(let p):
                if walk(id, to: p, near: 5, dt: dt) { entities[id]?.order = .idle }
            case .attack(let t):
                guard let target = entities[t] else { entities[id]?.order = .idle; continue }
                engage(id, target, dt, chase: true)
            case .attackMove(let p):
                if let t = nearestEnemy(of: e, within: d.range + 40) { engage(id, t, dt, chase: true) }
                else if walk(id, to: p, near: 6, dt: dt) { entities[id]?.order = .idle }
            default:
                // standing: shoot what comes near, and step towards it a little, but do not run across the map
                if let t = nearestEnemy(of: e, within: d.range + (d.structure ? 0 : 24)) { engage(id, t, dt, chase: !d.structure) }
                else { entities[id]?.moving = false }
            }
        }
        // the end: a side with no structure left has lost
        for s in sides.indices where !entities.values.contains(where: { $0.side == s && $0.def.structure }) { winner = 1 - s }
    }

    func nearestEnemy(of e: SkEntity, within r: Double) -> SkEntity? {
        var best: (SkEntity, Double)?
        for o in entities.values where o.side != e.side {
            let d = reach(e.pos, o)
            if d <= r && (best == nil || d < best!.1 || (d == best!.1 && o.id < best!.0.id)) { best = (o, d) }
        }
        return best?.0
    }

    /// Distance from a point to the nearest part of something (a structure is as big as its footprint).
    func reach(_ p: Vec2, _ o: SkEntity) -> Double {
        if !o.def.structure { return p.distance(to: o.pos) }
        let x0 = Double(o.tile.x * 16), y0 = Double(o.tile.y * 16), x1 = Double((o.tile.x + o.def.w) * 16), y1 = Double((o.tile.y + o.def.h) * 16)
        let dx = max(x0 - p.x, 0, p.x - x1), dy = max(y0 - p.y, 0, p.y - y1)
        return (dx * dx + dy * dy).squareRoot()
    }

    func engage(_ id: Int, _ target: SkEntity, _ dt: Double, chase: Bool) {
        guard var e = entities[id] else { return }
        let d = e.def
        if reach(e.pos, target) > d.range {
            if chase { _ = walk(id, to: target.pos, near: 0, dt: dt) }
            return
        }
        e.moving = false
        e.facing = (target.pos - e.pos).normalized
        if e.cooldown <= 0 {
            e.cooldown = d.cooldown; e.sinceShot = 0
            entities[id] = e
            events.append(SkEvent(kind: "shot", a: e.pos, b: target.pos, side: e.side, what: e.kind))
            hurt(target.id, d.damage * d.vs[target.def.armor.rawValue], by: e.side)
        } else { entities[id] = e }
    }

    func hurt(_ id: Int, _ dmg: Double, by side: Int) {
        guard var t = entities[id] else { return }
        t.hp -= dmg; t.sinceHurt = 0
        if t.hp > 0 {
            entities[id] = t
            // whoever is shot at and has nothing to do shoots back
            if !t.def.structure && t.def.damage > 0 && t.order == .idle, let a = nearestEnemy(of: t, within: t.def.range + 80) { entities[id]?.order = .attack(a.id) }
            if t.def.structure && sides[t.side].computer { sides[t.side].thinkT = 0 }
            return
        }
        entities[id] = nil
        sides[t.side].lost += 1; sides[side].killed += 1
        events.append(SkEvent(kind: "died", a: t.pos, b: t.pos, side: t.side, what: t.kind))
        if t.def.structure {
            for i in occupied.indices where occupied[i] == id { occupied[i] = 0 }
            mapVersion += 1; fields.removeAll(); fieldAge.removeAll()
            recount()
            // what its line was making is lost with the last building that could make it
            let line = t.def.key == "barracks" ? 1 : (t.def.key == "works" ? 2 : -1)
            if line > 0 && !owns(t.side, t.def.key) { sides[t.side].making[line] = nil; sides[t.side].queued[line] = []; sides[t.side].progress[line] = 0 }
        }
    }

    // MARK: harvesting

    static let load = 500.0

    func harvest(_ id: Int, _ dt: Double) {
        guard var e = entities[id] else { return }
        switch e.order {
        case .move(let p):
            if walk(id, to: p, near: 5, dt: dt) { entities[id]?.order = .idle }
        case .harvest:
            if e.cargo >= Skirmish.load { entities[id]?.order = .deliver; return }
            let t = e.pos.tile
            let here = Skirmish.inside(t.x, t.y) ? Skirmish.idx(t.x, t.y) : 0
            if ore[here] > 0 {
                let take = min(ore[here], 110 * dt, Skirmish.load - e.cargo)
                ore[here] -= take; e.cargo += take; e.moving = false
                entities[id] = e
                return
            }
            // the nearest moonstone (by straight distance; the flood gets it there)
            var best: (Int, Double)?
            for i in ore.indices where ore[i] > 0 {
                let p = TilePos(i % Skirmish.n, i / Skirmish.n).center
                let d = p.distance(to: e.pos)
                if best == nil || d < best!.1 { best = (i, d) }
            }
            guard let b = best else { entities[id]?.order = e.cargo > 0 ? .deliver : .idle; return }
            _ = walk(id, to: TilePos(b.0 % Skirmish.n, b.0 / Skirmish.n).center, near: 3, dt: dt)
        case .deliver:
            let refs = entities.values.filter { $0.side == e.side && $0.def.key == "refinery" }
            // with no refinery, the headquarters takes it (slowly), so a side is never stuck
            let homes = refs.isEmpty ? entities.values.filter { $0.side == e.side && $0.def.key == "hq" } : refs
            guard let home = homes.min(by: { reach(e.pos, $0) != reach(e.pos, $1) ? reach(e.pos, $0) < reach(e.pos, $1) : $0.id < $1.id }) else { entities[id]?.order = .idle; return }
            if reach(e.pos, home) <= 26 {
                let give = min(e.cargo, (refs.isEmpty ? 120 : 400) * dt)
                e.cargo -= give; e.moving = false
                entities[id] = e
                sides[e.side].credits += give; sides[e.side].mined += give
                if e.cargo <= 0.01 { entities[id]?.cargo = 0; entities[id]?.order = .harvest }
            } else {
                _ = walk(id, to: exit(of: home), near: 4, dt: dt)
            }
        default:
            entities[id]?.moving = false
        }
    }

    // MARK: the computer

    static let plan = ["reactor", "refinery", "barracks", "reactor", "works", "turret", "refinery", "reactor", "turret", "works", "reactor", "barracks", "turret"]

    func think(_ s: Int, _ dt: Double) {
        sides[s].thinkT -= dt
        guard sides[s].thinkT <= 0 else { return }
        sides[s].thinkT = 1.0
        guard let hq = entities.values.filter({ $0.side == s && $0.def.key == "hq" }).min(by: { $0.id < $1.id }) else {
            // no headquarters: everything left goes for the enemy
            let army = entities.values.filter { $0.side == s && !$0.def.structure && $0.def.damage > 0 }.map { $0.id }.sorted()
            if let t = entities.values.filter({ $0.side != s && $0.def.structure }).min(by: { $0.id < $1.id }) { order(army, move: t.pos, attacking: true) }
            return
        }
        // put down what is finished, as near the headquarters as it fits
        if let r = sides[s].ready {
            let d = SkKind.all[r]
            search: for radius in 2...14 {
                for y in (hq.tile.y - radius)...(hq.tile.y + 2 + radius) { for x in (hq.tile.x - radius)...(hq.tile.x + 2 + radius) {
                    if abs(x - hq.tile.x - 1) < radius - 1 && abs(y - hq.tile.y - 1) < radius - 1 { continue }       // only the ring
                    // leave a tile of road around every building
                    var roomy = true
                    for yy in (y - 1)...(y + d.h) { for xx in (x - 1)...(x + d.w) where !walkable(xx, yy) { roomy = false } }
                    if roomy && placeReady(s, at: TilePos(x, y)) { break search }
                } }
            }
        }
        // the next building of the plan, more power whenever it runs short
        if sides[s].making[0] == nil && sides[s].ready == nil {
            var want = Skirmish.plan[min(sides[s].step, Skirmish.plan.count - 1)]
            if sides[s].step >= Skirmish.plan.count { want = sides[s].powerMade - sides[s].powerUsed < 40 ? "reactor" : "turret" }
            if sides[s].powerUsed + 30 > sides[s].powerMade && owns(s, "reactor") { want = "reactor" }
            if !owns(s, "refinery") && owns(s, "reactor") { want = "refinery" }
            let k = SkKind.named(want)
            if available(s, k) && queue(s, k) && want == Skirmish.plan[min(sides[s].step, Skirmish.plan.count - 1)] { sides[s].step += 1 }
        }
        // harvesters: two for each refinery
        let harv = kindCount(s, "harvester") + (sides[s].making[2] == SkKind.named("harvester") ? 1 : 0)
        if owns(s, "works") && harv < 2 * kindCount(s, "refinery") && sides[s].making[2] == nil { queue(s, SkKind.named("harvester")) }
        // soldiers and vehicles, keeping something back for buildings
        if sides[s].credits > 700 {
            if sides[s].making[1] == nil && owns(s, "barracks") { queue(s, SkKind.named(rng.unit() < 0.6 ? "rifle" : "lancer")) }
            if sides[s].making[2] == nil && owns(s, "works") { let r = rng.unit(); queue(s, SkKind.named(r < 0.5 ? "scout" : (r < 0.8 ? "bastion" : "mortar"))) }
        }
        // the army: defend the base when something of ours is being shot at, else attack in waves that grow
        let army = entities.values.filter { $0.side == s && !$0.def.structure && $0.def.damage > 0 }.sorted { $0.id < $1.id }
        if let hit = entities.values.filter({ $0.side == s && $0.def.structure && $0.sinceHurt < 2 }).min(by: { $0.id < $1.id }) {
            let idle = army.filter { $0.pos.distance(to: hq.pos) < 420 }.map { $0.id }
            order(idle, move: hit.pos, attacking: true)
            return
        }
        let need = 8 + sides[s].wave * 4            // the first wave is eight strong; each one after is larger
        let home = army.filter { $0.order == .idle && $0.pos.distance(to: hq.pos) < 300 }
        if home.count >= need {
            // the nearest thing the enemy has built
            if let t = entities.values.filter({ $0.side != s && $0.def.structure }).min(by: { $0.pos.distance(to: hq.pos) != $1.pos.distance(to: hq.pos) ? $0.pos.distance(to: hq.pos) < $1.pos.distance(to: hq.pos) : $0.id < $1.id }) {
                order(home.map { $0.id }, move: t.pos, attacking: true)
                sides[s].wave += 1
                events.append(SkEvent(kind: "attack", a: hq.pos, b: t.pos, side: s, what: home.count))
            }
        }
        // those who arrived and found nothing go on to the next building
        for e in army where e.order == .idle && e.pos.distance(to: hq.pos) > 500 {
            if let t = entities.values.filter({ $0.side != s && $0.def.structure }).min(by: { $0.pos.distance(to: e.pos) != $1.pos.distance(to: e.pos) ? $0.pos.distance(to: e.pos) < $1.pos.distance(to: e.pos) : $0.id < $1.id }) {
                order([e.id], move: t.pos, attacking: true)
            }
        }
    }

    /// Hand a side to the computer (or take it back): used to let a whole battle play itself.
    public func setComputer(_ side: Int, _ on: Bool) { sides[side].computer = on }

    /// One line a battle can be compared by.
    public var summary: String {
        let per = sides.indices.map { s in "\(sides[s].name) \(Int(sides[s].credits))c \(entities.values.filter { $0.side == s && $0.def.structure }.count)b \(entities.values.filter { $0.side == s && !$0.def.structure }.count)u k\(sides[s].killed)" }
        return String(format: "t=%.0f ", time) + per.joined(separator: " | ") + (winner.map { " winner \($0)" } ?? "")
    }
}

public extension PixelArt {
    /// A structure or vehicle of command mode seen from above, in its side's colour (infantry use `character`).
    /// Vehicles are drawn pointing up; the app turns them.
    static func skirmish(_ kind: SkKind, color: RGBA) -> Bitmap {
        let steel = RGBA(hex: "#6e7480"), dark = RGBA(hex: "#2a2e38"), light = RGBA(hex: "#c8ccd8"), glow = RGBA(hex: "#9fe8ff")
        if kind.structure {
            let w = kind.w * 16, h = kind.h * 16 + 8
            var b = Bitmap(w, h)
            // walls with a lit top edge, a darker front, and the side's colour on the roof
            b.rect(1, 8, w - 2, h - 9, steel); b.rect(1, h - 7, w - 2, 6, steel.darkened(0.35)); b.rect(1, 8, w - 2, 2, light)
            b.rect(3, 11, w - 6, h - 21, color.darkened(0.15)); b.rect(3, 11, w - 6, 2, color.lightened(0.25))
            switch kind.key {
            case "hq":
                b.rect(w / 2 - 8, 2, 16, 14, steel); b.rect(w / 2 - 6, 4, 12, 9, color); b.rect(w / 2 - 1, 0, 2, 6, light)
                b.rect(w / 2 - 5, h - 14, 10, 8, dark); b.disc(Double(w) - 10, 18, 4, light); b.disc(Double(w) - 10, 18, 2, dark)
            case "reactor":
                b.disc(Double(w) / 2, Double(h) / 2 - 1, 9, dark); b.disc(Double(w) / 2, Double(h) / 2 - 1, 6.5, glow); b.disc(Double(w) / 2 - 1, Double(h) / 2 - 2, 3, .white)
            case "refinery":
                b.rect(4, 4, 10, 16, steel.lightened(0.1)); b.rect(5, 2, 8, 3, light); b.rect(w - 20, h - 16, 16, 10, dark); b.rect(w - 18, h - 14, 12, 3, glow)
                b.rect(18, 14, w - 40, 3, dark)
            case "barracks":
                b.rect(w / 2 - 4, h - 13, 8, 7, dark); b.rect(4, 14, 5, 4, light); b.rect(w - 9, 14, 5, 4, light); b.rect(w / 2 - 1, 2, 2, 10, light); b.rect(w / 2 + 1, 2, 6, 4, color)
            case "works":
                b.rect(6, h - 18, w - 12, 12, dark); for x in stride(from: 8, to: w - 8, by: 5) { b.rect(x, h - 18, 1, 12, steel) }
                b.rect(w - 12, 2, 6, 14, steel.darkened(0.2)); b.rect(w - 13, 1, 8, 2, light)
            case "turret":
                b.disc(8, 13, 6, dark); b.disc(8, 13, 4, color); b.rect(7, 2, 2, 10, light)
            default: break
            }
            return b
        }
        var b = Bitmap(24, 24)
        switch kind.key {
        case "harvester":
            b.rect(5, 4, 14, 17, steel); b.rect(6, 5, 12, 9, color); b.rect(7, 15, 10, 5, RGBA(hex: "#3a4a5a")); b.rect(4, 3, 16, 2, dark)
            b.rect(3, 6, 2, 13, dark); b.rect(19, 6, 2, 13, dark)
        case "scout":
            b.rect(7, 6, 10, 14, color.darkened(0.15)); b.rect(5, 6, 2, 14, dark); b.rect(17, 6, 2, 14, dark); b.disc(12, 13, 3.6, color.lightened(0.15)); b.rect(11, 3, 2, 9, light)
        case "bastion":
            b.rect(5, 4, 14, 18, color.darkened(0.2)); b.rect(3, 4, 3, 18, dark); b.rect(18, 4, 3, 18, dark); b.disc(12, 13, 5, color); b.rect(10, 1, 4, 11, light); b.rect(11, 0, 2, 2, dark)
        case "mortar":
            b.rect(6, 5, 12, 16, color.darkened(0.2)); b.rect(4, 6, 2, 14, dark); b.rect(18, 6, 2, 14, dark); b.rect(8, 9, 8, 9, steel); b.rect(10, 2, 4, 10, dark); b.rect(11, 2, 2, 9, light)
        default:
            b.disc(12, 12, 4, color)
        }
        return b
    }
}
