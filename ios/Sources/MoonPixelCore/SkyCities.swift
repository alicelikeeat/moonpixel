import Foundation

// Sky cities: islands of land floating high over the world.
//
// * One in every 18 x 18 chunks of the world (away from where the first villages are) has a sky city above it:
//   an island about five chunks across on storey 40 (SkyTune.storey), lying over whatever is below, sea or land.
// * The island is land as on the ground: grass, a grid of roads, houses, farms, parks and lamps (made the way
//   the underlands are), with a fence round its edge so nobody walks off it by mistake. In its middle is a
//   plaza with the stairway down (a long one: it comes out on the ground right under the island); east of the
//   plaza is its airport: a runway, an apron and a UFO pad.
// * It can only be reached by air or by teleport: the air network (AirNetwork.swift) flies planes and saucers
//   to it, and the teleport centre lists it.
// * Its people walk its roads (the land's figures).

public enum SkyTune {
    /// The storey the islands float on.
    public static let storey = 40
    public static var depth: Int { OpenWorld.storeyBase + storey }
    public static let spacing = 18
    /// Chunks from the middle of an island to its edge.
    public static let radius = 2.3
}

extension Generator {
    /// The middle chunk of the sky city of a block of chunks (nil near the first villages).
    func skyCentre(_ bx: Int, _ by: Int) -> (Int, Int)? {
        let n = SkyTune.spacing
        let h = MP.h2(seed &+ 9393, bx, by)
        let cx = bx * n + 3 + Int(h % UInt32(n - 6)), cy = by * n + 3 + Int((h >> 8) % UInt32(n - 6))
        if abs(cx) <= 6 && abs(cy) <= 6 { return nil }
        return (cx, cy)
    }

    /// Is this chunk the middle of a sky city?
    public func isSkyCity(_ cx: Int, _ cy: Int) -> Bool {
        let n = SkyTune.spacing
        guard let c = skyCentre(OpenWorld.floorDiv(cx, n), OpenWorld.floorDiv(cy, n)) else { return false }
        return c == (cx, cy)
    }

    /// The middle of the sky island this chunk is part of, if any.
    public func skyIsland(_ cx: Int, _ cy: Int) -> (Int, Int)? {
        let n = SkyTune.spacing, r = Int(SkyTune.radius.rounded(.up))
        var seen = Set<Int64>()
        for dy in -r...r { for dx in -r...r {
            let bx = OpenWorld.floorDiv(cx + dx, n), by = OpenWorld.floorDiv(cy + dy, n)
            guard seen.insert(MP.chunkKey(bx, by)).inserted, let c = skyCentre(bx, by) else { continue }
            let ex = Double(cx - c.0), ey = Double(cy - c.1)
            if ex * ex + ey * ey <= SkyTune.radius * SkyTune.radius { return c }
        } }
        return nil
    }

    /// A sky city's name, from its place.
    public func skyCityName(_ cx: Int, _ cy: Int, zh: Bool) -> String {
        let h = MP.h2(seed &+ 9494, cx, cy)
        let a = Int(h % 10), b = Int((h >> 8) % 8)
        if zh { return ["云", "霞", "星", "风", "虹", "月", "晴", "翠", "琼", "天"][a] + ["顶城", "浮岛", "阙", "台", "都", "空港", "苑", "庭"][b] }
        return ["Cloud", "Aurora", "Star", "Wind", "Rainbow", "Moon", "Clear", "Jade", "Halo", "Heaven"][a] + ["top", " Isle", "spire", "haven", "reach", " Port", " Garden", " Court"][b]
    }
}

extension Generator {
    /// How far the coast of the island centred on chunk `c` is from its middle, in tiles, in direction `a`
    /// (radians): a rounded island with bays and headlands, never past the island's chunks, and always wide
    /// enough to the east for the airport.
    public func skyCoast(_ c: (Int, Int), angle a: Double) -> Double {
        let h = MP.h2(seed &+ 9595, c.0, c.1)
        let p1 = Double(h % 628) / 100, p2 = Double((h >> 10) % 628) / 100, p3 = Double((h >> 20) % 628) / 100
        var r = 57 + 5 * sin(3 * a + p1) + 3 * sin(5 * a + p2) + 1.5 * sin(9 * a + p3)
        if abs(atan2(sin(a), cos(a))) < 0.62 { r = max(r, 56) }                  // the airport's side
        return min(66, r)
    }

    /// Is this tile on the island (inside its coast), and how far inside (tiles; negative: off it)?
    public func skyInside(_ x: Int, _ y: Int, centre c: (Int, Int)) -> Double {
        let dx = Double(x - (c.0 * 32 + 16)) + 0.5, dy = Double(y - (c.1 * 32 + 16)) + 0.5
        return skyCoast(c, angle: atan2(dy, dx)) - (dx * dx + dy * dy).squareRoot()
    }

    /// A chunk of a sky city: white marble houses with angel wings on either side, gold lamps, gardens of
    /// flowers and trees, marble paths in a grid, and the coast: grass to the edge, a balustrade along it,
    /// and nothing past it (open air). The middle chunk is the plaza with the stairway down; the one east of it
    /// the airport.
    public func skyPlan(_ cx: Int, _ cy: Int, centre c: (Int, Int)) -> [[UInt8]] {
        let k = Content.shared
        let grass = k.tid("grass"), marble = k.tid("marble_floor"), path = k.tid("marble_path"), wall = k.tid("marble_wall")
        let wingE = k.tid("wing_e"), wingW = k.tid("wing_w"), rail = k.tid("sky_rail"), lamp = k.tid("lamp_on")
        var g = [UInt8](repeating: grass, count: MP.chunkArea), st = [UInt8](repeating: 0, count: MP.chunkArea), ob = st, de = st
        @inline(__always) func i(_ x: Int, _ y: Int) -> Int { y * 32 + x }
        let inside: (Int, Int) -> Double = { x, y in self.skyInside(cx * 32 + x, cy * 32 + y, centre: c) }
        var r = RNG(seed: Int(MP.h2(seed &+ 9696, cx, cy)))
        let home = (cx, cy) == c
        let flowers = [k.tid("flower_red"), k.tid("flower_yellow"), k.tid("flower_blue")]
        if home {
            // the plaza: marble, an angel statue, fountains (wells), lamps, flower beds; the stairway in the middle
            for y in 5...26 { for x in 5...26 { g[i(x, y)] = marble } }
            ob[i(16, 11)] = k.tid("statue")
            for (x, y) in [(10, 16), (22, 16)] { ob[i(x, y)] = k.tid("well") }
            for (x, y) in [(7, 7), (24, 7), (7, 24), (24, 24), (12, 12), (20, 12), (12, 20), (20, 20)] { ob[i(x, y)] = lamp }
            for (x, y) in [(9, 9), (22, 9), (9, 22), (22, 22)] { for d in 0..<3 { de[i(x + d, y)] = flowers[(x + d) % 3] } }
            ob[i(16, 16)] = k.tid("glass_lift")
        } else {
            // what fills each quarter between the paths
            for (qx, qy) in [(1, 1), (18, 1), (1, 18), (18, 18)] {
                let w = 7 + r.index(2), h = 6 + r.index(2)
                let bx = qx + 2 + r.index(13 - w - 2), by = qy + 2 + r.index(13 - h - 3)
                // a house only where it and its wings stand well inside the coast
                let fits = [(bx - 2, by - 1), (bx + w + 1, by - 1), (bx - 2, by + h), (bx + w + 1, by + h)].allSatisfy { inside($0.0, $0.1) > 3 }
                if fits && r.unit() < 0.8 {
                    for y in by..<(by + h) { for x in bx..<(bx + w) {
                        g[i(x, y)] = marble
                        ob[i(x, y)] = x == bx || x == bx + w - 1 || y == by || y == by + h - 1 ? wall : 0
                    } }
                    ob[i(bx + w / 2, qy < 15 ? by + h - 1 : by)] = k.tid("door_wood")
                    ob[i(bx + 1, by + 1)] = k.tid("bed")
                    ob[i(bx + w - 2, by + 1)] = r.unit() < 0.5 ? k.tid("table") : k.tid("bookshelf")
                    // the wings: one on each side wall, outside it, at its middle
                    let wy = by + h / 2
                    ob[i(bx + w, wy)] = wingE; ob[i(bx - 1, wy)] = wingW
                    // a gold lamp at the door, flowers round the house
                    let lx = bx + w / 2 + 1, ly = qy < 15 ? by + h : by - 1
                    if lx < 32, ly >= 0, ly < 32 { ob[i(lx, ly)] = lamp }
                    for _ in 0..<5 {
                        let x = qx + r.index(13), y = qy + r.index(13)
                        if ob[i(x, y)] == 0 && g[i(x, y)] == grass { de[i(x, y)] = flowers[r.index(3)] }
                    }
                } else {
                    // a garden: trees, bushes, flowers, a marble pillar or two
                    for y in qy..<(qy + 13) { for x in qx..<(qx + 13) {
                        let u = r.unit()
                        if u < 0.05 { ob[i(x, y)] = [k.tid("tree_oak"), k.tid("tree_willow")][r.index(2)] }
                        else if u < 0.065 { ob[i(x, y)] = k.tid("pillar") }
                        else if u < 0.08 { ob[i(x, y)] = k.tid("bush") }
                        else if u < 0.2 { de[i(x, y)] = (flowers + [k.tid("tall_grass")])[r.index(4)] }
                    } }
                }
            }
            // the paths, gold lamps at the crossing
            for y in 0..<32 { for x in 0..<32 where x == 15 || x == 16 || y == 15 || y == 16 { st[i(x, y)] = path; ob[i(x, y)] = 0; de[i(x, y)] = 0 } }
            for (x, y) in [(14, 14), (17, 14), (14, 17), (17, 17)] { ob[i(x, y)] = lamp; de[i(x, y)] = 0 }
        }
        // the coast: off the island nothing at all (open air); the last tile a balustrade; grass inside it
        for y in 0..<32 { for x in 0..<32 {
            let d = inside(x, y)
            if d < 0 { g[i(x, y)] = 0; st[i(x, y)] = 0; ob[i(x, y)] = 0; de[i(x, y)] = 0 }
            else if d < 1.2 { g[i(x, y)] = grass; st[i(x, y)] = 0; ob[i(x, y)] = rail; de[i(x, y)] = 0 }
            else if d < 2.5 && st[i(x, y)] == 0 { if ob[i(x, y)] != 0 && ob[i(x, y)] != lamp { ob[i(x, y)] = 0 }; if r.unit() < 0.25 { de[i(x, y)] = flowers[r.index(3)] } }
        } }
        return [g, st, ob, de]
    }
}

extension Society {
    /// A chunk of the sky storey made for the first time: if it is part of an island, it is made so.
    func stampSky(_ ch: Chunk) {
        let gen = world.gen
        guard let c = gen.skyIsland(ch.cx, ch.cy) else { return }
        var p = gen.skyPlan(ch.cx, ch.cy, centre: c)
        if ch.cx == c.0 + 1 && ch.cy == c.1 {
            // the airport: a runway along the middle, an apron to the south, a UFO pad, lamps
            let runway = content.tid("runway"), apron = content.tid("apron"), pad = content.tid("ufo_pad"), stone = content.tid("marble_floor")
            for y in 2..<30 { for x in 1..<31 where p[0][y * 32 + x] != 0 {
                let i = y * 32 + x
                p[0][i] = stone; p[2][i] = 0; p[3][i] = 0; p[1][i] = 0
                if y >= 6 && y <= 9 { p[1][i] = runway }
                if y >= 13 && y <= 18 && x >= 3 && x <= 15 { p[1][i] = apron }
                if y >= 20 && y <= 26 && x >= 19 && x <= 27 { p[0][i] = pad }
            } }
            for (x, y) in [(2, 11), (16, 11), (29, 11), (17, 27)] where p[0][y * 32 + x] != 0 { p[2][y * 32 + x] = content.tid("lamp_on") }
            // the path in from the plaza stays open
            for y in 15...16 { for x in 0..<3 { p[1][y * 32 + x] = content.tid("marble_path"); p[0][y * 32 + x] = stone } }
        }
        for k in 0..<MP.chunkArea where ch.layers[0][k] == 0 && ch.layers[2][k] == 0 {
            for l in 0..<4 { ch.layers[l][k] = p[l][k] }
        }
    }

    /// The sky world (the storey the islands float on).
    public func skyWorld() -> OpenWorld { storeyWorld(SkyTune.storey) }

    /// The sky cities within `r` chunks of a tile: their names and their middle chunks.
    public func skyCities(near t: TilePos, within r: Int = 80, zh: Bool) -> [(name: String, cx: Int, cy: Int)] {
        let gen = world.gen, n = SkyTune.spacing
        let bx0 = OpenWorld.floorDiv(OpenWorld.floorDiv(t.x, 32) - r, n), bx1 = OpenWorld.floorDiv(OpenWorld.floorDiv(t.x, 32) + r, n)
        let by0 = OpenWorld.floorDiv(OpenWorld.floorDiv(t.y, 32) - r, n), by1 = OpenWorld.floorDiv(OpenWorld.floorDiv(t.y, 32) + r, n)
        var out: [(String, Int, Int)] = []
        for by in by0...by1 { for bx in bx0...bx1 { if let c = gen.skyCentre(bx, by) { out.append((gen.skyCityName(c.0, c.1, zh: zh), c.0, c.1)) } } }
        let me = (OpenWorld.floorDiv(t.x, 32), OpenWorld.floorDiv(t.y, 32))
        return out.sorted { a, b in
            let da = (a.1 - me.0) * (a.1 - me.0) + (a.2 - me.1) * (a.2 - me.1), db = (b.1 - me.0) * (b.1 - me.0) + (b.2 - me.1) * (b.2 - me.1)
            return da != db ? da < db : (a.1, a.2) < (b.1, b.2)
        }.map { (name: $0.0, cx: $0.1, cy: $0.2) }
    }

    /// Where one arrives at a sky city: its plaza (by the stairway), its runway's apron, or its UFO pad.
    public static func skyArrival(_ cx: Int, _ cy: Int, by: AirHub.Kind) -> TilePos {
        switch by {
        case .ufo: return TilePos((cx + 1) * 32 + 23, cy * 32 + 23)
        case .airport, .city: return TilePos((cx + 1) * 32 + 9, cy * 32 + 15)
        case .sky: return TilePos(cx * 32 + 16, cy * 32 + 18)
        }
    }

    /// The people of a sky city near a place, walking its roads.
    public func skyFolk(center: Vec2, halfW: Double, halfH: Double, limit: Int = 40) -> [UnderFolk] {
        let gen = world.gen
        let x0 = Int(((center.x - halfW) / 512).rounded(.down)), x1 = Int(((center.x + halfW) / 512).rounded(.down))
        let y0 = Int(((center.y - halfH) / 512).rounded(.down)), y1 = Int(((center.y + halfH) / 512).rounded(.down))
        var out: [UnderFolk] = []
        for cy in y0...y1 { for cx in x0...x1 {
            guard let c = gen.skyIsland(cx, cy), !(cx == c.0 + 1 && cy == c.1) else { continue }
            // (only on the island: a path that reaches the coast ends at the balustrade)
            out += walkers(cx, cy, salt: 8080, sea: false).filter { gen.skyInside(Int($0.pos.x / 16), Int($0.pos.y / 16), centre: c) > 1.5 }
            if out.count >= limit { return Array(out.prefix(limit)) }
        } }
        return out
    }

    /// Two or three people walking up and down a chunk's two roads, by the clock.
    func walkers(_ cx: Int, _ cy: Int, salt: Int, sea: Bool) -> [UnderFolk] {
        var out: [UnderFolk] = []
        let t = world.time
        let n = 2 + Int(MP.h2(world.seed &+ salt, cx, cy) % 2)
        for i in 0..<n {
            let h = MP.h2(world.seed &+ salt &+ 1 &+ i, cx, cy)
            let who = CharacterModels.resident(h, sea: sea)
            let period = 60.0 + Double(h % 40)
            let ph = (t / period + Double(h % 1000) / 1000).truncatingRemainder(dividingBy: 2)
            let f = ph < 1 ? ph : 2 - ph
            let along = 1.5 + f * 29, back = ph >= 1
            let vertical = i % 2 == 0
            let lane = 15.5 + (i % 3 == 2 ? 1 : 0)
            let tx = Double(cx * 32) + (vertical ? lane : along), ty = Double(cy * 32) + (vertical ? along : lane)
            let d: Vec2 = vertical ? Vec2(0, back ? -1 : 1) : Vec2(back ? -1 : 1, 0)
            let resting = f < 0.03 || f > 0.97
            let id = 900_000_000 + salt % 7 * 10_000_000 + Int((MP.h2(world.seed &+ salt &+ 2, cx, cy) & 0xffff)) * 8 + i
            out.append(UnderFolk(id: id, pos: Vec2(tx * 16, ty * 16), facing: resting ? Vec2(0, 1) : d, moving: !resting, look: who.look, female: who.female, child: who.child))
        }
        return out
    }

    /// The people of the city districts out on their streets: in front of every open building some of those
    /// who live or work there walk up and down the pavement (one for every 120 or so, three at most), by the
    /// clock, more by day than at night. They stand for the district's own people (who are counted in its
    /// buildings), so a district of thousands is busy, not empty.
    public func districtWalkers(center: Vec2, halfW: Double, halfH: Double, limit: Int = 40) -> [UnderFolk] {
        let t = world.time
        let x0 = center.x - halfW, x1 = center.x + halfW, y0 = center.y - halfH, y1 = center.y + halfH
        let day = world.hour >= 7 && world.hour < 21
        var out: [UnderFolk] = []
        for d in net.districts {
            for b in d.buildings where b.state == .open {
                let f = b.front
                let fx = Double(f.x) * 16 + 8, fy = Double(f.y) * 16 + 8
                guard fx > x0 - 300, fx < x1 + 300, fy > y0 - 300, fy < y1 + 300 else { continue }
                let crowd = b.residents + b.jobs
                guard crowd > 0 else { continue }
                let n = min(3, 1 + crowd / 120) - (day ? 0 : 1)
                guard n > 0 else { continue }
                // along the building's front (east-west for a door on the north or south side, else north-south)
                let alongX = f.y != b.entrance.y
                let reach = Double(max(4, alongX ? b.w : b.d)) * 16 / 2 + 24
                for i in 0..<n {
                    let h = MP.h2(world.seed &+ 6464 &+ i, b.id, d.id)
                    let who = CharacterModels.resident(h, sea: false)
                    let period = 40.0 + Double(h % 30)
                    let ph = (t / period + Double(h % 1000) / 1000).truncatingRemainder(dividingBy: 2)
                    let fr = ph < 1 ? ph : 2 - ph
                    let off = (fr * 2 - 1) * reach, side = Double(i % 2 == 0 ? 6 : 12)
                    let pos = alongX ? Vec2(fx + off, fy + side) : Vec2(fx + side, fy + off)
                    guard pos.x > x0, pos.x < x1, pos.y > y0, pos.y < y1 else { continue }
                    let dir = (ph < 1 ? 1.0 : -1.0)
                    let resting = fr < 0.03 || fr > 0.97
                    let id = 950_000_000 + (d.id % 100) * 1_000_000 + (b.id % 100_000) * 4 + i
                    out.append(UnderFolk(id: id, pos: pos, facing: resting ? Vec2(0, 1) : (alongX ? Vec2(dir, 0) : Vec2(0, dir)), moving: !resting, look: who.look, female: who.female, child: who.child))
                    if out.count >= limit { return out }
                }
            }
        }
        return out
    }

    /// The people to draw on a layer (underground or in the sky), near a place.
    public func folk(depth: Int, center: Vec2, halfW: Double, halfH: Double, limit: Int = 40) -> [UnderFolk] {
        if depth == 0 { return districtWalkers(center: center, halfW: halfW, halfH: halfH, limit: limit) }
        if MP.isBelow(depth) { return underFolk(center: center, halfW: halfW, halfH: halfH, limit: limit, level: depth) }
        if depth == SkyTune.depth { return skyFolk(center: center, halfW: halfW, halfH: halfH, limit: limit) }
        return []
    }
}
