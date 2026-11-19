import Foundation

// A nation's own landmark, designed for it: the world's famous landmarks taken apart and put together anew. A
// base (a white terrace, a star fort, a stepped podium, a ring of columns), a tower (glass, tiered eaves, an
// iron lattice, a stone shaft, red halls stacked), and a crown (a spire, a torch-bearing statue, a golden roof,
// a dome, a clock, a mast). Each is drawn from the nation's seed, so no two are alike.
//
// It is a real building at its real size. Its tower has a floor every 4 m (each a storey of the world: walls,
// floors, beds, a stair up), sky farms on some floors, and a glass lift up its side with a landing on every
// floor. On the plaza round it are fields of grain and an airstrip with an apron and a hangar.

public struct FusionDesign: Codable, Equatable {
    /// The ground it takes, tiles, and its tower's footprint (in the middle).
    public static let plot = 64, core = 16
    public static var coreOrigin: Int { (plot - core) / 2 }
    public var seed = 0
    public var base = 0, body = 0, top = 0, palette = 0
    public var storeys = 12
    public init() {}

    public static func make(seed: Int) -> FusionDesign {
        var r = RNG(seed: seed &* 7919 &+ 17)
        var d = FusionDesign()
        d.seed = seed
        d.base = r.int(0, 3); d.body = r.int(0, 4); d.top = r.int(0, 5); d.palette = r.int(0, 3)
        d.storeys = r.int(10, 24)
        return d
    }

    public var bodyHeight: Float { Float(storeys) * 2 }
    public var topHeight: Float { [14, 13, 9, 11, 13, 20][top] }
    public var totalHeight: Float { bodyHeight + topHeight }

    public func name(zh: Bool) -> String {
        let crown = zh ? ["云霄", "自由", "金顶", "穹顶", "时钟", "星辉"][top] : ["Sky", "Liberty", "Golden", "Dome", "Clock", "Star"][top]
        let tower = zh ? ["琉璃塔", "层檐阁", "铁骨塔", "石柱塔", "朱阁"][body] : ["Glass Tower", "Tiered Pavilion", "Iron Tower", "Stone Tower", "Red Pavilion"][body]
        return zh ? crown + tower : crown + " " + tower
    }

    /// Wall, trim and roof colours.
    var colors: (wall: RGBA, trim: RGBA, roof: RGBA) {
        [(RGBA(236, 232, 220), RGBA(226, 180, 60), RGBA(232, 176, 52)),
         (RGBA(120, 170, 210), RGBA(200, 208, 220), RGBA(80, 110, 140)),
         (RGBA(178, 44, 38), RGBA(236, 182, 56), RGBA(236, 180, 50)),
         (RGBA(214, 190, 140), RGBA(70, 140, 130), RGBA(60, 120, 110))][palette]
    }
}

extension Society {
    /// The tiles of a nation's own landmark: the plaza, the tower's floors with homes and sky farms, the lift,
    /// the fields and the airstrip.
    func carveFusion(_ m: Monument) {
        guard let d = m.design else { return }
        let T = { (k: String) in self.content.tid(k) }
        let P = FusionDesign.plot, c0 = FusionDesign.coreOrigin, C = FusionDesign.core
        let stone = T("stone_floor"), farmland = T("farmland"), wheat = T("wheat_0")
        func set(_ x: Int, _ y: Int, _ l: Int, _ v: UInt8) { world.setTile(l, m.x + x, m.y + y, v) }
        // the plaza
        for y in 0..<P { for x in 0..<P { set(x, y, 0, stone) } }
        // fields of grain in two corners
        for (fx, fy) in [(44, 4), (44, 46)] { for y in fy..<(fy + 13) { for x in fx..<(fx + 16) {
            set(x, y, 0, farmland); set(x, y, 2, wheat)
        } } }
        // the airstrip down the west side, its apron and a hangar
        for y in 3..<61 { for x in 2..<6 { set(x, y, 0, T("runway")) } }
        for y in 44..<56 { for x in 6..<16 { set(x, y, 0, T("apron")) } }
        for y in 30..<38 { for x in 7..<15 {
            let edge = x == 7 || x == 14 || y == 30 || y == 37
            set(x, y, 2, edge ? (x == 14 && (y == 33 || y == 34) ? T("door_wood") : T("wall_concrete")) : 0)
        } }
        // lamps along the way in
        for y in stride(from: c0 + C + 3, to: P - 2, by: 5) { set(P / 2 - 3, y, 2, T("lantern_post")); set(P / 2 + 2, y, 2, T("lantern_post")) }
        // the tower: real floors to live on, a stair from each to the next
        let o = TilePos(m.x + c0, m.y + c0)
        raiseHouse(at: o, storeys: d.storeys, w: C, d: C)
        // its door, on the south side; furniture and sky farms on its floors
        world.setTile(2, o.x + C / 2, o.y + C - 1, T("door_wood"))
        for lv in 0..<d.storeys {
            let w = lv == 0 ? world : storeyWorld(lv)
            if lv % 4 == 2 {
                for y in 4..<10 { for x in 4..<12 { w.setTile(0, o.x + x, o.y + y, farmland); w.setTile(2, o.x + x, o.y + y, wheat) } }
            } else {
                for (x, y, k) in [(4, 4, "table"), (5, 4, "chair"), (3, 4, "chair"), (8, 2, "kitchen"), (11, 2, "chest"), (12, 6, "bed"), (12, 9, "bed"), (6, 9, "bookshelf"), (9, 9, "flower_pot")] {
                    if w.tile(2, o.x + x, o.y + y) == 0 { w.setTile(2, o.x + x, o.y + y, T(k)) }
                }
            }
        }
        // the lift up its east side: a landing on every floor
        let sx = o.x + C + 1, sy = o.y + C / 2 - 1
        for lv in 1..<d.storeys { let w = storeyWorld(lv); for y in (sy - 1)...(sy + 2) { w.setTile(0, o.x + C, y, T("wood_floor")) } }
        for y in sy..<(sy + 2) { for x in sx..<(sx + 2) { for l in 1...3 { world.setTile(l, x, y, 0) } } }
        let plan = planLift(x: sx, y: sy, levels: Array(0..<d.storeys), landingSide: TilePos(-1, 0))
        if plan.ok { _ = makeLift(plan, x: sx, y: sy, w: 2, d: 2, town: m.town, tower: nil) }
        keepClear(TilePos(m.x + P / 2, m.y + P))
    }
}

extension Figure3D {
    /// A nation's own landmark: one piece over its whole plot.
    public static func fusionPieces(_ d: FusionDesign) -> [MonumentPiece] {
        let P = Float(FusionDesign.plot)
        return [MonumentPiece(key: "fusion-\(d.seed)-\(d.base)\(d.body)\(d.top)\(d.palette)-\(d.storeys)", x: 0, z: 0, w: P, d: P) { fusion(d) }]
    }

    /// The model: base, tower and crown, and the hangar with an aeroplane before it.
    public static func fusion(_ d: FusionDesign) -> Mesh3D {
        var m = Mesh3D()
        let P = Float(FusionDesign.plot), c0 = Float(FusionDesign.coreOrigin), C = Float(FusionDesign.core)
        let x0 = c0, x1 = c0 + C, z0 = c0, z1 = c0 + C, cx = P / 2, cz = P / 2
        let H = d.bodyHeight
        let (wall, trim, roof) = d.colors
        let marble = RGBA(236, 234, 226)
        // --- the base, round the tower (never over its door)
        switch d.base {
        case 0:   // a white terrace in three tiers, a ring round the tower
            for k in 0..<3 {
                let o = 12 - Float(k) * 3, h = Float(k + 1) * 0.5
                for (a0, b0, a1, b1) in [(x0 - o, z0 - o, x1 + o, z0), (x0 - o, z1, x1 + o, z1 + o), (x0 - o, z0, x0, z1), (x1, z0, x1 + o, z1)] {
                    m.box(a0, k == 0 ? -4 : 0, b0, a1, h, b1, marble.darkened(Double(k) * 0.03), faces: .all)
                }
            }
        case 1:   // a star fort: eleven points round the tower
            let pts = (0..<22).map { i -> SIMD3<Float> in
                let a = Float(i) / 22 * 2 * .pi, r: Float = i % 2 == 0 ? 27 : 19
                return SIMD3(cx + cos(a) * r, 0, cz + sin(a) * r)
            }
            for i in 0..<22 {
                let p = pts[i], q = pts[(i + 1) % 22]
                let mid = (p + q) / 2
                if mid.z > cz + 15 && abs(mid.x - cx) < 4 { continue }                  // the gate on the south
                m.face(SIMD3(q.x, -4, q.z), SIMD3(p.x, -4, p.z), SIMD3(p.x, 3, p.z), SIMD3(q.x, 3, q.z), RGBA(176, 164, 140))
                m.face(SIMD3(p.x, -4, p.z), SIMD3(q.x, -4, q.z), SIMD3(q.x, 3, q.z), SIMD3(p.x, 3, p.z), RGBA(176, 164, 140))
                m.frustum(SIMD3(p.x, 3, p.z), SIMD3(p.x, 3.6, p.z), 0.6, 0.6, RGBA(150, 140, 120), seg: 4)
            }
        case 2:   // a stepped podium, a ring round the tower
            for k in 0..<3 {
                let o = 10 - Float(k) * 3, h = Float(k + 1) * 1.0
                for (a0, b0, a1, b1) in [(x0 - o, z0 - o, x1 + o, z0), (x0 - o, z1 + 2, x1 + o, z1 + o), (x0 - o, z0, x0, z1 + 2), (x1, z0, x1 + o, z1 + 2)] {
                    m.box(a0, k == 0 ? -4 : 0, b0, a1, h, b1, RGBA(222, 198, 146).darkened(Double(k) * 0.03), faces: .all)
                }
            }
        default:  // a ring of columns with an entablature
            let n = 28, r: Float = 20
            for i in 0..<n {
                let a = Float(i) / Float(n) * 2 * .pi
                let p = SIMD3<Float>(cx + cos(a) * r, 0, cz + sin(a) * r)
                if p.z > cz + 15 && abs(p.x - cx) < 4 { continue }
                m.frustum(p + SIMD3(0, -1, 0), p + SIMD3(0, 6, 0), 0.6, 0.5, marble, seg: 8)
                let q = SIMD3<Float>(cx + cos(a + 2 * .pi / Float(n)) * r, 6, cz + sin(a + 2 * .pi / Float(n)) * r)
                m.frustum(p + SIMD3(0, 6, 0), q, 0.45, 0.45, trim, seg: 4)
            }
        }
        // --- the tower: a band at every floor, windows between
        let bandEvery: Float = 2
        switch d.body {
        case 0:   // glass, framed at every floor
            m.box(x0, -4, z0, x1, H, z1, RGBA(110, 160, 200), faces: .all)
            var y: Float = bandEvery
            while y < H { m.box(x0 - 0.06, y - 0.12, z0 - 0.06, x1 + 0.06, y + 0.12, z1 + 0.06, trim, faces: .all); y += bandEvery }
            for x in stride(from: x0 + 2, to: x1, by: 3) { for z in [z0 - 0.08, z1 + 0.02] { m.box(x - 0.1, 0, z, x + 0.1, H, z + 0.06, trim, faces: .all) } }
        case 1:   // tiered eaves every three floors
            m.box(x0 + 0.5, -4, z0 + 0.5, x1 - 0.5, H, z1 - 0.5, wall, faces: .all)
            var y: Float = 6
            while y < H - 1 { m.hipRoof(x0 + 0.5, z0 + 0.5, x1 - 0.5, z1 - 0.5, y0: y, h: 1.2, o: 2.4, curl: 0.5, roof); y += 6 }
        case 2:   // an iron lattice round a core
            m.box(x0 + 2, -4, z0 + 2, x1 - 2, H, z1 - 2, wall.darkened(0.25), faces: .all)
            let corners: [SIMD3<Float>] = [[x0, 0, z0], [x1, 0, z0], [x1, 0, z1], [x0, 0, z1]]
            for c in corners { m.frustum(c, c + SIMD3(0, H, 0), 0.6, 0.45, RGBA(110, 96, 80), seg: 4) }
            var y: Float = 0
            while y < H - 0.1 {
                let y1 = min(H, y + 8)
                for i in 0..<4 {
                    let a = corners[i], b = corners[(i + 1) % 4]
                    m.frustum(a + SIMD3(0, y, 0), b + SIMD3(0, y1, 0), 0.22, 0.22, RGBA(110, 96, 80), seg: 4)
                    m.frustum(b + SIMD3(0, y, 0), a + SIMD3(0, y1, 0), 0.22, 0.22, RGBA(110, 96, 80), seg: 4)
                }
                m.box(x0, y1 - 0.2, z0, x1, y1 + 0.2, z1, RGBA(130, 116, 96), faces: .all)
                y = y1
            }
        case 3:   // a stone shaft with corner pilasters
            m.box(x0, -4, z0, x1, H, z1, wall, faces: .all)
            for (px, pz) in [(x0, z0), (x1, z0), (x0, z1), (x1, z1)] { m.box(px - 0.8, 0, pz - 0.8, px + 0.8, H + 0.6, pz + 0.8, wall.lightened(0.06), faces: .all) }
            var y: Float = 4
            while y < H { m.box(x0 - 0.2, y, z0 - 0.2, x1 + 0.2, y + 0.3, z1 + 0.2, trim, faces: .all); y += 4 }
        default:  // red halls stacked, gold beams and eaves
            m.box(x0 + 0.6, -4, z0 + 0.6, x1 - 0.6, H, z1 - 0.6, RGBA(178, 44, 38), faces: .all)
            var y: Float = 0
            while y < H - 1 {
                for x in stride(from: x0 + 0.8, through: x1 - 0.8, by: 2.4) { m.frustum(SIMD3(x, y, z1 - 0.2), SIMD3(x, y + 5, z1 - 0.2), 0.3, 0.28, RGBA(150, 28, 28), seg: 6) }
                m.box(x0 + 0.4, y + 5, z0 + 0.4, x1 - 0.4, y + 5.5, z1 - 0.4, RGBA(40, 96, 120), faces: .all)
                m.hipRoof(x0 + 0.4, z0 + 0.4, x1 - 0.4, z1 - 0.4, y0: y + 5.5, h: 0.6, o: 1.8, curl: 0.45, roof)
                y += 6
            }
        }
        // --- the crown
        let T = H
        switch d.top {
        case 0:   // a setback and a spire
            m.box(x0 + 3, T, z0 + 3, x1 - 3, T + 4, z1 - 3, wall.lightened(0.05), faces: .all)
            m.frustum(SIMD3(cx, T + 4, cz), SIMD3(cx, T + 14, cz), 4.5, 0.1, trim, seg: 4)
        case 1:   // a torch-bearing statue on a pedestal
            m.box(cx - 3, T, cz - 3, cx + 3, T + 2, cz + 3, marble, faces: .all)
            let copper = RGBA(108, 176, 150), f = T + 2
            m.frustum(SIMD3(cx, f, cz), SIMD3(cx, f + 7, cz), 2.2, 1.2, copper, seg: 12)
            m.ellipsoid(SIMD3(cx, f + 8, cz), SIMD3(0.9, 1.1, 0.9), copper, seg: 10, rings: 5)
            m.frustum(SIMD3(cx + 1.2, f + 6.5, cz), SIMD3(cx + 1.6, f + 10.4, cz), 0.45, 0.35, copper, seg: 6)
            m.ellipsoid(SIMD3(cx + 1.6, f + 11, cz), SIMD3(0.6, 0.9, 0.6), RGBA(250, 196, 60), seg: 8, rings: 4)
        case 2:   // a golden roof in three tiers
            for k in 0..<3 {
                let i = Float(k) * 2.2
                m.box(x0 + 2 + i, T + Float(k) * 3, z0 + 2 + i, x1 - 2 - i, T + Float(k) * 3 + 1.6, z1 - 2 - i, wall, faces: .all)
                m.hipRoof(x0 + 2 + i, z0 + 2 + i, x1 - 2 - i, z1 - 2 - i, y0: T + Float(k) * 3 + 1.6, h: 1.4, o: 1.6, curl: 0.5, roof)
            }
            m.frustum(SIMD3(cx, T + 9, cz), SIMD3(cx, T + 11, cz), 0.3, 0.05, trim, seg: 6)
        case 3:   // a drum and a dome
            m.frustum(SIMD3(cx, T, cz), SIMD3(cx, T + 3, cz), 6, 6, wall, seg: 20)
            m.ellipsoid(SIMD3(cx, T + 3, cz), SIMD3(6, 6.5, 6), roof, seg: 20, rings: 8, from: 0.5, to: 1)
            m.frustum(SIMD3(cx, T + 9.4, cz), SIMD3(cx, T + 11, cz), 0.4, 0.05, trim, seg: 6)
        case 4:   // a clock stage and a pointed roof
            m.box(x0 + 2, T, z0 + 2, x1 - 2, T + 5, z1 - 2, wall.lightened(0.04), faces: .all)
            for (dx, dz) in [(Float(0), Float(-1)), (0, 1), (-1, 0), (1, 0)] {
                let at = SIMD3<Float>(cx + dx * (C / 2 - 1.95), T + 2.5, cz + dz * (C / 2 - 1.95)), ax = SIMD3<Float>(dx, 0, dz)
                m.frustum(at, at + ax * 0.1, 1.9, 1.9, trim, seg: 18)
                m.frustum(at + ax * 0.1, at + ax * 0.16, 1.6, 1.6, RGBA(246, 244, 232), seg: 18)
            }
            m.frustum(SIMD3(cx, T + 5, cz), SIMD3(cx, T + 13, cz), 6.5, 0.1, roof, seg: 4)
        default:  // a deck and a mast with rings of light
            m.box(x0 + 1, T, z0 + 1, x1 - 1, T + 1, z1 - 1, trim, faces: .all)
            m.frustum(SIMD3(cx, T + 1, cz), SIMD3(cx, T + 20, cz), 0.9, 0.12, RGBA(200, 205, 215), seg: 8)
            for k in 0..<4 { let y = T + 4 + Float(k) * 4; m.frustum(SIMD3(cx, y, cz), SIMD3(cx, y + 0.3, cz), 2.2 - Float(k) * 0.4, 2.2 - Float(k) * 0.4, RGBA(120, 255, 220), seg: 12) }
        }
        // --- the hangar and an aeroplane on the apron
        m.box(7, -4, 30, 15, 4, 38, RGBA(150, 158, 168), faces: .all)
        m.hipRoof(7, 30, 15, 38, y0: 4, h: 1.5, o: 0.4, RGBA(110, 118, 128))
        let plane = SIMD3<Float>(11, 0.9, 50)
        m.frustum(plane + SIMD3(0, 0, -4), plane + SIMD3(0, 0, 4), 0.7, 0.4, RGBA(240, 242, 246), seg: 10)
        m.box(plane.x - 5, plane.y - 0.1, plane.z - 0.6, plane.x + 5, plane.y + 0.1, plane.z + 0.8, RGBA(220, 60, 60), faces: .all)
        m.box(plane.x - 2, plane.y, plane.z + 3, plane.x + 2, plane.y + 0.1, plane.z + 3.8, RGBA(220, 60, 60), faces: .all)
        m.box(plane.x - 0.08, plane.y, plane.z + 3, plane.x + 0.08, plane.y + 1.8, plane.z + 3.9, RGBA(220, 60, 60), faces: .all)
        return m
    }
}

extension MonumentArt {
    /// A nation's own landmark in the flat view: the tower standing up from its south side.
    static func fusionSprites(_ d: FusionDesign) -> [MonumentSprite] {
        let P = Float(FusionDesign.plot)
        return [MonumentSprite(key: "fusion-\(d.seed)-\(d.base)\(d.body)\(d.top)\(d.palette)-\(d.storeys)", x: P / 2, z: Float(FusionDesign.coreOrigin + FusionDesign.core),
                               w: P, h: d.totalHeight + 1) { ppt in fusionPicture(d, ppt: ppt) }]
    }

    /// The landmark seen from the south.
    public static func fusionPicture(_ d: FusionDesign, ppt: Double) -> Bitmap {
        let P = Double(FusionDesign.plot), C = Double(FusionDesign.core)
        let W = Int(P * ppt), H = Int((Double(d.totalHeight) + 1) * ppt)
        var c = Canvas(max(2, W), max(2, H), scale: 1)
        let s = ppt, gh = Double(H), cx = Double(W) / 2
        let (wall, trim, roof) = d.colors
        c.inkColor = ink
        let body = Double(d.bodyHeight)
        // the base
        switch d.base {
        case 0: for k in 0..<3 { let o = 12 - Double(k) * 3; c.rect(cx - (C / 2 + o) * s, gh - Double(k + 1) * 0.5 * s, (C + 2 * o) * s, 0.5 * s, RGBA(236, 234, 226), ink: 0.6) }
        case 1: c.rect(cx - 27 * s, gh - 3 * s, 54 * s, 3 * s, RGBA(176, 164, 140), ink: 1)
        case 2: for k in 0..<3 { let o = 10 - Double(k) * 3; c.rect(cx - (C / 2 + o) * s, gh - Double(k + 1) * s, (C + 2 * o) * s, s, RGBA(222, 198, 146), ink: 0.6) }
        default: for i in 0..<9 { let x = cx + (Double(i) - 4) * 4.6 * s; c.rect(x - 0.5 * s, gh - 6 * s, s, 6 * s, RGBA(236, 234, 226), ink: 0.5) }; c.rect(cx - 20 * s, gh - 6.6 * s, 40 * s, 0.8 * s, trim, ink: 0.6)
        }
        // the tower
        let x0 = cx - C / 2 * s
        c.rect(x0, gh - body * s, C * s, body * s, d.body == 0 ? RGBA(110, 160, 200) : (d.body == 4 ? RGBA(178, 44, 38) : (d.body == 2 ? wall.darkened(0.25) : wall)), ink: 1, shade: Shade(shadow: 0.12, light: 0.15))
        var y = 2.0
        while y < body {
            if d.body == 1 || d.body == 4 { if Int(y) % 6 == 0 { c.poly([(x0 - 2.4 * s, gh - y * s + 0.3 * s), (x0 + (C + 2.4) * s, gh - y * s + 0.3 * s), (x0 + (C - 1) * s, gh - (y + 1.2) * s), (x0 + s, gh - (y + 1.2) * s)], roof, ink: 0.6) } }
            else { c.rect(x0, gh - y * s, C * s, 0.2 * s, trim) }
            if d.body != 2 { for k in 0..<5 { c.rect(x0 + (1.2 + Double(k) * 3) * s, gh - (y - 0.4) * s, 1.6 * s, 1.1 * s, RGBA(255, 236, 160, 200)) } }
            y += 2
        }
        if d.body == 2 { for k in stride(from: 0.0, to: body, by: 8) { c.line(x0, gh - k * s, x0 + C * s, gh - (k + 8) * s, 0.25 * s, RGBA(110, 96, 80)); c.line(x0 + C * s, gh - k * s, x0, gh - (k + 8) * s, 0.25 * s, RGBA(110, 96, 80)) } }
        // the crown
        let t = gh - body * s
        switch d.top {
        case 0: c.rect(x0 + 3 * s, t - 4 * s, (C - 6) * s, 4 * s, wall.lightened(0.05), ink: 0.8); c.poly([(cx - 4.5 * s, t - 4 * s), (cx + 4.5 * s, t - 4 * s), (cx, t - 14 * s)], trim, ink: 0.8)
        case 1: c.rect(cx - 3 * s, t - 2 * s, 6 * s, 2 * s, RGBA(236, 234, 226), ink: 0.8)
                c.poly([(cx - 2.2 * s, t - 2 * s), (cx + 2.2 * s, t - 2 * s), (cx + 1.2 * s, t - 9 * s), (cx - 1.2 * s, t - 9 * s)], RGBA(108, 176, 150), ink: 0.8)
                c.ellipse(cx, t - 10 * s, 0.9 * s, 1.1 * s, RGBA(108, 176, 150), ink: 0.8); c.line(cx + 1.2 * s, t - 8.5 * s, cx + 1.6 * s, t - 12.4 * s, 0.5 * s, RGBA(108, 176, 150))
                c.ellipse(cx + 1.6 * s, t - 13 * s, 0.6 * s, 0.9 * s, RGBA(250, 196, 60))
        case 2: for k in 0..<3 { let i = Double(k) * 2.2, y0 = t - Double(k) * 3 * s
                    c.rect(x0 + (2 + i) * s, y0 - 1.6 * s, (C - 4 - 2 * i) * s, 1.6 * s, wall, ink: 0.6)
                    c.poly([(x0 + (0.4 + i) * s, y0 - 1.4 * s), (x0 + (C - 0.4 - i) * s, y0 - 1.4 * s), (x0 + (C - 4 - i) * s, y0 - 3 * s), (x0 + (4 + i) * s, y0 - 3 * s)], roof, ink: 0.6) }
        case 3: c.rect(cx - 6 * s, t - 3 * s, 12 * s, 3 * s, wall, ink: 0.8); c.ellipse(cx, t - 3 * s, 6 * s, 6.5 * s, roof, ink: 0.8); c.rect(cx - 6.5 * s, t - 3 * s, 13 * s, 3 * s, wall, ink: 0.8)
        case 4: c.rect(x0 + 2 * s, t - 5 * s, (C - 4) * s, 5 * s, wall.lightened(0.04), ink: 0.8); c.ellipse(cx, t - 2.5 * s, 1.9 * s, 1.9 * s, trim, ink: 0.8)
                c.ellipse(cx, t - 2.5 * s, 1.6 * s, 1.6 * s, RGBA(246, 244, 232)); c.poly([(cx - 6.5 * s, t - 5 * s), (cx + 6.5 * s, t - 5 * s), (cx, t - 13 * s)], roof, ink: 0.8)
        default: c.rect(x0 + s, t - s, (C - 2) * s, s, trim, ink: 0.6); c.line(cx, t - s, cx, t - 20 * s, 0.7 * s, RGBA(200, 205, 215))
                for k in 0..<4 { c.rect(cx - (2.2 - Double(k) * 0.4) * s, t - (4 + Double(k) * 4) * s, (4.4 - Double(k) * 0.8) * s, 0.3 * s, RGBA(120, 255, 220)) }
        }
        return c.image()
    }
}
