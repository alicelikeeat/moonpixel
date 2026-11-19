import Foundation

// National monuments. A nation's capital raises great landmarks, one after another as it grows: an imperial
// palace city in the manner of the Forbidden City (a moat, red walls and gates, courtyards, three great halls on
// white terraces under golden double roofs), a colossal statue holding up a torch in the manner of the Statue of
// Liberty (copper green, on a star-shaped pedestal on an island), a clock tower with four faces, an iron
// lattice tower, a stepped pyramid, a many-eaved pagoda. They are designs in those manners, not copies.
//
// Each stands on real tiles - its walls, floors, water, gates and gardens are the world's own, walked through
// like any building - and its great structure (the halls and roofs, the statue, the tower) is modelled in 3D
// and painted as a picture in 2D. A capital pays for each from its own stone and wood.

public enum MonumentKind: String, Codable, CaseIterable {
    case palace, liberty, clock, ironTower, pyramid, pagoda

    public func name(zh: Bool) -> String {
        switch self {
        case .palace: return zh ? "宫城" : "Palace City"
        case .liberty: return zh ? "自由之像" : "Statue of Freedom"
        case .clock: return zh ? "钟楼" : "Clock Tower"
        case .ironTower: return zh ? "铁塔" : "Iron Tower"
        case .pyramid: return zh ? "金字塔" : "Pyramid"
        case .pagoda: return zh ? "宝塔" : "Pagoda"
        }
    }
    /// The ground it takes, tiles.
    public var size: (w: Int, d: Int) {
        switch self {
        case .palace: return (30, 26)
        case .liberty: return (18, 18)
        case .clock: return (10, 10)
        case .ironTower: return (18, 18)
        case .pyramid: return (20, 20)
        case .pagoda: return (12, 12)
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
    public init() {}
    public var center: TilePos { TilePos(x + w / 2, y + d / 2) }
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
            emit("monument", [n.name(zh: zh), m.kind.name(zh: zh), s.name(zh: zh)], m.center.center)
        }
    }

    /// Raise a monument by a town (beside it, on clear land): its tiles laid now. Returns it, or nil when there
    /// is no room.
    @discardableResult public func raiseMonument(_ kind: MonumentKind, near s: Settlement, nation: Int) -> Monument? {
        let (w, d) = kind.size
        let live = settlements.values.filter { !$0.abandoned }
        let others = (realm.monuments ?? [])
        let r = Double(realm.cfg.cityRadius)
        for k in 0..<30 {
            let c = world.findSite(from: s.center, minR: r + Double(max(w, d)) / 2 + 4, maxR: r + 40 + Double(k) * 5, salt: 7700 + s.id * 13 + k * 7 + kind.hashValue & 0xff,
                                   avoid: live.filter { $0.id != s.id }.map { $0.center }, avoidDist: 30)
            if c.isNone { continue }
            let o = TilePos(c.x - w / 2, c.y - d / 2)
            if !monumentSiteClear(o, w, d, others: others) { continue }
            var m = Monument()
            m.id = (others.map { $0.id }.max() ?? 0) + 1
            m.kind = kind; m.nation = nation; m.town = s.id
            m.x = o.x; m.y = o.y; m.w = w; m.d = d; m.built = world.time
            carveMonument(m)
            realm.monuments = others + [m]
            return m
        }
        return nil
    }

    func monumentSiteClear(_ o: TilePos, _ w: Int, _ d: Int, others: [Monument]) -> Bool {
        if others.contains(where: { $0.x < o.x + w + 3 && o.x < $0.x + $0.w + 3 && $0.y < o.y + d + 3 && o.y < $0.y + $0.d + 3 }) { return false }
        if settlements.values.contains(where: { !$0.abandoned && ($0.inArea(o) || $0.inArea(TilePos(o.x + w, o.y + d)) || $0.inArea(TilePos(o.x + w, o.y)) || $0.inArea(TilePos(o.x, o.y + d))) }) { return false }
        // nothing built is pulled down for it (roads, buildings, fields); a pond or a stream across a corner is
        // filled, but not a lake
        var wet = 0
        for y in (o.y - 1)...(o.y + d) { for x in (o.x - 1)...(o.x + w) {
            if waterDepth(TilePos(x, y)) > 0 { wet += 1 }
            if let t = content.tile(world.tile(2, x, y)), !t.natural { return false }
            if content.tile(world.tile(0, x, y))?.built == true { return false }
        } }
        return wet * 10 <= (w + 2) * (d + 2)
    }

    /// The monuments within `reach` tiles of a tile.
    public func monuments(near t: TilePos, reach: Int) -> [Monument] {
        (realm.monuments ?? []).filter { abs($0.center.x - t.x) <= reach && abs($0.center.y - t.y) <= reach }
    }

    /// The tiles of a monument: what can be walked on and through.
    func carveMonument(_ m: Monument) {
        let T = { (k: String) in self.content.tid(k) }
        func set(_ x: Int, _ y: Int, ground: UInt8? = nil, obj: UInt8? = nil, decor: UInt8? = nil) {
            let wx = m.x + x, wy = m.y + y
            if let g = ground { world.setTile(0, wx, wy, g) }
            if let o = obj { world.setTile(2, wx, wy, o) }
            if let d = decor { world.setTile(3, wx, wy, d) }
        }
        // clear the ground first: nothing natural stays on it
        for y in 0..<m.d { for x in 0..<m.w { world.setTile(1, m.x + x, m.y + y, 0); world.setTile(2, m.x + x, m.y + y, 0); world.setTile(3, m.x + x, m.y + y, 0) } }
        let w = m.w, d = m.d, cx = w / 2
        switch m.kind {
        case .palace:
            // the moat, a bridge over it on the south; red walls with a gate; a paved court; three halls on the axis
            for y in 0..<d { for x in 0..<w {
                let moat = x == 0 || y == 0 || x == w - 1 || y == d - 1
                let wall = !moat && (x == 1 || y == 1 || x == w - 2 || y == d - 2)
                set(x, y, ground: moat ? T("shallow_water") : T("stone_floor"))
                if wall { set(x, y, obj: T("wall_brick")) }
            } }
            for x in (cx - 1)...(cx + 1) { set(x, d - 1, ground: T("stone_floor")); set(x, d - 2, obj: x == cx ? T("gate_open") : 0) }
            set(cx - 1, d - 2, obj: T("gate_open")); set(cx + 1, d - 2, obj: T("gate_open"))
            for (hy, hw, hd) in [(4, 14, 5), (11, 11, 4), (17, 9, 4)] {
                let hx = cx - hw / 2
                for y in hy..<(hy + hd) { for x in hx..<(hx + hw) {
                    let edge = x == hx || y == hy || x == hx + hw - 1 || y == hy + hd - 1
                    set(x, y, ground: T("wood_floor"), obj: edge ? (y == hy + hd - 1 && x == cx ? T("door_wood") : (y == hy + hd - 1 && (x - hx) % 2 == 1 ? T("wall_glass") : T("wall_brick"))) : 0)
                } }
                set(cx, hy + 1, obj: T("throne"))
            }
            // lanterns down the axis, guardian lions by the gate, pines in the corners, gardens
            for y in stride(from: 9, to: d - 3, by: 3) where y != 11 && y != 17 { set(cx - 3, y, obj: T("lantern_post")); set(cx + 3, y, obj: T("lantern_post")) }
            set(cx - 2, d - 4, obj: T("statue")); set(cx + 2, d - 4, obj: T("statue"))
            for (x, y) in [(3, 3), (w - 4, 3), (3, d - 4), (w - 4, d - 4)] { set(x, y, obj: T("tree_pine")) }
            for y in 5..<(d - 5) where y % 2 == 0 { set(3, y, decor: T("flower_red")); set(w - 4, y, decor: T("flower_yellow")) }
        case .liberty:
            // an island: water round, a pier from the south; a plaza; a star-shaped pedestal round the statue
            for y in 0..<d { for x in 0..<w {
                let dx = Double(x) - Double(w - 1) / 2, dy = Double(y) - Double(d - 1) / 2, r = (dx * dx + dy * dy).squareRoot()
                set(x, y, ground: r > 8 ? T("shallow_water") : (r > 7 ? T("sand") : T("stone_floor")))
                // the star: eleven points
                let a = atan2(dy, dx), star = 3.2 + 1.4 * cos(a * 11 / 2 * 2)
                if r < 1.6 { set(x, y, obj: T("statue")) } else if r < star && r > 2.4 { set(x, y, obj: T("wall_stone")) }
            } }
            for y in (d / 2 + 7)..<d { set(cx, y, ground: T("stone_floor")); set(cx - 1, y, ground: T("stone_floor")) }
            for (x, y) in [(cx - 5, cx - 5), (cx + 4, cx - 5), (cx - 5, cx + 4), (cx + 4, cx + 4)] { set(x, y, obj: T("lantern_post")) }
        case .clock:
            for y in 0..<d { for x in 0..<w { set(x, y, ground: T("stone_floor")) } }
            for y in 3...6 { for x in 3...6 {
                let edge = x == 3 || x == 6 || y == 3 || y == 6
                set(x, y, obj: edge ? (x == 4 && y == 6 ? T("door_wood") : T("wall_limestone")) : 0)
            } }
            set(5, 4, obj: T("stairs_up"))
            for (x, y) in [(1, 1), (8, 1), (1, 8), (8, 8)] { set(x, y, obj: T("lantern_post")) }
        case .ironTower:
            // a lawn with paths to the four feet, the feet standing on piers
            for y in 0..<d { for x in 0..<w {
                let path = abs(x - y) <= 0 || abs(x + y - (w - 1)) <= 0 || x == cx || y == d / 2
                set(x, y, ground: path ? T("stone_floor") : T("grass"))
            } }
            for (x, y) in [(3, 3), (w - 5, 3), (3, d - 5), (w - 5, d - 5)] { for dy in 0...1 { for dx in 0...1 { set(x + dx, y + dy, obj: T("spire_steel")) } } }
            for (x, y) in [(1, 1), (w - 2, 1), (1, d - 2), (w - 2, d - 2)] { set(x, y, obj: T("tree_oak")) }
        case .pyramid:
            // sand round a stepped pyramid of stone, a passage into its heart from the south
            for y in 0..<d { for x in 0..<w { set(x, y, ground: T("sand")) } }
            for y in 2..<(d - 2) { for x in 2..<(w - 2) {
                let passage = x == cx && y > d / 2
                set(x, y, ground: T("stone_floor"), obj: passage || (x == cx && y == d / 2) ? 0 : T("wall_limestone"))
            } }
            set(cx, d / 2, obj: T("chest"))
        case .pagoda:
            for y in 0..<d { for x in 0..<w { set(x, y, ground: T("grass")) } }
            for y in 3...8 { for x in 3...8 {
                let edge = x == 3 || x == 8 || y == 3 || y == 8
                set(x, y, ground: T("wood_floor"), obj: edge ? (x == 5 && y == 8 ? T("door_wood") : T("wall_wood")) : 0)
            } }
            set(5, 5, obj: T("altar")); set(6, 4, obj: T("stairs_up"))
            for (x, y) in [(1, 1), (10, 1), (1, 10), (10, 10)] { set(x, y, obj: T("tree_pine")) }
            for (x, y) in [(5, 10), (6, 10)] { set(x, y, ground: T("stone_floor")) }
            set(4, 10, obj: T("lantern_post")); set(7, 10, obj: T("lantern_post"))
        }
        keepClear(TilePos(m.x + cx, m.y + d))
    }
}

// MARK: - modelling the monuments

extension Mesh3D {
    /// A hip roof over the rectangle x0...x1, z0...z1 from eave height `y0` up `h` to a ridge, overhanging by `o`;
    /// `curl` lifts the corners of the eaves (a Chinese roof).
    public mutating func hipRoof(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float, y0: Float, h: Float, o: Float, curl: Float = 0, _ c: RGBA) {
        let a = SIMD3<Float>(x0 - o, y0 + curl, z0 - o), b = SIMD3<Float>(x1 + o, y0 + curl, z0 - o)
        let cc = SIMD3<Float>(x1 + o, y0 + curl, z1 + o), dd = SIMD3<Float>(x0 - o, y0 + curl, z1 + o)
        let inset = min(x1 - x0, z1 - z0) / 2
        let r0 = SIMD3<Float>(x0 + inset, y0 + h, (z0 + z1) / 2), r1 = SIMD3<Float>(x1 - inset, y0 + h, (z0 + z1) / 2)
        let midZ0 = SIMD3<Float>((x0 + x1) / 2, y0, z0 - o), midZ1 = SIMD3<Float>((x0 + x1) / 2, y0, z1 + o)
        // the long sides (front and back), the eave sagging between lifted corners
        face(dd, midZ1, r1, r0, c); face(midZ1, cc, r1, r1, c)
        face(b, midZ0, r0, r1, c); face(midZ0, a, r0, r0, c)
        // the hipped ends
        tri(a, dd, r0, c); tri(cc, b, r1, c)
        // the underside of the eaves, so the roof is seen from below too
        face(a, b, cc, dd, c.darkened(0.35))
    }
}

extension Figure3D {
    /// A monument's great structure, in tiles from its north-west corner (x along w, z along d), standing on y = 0.
    public static func monument(_ kind: MonumentKind) -> Mesh3D {
        var m = Mesh3D()
        let (w, d) = kind.size
        let W = Float(w), D = Float(d), cx = W / 2
        switch kind {
        case .palace:
            let red = RGBA(178, 40, 36), gold = RGBA(232, 176, 52), marble = RGBA(236, 234, 226), col = RGBA(150, 28, 28), beam = RGBA(40, 96, 120)
            for (hy, hw, hd, scale) in [(4, 14, 5, Float(1.0)), (11, 11, 4, 0.8), (17, 9, 4, 0.85)] as [(Int, Int, Int, Float)] {
                let x0 = cx - Float(hw) / 2, z0 = Float(hy), x1 = x0 + Float(hw), z1 = z0 + Float(hd)
                // a three-tiered white terrace, the hall on it
                for (k, inset) in [Float(-1.4), -0.9, -0.4].enumerated() {
                    m.box(x0 + inset, Float(k) * 0.35, z0 + inset, x1 - inset, Float(k + 1) * 0.35, z1 - inset, marble, faces: .all)
                }
                let base: Float = 1.05, wallH: Float = 2.6 * scale
                m.box(x0 + 0.3, base, z0 + 0.3, x1 - 0.3, base + wallH, z1 - 0.3, red, faces: .all)
                for i in 0...Int(hw) where i % 2 == 0 {
                    let x = x0 + Float(i)
                    m.frustum(SIMD3(x, base, z1 + 0.1), SIMD3(x, base + wallH, z1 + 0.1), 0.18, 0.16, col, seg: 8)
                }
                m.box(x0, base + wallH, z0, x1, base + wallH + 0.35, z1, beam, faces: .all)                      // the painted beam band
                // the golden double roof: a lower eave, then the upper hip roof with curled corners
                m.hipRoof(x0, z0, x1, z1, y0: base + wallH + 0.35, h: 0.5, o: 1.0, curl: 0.3, gold.darkened(0.06))
                m.box(x0 + 0.8, base + wallH + 0.6, z0 + 0.8, x1 - 0.8, base + wallH + 1.3, z1 - 0.8, red, faces: .all)
                m.hipRoof(x0 + 0.5, z0 + 0.5, x1 - 0.5, z1 - 0.5, y0: base + wallH + 1.3, h: 2.9 * scale, o: 1.1, curl: 0.35, gold)
            }
            // the gate tower over the south gate
            m.box(cx - 3, 0, D - 2.6, cx + 3, 2.4, D - 1.4, red, faces: .all)
            m.hipRoof(cx - 3, D - 2.6, cx + 3, D - 1.4, y0: 2.4, h: 1.2, o: 0.6, curl: 0.2, gold)
        case .liberty:
            let copper = RGBA(108, 176, 150), stone = RGBA(200, 192, 176), flame = RGBA(250, 196, 60)
            let c = SIMD3<Float>(cx, 0, D / 2)
            // the pedestal: a broad plinth and a tall shaft
            m.roundedBox(c.x - 2.2, 0, c.z - 2.2, c.x + 2.2, 1.2, c.z + 2.2, r: 0.2, stone)
            m.roundedBox(c.x - 1.5, 1.2, c.z - 1.5, c.x + 1.5, 6.5, c.z + 1.5, r: 0.15, stone.darkened(0.05))
            m.roundedBox(c.x - 1.8, 6.5, c.z - 1.8, c.x + 1.8, 7.0, c.z + 1.8, r: 0.1, stone)
            // the figure: a long robe, shoulders, a head with a spiked crown, the torch held high, a tablet in the other arm
            let foot: Float = 7.0
            m.frustum(c + SIMD3(0, foot, 0), c + SIMD3(0, foot + 6.5, 0), 1.3, 0.75, copper, seg: 14)
            m.ellipsoid(c + SIMD3(0, foot + 6.7, 0), SIMD3(0.95, 0.55, 0.7), copper, seg: 12, rings: 5)
            m.frustum(c + SIMD3(0, foot + 7.0, 0), c + SIMD3(0, foot + 7.5, 0), 0.25, 0.22, copper, seg: 8)
            m.ellipsoid(c + SIMD3(0, foot + 8.1, 0), SIMD3(0.5, 0.62, 0.5), copper, seg: 12, rings: 6)
            for i in 0..<7 {
                let a = Float(i) / 7 * .pi - .pi / 2 - 0.1
                let base = c + SIMD3(cos(a) * 0.35, foot + 8.55, sin(a) * 0.35 + 0.2)
                m.frustum(base, base + SIMD3(cos(a) * 0.9, 0.55, sin(a) * 0.5 + 0.3), 0.1, 0.0, copper.lightened(0.05), seg: 4)
            }
            m.frustum(c + SIMD3(0.8, foot + 6.4, 0), c + SIMD3(1.0, foot + 10.2, 0.2), 0.3, 0.24, copper, seg: 8)   // the raised arm
            m.frustum(c + SIMD3(1.0, foot + 10.2, 0.2), c + SIMD3(1.05, foot + 11.0, 0.2), 0.28, 0.42, copper.darkened(0.1), seg: 8)
            m.ellipsoid(c + SIMD3(1.05, foot + 11.45, 0.2), SIMD3(0.4, 0.6, 0.4), flame, seg: 10, rings: 5)
            m.frustum(c + SIMD3(-0.8, foot + 6.2, 0), c + SIMD3(-0.9, foot + 4.6, 0.5), 0.26, 0.22, copper, seg: 8)  // the other arm
            m.roundedBox(c.x - 1.4, foot + 4.2, c.z + 0.3, c.x - 0.6, foot + 5.6, c.z + 0.65, r: 0.06, copper.darkened(0.05))  // the tablet
        case .clock:
            let stone = RGBA(214, 196, 150), gold = RGBA(226, 186, 76), face = RGBA(246, 244, 232), roof = RGBA(64, 92, 84)
            let x0: Float = 3, x1: Float = 7, z0: Float = 3, z1: Float = 7
            m.box(x0, 0, z0, x1, 15, z1, stone, faces: .all)
            for i in 0..<8 { let y = Float(i) * 1.8 + 1; m.box(x0 - 0.05, y, z0 - 0.05, x1 + 0.05, y + 0.12, z1 + 0.05, stone.darkened(0.15), faces: .all) }
            // the clock stage: wider, a face on each side with hands
            m.box(x0 - 0.4, 15, z0 - 0.4, x1 + 0.4, 18.5, z1 + 0.4, stone.lightened(0.05), faces: .all)
            let mid = SIMD3<Float>((x0 + x1) / 2, 16.75, (z0 + z1) / 2)
            for (dx, dz) in [(Float(0), Float(-1)), (0, 1), (-1, 0), (1, 0)] {
                let at = mid + SIMD3(dx * 2.45, 0, dz * 2.45)
                let axis = SIMD3<Float>(dx, 0, dz)
                m.frustum(at, at + axis * 0.08, 1.35, 1.35, gold, seg: 16)
                m.frustum(at + axis * 0.08, at + axis * 0.12, 1.15, 1.15, face, seg: 16)
                m.frustum(at + axis * 0.12, at + axis * 0.14 + SIMD3(0, 0.9, 0), 0.06, 0.04, RGBA(30, 30, 36), seg: 4)
                m.frustum(at + axis * 0.12, at + axis * 0.14 + SIMD3(dz * 0.6, 0.1, -dx * 0.6), 0.06, 0.04, RGBA(30, 30, 36), seg: 4)
            }
            // the belfry and the spire
            m.box(x0 + 0.3, 18.5, z0 + 0.3, x1 - 0.3, 20.5, z1 - 0.3, stone, faces: .all)
            m.frustum(SIMD3(mid.x, 20.5, mid.z), SIMD3(mid.x, 26, mid.z), 2.2, 0.05, roof, seg: 4)
            m.frustum(SIMD3(mid.x, 26, mid.z), SIMD3(mid.x, 27, mid.z), 0.12, 0.02, gold, seg: 6)
        case .ironTower:
            let iron = RGBA(108, 96, 80), deck = RGBA(130, 118, 98)
            let feet: [SIMD3<Float>] = [[4, 0, 4], [W - 4, 0, 4], [4, 0, D - 4], [W - 4, 0, D - 4]]
            let top = SIMD3<Float>(cx, 0, D / 2)
            // four legs leaning in to the first platform, then on to the second, then the mast
            for f in feet {
                let p1 = top + (f - top) * 0.45 + SIMD3(0, 7, 0)
                m.frustum(f + SIMD3(0, 0.5, 0), p1, 0.7, 0.45, iron, seg: 4)
                let p2 = top + (f - top) * 0.18 + SIMD3(0, 15, 0)
                m.frustum(p1, p2, 0.45, 0.3, iron, seg: 4)
                m.frustum(p2, top + SIMD3(0, 24, 0), 0.3, 0.15, iron, seg: 4)
                m.box(f.x - 0.8, 0, f.z - 0.8, f.x + 0.8, 0.6, f.z + 0.8, deck, faces: .all)
            }
            // lattice bands between the legs, the platforms, the arches at the foot
            for (y, k) in [(Float(3.5), Float(0.72)), (10.5, 0.33), (19, 0.1)] {
                let s = (W / 2 - 4) * k + 0.6
                m.box(cx - s, y, D / 2 - s, cx + s, y + 0.25, D / 2 + s, iron.darkened(0.1), faces: .all)
            }
            m.box(cx - 3.6, 7, D / 2 - 3.6, cx + 3.6, 7.6, D / 2 + 3.6, deck, faces: .all)
            m.box(cx - 1.7, 15, D / 2 - 1.7, cx + 1.7, 15.5, D / 2 + 1.7, deck, faces: .all)
            m.frustum(top + SIMD3(0, 24, 0), top + SIMD3(0, 28, 0), 0.25, 0.05, iron, seg: 6)
        case .pyramid:
            let sand = RGBA(222, 196, 140)
            for k in 0..<8 {
                let inset = 2 + Float(k) * 1.0
                m.box(inset, Float(k) * 1.2, inset, W - inset, Float(k + 1) * 1.2, D - inset, sand.darkened(Double(k) * 0.015), faces: .all)
            }
            m.frustum(SIMD3(cx, 9.6, D / 2), SIMD3(cx, 11.2, D / 2), 1.3, 0.02, RGBA(236, 206, 120), seg: 4)
        case .pagoda:
            let wood = RGBA(150, 52, 40), roof = RGBA(52, 72, 70), gold = RGBA(220, 170, 60)
            var y: Float = 0
            for tier in 0..<7 {
                let s = 3.0 - Float(tier) * 0.32
                let x0 = cx - s, x1 = cx + s, z0 = D / 2 - s, z1 = D / 2 + s
                let h: Float = tier == 0 ? 2.4 : 1.5
                m.box(x0, y, z0, x1, y + h, z1, wood, faces: .all)
                m.hipRoof(x0, z0, x1, z1, y0: y + h, h: 0.7, o: 0.9, curl: 0.25, roof)
                y += h + 0.7
            }
            m.frustum(SIMD3(cx, y, D / 2), SIMD3(cx, y + 3, D / 2), 0.18, 0.04, gold, seg: 6)
            for k in 0..<5 { m.ellipsoid(SIMD3(cx, y + 0.4 + Float(k) * 0.45, D / 2), SIMD3(0.3, 0.12, 0.3), gold, seg: 8, rings: 3) }
        }
        return m
    }
}

public enum MonumentArt {
    /// A monument as a picture seen from the front (for the flat view): its width is its ground's, its height
    /// what the structure rises to, in pixels at `ppt` a tile.
    public static func picture(_ kind: MonumentKind, ppt: Double = 16) -> Bitmap {
        let (w, _) = kind.size
        let tall: Double = [MonumentKind.palace: 8, .liberty: 20, .clock: 27, .ironTower: 28, .pyramid: 11, .pagoda: 16][kind] ?? 10
        let W = Int(Double(w) * ppt), H = Int(tall * ppt)
        var c = Canvas(W, H, scale: 1)
        let s = ppt, gw = Double(W), gh = Double(H), cx = gw / 2
        c.inkColor = RGBA(40, 30, 30)
        switch kind {
        case .palace:
            let red = RGBA(178, 40, 36), gold = RGBA(232, 176, 52), marble = RGBA(236, 234, 226)
            c.rect(cx - 7.5 * s, gh - 1.2 * s, 15 * s, 1.2 * s, marble, ink: 1)
            c.rect(cx - 6.5 * s, gh - 4.2 * s, 13 * s, 3 * s, red, ink: 1)
            for i in 0...12 { c.rect(cx - 6.4 * s + Double(i) * s, gh - 4.2 * s, 0.25 * s, 3 * s, RGBA(130, 24, 24)) }
            c.poly([(cx - 8.2 * s, gh - 4.2 * s), (cx + 8.2 * s, gh - 4.2 * s), (cx + 6.5 * s, gh - 5.0 * s), (cx - 6.5 * s, gh - 5.0 * s)], gold, ink: 1)
            c.rect(cx - 5.5 * s, gh - 5.8 * s, 11 * s, 0.8 * s, red, ink: 1)
            c.poly([(cx - 7.5 * s, gh - 5.6 * s), (cx + 7.5 * s, gh - 5.6 * s), (cx + 4 * s, gh - 7.6 * s), (cx - 4 * s, gh - 7.6 * s)], gold, ink: 1, shade: Shade(shadow: 0.15, light: 0.25))
            for x in [-7.6, 7.6] { c.curve([(cx + x * s, gh - 5.6 * s), (cx + x * 1.06 * s, gh - 6.2 * s)], 0.25 * s, gold) }
        case .liberty:
            let copper = RGBA(108, 176, 150), stone = RGBA(200, 192, 176)
            c.rect(cx - 2.2 * s, gh - 1.2 * s, 4.4 * s, 1.2 * s, stone, ink: 1)
            c.rect(cx - 1.5 * s, gh - 7 * s, 3 * s, 5.8 * s, stone.darkened(0.05), ink: 1)
            c.poly([(cx - 1.3 * s, gh - 7 * s), (cx + 1.3 * s, gh - 7 * s), (cx + 0.75 * s, gh - 13.5 * s), (cx - 0.75 * s, gh - 13.5 * s)], copper, ink: 1, shade: Shade(shadow: 0.2, light: 0.2))
            c.ellipse(cx, gh - 15.1 * s, 0.55 * s, 0.65 * s, copper, ink: 1)
            for i in 0..<7 { let a = -.pi / 2 + (Double(i) - 3) * 0.32; c.line(cx, gh - 15.4 * s, cx + cos(a) * 1.1 * s, gh - 15.4 * s + sin(a) * 1.1 * s, 0.18 * s, copper) }
            c.line(cx + 0.7 * s, gh - 13.3 * s, cx + 1.0 * s, gh - 17.6 * s, 0.5 * s, copper)
            c.ellipse(cx + 1.0 * s, gh - 18.3 * s, 0.4 * s, 0.7 * s, RGBA(250, 196, 60), ink: 0.8)
            c.rect(cx - 1.5 * s, gh - 12 * s, 0.7 * s, 1.4 * s, copper.darkened(0.1), ink: 0.8)
        case .clock:
            let stone = RGBA(214, 196, 150), gold = RGBA(226, 186, 76)
            c.rect(cx - 2 * s, gh - 15 * s, 4 * s, 15 * s, stone, ink: 1, shade: Shade(shadow: 0.1, light: 0.15))
            c.rect(cx - 2.4 * s, gh - 18.5 * s, 4.8 * s, 3.5 * s, stone.lightened(0.05), ink: 1)
            c.ellipse(cx, gh - 16.75 * s, 1.35 * s, 1.35 * s, gold, ink: 1)
            c.ellipse(cx, gh - 16.75 * s, 1.1 * s, 1.1 * s, RGBA(246, 244, 232))
            c.line(cx, gh - 16.75 * s, cx, gh - 17.6 * s, 0.12 * s, RGBA(20, 20, 26)); c.line(cx, gh - 16.75 * s, cx + 0.6 * s, gh - 16.6 * s, 0.12 * s, RGBA(20, 20, 26))
            c.rect(cx - 1.7 * s, gh - 20.5 * s, 3.4 * s, 2 * s, stone, ink: 1)
            c.poly([(cx - 2.1 * s, gh - 20.5 * s), (cx + 2.1 * s, gh - 20.5 * s), (cx, gh - 26.5 * s)], RGBA(64, 92, 84), ink: 1)
        case .ironTower:
            let iron = RGBA(108, 96, 80)
            c.poly([(cx - 7 * s, gh), (cx - 4.5 * s, gh), (cx - 0.4 * s, gh - 24 * s), (cx - 0.9 * s, gh - 24 * s)], iron, ink: 1)
            c.poly([(cx + 7 * s, gh), (cx + 4.5 * s, gh), (cx + 0.4 * s, gh - 24 * s), (cx + 0.9 * s, gh - 24 * s)], iron, ink: 1)
            c.curve([(cx - 4.5 * s, gh), (cx, gh - 3.5 * s), (cx + 4.5 * s, gh)], 0.35 * s, iron)
            c.rect(cx - 4 * s, gh - 7.6 * s, 8 * s, 0.6 * s, iron.lightened(0.1), ink: 0.8)
            c.rect(cx - 1.9 * s, gh - 15.5 * s, 3.8 * s, 0.5 * s, iron.lightened(0.1), ink: 0.8)
            c.line(cx, gh - 24 * s, cx, gh - 28 * s, 0.25 * s, iron)
            for k in 0..<12 { let y = gh - Double(k) * 2 * s; c.line(cx - (7 - Double(k) * 0.55) * s, y, cx + (7 - Double(k) * 0.55) * s, y - s, 0.1 * s, iron.darkened(0.2)) }
        case .pyramid:
            let sand = RGBA(222, 196, 140)
            for k in 0..<8 { let inset = (2 + Double(k)) * s; c.rect(inset, gh - Double(k + 1) * 1.2 * s, gw - 2 * inset, 1.2 * s, sand.darkened(Double(k) * 0.02), ink: 0.8) }
            c.poly([(cx - 1.3 * s, gh - 9.6 * s), (cx + 1.3 * s, gh - 9.6 * s), (cx, gh - 11 * s)], RGBA(236, 206, 120), ink: 0.8)
        case .pagoda:
            var y = gh
            for tier in 0..<7 {
                let half = (3.0 - Double(tier) * 0.32) * s, h = (tier == 0 ? 2.4 : 1.5) * s
                c.rect(cx - half, y - h, 2 * half, h, RGBA(150, 52, 40), ink: 0.8)
                y -= h
                c.poly([(cx - half - 0.9 * s, y + 0.25 * s), (cx + half + 0.9 * s, y + 0.25 * s), (cx + half * 0.6, y - 0.7 * s), (cx - half * 0.6, y - 0.7 * s)], RGBA(52, 72, 70), ink: 0.8)
                y -= 0.7 * s
            }
            c.line(cx, y, cx, y - 3 * s, 0.2 * s, RGBA(220, 170, 60))
        }
        return c.image()
    }
}
