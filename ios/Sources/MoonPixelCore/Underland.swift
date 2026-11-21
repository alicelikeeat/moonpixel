import Foundation

// The underlands: what the nations below the world make of it.
//
// * Every city of an underground nation, and every city of a sea-floor nation, keeps digging outward
//   (`dug`, in tiles from its centre; UnderTune). Everything within that reach is no longer cave: it is
//   open land like the surface, with grass, roads in a grid, houses, farms and parks, and lamps for a sky.
// * The sea-floor nations make theirs in the underground under their city, entered by a stairway in the
//   pearl dome on the sea floor: sand, coral houses, kelp farms, pearl lamps, and glass walls on every side
//   that still meets the flooded rock. An underground nation digging under the sea walls it out with glass
//   too.
// * Down there the light is the nations' own: an artificial day, bright from six in the morning to nine at
//   night and dimmed between (Society.underSky).
// * A chunk is made into underland when it is first made, if it is already within reach; chunks already in
//   use are carved as the reach grows (Society.digUnderground). Only cave is replaced: rock, ore, cave
//   floor and flooded caverns. Whatever anyone built there stays.

public struct UnderlandZone: Equatable {
    public let cx: Int, cy: Int
    /// The level down it is on: 1 the underground, 2 the level under it, and so on (DeepTune).
    public var level = 1
    /// Reach in chunks from the centre chunk.
    public let r: Double
    /// A sea-floor nation's (sand, coral and pearl), or an underground nation's (grass, brick and lamps).
    public let sea: Bool
    public let nation: Int
    public func contains(_ x: Int, _ y: Int) -> Bool {
        let dx = Double(x - cx), dy = Double(y - cy)
        return dx * dx + dy * dy <= r * r + 0.01
    }
}

/// Digging down: the cities below do not only widen their underland, they build down into the rock under it.
/// Every `levelStep` tiles a city has dug outward, it has dug one level deeper (to B8 at most); each level is an
/// underland of its own round the same middle, a little narrower than the one above it (a city like an
/// upturned pyramid), joined by a stairway down from each plaza to the next.
public enum DeepTune {
    public static let levelStep = 40.0
    /// Tiles narrower each level down.
    public static let narrower = 40.0
    /// Where the stairway down from level k is in its city's middle chunk (and the one up on level k + 1).
    public static func stairDown(_ level: Int) -> (Int, Int) { level % 2 == 1 ? (19, 19) : (13, 19) }
}

extension Civ {
    /// The open lands the nations below have made: one round each of their cities, `dug` tiles across.
    public func underlands() -> [UnderlandZone] { underlands(level: 1) }

    /// The underlands on a level down (1 the underground; 2 ... the levels the cities have dug below it).
    public func underlands(level: Int) -> [UnderlandZone] {
        cities.values.compactMap { c -> UnderlandZone? in
            guard c.under == true || c.sea == true, let (cx, cy) = c.underAt, polities[c.nation]?.status == .active else { return nil }
            if level == 1 { return UnderlandZone(cx: cx, cy: cy, r: c.dug / 32, sea: c.sea == true, nation: c.nation) }
            guard level <= Civ.levelsDown(c) else { return nil }
            let r = max(1, (c.dug - Double(level - 1) * DeepTune.narrower) / 32)
            return UnderlandZone(cx: cx, cy: cy, level: level, r: r, sea: c.sea == true, nation: c.nation)
        }.sorted { ($0.cx, $0.cy, $0.nation) < ($1.cx, $1.cy, $1.nation) }
    }

    /// How many levels down a city of the nations below has built (1: only its underland).
    public static func levelsDown(_ c: CivCity) -> Int {
        guard c.under == true || c.sea == true else { return 0 }
        return max(1, min(MP.deepest, 1 + Int(((c.dug - 32) / DeepTune.levelStep).rounded(.down))))
    }
}

public struct UnderlandPlan {
    /// The four layers the chunk should have (ground, surface, objects, decoration).
    public var layers: [[UInt8]]
    /// Tiles on the chunk's edge that should be open now (a wall of glass stood there while it was the edge).
    public var openEdge: [Bool]
}

extension Generator {
    /// What a chunk of underland looks like. `inZone` says which chunks round it are underland too (their
    /// sides get no wall); `home` is the centre chunk of a city (a plaza with its stairway).
    public func underlandPlan(_ cx: Int, _ cy: Int, sea: Bool, home: Bool, rim: UInt8? = nil, level: Int = 1, down: Bool = false, inZone: (Int, Int) -> Bool) -> UnderlandPlan {
        let c = Content.shared
        let ground = sea ? c.tid("sand") : c.tid("grass")
        let road = c.tid("cobble_road"), plaza = sea ? c.tid("sand") : c.tid("stone_floor")
        let glass = c.tid("wall_glass")
        let houseWall = sea ? c.tid("coral_wall") : c.tid("wall_brick"), houseWall2 = sea ? c.tid("pearl_dome") : c.tid("wall_wood")
        let lamp = sea ? c.tid("pearl_lamp") : c.tid("lamp_on")
        let floor = sea ? c.tid("sand") : c.tid("wood_floor")
        let door = c.tid("door_wood")
        var g = [UInt8](repeating: ground, count: MP.chunkArea), st = [UInt8](repeating: 0, count: MP.chunkArea), ob = st, de = st
        var open = [Bool](repeating: false, count: MP.chunkArea)
        // (each level down is laid out afresh: the same city, different streets)
        var r = RNG(seed: Int(MP.h2(seed &+ 9191 &+ (level - 1) &* 7919, cx, cy)))
        let kind = Int(MP.h2(seed &+ 9192 &+ (level - 1) &* 7919, cx, cy) % 100)
        @inline(__always) func i(_ x: Int, _ y: Int) -> Int { y * 32 + x }
        let isRoad: (Int, Int) -> Bool = { x, y in x == 15 || x == 16 || y == 15 || y == 16 }
        // what fills each quarter (between the roads)
        let quarters = [(1, 1), (18, 1), (1, 18), (18, 18)]          // top-left corners of 13 x 13 quarters
        if home {
            // the city's plaza: paving, a statue or a coral, a well, stalls, lamps; the stairway stays clear
            for y in 6...25 { for x in 6...25 { g[i(x, y)] = plaza } }
            ob[i(11, 11)] = sea ? c.tid("coral") : c.tid("statue")
            ob[i(20, 11)] = c.tid("well")
            for (x, y) in [(11, 20), (20, 20)] { ob[i(x, y)] = c.tid("market_stall") }
            for (x, y) in [(8, 8), (23, 8), (8, 23), (23, 23)] { ob[i(x, y)] = lamp }
            if sea { for (x, y) in [(7, 12), (24, 12), (12, 24), (19, 7)] { de[i(x, y)] = c.tid("kelp") } }
            // the stairways: up from a deep level (where the one above comes down), down to the next
            if level > 1 { let (x, y) = DeepTune.stairDown(level - 1); ob[i(x, y)] = c.tid("stairs_up"); de[i(x, y)] = 0 }
            if down { let (x, y) = DeepTune.stairDown(level); ob[i(x, y)] = c.tid("stairs_down"); de[i(x, y)] = 0 }
        } else if kind < 50 {
            // town: a house in each quarter, its door on the road, a bed and a table inside, flowers by it
            for (qx, qy) in quarters {
                let w = 6 + r.index(3), h = 5 + r.index(2)
                let bx = qx + 2 + r.index(13 - w - 3), by = qy + 2 + r.index(13 - h - 3)
                let mat = r.unit() < 0.5 ? houseWall : houseWall2
                for y in by..<(by + h) { for x in bx..<(bx + w) {
                    g[i(x, y)] = floor
                    let edge = x == bx || x == bx + w - 1 || y == by || y == by + h - 1
                    ob[i(x, y)] = edge ? mat : 0
                } }
                // the door faces the nearer road
                let dx = bx + w / 2, dy = qy < 15 ? by + h - 1 : by
                ob[i(dx, dy)] = door
                ob[i(bx + 1, by + 1)] = c.tid("bed")
                ob[i(bx + w - 2, by + 1)] = r.unit() < 0.5 ? c.tid("table") : c.tid("bookshelf")
                for _ in 0..<4 {
                    let x = qx + r.index(13), y = qy + r.index(13)
                    if ob[i(x, y)] == 0 && g[i(x, y)] == ground { de[i(x, y)] = sea ? c.tid("kelp") : [c.tid("flower_red"), c.tid("flower_yellow"), c.tid("flower_blue")][r.index(3)] }
                }
            }
        } else if kind < 80 {
            // farms: fields of wheat behind a fence with a gate on the road (kelp beds on the sea floor)
            for (qx, qy) in quarters {
                for y in qy..<(qy + 13) { for x in qx..<(qx + 13) {
                    let edge = x == qx || x == qx + 12 || y == qy || y == qy + 12
                    if sea { if !edge { de[i(x, y)] = c.tid("kelp") } ; continue }
                    if edge { ob[i(x, y)] = c.tid("fence") } else { g[i(x, y)] = c.tid("farmland"); ob[i(x, y)] = c.tid("wheat_2") }
                } }
                if !sea { ob[i(qx + 6, qy < 15 ? qy + 12 : qy)] = c.tid("fence_gate") }
            }
        } else {
            // a park: trees, bushes and flowers (coral gardens and shells on the sea floor)
            for (qx, qy) in quarters { for y in qy..<(qy + 13) { for x in qx..<(qx + 13) {
                let u = r.unit()
                if sea {
                    if u < 0.06 { ob[i(x, y)] = c.tid("coral") } else if u < 0.16 { de[i(x, y)] = c.tid("kelp") } else if u < 0.19 { de[i(x, y)] = c.tid("shell") }
                } else {
                    if u < 0.07 { ob[i(x, y)] = [c.tid("tree_oak"), c.tid("tree_willow"), c.tid("tree_pine")][r.index(3)] }
                    else if u < 0.09 { ob[i(x, y)] = c.tid("bush") }
                    else if u < 0.17 { de[i(x, y)] = [c.tid("flower_red"), c.tid("flower_yellow"), c.tid("flower_blue"), c.tid("tall_grass")][r.index(4)] }
                }
            } } }
        }
        // the roads, and lamps at the crossing (the light of this sky)
        for y in 0..<32 { for x in 0..<32 where isRoad(x, y) && !(home && x >= 6 && x <= 25 && y >= 6 && y <= 25) {
            st[i(x, y)] = road; ob[i(x, y)] = 0; de[i(x, y)] = 0
            if g[i(x, y)] != ground { g[i(x, y)] = ground }
        } }
        if !home { for (x, y) in [(14, 14), (17, 14), (14, 17), (17, 17)] { ob[i(x, y)] = lamp; de[i(x, y)] = 0 } }
        // the edge: glass where it still meets the flooded rock (always on the sea floor's), open towards
        // the rest of the underland
        let glassy = rim != nil || sea || seaAbove(cx * 32 + 16, cy * 32 + 16)
        let edgeTile = rim ?? glass
        let sides: [(Int, Int, (Int) -> (Int, Int))] = [(0, -1, { ($0, 0) }), (0, 1, { ($0, 31) }), (-1, 0, { (0, $0) }), (1, 0, { (31, $0) })]
        for (dx, dy, at) in sides {
            let shut = !inZone(cx + dx, cy + dy)
            for k in 0..<32 {
                let (x, y) = at(k)
                if shut && glassy { ob[i(x, y)] = edgeTile; de[i(x, y)] = 0; st[i(x, y)] = 0 } else if !shut { open[i(x, y)] = true }
            }
        }
        return UnderlandPlan(layers: [g, st, ob, de], openEdge: open)
    }

    /// Is this tile still the cave as it was made (so the underland may replace it)?
    static func naturalCave(_ g: UInt8, _ st: UInt8, _ ob: UInt8, _ de: UInt8) -> Bool {
        let c = Content.shared
        guard st == 0 else { return false }
        guard g == 0 || g == c.tid("cave_floor") || g == c.tid("cave_water") else { return false }
        guard de == 0 || de == c.tid("mushroom") else { return false }
        if ob == 0 { return true }
        return ["cave_wall", "ore_iron", "ore_copper", "ore_moon", "ore_gold"].contains(c.tile(ob)?.key ?? "")
    }
}

extension Society {
    /// The underlands of the nations below (empty until they are known).
    public func underlandZones() -> [UnderlandZone] {
        guard let c = realm.civBox, c.underNations else { return [] }
        let stamp = c.day &* 1_000_003 &+ c.cities.count
        if let k = underlandCache, k.stamp == stamp { return k.zones }
        let z = c.underlands()
        underlandCache = (stamp, z)
        return z
    }

    /// The underlands of a level down (1: the underground; 2 ... the deep levels).
    public func underlandZones(level: Int) -> [UnderlandZone] {
        if level <= 1 { return underlandZones() }
        guard let c = realm.civBox, c.underNations else { return [] }
        let stamp = c.day &* 1_000_003 &+ c.cities.count
        if let k = deepCache[level], k.stamp == stamp { return k.zones }
        let z = c.underlands(level: level)
        deepCache[level] = (stamp, z)
        return z
    }

    /// The underland a chunk of the underground (or of a deep level) belongs to, if any.
    public func underland(_ cx: Int, _ cy: Int, level: Int = 1) -> UnderlandZone? {
        if level > 1 { return underlandZones(level: level).first { $0.contains(cx, cy) } }
        return underlandZones().first { $0.contains(cx, cy) && !(!$0.sea && $0.cx == cx && $0.cy == cy && world.gen.isUnderCity(cx, cy)) }
    }

    func inAnyUnderland(_ cx: Int, _ cy: Int, level: Int = 1) -> Bool { underlandZones(level: level).contains { $0.contains(cx, cy) } }

    /// Has the city whose middle is this chunk built a level under `level`?
    func goesDeeper(_ z: UnderlandZone) -> Bool {
        z.level < MP.deepest && underlandZones(level: z.level + 1).contains { $0.cx == z.cx && $0.cy == z.cy }
    }

    func underlandPlan(_ cx: Int, _ cy: Int, _ z: UnderlandZone) -> UnderlandPlan {
        let home = z.cx == cx && z.cy == cy
        return world.gen.underlandPlan(cx, cy, sea: z.sea, home: home, level: z.level, down: home && goesDeeper(z),
                                       inZone: { [unowned self] x, y in self.inAnyUnderland(x, y, level: z.level) })
    }

    /// A deep level (depth 2 ... 8, under the underground; created on first use, in the same store).
    public func deepWorld(_ depth: Int) -> OpenWorld {
        if let w = deeps[depth] { return w }
        let w = OpenWorld(seed: world.seed, budget: world.budget, depth: depth)
        w.diskLimitBytes = world.diskLimitBytes
        if let st = world.store { w.open(store: st) }
        w.overlay = { [unowned self] ch in self.stampDeep(ch, level: depth) }
        deeps[depth] = w
        return w
    }

    /// A chunk of a deep level made for the first time: if a city has built down to it there, it is made so.
    func stampDeep(_ ch: Chunk, level: Int) {
        guard let z = underland(ch.cx, ch.cy, level: level) else { return }
        let p = underlandPlan(ch.cx, ch.cy, z)
        for k in 0..<MP.chunkArea where Generator.naturalCave(ch.layers[0][k], ch.layers[1][k], ch.layers[2][k], ch.layers[3][k]) || isDeepRock(ch.layers[0][k], ch.layers[2][k]) {
            for l in 0..<4 { ch.layers[l][k] = p.layers[l][k] }
        }
    }

    /// The deep levels' own rock (basalt floors, pools of lava) counts as untouched cave too.
    func isDeepRock(_ g: UInt8, _ ob: UInt8) -> Bool {
        (g == content.tid("basalt") || g == content.tid("lava")) && (ob == 0 || Generator.naturalCave(content.tid("cave_floor"), 0, ob, 0))
    }

    /// Near the traveller on a deep level, the cities' building down is real there too: chunks in use within
    /// their reach are carved, and a city that has gone a level deeper gets its stairway down in its plaza.
    @discardableResult public func digDeep(around t: TilePos, level: Int, reach: Int = 160) -> Int {
        guard level >= 1, level <= MP.deepest, let c = realm.civBox, c.underNations else { return 0 }
        let zones = underlandZones(level: level)
        let u = layer(level)
        let pcx = t.x >> 5, pcy = t.y >> 5, rc = max(1, reach / 32)
        var sig = pcx &* 73_856_093 ^ pcy &* 19_349_663 &+ level
        for z in zones where abs(z.cx - pcx) <= rc + Int(z.r) + 1 && abs(z.cy - pcy) <= rc + Int(z.r) + 1 { sig = sig &* 31 &+ Int(z.r * 32) &+ z.cx &* 7 &+ z.cy &+ (goesDeeper(z) ? 1 : 0) }
        if deepDone[level] == sig { return 0 }
        deepDone[level] = sig
        var changed = 0
        for z in zones where abs(z.cx - pcx) <= rc + 1 && abs(z.cy - pcy) <= rc + 1 && goesDeeper(z) {
            // the stairway down in the plaza (unless something was built on its spot)
            let (x, y) = DeepTune.stairDown(level)
            let wx = z.cx * 32 + x, wy = z.cy * 32 + y
            if u.tile(2, wx, wy) == 0 { u.setTile(2, wx, wy, content.tid("stairs_down")); changed += 1 }
        }
        guard level > 1 else { return changed }
        for cy in (pcy - rc)...(pcy + rc) { for cx in (pcx - rc)...(pcx + rc) where u.touched(cx, cy) {
            guard let z = underland(cx, cy, level: level) else { continue }
            changed += carveUnderland(cx, cy, z, in: u)
        } }
        return changed
    }

    /// A chunk of the underground made for the first time: if it is within an underland, it is made so.
    func stampUnderland(_ ch: Chunk) {
        guard let z = underland(ch.cx, ch.cy) else { return }
        let p = underlandPlan(ch.cx, ch.cy, z)
        for k in 0..<MP.chunkArea where Generator.naturalCave(ch.layers[0][k], ch.layers[1][k], ch.layers[2][k], ch.layers[3][k]) {
            for l in 0..<4 { ch.layers[l][k] = p.layers[l][k] }
        }
    }

    /// Carve the underland into one chunk already in use (cave only; what anyone built stays). Returns the
    /// tiles changed.
    @discardableResult func carveUnderland(_ cx: Int, _ cy: Int, _ z: UnderlandZone, in u: OpenWorld) -> Int {
        let p = underlandPlan(cx, cy, z)
        let glass = content.tid("wall_glass")
        var n = 0
        for y in 0..<32 { for x in 0..<32 {
            let k = y * 32 + x, wx = cx * 32 + x, wy = cy * 32 + y
            let g = u.tile(0, wx, wy), st = u.tile(1, wx, wy), ob = u.tile(2, wx, wy), de = u.tile(3, wx, wy)
            if Generator.naturalCave(g, st, ob, de) || (z.level > 1 && isDeepRock(g, ob)) {
                for l in 0..<4 where u.tile(l, wx, wy) != p.layers[l][k] { u.setTile(l, wx, wy, p.layers[l][k]) }
                n += 1
            } else if p.openEdge[k] && ob == glass {
                // this was the edge of the underland; now it goes on: the wall comes down
                u.setTile(2, wx, wy, p.layers[2][k]); n += 1
            }
        } }
        return n
    }

    /// Down there, within an underland, the nations' own light: (brightness 0...1 of their artificial day,
    /// a sea-floor nation's). Nil anywhere else (the dark of the cave).
    public func underSky(at t: TilePos, level: Int = 1) -> (light: Double, sea: Bool)? {
        guard let z = underlandZones(level: level).first(where: { $0.contains(t.x >> 5, t.y >> 5) }) else { return nil }
        let h = world.hour
        // full from 6 to 21; an hour's fade either side; a night glow of 45 %
        let day: Double = h >= 6 && h < 21 ? 1 : (h >= 5 && h < 6 ? h - 5 : (h >= 21 && h < 22 ? 22 - h : 0))
        return (0.45 + 0.55 * day, z.sea)
    }
}

extension Society {
    /// The nearest city on the sea floor (its pearl dome holds the stairway down to its underland).
    public func nearestSeaCity(cx: Int, cy: Int, within r: Int = 64) -> TilePos? {
        var best: TilePos?, bd = Int.max
        for y in (cy - r)...(cy + r) { for x in (cx - r)...(cx + r) where world.gen.isSeaCity(x, y) {
            let d = (x - cx) * (x - cx) + (y - cy) * (y - cy)
            if d < bd { bd = d; best = TilePos(x * 32 + 16, y * 32 + 16) }
        } }
        return best
    }
}

extension Society {
    /// Where to arrive at a city of the civilisation layer: its town on the surface, the middle of its region,
    /// or, for a city underground or on the sea floor, its plaza below (`below` true).
    public func cityGate(_ id: Int) -> (tile: TilePos, below: Bool)? {
        let c = civ
        guard let city = c.cities[id] else { return nil }
        if (city.under == true || city.sea == true), let (cx, cy) = city.underAt {
            // an underground city of the old kind has its own streets; the stairway is in the middle
            let old = city.under == true && world.gen.isUnderCity(cx, cy)
            return (TilePos(cx * 32 + 16, cy * 32 + (old ? 18 : 19)), true)
        }
        if let d = city.detail, let t = settlements[d], !t.abandoned { return (t.center, false) }
        let rc = c.cfg.regionTiles
        return (TilePos(city.rx * rc + rc / 2, city.ry * rc + rc / 2), false)
    }

    /// A city's plaza on a level it has built down to (nil when it has not dug that deep).
    public func deepGate(_ id: Int, level: Int) -> TilePos? {
        guard let city = civ.cities[id], let (cx, cy) = city.underAt, level >= 2, level <= Civ.levelsDown(city) else { return nil }
        return TilePos(cx * 32 + 16, cy * 32 + 16)
    }

    /// Go below at once, to a tile of the underground (the traveller stands on the nearest free floor there).
    public func teleportBelow(to t: TilePos) -> Vec2 {
        let u = underworld()
        realm.player.depth = 1
        _ = digUnderground(around: t)
        let f = u.findFree(near: t, maxR: 24)
        if u.blocked(f.x, f.y) {
            // nowhere to stand: a small room is cleared
            for dy in -1...1 { for dx in -1...1 { u.setTile(2, t.x + dx, t.y + dy, 0); if content.water[Int(u.tile(0, t.x + dx, t.y + dy))] { u.setTile(0, t.x + dx, t.y + dy, content.tid("cave_floor")) } } }
            return t.center
        }
        return f.center
    }
}
