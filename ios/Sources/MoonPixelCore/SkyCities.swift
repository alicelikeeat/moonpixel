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

extension Society {
    /// A chunk of the sky storey made for the first time: if it is part of an island, it is made so.
    func stampSky(_ ch: Chunk) {
        let gen = world.gen
        guard let c = gen.skyIsland(ch.cx, ch.cy) else { return }
        let fence = content.tid("fence")
        let home = c == (ch.cx, ch.cy)
        var p = gen.underlandPlan(ch.cx, ch.cy, sea: false, home: home, rim: fence, inZone: { x, y in gen.skyIsland(x, y).map { $0 == c } ?? false })
        if home {
            // the long stairway down, in the middle of the plaza
            p.layers[2][16 * 32 + 16] = content.tid("stairs_down")
        } else if ch.cx == c.0 + 1 && ch.cy == c.1 {
            // the airport: a runway along the middle, an apron to the south, a UFO pad, lamps
            let runway = content.tid("runway"), apron = content.tid("apron"), pad = content.tid("ufo_pad"), stone = content.tid("stone_floor")
            for y in 2..<30 { for x in 1..<31 {
                let i = y * 32 + x
                p.layers[0][i] = stone; p.layers[2][i] = 0; p.layers[3][i] = 0; p.layers[1][i] = 0
                if y >= 6 && y <= 9 { p.layers[1][i] = runway }
                if y >= 13 && y <= 18 && x >= 3 && x <= 15 { p.layers[1][i] = apron }
                if y >= 20 && y <= 26 && x >= 19 && x <= 27 { p.layers[0][i] = pad }
            } }
            for (x, y) in [(2, 11), (16, 11), (29, 11), (17, 27)] { p.layers[2][y * 32 + x] = content.tid("lamp_on") }
            // the road in from the plaza stays open
            for y in 15...16 { for x in 0..<3 { p.layers[1][y * 32 + x] = content.tid("cobble_road"); p.layers[0][y * 32 + x] = stone } }
        }
        for k in 0..<MP.chunkArea where ch.layers[0][k] == 0 && ch.layers[2][k] == 0 {
            for l in 0..<4 { ch.layers[l][k] = p.layers[l][k] }
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
            out += walkers(cx, cy, salt: 8080, sea: false)
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

    /// The people to draw on a layer (underground or in the sky), near a place.
    public func folk(depth: Int, center: Vec2, halfW: Double, halfH: Double, limit: Int = 40) -> [UnderFolk] {
        if depth == 1 { return underFolk(center: center, halfW: halfW, halfH: halfH, limit: limit) }
        if depth == SkyTune.depth { return skyFolk(center: center, halfW: halfW, halfH: halfH, limit: limit) }
        return []
    }
}
