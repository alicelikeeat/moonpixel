import Foundation

// National monuments, at their real size. A nation's capital raises great landmarks one after another as it
// grows: an imperial palace city in the manner of the Forbidden City, a colossal statue holding up a torch in
// the manner of the Statue of Liberty, a clock tower, an iron lattice tower, a great pyramid, a wooden pagoda.
// They are designs in those manners, not copies, but built to the real thing's measure: a tile is about 2 m
// across and a unit of height about 2 m, so the palace city is 961 m by 753 m inside a moat 52 m wide, the
// iron tower 330 m tall on a base 125 m square, the pyramid 230 m along each side and 146 m high.
//
// Each stands on real tiles - its walls, courts, water, gates and gardens are the world's own, walked through
// like any building - and its structures are modelled in 3D, piece by piece (each piece standing on the
// ground where it is, so a long wall follows the land), and painted standing up in 2D.

public enum MonumentKind: String, Codable, CaseIterable {
    case palace, liberty, clock, ironTower, pyramid, pagoda
    /// A landmark of a nation's own design: elements of the world's famous landmarks put together anew
    /// (Fusion.swift), with floors to live on, a lift, sky farms and an airstrip.
    case fusion

    /// The six of the world's famous kinds.
    public static let classic: [MonumentKind] = [.palace, .liberty, .clock, .ironTower, .pyramid, .pagoda]

    public func name(zh: Bool) -> String {
        switch self {
        case .palace: return zh ? "宫城" : "Palace City"
        case .liberty: return zh ? "自由之像" : "Statue of Freedom"
        case .clock: return zh ? "钟楼" : "Clock Tower"
        case .ironTower: return zh ? "铁塔" : "Iron Tower"
        case .pyramid: return zh ? "金字塔" : "Pyramid"
        case .pagoda: return zh ? "宝塔" : "Pagoda"
        case .fusion: return zh ? "奇观" : "Wonder"
        }
    }
    /// The ground it takes, tiles (a tile is about 2 m).
    public var size: (w: Int, d: Int) {
        switch self {
        case .palace: return (Palace.W, Palace.D)
        case .liberty: return (160, 160)
        case .clock: return (30, 30)
        case .ironTower: return (100, 100)
        case .pyramid: return (140, 140)
        case .pagoda: return (44, 44)
        case .fusion: return (FusionDesign.plot, FusionDesign.plot)
        }
    }
    /// How tall it stands, units (about 2 m each).
    public var height: Double {
        switch self {
        case .palace: return 19
        case .liberty: return 46.5
        case .clock: return 48
        case .ironTower: return 165
        case .pyramid: return 73
        case .pagoda: return 34
        case .fusion: return 60
        }
    }
    /// What it costs the capital (stone, wood).
    public var cost: (stone: Double, wood: Double) {
        switch self {
        case .palace: return (90, 70)
        case .liberty: return (60, 10)
        case .clock: return (60, 20)
        case .ironTower: return (40, 10)
        case .pyramid: return (100, 10)
        case .pagoda: return (30, 60)
        case .fusion: return (80, 60)
        }
    }
    /// The order a nation builds them in (each nation its own, so capitals differ).
    public static func order(nation n: Int) -> [MonumentKind] {
        switch (max(1, n) - 1) % 3 {
        case 0: return [.palace, .pagoda, .clock, .pyramid]
        case 1: return [.liberty, .ironTower, .clock, .pagoda]
        default: return [.clock, .pyramid, .liberty, .ironTower]
        }
    }
}

public struct Monument: Codable, Equatable {
    public var id = 0
    public var kind = MonumentKind.palace
    public var nation = 0, town = 0
    public var x = 0, y = 0, w = 0, d = 0
    public var built = 0.0
    /// The height its ground was levelled to (elevation), so the halls, courts and walls stand level.
    public var ground: Double?
    /// The nation that raised it (the holder, `nation`, may since have taken it).
    public var builder: Int?
    /// A landmark of a nation's own design: what it is made of.
    public var design: FusionDesign?
    /// Its name: the kind's, or its own for a landmark of a nation's design.
    public func title(zh: Bool) -> String { design?.name(zh: zh) ?? kind.name(zh: zh) }
    /// How tall it stands, units.
    public var height: Double { design.map { Double($0.totalHeight) } ?? kind.height }
    public init() {}
    public var center: TilePos { TilePos(x + w / 2, y + d / 2) }
}

/// The palace city's plan, tiles from the north-west corner of its moat: x east, z south.
public enum Palace {
    public static let moat = 26, wall = 5
    /// Inside the moat: 376 tiles (753 m) east to west, 480 (961 m) north to south.
    public static let W = 376 + 2 * moat, D = 480 + 2 * moat
    public static let cx = W / 2
    public static let wallW = moat, wallE = W - moat, wallN = moat, wallS = D - moat
    public struct R { public let x: Int, z: Int, w: Int, d: Int }
    // along the axis, south to north
    public static let meridianGate = R(x: cx - 30, z: wallS - 16, w: 60, d: 18)
    public static let goldenStream = R(x: cx - 60, z: 452, w: 120, d: 4)
    public static let harmonyGate = R(x: cx - 18, z: 418, w: 36, d: 22)
    public static let outerCourt = R(x: cx - 34, z: 206, w: 68, d: 126)            // the great three-tier terrace
    public static let outerHalls: [(R, Float, Float, Bool)] = [                       // hall, column height, roof, double
        (R(x: cx - 16, z: 298, w: 32, d: 18), 6.5, 6.2, true),                        // the Hall of Supreme Harmony, 64 x 37 m
        (R(x: cx - 6, z: 268, w: 12, d: 12), 5.5, 4.5, false),                        // the square hall between
        (R(x: cx - 12, z: 230, w: 24, d: 12), 6, 5.2, true),                          // the hall behind
    ]
    public static let yard = R(x: cx - 100, z: 206, w: 200, d: 234)                    // the outer courtyard, galleries round it
    public static let purityGate = R(x: cx - 14, z: 186, w: 28, d: 14)
    public static let innerCourt = R(x: cx - 30, z: 106, w: 60, d: 76)
    public static let innerHalls: [(R, Float, Float, Bool)] = [
        (R(x: cx - 12, z: 160, w: 24, d: 12), 5.5, 5, true),
        (R(x: cx - 4, z: 142, w: 8, d: 8), 4, 3.5, false),
        (R(x: cx - 12, z: 116, w: 24, d: 12), 5.5, 5, true),
    ]
    public static let innerWall = R(x: cx - 62, z: 92, w: 124, d: 100)
    public static let garden = R(x: cx - 60, z: 42, w: 120, d: 46)
    public static let northGate = R(x: cx - 17, z: wallN - 4, w: 34, d: 14)
    public static let eastGate = R(x: wallE - 9, z: 410, w: 14, d: 24), westGate = R(x: wallW - 5, z: 410, w: 14, d: 24)
    public static let towers = [R(x: wallW - 4, z: wallN - 4, w: 14, d: 14), R(x: wallE - 10, z: wallN - 4, w: 14, d: 14),
                                R(x: wallW - 4, z: wallS - 10, w: 14, d: 14), R(x: wallE - 10, z: wallS - 10, w: 14, d: 14)]
    /// The courtyard houses of the east and west palaces: a walled court with a hall at its north side.
    public static let courts: [R] = {
        var out: [R] = []
        for z in stride(from: 40, through: wallS - 34, by: 28) where !(z + 22 > 404 && z < 440) {
            for x in [wallW + 12, wallW + 46] { out.append(R(x: x, z: z, w: 30, d: 22)) }
            for x in [wallE - 42, wallE - 76] { out.append(R(x: x, z: z, w: 30, d: 22)) }
        }
        return out
    }()
}

extension Society {
    /// How many monuments a capital raises: one at first, another for every 40 people, four at most.
    public static func monumentsAllowed(_ people: Int) -> Int { min(4, 1 + people / 40) }

    /// Once a day: each capital that may raise another monument, and has the stone and wood, raises the next.
    func monumentDay() {
        for n in realm.nations where n.exileSince == nil {
            guard let s = capital(of: n.id), !s.abandoned else { continue }
            let have = (realm.monuments ?? []).filter { $0.town == s.id }
            guard have.count < Society.monumentsAllowed(s.members.count), world.time >= (realm.cool["monument-\(n.id)"] ?? 0) else { continue }
            let order = MonumentKind.order(nation: n.id)
            guard let kind = order.first(where: { k in !have.contains { $0.kind == k } }) else { continue }
            let c = kind.cost
            guard s.stone >= c.stone, s.wood >= c.wood else { continue }
            guard let m = raiseMonument(kind, near: s, nation: n.id) else { realm.cool["monument-\(n.id)"] = world.time + MP.daySeconds; continue }
            s.stone -= c.stone; s.wood -= c.wood
            realm.cool["monument-\(n.id)"] = world.time + 2 * MP.daySeconds
            emit("monument", [n.name(zh: zh), s.name(zh: zh), m.title(zh: zh)], m.center.center)
        }
    }

    /// Raise a monument by a town, outside it on open land: its tiles laid now. Returns it, or nil when there is
    /// no room within reach.
    @discardableResult public func raiseMonument(_ kind: MonumentKind, near s: Settlement, nation: Int, seed: Int? = nil) -> Monument? {
        let (w, d) = kind.size
        let others = realm.monuments ?? []
        let half = Double(max(w, d)) / 2
        let start = Double(realm.cfg.cityRadius) + half + 30
        let turn = Double(MP.h2(world.seed, s.id, kind.rawValue.count) % 1000) / 1000
        for ring in 0..<26 {
            let dist = start + Double(ring) * 40
            for k in 0..<12 {
                let a = (Double(k) + turn) / 12 * 2 * .pi
                let o = TilePos(s.center.x + Int(cos(a) * dist) - w / 2, s.center.y + Int(sin(a) * dist) - d / 2)
                guard monumentSiteClear(o, w, d, others: others) else { continue }
                var m = Monument()
                m.id = (others.map { $0.id }.max() ?? 0) + 1
                m.kind = kind; m.nation = nation; m.town = s.id; m.builder = nation
                if kind == .fusion { m.design = FusionDesign.make(seed: seed ?? Int(MP.h2(world.seed, s.id, others.count) % 1_000_000)) }
                m.x = o.x; m.y = o.y; m.w = w; m.d = d; m.built = world.time
                m.ground = levelFor(o, w, d)
                carveMonument(m)
                realm.monuments = others + [m]
                syncFlats()
                // the chunks round it are drawn again on the levelled ground
                for cy in OpenWorld.floorDiv(o.y - Generator.flatBlend, 32)...OpenWorld.floorDiv(o.y + d + Generator.flatBlend, 32) {
                    for cx in OpenWorld.floorDiv(o.x - Generator.flatBlend, 32)...OpenWorld.floorDiv(o.x + w + Generator.flatBlend, 32) { world.bump(cx, cy) }
                }
                return m
            }
        }
        return nil
    }

    /// The level a monument's ground is made: the land's middle height there, kept above the water and below
    /// the high mountains.
    func levelFor(_ o: TilePos, _ w: Int, _ d: Int) -> Double {
        var es: [Double] = []
        for y in stride(from: o.y, through: o.y + d, by: 8) { for x in stride(from: o.x, through: o.x + w, by: 8) { es.append(world.gen.naturalElevation(x, y)) } }
        es.sort()
        let mid = es.isEmpty ? Biome.sea + 0.1 : es[es.count / 2]
        return min(max(mid, Biome.sea + 0.04), Biome.mountainLevel - 0.04)
    }

    /// Tell the land where it is levelled for monuments.
    func syncFlats() {
        world.gen.flats = (realm.monuments ?? []).map { m in
            Generator.Flat(x0: m.x, y0: m.y, x1: m.x + m.w - 1, y1: m.y + m.d - 1, e: m.ground ?? levelFor(TilePos(m.x, m.y), m.w, m.d))
        }
    }

    /// Open land for a monument: clear of the towns, districts and other monuments, mostly dry, and with no
    /// road or railway across it. The ground under it is levelled (hills, a volcano's
    /// slope, a stretch of shore), and a UFO airport there gives way.
    func monumentSiteClear(_ o: TilePos, _ w: Int, _ d: Int, others: [Monument]) -> Bool {
        if others.contains(where: { $0.x < o.x + w + 6 && o.x < $0.x + $0.w + 6 && $0.y < o.y + d + 6 && o.y < $0.y + $0.d + 6 }) { return false }
        func away(_ c: TilePos, _ r: Double) -> Bool {
            let nx = min(max(c.x, o.x), o.x + w), ny = min(max(c.y, o.y), o.y + d)
            let dx = Double(c.x - nx), dy = Double(c.y - ny)
            return (dx * dx + dy * dy).squareRoot() > r
        }
        let townR = Double(realm.cfg.cityRadius) + 25
        if settlements.values.contains(where: { !$0.abandoned && !away($0.center, townR) }) { return false }
        if net.districts.contains(where: { !away($0.center, Double($0.radius) + 10) }) { return false }
        // the lie of the land, sampled: mostly dry, not in the high mountains
        let gen = world.gen
        var wet = 0, high = 0, n = 0
        for y in stride(from: o.y, through: o.y + d, by: 8) { for x in stride(from: o.x, through: o.x + w, by: 8) {
            let e = gen.naturalElevation(x, y)
            if e < Biome.sea { wet += 1 }
            if e > Biome.mountainLevel + 0.08 { high += 1 }
            n += 1
        } }
        if wet * 4 > n || high * 10 > n { return false }
        // no road, railway, runway or quay is cut for it (the old ruins, a saucer port or a stair down to an
        // underground city there are built over)
        let ways: Set<UInt8> = Set(["path", "cobble_road", "road_asphalt", "highway", "rail", "rail_hsr", "runway", "taxiway", "apron", "quay",
                                    "parking", "platform", "bridge_road", "bridge_rail", "bridge_lift", "bridge_foot", "bridge_wood", "bridge_stone"].map { content.tid($0) })
        // only land already made can have a road on it: chunks never generated are skipped (looking would make
        // them, thousands of them for a palace's search, and stall the game)
        for cy in OpenWorld.floorDiv(o.y, 32)...OpenWorld.floorDiv(o.y + d, 32) { for cx in OpenWorld.floorDiv(o.x, 32)...OpenWorld.floorDiv(o.x + w, 32) {
            guard let c = world.peekStored(MP.chunkKey(cx, cy)) else { continue }
            let g = c.layers[0]
            for ly in 0..<32 { for lx in 0..<32 {
                let x = cx * 32 + lx, y = cy * 32 + ly
                guard x >= o.x, x <= o.x + w, y >= o.y, y <= o.y + d else { continue }
                if ways.contains(g[ly * 32 + lx]) { return false }
            } }
        } }
        return true
    }

    /// A UFO airport is open unless a monument has been built over its pad.
    public func ufoPortOpen(_ cx: Int, _ cy: Int) -> Bool {
        guard world.gen.isUfoPort(cx, cy) else { return false }
        let px = cx * 32 + 15, py = cy * 32 + 13
        return !(realm.monuments ?? []).contains { px >= $0.x - 2 && px <= $0.x + $0.w + 2 && py >= $0.y - 2 && py <= $0.y + $0.d + 2 }
    }

    /// The monuments within `reach` tiles of a tile (measured to their nearest edge).
    public func monuments(near t: TilePos, reach: Int) -> [Monument] {
        (realm.monuments ?? []).filter { t.x >= $0.x - reach && t.x <= $0.x + $0.w + reach && t.y >= $0.y - reach && t.y <= $0.y + $0.d + reach }
    }

    /// The tiles of a monument: what can be walked on and through.
    func carveMonument(_ m: Monument) {
        let T = { (k: String) in self.content.tid(k) }
        let water = T("shallow_water"), stone = T("stone_floor"), brick = T("wall_brick"), grass = T("grass"), wood = T("wood_floor")
        func set(_ x: Int, _ y: Int, ground: UInt8? = nil, obj: UInt8? = nil, decor: UInt8? = nil) {
            let wx = m.x + x, wy = m.y + y
            if let g = ground { world.setTile(0, wx, wy, g) }
            if let o = obj { world.setTile(2, wx, wy, o) }
            if let d = decor { world.setTile(3, wx, wy, d) }
        }
        func fill(_ x0: Int, _ z0: Int, _ w: Int, _ d: Int, ground: UInt8? = nil, obj: UInt8? = nil) {
            for z in z0..<(z0 + d) { for x in x0..<(x0 + w) { set(x, z, ground: ground, obj: obj) } }
        }
        /// A walled room: walls round, a floor inside, a door in the middle of its south side.
        func room(_ x0: Int, _ z0: Int, _ w: Int, _ d: Int, wall: UInt8, floor: UInt8, door: UInt8 = T("door_wood"), windows: Bool = false) {
            for z in z0..<(z0 + d) { for x in x0..<(x0 + w) {
                let edge = x == x0 || z == z0 || x == x0 + w - 1 || z == z0 + d - 1
                let front = z == z0 + d - 1
                set(x, z, ground: floor, obj: edge ? (front && x == x0 + w / 2 ? door : (front && windows && (x - x0) % 3 == 1 ? T("wall_glass") : wall)) : 0)
            } }
        }
        // clear the ground first: nothing natural stays on it
        for y in 0..<m.d { for x in 0..<m.w { world.setTile(1, m.x + x, m.y + y, 0); world.setTile(2, m.x + x, m.y + y, 0); world.setTile(3, m.x + x, m.y + y, 0) } }
        let w = m.w, d = m.d, cx = w / 2
        switch m.kind {
        case .palace:
            typealias P = Palace
            fill(0, 0, w, d, ground: water)
            fill(P.wallW, P.wallN, P.wallE - P.wallW, P.wallS - P.wallN, ground: stone)
            fill(cx - 6, P.wallS, 13, P.moat, ground: stone); fill(cx - 6, 0, 13, P.moat, ground: stone)          // the bridges
            // the red wall round, with gates south, north, east and west
            for z in P.wallN..<P.wallS { for x in P.wallW..<P.wallE {
                let inWall = x < P.wallW + P.wall || x >= P.wallE - P.wall || z < P.wallN + P.wall || z >= P.wallS - P.wall
                guard inWall else { continue }
                let southGate = z >= P.wallS - P.wall && abs(x - cx) <= 4, northGate = z < P.wallN + P.wall && abs(x - cx) <= 4
                let sideGate = (x < P.wallW + P.wall || x >= P.wallE - P.wall) && abs(z - 422) <= 3
                if southGate || northGate || sideGate {
                    let mid = southGate ? z == P.wallS - 3 : (northGate ? z == P.wallN + 2 : (x == P.wallW + 2 || x == P.wallE - 3))
                    set(x, z, obj: mid ? T("gate_open") : 0)
                } else { set(x, z, obj: brick) }
            } }
            // the golden stream across the outer court, bridged on the axis
            fill(P.goldenStream.x, P.goldenStream.z, P.goldenStream.w, P.goldenStream.d, ground: water)
            fill(cx - 12, P.goldenStream.z, 25, P.goldenStream.d, ground: stone)
            // the galleries round the outer courtyard and the inner court's wall
            for r in [P.yard, P.innerWall] {
                for x in r.x..<(r.x + r.w) where abs(x - cx) > 18 { set(x, r.z, obj: brick); set(x, r.z + r.d - 1, obj: brick) }
                for z in r.z..<(r.z + r.d) where abs(z - 422) > 3 { set(r.x, z, obj: brick); set(r.x + r.w - 1, z, obj: brick) }
            }
            // the halls: each a walled room with a throne, the great ones with windows across their front
            for (r, _, _, _) in P.outerHalls + P.innerHalls {
                room(r.x, r.z, r.w, r.d, wall: brick, floor: wood, windows: r.w > 12)
                set(cx, r.z + 2, obj: T("throne"))
            }
            for r in [P.harmonyGate, P.purityGate] { room(r.x + 4, r.z + 4, r.w - 8, r.d - 8, wall: brick, floor: stone, door: T("gate_open")) }
            for r in [P.meridianGate, P.northGate] { fill(r.x + 3, r.z + 2, r.w - 6, 1, obj: brick) }
            // lanterns down the axis, guardian lions by the gate, the imperial garden
            for z in stride(from: 340, to: 416, by: 12) { set(cx - 8, z, obj: T("lantern_post")); set(cx + 8, z, obj: T("lantern_post")) }
            set(cx - 10, 442, obj: T("statue")); set(cx + 10, 442, obj: T("statue"))
            let g = P.garden
            fill(g.x, g.z, g.w, g.d, ground: grass)
            for z in stride(from: g.z + 3, to: g.z + g.d - 2, by: 7) { for x in stride(from: g.x + 3, to: g.x + g.w - 2, by: 9) where abs(x - cx) > 8 {
                set(x, z, obj: (x + z) % 2 == 0 ? T("tree_pine") : T("tree_oak"))
                set(x + 2, z + 1, decor: (x / 9) % 2 == 0 ? T("flower_red") : T("flower_yellow"))
            } }
            fill(cx - 2, g.z, 5, g.d, ground: stone)
            // the courtyard houses of the east and west palaces
            for r in P.courts {
                for x in r.x..<(r.x + r.w) { set(x, r.z, obj: brick); set(x, r.z + r.d - 1, obj: x == r.x + r.w / 2 ? T("gate_open") : brick) }
                for z in r.z..<(r.z + r.d) { set(r.x, z, obj: brick); set(r.x + r.w - 1, z, obj: brick) }
                room(r.x + 6, r.z + 3, 18, 7, wall: brick, floor: wood)
                set(r.x + 4, r.z + 15, obj: T("tree_pine")); set(r.x + r.w - 5, r.z + 15, obj: T("tree_pine"))
            }
            keepClear(TilePos(m.x + cx, m.y + d)); keepClear(TilePos(m.x + cx, m.y))
        case .liberty:
            // an island: water round, a pier from the south; lawns and paths; the star-shaped fort with the
            // pedestal at its heart
            let c = Double(w - 1) / 2
            for y in 0..<d { for x in 0..<w {
                let dx = Double(x) - c, dy = Double(y) - c, r = (dx * dx + dy * dy).squareRoot()
                let a = atan2(dy, dx)
                let shore = 66 + 6 * sin(a * 3 + 0.7)
                if r > shore { set(x, y, ground: water); continue }
                if r > shore - 3 { set(x, y, ground: T("sand")); continue }
                set(x, y, ground: r < 30 ? stone : grass)
                let star = LibertyPlan.starRadius(a)
                if abs(r - star) < 1.2 && r > 14 { set(x, y, obj: T("wall_stone")) }
                if r > 34 && r < shore - 6 && Int(r) % 9 == 0 && Int((a + .pi) * 30) % 7 == 0 { set(x, y, obj: T("tree_oak")) }
            } }
            room(cx - 5, cx - 5, 10, 10, wall: T("wall_stone"), floor: stone)
            set(cx - 1, cx - 2, obj: T("statue")); set(cx + 1, cx - 2, obj: T("stairs_up"))
            for y in (cx + 5)..<d { set(cx, y, ground: stone); set(cx - 1, y, ground: stone); set(cx + 1, y, ground: stone); set(cx, y, obj: 0) }
            for y in stride(from: cx + 30, to: d - 4, by: 8) { set(cx - 3, y, obj: T("lantern_post")); set(cx + 3, y, obj: T("lantern_post")) }
            keepClear(TilePos(m.x + cx, m.y + d))
        case .clock:
            fill(0, 0, w, d, ground: grass)
            fill(8, 8, 14, 14, ground: stone); fill(cx - 1, 22, 3, d - 22, ground: stone)
            room(12, 12, 6, 6, wall: T("wall_limestone"), floor: stone)
            set(14, 14, obj: T("stairs_up"))
            for (x, y) in [(8, 8), (21, 8), (8, 21), (21, 21)] { set(x, y, obj: T("lantern_post")) }
            for (x, y) in [(3, 3), (26, 3), (3, 26), (26, 26)] { set(x, y, obj: T("tree_oak")) }
        case .ironTower:
            // a lawn with paths to the four feet, each foot on its pier
            for y in 0..<d { for x in 0..<w {
                let path = abs(x - y) <= 1 || abs(x + y - (w - 1)) <= 1 || abs(x - cx) <= 1 || abs(y - d / 2) <= 1
                set(x, y, ground: path ? stone : grass)
            } }
            for (fx, fy) in IronTowerPlan.feet { fill(Int(fx) - 4, Int(fy) - 4, 9, 9, ground: stone, obj: T("spire_steel")) }
            for (x, y) in [(4, 4), (w - 5, 4), (4, d - 5), (w - 5, d - 5), (cx - 12, 6), (cx + 12, 6)] { set(x, y, obj: T("tree_oak")) }
        case .pyramid:
            // sand round a pyramid of limestone blocks, a passage from the south into the chamber at its heart
            fill(0, 0, w, d, ground: T("sand"))
            let p0 = PyramidPlan.inset, p1 = w - PyramidPlan.inset
            for y in p0..<p1 { for x in p0..<p1 {
                let passage = abs(x - cx) <= 1 && y > d / 2
                let chamber = abs(x - cx) <= 3 && abs(y - d / 2) <= 3
                set(x, y, ground: stone, obj: passage || chamber ? 0 : T("wall_limestone"))
            } }
            set(cx, d / 2, obj: T("chest"))
        case .pagoda:
            fill(0, 0, w, d, ground: grass)
            for y in 0..<d { for x in 0..<w {
                let dx = Double(x) - Double(cx), dy = Double(y) - Double(d / 2), r = (dx * dx + dy * dy).squareRoot()
                if r < 11 { set(x, y, ground: stone) }
                if abs(r - 7.5) < 0.6 { set(x, y, ground: wood, obj: T("wall_wood")) } else if r < 7 { set(x, y, ground: wood) }
            } }
            set(cx, d / 2 + 7, obj: T("door_wood")); set(cx, d / 2 + 8, obj: 0)
            set(cx, d / 2, obj: T("altar")); set(cx + 3, d / 2 - 2, obj: T("stairs_up"))
            fill(cx - 1, d / 2 + 9, 3, d - d / 2 - 9, ground: stone)
            for (x, y) in [(4, 4), (w - 5, 4), (4, d - 5), (w - 5, d - 5), (cx - 12, cx + 14), (cx + 12, cx + 14)] { set(x, y, obj: T("tree_pine")) }
            set(cx - 3, d - 4, obj: T("lantern_post")); set(cx + 3, d - 4, obj: T("lantern_post"))
        case .fusion:
            carveFusion(m)
        }
    }
}

enum LibertyPlan {
    /// The star fort's outline: eleven points, 25 tiles out at a point, 15 between.
    static func starRadius(_ a: Double) -> Double {
        let k = 11.0, u = ((a / (2 * .pi) * k).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        return 15 + 10 * (1 - abs(u - 0.5) * 2)
    }
}

enum IronTowerPlan {
    static let c: Float = 50, foot: Float = 27, p1 = (y: Float(28.5), half: Float(17.5)), p2 = (y: Float(57.5), half: Float(10)), top = (y: Float(138), half: Float(2.5))
    static var feet: [(Float, Float)] { [(c - foot, c - foot), (c + foot, c - foot), (c - foot, c + foot), (c + foot, c + foot)] }
}

enum PyramidPlan { static let inset = 12 }

// MARK: - modelling

extension Mesh3D {
    /// Another mesh added to this one, moved by `off`.
    public mutating func add(_ o: Mesh3D, at off: SIMD3<Float>) {
        let base = UInt32(positions.count)
        positions.append(contentsOf: o.positions.map { $0 + off })
        normals.append(contentsOf: o.normals); uvs.append(contentsOf: o.uvs)
        indices.append(contentsOf: o.indices.map { $0 + base })
    }

    /// A hip roof over the rectangle x0...x1, z0...z1 from eave height `y0` up `h` to a ridge, overhanging by `o`;
    /// `curl` lifts the corners of the eaves and lets the middle of each long eave sag (a Chinese roof). On a
    /// square the ridge closes to a point (a pyramid roof).
    public mutating func hipRoof(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float, y0: Float, h: Float, o: Float, curl: Float = 0, _ c: RGBA) {
        let a = SIMD3<Float>(x0 - o, y0 + curl, z0 - o), b = SIMD3<Float>(x1 + o, y0 + curl, z0 - o)
        let cc = SIMD3<Float>(x1 + o, y0 + curl, z1 + o), dd = SIMD3<Float>(x0 - o, y0 + curl, z1 + o)
        let inset = min(x1 - x0, z1 - z0) / 2
        let r0 = SIMD3<Float>(x0 + inset, y0 + h, (z0 + z1) / 2), r1 = SIMD3<Float>(x1 - inset, y0 + h, (z0 + z1) / 2)
        let m1 = SIMD3<Float>((x0 + x1) / 2, y0, z1 + o), m0 = SIMD3<Float>((x0 + x1) / 2, y0, z0 - o)
        // the front (south) and back (north), each fanned from its sagging middle; the hipped ends
        tri(dd, m1, r0, c); tri(m1, r1, r0, c); tri(m1, cc, r1, c)
        tri(b, m0, r1, c); tri(m0, r0, r1, c); tri(m0, a, r0, c)
        tri(a, dd, r0, c); tri(cc, b, r1, c)
        // the underside of the eaves, dark, so the roof is seen from below too
        face(a, b, cc, dd, c.darkened(0.4))
    }

    /// A box from below the ground (so a piece on a slope never floats) up to `y1`.
    mutating func footed(_ x0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: RGBA) {
        box(x0, -4, z0, x1, y1, z1, c, faces: .all)
    }

    /// A tree: a trunk and a rounded crown, `h` units tall.
    mutating func tree(_ x: Float, _ z: Float, h: Float, pine: Bool) {
        frustum(SIMD3(x, -0.5, z), SIMD3(x, h * 0.45, z), h * 0.06, h * 0.045, RGBA(110, 78, 50), seg: 6)
        if pine {
            for k in 0..<3 { let y = h * (0.35 + Float(k) * 0.2); frustum(SIMD3(x, y, z), SIMD3(x, y + h * 0.35, z), h * (0.3 - Float(k) * 0.07), 0, RGBA(48, 110, 70), seg: 8) }
        } else {
            ellipsoid(SIMD3(x, h * 0.68, z), SIMD3(h * 0.32, h * 0.3, h * 0.32), RGBA(84, 150, 70), seg: 10, rings: 6)
        }
    }
}

/// A piece of a monument, modelled on its own and placed on the ground where it stands.
public struct MonumentPiece {
    /// Shared by every piece built alike (the 3D view makes each model once).
    public let key: String
    /// Its footprint, tiles from the monument's corner.
    public let x: Float, z: Float, w: Float, d: Float
    public let mesh: () -> Mesh3D
}

/// Something of a monument painted standing up in the flat view: its picture, `w` tiles wide and `h` tall,
/// its foot centred at (x, z) tiles from the monument's corner.
public struct MonumentSprite {
    public let key: String
    public let x: Float, z: Float, w: Float, h: Float
    public let draw: (_ ppt: Double) -> Bitmap
}

extension Figure3D {
    public static let red = RGBA(178, 40, 36), gold = RGBA(236, 180, 50), marble = RGBA(236, 234, 226), pillar = RGBA(150, 28, 28)
    static let beam = RGBA(40, 96, 120)

    /// A Chinese hall `w` by `d` tiles (its origin the corner of its terrace): a white terrace `terrace` high
    /// (in `tiers` steps), red walls and a row of columns along the front `col` high, the painted beam band,
    /// and a golden roof `roof` high, single or double-eaved.
    public static func hall(w: Float, d: Float, terrace: Float, tiers: Int = 1, margin: Float = 2, col: Float, roof: Float, double: Bool, roofColor: RGBA = gold) -> Mesh3D {
        var m = Mesh3D()
        let step = terrace / Float(max(1, tiers))
        for k in 0..<max(1, tiers) {
            let i = Float(k) * margin / Float(max(1, tiers))
            m.box(i, k == 0 ? -4 : Float(k) * step, i, w - i, Float(k + 1) * step, d - i, marble, faces: .all)
        }
        let x0 = margin, z0 = margin, x1 = w - margin, z1 = d - margin, y0 = terrace
        // the front steps, in the middle of the south side
        for s in 0..<4 { let t = Float(s) / 4; m.box(w / 2 - 3, 0, z1 + margin * (1 - t) - 0.01, w / 2 + 3, y0 * (t + 0.25), z1 + margin, marble.darkened(0.04), faces: .all) }
        m.box(x0 + 0.8, y0, z0 + 0.8, x1 - 0.8, y0 + col, z1 - 0.8, red, faces: .all)
        var x = x0 + 0.5
        while x <= x1 - 0.4 { m.frustum(SIMD3(x, y0, z1 - 0.3), SIMD3(x, y0 + col, z1 - 0.3), 0.42, 0.38, pillar, seg: 8); x += 2.4 }
        m.box(x0, y0 + col, z0, x1, y0 + col + 0.8, z1, beam, faces: .all)
        let top = y0 + col + 0.8
        if double {
            m.hipRoof(x0, z0, x1, z1, y0: top, h: roof * 0.22, o: 2.0, curl: 0.55, roofColor.darkened(0.05))
            m.box(x0 + 1.6, top + roof * 0.12, z0 + 1.6, x1 - 1.6, top + roof * 0.32, z1 - 1.6, red, faces: .all)
            m.box(x0 + 1.4, top + roof * 0.32, z0 + 1.4, x1 - 1.4, top + roof * 0.38, z1 - 1.4, beam, faces: .all)
            m.hipRoof(x0 + 1.4, z0 + 1.4, x1 - 1.4, z1 - 1.4, y0: top + roof * 0.38, h: roof * 0.62, o: 2.2, curl: 0.7, roofColor)
        } else {
            m.hipRoof(x0, z0, x1, z1, y0: top, h: roof, o: 2.0, curl: 0.55, roofColor)
        }
        // the beasts at the ends of the ridge, or a gilded finial on a pointed roof
        let inset = min(x1 - x0, z1 - z0) / 2
        if x1 - x0 > z1 - z0 + 1 {
            for ex in [x0 + inset, x1 - inset] { m.box(ex - 0.35, top + roof - 0.1, (z0 + z1) / 2 - 0.3, ex + 0.35, top + roof + 0.9, (z0 + z1) / 2 + 0.3, roofColor.darkened(0.2), faces: .all) }
        } else {
            m.frustum(SIMD3(w / 2, top + roof - 0.2, d / 2), SIMD3(w / 2, top + roof + 1.2, d / 2), 0.35, 0.05, RGBA(250, 210, 90), seg: 6)
        }
        return m
    }

    /// A gate tower: a red platform `base` high with three arched openings through it, a hall on top.
    static func gateTower(w: Float, d: Float, base: Float, hallW: Float, hallD: Float, col: Float, roof: Float) -> Mesh3D {
        var m = Mesh3D()
        m.footed(0, 0, w, base, d, red)
        m.box(-0.2, base, -0.2, w + 0.2, base + 0.4, d + 0.2, gold.darkened(0.15), faces: .all)
        for k in [-1, 0, 1] as [Float] {
            let ax = w / 2 + k * w * 0.22, aw: Float = k == 0 ? 2.4 : 1.8
            m.box(ax - aw, 0, d - 0.05, ax + aw, base * 0.55, d + 0.05, RGBA(40, 26, 24), faces: .all)
            m.box(ax - aw, 0, -0.05, ax + aw, base * 0.55, 0.05, RGBA(40, 26, 24), faces: .all)
        }
        m.add(hall(w: hallW + 4, d: hallD + 4, terrace: 0.3, col: col, roof: roof, double: true), at: SIMD3((w - hallW) / 2 - 2, base, (d - hallD) / 2 - 2))
        return m
    }

    /// The palace's pieces.
    static func palacePieces() -> [MonumentPiece] {
        typealias P = Palace
        var out: [MonumentPiece] = []
        func piece(_ key: String, _ r: Palace.R, _ make: @escaping () -> Mesh3D) { out.append(MonumentPiece(key: key, x: Float(r.x), z: Float(r.z), w: Float(r.w), d: Float(r.d), mesh: make)) }
        // the red walls, a piece every 48 tiles along each side, crenellated on the outside, capped in gold
        func wall(_ w: Int, _ d: Int, outside: Int) -> Mesh3D {
            var m = Mesh3D()
            m.footed(0, 0, Float(w), 5, Float(d), red)
            m.box(-0.3, 5, -0.3, Float(w) + 0.3, 5.5, Float(d) + 0.3, gold.darkened(0.12), faces: .all)
            let along = w > d
            let n = (along ? w : d) / 2
            for i in 0..<n {
                let t = Float(i * 2) + 0.5
                let (bx, bz): (Float, Float) = along ? (t, outside == 0 ? 0 : Float(d) - 0.6) : (outside == 0 ? 0 : Float(w) - 0.6, t)
                m.box(bx, 5.5, bz, bx + (along ? 1 : 0.6), 6.4, bz + (along ? 0.6 : 1), red.darkened(0.08), faces: .all)
            }
            return m
        }
        let L = 48
        for x in stride(from: P.wallW, to: P.wallE, by: L) {
            let len = min(L, P.wallE - x)
            piece("pwall-n\(len)", P.R(x: x, z: P.wallN, w: len, d: P.wall)) { wall(len, P.wall, outside: 0) }
            piece("pwall-s\(len)", P.R(x: x, z: P.wallS - P.wall, w: len, d: P.wall)) { wall(len, P.wall, outside: 1) }
        }
        for z in stride(from: P.wallN + P.wall, to: P.wallS - P.wall, by: L) {
            let len = min(L, P.wallS - P.wall - z)
            piece("pwall-w\(len)", P.R(x: P.wallW, z: z, w: P.wall, d: len)) { wall(P.wall, len, outside: 0) }
            piece("pwall-e\(len)", P.R(x: P.wallE - P.wall, z: z, w: P.wall, d: len)) { wall(P.wall, len, outside: 1) }
        }
        // the corner towers: crossed roofs under a pointed one, on the wall's corner
        for r in P.towers {
            piece("ptower", r) {
                var m = Mesh3D()
                m.footed(1, 1, 13, 5, 13, red)
                m.box(3, 5, 3, 11, 10, 11, red, faces: .all)
                m.box(2.6, 9.6, 2.6, 11.4, 10.2, 11.4, beam, faces: .all)
                m.hipRoof(2, 4.5, 12, 9.5, y0: 10.2, h: 2.4, o: 1.0, curl: 0.4, gold)
                m.hipRoof(4.5, 2, 9.5, 12, y0: 10.2, h: 2.4, o: 1.0, curl: 0.4, gold)
                m.hipRoof(5, 5, 9, 9, y0: 11.8, h: 2.6, o: 0.8, curl: 0.3, gold)
                return m
            }
        }
        piece("pmeridian", P.meridianGate) {
            var m = gateTower(w: 60, d: 18, base: 6, hallW: 32, hallD: 10, col: 5, roof: 7)
            // the pavilions on its wings
            for px: Float in [3, 49] { m.add(hall(w: 8, d: 8, terrace: 0.2, margin: 1, col: 3, roof: 3, double: false), at: SIMD3(px, 6, 1)) }
            return m
        }
        piece("pnorthgate", P.northGate) { gateTower(w: 34, d: 14, base: 5.5, hallW: 24, hallD: 7, col: 4, roof: 5) }
        piece("psidegate", P.eastGate) { gateTower(w: 14, d: 24, base: 5, hallW: 8, hallD: 16, col: 3.5, roof: 3.5) }
        piece("psidegate", P.westGate) { gateTower(w: 14, d: 24, base: 5, hallW: 8, hallD: 16, col: 3.5, roof: 3.5) }
        piece("pharmonygate", P.harmonyGate) { hall(w: 36, d: 22, terrace: 2, tiers: 1, col: 5, roof: 5, double: true) }
        piece("ppuritygate", P.purityGate) { hall(w: 28, d: 14, terrace: 1.5, col: 4.5, roof: 4, double: false) }
        // the great terrace with its three halls; the inner court's terrace with its three
        func court(_ r: Palace.R, terrace: Float, tiers: Int, halls: [(Palace.R, Float, Float, Bool)]) -> () -> Mesh3D {
            return {
                var m = Mesh3D()
                for k in 0..<tiers {
                    let i = Float(k) * 2.2, step = terrace / Float(tiers)
                    m.box(i, k == 0 ? -4 : Float(k) * step, i, Float(r.w) - i, Float(k + 1) * step, Float(r.d) - i, marble, faces: .all)
                    // a balustrade along each tier
                    m.box(i, Float(k + 1) * step, i, Float(r.w) - i, Float(k + 1) * step + 0.5, i + 0.25, marble.darkened(0.06), faces: .all)
                    m.box(i, Float(k + 1) * step, Float(r.d) - i - 0.25, Float(r.w) - i, Float(k + 1) * step + 0.5, Float(r.d) - i, marble.darkened(0.06), faces: .all)
                }
                // the carved ramp up the middle of the south side
                m.box(Float(r.w) / 2 - 2, 0, Float(r.d) - 0.5, Float(r.w) / 2 + 2, terrace * 0.7, Float(r.d) + 3, marble.darkened(0.1), faces: .all)
                for (h, col, roof, dbl) in halls {
                    let mk = hall(w: Float(h.w) + 4, d: Float(h.d) + 4, terrace: 1, col: col, roof: roof, double: dbl)
                    m.add(mk, at: SIMD3(Float(h.x - r.x) - 2, terrace, Float(h.z - r.z) - 2))
                }
                return m
            }
        }
        piece("pouter", P.outerCourt, court(P.outerCourt, terrace: 4, tiers: 3, halls: P.outerHalls))
        piece("pinner", P.innerCourt, court(P.innerCourt, terrace: 1.5, tiers: 1, halls: P.innerHalls))
        // the galleries: long low halls round the outer courtyard and the inner court
        func gallery(_ w: Int, _ d: Int) -> Mesh3D {
            var m = Mesh3D()
            m.footed(0, 0, Float(w), 0.4, Float(d), marble)
            m.box(0.3, 0.4, 0.3, Float(w) - 0.3, 3.2, Float(d) - 0.3, red, faces: .all)
            m.hipRoof(0.3, 0.3, Float(w) - 0.3, Float(d) - 0.3, y0: 3.2, h: 1.6, o: 0.9, curl: 0.2, gold)
            return m
        }
        for r in [P.yard, P.innerWall] {
            for x in stride(from: r.x, to: r.x + r.w, by: 40) {
                let len = min(40, r.x + r.w - x)
                for z in [r.z - 1, r.z + r.d - 3] where !(z > r.z && x < P.cx + 18 && x + len > P.cx - 18) {
                    piece("pgal-h\(len)", P.R(x: x, z: z, w: len, d: 4)) { gallery(len, 4) }
                }
            }
            for z in stride(from: r.z + 3, to: r.z + r.d - 3, by: 40) {
                let len = min(40, r.z + r.d - 3 - z)
                for x in [r.x - 1, r.x + r.w - 3] { piece("pgal-v\(len)", P.R(x: x, z: z, w: 4, d: len)) { gallery(4, len) } }
            }
        }
        // the courtyard houses
        for r in P.courts {
            piece("pcourt", r) {
                var m = Mesh3D()
                for (x0, z0, x1, z1) in [(0, 0, 30, 0.6), (0, 21.4, 13.5, 22), (16.5, 21.4, 30, 22), (0, 0, 0.6, 22), (29.4, 0, 30, 22)] as [(Float, Float, Float, Float)] {
                    m.footed(x0, z0, x1, 2.6, z1, red)
                    m.box(x0 - 0.2, 2.6, z0 - 0.2, x1 + 0.2, 3.0, z1 + 0.2, gold.darkened(0.1), faces: .all)
                }
                m.add(hall(w: 22, d: 11, terrace: 0.6, col: 3.5, roof: 3.2, double: false), at: SIMD3(4, 0, 1))
                m.tree(5, 16, h: 6, pine: true); m.tree(25, 16, h: 6, pine: true)
                return m
            }
        }
        // the imperial garden: old trees, two pavilions, a rockery
        piece("pgarden", P.garden) {
            var m = Mesh3D()
            for z in stride(from: Float(3), to: 44, by: 7) { for x in stride(from: Float(3), to: 118, by: 9) where abs(x - 60) > 8 { m.tree(x, z, h: Int(x + z) % 2 == 0 ? 9 : 7, pine: Int(x + z) % 2 == 0) } }
            for px: Float in [30, 84] { m.add(hall(w: 8, d: 8, terrace: 0.6, margin: 1, col: 2.6, roof: 2.6, double: false, roofColor: RGBA(70, 140, 110)), at: SIMD3(px, 0, 18)) }
            for (k, r) in [Float(3), 2.2, 1.6].enumerated() { m.ellipsoid(SIMD3(60 + Float(k) * 1.2, r * 0.8, 10 + Float(k)), SIMD3(r * 1.4, r, r * 1.2), RGBA(150, 146, 136), seg: 8, rings: 4) }
            return m
        }
        return out
    }

    /// A monument's pieces, each in tiles from its own corner, standing on y = 0 (with footings below).
    public static func monumentPieces(_ kind: MonumentKind) -> [MonumentPiece] {
        let (w, d) = kind.size
        let one = { (key: String, make: @escaping () -> Mesh3D) in [MonumentPiece(key: key, x: 0, z: 0, w: Float(w), d: Float(d), mesh: make)] }
        switch kind {
        case .palace: return palacePieces()
        case .liberty: return one("liberty", liberty)
        case .clock: return one("clock", clockTower)
        case .ironTower: return one("irontower", ironTower)
        case .pyramid: return one("pyramid", pyramid)
        case .pagoda: return one("pagoda", pagoda)
        case .fusion: return fusionPieces(FusionDesign.make(seed: 1))
        }
    }

    /// A monument's pieces (a landmark of a nation's own design by its design).
    public static func monumentPieces(for m: Monument) -> [MonumentPiece] {
        if m.kind == .fusion, let d = m.design { return fusionPieces(d) }
        return monumentPieces(m.kind)
    }

    /// A monument whole, every piece in place on flat ground (for previews and checks).
    public static func monument(_ kind: MonumentKind) -> Mesh3D {
        var m = Mesh3D()
        for p in monumentPieces(kind) { m.add(p.mesh(), at: SIMD3(p.x, 0, p.z)) }
        return m
    }

    /// The statue on its island: the star fort, the granite pedestal, the robed copper figure 46 m from heel to
    /// torch, the spiked crown, the tablet.
    static func liberty() -> Mesh3D {
        var m = Mesh3D()
        let copper = RGBA(108, 176, 150), granite = RGBA(200, 192, 176), fort = RGBA(176, 164, 140), flame = RGBA(250, 196, 60)
        let c = SIMD3<Float>(80, 0, 80)
        // the star fort: eleven points, its walls 5 units high, its top flat
        let pts = (0..<22).map { i -> SIMD3<Float> in
            let a = Float(i) / 22 * 2 * .pi
            let r: Float = i % 2 == 0 ? 25 : 15
            return c + SIMD3(cos(a) * r, 0, sin(a) * r)
        }
        let top: Float = 5
        for i in 0..<22 {
            let p = pts[i], q = pts[(i + 1) % 22]
            m.face(SIMD3(q.x, -4, q.z), SIMD3(p.x, -4, p.z), SIMD3(p.x, top, p.z), SIMD3(q.x, top, q.z), fort)
            m.tri(SIMD3(c.x, top, c.z), SIMD3(q.x, top, q.z), SIMD3(p.x, top, p.z), fort.lightened(0.05))
        }
        // the pedestal: a stepped base, the tall shaft with its pilasters, the cornice, the balcony
        m.box(c.x - 7, top, c.z - 7, c.x + 7, top + 2, c.z + 7, granite, faces: .all)
        m.box(c.x - 5.5, top + 2, c.z - 5.5, c.x + 5.5, top + 4, c.z + 5.5, granite, faces: .all)
        m.box(c.x - 4.3, top + 4, c.z - 4.3, c.x + 4.3, top + 15, c.z + 4.3, granite.darkened(0.04), faces: .all)
        for k in [-1, 1] as [Float] { for j in [-1, 1] as [Float] {
            m.box(c.x + k * 4.3 - (k > 0 ? 0.6 : 0), top + 4, c.z + j * 2.2 - 0.5, c.x + k * 4.3 + (k > 0 ? 0 : 0.6), top + 14, c.z + j * 2.2 + 0.5, granite.lightened(0.04), faces: .all)
        } }
        m.box(c.x - 5, top + 15, c.z - 5, c.x + 5, top + 16.5, c.z + 5, granite, faces: .all)
        m.box(c.x - 4, top + 16.5, c.z - 4, c.x + 4, top + 18.5, c.z + 4, granite.darkened(0.03), faces: .all)
        // the figure, 23 units heel to torch: the robe in folds, the shoulders and head, the crown
        let s: Float = 1.95, foot = top + 18.5
        func P(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { c + SIMD3(x * s, foot + y * s, z * s) }
        m.frustum(P(0, 0, 0), P(0, 2.5, 0), 1.35 * s, 1.15 * s, copper.darkened(0.04), seg: 16)
        m.frustum(P(0, 2.5, 0), P(0, 6.5, 0), 1.15 * s, 0.75 * s, copper, seg: 16)
        for i in 0..<8 { let a = Float(i) / 8 * 2 * .pi; m.frustum(P(cos(a) * 1.2, 0, sin(a) * 1.2), P(cos(a) * 0.72, 6.3, sin(a) * 0.72), 0.16 * s, 0.1 * s, copper.darkened(0.08), seg: 5) }
        m.ellipsoid(P(0, 6.7, 0), SIMD3(0.95, 0.55, 0.7) * s, copper, seg: 12, rings: 5)
        m.frustum(P(0, 7.0, 0), P(0, 7.5, 0), 0.25 * s, 0.22 * s, copper, seg: 8)
        m.ellipsoid(P(0, 8.1, 0), SIMD3(0.5, 0.62, 0.5) * s, copper, seg: 12, rings: 6)
        m.frustum(P(0, 8.5, 0), P(0, 8.75, 0), 0.52 * s, 0.5 * s, copper.darkened(0.05), seg: 12)
        for i in 0..<7 {
            let a = Float(i) / 7 * .pi - .pi / 2 - 0.1
            m.frustum(P(cos(a) * 0.4, 8.65, sin(a) * 0.4 + 0.15), P(cos(a) * 1.3, 9.2, sin(a) * 0.8 + 0.4), 0.1 * s, 0, copper.lightened(0.05), seg: 4)
        }
        m.frustum(P(0.8, 6.4, 0), P(1.0, 10.2, 0.2), 0.3 * s, 0.24 * s, copper, seg: 8)
        m.frustum(P(1.0, 10.2, 0.2), P(1.05, 11.0, 0.2), 0.28 * s, 0.42 * s, copper.darkened(0.1), seg: 8)
        m.frustum(P(1.05, 11.0, 0.2), P(1.05, 11.12, 0.2), 0.5 * s, 0.5 * s, RGBA(230, 190, 80), seg: 10)
        m.ellipsoid(P(1.05, 11.5, 0.2), SIMD3(0.4, 0.6, 0.4) * s, flame, seg: 10, rings: 5)
        m.frustum(P(-0.8, 6.2, 0), P(-0.9, 4.6, 0.5), 0.26 * s, 0.22 * s, copper, seg: 8)
        m.roundedBox(c.x - 1.4 * s, foot + 4.2 * s, c.z + 0.3 * s, c.x - 0.6 * s, foot + 5.6 * s, c.z + 0.65 * s, r: 0.1, copper.darkened(0.05))
        // the island's trees
        for i in 0..<14 { let a = Float(i) / 14 * 2 * .pi + 0.2; m.tree(c.x + cos(a) * 42, c.z + sin(a) * 42, h: 7, pine: false) }
        return m
    }

    /// The clock tower, 96 m: the shaft with its bands of tracery, the clock stage with a 7 m face on each side,
    /// the belfry, the spire with corner pinnacles.
    static func clockTower() -> Mesh3D {
        var m = Mesh3D()
        let stone = RGBA(214, 196, 150), gold = RGBA(226, 186, 76), face = RGBA(246, 244, 232), roof = RGBA(64, 92, 84), ink = RGBA(30, 30, 36)
        let x0: Float = 12, x1: Float = 18, z0: Float = 12, z1: Float = 18, mx: Float = 15, mz: Float = 15
        m.box(x0, -4, z0, x1, 27, z1, stone, faces: .all)
        for i in 0..<13 { let y = Float(i) * 2.05 + 1.2; m.box(x0 - 0.08, y, z0 - 0.08, x1 + 0.08, y + 0.18, z1 + 0.08, stone.darkened(0.15), faces: .all) }
        for (dx, dz) in [(Float(-1), Float(-1)), (1, -1), (-1, 1), (1, 1)] {
            m.box(mx + dx * 3 - 0.35, 0, mz + dz * 3 - 0.35, mx + dx * 3 + 0.35, 27.5, mz + dz * 3 + 0.35, stone.lightened(0.04), faces: .all)
        }
        m.box(x0 - 0.6, 27, z0 - 0.6, x1 + 0.6, 34.5, z1 + 0.6, stone.lightened(0.05), faces: .all)
        for (dx, dz) in [(Float(0), Float(-1)), (0, 1), (-1, 0), (1, 0)] {
            let at = SIMD3<Float>(mx, 30.8, mz) + SIMD3(dx * 3.62, 0, dz * 3.62)
            let axis = SIMD3<Float>(dx, 0, dz)
            m.frustum(at, at + axis * 0.1, 2.05, 2.05, gold, seg: 20)
            m.frustum(at + axis * 0.1, at + axis * 0.16, 1.75, 1.75, face, seg: 20)
            m.frustum(at + axis * 0.16, at + axis * 0.2 + SIMD3(0, 1.3, 0), 0.08, 0.05, ink, seg: 4)
            m.frustum(at + axis * 0.16, at + axis * 0.2 + SIMD3(dz * 0.9, 0.2, -dx * 0.9), 0.08, 0.05, ink, seg: 4)
        }
        m.box(x0 + 0.2, 34.5, z0 + 0.2, x1 - 0.2, 39, z1 - 0.2, stone, faces: .all)
        for k in 0..<3 { let x = x0 + 1.2 + Float(k) * 1.8; for z in [z0 + 0.1, z1 - 0.2] { m.box(x, 35.3, z, x + 0.9, 38.2, z + 0.1, ink.lightened(0.15), faces: .all) } }
        m.frustum(SIMD3(mx, 39, mz), SIMD3(mx, 47.5, mz), 3.3, 0.08, roof, seg: 4)
        for (dx, dz) in [(Float(-1), Float(-1)), (1, -1), (-1, 1), (1, 1)] {
            m.frustum(SIMD3(mx + dx * 2.8, 39, mz + dz * 2.8), SIMD3(mx + dx * 2.8, 42.5, mz + dz * 2.8), 0.4, 0.02, roof, seg: 4)
        }
        m.frustum(SIMD3(mx, 47.5, mz), SIMD3(mx, 49, mz), 0.15, 0.02, gold, seg: 6)
        return m
    }

    /// The iron tower, 330 m: four lattice legs braced in X, the arches at the foot, the first platform at
    /// 57 m, the second at 115 m, the top deck at 276 m and the mast.
    static func ironTower() -> Mesh3D {
        var m = Mesh3D()
        let iron = RGBA(118, 100, 82), deck = RGBA(140, 124, 100), plan = IronTowerPlan.self
        let c = plan.c
        func corner(_ sx: Float, _ sz: Float, _ half: Float, _ y: Float) -> SIMD3<Float> { SIMD3(c + sx * half, y, c + sz * half) }
        let signs: [(Float, Float)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        let levels: [(Float, Float, Float)] = [(0, plan.foot, 3.2), (plan.p1.y, plan.p1.half - 2, 2.2), (plan.p2.y, plan.p2.half - 1.2, 1.5), (plan.top.y, plan.top.half, 0.6)]
        for k in 0..<3 {
            let (ya, ha, ra) = levels[k], (yb, hb, rb) = levels[k + 1]
            for (sx, sz) in signs { m.frustum(corner(sx, sz, ha, ya), corner(sx, sz, hb, yb), ra, rb, iron, seg: 4) }
            // X bracing between neighbouring legs, in panels up the segment
            let panels = k == 2 ? 10 : 4
            for p in 0..<panels {
                let t0 = Float(p) / Float(panels), t1 = Float(p + 1) / Float(panels)
                let y0 = ya + (yb - ya) * t0, y1 = ya + (yb - ya) * t1, h0 = ha + (hb - ha) * t0, h1 = ha + (hb - ha) * t1
                for i in 0..<4 {
                    let (ax, az) = signs[i], (bx, bz) = signs[(i + 1) % 4]
                    let r = max(0.12, rb * 0.25)
                    m.frustum(corner(ax, az, h0, y0), corner(bx, bz, h1, y1), r, r, iron.darkened(0.1), seg: 4)
                    m.frustum(corner(bx, bz, h0, y0), corner(ax, az, h1, y1), r, r, iron.darkened(0.1), seg: 4)
                }
            }
        }
        // the great arches between the legs at the foot
        for i in 0..<4 {
            let (ax, az) = signs[i], (bx, bz) = signs[(i + 1) % 4]
            for j in 0..<12 {
                let t0 = Float(j) / 12, t1 = Float(j + 1) / 12
                func at(_ t: Float) -> SIMD3<Float> {
                    let h = plan.foot - (plan.foot - (plan.p1.half - 2)) * 0.4
                    let a = corner(ax, az, h, 11), b = corner(bx, bz, h, 11)
                    return a + (b - a) * t + SIMD3(0, sin(t * .pi) * 6, 0)
                }
                m.frustum(at(t0), at(t1), 0.35, 0.35, iron, seg: 4)
            }
        }
        // the platforms with their galleries
        for (y, half, thick) in [(plan.p1.y, plan.p1.half, Float(1.6)), (plan.p2.y, plan.p2.half, 1.2), (plan.top.y, plan.top.half + 1, 1)] {
            m.box(c - half, y, c - half, c + half, y + thick, c + half, deck, faces: .all)
            m.box(c - half + 0.6, y + thick, c - half + 0.6, c + half - 0.6, y + thick + 2.2, c + half - 0.6, RGBA(150, 170, 176), faces: .all)
            m.box(c - half - 0.2, y + thick + 2.2, c - half - 0.2, c + half + 0.2, y + thick + 2.5, c + half + 0.2, deck, faces: .all)
        }
        m.frustum(SIMD3(c, plan.top.y + 3.5, c), SIMD3(c, plan.top.y + 9, c), 1.4, 0.9, iron, seg: 8)
        m.frustum(SIMD3(c, plan.top.y + 9, c), SIMD3(c, 165, c), 0.4, 0.08, iron, seg: 6)
        for (fx, fz) in plan.feet { m.box(fx - 4.5, -4, fz - 4.5, fx + 4.5, 1, fz + 4.5, RGBA(160, 150, 130), faces: .all) }
        return m
    }

    /// The great pyramid: 230 m along each side, 146 m high, of limestone in courses, with a golden capstone.
    static func pyramid() -> Mesh3D {
        var m = Mesh3D()
        let lime = RGBA(222, 198, 146)
        let a: Float = Float(PyramidPlan.inset), b: Float = 140 - a, c: Float = 70, h: Float = 73
        m.box(a, -4, a, b, 0.4, b, lime.darkened(0.08), faces: .all)
        func ring(_ t: Float) -> [SIMD3<Float>] {
            let i = (c - a) * t, y = h * t
            return [SIMD3(a + i, y, b - i), SIMD3(b - i, y, b - i), SIMD3(b - i, y, a + i), SIMD3(a + i, y, a + i)]
        }
        // four faces in courses (bands of a slightly different tone), up to the capstone
        let courses = 24, capAt: Float = 0.94
        for k in 0..<courses {
            let lo = ring(Float(k) / Float(courses) * capAt), hi = ring(Float(k + 1) / Float(courses) * capAt)
            let tone = lime.darkened(k % 2 == 0 ? 0 : 0.035)
            for i in 0..<4 { m.face(lo[i], lo[(i + 1) % 4], hi[(i + 1) % 4], hi[i], tone) }
        }
        let cap = ring(capAt), apex = SIMD3<Float>(c, h + 0.6, c)
        for k in 0..<4 { m.tri(cap[k], cap[(k + 1) % 4], apex, RGBA(240, 200, 90)) }
        // the entrance on the south face
        m.box(c - 1.5, 0, b - 1.6, c + 1.5, 4, b - 1.4, RGBA(60, 44, 30), faces: .all)
        return m
    }

    /// The wooden pagoda, 67 m: an octagonal tower of five storeys on a stone platform, each storey with its
    /// balcony and flaring eaves, the spire of rings on top.
    static func pagoda() -> Mesh3D {
        var m = Mesh3D()
        let wood = RGBA(160, 58, 42), roof = RGBA(56, 74, 72), stone = RGBA(190, 184, 170), gold = RGBA(220, 170, 60), rail = RGBA(120, 44, 34)
        let c = SIMD3<Float>(22, 0, 22)
        m.frustum(c + SIMD3(0, -4, 0), c + SIMD3(0, 2, 0), 11, 10.5, stone, seg: 8)
        var y: Float = 2
        let radii: [Float] = [7.5, 7, 6.5, 6, 5.5]
        for (k, r) in radii.enumerated() {
            let wall: Float = k == 0 ? 5 : 3.6
            m.frustum(c + SIMD3(0, y, 0), c + SIMD3(0, y + wall, 0), r, r, wood, seg: 8)
            m.frustum(c + SIMD3(0, y + wall - 0.6, 0), c + SIMD3(0, y + wall, 0), r + 0.25, r + 0.25, RGBA(230, 220, 190), seg: 8)
            y += wall
            // the eaves: flaring out and up from the wall
            let last = k == radii.count - 1
            m.frustum(c + SIMD3(0, y - 0.3, 0), c + SIMD3(0, y + (last ? 3.6 : 1.5), 0), r + 3.2, last ? 0.6 : r * 0.8, roof, seg: 8)
            m.frustum(c + SIMD3(0, y - 0.5, 0), c + SIMD3(0, y - 0.3, 0), r + 3.0, r + 3.2, roof.darkened(0.2), seg: 8)
            y += last ? 3.6 : 1.5
            if !last {
                // the balcony of the storey above, with its railing
                m.frustum(c + SIMD3(0, y, 0), c + SIMD3(0, y + 0.3, 0), r + 1.2, r + 1.2, wood.darkened(0.15), seg: 8)
                m.frustum(c + SIMD3(0, y + 0.3, 0), c + SIMD3(0, y + 1.2, 0), r + 1.15, r + 1.15, rail, seg: 8, caps: false)
            }
        }
        m.frustum(c + SIMD3(0, y - 0.2, 0), c + SIMD3(0, y + 1, 0), 0.9, 0.7, gold, seg: 8)
        for k in 0..<4 { m.frustum(c + SIMD3(0, y + 1.2 + Float(k) * 0.4, 0), c + SIMD3(0, y + 1.45 + Float(k) * 0.4, 0), 0.7 - Float(k) * 0.06, 0.7 - Float(k) * 0.06, gold, seg: 10) }
        m.frustum(c + SIMD3(0, y + 1, 0), c + SIMD3(0, y + 3, 0), 0.15, 0.04, gold, seg: 6)
        for (x, z) in [(Float(4), Float(4)), (40, 4), (4, 40), (40, 40), (10, 36), (34, 36)] { m.tree(x, z, h: 8, pine: true) }
        return m
    }
}

// MARK: - the flat view's pictures

public enum MonumentArt {
    static let ink = RGBA(40, 30, 30)

    /// What of a monument is painted standing up in the flat view.
    public static func sprites(for m: Monument) -> [MonumentSprite] {
        if m.kind == .fusion, let d = m.design { return fusionSprites(d) }
        return sprites(m.kind)
    }

    public static func sprites(_ kind: MonumentKind) -> [MonumentSprite] {
        let (w, d) = kind.size
        switch kind {
        case .palace:
            typealias P = Palace
            var out: [MonumentSprite] = []
            func hallSprite(_ key: String, _ r: Palace.R, base: Float, col: Float, roof: Float, double: Bool, terrace: Float = 1, wide: Float? = nil) {
                let wd = wide ?? Float(r.w)
                out.append(MonumentSprite(key: key, x: Float(r.x) + Float(r.w) / 2, z: Float(r.z + r.d), w: wd + 4, h: base + terrace + col + 0.8 + roof + 1.5) { ppt in
                    hallPicture(w: Double(wd), base: Double(base), terrace: Double(terrace), col: Double(col), roof: Double(roof), double: double, ppt: ppt)
                })
            }
            for (k, r) in P.towers.enumerated() { hallSprite("ptower\(k)", r, base: 5, col: 5, roof: 4, double: true, terrace: 0, wide: 10) }
            hallSprite("pnorth", P.northGate, base: 5.5, col: 4, roof: 5, double: true, terrace: 0, wide: 24)
            for (k, (r, col, roof, dbl)) in P.innerHalls.enumerated() { hallSprite("pinner\(k)", r, base: 1.5, col: col, roof: roof, double: dbl) }
            hallSprite("ppurity", P.purityGate, base: 0, col: 4.5, roof: 4, double: false, terrace: 1.5, wide: 24)
            for (k, (r, col, roof, dbl)) in P.outerHalls.enumerated() { hallSprite("pouter\(k)", r, base: 4, col: col, roof: roof, double: dbl) }
            hallSprite("pharmony", P.harmonyGate, base: 0, col: 5, roof: 5, double: true, terrace: 2, wide: 32)
            hallSprite("pmeridian", P.meridianGate, base: 6, col: 5, roof: 7, double: true, terrace: 0, wide: 32)
            return out
        default:
            let foot: Float = kind == .liberty ? Float(d) / 2 + 8 : (kind == .pyramid ? Float(d - PyramidPlan.inset) : (kind == .clock ? 18 : (kind == .pagoda ? Float(d) / 2 + 11 : Float(d) / 2 + 30)))
            return [MonumentSprite(key: "mon-\(kind.rawValue)", x: Float(w) / 2, z: foot, w: Float(w), h: Float(kind.height) + 1) { ppt in picture(kind, ppt: ppt) }]
        }
    }

    /// A Chinese hall seen from the south: `w` tiles wide, a base (platform or terrace) `base` high, a white
    /// terrace, red columns, the beam band and a golden roof.
    public static func hallPicture(w: Double, base: Double, terrace: Double, col: Double, roof: Double, double: Bool, ppt: Double) -> Bitmap {
        let s = ppt, W = Int((w + 4) * s), H = Int((base + terrace + col + 0.8 + roof + 1.5) * s)
        var c = Canvas(max(2, W), max(2, H), scale: 1)
        c.inkColor = ink
        let gw = Double(W), gh = Double(H), cx = gw / 2
        let red = RGBA(178, 40, 36), gold = RGBA(236, 180, 50), marble = RGBA(236, 234, 226), beam = RGBA(40, 96, 120)
        _ = gw
        var y = gh
        if base > 0 {
            c.rect(cx - (w / 2 + 1) * s, y - base * s, (w + 2) * s, base * s, red, ink: 1); y -= base * s
            c.rect(cx - (w / 2 + 1.2) * s, y - 0.4 * s, (w + 2.4) * s, 0.4 * s, gold.darkened(0.15), ink: 0.8)
        }
        if terrace > 0 { c.rect(cx - (w / 2 + 0.6) * s, y - terrace * s, (w + 1.2) * s, terrace * s, marble, ink: 1); y -= terrace * s }
        c.rect(cx - w / 2 * s, y - col * s, w * s, col * s, red, ink: 1, shade: Shade(shadow: 0.15, light: 0.1))
        var x = cx - w / 2 * s + 0.4 * s
        while x < cx + w / 2 * s { c.rect(x, y - col * s, 0.4 * s, col * s, RGBA(130, 24, 24)); x += 2.4 * s }
        y -= col * s
        c.rect(cx - w / 2 * s, y - 0.8 * s, w * s, 0.8 * s, beam, ink: 0.8); y -= 0.8 * s
        func roofShape(_ half: Double, _ rh: Double, _ o: Double) {
            let top = max(0.3, min(half * 0.7, half - rh * 0.4))
            c.poly([(cx - (half + o) * s, y + 0.2 * s), (cx + (half + o) * s, y + 0.2 * s), (cx + top * s, y - rh * s), (cx - top * s, y - rh * s)], gold, ink: 1, shade: Shade(shadow: 0.15, light: 0.25))
            for sx in [-1.0, 1.0] { c.curve([(cx + sx * (half + o - 0.6) * s, y), (cx + sx * (half + o + 0.3) * s, y - 0.7 * s)], 0.35 * s, gold) }
            c.rect(cx - top * s, y - rh * s - 0.3 * s, 2 * top * s, 0.35 * s, gold.darkened(0.2))
        }
        if double {
            roofShape(w / 2, roof * 0.22, 2.0); y -= roof * 0.22 * s
            c.rect(cx - (w / 2 - 1.6) * s, y - roof * 0.12 * s, (w - 3.2) * s, roof * 0.12 * s, red, ink: 0.8); y -= roof * 0.12 * s
            roofShape(w / 2 - 1.4, roof * 0.62, 2.2)
        } else { roofShape(w / 2, roof, 2.0) }
        return c.image()
    }

    /// A monument (other than the palace) as a picture seen from the front, its width its ground's, its height
    /// what the structure rises to, `ppt` pixels a tile.
    public static func picture(_ kind: MonumentKind, ppt: Double = 4) -> Bitmap {
        let (w, _) = kind.size
        let W = Int(Double(w) * ppt), H = Int((kind.height + 1) * ppt)
        var c = Canvas(W, H, scale: 1)
        let s = ppt, gw = Double(W), gh = Double(H), cx = gw / 2
        c.inkColor = ink
        switch kind {
        case .palace:
            return hallPicture(w: 32, base: 4, terrace: 1, col: 6.5, roof: 6.2, double: true, ppt: ppt)
        case .fusion:
            return fusionPicture(FusionDesign.make(seed: 1), ppt: ppt)
        case .liberty:
            let copper = RGBA(108, 176, 150), granite = RGBA(200, 192, 176)
            c.rect(cx - 25 * s, gh - 5 * s, 50 * s, 5 * s, RGBA(176, 164, 140), ink: 1)
            c.rect(cx - 7 * s, gh - 7 * s, 14 * s, 2 * s, granite, ink: 1)
            c.rect(cx - 5.5 * s, gh - 9 * s, 11 * s, 2 * s, granite, ink: 1)
            c.rect(cx - 4.3 * s, gh - 20 * s, 8.6 * s, 11 * s, granite.darkened(0.04), ink: 1)
            c.rect(cx - 5 * s, gh - 21.5 * s, 10 * s, 1.5 * s, granite, ink: 1)
            c.rect(cx - 4 * s, gh - 23.5 * s, 8 * s, 2 * s, granite, ink: 1)
            let f = gh - 23.5 * s, k = 1.95 * s
            c.poly([(cx - 1.35 * k, f), (cx + 1.35 * k, f), (cx + 0.75 * k, f - 6.5 * k), (cx - 0.75 * k, f - 6.5 * k)], copper, ink: 1, shade: Shade(shadow: 0.2, light: 0.2))
            for i in 0..<6 { let x = cx + (Double(i) - 2.5) * 0.4 * k; c.line(x, f, x * 0.98 + cx * 0.02, f - 6.2 * k, 0.12 * k, copper.darkened(0.12)) }
            c.ellipse(cx, f - 6.75 * k, 0.95 * k, 0.5 * k, copper, ink: 1)
            c.ellipse(cx, f - 8.1 * k, 0.5 * k, 0.62 * k, copper, ink: 1)
            for i in 0..<7 { let a = -.pi / 2 + (Double(i) - 3) * 0.3; c.line(cx, f - 8.6 * k, cx + cos(a) * 1.2 * k, f - 8.6 * k + sin(a) * 1.2 * k, 0.16 * k, copper) }
            c.line(cx + 0.8 * k, f - 6.4 * k, cx + 1.05 * k, f - 11 * k, 0.5 * k, copper)
            c.ellipse(cx + 1.05 * k, f - 11.5 * k, 0.4 * k, 0.65 * k, RGBA(250, 196, 60), ink: 0.8)
            c.rect(cx - 1.5 * k, f - 5.6 * k, 0.8 * k, 1.4 * k, copper.darkened(0.08), ink: 0.8)
        case .clock:
            let stone = RGBA(214, 196, 150), gold = RGBA(226, 186, 76)
            c.rect(cx - 3 * s, gh - 27 * s, 6 * s, 27 * s, stone, ink: 1, shade: Shade(shadow: 0.1, light: 0.15))
            for i in 0..<13 { c.rect(cx - 3 * s, gh - (Double(i) * 2.05 + 1.2) * s, 6 * s, 0.18 * s, stone.darkened(0.15)) }
            c.rect(cx - 3.6 * s, gh - 34.5 * s, 7.2 * s, 7.5 * s, stone.lightened(0.05), ink: 1)
            c.ellipse(cx, gh - 30.8 * s, 2.05 * s, 2.05 * s, gold, ink: 1)
            c.ellipse(cx, gh - 30.8 * s, 1.75 * s, 1.75 * s, RGBA(246, 244, 232))
            c.line(cx, gh - 30.8 * s, cx, gh - 32.1 * s, 0.15 * s, RGBA(20, 20, 26)); c.line(cx, gh - 30.8 * s, cx + 0.9 * s, gh - 30.6 * s, 0.15 * s, RGBA(20, 20, 26))
            c.rect(cx - 2.8 * s, gh - 39 * s, 5.6 * s, 4.5 * s, stone, ink: 1)
            c.poly([(cx - 3.3 * s, gh - 39 * s), (cx + 3.3 * s, gh - 39 * s), (cx, gh - 47.5 * s)], RGBA(64, 92, 84), ink: 1)
            c.line(cx, gh - 47.5 * s, cx, gh - 49 * s, 0.2 * s, gold)
        case .ironTower:
            let iron = RGBA(118, 100, 82)
            let p = IronTowerPlan.self
            func half(_ y: Double) -> Double {
                let ys: [Double] = [0, Double(p.p1.y), Double(p.p2.y), Double(p.top.y)], hs: [Double] = [Double(p.foot) + 3, Double(p.p1.half), Double(p.p2.half), Double(p.top.half)]
                for i in 0..<3 where y <= ys[i + 1] { let t = (y - ys[i]) / (ys[i + 1] - ys[i]); return hs[i] + (hs[i + 1] - hs[i]) * (t * t * 0.3 + t * 0.7) }
                return Double(p.top.half)
            }
            // the two legs seen side on, meeting higher up; the arch between them; the platforms; the bracing
            let legW = 5.0
            for sx in [-1.0, 1.0] {
                var pts: [(Double, Double)] = []
                for k in 0...30 { let y = Double(k) / 30 * Double(p.p2.y); pts.append((cx + sx * half(y) * s, gh - y * s)) }
                for k in (0...30).reversed() { let y = Double(k) / 30 * Double(p.p2.y); pts.append((cx + sx * max(0, half(y) - legW * (1 - y / Double(p.p2.y) * 0.6)) * s, gh - y * s)) }
                c.poly(pts, iron, ink: 1)
            }
            var upper: [(Double, Double)] = []
            for k in 0...20 { let y = Double(p.p2.y) + Double(k) / 20 * (Double(p.top.y) - Double(p.p2.y)); upper.append((cx - half(y) * s, gh - y * s)) }
            for k in (0...20).reversed() { let y = Double(p.p2.y) + Double(k) / 20 * (Double(p.top.y) - Double(p.p2.y)); upper.append((cx + half(y) * s, gh - y * s)) }
            c.poly(upper, iron, ink: 1)
            c.curve((0...12).map { k in let t = Double(k) / 12; return (cx + (t - 0.5) * 2 * (half(11) - 2) * s, gh - (11 + sin(t * .pi) * 6) * s) }, 0.8 * s, iron)
            for (y, h) in [(Double(p.p1.y), Double(p.p1.half)), (Double(p.p2.y), Double(p.p2.half)), (Double(p.top.y), Double(p.top.half) + 1)] {
                c.rect(cx - h * s, gh - (y + 4) * s, 2 * h * s, 4 * s, RGBA(140, 124, 100), ink: 0.8)
            }
            for k in 0..<30 {
                let y0 = Double(k) * 4.6, y1 = y0 + 4.6
                c.line(cx - half(y0) * s, gh - y0 * s, cx + half(y1) * s, gh - y1 * s, 0.12 * s, iron.darkened(0.25))
                c.line(cx + half(y0) * s, gh - y0 * s, cx - half(y1) * s, gh - y1 * s, 0.12 * s, iron.darkened(0.25))
            }
            c.line(cx, gh - Double(p.top.y) * s, cx, gh - 165 * s, 0.5 * s, iron)
        case .pyramid:
            let lime = RGBA(222, 198, 146)
            let a = Double(PyramidPlan.inset) * s
            c.poly([(a, gh), (gw - a, gh), (cx, gh - 73 * s)], lime, ink: 1, shade: Shade(shadow: 0.18, light: 0.18))
            for k in 1..<24 { let y = gh - Double(k) / 24 * 73 * s, i = (cx - a) * Double(k) / 24; c.line(a + i, y, gw - a - i, y, 0.08 * s, lime.darkened(0.12)) }
            c.poly([(cx - (cx - a) * 0.06, gh - 73 * 0.94 * s), (cx + (cx - a) * 0.06, gh - 73 * 0.94 * s), (cx, gh - 73.6 * s)], RGBA(240, 200, 90), ink: 0.8)
            c.rect(cx - 1.5 * s, gh - 4 * s, 3 * s, 4 * s, RGBA(60, 44, 30))
        case .pagoda:
            let wood = RGBA(160, 58, 42), roof = RGBA(56, 74, 72)
            c.rect(cx - 11 * s, gh - 2 * s, 22 * s, 2 * s, RGBA(190, 184, 170), ink: 1)
            var y = gh - 2 * s
            let radii: [Double] = [7.5, 7, 6.5, 6, 5.5]
            for (k, r) in radii.enumerated() {
                let wall = (k == 0 ? 5 : 3.6) * s
                c.rect(cx - r * s, y - wall, 2 * r * s, wall, wood, ink: 1)
                for j in 0..<Int(r) { c.rect(cx - r * s + (Double(j) * 2 + 0.6) * s, y - wall * 0.8, 0.8 * s, wall * 0.55, RGBA(230, 220, 190)) }
                y -= wall
                let last = k == radii.count - 1, rh = (last ? 3.6 : 1.5) * s
                c.poly([(cx - (r + 3.2) * s, y + 0.3 * s), (cx + (r + 3.2) * s, y + 0.3 * s), (cx + (last ? 0.6 : r * 0.8) * s, y - rh), (cx - (last ? 0.6 : r * 0.8) * s, y - rh)], roof, ink: 1)
                y -= rh
                if !last { c.rect(cx - (r + 1.2) * s, y - 1.2 * s, 2 * (r + 1.2) * s, 1.2 * s, RGBA(120, 44, 34), ink: 0.6); y -= 0.3 * s }
            }
            c.line(cx, y, cx, y - 3 * s, 0.4 * s, RGBA(220, 170, 60))
            for k in 0..<7 { c.rect(cx - 0.7 * s, y - (1.2 + Double(k) * 0.5) * s, 1.4 * s, 0.25 * s, RGBA(220, 170, 60)) }
        }
        return c.image()
    }
}
