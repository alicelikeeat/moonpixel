import Foundation

// New York-style towers for grown districts. Real Manhattan massing is set by its zoning: a tower rises
// straight from the street, then steps back in tiers ("wedding cake" setbacks) and ends in a crown or a
// spire. These are original buildings in that manner, not copies of any one building:
//
// - "deco": an Art Deco limestone tower, vertical window ribbons, four setbacks, a deco crown and a mast;
// - "crown": a slimmer stone tower whose top tiers step in quickly as a terraced metal crown with a needle;
// - "supertall": a modern glass tower that tapers steadily as it rises, steel corners, a spire;
// - "pencil": a slim residential tower, straight up, a square grid of windows (no setbacks);
// - "brownstone": a row of brownstone houses, four storeys (the ordinary streets between the towers).
//
// Every floor of a tower is real: walls on the floor's setback line, a floor inside, a lift and stairs in
// the core at the centre (the same place on every floor, so they line up), roof terraces where the tower
// steps back. The topmost tiers (crown, spire) are too narrow for the core and are closed.

public enum Skyline {
    /// The kinds drawn as setback towers with a core (the brownstone is an ordinary building).
    public static let towers: Set<String> = ["deco", "crown", "supertall", "pencil"]
    public static func isTower(_ kind: String) -> Bool { towers.contains(kind) }

    /// How many tiles in from each side the walls stand on `level` (0 = street) of a tower `n` storeys high
    /// with a square footprint of `side` tiles. Never decreases going up.
    public static func inset(_ kind: String, level l: Int, of n: Int, side: Int) -> Int {
        let f = Double(l) / Double(max(1, n))
        let tip = (side - 1) / 2                        // a 1×1 spire
        switch kind {
        case "deco":
            if f < 0.09 { return 0 }                    // the base fills the block
            if f < 0.55 { return 2 }
            if f < 0.78 { return 3 }
            if f < 0.88 { return 4 }
            if f < 0.94 { return 5 }                    // the crown
            return tip                                  // the mast
        case "crown":
            if f < 0.14 { return 0 }
            if f < 0.70 { return 2 }
            if f < 0.80 { return 3 }
            if f < 0.86 { return 4 }
            if f < 0.91 { return 5 }
            return tip
        case "supertall":
            if f < 0.08 { return 0 }                    // a podium
            if f < 0.92 { return min(4, 1 + Int((f - 0.08) / 0.84 * 4)) }   // the steady taper
            return tip
        default:                                        // pencil: straight up
            return 0
        }
    }

    /// The tower's core (lift and stairs) fits on a floor with this inset.
    public static func coreFits(inset: Int, side: Int) -> Bool { inset <= (side - 1) / 2 - 2 }

    /// What a floor's walls are made of: the body, the windows, and whether the floor is in the crown.
    public static func walls(_ kind: String, level l: Int, of n: Int, side: Int) -> (wall: String, window: String, crown: Bool) {
        let i = inset(kind, level: l, of: n, side: side)
        if i == (side - 1) / 2 { return ("spire_steel", "spire_steel", true) }
        switch kind {
        case "deco": return i >= 5 ? ("wall_deco", "spire_steel", true) : ("wall_limestone", "wall_glass", false)
        case "crown": return i >= 3 ? ("wall_deco", "spire_steel", true) : ("wall_limestone", "wall_glass", false)
        case "supertall": return ("spire_steel", "wall_glass", false)
        default: return ("wall_concrete", "wall_glass", false)
        }
    }

    /// Where the core is on a tower whose footprint starts at `x`, `y`: the 2×2 lift shaft, the tile in
    /// front of it where the car is boarded, and the stairs (two places, used on alternate floors, so the
    /// stairs down from one floor never stand where the stairs up are).
    public static func core(x: Int, y: Int, side: Int) -> (shaft: TilePos, landing: TilePos, stairs: [TilePos]) {
        let c = (side - 1) / 2
        return (TilePos(x + c - 1, y + c - 1), TilePos(x + c - 1, y + c + 1), [TilePos(x + c + 1, y + c - 1), TilePos(x + c + 1, y + c + 1)])
    }

    /// A tower's tiers from the street up: each run of floors with the same inset (for drawing the massing).
    public static func tiers(_ kind: String, storeys n: Int, side: Int) -> [(from: Int, to: Int, inset: Int)] {
        var out: [(Int, Int, Int)] = []
        for l in 0..<n {
            let i = inset(kind, level: l, of: n, side: side)
            if let last = out.last, last.2 == i { out[out.count - 1].1 = l } else { out.append((l, l, i)) }
        }
        return out.map { (from: $0.0, to: $0.1, inset: $0.2) }
    }
}

extension Society {
    /// Raise a setback tower: every floor's walls on its setback line, roof terraces where it steps in, the
    /// core (lift shaft kept open, the landing, stairs) on every floor it fits, desks or beds in rows.
    func raiseTower(_ b: CityBuilding, _ d: District) {
        let side = min(b.w, b.d)
        let n = max(1, b.floors.count)
        let core = Skyline.core(x: b.x, y: b.y, side: side)
        let door = content.tid("door_wood")
        let thing = content.tid(b.def.use == .residential ? "bed" : "desk")
        func inShaft(_ t: TilePos) -> Bool { t.x >= core.shaft.x && t.x < core.shaft.x + 2 && t.y >= core.shaft.y && t.y < core.shaft.y + 2 }
        for level in 0..<n {
            let lw = level == 0 ? world : storeyWorld(level)
            let i = Skyline.inset(b.kind, level: level, of: n, side: side)
            let below = level == 0 ? 0 : Skyline.inset(b.kind, level: level - 1, of: n, side: side)
            let mat = Skyline.walls(b.kind, level: level, of: n, side: side)
            let wall = content.tid(mat.wall), window = content.tid(mat.window)
            let floor = content.tid(b.kind == "supertall" || b.kind == "pencil" ? "stone_floor" : "brick_floor")
            let hasCore = Skyline.coreFits(inset: i, side: side)
            let lo = i, hi = side - 1 - i
            for y in 0..<side { for x in 0..<side {
                let t = TilePos(b.x + x, b.y + y)
                if level == 0 { lw.setTile(1, t.x, t.y, 0); lw.setTile(3, t.x, t.y, 0) }
                let inside = x >= lo && x <= hi && y >= lo && y <= hi
                if !inside {
                    // a roof terrace where the tower stepped in on this floor; open air above that
                    let terrace = x >= below && x <= side - 1 - below && y >= below && y <= side - 1 - below
                    lw.setTile(0, t.x, t.y, terrace ? floor : 0)
                    lw.setTile(2, t.x, t.y, 0)
                    continue
                }
                let edge = x == lo || x == hi || y == lo || y == hi
                let corner = (x == lo || x == hi) && (y == lo || y == hi)
                if hasCore && inShaft(t) && level > 0 {
                    // the shaft: no floor, no wall, on every floor above the street
                    lw.setTile(0, t.x, t.y, 0); lw.setTile(2, t.x, t.y, 0); continue
                }
                lw.setTile(0, t.x, t.y, floor)
                if edge {
                    // how far along its wall a tile is: windows in vertical ribbons, a pier between each
                    let along = (y == lo || y == hi) ? x - lo : y - lo
                    let glazed: Bool
                    switch b.kind {
                    case "supertall": glazed = !corner
                    default: glazed = !corner && along % 2 == (mat.crown ? 0 : 1)
                    }
                    let isDoor = level == 0 && t == b.entrance
                    lw.setTile(2, t.x, t.y, isDoor ? door : (glazed ? window : wall))
                } else if !hasCore && hi - lo <= 2 {
                    // a crown or a spire too narrow to enter: solid
                    lw.setTile(2, t.x, t.y, wall)
                } else if lw.tile(2, t.x, t.y) != content.tid("stairs_down") {
                    lw.setTile(2, t.x, t.y, 0)
                }
            } }
            guard hasCore else { continue }
            // desks or beds in rows around the core (never on the core, its landing or the stairs)
            let keep = Set([core.landing] + core.stairs)
            for y in stride(from: b.y + lo + 2, to: b.y + hi - 1, by: 3) { for x in stride(from: b.x + lo + 2, to: b.x + hi - 1, by: 2) {
                let t = TilePos(x, y)
                if inShaft(t) || keep.contains(t) || abs(t.x - core.landing.x) + abs(t.y - core.landing.y) <= 1 { continue }
                if lw.tile(2, x, y) == 0 { lw.setTile(2, x, y, thing) }
            } }
            // stairs up to the next floor when the core is there too
            if level + 1 < n, Skyline.coreFits(inset: Skyline.inset(b.kind, level: level + 1, of: n, side: side), side: side) {
                let st = core.stairs[level % 2]
                lw.setTile(2, st.x, st.y, content.tid("stairs_up"))
                linkUp(at: st, from: lw)
            }
        }
        keepClear(b.front)
        keepClear(b.entrance)
    }

    /// The lift in a tower's core: from the street to the highest floor the core reaches, a stop on every
    /// floor. Paid from the district's store like any other lift.
    @discardableResult func coreLift(_ bi: Int, _ d: District) -> Int? {
        let b = d.buildings[bi]
        guard b.floors.count >= 3, b.lift == nil else { return b.lift }
        let side = min(b.w, b.d), n = b.floors.count
        let core = Skyline.core(x: b.x, y: b.y, side: side)
        let levels = (0..<n).filter { Skyline.coreFits(inset: Skyline.inset(b.kind, level: $0, of: n, side: side), side: side) }
        let plan = planLift(x: core.shaft.x, y: core.shaft.y, levels: levels, landingSide: TilePos(0, 1))
        guard plan.ok, Goods.take(plan.cost, from: d.holding) == nil else { d.note("no lift yet for tower \(b.id): \(plan.reason)"); return nil }
        record(plan.cost.map { ($0.key, $0.value) }, from: d.holding.name, to: "elevator works", note: "core lift for tower \(b.id)")
        let id = makeLift(plan, x: core.shaft.x, y: core.shaft.y, w: 2, d: 2, town: 0, tower: nil)
        if let e = lift(id) { e.district = d.id; e.building = b.id; e.nation = d.nation }
        d.buildings[bi].lift = id
        return id
    }

    /// The towers of every district that reach past `level` storeys, as boxes to draw from afar: one box per
    /// tier (x, y, w, d in tiles; from and to as storeys), with the tier's wall colour and whether it is glass.
    /// The 3D view draws these for the floors it does not mesh (the far ones), so a skyline is seen whole.
    public func skylineBlocks(near c: TilePos, radius: Int) -> [SkylineBlock] {
        var out: [SkylineBlock] = []
        for d in (realm.transportBox?.districts ?? []) {
            for b in d.buildings where b.state == .open && b.floors.count >= 8 && abs(b.x - c.x) <= radius && abs(b.y - c.y) <= radius {
                let side = min(b.w, b.d), n = b.floors.count
                let base = Terrain3D.level(elevation: world.gen.elevation(b.entrance.x, b.entrance.y))
                let tiers: [(from: Int, to: Int, inset: Int)] = Skyline.isTower(b.kind)
                    ? Skyline.tiers(b.kind, storeys: n, side: side) : [(from: 0, to: n - 1, inset: 0)]
                for t in tiers {
                    let face = Society.facade(b.kind)
                    let mat: (wall: String, window: String, crown: Bool) = Skyline.isTower(b.kind) ? Skyline.walls(b.kind, level: t.from, of: n, side: side) : (face.wall, face.window, false)
                    let wall = content.tile(content.tid(mat.wall)), window = content.tile(content.tid(mat.window))
                    var k = SkylineBlock()
                    k.x = b.x + t.inset; k.y = b.y + t.inset
                    k.w = (Skyline.isTower(b.kind) ? side : b.w) - 2 * t.inset; k.d = (Skyline.isTower(b.kind) ? side : b.d) - 2 * t.inset
                    k.from = t.from; k.to = t.to + 1; k.baseLevel = base
                    k.wall = RGBA(hex: wall?.c1 ?? "#c8c6c0"); k.window = RGBA(hex: window?.c2 ?? "#5a8cb0")
                    k.glass = b.kind == "supertall" || b.kind == "skyscraper"
                    k.crown = mat.crown
                    if mat.crown, let a = wall?.c3, !a.isEmpty { k.accent = RGBA(hex: a) } else { k.accent = k.wall.darkened(0.12) }
                    k.building = b.id; k.district = d.id
                    out.append(k)
                }
            }
        }
        return out
    }
}

/// One tier of a tower, to be drawn from afar.
public struct SkylineBlock: Equatable {
    public var x = 0, y = 0, w = 1, d = 1
    public var from = 0, to = 1                  // storeys: from the floor of `from` to the floor of `to`
    public var baseLevel = 0                     // the terrain level at the street (heights are counted from it)
    public var wall = RGBA(200, 198, 192), window = RGBA(90, 140, 176)
    public var glass = false, crown = false
    public var accent = RGBA(176, 174, 168)       // the ledge round the tier's top (gold on an Art Deco crown)
    public var building = 0, district = 0
    public init() {}
    /// Height in scene units of storey `s` of this tower (the floor of it).
    public func y(_ s: Int) -> Float { Float(baseLevel + s * Terrain3D.storeyLevels) * Terrain3D.step }
}

extension Mesh3D {
    /// The skyline boxes as one mesh, in world units (x and z are tiles, y is up): each tier a box, with
    /// the window bands of its floors drawn on its sides and a ledge on top, only the floors from `skipBelow`
    /// up (the nearer ones are meshed from the real tiles).
    public static func skyline(_ blocks: [SkylineBlock], skipBelow: Int = 0, anime: Bool = false) -> Mesh3D {
        skyline(blocks, skip: { _ in [0..<skipBelow] }, anime: anime)
    }

    /// The same, leaving out for each tower the floors `skip` names (the ones the view meshes from tiles).
    public static func skyline(_ blocks: [SkylineBlock], skip: (SkylineBlock) -> [Range<Int>], anime: Bool = false) -> Mesh3D {
        var m = Mesh3D()
        m.cel = anime
        for whole in blocks {
            // what is left of the tier once the skipped floors are taken out: up to a few runs of floors
            var runs: [Range<Int>] = [whole.from..<whole.to]
            for r in skip(whole) where !r.isEmpty {
                runs = runs.flatMap { a -> [Range<Int>] in
                    guard a.overlaps(r) else { return [a] }
                    return [a.lowerBound..<max(a.lowerBound, r.lowerBound), min(a.upperBound, r.upperBound)..<a.upperBound].filter { !$0.isEmpty }
                }
            }
            for run in runs { m.tier(whole, from: run.lowerBound, to: run.upperBound) }
        }
        return m
    }

    /// One run of floors of a tier as a box with its windows, piers and ledge (the ledge only at the tier's top).
    mutating func tier(_ k: SkylineBlock, from s0: Int, to s1: Int) {
        var m = self
        defer { self = m }
        do {
            let x0 = Float(k.x), z0 = Float(k.y), x1 = Float(k.x + k.w), z1 = Float(k.y + k.d)
            let y0 = k.y(s0), y1 = k.y(s1)
            let top = s1 == k.to
            if k.w <= 1 && k.d <= 1 {
                // a spire: a thin needle
                let cx = (x0 + x1) / 2, cz = (z0 + z1) / 2
                m.box(cx - 0.3, y0, cz - 0.3, cx + 0.3, y1, cz + 0.3, k.wall)
                if top { m.box(cx - 0.1, y1, cz - 0.1, cx + 0.1, y1 + 3, cz + 0.1, k.wall.lightened(0.2)) }
                return
            }
            m.box(x0, y0, z0, x1, y1, z1, k.wall)
            // window bands: a strip on each side for every floor (glass towers: tall panes, a mullion each tile)
            let h = Terrain3D.step * Float(Terrain3D.storeyLevels)
            let e: Float = 0.02
            for s in s0..<s1 {
                let a = k.y(s) + h * (k.glass ? 0.12 : 0.3), b = k.y(s) + h * (k.glass ? 0.92 : 0.75)
                m.flat([x0 + 0.15, a, z1 + e], [x1 - 0.15, a, z1 + e], [x1 - 0.15, b, z1 + e], [x0 + 0.15, b, z1 + e], [0, 0, 1], k.window, shade: Mesh3D.shadeSouth)
                m.flat([x1 - 0.15, a, z0 - e], [x0 + 0.15, a, z0 - e], [x0 + 0.15, b, z0 - e], [x1 - 0.15, b, z0 - e], [0, 0, -1], k.window, shade: Mesh3D.shadeNorth)
                m.flat([x1 + e, a, z1 - 0.15], [x1 + e, a, z0 + 0.15], [x1 + e, b, z0 + 0.15], [x1 + e, b, z1 - 0.15], [1, 0, 0], k.window, shade: Mesh3D.shadeEast)
                m.flat([x0 - e, a, z0 + 0.15], [x0 - e, a, z1 - 0.15], [x0 - e, b, z1 - 0.15], [x0 - e, b, z0 + 0.15], [-1, 0, 0], k.window, shade: Mesh3D.shadeWest)
            }
            // stone piers between the windows (not on glass): a pier every other tile, the height of the tier
            if !k.glass {
                for xi in stride(from: 1, to: k.w, by: 2) {
                    let px = x0 + Float(xi)
                    m.box(px - 0.12, y0, z1, px + 0.12, y1, z1 + 0.06, k.wall, faces: [.south, .east, .west])
                    m.box(px - 0.12, y0, z0 - 0.06, px + 0.12, y1, z0, k.wall, faces: [.north, .east, .west])
                }
                for zi in stride(from: 1, to: k.d, by: 2) {
                    let pz = z0 + Float(zi)
                    m.box(x1, y0, pz - 0.12, x1 + 0.06, y1, pz + 0.12, k.wall, faces: [.east, .north, .south])
                    m.box(x0 - 0.06, y0, pz - 0.12, x0, y1, pz + 0.12, k.wall, faces: [.west, .north, .south])
                }
            }
            // a ledge (cornice) round the top of the tier
            if top { m.box(x0 - 0.15, y1 - 0.3, z0 - 0.15, x1 + 0.15, y1, z1 + 0.15, k.accent) }
            if k.crown {
                // a crown's sunburst: a gold chevron stripe up the middle of each side
                let cx = (x0 + x1) / 2, cz = (z0 + z1) / 2
                m.box(cx - 0.2, y0, z1, cx + 0.2, y1, z1 + 0.08, k.accent, faces: [.south, .east, .west])
                m.box(cx - 0.2, y0, z0 - 0.08, cx + 0.2, y1, z0, k.accent, faces: [.north, .east, .west])
                m.box(x1, y0, cz - 0.2, x1 + 0.08, y1, cz + 0.2, k.accent, faces: [.east, .north, .south])
                m.box(x0 - 0.08, y0, cz - 0.2, x0, y1, cz + 0.2, k.accent, faces: [.west, .north, .south])
            }
        }
    }
}
