import Foundation

// The four realms: the ground, the underground (and the levels under it), the sea floor and the sky.
//
// * Below the ground is a copy of the ground: every chunk of a city's underland takes the ground, the plants,
//   the rivers and the buildings of the chunk right above it (where the ground above is sea, or has nothing
//   built, the city's own streets and houses are laid over it so its people still have homes and beds).
//   Every level down is the same copy again.
// * The realms are joined by glass elevators: one shaft in the middle of every city below, through all its
//   levels and up to the ground (a car of glass, seen from every side); one in the plaza of every sky island,
//   down to the ground under it; and one in the pearl dome of every city on the sea floor. Stepping into one
//   asks which floor (`liftFloors`, `rideLift`).
// * A city of the sea floor is a dome of glass in the sea: its streets inside, a ring of glass round them,
//   and outside the open water, where fish, turtles, rays, dolphins and whales swim past (`domeLife`).

public enum RealmLift {
    /// Where the elevator stands in the middle chunk of a city (below, on the ground above it, in the sky).
    public static let x = 16, y = 16
}

extension Society {
    // MARK: - the copy of the ground

    /// Lay the ground above over a chunk of underland: its ground, plants and buildings. A chunk with nothing
    /// built above keeps the city's own houses and streets laid over the copied land; the plaza in the city's
    /// middle (with its elevator) and the glass where the underland still meets rock stay as planned.
    func copyGround(_ p: inout UnderlandPlan, _ cx: Int, _ cy: Int, home: Bool) {
        let lift = content.tid("glass_lift"), down = content.tid("stairs_down"), up = content.tid("stairs_up")
        var built = 0
        for y in 0..<32 { for x in 0..<32 {
            let o = world.tile(2, cx * 32 + x, cy * 32 + y)
            if o != 0, let t = content.tile(o), t.built && t.solid { built += 1 }
        } }
        let town = built >= 12
        for y in 0..<32 { for x in 0..<32 {
            let k = y * 32 + x
            if home && x >= 6 && x <= 25 && y >= 6 && y <= 25 { continue }
            let rim = x == 0 || y == 0 || x == 31 || y == 31
            if rim && p.layers[2][k] != 0 && !p.openEdge[k] { continue }
            let wx = cx * 32 + x, wy = cy * 32 + y
            let g = world.tile(0, wx, wy)
            // the sea and wide water above: the city's own streets down here
            if g == 0 || g == content.tid("deep_water") || g == content.tid("water") || g == content.tid("seabed") { continue }
            var ob = world.tile(2, wx, wy)
            if ob == down || ob == up || ob == lift { ob = 0 }
            let st = world.tile(1, wx, wy), de = world.tile(3, wx, wy)
            if town {
                p.layers[0][k] = g; p.layers[1][k] = st; p.layers[2][k] = ob; p.layers[3][k] = de
            } else {
                // the land as above, the city's buildings and roads on it
                let planned = p.layers[2][k] != 0 || p.layers[1][k] != 0
                let plannedGround = p.layers[0][k]
                let groundIsBuilt = content.tile(plannedGround)?.key.contains("floor") == true || content.tile(plannedGround)?.key == "farmland"
                if !planned && !groundIsBuilt {
                    p.layers[0][k] = g; p.layers[2][k] = ob; p.layers[3][k] = de
                    if st != 0 { p.layers[1][k] = st }
                }
            }
        } }
    }

    // MARK: - the domes of the sea floor

    /// How far the glass of a sea city's dome reaches from its middle (tiles).
    func domeRadius(_ z: UnderlandZone) -> Double { max(10, (z.r - 0.75) * 32) }

    /// A chunk of a sea city: inside the dome its streets; the ring of glass; outside it, the sea.
    func seaDome(_ p: inout UnderlandPlan, _ cx: Int, _ cy: Int, _ z: UnderlandZone) {
        let R = domeRadius(z)
        let ox = Double(z.cx * 32 + 16), oy = Double(z.cy * 32 + 16)
        let water = content.tid("water"), glass = content.tid("wall_glass"), sand = content.tid("sand"), kelp = content.tid("kelp")
        for y in 0..<32 { for x in 0..<32 {
            let k = y * 32 + x
            let dx = Double(cx * 32 + x) + 0.5 - ox, dy = Double(cy * 32 + y) + 0.5 - oy
            let d = (dx * dx + dy * dy).squareRoot()
            if d > R + 0.75 {
                p.layers[0][k] = water; p.layers[1][k] = 0; p.layers[2][k] = 0
                p.layers[3][k] = MP.h2(world.seed &+ 5151, cx * 32 + x, cy * 32 + y) % 23 == 0 ? kelp : 0
                p.openEdge[k] = false
            } else if d > R - 0.75 {
                p.layers[0][k] = sand; p.layers[1][k] = 0; p.layers[2][k] = glass; p.layers[3][k] = 0
                p.openEdge[k] = false
            }
        } }
    }

    /// The sea city whose waters reach this chunk of the underground (round its dome, beyond its underland).
    func seaHalo(_ cx: Int, _ cy: Int) -> UnderlandZone? {
        underlandZones().first { z in
            guard z.sea, !z.contains(cx, cy) else { return false }
            let dx = Double(cx - z.cx), dy = Double(cy - z.cy)
            return dx * dx + dy * dy <= (z.r + 1.6) * (z.r + 1.6)
        }
    }

    /// The four layers of open sea round a dome.
    func haloPlan(_ cx: Int, _ cy: Int, _ z: UnderlandZone) -> [[UInt8]] {
        let g = [UInt8](repeating: content.tid("water"), count: MP.chunkArea)
        var de = [UInt8](repeating: 0, count: MP.chunkArea)
        let kelp = content.tid("kelp")
        for k in 0..<MP.chunkArea where MP.h2(world.seed &+ 5151, cx * 32 + k % 32, cy * 32 + k / 32) % 23 == 0 { de[k] = kelp }
        _ = z
        return [g, [UInt8](repeating: 0, count: MP.chunkArea), [UInt8](repeating: 0, count: MP.chunkArea), de]
    }

    /// Flood one chunk already in use round a dome (cave only). Returns the tiles changed.
    @discardableResult func carveHalo(_ cx: Int, _ cy: Int, _ z: UnderlandZone, in u: OpenWorld) -> Int {
        let p = haloPlan(cx, cy, z)
        var n = 0
        for y in 0..<32 { for x in 0..<32 {
            let k = y * 32 + x, wx = cx * 32 + x, wy = cy * 32 + y
            guard Generator.naturalCave(u.tile(0, wx, wy), u.tile(1, wx, wy), u.tile(2, wx, wy), u.tile(3, wx, wy)) else { continue }
            for l in 0..<4 where u.tile(l, wx, wy) != p[l][k] { u.setTile(l, wx, wy, p[l][k]) }
            n += 1
        } }
        return n
    }

    /// A creature swimming past a dome (seen through its glass; it lives in no save: its way round the dome
    /// comes from the time and its number alone).
    public struct DomeSwimmer {
        public let id: Int
        public let species: Species
        public let pos: Vec2
        public let facing: Vec2
    }

    /// The creatures swimming round the domes near a point of the underground, now.
    public func domeLife(around p: Vec2, reach: Double = 1600, time: Double? = nil) -> [DomeSwimmer] {
        let now = time ?? world.time
        let kinds = Species.all.filter { $0.aquatic }
        guard !kinds.isEmpty else { return [] }
        let u = underworld()
        var out: [DomeSwimmer] = []
        for z in underlandZones() where z.sea {
            let ox = Double(z.cx * 32 + 16) * 16, oy = Double(z.cy * 32 + 16) * 16
            let R = domeRadius(z)
            if abs(ox - p.x) > reach + (R + 60) * 16 || abs(oy - p.y) > reach + (R + 60) * 16 { continue }
            for i in 0..<28 {
                let h = MP.h2(world.seed &+ 7373 &+ i, z.cx, z.cy)
                let sp = kinds[Int(h % UInt32(kinds.count))]
                // its ring round the dome, its speed, which way round it swims
                let ring = (R + 4 + Double((h >> 8) % 36)) * 16
                let dir: Double = (h >> 20) & 1 == 0 ? 1 : -1
                let speed = sp.speed * 0.35 / ring
                let a = Double((h >> 12) % 628) / 100 + dir * now * speed
                let pos = Vec2(ox + cos(a) * ring, oy + sin(a) * ring)
                if abs(pos.x - p.x) > reach || abs(pos.y - p.y) > reach { continue }
                let t = pos.tile
                guard content.water[Int(u.tile(0, t.x, t.y))] else { continue }
                out.append(DomeSwimmer(id: z.cx &* 7919 &+ z.cy &* 131 &+ i, species: sp, pos: pos, facing: Vec2(-sin(a) * dir, cos(a) * dir)))
            }
        }
        return out
    }

    // MARK: - the glass elevators

    /// One floor a glass elevator stops at.
    public struct LiftFloor: Equatable {
        public let depth: Int
        public let en: String, zh: String
        public func name(zh z: Bool) -> String { z ? zh : en }
    }

    /// The floors a glass elevator standing at this tile serves: the ground, every level the city below has built
    /// down to, the sky island over it.
    public func liftFloors(at t: TilePos) -> [LiftFloor] {
        let cx = t.x >> 5, cy = t.y >> 5
        var out = [LiftFloor(depth: 0, en: "Ground", zh: "地面")]
        let sea = underlandZones().contains { $0.sea && $0.contains(cx, cy) } || world.gen.isSeaCity(cx, cy)
        var levels = (1...MP.deepest).filter { l in underlandZones(level: l).contains { $0.contains(cx, cy) } }
        if levels.isEmpty && (world.gen.isUnderCity(cx, cy) || sea) { levels = [1] }
        for l in levels {
            if l == 1 && sea { out.append(LiftFloor(depth: 1, en: "Sea-floor city", zh: "海底城")) }
            else { out.append(LiftFloor(depth: l, en: "B\(l)", zh: "地下 \(l) 层")) }
        }
        if world.gen.skyIsland(cx, cy) != nil { out.append(LiftFloor(depth: SkyTune.depth, en: "Sky city", zh: "天空城")) }
        return out
    }

    /// Ride a glass elevator to a floor: the car comes out of the same shaft there (a landing is made where there
    /// is none yet). Returns where the traveller steps out, nil when the floor is not served.
    public func rideLift(at t: TilePos, to depth: Int) -> Vec2? {
        guard liftFloors(at: t).contains(where: { $0.depth == depth }) else { return nil }
        let w = layer(depth)
        realm.player.depth = depth
        if depth == 1 { _ = digUnderground(around: t) }
        if MP.isBelow(depth) { _ = digDeep(around: t, level: depth) }
        // the landing: the shaft, and floor round it to step out on
        let lift = content.tid("glass_lift")
        for dy in -1...1 { for dx in -1...1 {
            let x = t.x + dx, y = t.y + dy
            let o = w.tile(2, x, y)
            if o != 0 && o != lift && (content.solid[Int(o)] || content.tile(o)?.natural == true) { w.setTile(2, x, y, 0) }
            let g = w.tile(0, x, y)
            if g == 0 || content.water[Int(g)] || g == content.tid("lava") { w.setTile(0, x, y, content.tid("stone_floor")) }
        } }
        if w.tile(2, t.x, t.y) != lift { w.setTile(2, t.x, t.y, lift) }
        let out = w.findFree(near: t + TilePos(0, 1), maxR: 4)
        return out.center
    }

    /// The glass elevators on the ground over the cities below near a place (one over the middle of each; a tree
    /// or a stair there makes way, anything built stays).
    @discardableResult public func placeGroundLifts(around t: TilePos, reach: Int = 6) -> Int {
        guard let c = realm.civBox, c.underNations else { return 0 }
        let lift = content.tid("glass_lift")
        var n = 0
        for z in underlandZones() where !z.sea && abs(z.cx - (t.x >> 5)) <= reach && abs(z.cy - (t.y >> 5)) <= reach {
            let wx = z.cx * 32 + RealmLift.x, wy = z.cy * 32 + RealmLift.y
            let o = world.tile(2, wx, wy)
            if o == lift { continue }
            let key = content.tile(o)?.key ?? ""
            guard o == 0 || content.tile(o)?.natural == true || key == "stairs_down" else { continue }
            world.setTile(2, wx, wy, lift)
            if content.water[Int(world.tile(0, wx, wy))] { world.setTile(0, wx, wy, content.tid("stone_floor")) }
            n += 1
        }
        return n
    }
}
