import Foundation

public struct GrowTimer: Codable {
    public var i: Int, l: Int, to: UInt8, due: Double, expect: UInt8
}

public struct Prop: Codable {
    public var id: Int, key: String, x: Double, y: Double
}

/// One 32x32 chunk: four tile layers plus timers and free-positioned props.
public final class Chunk {
    public let cx: Int, cy: Int
    public var layers: [[UInt8]]
    public var timers: [GrowTimer] = []
    public var props: [Prop] = []
    public var modified = false
    public var dirty = false
    public var revision = 0
    public var lastUsed = 0

    public init(cx: Int, cy: Int) {
        self.cx = cx; self.cy = cy
        layers = Array(repeating: [UInt8](repeating: 0, count: MP.chunkArea), count: 4)
    }

    public var key: Int64 { MP.chunkKey(cx, cy) }
    public func touch() { modified = true; dirty = true; revision += 1 }

    struct Saved: Codable {
        var v: Int, cx: Int, cy: Int, l0: Data, l1: Data, l2: Data, l3: Data, timers: [GrowTimer], props: [Prop], revision: Int
    }

    public func encoded() -> Data {
        let s = Saved(v: 1, cx: cx, cy: cy, l0: Data(layers[0]), l1: Data(layers[1]), l2: Data(layers[2]), l3: Data(layers[3]),
                      timers: timers, props: props, revision: revision)
        return (try? JSONEncoder().encode(s)) ?? Data()
    }

    /// nil when the data is truncated, corrupt or from an unknown format.
    public static func decode(_ data: Data) -> Chunk? {
        guard let s = try? JSONDecoder().decode(Saved.self, from: data), s.v == 1,
              s.l0.count == MP.chunkArea, s.l1.count == MP.chunkArea, s.l2.count == MP.chunkArea, s.l3.count == MP.chunkArea else { return nil }
        let c = Chunk(cx: s.cx, cy: s.cy)
        c.layers = [[UInt8](s.l0), [UInt8](s.l1), [UInt8](s.l2), [UInt8](s.l3)]
        c.timers = s.timers
        c.props = s.props
        c.revision = s.revision
        c.modified = true
        return c
    }
}

/// Unbounded deterministic terrain: every tile is a pure function of (seed, x, y).
public final class Generator {
    public let seed: Int
    /// Climate shifts chosen when the world was created (see WorldRecipe).
    public var tempBias = 0.0, moistBias = 0.0, elevBias = 0.0
    public var depth = 0
    /// Oceans and continents (worlds made from v2.16 on; WorldRecipe.oceans): a slow continental swell is added
    /// to the land's height, so open seas join up between continents. Off, the land is as it always was.
    public var oceans = false
    /// Ground levelled for monuments (set from the realm's monuments: Society.syncFlats).
    public struct Flat: Equatable { public let x0: Int, y0: Int, x1: Int, y1: Int, e: Double }
    /// The 3D view builds terrain on background threads (reading the ground's height) while the game, on the
    /// main thread, may level ground for a monument or load a saved world: the list is only ever read and
    /// replaced whole, under a lock.
    public var flats: [Flat] {
        get { flatLock.lock(); defer { flatLock.unlock() }; return _flats }
        set { flatLock.lock(); _flats = newValue; flatLock.unlock() }
    }
    private var _flats: [Flat] = []
    private let flatLock = NSLock()
    public static let flatBlend = 24
    let content = Content.shared
    let nElev, nTemp, nMoist, nRiver, nForest, nDetail, nHill: Noise
    let nCont: Noise
    var ground = [UInt8](), alt = [UInt8](), altCh = [Double](), density = [Double]()
    var trees = [[(UInt8, Double)]](), objects = [[(UInt8, Double)]](), decor = [[(UInt8, Double)]]()
    let tDeep, tWater, tShallow, tIce, tSand, tMud, tSnow, tCliff, tReeds, tLily: UInt8

    public init(seed: Int) {
        self.seed = seed
        nElev = Noise(seed: seed + 1, frequency: 0.0035, octaves: 4)
        nTemp = Noise(seed: seed + 2, frequency: 0.0005, octaves: 2)
        nMoist = Noise(seed: seed + 3, frequency: 0.002, octaves: 3)
        nRiver = Noise(seed: seed + 4, frequency: 0.005, octaves: 2)
        nForest = Noise(seed: seed + 5, frequency: 0.035, octaves: 2)
        nDetail = Noise(seed: seed + 6, frequency: 0.09, octaves: 1)
        nHill = Noise(seed: seed + 7, frequency: 0.011, octaves: 3)
        nCont = Noise(seed: seed + 11, frequency: 0.00022, octaves: 3)
        let c = Content.shared
        tDeep = c.tid("deep_water"); tWater = c.tid("water"); tShallow = c.tid("shallow_water"); tIce = c.tid("ice")
        tSand = c.tid("sand"); tMud = c.tid("mud"); tSnow = c.tid("snow"); tCliff = c.tid("cliff"); tReeds = c.tid("reeds"); tLily = c.tid("lily_pad")
        func cum(_ l: [(String, Double)]) -> [(UInt8, Double)] {
            var acc = 0.0
            return l.map { acc += $0.1; return (c.tid($0.0), acc) }
        }
        for b in c.biomes {
            ground.append(c.tid(b.ground)); alt.append(c.tid(b.alt)); altCh.append(b.altChance); density.append(b.treeDensity)
            trees.append(cum(b.trees)); objects.append(cum(b.objects)); decor.append(cum(b.decor))
        }
    }

    /// The continental swell at a place (0 when the world has no oceans): seas where it is low, continents
    /// where it is high (land is lifted only a little, so continents look like the land always did). Within
    /// 300 tiles of the start there is no swell at all (the land there is exactly as in any world), and it
    /// comes in over the next 400 tiles.
    @inline(__always) public func continental(_ x: Double, _ y: Double) -> Double {
        guard oceans else { return 0 }
        let fade = Swift.min(1, Swift.max(0, ((x * x + y * y).squareRoot() - 300) / 400))
        guard fade > 0 else { return 0 }
        var c = Generator.oceanAmp * nCont.get(x, y) + Generator.oceanBias
        if c > 0 { c *= 0.35 }
        return c * fade
    }
    static let oceanAmp = 0.55, oceanBias = -0.1

    /// (elevation, temperature, moisture)
    public func climate(_ wx: Int, _ wy: Int) -> (Double, Double, Double) {
        let x = Double(wx), y = Double(wy)
        return (0.5 + elevBias + 0.62 * nElev.get(x, y) + continental(x, y), min(1, max(0, 0.5 + tempBias + 1.0 * nTemp.get(x, y))), min(1, max(0, 0.5 + moistBias + 0.85 * nMoist.get(x, y))))
    }

    public func biome(_ wx: Int, _ wy: Int) -> Int {
        let c = climate(wx, wy)
        return Biome.classify(c.0, c.1, c.2)
    }

    public func isRiver(_ wx: Int, _ wy: Int, _ e: Double) -> Bool {
        e >= Biome.sea && e < Biome.mountainLevel && abs(nRiver.get(Double(wx), Double(wy))) < 0.012
    }

    /// The underground: rock everywhere, tunnels and caverns cut by noise, lakes
    /// in the low places, ore in the walls, and now and then a ruin with a chest.
    func generateCave(_ cx: Int, _ cy: Int) -> Chunk {
        let c = Chunk(cx: cx, cy: cy)
        let ct = Content.shared
        let floor = ct.tid("cave_floor"), wall = ct.tid("cave_wall"), lake = ct.tid("cave_water")
        let ores: [(UInt8, Double)] = [(ct.tid("ore_iron"), 0.05), (ct.tid("ore_copper"), 0.08), (ct.tid("ore_moon"), 0.09), (ct.tid("ore_gold"), 0.10)]
        var g = [UInt8](repeating: floor, count: MP.chunkArea), st = [UInt8](repeating: 0, count: MP.chunkArea), ob = st, de = st
        for ty in 0..<32 { for tx in 0..<32 {
            let wx = cx * 32 + tx, wy = cy * 32 + ty
            let x = Double(wx), y = Double(wy)
            let tunnel = abs(nForest.get(x * 0.5, y * 0.5)), cavern = nMoist.get(x * 6, y * 6), wet = nRiver.get(x * 2, y * 2)
            let open = tunnel < 0.16 || cavern > 0.22
            let i = ty * 32 + tx
            if !open {
                let r = Double(MP.h2(seed &+ 31, wx, wy) & 0xffff) / 65536.0
                ob[i] = ores.first { r < $0.1 }?.0 ?? wall
            } else if cavern > 0.3 && wet > 0.25 {
                g[i] = lake
            } else if MP.h01(seed &+ 5, wx, wy) < 0.012 { de[i] = ct.tid("mushroom") }
        } }
        if isUnderCity(cx, cy) {
            carveUnderCity(cx, cy, &g, &ob, &de)
            c.layers = [g, st, ob, de]
            return c
        }
        // one ruin in every 3x3 block of chunks
        let rx = Int((Double(cx) / 3).rounded(.down)), ry = Int((Double(cy) / 3).rounded(.down))
        let h = MP.h2(seed &+ 555, rx, ry)
        if rx * 3 + Int(h % 3) == cx && ry * 3 + Int((h >> 8) % 3) == cy {
            let rwall = ct.tid("ruin_wall"), rfloor = ct.tid("ruin_floor")
            for y in 10...20 { for x in 10...20 {
                let i = y * 32 + x
                let edge = x == 10 || x == 20 || y == 10 || y == 20
                g[i] = rfloor; de[i] = 0
                ob[i] = edge && !(x == 15 && (y == 10 || y == 20)) ? rwall : 0
            } }
            ob[15 * 32 + 15] = ct.tid("chest")
            for (x, y) in [(15, 9), (15, 8), (15, 21), (15, 22)] { ob[y * 32 + x] = 0; g[y * 32 + x] = floor }
        }
        c.layers = [g, st, ob, de]
        return c
    }

    public func isUnderRuin(_ cx: Int, _ cy: Int) -> Bool {
        let rx = Int((Double(cx) / 3).rounded(.down)), ry = Int((Double(cy) / 3).rounded(.down))
        let h = MP.h2(seed &+ 555, rx, ry)
        return rx * 3 + Int(h % 3) == cx && ry * 3 + Int((h >> 8) % 3) == cy
    }

    public func generate(_ cx: Int, _ cy: Int) -> Chunk {
        if depth == 1 { return generateCave(cx, cy) }
        // a storey above the ground is air until someone lays a floor on it
        if depth >= OpenWorld.storeyBase { return Chunk(cx: cx, cy: cy) }
        let c = Chunk(cx: cx, cy: cy)
        var g = [UInt8](repeating: 0, count: MP.chunkArea), st = g, ob = g, de = g
        let bx = cx * 32, by = cy * 32
        let solid = content.solid
        for ty in 0..<32 {
            let wy = by + ty
            for tx in 0..<32 {
                let wx = bx + tx
                let x = Double(wx), y = Double(wy)
                let dn = nDetail.get(x, y)
                let e = 0.5 + elevBias + 0.62 * nElev.get(x, y) + continental(x, y) + dn * 0.006
                let t = min(1, max(0, 0.5 + tempBias + 1.0 * nTemp.get(x, y) + dn * 0.012))
                let m = min(1, max(0, 0.5 + moistBias + 0.85 * nMoist.get(x, y) + dn * 0.012))
                let fo = nForest.get(x, y)
                let b = Biome.classify(e, t, m)
                let h = MP.h2(seed, wx, wy)
                let r1 = Double(h & 0xffff) / 65536.0
                let r2 = Double((h >> 16) & 0xffff) / 65536.0
                let idx = ty * 32 + tx
                var gr: UInt8 = 0
                var natural = true
                var cliff = false
                if b == Biome.ocean {
                    natural = false
                    if t < 0.27 && e > Biome.sea - 0.035 { gr = tIce }
                    else if e < Biome.sea - 0.05 { gr = tDeep }
                    else if e < Biome.sea - 0.012 { gr = tWater }
                    else { gr = tShallow }
                } else {
                    gr = r2 < altCh[b] ? alt[b] : ground[b]
                    if b == Biome.mountain {
                        if t < 0.36 { gr = tSnow }
                        cliff = e > Biome.mountainLevel + 0.012 && abs(fo) > 0.10
                    } else if b == Biome.canyon {
                        cliff = fo > 0.26
                    } else if b == Biome.wetland && fo < -0.22 {
                        gr = tShallow
                        natural = false
                        if r2 < 0.12 { de[idx] = tLily }
                    }
                    let rv = abs(nRiver.get(x, y))
                    if e < Biome.mountainLevel && rv < 0.022 {
                        cliff = false
                        natural = false
                        if rv < 0.012 {
                            gr = t < 0.27 ? tIce : (rv > 0.008 ? tShallow : tWater)
                            de[idx] = 0
                        } else if t >= 0.30 {
                            gr = b == Biome.wetland ? tMud : tSand
                            if t < 0.7 && r2 < 0.2 { de[idx] = tReeds }
                        }
                    }
                }
                g[idx] = gr
                if cliff {
                    st[idx] = tCliff
                } else if natural && !solid[Int(gr)] {
                    let dens = min(0.30, density[b] * min(2.4, max(0.15, 1.0 + fo * 2.2)))
                    if r1 < dens {
                        let tr = trees[b]
                        if let last = tr.last {
                            let pick = Double((h >> 8) & 0xff) / 256.0 * last.1
                            ob[idx] = tr.first { pick < $0.1 }?.0 ?? last.0
                        }
                    } else {
                        let rr = r1 - dens
                        if let o = objects[b].first(where: { rr < $0.1 }) {
                            ob[idx] = o.0
                        } else if let d = decor[b].first(where: { r2 < $0.1 }) {
                            de[idx] = d.0
                        }
                    }
                }
            }
        }
        // landmarks: a volcano's cone and crater, a UFO airport, the stairway down to an underground city
        if let v = volcano(near: bx + 16, by + 16, radius: 48) { shapeVolcano(v, cx, cy, &g, &st, &ob, &de) }
        if isUfoPort(cx, cy) { carveUfoPort(cx, cy, &g, &st, &ob, &de) }
        else if isUnderCity(cx, cy) && volcano(near: bx + 16, by + 16, radius: 40) == nil { carveCityStair(&g, &st, &ob, &de) }
        c.layers = [g, st, ob, de]
        return c
    }

    /// The old mazes are gone from the world (kept as a name: always false).
    public func isMaze(_ cx: Int, _ cy: Int) -> Bool { false }

    // MARK: landmarks

    /// One chunk in every 14x14 block of chunks (about one every 900 m each way) is a UFO airport, on land and
    /// away from where the first villages are founded.
    public static let ufoSpacing = 14
    public func isUfoPort(_ cx: Int, _ cy: Int) -> Bool {
        if depth > 0 { return false }
        let n = Generator.ufoSpacing
        let rx = Int((Double(cx) / Double(n)).rounded(.down)), ry = Int((Double(cy) / Double(n)).rounded(.down))
        let h = MP.h2(seed &+ 77, rx, ry)
        if rx * n + Int(h % UInt32(n)) != cx || ry * n + Int((h >> 8) % UInt32(n)) != cy { return false }
        if abs(cx) <= 3 && abs(cy) <= 3 { return false }
        let e = climate(cx * 32 + 16, cy * 32 + 16).0
        guard e > Biome.sea + 0.03 && e < Biome.mountainLevel - 0.03 else { return false }
        return volcano(near: cx * 32 + 16, cy * 32 + 16, radius: 40) == nil
    }

    /// A volcano: one in every 8x8 block of chunks may have one (on land, away from the first villages), its
    /// centre somewhere in the block's middle; the cone is `r` tiles across the base.
    public struct Volcano: Equatable { public let x: Int, y: Int, r: Int }

    /// The volcano whose centre is within `radius` tiles of (wx, wy), if any.
    public func volcano(near wx: Int, _ wy: Int, radius: Int) -> Volcano? {
        if depth > 0 { return nil }
        let bxs = Int((Double(wx) / 256).rounded(.down)), bys = Int((Double(wy) / 256).rounded(.down))
        for by in (bys - 1)...(bys + 1) { for bx in (bxs - 1)...(bxs + 1) {
            let h = MP.h2(seed &+ 4242, bx, by)
            guard h % 8 == 0 else { continue }                                   // one block in eight
            let vx = bx &* 256 &+ 64 &+ Int((h >> 4) % 128), vy = by &* 256 &+ 64 &+ Int((h >> 12) % 128)
            if abs(vx) < 200 && abs(vy) < 200 { continue }
            // (in Double: far-off numbers must not overflow)
            let dx = Double(vx) - Double(wx), dy = Double(vy) - Double(wy)
            guard dx * dx + dy * dy <= Double(radius * radius) else { continue }
            let e = climate(vx, vy).0
            guard e > Biome.sea + 0.06 else { continue }
            return Volcano(x: vx, y: vy, r: 26)
        } }
        return nil
    }

    /// How much a volcano raises the ground at (wx, wy): a cone rising to its rim, the crater sunk in the top.
    func volcanoLift(_ wx: Int, _ wy: Int) -> Double {
        guard let v = volcano(near: wx, wy, radius: 30) else { return 0 }
        let d = Double((v.x - wx) * (v.x - wx) + (v.y - wy) * (v.y - wy)).squareRoot()
        let R = Double(v.r)
        guard d < R else { return 0 }
        // a steep cone (its upper slopes past the mountain line, where the land climbs fastest)
        var lift = 0.62 * pow(1 - d / R, 1.15)
        if d < 5.5 { lift -= 0.24 * (1 - d / 5.5) }                                 // the crater
        return lift
    }

    /// A volcano on the tiles of this chunk: black basalt slopes with scattered rocks, the crater a pool of lava
    /// with a rim, two lava streams running down the sides; no trees on it.
    func shapeVolcano(_ v: Volcano, _ cx: Int, _ cy: Int, _ g: inout [UInt8], _ st: inout [UInt8], _ ob: inout [UInt8], _ de: inout [UInt8]) {
        let c = Content.shared
        let basalt = c.tid("basalt"), lava = c.tid("lava"), rock = c.tid("rock"), pebbles = c.tid("pebbles")
        let h0 = MP.h2(seed &+ 4243, v.x, v.y)
        let a1 = Double(h0 % 628) / 100, a2 = a1 + 2.2 + Double((h0 >> 10) % 100) / 100
        for ty in 0..<32 { for tx in 0..<32 {
            let wx = cx * 32 + tx, wy = cy * 32 + ty
            let dx = Double(wx - v.x), dy = Double(wy - v.y), d = (dx * dx + dy * dy).squareRoot()
            guard d < Double(v.r) else { continue }
            let i = ty * 32 + tx
            st[i] = 0; ob[i] = 0; de[i] = 0
            g[i] = basalt
            if d < 3.6 { g[i] = lava; continue }
            // the streams: lava along two directions out of the crater, narrowing as they run down
            let ang = atan2(dy, dx)
            for a in [a1, a2] {
                var da = abs(ang - a).truncatingRemainder(dividingBy: 2 * .pi); if da > .pi { da = 2 * .pi - da }
                let wob = sin(d * 0.5 + a * 3) * 0.06
                if d < Double(v.r) * 0.75 && da < 0.11 - d * 0.0025 + wob { g[i] = lava }
            }
            if g[i] == basalt {
                let r = MP.h01(seed &+ 4244, wx, wy)
                if d > 7 && r < 0.03 { ob[i] = rock } else if r < 0.12 { de[i] = pebbles }
            }
        } }
    }

    /// A UFO airport: a round landing pad of glowing metal with a ring of beacon lamps, a glass control
    /// tower with its antenna and servers, crates of supplies, and a road in from the south.
    func carveUfoPort(_ cx: Int, _ cy: Int, _ g: inout [UInt8], _ st: inout [UInt8], _ ob: inout [UInt8], _ de: inout [UInt8]) {
        let c = Content.shared
        let pad = c.tid("ufo_pad"), lamp = c.tid("lamp_on"), stoneF = c.tid("stone_floor"), glass = c.tid("wall_glass")
        let steel = c.tid("spire_steel"), door = c.tid("door_wood")
        for y in 0..<32 { for x in 0..<32 {
            let i = y * 32 + x
            let dx = Double(x) - 15.5, dy = Double(y) - 13.5, d = (dx * dx + dy * dy).squareRoot()
            if d < 12.5 {
                st[i] = 0; ob[i] = 0; de[i] = 0
                g[i] = d < 10.5 ? pad : stoneF
                // beacons round the pad, sixteen of them
                if d >= 10.5 && d < 11.5 {
                    let a = atan2(dy, dx), k = (a + .pi) / (2 * .pi) * 16
                    if abs(k - k.rounded()) < 0.18 { ob[i] = lamp }
                }
            }
        } }
        // the control tower in the south-west corner, glass with steel corners, its antenna and servers inside
        for y in 25...30 { for x in 1...6 {
            let i = y * 32 + x
            st[i] = 0; de[i] = 0; g[i] = stoneF
            let edge = x == 1 || x == 6 || y == 25 || y == 30, corner = (x == 1 || x == 6) && (y == 25 || y == 30)
            ob[i] = edge ? (x == 3 && y == 25 ? door : (corner ? steel : glass)) : 0
        } }
        ob[27 * 32 + 3] = c.tid("server"); ob[27 * 32 + 4] = c.tid("desk"); ob[29 * 32 + 5] = c.tid("antenna")
        for (x, y) in [(26, 26), (27, 26), (26, 27), (28, 28)] { st[y * 32 + x] = 0; ob[y * 32 + x] = c.tid("crate"); g[y * 32 + x] = stoneF }
        // the road in from the south edge to the pad
        for y in 24...31 { for x in 15...16 { let i = y * 32 + x; st[i] = 0; ob[i] = 0; de[i] = 0; g[i] = stoneF } }
    }

    /// One chunk in every 10x10 block of chunks (about one every 640 m each way) holds an underground city (not
    /// under a ruin).
    public static let underCitySpacing = 10
    public func isUnderCity(_ cx: Int, _ cy: Int) -> Bool {
        let n = Generator.underCitySpacing
        let rx = Int((Double(cx) / Double(n)).rounded(.down)), ry = Int((Double(cy) / Double(n)).rounded(.down))
        let h = MP.h2(seed &+ 888, rx, ry)
        guard rx * n + Int(h % UInt32(n)) == cx && ry * n + Int((h >> 8) % UInt32(n)) == cy else { return false }
        if abs(cx) <= 2 && abs(cy) <= 2 { return false }
        let rr = Int((Double(cx) / 3).rounded(.down)), rr2 = Int((Double(cy) / 3).rounded(.down))
        let hr = MP.h2(seed &+ 555, rr, rr2)
        return !(rr * 3 + Int(hr % 3) == cx && rr2 * 3 + Int((hr >> 8) % 3) == cy)
    }

    /// On the surface over an underground city, an entrance nobody can miss: a round plaza of brick ringed by
    /// burning beacons, four paved roads in from the chunk's edges, banners and a signpost at the gate, and a
    /// stone gatehouse with an open gate round the stairway down.
    func carveCityStair(_ g: inout [UInt8], _ st: inout [UInt8], _ ob: inout [UInt8], _ de: inout [UInt8]) {
        let c = Content.shared
        let wall = c.tid("wall_stone"), floor = c.tid("stone_floor"), plaza = c.tid("brick_floor"), beacon = c.tid("lamp_on")
        for y in 0..<32 { for x in 0..<32 {
            let i = y * 32 + x
            let dx = Double(x) - 16, dy = Double(y) - 16, r = (dx * dx + dy * dy).squareRoot()
            let road = (abs(x - 16) <= 1 && (y > 26 || y < 6)) || (abs(y - 16) <= 1 && (x > 26 || x < 6))
            if r <= 11 || road { st[i] = 0; de[i] = 0; ob[i] = 0; g[i] = r <= 11 ? plaza : floor }
            // the beacons round the plaza (gaps where the roads come in)
            if abs(r - 10.5) < 0.5 && abs(x - 16) > 2 && abs(y - 16) > 2 && (x + y) % 3 == 0 { ob[i] = beacon }
        } }
        for y in 12...20 { for x in 12...20 {
            let i = y * 32 + x
            g[i] = floor
            let edge = x == 12 || x == 20 || y == 12 || y == 20
            ob[i] = edge ? (y == 20 && abs(x - 16) <= 1 ? c.tid("gate_open") : wall) : 0
        } }
        ob[16 * 32 + 16] = c.tid("stairs_down")
        ob[14 * 32 + 14] = c.tid("torch"); ob[14 * 32 + 18] = c.tid("torch")
        ob[21 * 32 + 14] = c.tid("banner_1"); ob[21 * 32 + 18] = c.tid("banner_1")
        ob[23 * 32 + 15] = c.tid("lantern_post"); ob[23 * 32 + 17] = c.tid("lantern_post")
        ob[24 * 32 + 18] = c.tid("sign")
    }

    /// An underground city filling a cave chunk: a wall round it with four gates, paved streets on a grid,
    /// lamp posts along them, stone and brick houses with doors, beds, tables and chests, a market of stalls
    /// on the central square round a statue and a well, banners, and the stairway up to the surface.
    func carveUnderCity(_ cx: Int, _ cy: Int, _ g: inout [UInt8], _ ob: inout [UInt8], _ de: inout [UInt8]) {
        let c = Content.shared
        let wall = c.tid("wall_stone"), brick = c.tid("wall_brick"), street = c.tid("stone_floor"), house = c.tid("wood_floor")
        let door = c.tid("door_wood"), lamp = c.tid("lantern_post")
        var r = RNG(seed: Int(MP.h2(seed &+ 889, cx, cy)))
        for y in 1...30 { for x in 1...30 {
            let i = y * 32 + x
            g[i] = street; de[i] = 0; ob[i] = 0
            let edge = x == 1 || x == 30 || y == 1 || y == 30
            let gate = (x == 15 || x == 16) && (y == 1 || y == 30) || (y == 15 || y == 16) && (x == 1 || x == 30)
            if edge && !gate { ob[i] = wall }
        } }
        // blocks between the streets (streets on rows/columns 2-3, 9-10, 15-16, 21-22, 28-29): a house in each
        let starts = [4, 11, 17, 23]
        for by in starts { for bx in starts {
            if (bx == 11 || bx == 17) && (by == 11 || by == 17) { continue }      // the square
            let w = 5, h = 4
            let mat = r.unit() < 0.5 ? wall : brick
            for y in by..<(by + h) { for x in bx..<(bx + w) {
                let i = y * 32 + x
                g[i] = house
                let edge = x == bx || x == bx + w - 1 || y == by || y == by + h - 1
                ob[i] = edge ? mat : 0
            } }
            ob[(by + h - 1) * 32 + bx + 2] = door
            ob[(by + 1) * 32 + bx + 1] = c.tid("bed")
            ob[(by + 1) * 32 + bx + 3] = r.unit() < 0.35 ? c.tid("chest") : c.tid("table")
            ob[(by + 2) * 32 + bx + 3] = r.unit() < 0.5 ? c.tid("barrel") : c.tid("bookshelf")
            // a lamp at the corner of the block
            if ob[(by - 1) * 32 + bx - 1] == 0 { ob[(by - 1) * 32 + bx - 1] = lamp }
        } }
        // the square: a statue, a well, market stalls, banners at its corners
        ob[14 * 32 + 15] = c.tid("statue")
        ob[13 * 32 + 16] = c.tid("chest")                                     // the city's vault, by the statue
        ob[17 * 32 + 16] = c.tid("well")
        for (x, y) in [(12, 12), (19, 12), (12, 19), (19, 19)] { ob[y * 32 + x] = c.tid("market_stall") }
        for (x, y) in [(11, 11), (20, 11), (11, 20), (20, 20)] { ob[y * 32 + x] = c.tid("banner_1") }
        for (x, y) in [(13, 15), (18, 16)] { de[y * 32 + x] = c.tid("fallen_leaves") }
        // the stairway up, at the spot of the gatehouse's stairs above
        ob[16 * 32 + 16] = c.tid("stairs_up")
    }
}

/// Asks the device how much memory it has and derives the cache limits.
public struct MemoryBudget {
    public var physicalMB = 0, availableMB = 0, budgetMB = 256, maxChunks = 1024, maxAgents = 300, maxSettlements = 12, overrideMB = 0
    public static let chunkBytes = 12 * 1024, minMB = 96, maxAutoMB = 768

    public static func deviceMemory() -> (physicalMB: Int, availableMB: Int) {
        let phys = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        var avail = phys / 2
        #if os(iOS)
        let a = Int(os_proc_available_memory() / 1_048_576)
        if a > 0 { avail = a }
        #endif
        return (phys, avail)
    }

    public init(overrideMB: Int = 0) {
        let d = MemoryBudget.deviceMemory()
        physicalMB = d.physicalMB
        availableMB = d.availableMB
        self.overrideMB = overrideMB
        if overrideMB > 0 {
            budgetMB = max(MemoryBudget.minMB, overrideMB)
        } else {
            // well under what the system allows an app: textures, the 3D scene and the save all need room too
            budgetMB = min(MemoryBudget.maxAutoMB, max(MemoryBudget.minMB, min(availableMB / 5, physicalMB / 10)))
        }
        maxChunks = min(60000, max(256, budgetMB * 1_048_576 * 4 / 10 / MemoryBudget.chunkBytes))
        maxAgents = min(1200, max(150, budgetMB))
        maxSettlements = min(200, max(6, maxChunks / 24))
    }

    /// Resident memory of this process in MB (0 when unknown).
    public static func usedMB() -> Int {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : 0
        #else
        if let s = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8), let pages = Int(s.split(separator: " ").dropFirst().first ?? "") {
            return pages * 4096 / 1_048_576
        }
        return 0
        #endif
    }

    public func pressure() -> Double { Double(MemoryBudget.usedMB()) / Double(max(1, budgetMB)) }
}

/// Unbounded world: on-demand chunks, memory-bounded LRU cache with disk-backed
/// edits, and a self-expanding one-byte-per-chunk survey map.
public final class OpenWorld {
    public static let region = 64
    public let seed: Int
    public let content = Content.shared
    public let gen: Generator
    public var budget: MemoryBudget
    public private(set) var cache: [Int64: Chunk] = [:]
    public private(set) var pins: [Int64: Int] = [:]
    public private(set) var regions: [TilePos: [UInt8]] = [:]
    public private(set) var surveyed = 0, generated = 0, evicted = 0
    public var time = 0.3 * MP.daySeconds
    public var nextPropID = 1
    public var directory: URL?
    /// Transactional storage shared by the surface and the underground of one world (see Store.swift).
    public private(set) var store: WorldStore?
    var saved: Set<Int64> = []
    /// Size of every stored chunk (bytes) in the current view, kept up to date on every change.
    private var fileSizes: [Int64: Int] = [:]
    public private(set) var diskBytes = 0
    /// Hard cap for the saved map. Default 5 GB.
    public var diskLimitBytes = 5 * 1024 * 1024 * 1024
    public private(set) var prunedFiles = 0
    /// Chunk files that could not be written (disk full, folder gone). A save that raises this has failed.
    public private(set) var writeFailures = 0
    var natural: Chunk?
    var naturalKey: Int64 = .min
    var clock = 0
    var ring: [TilePos: Int] = [:]
    var timerAcc = 0.0
    public var onTileChanged: [(Int, Int, Int, UInt8, UInt8) -> Void] = []
    public var onChunkChanged: [(Int, Int) -> Void] = []
    /// A counter bumped on every change to a chunk (tiles, reverts), so plans made against a chunk can tell they are stale.
    public private(set) var stamps: [Int64: Int] = [:]
    var stampClock = 0
    public func stamp(_ cx: Int, _ cy: Int) -> Int { stamps[MP.chunkKey(cx, cy)] ?? 0 }
    func bump(_ cx: Int, _ cy: Int) { stampClock += 1; stamps[MP.chunkKey(cx, cy)] = stampClock }
    /// What is drawn for a chunk changed (tiles, growth, props): baked bitmaps of older revisions are stale.
    public private(set) var revisions: [Int64: Int] = [:]
    public func revision(_ cx: Int, _ cy: Int) -> Int { revisions[MP.chunkKey(cx, cy)] ?? 0 }
    /// Bumped when the whole map is replaced (Genesis wipes it), so nothing baked before is used again.
    public private(set) var mapEpoch = 0
    func changed(_ cx: Int, _ cy: Int) {
        revClock += 1; revisions[MP.chunkKey(cx, cy)] = revClock
        for f in onChunkChanged { f(cx, cy) }
    }
    private var revClock = 0

    /// 0 is the surface; 1 is the underground layer; 100 + n is the n-th storey above the surface (n = 1, 2, ...
    /// with no top). Each has its own chunks and files in the same store.
    public let depth: Int
    public static let storeyBase = 100
    /// What stands in a freshly made chunk besides what the generator put there: on a storey, the floors
    /// of the towers that reach it (they are made from the tower itself when first looked at, never stored
    /// unless someone changes them).
    public var overlay: ((Chunk) -> Void)?
    public var isUnder: Bool { depth == 1 }
    /// Which storey this layer is (0 for the surface and the underground).
    public var storey: Int { depth >= OpenWorld.storeyBase ? depth - OpenWorld.storeyBase : 0 }

    public init(seed: Int, budget: MemoryBudget, depth: Int = 0) {
        self.seed = seed
        self.budget = budget
        self.depth = depth
        gen = Generator(seed: seed)
        gen.depth = depth
    }

    /// Open a world folder with a fresh store (as on app start). Use `open(store:)` to share a store.
    public func open(directory dir: URL) { open(store: WorldStore(directory: dir)) }

    public func open(store st: WorldStore) {
        store = st
        directory = st.dir
        saved = []; fileSizes = [:]; diskBytes = 0
        for k in st.chunks(depth: depth) {
            saved.insert(k)
            let n = st.size(WorldStore.key(depth, k))
            fileSizes[k] = n
            diskBytes += n
        }
    }

    func skey(_ k: Int64) -> String { WorldStore.key(depth, k) }

    // MARK: time
    public var year: Int { Int(time / MP.year) }
    public var hour: Double { time.truncatingRemainder(dividingBy: MP.daySeconds) / MP.daySeconds * 24.0 }
    public var isNight: Bool { let h = hour; return h < 5.5 || h >= 20.5 }
    public var daylight: Double {
        let h = hour
        if h < 4.5 || h >= 21.0 { return 0 }
        if h < 7.0 { return (h - 4.5) / 2.5 }
        if h < 18.5 { return 1 }
        return 1.0 - (h - 18.5) / 2.5
    }

    public func advance(_ dt: Double) {
        time += dt
        timerAcc += dt
        if timerAcc >= 2.0 {
            timerAcc = 0
            for c in cache.values where !c.timers.isEmpty { processTimers(c) }
        }
    }

    // MARK: chunks
    @discardableResult public func chunk(_ cx: Int, _ cy: Int) -> Chunk {
        let k = MP.chunkKey(cx, cy)
        clock += 1
        if let c = cache[k] { c.lastUsed = clock; return c }
        var c: Chunk?
        if saved.contains(k), let data = store?.read(skey(k)) { c = Chunk.decode(data) }
        if c == nil { c = gen.generate(cx, cy); generated += 1; overlay?(c!) }
        let ch = c!
        cache[k] = ch
        ch.lastUsed = clock
        mark(cx, cy)
        if !ch.timers.isEmpty { processTimers(ch) }
        return ch
    }

    public func loaded(_ cx: Int, _ cy: Int) -> Bool { cache[MP.chunkKey(cx, cy)] != nil }
    /// True when this chunk is in memory or has been changed and saved: its tiles may differ from what the generator would make.
    public func touched(_ cx: Int, _ cy: Int) -> Bool { let k = MP.chunkKey(cx, cy); return cache[k] != nil || saved.contains(k) }
    public func pin(_ cx: Int, _ cy: Int) { pins[MP.chunkKey(cx, cy), default: 0] += 1; chunk(cx, cy) }
    public func unpin(_ cx: Int, _ cy: Int) {
        let k = MP.chunkKey(cx, cy)
        if let n = pins[k] { if n <= 1 { pins[k] = nil } else { pins[k] = n - 1 } }
    }

    /// Hand a changed chunk to the store. It becomes durable with the next commit.
    func write(_ c: Chunk) -> Bool {
        guard let st = store else { return !c.modified }
        let data = c.encoded()
        st.stage(skey(c.key), data)
        c.dirty = false
        saved.insert(c.key)
        diskBytes += data.count - (fileSizes[c.key] ?? 0)
        fileSizes[c.key] = data.count
        if diskBytes > diskLimitBytes { enforceDiskLimit() }
        return true
    }

    /// Estimated memory used by cached chunk data (bytes).
    public var memoryBytes: Int { cache.count * MemoryBudget.chunkBytes + regions.count * OpenWorld.region * OpenWorld.region }

    /// Keeps the saved map under `diskLimitBytes`: the oldest chunk files that
    /// are not pinned (no living settlement there) and not currently loaded are
    /// removed; those areas return to their natural, regenerated state.
    @discardableResult public func enforceDiskLimit() -> Int {
        guard let st = store, diskBytes > diskLimitBytes else { return 0 }
        let target = diskLimitBytes * 9 / 10
        var cands: [(Int64, Double)] = []
        for k in saved where pins[k] == nil && cache[k] == nil { cands.append((k, st.stamp(skey(k)))) }
        cands.sort { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
        var removed = 0
        for (k, _) in cands {
            if diskBytes <= target { break }
            st.remove(skey(k))
            diskBytes -= fileSizes[k] ?? 0
            fileSizes[k] = nil
            saved.remove(k)
            removed += 1
        }
        prunedFiles += removed
        return removed
    }

    /// Keep the cache inside the memory budget (least recently used first).
    @discardableResult public func maintain() -> Int {
        var limit = budget.maxChunks
        if budget.pressure() > 1.0 { limit = max(pins.count + 64, cache.count * 7 / 10) }
        if cache.count <= limit { return 0 }
        let list = cache.values.filter { pins[$0.key] == nil }.sorted { $0.lastUsed < $1.lastUsed }
        var removed = 0
        let target = limit * 9 / 10
        for c in list {
            if cache.count <= target { break }
            if c.dirty && !write(c) { continue }
            cache[c.key] = nil
            removed += 1
        }
        evicted += removed
        return removed
    }

    /// One-tap cleanup: drop everything that is neither pinned nor in `keep`.
    @discardableResult public func purge(keep: Set<Int64> = []) -> Int {
        var removed = 0
        for (k, c) in cache where pins[k] == nil && !keep.contains(k) {
            if c.dirty && !write(c) { continue }
            cache[k] = nil
            removed += 1
        }
        evicted += removed
        return removed
    }

    @discardableResult public func saveAll() -> Int {
        var n = 0
        for c in cache.values where c.dirty { if write(c) { n += 1 } }
        return n
    }

    // MARK: survey
    static func floorDiv(_ a: Int, _ b: Int) -> Int { Int((Double(a) / Double(b)).rounded(.down)) }
    static func posMod(_ a: Int, _ b: Int) -> Int { ((a % b) + b) % b }

    @discardableResult func mark(_ cx: Int, _ cy: Int) -> Bool {
        let R = OpenWorld.region
        let rk = TilePos(OpenWorld.floorDiv(cx, R), OpenWorld.floorDiv(cy, R))
        var r = regions[rk] ?? [UInt8](repeating: 0, count: R * R)
        let i = OpenWorld.posMod(cy, R) * R + OpenWorld.posMod(cx, R)
        if r[i] != 0 { return false }
        r[i] = UInt8(gen.biome(cx * 32 + 16, cy * 32 + 16) + 1)
        regions[rk] = r
        surveyed += 1
        return true
    }

    public func known(_ cx: Int, _ cy: Int) -> UInt8 {
        let R = OpenWorld.region
        guard let r = regions[TilePos(OpenWorld.floorDiv(cx, R), OpenWorld.floorDiv(cy, R))] else { return 0 }
        return r[OpenWorld.posMod(cy, R) * R + OpenWorld.posMod(cx, R)]
    }

    /// Explore up to `count` new chunks in growing rings; no terrain is generated.
    @discardableResult public func survey(center: TilePos, count: Int, maxRadius: Int = 4096) -> Int {
        var r = ring[center] ?? 0
        var done = 0
        while done < count && r <= maxRadius {
            var unknownLeft = false
            for dy in -r...r {
                let step = abs(dy) == r ? 1 : max(1, 2 * r)
                var dx = -r
                while dx <= r {
                    if known(center.x + dx, center.y + dy) == 0 {
                        if done < count { mark(center.x + dx, center.y + dy); done += 1 } else { unknownLeft = true }
                    }
                    dx += step
                }
            }
            if unknownLeft { break }
            r += 1
        }
        ring[center] = r
        return done
    }

    // MARK: tiles
    @inline(__always) static func idx(_ wx: Int, _ wy: Int) -> Int { (wy & 31) * 32 + (wx & 31) }

    public func tile(_ layer: Int, _ wx: Int, _ wy: Int) -> UInt8 {
        // a place far beyond any world (a "none" placeholder, a broken number) is empty: never generated
        guard OpenWorld.sane(wx, wy) else { return 0 }
        return chunk(wx >> 5, wy >> 5).layers[layer][OpenWorld.idx(wx, wy)]
    }

    /// Coordinates a world can hold (about 17 000 km either way): anything beyond is a placeholder or a fault.
    @inline(__always) public static func sane(_ wx: Int, _ wy: Int) -> Bool { wx.magnitude < (1 << 33) && wy.magnitude < (1 << 33) }
    @inline(__always) public static func sane(_ t: TilePos) -> Bool { sane(t.x, t.y) }

    public func blocked(_ wx: Int, _ wy: Int) -> Bool {
        guard OpenWorld.sane(wx, wy) else { return true }
        let c = chunk(wx >> 5, wy >> 5)
        let i = OpenWorld.idx(wx, wy)
        let o = Int(c.layers[2][i])
        if o != 0 && content.solid[o] { return true }
        let s = Int(c.layers[1][i])
        if s != 0 {
            if content.solid[s] { return true }
            if content.bridge[s] { return false }
        }
        // on a storey, air holds nobody: only a floor can be walked on
        if depth >= OpenWorld.storeyBase && c.layers[0][i] == 0 { return true }
        return content.solid[Int(c.layers[0][i])]
    }

    public func isLand(_ wx: Int, _ wy: Int) -> Bool {
        if depth >= OpenWorld.storeyBase && tile(0, wx, wy) == 0 { return false }
        return !content.water[Int(tile(0, wx, wy))] && !content.solid[Int(tile(1, wx, wy))]
    }

    public func setTile(_ layer: Int, _ wx: Int, _ wy: Int, _ id: UInt8) {
        guard OpenWorld.sane(wx, wy) else { return }
        let c = chunk(wx >> 5, wy >> 5)
        let i = OpenWorld.idx(wx, wy)
        let old = c.layers[layer][i]
        if old == id { return }
        c.layers[layer][i] = id
        c.touch()
        c.timers.removeAll { $0.i == i && $0.l == layer }
        if id != 0, let t = content.tile(id), !t.growTo.isEmpty {
            c.timers.append(GrowTimer(i: i, l: layer, to: content.tid(t.growTo), due: time + t.growTime, expect: id))
        }
        bump(c.cx, c.cy)
        for f in onTileChanged { f(wx, wy, layer, old, id) }
        changed(c.cx, c.cy)
    }

    public func schedule(_ wx: Int, _ wy: Int, layer: Int, to: UInt8, delay: Double, expect: UInt8) {
        let c = chunk(wx >> 5, wy >> 5)
        c.timers.append(GrowTimer(i: OpenWorld.idx(wx, wy), l: layer, to: to, due: time + delay, expect: expect))
        c.touch()
    }

    /// Growth catches up from due times, so plants keep growing while evicted.
    func processTimers(_ c: Chunk) {
        var n = 0, guardCount = 0, grew = false
        while n < c.timers.count && guardCount < 4096 {
            guardCount += 1
            let tm = c.timers[n]
            if tm.due > time { n += 1; continue }
            c.timers.remove(at: n)
            if c.layers[tm.l][tm.i] != tm.expect { continue }
            let old = c.layers[tm.l][tm.i]
            c.layers[tm.l][tm.i] = tm.to
            c.touch()
            grew = true
            if tm.to != 0, let t = content.tile(tm.to), !t.growTo.isEmpty {
                c.timers.append(GrowTimer(i: tm.i, l: tm.l, to: content.tid(t.growTo), due: tm.due + t.growTime, expect: tm.to))
            }
            for f in onTileChanged { f(c.cx * 32 + tm.i % 32, c.cy * 32 + tm.i / 32, tm.l, old, tm.to) }
        }
        if grew { changed(c.cx, c.cy) }
    }

    // MARK: permanent deletion (world laws) - unlike cache cleaning, this destroys saved data
    /// Chunks that exist as files, sorted.
    public var storedChunks: [Int64] { saved.sorted() }
    public func storedSize(_ key: Int64) -> Int { fileSizes[key] ?? 0 }
    /// Decode a stored chunk without putting it in the cache.
    public func peekStored(_ key: Int64) -> Chunk? {
        if let c = cache[key] { return c }
        guard saved.contains(key), let data = store?.read(skey(key)) else { return nil }
        return Chunk.decode(data)
    }

    /// Forget every change ever made to a chunk: its file is deleted and, if it
    /// is in use, it is regenerated in place. Returns the bytes freed on disk.
    @discardableResult public func revertChunk(_ cx: Int, _ cy: Int) -> Int {
        let k = MP.chunkKey(cx, cy)
        var freed = 0
        if saved.contains(k) {
            store?.remove(skey(k))
            freed = fileSizes[k] ?? 0
            diskBytes -= freed
            fileSizes[k] = nil
            saved.remove(k)
        }
        bump(cx, cy)
        revClock += 1; revisions[k] = revClock          // even when not loaded: any bitmap of it is out of date
        if cache[k] != nil {
            if pins[k] != nil {
                let fresh = gen.generate(cx, cy)
                overlay?(fresh)
                fresh.lastUsed = clock
                cache[k] = fresh
            } else { cache[k] = nil }
            changed(cx, cy)
        }
        return freed
    }

    /// Put the ground layer of one tile back to what the generator made.
    public func restoreGround(_ wx: Int, _ wy: Int) {
        let cx = wx >> 5, cy = wy >> 5
        let k = MP.chunkKey(cx, cy)
        if naturalKey != k { natural = gen.generate(cx, cy); naturalKey = k }
        if let n = natural { setTile(0, wx, wy, n.layers[0][OpenWorld.idx(wx, wy)]) }
    }

    /// Put one tile back to what the generator made there (all four layers).
    public func restoreNatural(_ wx: Int, _ wy: Int) {
        let cx = wx >> 5, cy = wy >> 5
        let k = MP.chunkKey(cx, cy)
        if naturalKey != k { natural = gen.generate(cx, cy); naturalKey = k }
        guard let n = natural else { return }
        let i = OpenWorld.idx(wx, wy)
        for l in 0..<4 { setTile(l, wx, wy, n.layers[l][i]) }
    }

    /// Delete every chunk file and forget the whole map (used by Genesis).
    @discardableResult public func wipe() -> Int {
        let freed = diskBytes
        for k in saved { store?.remove(skey(k)) }
        saved.removeAll(); fileSizes.removeAll(); diskBytes = 0
        cache.removeAll(); pins.removeAll(); regions.removeAll(); ring.removeAll()
        surveyed = 0
        mapEpoch += 1; revisions.removeAll()
        return freed
    }

    @discardableResult public func removeProp(id: Int, cx: Int, cy: Int) -> Bool {
        let c = chunk(cx, cy)
        guard let i = c.props.firstIndex(where: { $0.id == id }) else { return false }
        c.props.remove(at: i)
        c.touch()
        changed(cx, cy)
        return true
    }

    // MARK: props
    @discardableResult public func addProp(key: String, at p: Vec2) -> Int {
        let c = chunk(Int((p.x / 512).rounded(.down)), Int((p.y / 512).rounded(.down)))
        let id = nextPropID
        nextPropID += 1
        c.props.append(Prop(id: id, key: key, x: p.x, y: p.y))
        c.touch()
        changed(c.cx, c.cy)
        return id
    }

    public func removeProp(near p: Vec2, radius: Double = 14) -> Bool {
        let cx = Int((p.x / 512).rounded(.down)), cy = Int((p.y / 512).rounded(.down))
        for dy in -1...1 { for dx in -1...1 {
            let c = chunk(cx + dx, cy + dy)
            if let i = c.props.firstIndex(where: { Vec2($0.x, $0.y).distance(to: p) <= radius }) {
                c.props.remove(at: i)
                c.touch()
                changed(c.cx, c.cy)
                return true
            }
        } }
        return false
    }

    public func findFree(near t: TilePos, maxR: Int = 12) -> TilePos {
        for r in 0...maxR { for dy in -r...r { for dx in -r...r where max(abs(dx), abs(dy)) == r {
            if !blocked(t.x + dx, t.y + dy) { return TilePos(t.x + dx, t.y + dy) }
        } } }
        return t
    }

    /// Dry-land spot for a camp, searched deterministically around `from`.
    public func findSite(from: TilePos, minR: Double, maxR: Double, salt: Int, avoid: [TilePos], avoidDist: Double) -> TilePos {
        for k in 0..<240 {
            let ang = MP.h01(seed + salt, k, 1) * 2 * Double.pi
            let rad = minR + (maxR - minR) * MP.h01(seed + salt, k, 2)
            let p = TilePos(from.x + Int(cos(ang) * rad), from.y + Int(sin(ang) * rad))
            let b = gen.biome(p.x, p.y)
            if b == Biome.ocean || b == Biome.mountain || b == Biome.canyon { continue }
            // the first two thirds of the attempts insist on green land with timber nearby
            if k < 160 && (b == Biome.desert || b == Biome.snow || b == Biome.beach) { continue }
            if avoid.contains(where: { Double(($0 - p).lengthSquared).squareRoot() < avoidDist }) { continue }
            var mazeNear = false
            for my in -1...1 { for mx in -1...1 where gen.isMaze((p.x >> 5) + mx, (p.y >> 5) + my) { mazeNear = true } }
            if mazeNear { continue }
            // every tile of the village core must be dry, walkable ground:
            // a river through the square would cut the villagers off from each other
            var dry = true
            outer: for dy in -14...14 { for dx in -14...14 {
                let c = gen.climate(p.x + dx, p.y + dy)
                if c.0 < Biome.sea + 0.012 || c.0 > Biome.mountainLevel - 0.01 || abs(gen.nRiver.get(Double(p.x + dx), Double(p.y + dy))) < 0.024 { dry = false; break outer }
            } }
            if dry { return p }
        }
        return .none
    }

    // MARK: persistence
    public struct Snapshot: Codable {
        public var seed: Int, time: Double, nextPropID: Int, regions: [String: Data]
    }

    public func snapshot() -> Snapshot {
        var reg: [String: Data] = [:]
        for (k, v) in regions { reg["\(k.x),\(k.y)"] = Data(v) }
        return Snapshot(seed: seed, time: time, nextPropID: nextPropID, regions: reg)
    }

    public func restore(_ s: Snapshot) {
        time = s.time
        nextPropID = s.nextPropID
        regions.removeAll()
        surveyed = 0
        let R = OpenWorld.region
        for (k, v) in s.regions {
            let p = k.split(separator: ",")
            if p.count == 2, let x = Int(p[0]), let y = Int(p[1]), v.count == R * R {
                regions[TilePos(x, y)] = [UInt8](v)
                surveyed += v.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
            }
        }
    }
}
