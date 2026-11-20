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

extension Civ {
    /// The open lands the nations below have made: one round each of their cities, `dug` tiles across.
    public func underlands() -> [UnderlandZone] {
        cities.values.compactMap { c -> UnderlandZone? in
            guard c.under == true || c.sea == true, let (cx, cy) = c.underAt, polities[c.nation]?.status == .active else { return nil }
            return UnderlandZone(cx: cx, cy: cy, r: c.dug / 32, sea: c.sea == true, nation: c.nation)
        }.sorted { ($0.cx, $0.cy, $0.nation) < ($1.cx, $1.cy, $1.nation) }
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
    public func underlandPlan(_ cx: Int, _ cy: Int, sea: Bool, home: Bool, inZone: (Int, Int) -> Bool) -> UnderlandPlan {
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
        var r = RNG(seed: Int(MP.h2(seed &+ 9191, cx, cy)))
        let kind = Int(MP.h2(seed &+ 9192, cx, cy) % 100)
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
        let glassy = sea || seaAbove(cx * 32 + 16, cy * 32 + 16)
        let sides: [(Int, Int, (Int) -> (Int, Int))] = [(0, -1, { ($0, 0) }), (0, 1, { ($0, 31) }), (-1, 0, { (0, $0) }), (1, 0, { (31, $0) })]
        for (dx, dy, at) in sides {
            let shut = !inZone(cx + dx, cy + dy)
            for k in 0..<32 {
                let (x, y) = at(k)
                if shut && glassy { ob[i(x, y)] = glass; de[i(x, y)] = 0; st[i(x, y)] = 0 } else if !shut { open[i(x, y)] = true }
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

    /// The underland a chunk of the underground belongs to, if any.
    public func underland(_ cx: Int, _ cy: Int) -> UnderlandZone? {
        underlandZones().first { $0.contains(cx, cy) && !(!$0.sea && $0.cx == cx && $0.cy == cy && world.gen.isUnderCity(cx, cy)) }
    }

    func inAnyUnderland(_ cx: Int, _ cy: Int) -> Bool { underlandZones().contains { $0.contains(cx, cy) } }

    func underlandPlan(_ cx: Int, _ cy: Int, _ z: UnderlandZone) -> UnderlandPlan {
        world.gen.underlandPlan(cx, cy, sea: z.sea, home: z.cx == cx && z.cy == cy, inZone: { [unowned self] x, y in self.inAnyUnderland(x, y) })
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
            if Generator.naturalCave(g, st, ob, de) {
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
    public func underSky(at t: TilePos) -> (light: Double, sea: Bool)? {
        guard let z = underlandZones().first(where: { $0.contains(t.x >> 5, t.y >> 5) }) else { return nil }
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
