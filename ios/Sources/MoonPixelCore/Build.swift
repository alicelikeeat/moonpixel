import Foundation

/// Free building on the tile grid, for the player and the villagers alike:
/// one catalogue of pieces, one set of placement rules, preview before paying,
/// refunds on demolition, and switches, wires and devices that work.
public struct Piece {
    public let key: String, tile: String, en: String, zh: String
    public let layer: Int
    public let cost: [(String, Double)]
    public let group: Int          // 0 structure, 1 ways, 2 production, 3 mechanisms, 4 city
    public let onWater: Bool
    public func name(zh z: Bool) -> String { z ? zh : en }

    static func p(_ k: String, _ t: String, _ en: String, _ zh: String, _ l: Int, _ c: [(String, Double)], _ g: Int, water: Bool = false) -> Piece {
        Piece(key: k, tile: t, en: en, zh: zh, layer: l, cost: c, group: g, onWater: water)
    }
    public static let all: [Piece] = [
        p("floor_wood", "wood_floor", "Wood floor", "木地板", 0, [("wood", 1)], 0),
        p("floor_stone", "stone_floor", "Stone floor", "石地板", 0, [("stone", 1)], 0),
        p("wall_wood", "wall_wood", "Wood wall", "木墙", 2, [("wood", 2)], 0),
        p("wall_stone", "wall_stone", "Stone wall", "石墙", 2, [("stone", 2)], 0),
        p("wall_concrete", "wall_concrete", "Concrete wall", "混凝土墙", 2, [("stone", 2), ("iron", 1)], 0),
        p("wall_glass", "wall_glass", "Glass curtain wall", "玻璃幕墙", 2, [("stone", 1), ("iron", 1), ("parts", 1)], 0),
        p("wall_limestone", "wall_limestone", "Limestone wall", "石灰岩墙", 2, [("stone", 3)], 0),
        p("wall_deco", "wall_deco", "Art Deco wall", "装饰艺术墙", 2, [("stone", 2), ("iron", 1)], 0),
        p("wall_brownstone", "wall_brownstone", "Brownstone wall", "褐石墙", 2, [("stone", 2), ("planks", 1)], 0),
        p("spire_steel", "spire_steel", "Steel spire", "不锈钢尖顶", 2, [("iron", 2), ("parts", 1)], 0),
        p("gate", "gate", "City gate", "城门", 2, [("wood", 3), ("iron", 1)], 0),
        p("door", "door_wood", "Door", "木门", 2, [("wood", 2)], 0),
        p("fence", "fence", "Fence", "围栏", 2, [("wood", 1)], 0),
        p("bed", "bed", "Bed", "床", 2, [("wood", 3)], 0),
        p("torch", "torch", "Torch", "火把", 2, [("wood", 1)], 0),
        p("road", "cobble_road", "Road", "道路", 1, [("stone", 1)], 1),
        p("bridge", "bridge_wood", "Bridge", "桥梁", 1, [("wood", 3)], 1, water: true),
        p("stairs", "stairs_down", "Mine stairs", "矿井阶梯", 2, [("wood", 4), ("stone", 4)], 1),
        p("stairs_up", "stairs_up", "Stairs up", "向上楼梯", 2, [("wood", 4), ("stone", 2)], 1),
        p("workbench", "workbench", "Workbench", "工作台", 2, [("wood", 6)], 2),
        p("furnace", "furnace", "Furnace", "熔炉", 2, [("stone", 8)], 2),
        p("anvil", "anvil", "Anvil", "铁砧", 2, [("iron", 3)], 2),
        p("kitchen", "kitchen", "Kitchen", "厨房", 2, [("stone", 4), ("wood", 2)], 2),
        p("warehouse", "chest", "Warehouse chest", "仓库", 2, [("wood", 6)], 2),
        p("lever", "lever_off", "Lever", "拉杆", 2, [("wood", 1), ("iron", 1)], 3),
        p("plate", "plate", "Pressure plate", "压力板", 2, [("stone", 1), ("iron", 1)], 3),
        p("wire", "wire", "Wire", "连接线", 3, [("iron", 0.25)], 3),
        p("lamp", "lamp_off", "Lamp", "灯", 2, [("iron", 1)], 3),
        p("door_iron", "door_iron", "Iron door", "铁门", 2, [("iron", 3)], 3),
        p("trap", "trap", "Spike trap", "尖刺陷阱", 2, [("iron", 2)], 3),
        p("tower", "tower", "Watchtower", "瞭望塔", 2, [("stone", 12), ("parts", 2)], 4),
        p("ballista", "ballista", "Ballista", "弩炮", 2, [("engines", 1)], 4),
        p("throne", "throne", "Throne", "王座", 2, [("parts", 6), ("gold_ore", 2)], 4),
        p("banner", "banner_1", "Banner", "旗帜", 2, [("wood", 2)], 4),
        p("stall", "market_stall", "Market stall", "市场摊位", 2, [("wood", 5), ("parts", 1)], 4),
        p("mill", "mill", "Windmill", "风车", 2, [("wood", 8), ("parts", 2)], 4),
    ]
    public static let byKey: [String: Piece] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    public static let groupNames: [(String, String)] = [("Structure", "结构"), ("Ways", "道路桥梁"), ("Production", "生产设施"), ("Mechanisms", "机关"), ("City", "城市")]
}

public struct BuildPlan: Codable, Equatable {
    public var id: Int
    public var piece: String
    public var cells: [TilePos]
    public init(id: Int, piece: String, cells: [TilePos]) { self.id = id; self.piece = piece; self.cells = cells }
}

public struct BuildPreview {
    public var cells: [(pos: TilePos, ok: Bool, reason: String)] = []
    public var cost: [String: Double] = [:]
    public var affordable = false
    public var valid: Int { cells.filter { $0.ok }.count }
}

public struct BuildResult {
    public var placed = 0
    public var cost: [String: Double] = [:]
    public var reason = ""             // "", "duplicate", "cost", "nothing"
    public var moved: Vec2?            // where the player was pushed to, if their tile was built on
}

extension Society {
    // MARK: what the player carries
    public func carried(_ good: String) -> Double {
        switch good {
        case "food": return realm.player.food
        case "wood": return realm.player.wood
        case "stone": return realm.player.stone
        default: return realm.player.goods?[good] ?? 0
        }
    }

    public func carry(_ good: String, _ delta: Double) {
        switch good {
        case "food": realm.player.food = max(0, realm.player.food + delta)
        case "wood": realm.player.wood = max(0, realm.player.wood + delta)
        case "stone": realm.player.stone = max(0, realm.player.stone + delta)
        default:
            var g = realm.player.goods ?? [:]
            g[good] = max(0, (g[good] ?? 0) + delta)
            if g[good] == 0 { g[good] = nil }
            realm.player.goods = g
        }
    }

    // MARK: one rule book for placing things
    /// Why a tile cannot take this piece ("" when it can). Used for the player's
    /// plans and for the cells villagers lay.
    public func placeProblem(_ tileKey: String, layer: Int, onWater: Bool, at t: TilePos, in w: OpenWorld, nation: Int) -> String {
        let water = content.water[Int(w.tile(0, t.x, t.y))]
        if onWater { if !water { return "land" } } else if water { return "water" }
        if layer == 1 { if w.tile(1, t.x, t.y) != 0 { return "occupied" } }
        else if layer == 2 { if w.tile(2, t.x, t.y) != 0 { return "occupied" } }
        else if layer == 3 { if w.tile(3, t.x, t.y) == content.tid(tileKey) { return "occupied" } }
        else if w.tile(0, t.x, t.y) == content.tid(tileKey) { return "occupied" }
        // storeys: a floor needs something under it to stand on; anything else needs a floor
        if w.storey > 0 {
            if layer == 0 { if !supported(t, onStorey: w.storey) { return "unsupported" } }
            else if w.tile(0, t.x, t.y) == 0 { return "no_floor" }
            if tileKey == "stairs_down" { return "stairs_from_below" }
        }
        if tileKey == "stairs_up" && w.isUnder { return "stairs_from_below" }
        if w.depth == 0, nation != 0 {
            // nobody builds inside a city that belongs to someone else
            for s in settlements.values where !s.abandoned && s.inArea(t) && (t - s.center).lengthSquared < 30 * 30 {
                if let n = s.nation, n != nation, n != 0 { return "foreign" }
            }
        }
        return ""
    }

    public func previewBuild(_ plan: BuildPlan, in w: OpenWorld? = nil) -> BuildPreview {
        var out = BuildPreview()
        guard let p = Piece.byKey[plan.piece] else { return out }
        let w = w ?? world
        var seen = Set<TilePos>()
        for c in plan.cells where !seen.contains(c) {
            seen.insert(c)
            let why = placeProblem(p.tile, layer: p.layer, onWater: p.onWater, at: c, in: w, nation: realm.player.nation)
            out.cells.append((c, why.isEmpty, why))
        }
        for (g, n) in p.cost { out.cost[g] = n * Double(out.valid) }
        out.affordable = out.valid > 0 && out.cost.allSatisfy { carried($0.key) >= $0.value - 1e-9 }
        return out
    }

    /// Carry out a plan. A plan is paid for once: sending the same id again does nothing.
    public func commitBuild(_ plan: BuildPlan, in w: OpenWorld? = nil, player: Vec2? = nil) -> BuildResult {
        var out = BuildResult()
        guard let p = Piece.byKey[plan.piece] else { out.reason = "nothing"; return out }
        if (realm.player.plans ?? []).contains(plan.id) { out.reason = "duplicate"; return out }
        let w = w ?? world
        let pre = previewBuild(plan, in: w)
        if pre.valid == 0 { out.reason = "nothing"; return out }
        if !pre.affordable { out.reason = "cost"; return out }
        var ids = realm.player.plans ?? []
        ids.append(plan.id)
        if ids.count > 64 { ids.removeFirst(ids.count - 64) }
        realm.player.plans = ids
        for (g, n) in pre.cost { carry(g, -n) }
        // a bridge is checked against the real routes between nearby towns, before and after
        let bridging = p.key == "bridge" && w.depth == 0
        let routesBefore = bridging ? routesNear(pre.cells.filter { $0.ok }.map { $0.pos }) : []
        var tile = content.tid(p.tile)
        if p.key == "banner" { tile = content.tid("banner_\(max(1, realm.player.nation))") }
        for c in pre.cells where c.ok {
            w.setTile(p.layer, c.pos.x, c.pos.y, tile)
            if p.layer == 2 && p.key != "ballista" { w.setTile(3, c.pos.x, c.pos.y, w.tile(3, c.pos.x, c.pos.y) == content.tid("wire") ? content.tid("wire") : 0) }
            out.placed += 1
            if content.solid[Int(tile)] {
                displace(from: c.pos, in: w)
                if let pp = player, pp.tile == c.pos { out.moved = w.findFree(near: c.pos, maxR: 6).center }
            }
            if p.key == "stairs" && w.depth == 0 { linkStairs(at: c.pos) }
            if p.key == "stairs_up" { linkUp(at: c.pos, from: w) }
            if p.group == 3 { updateNetwork(around: c.pos, in: w) }
        }
        out.cost = pre.cost
        if bridging && out.placed > 0 { creditBridge(before: routesBefore, cells: pre.cells.filter { $0.ok }.map { $0.pos }) }
        if w.depth == 0 { for s in settlements.values where !s.abandoned && pre.cells.contains(where: { s.inArea($0.pos) }) { s.planT = 0; s.cityT = 0 } }
        for lg in realm.legions { lg.supplyT = 0 }            // routes notice the change themselves (chunk stamps)
        if realm.liftBox != nil { checkLifts() }          // a landing built over or taken away
        return out
    }

    /// Move anyone standing on a tile that has just become solid (or lost its footing) to free ground nearby.
    func displace(from t: TilePos, in w: OpenWorld) {
        guard w.depth == 0 else { return }
        for a in agents.values where a.pos.tile == t {
            a.pos = w.findFree(near: t, maxR: 6).center
            a.path = []; a.task = nil
        }
        for i in realm.fauna.animals.indices where realm.fauna.animals[i].pos.tile == t { realm.fauna.animals[i].pos = w.findFree(near: t, maxR: 6).center }
    }

    /// Take a built thing down and get half of what it cost back. Returns the piece removed.
    @discardableResult public func demolishBuild(at t: TilePos, in w: OpenWorld? = nil) -> Piece? {
        let w = w ?? world
        for layer in [2, 3, 1, 0] {
            let id = w.tile(layer, t.x, t.y)
            if id == 0 { continue }
            let key = content.tile(id)?.key ?? ""
            let norm = key.hasPrefix("banner_") ? "banner_1" : (key == "gate_open" ? "gate" : (key == "lever_on" ? "lever_off" : (key == "lamp_on" ? "lamp_off" : (key == "door_iron_open" ? "door_iron" : (key == "trap_sprung" ? "trap" : key)))))
            guard let p = Piece.all.first(where: { $0.tile == norm && $0.layer == layer }) else { continue }
            if layer == 0 { w.restoreGround(t.x, t.y) } else { w.setTile(layer, t.x, t.y, 0) }
            for (g, n) in p.cost { carry(g, (n * 0.5 * 4).rounded(.down) / 4) }
            if p.key == "stairs" { unlinkStairs(at: t) }
            // the stair down that answered a stair up goes with it; floors left with nothing under them fall
            if p.key == "stairs_up" { let up = storeyWorld(w.storey + 1); if up.tile(2, t.x, t.y) == content.tid("stairs_down") { up.setTile(2, t.x, t.y, 0) } }
            if layer != 3 && !w.isUnder && (realm.storeyTop ?? 0) > w.storey { settleStoreys(above: w, around: t) }
            if p.group == 3 { updateNetwork(around: t, in: w) }
            realm.depots.removeAll { $0.x == t.x && $0.y == t.y }
            for lg in realm.legions { lg.supplyT = 0 }            // routes notice the change themselves (chunk stamps)
            if realm.liftBox != nil { checkLifts() }
            if w.depth == 0 { for s in settlements.values where !s.abandoned && s.inArea(t) { s.cityT = 0 } }
            return p
        }
        return nil
    }

    // MARK: switches, wires, devices
    static let sources: Set<String> = ["lever_on", "lever_off", "plate"]
    static let devices: [String: String] = ["lamp_off": "lamp_on", "door_iron": "door_iron_open", "gate": "gate_open", "trap": "trap_sprung"]

    /// Flip a lever, or open and close a gate or door by hand. Returns what happened ("" if nothing).
    @discardableResult public func interact(at t: TilePos, in w: OpenWorld? = nil) -> String {
        let w = w ?? world
        let key = content.tile(w.tile(2, t.x, t.y))?.key ?? ""
        switch key {
        case "lever_off": w.setTile(2, t.x, t.y, content.tid("lever_on")); updateNetwork(around: t, in: w); return "lever_on"
        case "lever_on": w.setTile(2, t.x, t.y, content.tid("lever_off")); updateNetwork(around: t, in: w); return "lever_off"
        case "gate": w.setTile(2, t.x, t.y, content.tid("gate_open")); return "gate_open"
        case "gate_open": w.setTile(2, t.x, t.y, content.tid("gate")); displace(from: t, in: w); return "gate"
        case "door_iron": w.setTile(2, t.x, t.y, content.tid("door_iron_open")); return "door_open"
        case "door_iron_open": w.setTile(2, t.x, t.y, content.tid("door_iron")); displace(from: t, in: w); return "door"
        default: return ""
        }
    }

    /// Someone stepped on or off a pressure plate.
    public func press(_ t: TilePos, down: Bool, in w: OpenWorld? = nil) {
        let w = w ?? world
        guard OpenWorld.sane(t), content.tile(w.tile(2, t.x, t.y))?.key == "plate" else { return }
        let was = pressed.contains(t)
        if down == was { return }
        if down { pressed.insert(t) } else { pressed.remove(t) }
        updateNetwork(around: t, in: w)
    }

    /// Recompute one connected network: wires carry power between neighbours;
    /// a network is powered when any lever in it is on or any plate is pressed.
    /// Bounded: a network larger than `maxNetwork` tiles is cut off there, so a
    /// loop of wire can never run away.
    @discardableResult public func updateNetwork(around start: TilePos, in w: OpenWorld? = nil) -> (tiles: Int, powered: Bool, changed: Int) {
        let w = w ?? world
        let wire = content.tid("wire")
        func role(_ t: TilePos) -> (wire: Bool, key: String) { (w.tile(3, t.x, t.y) == wire, content.tile(w.tile(2, t.x, t.y))?.key ?? "") }
        func member(_ r: (wire: Bool, key: String)) -> Bool { r.wire || Society.sources.contains(r.key) || Society.devices[r.key] != nil || Society.devices.values.contains(r.key) }
        var seen = Set<TilePos>()
        var total = 0, anyPower = false, changed = 0
        let limit = realm.cfg.maxNetwork
        // what was one network may now be several (a wire was cut): settle each piece on its own
        for d0 in [TilePos(0, 0), TilePos(1, 0), TilePos(-1, 0), TilePos(0, 1), TilePos(0, -1)] {
            let seed = start + d0
            if seen.contains(seed) || !member(role(seed)) { continue }
            var queue = [seed]
            seen.insert(seed)
            var i = 0, count = 1
            var powered = false
            var devices: [TilePos] = []
            while i < queue.count && count <= limit {
                let t = queue[i]; i += 1
                let r = role(t)
                if r.key == "lever_on" || (r.key == "plate" && pressed.contains(t)) { powered = true }
                if Society.devices[r.key] != nil || Society.devices.values.contains(r.key) { devices.append(t) }
                // power travels along wire, out of a source, and into a device beside either
                let conducts = r.wire || Society.sources.contains(r.key)
                for d in [TilePos(1, 0), TilePos(-1, 0), TilePos(0, 1), TilePos(0, -1)] {
                    let n = t + d
                    if seen.contains(n) { continue }
                    let nr = role(n)
                    if !member(nr) { continue }
                    if conducts || nr.wire || Society.sources.contains(nr.key) { seen.insert(n); queue.append(n); count += 1 }
                }
            }
            total += count
            anyPower = anyPower || powered
            for t in devices {
                let key = content.tile(w.tile(2, t.x, t.y))?.key ?? ""
                let on = Society.devices[key], off = Society.devices.first { $0.value == key }?.key
                if powered, let to = on { w.setTile(2, t.x, t.y, content.tid(to)); changed += 1; if to == "trap_sprung" { sprung.append(t) } }
                else if !powered, let to = off { w.setTile(2, t.x, t.y, content.tid(to)); changed += 1; if content.solid[Int(content.tid(to))] { displace(from: t, in: w) } }
            }
        }
        return (total, anyPower, changed)
    }

    /// Traps that fired since the last call (the scene hurts whoever stands there).
    public func takeSprung() -> [TilePos] { let l = sprung; sprung.removeAll(); return l }

    // MARK: stairs between the surface and the underground
    /// The underground layer of this world (created on first use, sharing the save folder).
    public func underworld() -> OpenWorld {
        if let u = under { return u }
        let u = OpenWorld(seed: world.seed, budget: world.budget, depth: 1)
        u.diskLimitBytes = world.diskLimitBytes
        if let st = world.store { u.open(store: st) }          // one store, one commit for both layers
        u.overlay = { [unowned self] ch in self.stampUnderland(ch) }   // the nations' underlands, as they reach
        under = u
        return u
    }

    /// A stair on the surface always has its partner directly below, in a cleared landing.
    func linkStairs(at t: TilePos) {
        let u = underworld()
        for dy in -1...1 { for dx in -1...1 {
            let x = t.x + dx, y = t.y + dy
            if content.solid[Int(u.tile(2, x, y))] { u.setTile(2, x, y, 0) }
            if content.water[Int(u.tile(0, x, y))] { u.setTile(0, x, y, content.tid("cave_floor")) }
        } }
        u.setTile(2, t.x, t.y, content.tid("stairs_up"))
    }

    func unlinkStairs(at t: TilePos) {
        let u = underworld()
        if u.tile(2, t.x, t.y) == content.tid("stairs_up") { u.setTile(2, t.x, t.y, 0) }
    }

    // MARK: storeys above the surface

    /// The n-th storey above the surface (created on first use, in the same store as the rest of the world).
    /// Asking for a storey makes no storeys under it and reads nothing: storey 900 is as cheap as storey 1.
    public func storeyWorld(_ n: Int) -> OpenWorld {
        if let w = storeys[n] { return w }
        let w = OpenWorld(seed: world.seed, budget: world.budget, depth: OpenWorld.storeyBase + n)
        w.diskLimitBytes = world.diskLimitBytes
        if let st = world.store { w.open(store: st) }
        w.overlay = { [unowned self] ch in self.stampTowers(ch, storey: n); if n == SkyTune.storey { self.stampSky(ch) } }
        w.onChunkChanged.append { [unowned self] _, _ in self.noteStorey(n) }
        storeys[n] = w
        return w
    }

    /// Let go of storey layers nobody built on that are far from storey `here` (they are made again, the
    /// same, from the towers when next needed). Storeys someone built on are kept: they hold changes.
    /// Returns how many were let go.
    @discardableResult public func trimStoreys(around here: Int, span: Int = 8) -> Int {
        let built = storeySet
        var gone = 0
        for n in storeys.keys.sorted() where abs(n - here) > span && Society.insertion(built, n) != nil {
            storeys[n] = nil; gone += 1
        }
        return gone
    }

    /// Something was built or changed on storey n: it is one of the storeys that exist.
    func noteStorey(_ n: Int) {
        var set = storeySet
        guard let i = Society.insertion(set, n) else { return }
        set.insert(n, at: i)
        realm.storeySet = set
        realm.storeyTop = max(realm.storeyTop ?? 0, n)
    }

    /// Where `n` goes in a sorted list, or nil when it is there already (binary search).
    static func insertion(_ a: [Int], _ n: Int) -> Int? {
        var lo = 0, hi = a.count
        while lo < hi { let m = (lo + hi) / 2; if a[m] < n { lo = m + 1 } else { hi = m } }
        return lo < a.count && a[lo] == n ? nil : lo
    }

    /// The storeys something was built on, sorted. Saves from before v2.6 only knew the highest storey:
    /// for them it is every storey up to that one (they are all low), remembered from then on.
    var storeySet: [Int] {
        if let s = realm.storeySet { return s }
        let top = realm.storeyTop ?? 0
        return top > 0 ? Array(1...top) : []
    }

    /// Every storey something was built or changed on, for saving and world laws. Its length is the
    /// number of such storeys, not the height of the tallest building.
    public func builtStoreys() -> [Int] { storeySet }

    /// Storeys to draw or collide with around storey `n` (n = 0 is the ground): the built ones and those a
    /// standing tower reaches, no further than `span` away. Never more than 2 x span + 1 entries.
    public func storeysNear(_ n: Int, span: Int) -> [Int] {
        let lo = max(1, n - span), hi = n + span
        guard hi >= lo else { return [] }
        let set = storeySet
        let top = (realm.standing ?? []).map { $0.levels - 1 }.max() ?? 0
        var out: [Int] = []
        for k in lo...hi where k <= top || Society.insertion(set, k) == nil { out.append(k) }
        return out
    }

    /// True when a standing tower has a floor in this chunk of storey n (so there is something to draw
    /// there although nobody has touched the chunk).
    public func towerCovers(storey n: Int, cx: Int, cy: Int) -> Bool {
        for t in realm.standing ?? [] where n >= 1 && n < t.levels {
            if t.x + t.w > cx * 32 && t.x < cx * 32 + 32 && t.y + t.d > cy * 32 && t.y < cy * 32 + 32 { return true }
        }
        return false
    }

    /// The stair of a tower between level k and level k + 1 (alternating sides, as raiseHouse lays them).
    static func towerStair(_ t: StandingTower, level k: Int) -> TilePos { TilePos(t.x + (k % 2 == 0 ? 2 : t.w - 3), t.y + t.d - 2) }

    /// A fresh chunk of storey n gets the floors of the towers standing there: walls round the edge, a
    /// floor inside, two beds, the stair down from below and (unless it is the top) the stair up. The same
    /// rooms raiseHouse builds, made from the tower when the chunk is first needed. Changing anything
    /// stores the chunk like any other, so what was changed stays changed.
    /// Footprints of standing towers, by tower.
    static let towerSizes: [(w: Int, d: Int)] = [(12, 10), (14, 12), (16, 12), (18, 14)]
    /// What a standing tower's storeys are made of, by tower: stone, concrete or brick, with glass windows.
    static func towerFacade(_ tower: Int) -> (wall: String, window: String) {
        [("wall_stone", "wall_glass"), ("wall_concrete", "wall_glass"), ("wall_brick", "wall_glass")][tower % 3]
    }

    func stampTowers(_ ch: Chunk, storey n: Int) {
        guard n >= 1, let list = realm.standing, !list.isEmpty else { return }
        let floor = content.tid("wood_floor"), bed = content.tid("bed")
        let up = content.tid("stairs_up"), down = content.tid("stairs_down")
        let bx = ch.cx * 32, by = ch.cy * 32
        for t in list where n < t.levels && t.x + t.w > bx && t.x < bx + 32 && t.y + t.d > by && t.y < by + 32 {
            func put(_ l: Int, _ x: Int, _ y: Int, _ id: UInt8) {
                guard x >= bx, x < bx + 32, y >= by, y < by + 32 else { return }
                ch.layers[l][OpenWorld.idx(x, y)] = id
            }
            let face = Society.towerFacade(t.tower)
            let wall = content.tid(face.wall), window = content.tid(face.window)
            for y in 0..<t.d { for x in 0..<t.w {
                put(0, t.x + x, t.y + y, floor)
                let corner = (x == 0 || x == t.w - 1) && (y == 0 || y == t.d - 1)
                if x == 0 || y == 0 || x == t.w - 1 || y == t.d - 1 { put(2, t.x + x, t.y + y, !corner && (x + y) % 3 == 1 ? window : wall) }
            } }
            // flats along the north wall: a bed in every other tile, a wall between each pair of homes
            for x in stride(from: 1, to: t.w - 1, by: 2) { put(2, t.x + x, t.y + 1, bed) }
            for x in stride(from: 4, to: t.w - 2, by: 4) { put(2, t.x + x, t.y + 2, wall) }
            let from = Society.towerStair(t, level: n - 1)
            put(2, from.x, from.y, down)
            if n + 1 < t.levels { let st = Society.towerStair(t, level: n); put(2, st.x, st.y, up) }
        }
    }

    /// How tall each standing tower is now, from the tower itself (the regional layer owns that).
    /// A storey chunk nobody changed is made again from the new height when it is next needed.
    func refreshStanding(_ c: Civ) {
        guard var list = realm.standing, !list.isEmpty else { return }
        var changed = false
        for i in list.indices {
            guard let t = c.towerIndex.towers[list[i].tower] else { continue }
            let n = max(1, t.floors.filter { $0.stage == .inUse }.count)
            if n != list[i].levels {
                let was = list[i].levels
                list[i].levels = n; changed = true
                // the storeys between the old top and the new one, where they are in memory and unchanged
                for k in max(1, min(was, n) - 1)...max(was, n) { if let w = storeys[k] {
                    for cy in (list[i].y >> 5)...((list[i].y + list[i].d - 1) >> 5) { for cx in (list[i].x >> 5)...((list[i].x + list[i].w - 1) >> 5) where w.loaded(cx, cy) && w.storedSize(MP.chunkKey(cx, cy)) == 0 { w.revertChunk(cx, cy) } }
                } }
            }
        }
        if changed { realm.standing = list; realm.storeyTop = max(realm.storeyTop ?? 0, (list.map { $0.levels }.max() ?? 1) - 1) }
    }

    /// The layer with this depth: 0 surface, 1 underground, 100 + n storey n.
    public func layer(_ depth: Int) -> OpenWorld { depth == 0 ? world : (depth == 1 ? underworld() : storeyWorld(depth - OpenWorld.storeyBase)) }

    /// What holds a floor up: a wall, a column or a stair on the level below, within three tiles of it
    /// (a floor may reach out that far from what carries it, no further).
    public func supported(_ t: TilePos, onStorey n: Int) -> Bool {
        let below = n == 1 ? world : storeyWorld(n - 1)
        let up = content.tid("stairs_up")
        for dy in -3...3 { for dx in -3...3 {
            let x = t.x + dx, y = t.y + dy
            // only what people built carries a floor: walls and stairs, not trees or boulders
            let o = Int(below.tile(2, x, y)), s = Int(below.tile(1, x, y))
            let tiles = content.tiles
            let built = { (id: Int) -> Bool in tiles[id]?.built == true }
            if (o != 0 && ((content.solid[o] && built(o)) || o == Int(up))) || (s != 0 && content.solid[s] && built(s)) { return true }
        } }
        return false
    }

    /// A house of `storeys` levels (the ground floor and n - 1 above it), w x d tiles: on every level stone walls
    /// round the edge with a door on the ground, a floor inside, beds, and stairs that alternate sides going up.
    /// Every floor stands on the walls below it, by the same rules as anything the player builds.
    /// Returns the stair positions, level by level.
    @discardableResult public func raiseHouse(at o: TilePos, storeys: Int, w: Int = 7, d: Int = 7) -> [TilePos] {
        var stairs: [TilePos] = []
        let wall = content.tid("wall_stone"), floor = content.tid("wood_floor"), bed = content.tid("bed"), door = content.tid("door_wood")
        for level in 0..<max(1, storeys) {
            let lw = level == 0 ? world : storeyWorld(level)
            for y in 0..<d { for x in 0..<w {
                let t = TilePos(o.x + x, o.y + y)
                if level > 0 && lw.tile(0, t.x, t.y) == 0 { lw.setTile(0, t.x, t.y, floor) }
                else if level == 0 { lw.setTile(0, t.x, t.y, floor); lw.setTile(3, t.x, t.y, 0) }
                let edge = x == 0 || y == 0 || x == w - 1 || y == d - 1
                if edge { lw.setTile(2, t.x, t.y, level == 0 && x == w / 2 && y == d - 1 ? door : wall) }
                else if lw.tile(2, t.x, t.y) != content.tid("stairs_down") { lw.setTile(2, t.x, t.y, 0) }
            } }
            lw.setTile(2, o.x + 1, o.y + 1, bed); lw.setTile(2, o.x + w - 2, o.y + 1, bed)
            if level + 1 < storeys {
                let st = TilePos(o.x + (level % 2 == 0 ? 2 : w - 3), o.y + d - 2)
                lw.setTile(2, st.x, st.y, content.tid("stairs_up"))
                linkUp(at: st, from: lw)
                stairs.append(st)
            }
        }
        return stairs
    }

    /// A town adds a storey to its lowest finished house: floor over the whole footprint, walls like the
    /// ground floor's, two beds, and a stair inside from the level below. Costs the town 12 wood and 6 stone.
    /// The floor stands on the walls below by the same rule as anything the player builds.
    func addStorey(_ s: Settlement, _ houses: [Building]) -> Bool {
        guard s.wood >= 12, s.stone >= 6,
              let b = houses.filter({ $0.done && $0.w >= 5 && $0.h >= 5 }).min(by: { ($0.levels ?? 1, $0.id) < ($1.levels ?? 1, $1.id) }) else { return false }
        let n = b.levels ?? 1                                   // the new storey's number
        let below = n == 1 ? world : storeyWorld(n - 1), up = storeyWorld(n)
        let o = TilePos(b.x, b.y)
        var wall = world.tile(2, o.x, o.y)
        if wall == 0 || !content.solid[Int(wall)] { wall = content.tid("wall_wood") }
        let floor = content.tid("wood_floor"), bed = content.tid("bed")
        // the stair: an inside corner, alternating so flights do not stack on each other
        let st = TilePos(o.x + (n % 2 == 1 ? 1 : b.w - 2), o.y + b.h / 2)
        if below.tile(2, st.x, st.y) != 0 && below.tile(2, st.x, st.y) != bed { return false }
        s.wood -= 12; s.stone -= 6
        for dy in 0..<b.h { for dx in 0..<b.w {
            let t = TilePos(o.x + dx, o.y + dy)
            up.setTile(0, t.x, t.y, floor)
            if dx == 0 || dy == 0 || dx == b.w - 1 || dy == b.h - 1 { up.setTile(2, t.x, t.y, wall) }
        } }
        below.setTile(2, st.x, st.y, content.tid("stairs_up"))
        linkUp(at: st, from: below)
        up.setTile(2, o.x + b.w - 2, o.y + 1, bed); up.setTile(2, o.x + 1, o.y + b.h - 2, bed)
        b.levels = n + 1; b.cap += 4
        emit("storey_added", [s.name(zh: zh), "\(n + 1)"], o.center)
        return true
    }

    /// After something was taken down on a level: floors above that nothing carries any more come down
    /// (with what stood on them), level after level. Returns how many floor tiles fell.
    @discardableResult func settleStoreys(above w: OpenWorld, around t: TilePos) -> Int {
        var fell = 0
        var n = w.storey + 1
        var x0 = t.x - 3, x1 = t.x + 3, y0 = t.y - 3, y1 = t.y + 3
        while n <= (realm.storeyTop ?? 0) {
            let up = storeyWorld(n)
            var gone: [TilePos] = []
            for y in y0...y1 { for x in x0...x1 where up.tile(0, x, y) != 0 && !supported(TilePos(x, y), onStorey: n) { gone.append(TilePos(x, y)) } }
            if gone.isEmpty { break }
            for g in gone { for l in 0..<4 { up.setTile(l, g.x, g.y, 0) } }
            fell += gone.count
            x0 -= 3; x1 += 3; y0 -= 3; y1 += 3; n += 1
        }
        return fell
    }

    /// A stair going up has its landing on the storey above: a floor round it and a stair down.
    func linkUp(at t: TilePos, from w: OpenWorld) {
        let n = w.storey + 1
        let up = storeyWorld(n)
        let floor = content.tid("wood_floor")
        for dy in -1...1 { for dx in -1...1 where up.tile(0, t.x + dx, t.y + dy) == 0 { up.setTile(0, t.x + dx, t.y + dy, floor) } }
        up.setTile(2, t.x, t.y, content.tid("stairs_down"))
        realm.storeyTop = max(realm.storeyTop ?? 0, n)
    }

    /// Use the stairs under the player's feet (or beside them). Returns the new depth and position.
    /// Down from the surface goes underground; up from the underground comes back; up from the surface or
    /// any storey goes one storey higher, down from a storey one lower.
    public func useStairs(at pos: Vec2) -> (depth: Int, pos: Vec2)? {
        let depth = realm.player.depth ?? 0
        let w = layer(depth)
        let down = content.tid("stairs_down"), up = content.tid("stairs_up")
        for d in [TilePos(0, 0), TilePos(1, 0), TilePos(-1, 0), TilePos(0, 1), TilePos(0, -1)] {
            let t = pos.tile + d
            let id = w.tile(2, t.x, t.y)
            if depth == 0 && id == down { linkStairs(at: t); realm.player.depth = 1; return (1, underworld().findFree(near: t + TilePos(0, 1), maxR: 3).center) }
            if depth == 1 && id == up {
                // coming up: the surface stair may have been removed or built over; come out beside where it was
                realm.player.depth = 0
                return (0, world.findFree(near: t + TilePos(0, 1), maxR: 12).center)
            }
            if depth != 1 && id == up {
                linkUp(at: t, from: w)
                let n = w.storey + 1
                realm.player.depth = OpenWorld.storeyBase + n
                return (OpenWorld.storeyBase + n, storeyWorld(n).findFree(near: t + TilePos(0, 1), maxR: 3).center)
            }
            if w.storey == SkyTune.storey && id == down && world.gen.skyIsland(t.x >> 5, t.y >> 5) != nil {
                // the sky city's way down: a long stair (a lift, really) straight to the ground below
                realm.player.depth = 0
                return (0, world.findFree(near: t + TilePos(0, 1), maxR: 24).center)
            }
            if w.storey > 0 && id == down {
                let n = w.storey - 1
                let target = n == 0 ? world : storeyWorld(n)
                realm.player.depth = n == 0 ? 0 : OpenWorld.storeyBase + n
                return (realm.player.depth!, target.findFree(near: t + TilePos(0, 1), maxR: 12).center)
            }
        }
        return nil
    }

    /// A way back that never depends on an entrance still existing: climb out
    /// where you stand. A new stair pair is cut at the nearest ground that can take it.
    public func climbOut(from pos: Vec2) -> Vec2 {
        guard (realm.player.depth ?? 0) > 0 else { return pos }
        let u = underworld()
        var top = world.findFree(near: pos.tile, maxR: 40)
        if world.blocked(top.x, top.y) { top = spawnPoint(near: pos).tile }
        if world.tile(2, top.x, top.y) == 0 && !content.water[Int(world.tile(0, top.x, top.y))] {
            world.setTile(2, top.x, top.y, content.tid("stairs_down"))
            linkStairs(at: top)
        }
        _ = u
        realm.player.depth = 0
        return world.findFree(near: top + TilePos(0, 1), maxR: 6).center
    }

    /// Mine the rock or ore in front of the player underground (or an ore vein on the surface).
    public func playerDig(at t: TilePos, in w: OpenWorld? = nil) -> (good: String, amount: Double)? {
        let w = w ?? world
        let key = content.tile(w.tile(2, t.x, t.y))?.key ?? ""
        let yield: [String: (String, Double)] = ["cave_wall": ("stone", 1), "rock": ("stone", 3), "ore_iron": ("iron_ore", 2), "ore_copper": ("iron_ore", 1),
                                                 "ore_moon": ("moon_ore", 1), "ore_gold": ("gold_ore", 1)]
        guard let y = yield[key] else { return nil }
        w.setTile(2, t.x, t.y, 0)
        carry(y.0, y.1)
        return y
    }

    /// Chests in underground ruins: materials, and a recipe's worth of finished goods.
    public func playerOpenRuin(at t: TilePos) -> [String: Double]? {
        let u = underworld()
        guard u.tile(2, t.x, t.y) == T["chest"], u.gen.isUnderRuin(t.x >> 5, t.y >> 5) || u.gen.isUnderCity(t.x >> 5, t.y >> 5) else { return nil }
        u.setTile(2, t.x, t.y, content.tid("altar_pure"))
        var r = RNG(seed: world.seed &+ t.x &* 131 &+ t.y)
        var loot: [String: Double] = ["iron": Double(r.int(3, 6)), "parts": Double(r.int(2, 4))]
        loot[["tools", "weapons", "armor"][r.index(3)]] = 2
        if r.unit() < 0.5 { loot["moonsteel"] = 1 }
        for (g, n) in loot { carry(g, n) }
        return loot
    }
}
