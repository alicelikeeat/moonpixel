import Foundation

// The 3D view of the same tile world. Nothing here changes the simulation or the save format: a
// chunk's four tile layers, the generator's elevation and a character's look are turned into
// triangle meshes that any renderer can draw. No graphics framework is used, so all of it is
// tested on Linux.
//
// Space: 1 unit = one tile; x east, y up, z south (a tile (tx, ty) covers x tx...tx+1, z ty...ty+1).

/// A triangle mesh. Every face is flat-coloured through a texture coordinate (see `Palette3D`),
/// except ground tops, whose coordinates point into the chunk's own ground picture.
public struct Mesh3D {
    public var positions: [SIMD3<Float>] = []
    public var normals: [SIMD3<Float>] = []
    public var uvs: [SIMD2<Float>] = []
    public var indices: [UInt32] = []
    /// Anime look: two flat tones (lit tops, shadowed sides) instead of six graded ones, like 2D cel shading.
    public var cel = false
    /// Drawn in its own colours whichever way it faces (the sun, the moon, the planets: lights in the sky).
    public var unshaded = false
    public init() {}
    public var isEmpty: Bool { indices.isEmpty }
    public var triangles: Int { indices.count / 3 }

    public struct Faces: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Faces(rawValue: 1), bottom = Faces(rawValue: 2), north = Faces(rawValue: 4)
        public static let south = Faces(rawValue: 8), east = Faces(rawValue: 16), west = Faces(rawValue: 32)
        public static let sides: Faces = [.north, .south, .east, .west]
        public static let noBottom: Faces = [.top, .north, .south, .east, .west]
        public static let all: Faces = [.top, .bottom, .north, .south, .east, .west]
    }

    /// How bright each side of a box is: a fixed sun from the south-east, baked into the colours.
    public static let shadeTop = 0.0, shadeSouth = 0.14, shadeEast = 0.24, shadeWest = 0.32, shadeNorth = 0.40, shadeBottom = 0.5

    /// Four corners, counter-clockwise when seen from the side the normal points to.
    public mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, normal n: SIMD3<Float>,
                              uv: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)) {
        let i = UInt32(positions.count)
        positions.append(a); positions.append(b); positions.append(c); positions.append(d)
        for _ in 0..<4 { normals.append(n) }
        uvs.append(uv.0); uvs.append(uv.1); uvs.append(uv.2); uvs.append(uv.3)
        indices.append(i); indices.append(i + 1); indices.append(i + 2)
        indices.append(i); indices.append(i + 2); indices.append(i + 3)
    }

    mutating func flat(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ n: SIMD3<Float>, _ color: RGBA, shade: Double) {
        let t = Palette3D.uv(unshaded ? color : (cel ? Mesh3D.celColor(color, shade: shade) : color.darkened(shade)))
        quad(a, b, c, d, normal: n, uv: (t, t, t, t))
    }

    /// An axis-aligned box in one colour, each side shaded by where it faces.
    public mutating func box(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ color: RGBA, faces: Faces = .noBottom) {
        if faces.contains(.top) { flat([x0, y1, z1], [x1, y1, z1], [x1, y1, z0], [x0, y1, z0], [0, 1, 0], color, shade: Mesh3D.shadeTop) }
        if faces.contains(.bottom) { flat([x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1], [0, -1, 0], color, shade: Mesh3D.shadeBottom) }
        if faces.contains(.south) { flat([x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], [0, 0, 1], color, shade: Mesh3D.shadeSouth) }
        if faces.contains(.north) { flat([x1, y0, z0], [x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [0, 0, -1], color, shade: Mesh3D.shadeNorth) }
        if faces.contains(.east) { flat([x1, y0, z1], [x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [1, 0, 0], color, shade: Mesh3D.shadeEast) }
        if faces.contains(.west) { flat([x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0], [-1, 0, 0], color, shade: Mesh3D.shadeWest) }
    }

    /// A box given in sixteenths of a tile around an origin: x and z from the origin, y up from it.
    mutating func px(_ o: SIMD3<Float>, _ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: RGBA, scale: Float = 1, faces: Faces = .noBottom) {
        let k = scale / 16
        box(o.x + x * k, o.y + y * k, o.z + z * k, o.x + (x + w) * k, o.y + (y + h) * k, o.z + (z + d) * k, c, faces: faces)
    }

    /// A face colour in the anime look: lit faces a touch brighter, faces turned from the sun one shadow
    /// tone (the far sides a deeper one), the shadow cooled towards blue as a cel painter does.
    public static func celColor(_ c: RGBA, shade: Double) -> RGBA {
        if shade <= 0.001 { return c.lightened(0.06) }
        let k = shade < 0.3 ? 0.16 : 0.3
        let d = c.darkened(k)
        return RGBA(UInt8(Double(d.r) * 0.92), UInt8(Double(d.g) * 0.95), UInt8(min(255, Double(d.b) * 1.04 + 6)), c.a)
    }

    /// The ink colour of outlines (the same dark plum the 2D anime art draws its lines in).
    public static let ink = RGBA(46, 34, 52)

    /// Ink outlines by the inverted hull: every quad gets a shell a hair outside it, a little larger and facing
    /// inwards, in ink. With back faces culled, only the shells behind an object show, round its silhouette
    /// and along its edges: a drawn line about `width` tiles wide. (Every quad of the mesh is four vertices.)
    public func inked(width: Float = 0.035) -> Mesh3D {
        var out = self
        let uv = Palette3D.uv(Mesh3D.ink)
        var q = 0
        while q + 3 < positions.count {
            let p = [positions[q], positions[q + 1], positions[q + 2], positions[q + 3]]
            let n = normals[q]
            let centre = (p[0] + p[1] + p[2] + p[3]) * 0.25
            var shell: [SIMD3<Float>] = []
            for v in p {
                // out along the normal, and out from the face's centre within its plane
                var r = v - centre
                r -= n * ((r * n).sum())
                let len = ((r * r).sum()).squareRoot()
                let grow = len > 1e-6 ? r / len * width * 1.4 : SIMD3<Float>(0, 0, 0)
                shell.append(v + n * width + grow)
            }
            // wound the other way round, facing in
            out.quad(shell[3], shell[2], shell[1], shell[0], normal: -n, uv: (uv, uv, uv, uv))
            q += 4
        }
        return out
    }

    /// Lowest and highest corner (zero when empty).
    public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard var lo = positions.first else { return ([0, 0, 0], [0, 0, 0]) }
        var hi = lo
        for p in positions {
            lo = SIMD3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = SIMD3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        return (lo, hi)
    }
}

/// One small texture holds every flat colour the 3D view uses (5 bits per channel). Red and green
/// run along x, blue along y; the rows are mirrored top to bottom, so a renderer that counts v from
/// the bottom reads the same colour as one that counts from the top.
public enum Palette3D {
    public static let width = 1024, height = 64

    public static func uv(_ c: RGBA) -> SIMD2<Float> {
        let r = Int(c.r) >> 3, g = Int(c.g) >> 3, b = Int(c.b) >> 3
        return SIMD2((Float(r + g * 32) + 0.5) / Float(width), (Float(b) + 0.5) / Float(height))
    }

    /// The colour a coordinate made by `uv` shows (what the quantisation does to it).
    public static func color(at uv: SIMD2<Float>) -> RGBA {
        let x = Swift.min(width - 1, Swift.max(0, Int(uv.x * Float(width)))), y = Swift.min(height - 1, Swift.max(0, Int(uv.y * Float(height))))
        return bitmap.get(x, y)
    }

    public static let bitmap: Bitmap = {
        var img = Bitmap(width, height)
        func up(_ v: Int) -> UInt8 { UInt8((v << 3) | (v >> 2)) }
        for b in 0..<32 { for g in 0..<32 { for r in 0..<32 {
            let c = RGBA(up(r), up(g), up(b))
            img.set(r + g * 32, b, c)
            img.set(r + g * 32, height - 1 - b, c)
        } } }
        return img
    }()
}

/// Heights. The simulation is flat; the 3D view raises the land in quarter-tile steps from the
/// generator's own elevation, so the same seed always gives the same hills. Water lies a little
/// below its banks, bridges are level with them, and the underground is one flat floor.
public enum Terrain3D {
    public static let step: Float = 0.25
    /// Height of one storey in levels (2 tiles): room for a wall and a slab.
    public static let storeyLevels = 8
    public static let waterDrop: Float = 0.3
    public static let maxLevel = 64

    /// Height in levels: a gentle rise from the shore through the lowlands, then mountains climbing steeply
    /// above the mountain line (to 16 tiles at the highest).
    public static func level(elevation e: Double) -> Int {
        let low = (Swift.min(e, Biome.mountainLevel) - Biome.sea) * 34
        let high = Swift.max(0, e - Biome.mountainLevel) * 110
        return Swift.max(0, Swift.min(maxLevel, Int((low + high).rounded(.down))))
    }

    /// Top of the ground of one tile.
    public static func groundY(level: Int, ground: UInt8, structure: UInt8, depth: Int) -> Float {
        let c = Content.shared
        let wet = c.water[Int(ground)] && !c.bridge[Int(structure)]
        let base = depth == 1 ? 0 : Float(level) * step
        return wet ? base - waterDrop : base
    }

    /// Top of the ground under a point of the world (points are in the simulation's units, 16 per tile).
    public static func groundY(world: OpenWorld, at p: Vec2) -> Float {
        let t = p.tile
        let lv = world.depth == 1 ? 0 : level(elevation: world.gen.elevation(t.x, t.y)) + world.storey * storeyLevels
        return groundY(level: lv, ground: world.tile(MP.lGround, t.x, t.y), structure: world.tile(MP.lStruct, t.x, t.y), depth: world.depth)
    }

    public enum Hit: Equatable { case ground, wall, object }

    /// What a ray meets first: the ground, or something standing on it (a wall, a tree, a rock) which
    /// is as tall as `standing` says and is hit on its sides as well as its top. Something standing is
    /// reported at the middle of its tile, so a tap on a tree's crown means that tree, not the ground behind.
    public static func pickThing(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float = 400,
                                 ground: (Int, Int) -> Float, standing: (Int, Int) -> (Float, Hit)) -> (Vec2, Hit)? {
        guard let p = pick(origin: origin, direction: direction, maxDistance: maxDistance, height: { ground($0, $1) + standing($0, $1).0 }) else { return nil }
        let t = TilePos(Int((p.x / 16).rounded(.down)), Int((p.y / 16).rounded(.down)))
        let s = standing(t.x, t.y)
        return s.0 > 0 ? (t.center, s.1) : (p, .ground)
    }

    /// Where a ray meets the ground, as a point of the world; nil when it leaves upwards or runs out.
    /// `height` gives the top of the ground of a tile.
    public static func pick(origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float = 400, height: (Int, Int) -> Float) -> Vec2? {
        let len = (direction.x * direction.x + direction.y * direction.y + direction.z * direction.z).squareRoot()
        guard len > 0 else { return nil }
        let d = direction / len
        var t: Float = 0
        var last = origin
        while t <= maxDistance {
            let p = origin + d * t
            let h = height(Int(p.x.rounded(.down)), Int(p.z.rounded(.down)))
            if p.y <= h {
                // step back between the last point above ground and this one
                var a = last, b = p
                for _ in 0..<6 {
                    let m = (a + b) * 0.5
                    if m.y <= height(Int(m.x.rounded(.down)), Int(m.z.rounded(.down))) { b = m } else { a = m }
                }
                return Vec2(Double(b.x) * 16, Double(b.z) * 16)
            }
            last = p
            // far above the highest ground the ray can take long strides
            let clear = p.y - Float(maxLevel) * step - 2.5
            t += clear > 0 && d.y < 0 ? Swift.max(0.2, clear / -d.y) : 0.2
        }
        return nil
    }
}

extension Generator {
    /// The smooth elevation the 3D heights are read from (the tile detail noise is left out, so
    /// neighbouring tiles do not jitter by one step).
    public func elevation(_ wx: Int, _ wy: Int) -> Double {
        let e = naturalElevation(wx, wy)
        let fl = flats                         // one consistent copy (another thread may replace the list)
        guard !fl.isEmpty else { return e }
        // ground levelled for a monument: flat on its ground, easing back to the land round it over 24 tiles
        for f in fl {
            let dx = Swift.max(f.x0 - wx, 0, wx - f.x1), dy = Swift.max(f.y0 - wy, 0, wy - f.y1)
            let d = Swift.max(dx, dy)
            guard d < Generator.flatBlend else { continue }
            let t = Double(d) / Double(Generator.flatBlend), s = t * t * (3 - 2 * t)
            return f.e * (1 - s) + e * s
        }
        return e
    }

    /// The land as made, before any levelling.
    public func naturalElevation(_ wx: Int, _ wy: Int) -> Double {
        let e = shaped(0.5 + elevBias + 0.62 * nElev.get(Double(wx), Double(wy)) + continental(Double(wx), Double(wy)), Double(wx), Double(wy))
        guard e > Biome.sea else { return e }
        // rolling hills inland (none at the shore, fuller further from it), and volcanoes on top
        let inland = Swift.min(1, Swift.max(0, (e - Biome.sea - 0.02) / 0.1))
        let hills = 0.11 * Swift.max(0, nHill.get(Double(wx), Double(wy)) + 0.15) * inland
        return e + hills + volcanoLift(wx, wy)
    }
}

/// What the mesher needs to know about one chunk; taken on the main thread, meshed anywhere.
public struct ChunkInput3D {
    public var cx: Int, cy: Int, depth: Int
    public var layers: [[UInt8]]
    /// Ground and structure ids of the rows just outside the chunk (32 each); nil where unknown.
    public var north: (ground: [UInt8], structure: [UInt8])?, south: (ground: [UInt8], structure: [UInt8])?
    public var west: (ground: [UInt8], structure: [UInt8])?, east: (ground: [UInt8], structure: [UInt8])?

    public init(cx: Int, cy: Int, depth: Int, layers: [[UInt8]]) { self.cx = cx; self.cy = cy; self.depth = depth; self.layers = layers }

    /// The chunk and the edges of its four neighbours, read from an open world.
    public init(world: OpenWorld, cx: Int, cy: Int) {
        self.init(cx: cx, cy: cy, depth: world.depth, layers: world.chunk(cx, cy).layers)
        let n = world.chunk(cx, cy - 1).layers, s = world.chunk(cx, cy + 1).layers, w = world.chunk(cx - 1, cy).layers, e = world.chunk(cx + 1, cy).layers
        func row(_ l: [[UInt8]], _ y: Int) -> ([UInt8], [UInt8]) { (Array(l[0][(y * 32)..<(y * 32 + 32)]), Array(l[1][(y * 32)..<(y * 32 + 32)])) }
        func col(_ l: [[UInt8]], _ x: Int) -> ([UInt8], [UInt8]) { ((0..<32).map { l[0][$0 * 32 + x] }, (0..<32).map { l[1][$0 * 32 + x] }) }
        north = row(n, 31); south = row(s, 0); west = col(w, 31); east = col(e, 0)
    }
}

/// The meshes of one chunk, in chunk-local tile units (0...32 on x and z).
public struct ChunkMesh3D {
    /// Ground tops, textured with `PixelArt.bakeGround`.
    public var ground = Mesh3D()
    /// Everything that stands up: terrain steps, walls, trees, furniture. Coloured through `Palette3D`.
    public var solid = Mesh3D()
    /// Anime look: plants, rocks and the like as the 2D anime pictures, on two crossed upright quads each
    /// (paper cut-outs seen from any side), textured from `AnimeArt.atlas` (transparent where nothing is drawn).
    public var sprites = Mesh3D()
    /// Top of the ground of every tile of the chunk (32 x 32).
    public var heights = [Float](repeating: 0, count: MP.chunkArea)
    /// How bright each tile's ground is drawn for the lie of the land (1 flat; more on slopes facing the light
    /// from the south-east, less on those turned away): hills, mountains and valleys read in the 3D view.
    public var relief = [Float](repeating: 1, count: MP.chunkArea)
}

public enum Mesher3D {
    /// v of a ground picture row for renderers that count v from the bottom of the image (RealityKit does).
    public static var flipV = true

    static let colors: [(RGBA, RGBA, RGBA)] = (0..<256).map { i in
        guard let t = Content.shared.tiles[i] else { return (.white, .white, .white) }
        let c1 = RGBA(hex: t.c1)
        return (c1, t.c2.isEmpty || !t.c2.hasPrefix("#") ? c1.darkened(0.2) : RGBA(hex: t.c2), t.c3.isEmpty || !t.c3.hasPrefix("#") ? c1.lightened(0.2) : RGBA(hex: t.c3))
    }

    /// Height in sixteenths of a tile of the tiles that fill their whole square (walls, cliffs); 0 for the rest.
    static let blockHeight: [Float] = (0..<256).map { i in
        guard let t = Content.shared.tiles[i] else { return 0 }
        switch t.artKind {
        case "cliff": return 30
        case "wall": return t.key == "cave_wall" ? 30 : 24
        default: return 0
        }
    }

    /// What the player builds, breaks or opens in a chunk: every structure, and whether each tile holds
    /// something solid (a tree felled, a rock broken). Crops growing and the like leave it unchanged, so
    /// a renderer can tell a change it must show at once from one that can wait.
    public static func structureHash(_ layers: [[UInt8]]) -> UInt64 {
        let solid = Content.shared.solid
        var h: UInt64 = 1469598103934665603
        for v in layers[1] { h = (h ^ UInt64(v)) &* 1099511628211 }
        for v in layers[2] { h = (h ^ (solid[Int(v)] ? 1 : 0)) &* 1099511628211 }
        return h
    }

    /// The edge rows and columns of the ground and structure layers: what the four neighbours read
    /// (`ChunkInput3D`). When it changes, they must be meshed again too.
    public static func edgeHash(_ layers: [[UInt8]]) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for l in 0..<2 { for k in 0..<32 { for t in [k, 31 * 32 + k, k * 32, k * 32 + 31] { h = (h ^ UInt64(layers[l][t])) &* 1099511628211 } } }
        return h
    }

    /// Height marking air on a storey (no floor there).
    public static let air: Float = -1000

    /// What becomes a cut-out picture in the anime look (the rest keeps its solid shape, cel-shaded and inked).
    public static let spriteKinds: Set<String> = ["tree", "pine", "deadtree", "cactus", "bush", "berrybush", "sapling", "crop", "flower",
                                                   "tuft", "mushroom", "rock", "ore", "scarecrow", "leaves"]

    /// Two crossed quads standing on `o` showing atlas cell `id` (the picture's foot on the ground, its cell
    /// two tiles wide and tall like the anime atlas draws a standing thing), turned a little by `salt`.
    /// How much bigger than its atlas cell (two tiles) a cut-out stands: trees tower over people as in 3D.
    public static func spriteScale(_ kind: String) -> Float {
        switch kind {
        case "tree", "pine", "deadtree": return 1.8
        case "bush", "berrybush", "cactus", "scarecrow": return 1.25
        default: return 1
        }
    }

    static func addSprite(_ m: inout Mesh3D, id: Int, at o: SIMD3<Float>, salt: Int, scale k: Float = 1) {
        let cells = 16.0 as Float
        let u0 = Float(id % 16) / cells, u1 = Float(id % 16 + 1) / cells
        let r0 = Float(id / 16) / cells, r1 = Float(id / 16 + 1) / cells
        func v(_ r: Float) -> Float { flipV ? 1 - r : r }
        let c = SIMD3<Float>(o.x + 0.5, o.y, o.z + 0.5)
        let a = Float(salt % 8) * .pi / 32 + .pi / 4
        for side in 0..<2 {
            let ang = a + Float(side) * .pi / 2
            let d = SIMD3<Float>(cos(ang), 0, sin(ang)) * k      // half width k tiles: the cell is 2 tiles wide
            let n = SIMD3<Float>(-sin(ang), 0, cos(ang))
            let bl = c - d, br = c + d, tl = bl + SIMD3<Float>(0, 2 * k, 0), tr = br + SIMD3<Float>(0, 2 * k, 0)
            // both sides are drawn (a cut-out is seen from behind too)
            m.quad(bl, br, tr, tl, normal: n, uv: ([u0, v(r1)], [u1, v(r1)], [u1, v(r0)], [u0, v(r0)]))
            m.quad(br, bl, tl, tr, normal: -n, uv: ([u1, v(r1)], [u0, v(r1)], [u0, v(r0)], [u1, v(r0)]))
        }
    }

    public static func build(_ input: ChunkInput3D, gen: Generator, anime: Bool = false) -> ChunkMesh3D {
        var out = ChunkMesh3D()
        out.solid.cel = anime
        let g = input.layers[0], st = input.layers[1], ob = input.layers[2], de = input.layers[3]
        let storey = input.depth >= OpenWorld.storeyBase ? input.depth - OpenWorld.storeyBase : 0
        let bx = input.cx * 32, by = input.cy * 32
        // ground tops on a 34 x 34 grid: the chunk and one tile around it
        var h = [Float](repeating: 0, count: 34 * 34)
        func edge(_ tx: Int, _ ty: Int) -> (UInt8, UInt8) {
            let x = Swift.min(31, Swift.max(0, tx)), y = Swift.min(31, Swift.max(0, ty))
            if ty < 0, let n = input.north { return (n.ground[x], n.structure[x]) }
            if ty > 31, let s = input.south { return (s.ground[x], s.structure[x]) }
            if tx < 0, let w = input.west { return (w.ground[y], w.structure[y]) }
            if tx > 31, let e = input.east { return (e.ground[y], e.structure[y]) }
            return (g[y * 32 + x], st[y * 32 + x])
        }
        for ty in -1...32 { for tx in -1...32 {
            let inside = tx >= 0 && tx < 32 && ty >= 0 && ty < 32
            let ids = inside ? (g[ty * 32 + tx], st[ty * 32 + tx]) : edge(tx, ty)
            let lv = input.depth == 1 ? 0 : Terrain3D.level(elevation: gen.elevation(bx + tx, by + ty)) + storey * Terrain3D.storeyLevels
            // air on a storey: nothing to stand on, nothing drawn
            h[(ty + 1) * 34 + tx + 1] = storey > 0 && ids.0 == 0 ? Mesher3D.air : Terrain3D.groundY(level: lv, ground: ids.0, structure: ids.1, depth: input.depth)
        } }
        func H(_ tx: Int, _ ty: Int) -> Float { h[(ty + 1) * 34 + tx + 1] }
        for ty in 0..<32 { for tx in 0..<32 { out.heights[ty * 32 + tx] = H(tx, ty) } }
        // relief: the fall of the ground from the north-west to the south-east round each tile (water stays flat)
        for ty in 0..<32 { for tx in 0..<32 {
            func G(_ x: Int, _ y: Int) -> Float { let v = H(x, y); return v == Mesher3D.air ? H(tx, ty) : v }
            let nw = (G(tx - 1, ty - 1) + G(tx - 1, ty) + G(tx, ty - 1)) / 3, se = (G(tx + 1, ty + 1) + G(tx + 1, ty) + G(tx, ty + 1)) / 3
            // the sun is in the south-east (as for every solid): ground climbing towards the north-west faces it
            let rise = nw - se
            let wet = Content.shared.water[Int(g[ty * 32 + tx])]
            out.relief[ty * 32 + tx] = wet || input.depth == 1 ? 1 : Swift.max(0.55, Swift.min(1.32, 1 + rise * 0.42))
        } }

        // ground tops: runs of equal height along a row become one quad over the ground picture
        func v(_ row: Float) -> Float { flipV ? 1 - row / 32 : row / 32 }
        for ty in 0..<32 {
            var tx = 0
            while tx < 32 {
                let y = H(tx, ty)
                if y == Mesher3D.air { tx += 1; continue }
                var end = tx + 1
                while end < 32 && H(end, ty) == y { end += 1 }
                let x0 = Float(tx), x1 = Float(end), z0 = Float(ty), z1 = Float(ty + 1)
                out.ground.quad([x0, y, z1], [x1, y, z1], [x1, y, z0], [x0, y, z0], normal: [0, 1, 0],
                                uv: ([x0 / 32, v(z1)], [x1 / 32, v(z1)], [x1 / 32, v(z0)], [x0 / 32, v(z0)]))
                tx = end
            }
        }

        // a storey's floors are slabs a quarter of a level thick, seen from below and at their open edges
        if storey > 0 {
            for ty in 0..<32 { for tx in 0..<32 {
                let y = H(tx, ty)
                guard y != Mesher3D.air else { continue }
                let c = colors[Int(g[ty * 32 + tx])].0.darkened(0.3)
                var f: Mesh3D.Faces = [.bottom]
                if H(tx, ty + 1) == Mesher3D.air { f.insert(.south) }
                if H(tx, ty - 1) == Mesher3D.air { f.insert(.north) }
                if H(tx + 1, ty) == Mesher3D.air { f.insert(.east) }
                if H(tx - 1, ty) == Mesher3D.air { f.insert(.west) }
                out.solid.box(Float(tx), y - 0.25, Float(ty), Float(tx + 1), y, Float(ty + 1), c, faces: f)
            } }
        }
        // the sides of every step down to a lower neighbour
        for ty in 0..<32 { for tx in 0..<32 where storey == 0 {
            let y = H(tx, ty)
            let c = colors[Int(g[ty * 32 + tx])].0.darkened(0.22)
            let x0 = Float(tx), x1 = Float(tx + 1), z0 = Float(ty), z1 = Float(ty + 1)
            let s = H(tx, ty + 1), n = H(tx, ty - 1), e = H(tx + 1, ty), w = H(tx - 1, ty)
            if s < y { out.solid.box(x0, s, z0, x1, y, z1, c, faces: .south) }
            if n < y { out.solid.box(x0, n, z0, x1, y, z1, c, faces: .north) }
            if e < y { out.solid.box(x0, e, z0, x1, y, z1, c, faces: .east) }
            if w < y { out.solid.box(x0, w, z0, x1, y, z1, c, faces: .west) }
        } }

        // what stands on the ground
        func blockTop(_ tx: Int, _ ty: Int) -> Float {
            guard tx >= 0, tx < 32, ty >= 0, ty < 32 else { return -1000 }
            let i = ty * 32 + tx
            let b = Swift.max(blockHeight[Int(st[i])], blockHeight[Int(ob[i])])
            return b > 0 ? H(tx, ty) + b / 16 : -1000
        }
        func family(_ tx: Int, _ ty: Int) -> Bool {          // something a fence or a gate joins on to
            guard tx >= 0, tx < 32, ty >= 0, ty < 32 else { return false }
            let i = ty * 32 + tx
            if blockHeight[Int(ob[i])] > 0 || blockHeight[Int(st[i])] > 0 { return true }
            guard let t = Content.shared.tiles[Int(ob[i])] else { return false }
            return ["fence", "gate", "citygate", "citygate_open", "door"].contains(t.artKind)
        }
        for ty in 0..<32 { for tx in 0..<32 {
            let i = ty * 32 + tx
            let y = H(tx, ty)
            let o = SIMD3<Float>(Float(tx), y, Float(ty))
            for id in [st[i], ob[i]] where blockHeight[Int(id)] > 0 {
                let top = y + blockHeight[Int(id)] / 16
                let col = colors[Int(id)]
                let x0 = Float(tx), x1 = Float(tx + 1), z0 = Float(ty), z1 = Float(ty + 1)
                out.solid.box(x0, y, z0, x1, top, z1, col.0.lightened(0.12), faces: .top)
                // a side is only drawn where the neighbour is not a block at least as high
                var f: Mesh3D.Faces = []
                if blockTop(tx, ty + 1) < top { f.insert(.south) }
                if blockTop(tx, ty - 1) < top { f.insert(.north) }
                if blockTop(tx + 1, ty) < top { f.insert(.east) }
                if blockTop(tx - 1, ty) < top { f.insert(.west) }
                if !f.isEmpty {
                    out.solid.box(x0, y, z0, x1, top - 0.125, z1, col.1, faces: f)
                    out.solid.box(x0, top - 0.125, z0, x1, top, z1, col.0.lightened(0.12), faces: f)
                }
            }
            for id in [de[i], ob[i]] where id != 0 && blockHeight[Int(id)] == 0 {
                guard let t = Content.shared.tiles[Int(id)] else { continue }
                if anime && spriteKinds.contains(t.artKind) {
                    addSprite(&out.sprites, id: Int(id), at: o, salt: Int(MP.h2(7, bx + tx, by + ty) & 0xff), scale: spriteScale(t.artKind))
                    continue
                }
                let n = family(tx, ty - 1), s = family(tx, ty + 1), e = family(tx + 1, ty), w = family(tx - 1, ty)
                TileShapes.add(t, to: &out.solid, at: o, colors: colors[Int(id)], joins: (n, s, e, w), salt: Int(MP.h2(7, bx + tx, by + ty) & 0xff))
            }
        } }
        if anime { out.solid = out.solid.inked() }
        return out
    }
}

public extension PixelArt {
    /// The flat part of a chunk as one 512 x 512 picture (ground, paths, roads, bridges): what the
    /// 3D view lays over the ground tops. Pure function of the layers.
    static func bakeGround(layers: [[UInt8]], relief: [Float]? = nil) -> Bitmap {
        let at = atlas
        var img = Bitmap(MP.chunkPx, MP.chunkPx)
        defer { if let r = relief { img.shadeRelief(r, tilePx: 16) } }
        let g = layers[0], st = layers[1]
        let cliff = Content.shared.tid("cliff")
        for i in 0..<MP.chunkArea {
            let x = (i % 32) * 16, y = (i / 32) * 16
            img.blit(at, sx: (Int(g[i]) % 16) * cell, sy: (Int(g[i]) / 16) * cell, sw: 16, sh: 16, dx: x, dy: y, blend: false)
            if st[i] != 0 && st[i] != cliff {
                img.blit(at, sx: (Int(st[i]) % 16) * cell, sy: (Int(st[i]) / 16) * cell, sw: 16, sh: 16, dx: x, dy: y, blend: false)
            }
        }
        return img
    }
}

/// The solid shape of every tile that is not a plain block, built from the same colours and roughly
/// the same proportions as its 2D picture. Sizes are in sixteenths of a tile.
enum TileShapes {
    static func add(_ t: TileDef, to m: inout Mesh3D, at o: SIMD3<Float>, colors: (RGBA, RGBA, RGBA), joins: (n: Bool, s: Bool, e: Bool, w: Bool), salt: Int) {
        let (c1, c2, c3) = colors
        // things that sit in a wall turn with it: a wall running north-south turns them a quarter
        let turned = (joins.n || joins.s) && !(joins.e || joins.w)
        func b(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: RGBA) {
            if turned { m.px(o, z, y, x, d, h, w, c) } else { m.px(o, x, y, z, w, h, d, c) }
        }
        let grey = RGBA(hex: "#6e7079"), wood = RGBA(hex: "#6b4a2c")
        switch t.artKind {
        case "tree":
            let lean = Float(salt % 3) - 1
            b(6, 0, 6, 4, 11, 4, c3)
            b(0, 10, 0, 16, 9, 16, c2); b(2 + lean, 18, 2, 12, 6, 12, c1); b(5 + lean, 24, 5, 6, 3, 6, c1.lightened(0.18))
        case "pine":
            b(7, 0, 7, 3, 6, 3, c3)
            b(1, 5, 1, 14, 5, 14, c2 == .white ? c1 : c2); b(3, 10, 3, 10, 6, 10, c1); b(5, 16, 5, 6, 6, 6, c1); b(7, 22, 7, 2, 4, 2, c2)
            if t.key == "tree_snow_pine" { b(3, 15.5, 3, 10, 1, 10, c2); b(1, 9.5, 1, 14, 1, 14, c2) }
        case "deadtree":
            b(7, 0, 7, 3, 17, 3, c1); b(3, 11, 7, 4, 2, 2, c2); b(10, 13, 7, 4, 2, 2, c2); b(7, 9, 3, 2, 2, 4, c2)
        case "cactus":
            b(6, 0, 6, 4, 14, 4, c1); b(2, 6, 7, 4, 2, 2, c2); b(2, 8, 7, 2, 4, 2, c2); b(10, 8, 7, 4, 2, 2, c2); b(12, 10, 7, 2, 4, 2, c2)
        case "bush", "berrybush":
            b(3, 0, 3, 10, 6, 10, c2); b(4, 6, 4, 8, 3, 8, c1)
            if t.artKind == "berrybush" { b(5, 9, 6, 2, 1, 2, c3); b(9, 9, 9, 2, 1, 2, c3); b(12.5, 3, 6, 1, 2, 2, c3); b(6, 3, 12.5, 2, 2, 1, c3) }
        case "rock", "ore":
            b(3, 0, 4, 10, 6, 9, c2); b(4, 6, 5, 7, 3, 6, c1)
            if t.artKind == "ore" { b(5, 9, 6, 2, 1, 2, c3); b(8, 9, 8, 2, 1, 2, c3); b(12.5, 2, 7, 1, 2, 2, c3); b(6, 2, 12.5, 2, 2, 1, c3) }
        case "door":
            // a doorway you can see from the street: a frame as tall as the wall, a lintel, a panelled door with
            // its handle, a little roof over it and a lamp on each side of the wall
            let frame = c2.darkened(0.1), gold = RGBA(hex: "#e8c84a"), lamp = RGBA(hex: "#ffe08a")
            b(0, 0, 4.5, 2, 24, 7, frame); b(14, 0, 4.5, 2, 24, 7, frame)
            b(0, 19, 4, 16, 5, 8, frame)
            b(2, 0, 7, 12, 19, 2, c1)
            for (px, py) in [(Float(3.2), Float(10.5)), (8.6, 10.5), (3.2, 2), (8.6, 2)] {
                b(px, py, 6.6, 4.2, 6.5, 2.8, c1.darkened(0.12))
            }
            b(11.5, 8.5, 5.6, 1.4, 1.4, 4.8, gold)
            b(-1.5, 24, 1, 19, 1.5, 14, c3.darkened(0.15)); b(0, 25.5, 2.5, 16, 1, 11, c3)
            b(-1.6, 15, 1.4, 1.4, 3, 1.4, lamp); b(-1.6, 15, 13.2, 1.4, 3, 1.4, lamp)
            b(16.2, 15, 1.4, 1.4, 3, 1.4, lamp); b(16.2, 15, 13.2, 1.4, 3, 1.4, lamp)
        case "fence", "gate":
            let post = t.artKind == "gate" ? c1.lightened(0.15) : c2
            m.px(o, 6, 0, 6, 4, 13, 4, post)
            let alone = !(joins.n || joins.s || joins.e || joins.w)
            if t.artKind == "fence" {
                for y: Float in [5, 10] {
                    if joins.w || alone { m.px(o, 0, y, 7, 6, 2, 2, c1) }
                    if joins.e || alone { m.px(o, 10, y, 7, 6, 2, 2, c1) }
                    if joins.n { m.px(o, 7, y, 0, 2, 2, 6, c1) }
                    if joins.s { m.px(o, 7, y, 10, 2, 2, 6, c1) }
                }
            } else {
                b(0, 3, 7, 16, 2, 2, c1); b(0, 8, 7, 16, 2, 2, c1)
            }
        case "citygate":
            b(0, 0, 4, 16, 24, 8, c3.darkened(0.3)); b(1, 0, 3, 14, 20, 10, c1); b(5, 0, 2.5, 1, 20, 11, c2); b(10, 0, 2.5, 1, 20, 11, c2)
        case "citygate_open":
            b(0, 0, 4, 3, 24, 8, c3.darkened(0.3)); b(13, 0, 4, 3, 24, 8, c3.darkened(0.3)); b(0, 21, 4, 16, 3, 8, c3.darkened(0.2))
        case "crop":
            let h = Float(3 + t.stage * 4)
            for x: Float in [2, 7, 12] { b(x, 0, 2, 2, h, 12, c1); if t.stage == 2 { b(x - 0.5, h, 2, 3, 2, 12, c1.lightened(0.15)) } }
        case "sapling":
            b(7, 0, 7, 2, 6, 2, c2); b(5, 5, 5, 6, 5, 6, c1)
        case "flower":
            b(7.5, 0, 7.5, 1, 5, 1, c2); b(6.5, 5, 6.5, 3, 3, 3, c1); b(7.5, 8, 7.5, 1, 0.5, 1, RGBA(hex: "#fff7cf"))
        case "tuft", "leaves":
            for (i, p) in [(3, 10), (6, 5), (9, 11), (12, 6), (7, 13)].enumerated() { b(Float(p.0), 0, Float(p.1), 1, t.artKind == "leaves" ? 1 : Float(3 + (i + salt) % 3), 1, i % 2 == 0 ? c1 : c2) }
        case "mushroom":
            b(7, 0, 7, 2, 4, 2, c2); b(5, 4, 5, 6, 3, 6, c1)
        case "pebbles", "shell", "bones":
            b(4, 0, 10, 3, 2, 3, c1); b(9, 0, 6, 3, 2, 2, c2); b(11, 0, 12, 2, 1, 3, c1)
        case "lily":
            b(4, 0, 4, 8, 0.6, 8, c1); b(7, 0.6, 7, 2, 1.4, 2, c2)
        case "campfire", "campfire_out":
            b(3, 0, 6, 10, 3, 4, c1); b(6, 0, 3, 4, 3, 10, c1.darkened(0.15)); b(2, 0, 2, 2, 2, 2, grey); b(12, 0, 2, 2, 2, 2, grey); b(2, 0, 12, 2, 2, 2, grey); b(12, 0, 12, 2, 2, 2, grey)
            if t.artKind == "campfire" { b(6, 3, 6, 4, 5, 4, c2); b(7, 8, 7, 2, 3, 2, c3) }
        case "bed":
            b(1, 0, 1, 14, 4, 14, c3); b(2, 4, 5, 12, 2, 9, c1); b(3, 4, 1.5, 10, 3, 3, c2)
        case "chest":
            b(2, 0, 4, 12, 6, 8, c2); b(2, 6, 4, 12, 4, 8, c1); b(7, 5, 12, 2, 3, 1, c3)
        case "well", "well_broken":
            b(2, 0, 2, 12, 7, 2, c2); b(2, 0, 12, 12, 7, 2, c2); b(2, 0, 4, 2, 7, 8, c1); b(12, 0, 4, 2, 7, 8, c1)
            b(4, 0, 4, 8, 5, 8, t.artKind == "well" ? c3 : RGBA(hex: "#2a2a2a"))
            if t.artKind == "well" { b(2, 7, 7, 2, 11, 2, wood); b(12, 7, 7, 2, 11, 2, wood); b(1, 18, 4, 14, 2, 8, wood.lightened(0.15)) }
        case "lantern", "moonlantern", "torch":
            let h: Float = t.artKind == "torch" ? 9 : 17
            b(7, 0, 7, 2, h, 2, c1); b(5.5, h, 5.5, 5, 5, 5, c2)
        case "grave":
            b(4, 0, 6, 8, 11, 3, c1); b(5, 11, 6, 6, 2, 3, c1); b(7, 4, 9, 2, 5, 0.5, c2); b(6, 7, 9, 4, 1, 0.5, c2)
        case "machine":
            b(1, 0, 2, 14, 9, 12, c2); b(1, 9, 2, 14, 3, 12, c1); b(12, 12, 4, 2, 4, 2, c2); b(9, 3, 14, 4, 3, 0.5, c3)
        case "chimney":
            b(4, 0, 4, 8, 26, 8, c2); b(3, 26, 3, 10, 3, 10, c1.lightened(0.1)); b(6, 31, 6, 4, 4, 4, c3)
        case "server":
            b(2, 0, 3, 12, 22, 10, c2); b(2, 22, 3, 12, 2, 10, c1)
            for i in 0..<5 { b(4, 2 + Float(i) * 4, 13, 8, 2, 0.5, i % 2 == 0 ? c3 : c1) }
        case "antenna":
            b(7, 0, 7, 2, 28, 2, c2); b(3, 22, 7.5, 10, 1, 1, c1); b(5, 17, 7.5, 6, 1, 1, c1); b(6, 28, 6, 4, 2, 4, c3); b(4, 0, 4, 8, 2, 8, c2)
        case "desk", "table", "workbench":
            b(1, 7, 3, 14, 2, 10, c1)
            for (x, z) in [(2, 4), (12, 4), (2, 10), (12, 10)] { b(Float(x), 0, Float(z), 2, 7, 2, c2) }
            if t.artKind == "desk" { b(5, 9, 5, 6, 5, 1, c3) }
            if t.artKind == "workbench" { b(3, 9, 5, 5, 1, 2, grey); b(10, 9, 8, 3, 2, 3, c2) }
        case "chair":
            b(4, 0, 4, 8, 6, 8, c2); b(4, 6, 4, 8, 1, 8, c1); b(4, 7, 4, 8, 8, 2, c1)
        case "furnace":
            b(2, 0, 2, 12, 14, 12, c1); b(3, 14, 3, 10, 2, 10, c2); b(5, 2, 14, 6, 5, 0.5, c3); b(6, 16, 6, 4, 6, 4, c2)
        case "anvil":
            b(5, 0, 5, 6, 4, 6, c2); b(2, 4, 4, 12, 4, 8, c1)
        case "barrel":
            b(4, 0, 4, 8, 12, 8, c1); b(3.5, 3, 3.5, 9, 1, 9, c2); b(3.5, 9, 3.5, 9, 1, 9, c2)
        case "crate":
            b(2, 0, 2, 12, 12, 12, c1); b(1.5, 0, 1.5, 13, 2, 13, c2); b(1.5, 10, 1.5, 13, 2, 13, c2)
        case "sign":
            b(7, 0, 7, 2, 8, 2, c2); b(3, 8, 7, 10, 6, 1.5, c1)
        case "bookshelf":
            b(2, 0, 4, 12, 22, 8, c1)
            for i in 0..<4 { b(3, 2 + Float(i) * 5, 12, 10, 3, 0.5, i % 2 == 0 ? c2 : c3) }
        case "pillar":
            b(4, 0, 4, 8, 24, 8, c1); b(3, 24, 3, 10, 2, 10, c2); b(3, 0, 3, 10, 2, 10, c2)
        case "statue":
            b(3, 0, 3, 10, 4, 10, c2); b(5, 4, 6, 6, 10, 4, c1); b(6, 14, 6, 4, 4, 4, c1); b(3, 8, 7, 2, 6, 2, c1); b(11, 8, 7, 2, 6, 2, c1)
        case "altar":
            b(2, 0, 3, 12, 8, 10, c1); b(1, 8, 2, 14, 2, 12, c1.lightened(0.1)); b(5, 10, 5, 6, 3, 6, c2)
        case "stall":
            b(1, 0, 5, 14, 8, 7, c1); b(1, 8, 12, 1, 10, 1, c1); b(14, 8, 12, 1, 10, 1, c1); b(1, 8, 3, 1, 10, 1, c1); b(14, 8, 3, 1, 10, 1, c1)
            for i in 0..<4 { b(Float(i) * 4, 18, 2, 4, 2, 12, i % 2 == 0 ? c2 : c3) }
        case "pot":
            b(5, 0, 5, 6, 5, 6, c1); b(6, 5, 6, 4, 5, 4, c3); b(7, 10, 7, 2, 2, 2, c2)
        case "scarecrow":
            b(7, 0, 7, 2, 20, 2, c2); b(2, 13, 7, 12, 2, 2, c2); b(5, 15, 5.5, 6, 6, 5, c1); b(4, 21, 4.5, 8, 2, 7, c3)
        case "tent":
            b(1, 0, 1, 14, 5, 14, c1); b(3, 5, 3, 10, 5, 10, c1); b(5, 10, 5, 6, 4, 6, c2); b(6, 0, 15, 4, 6, 0.5, c2.darkened(0.4))
        case "stairs":
            b(1, 0, 1, 14, 1, 14, c2)
            for i in 0..<4 { b(2, 1, 2 + Float(i) * 3, 12, Float(i + 1) * 2, 3, c1.lerp(c3, Double(i) / 4)) }
        case "lever", "lever_on":
            b(4, 0, 6, 8, 3, 4, c1)
            let x: Float = t.artKind == "lever" ? 5 : 9
            b(x, 3, 7, 2, 8, 2, c1.lightened(0.2)); b(x - 1, 11, 6, 4, 3, 4, c2)
        case "plate":
            b(2, 0, 2, 12, 1, 12, c2); b(3, 1, 3, 10, 0.6, 10, c1)
        case "trap":
            b(2, 0, 2, 12, 2, 12, c1)
            for x: Float in [3, 6, 9, 12] { b(x, 2, 5, 1, 6, 1, c2); b(x, 2, 10, 1, 6, 1, c2) }
        case "wire":
            b(7, 0, 0, 2, 0.6, 16, c1); b(0, 0, 7, 16, 0.6, 2, c1); b(6.5, 0, 6.5, 3, 1, 3, c2)
        case "lamp":
            b(6, 0, 6, 4, 10, 4, c1); b(4, 10, 4, 8, 7, 8, c2)
        case "banner":
            b(7, 0, 7, 2, 30, 2, wood); b(9, 17, 7.5, 7, 12, 1, c1); b(9, 17, 7.4, 7, 2, 1.2, c2); b(11, 21, 7.3, 3, 5, 1.4, c1.lightened(0.55))
        case "throne":
            b(2, 0, 3, 12, 7, 11, c1); b(3, 7, 3, 10, 12, 3, c2); b(4, 7, 6, 8, 1, 7, c2); b(7, 19, 3.5, 2, 3, 2, c1)
        case "tower":
            b(2, 0, 2, 12, 36, 12, c2); b(1, 36, 1, 14, 3, 14, c1)
            for (x, z) in [(1, 1), (12, 1), (1, 12), (12, 12)] { b(Float(x), 39, Float(z), 3, 3, 3, c1) }
            b(7, 22, 14, 2, 4, 0.5, RGBA(hex: "#2a2233"))
        case "mill":
            b(4, 0, 4, 8, 24, 8, c1); b(3, 24, 3, 10, 3, 10, c2); b(6, 0, 12, 4, 7, 0.5, c2)
            b(-3, 20, 13, 22, 2, 1, c2); b(7, 10, 13.2, 2, 22, 1, c2)
        case "ballista":
            b(2, 0, 4, 12, 4, 8, c1); b(7, 4, 1, 2, 2, 14, c1); b(1, 5, 3, 14, 1, 1, c2); b(2, 0, 3, 2, 5, 2, c1.darkened(0.3)); b(12, 0, 3, 2, 5, 2, c1.darkened(0.3))
        case "ai_core":
            b(2, 0, 2, 12, 8, 12, c1); b(4, 8, 4, 8, 3, 8, c1.lightened(0.15)); b(4, 13, 4, 8, 8, 8, c2); b(6, 21, 6, 4, 2, 4, c3)
        case "star":
            b(6, 2, 6, 4, 4, 4, c1); b(7, 1, 7, 2, 6, 2, c2); b(5, 3, 7, 6, 2, 2, c2)
        default:
            b(2, 0, 2, 12, 8, 12, c2); b(2, 8, 2, 12, 4, 12, c1)
        }
    }
}

/// People, animals, roofs and standards as meshes. A figure stands on y = 0 at the origin and looks
/// south (+z); the renderer turns it. Sizes are in sixteenths of a tile, like the tile shapes.
public enum Figure3D {
    public static let adultHeight: Float = 24.0 / 16

    /// frame: 0 standing, 1 and 2 the two steps of a walk, 3 working or striking.
    public static func human(_ look: Look, frame: Int, held: String, child: Bool, female: Bool, face: Bitmap? = nil) -> Mesh3D {
        var m = Mesh3D()
        let k: Float = child ? 0.68 : 1
        let o = SIMD3<Float>(0, 0, 0)
        func b(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: RGBA) { m.px(o, x, y, z, w, h, d, c, scale: k, faces: .all) }
        // modelled with curves: every measure is in sixteenths of a tile (as the figure was drawn), scaled by k
        func P(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x, y, z) * (k / 16) }
        func R(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x, y, z) * (k / 16) }
        let u = k / 16
        let skin = RGBA(hex: look.skin), hair = RGBA(hex: look.hair), shirt = RGBA(hex: look.shirt), pants = RGBA(hex: look.pants), shoes = RGBA(hex: look.shoes)
        // legs swing forwards and back; arms the other way
        let sw: Float = frame == 1 ? 2 : (frame == 2 ? -2 : 0)
        let acting = frame == 3
        // legs: a thigh and a shin each (tapered), knees bent a little in a step, shoes as rounded toes
        for (x, swing) in [(-2.0 as Float, sw), (2.0, -sw)] {
            let hip = P(x, 7.5, 0), knee = P(x, 4, swing * 0.6 + 0.3), ankle = P(x, 1.2, swing)
            m.frustum(hip, knee, 1.6 * u, 1.35 * u, pants, seg: 8)
            m.frustum(knee, ankle, 1.35 * u, 1.05 * u, pants, seg: 8)
            m.ellipsoid(P(x, 0.95, swing + 0.6), R(1.5, 0.95, 2.3), shoes, seg: 8, rings: 4)          // the sole on the ground
        }
        // the body: hips, a waist and a chest (ellipsoids), a skirt for a woman, a collar
        m.ellipsoid(P(0, 8, 0), R(3.6, 1.9, 2.3), pants, seg: 12, rings: 5)
        m.frustum(P(0, 8.5, 0), P(0, 11, 0), 3.0 * u, 3.4 * u, shirt, seg: 12, caps: false)
        m.ellipsoid(P(0, 12.3, 0), R(4.0, 3.0, 2.5), shirt, seg: 12, rings: 6)
        if female { m.frustum(P(0, 9.6, 0), P(0, 5.2, 0), 3.5 * u, 5.0 * u, shirt.darkened(0.1), seg: 14) }
        m.frustum(P(0, 14.6, 0), P(0, 15.8, 0), 1.2 * u, 1.1 * u, skin, seg: 8)                       // the neck
        m.ellipsoid(P(0, 14.8, 0), R(2.4, 0.7, 1.8), shirt.lightened(0.15), seg: 10, rings: 3)       // the collar
        // arms: shoulder, elbow, hand (one raised when working or striking)
        for side: Float in [-1, 1] {
            let raised = acting && side > 0
            let swing: Float = side < 0 ? -sw : sw
            let shoulder = P(side * 4.4, 14, 0)
            let elbow = raised ? P(side * 5.4, 17.5, 0.5) : P(side * 5.0, 10.8, swing * 0.5)
            let hand = raised ? P(side * 5.2, 21, 0.5) : P(side * 5.2, 7.6, swing)
            m.ellipsoid(shoulder, R(1.6, 1.5, 1.6), shirt, seg: 8, rings: 4)
            m.frustum(shoulder, elbow, 1.15 * u, 1.0 * u, shirt.darkened(0.06), seg: 8)
            m.frustum(elbow, hand, 0.95 * u, 0.8 * u, skin, seg: 8)
            m.ellipsoid(hand, R(0.95, 1.1, 0.95), skin, seg: 8, rings: 4)
        }
        // the head: a rounded skull and a chin, ears; the hair as a cap over it, longer behind for long hair
        let hc = P(0, 19.2, 0)
        m.ellipsoid(hc, R(3.9, 4.1, 3.7), skin, seg: 14, rings: 8)
        m.ellipsoid(P(0, 17.0, 0.9), R(2.7, 1.8, 2.6), skin, seg: 10, rings: 4)
        for side: Float in [-1, 1] { m.ellipsoid(P(side * 3.9, 19.0, -0.2), R(0.6, 1.0, 0.8), skin.darkened(0.06), seg: 6, rings: 3) }
        m.ellipsoid(P(0, 19.8, -0.35), R(4.25, 4.15, 4.0), hair, seg: 14, rings: 6, from: 0.48, to: 1)
        m.ellipsoid(P(0, 21.6, 2.6), R(3.6, 1.2, 1.2), hair, seg: 10, rings: 3)                        // the fringe
        if female || look.style % 3 == 1 {
            // long hair falling behind to the shoulders
            m.ellipsoid(P(0, 16.5, -2.6), R(4.0, 5.0, 1.6), hair, seg: 12, rings: 5)
        }
        if look.style % 3 == 2 { m.ellipsoid(P(0, 24.2, -1.0), R(1.9, 1.6, 1.9), hair, seg: 8, rings: 4) }   // a bun
        if look.style % 4 == 3 { m.frustum(P(0, 20, -3.8), P(0, 13.5, -5.2), 1.3 * u, 0.5 * u, hair, seg: 8) }   // a ponytail
        if let f = face, f.w > 0, f.h > 0 {
            // a face made from a photo: its pixels become small plates on the front of the head
            let n = 8
            for gy in 0..<n { for gx in 0..<n {
                let c = f.get(Swift.min(f.w - 1, gx * f.w / n + f.w / (2 * n)), Swift.min(f.h - 1, gy * f.h / n + f.h / (2 * n)))
                if c.a < 128 { continue }
                m.px(o, -4 + Float(gx), 22 - Float(gy), 3.6, 1, 1, 0.25, c, scale: k, faces: [.south])
            } }
        } else {
            // eyes with a light in each, brows, a mouth, a blush
            let ink = RGBA(hex: "#2a1e24")
            for side: Float in [-1, 1] {
                m.ellipsoid(P(side * 1.45, 19.2, 3.45), R(0.62, 0.9, 0.35), ink, seg: 8, rings: 4)
                m.ellipsoid(P(side * 1.25, 19.55, 3.72), R(0.2, 0.22, 0.1), RGBA(255, 255, 255), seg: 6, rings: 3)
                m.frustum(P(side * 0.7, 20.6, 3.55), P(side * 2.2, 20.8, 3.4), 0.18 * u, 0.12 * u, hair.darkened(0.3), seg: 4)
                m.ellipsoid(P(side * 2.4, 17.9, 3.1), R(0.8, 0.4, 0.2), RGBA(240, 140, 150), seg: 6, rings: 3)
            }
            m.frustum(P(-0.6, 17.0, 3.55), P(0.6, 17.0, 3.55), 0.16 * u, 0.16 * u, RGBA(170, 80, 90), seg: 4)
        }
        // what the right hand holds
        let hy: Float = acting ? 20 : 7, hz: Float = acting ? 0 : sw
        let steel = RGBA(hex: "#c8ccd8"), wood = RGBA(hex: "#8a5a30")
        switch held {
        case "sword": b(4.5, hy + 1, hz - 0.5, 1, 2, 1, wood); b(4.5, hy + 3, hz - 0.5, 1, 9, 1, steel); b(3.5, hy + 2.5, hz - 0.5, 3, 1, 1, wood)
        case "bow": b(6, hy - 4, hz - 0.5, 1, 12, 1, wood); b(5.5, hy - 4, hz - 0.5, 1, 1, 1, wood); b(5.5, hy + 7, hz - 0.5, 1, 1, 1, wood)
        case "staff": b(4.5, hy - 6, hz + 1, 1, 18, 1, wood); b(4, hy + 12, hz + 0.5, 2, 2, 2, RGBA(hex: "#59d8ff"))
        case "axe": b(4.5, hy, hz + 1, 1, 10, 1, wood); b(5.5, hy + 7, hz + 0.5, 3, 3, 2, steel)
        case "pick": b(4.5, hy, hz + 1, 1, 10, 1, wood); b(2, hy + 9, hz + 1, 6, 1, 1, steel)
        case "hoe": b(4.5, hy, hz + 1, 1, 11, 1, wood); b(4.5, hy + 10, hz + 2, 1, 1, 3, steel)
        case "hammer": b(4.5, hy, hz + 1, 1, 9, 1, wood); b(3.5, hy + 8, hz, 3, 3, 3, steel.darkened(0.25))
        case "basket": b(3, hy - 3, hz + 1, 5, 3, 4, RGBA(hex: "#c8a050"))
        case "cane": b(5, 0, hz + 2, 1, 9, 1, wood)
        default: break
        }
        return m
    }

    /// A four-legged animal looking south; the golem and the chicken walk on two.
    public static func animal(_ sp: Species, frame: Int) -> Mesh3D {
        var m = Mesh3D()
        let o = SIMD3<Float>(0, 0, 0)
        func b(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: RGBA) { m.px(o, x, y, z, w, h, d, c, faces: .all) }
        let body = RGBA(hex: sp.body), accent = RGBA(hex: sp.accent), ink = RGBA(hex: "#2a2233")
        let sw: Float = frame % 2 == 1 ? 1 : 0
        if sp.key == "chicken" {
            b(-2, 3, -3, 4, 4, 6, body); b(-1.5, 6, 2, 3, 3, 3, body); b(-0.5, 7, 5, 1, 1, 1, RGBA(hex: "#f0a020")); b(-0.5, 9, 3, 1, 1, 2, accent)
            b(-1.5, 0, -0.5 + sw, 1, 3, 1, RGBA(hex: "#f0a020")); b(0.5, 0, -0.5 - sw, 1, 3, 1, RGBA(hex: "#f0a020"))
            return m
        }
        if sp.key == "golem" {
            b(-5, 5, -3, 10, 11, 6, body); b(-3, 16, -2.5, 6, 4, 5, body.lightened(0.1)); b(-2, 17.5, 2.5, 1, 1, 0.3, accent); b(1, 17.5, 2.5, 1, 1, 0.3, accent)
            b(-7, 6, -1.5, 2, 9, 3, body.darkened(0.15)); b(5, 6, -1.5, 2, 9, 3, body.darkened(0.15)); b(-1, 9, 3, 2, 3, 0.3, accent)
            b(-4, 0, -1.5 + sw, 3, 5, 3, body.darkened(0.2)); b(1, 0, -1.5 - sw, 3, 5, 3, body.darkened(0.2))
            return m
        }
        let dims: [(Float, Float, Float)] = [(8, 5, 2), (11, 6, 4), (12, 6, 5), (14, 8, 6)]       // body length, body height, leg length
        let (len, bh, leg) = dims[Swift.min(sp.size, 3)]
        let wd = (bh * 0.9).rounded()
        b(-wd / 2, leg, -len / 2, wd, bh, len, body)
        let hy = leg + bh - (sp.size >= 2 ? 1 : 3)
        let head = sp.key == "sheep" || sp.key == "cow" ? accent.lerp(body, sp.key == "cow" ? 0.0 : 0.2) : body
        b(-2, hy, len / 2 - 1, 4, 4, 4, head)
        b(-1.5, hy + 2, len / 2 + 3, 0.8, 1, 0.3, ink); b(0.7, hy + 2, len / 2 + 3, 0.8, 1, 0.3, ink)
        switch sp.key {
        case "rabbit": b(-1.5, hy + 4, len / 2, 1, 3, 1, body); b(0.5, hy + 4, len / 2, 1, 3, 1, accent); b(-1, leg + 1, -len / 2 - 1, 2, 2, 1, .white)
        case "deer": b(-2, hy + 4, len / 2, 1, 3, 1, accent); b(1, hy + 4, len / 2, 1, 3, 1, accent)
        case "boar": b(-2, hy, len / 2 + 3, 1, 1, 1, accent); b(1, hy, len / 2 + 3, 1, 1, 1, accent)
        case "cow": b(-wd / 2 - 0.1, leg + 2, -2, wd + 0.2, 3, 4, accent)
        default: b(-0.5, leg + bh - 2, -len / 2 - 2, 1, 1, 2, body.darkened(0.15))
        }
        let lc = body.darkened(0.18)
        for (x, z, s) in [(-wd / 2, len / 2 - 2, sw), (wd / 2 - 1.5, len / 2 - 2, -sw), (-wd / 2, -len / 2 + 0.5, -sw), (wd / 2 - 1.5, -len / 2 + 0.5, sw)] {
            b(x, 0, z + s, 1.5, leg, 1.5, lc)
        }
        return m
    }

    /// A cavalry mount; the rider sits `saddleHeight` up.
    public static let saddleHeight: Float = 9.0 / 16
    public static func horse(frame: Int) -> Mesh3D {
        animal(Species(key: "horse", en: "", zh: "", hp: 0, speed: 0, meat: 0, hostile: false, tameable: false, size: 3, body: "#8a5a30", accent: "#3a2a1a"), frame: frame)
    }

    /// Each nation's roofing colours (base, lines, ridge), the same as the 2D roofs.
    public static func roofColors(nation: Int) -> (RGBA, RGBA, RGBA) {
        switch nation {
        case 1: return (RGBA(hex: "#5a6c88"), RGBA(hex: "#3a4a64"), RGBA(hex: "#8aa0c0"))
        case 2: return (RGBA(hex: "#b04a38"), RGBA(hex: "#7a2a22"), RGBA(hex: "#e07a5a"))
        case 3: return (RGBA(hex: "#c8a050"), RGBA(hex: "#8a6a2a"), RGBA(hex: "#e8c878"))
        default: return (RGBA(hex: "#7a5a3a"), RGBA(hex: "#523a24"), RGBA(hex: "#9a7a52"))
        }
    }

    /// A stepped roof over a building of w x h tiles; its corner is the origin and it starts at y = 0.
    public static func roof(nation: Int, w: Int, h: Int) -> Mesh3D {
        var m = Mesh3D()
        let (base, line, ridge) = roofColors(nation: nation)
        let fw = Float(w), fh = Float(h)
        let steps = Swift.max(1, Int((Swift.min(fw, fh) / 2 / 0.5).rounded(.up)))
        for i in 0..<steps {
            let inset = Float(i) * 0.5 - 0.25
            let x0 = inset, x1 = fw - inset, z0 = inset, z1 = fh - inset
            if x1 - x0 < 0.2 || z1 - z0 < 0.2 { break }
            let y = Float(i) * 0.3
            m.box(x0, y, z0, x1, y + 0.3, z1, i == steps - 1 ? ridge : (i % 2 == 0 ? base : (nation == 2 ? base.lightened(0.08) : line.lerp(base, 0.5))), faces: i == 0 ? .all : .noBottom)
        }
        if nation == 2 {            // upturned eaves
            for (x, z) in [(-0.25, -0.25), (fw - 0.05, -0.25), (-0.25, fh - 0.05), (fw - 0.05, fh - 0.05)] { m.box(x, 0.3, z, x + 0.3, 0.6, z + 0.3, ridge) }
        }
        return m
    }

    /// An army's standard: a pole and a cloth in the nation's colour, at the origin.
    public static func standard(color: RGBA) -> Mesh3D {
        var m = Mesh3D()
        let o = SIMD3<Float>(0, 0, 0)
        m.px(o, -1, 0, -1, 2, 44, 2, RGBA(hex: "#6b4a2c"), faces: .all)
        m.px(o, 1, 28, -0.5, 14, 14, 1, color, faces: .all)
        m.px(o, 1, 28, -0.6, 14, 3, 1.2, color.darkened(0.35), faces: .all)
        m.px(o, 6, 33, -0.7, 4, 5, 1.4, color.lightened(0.55), faces: .all)
        return m
    }

    /// A unit cube centred on the origin in one colour: particles, markers, previews.
    public static func cube(color: RGBA, size: Float = 1) -> Mesh3D {
        var m = Mesh3D()
        let s = size / 2
        m.box(-s, -s, -s, s, s, s, color, faces: .all)
        return m
    }

    /// A flat tile-sized plate lying on y = 0, its corner at the origin (build previews, rings).
    /// A machine of the regional wars as blocks, in its nation's colour, standing on y = 0 and centred on
    /// x, z = 0: a frame is a figure four tiles tall, a carrier a long hull with a flat deck and an island,
    /// a sky carrier a broad hull with wings and glowing lifters, the rest simpler shapes of their kind.
    public static func machine(_ kind: String, color: RGBA) -> Mesh3D {
        var m = Mesh3D()
        let dark = color.darkened(0.35), light = color.lightened(0.3), steel = RGBA(120, 126, 140), ink = RGBA(40, 42, 54), glow = RGBA(120, 220, 255)
        let def = CivUnitDef.byKey[kind]
        if def?.hangarBay != nil && def?.layer == .sea {
            m.box(-4, 0, -1.2, 4, 0.9, 1.2, steel, faces: .all); m.box(-4.4, 0.9, -1.4, 4.4, 1.05, 1.4, ink, faces: .all)
            m.box(1.5, 1.05, 0.7, 2.6, 2.2, 1.3, dark, faces: .all); m.box(-3, 1.05, -0.4, -2.2, 1.3, 0.4, color, faces: .all); m.box(-1, 1.05, -0.9, -0.2, 1.3, -0.1, color, faces: .all)
        } else if def?.hangarBay != nil {
            m.box(-3.5, 0.6, -1.5, 3.5, 1.8, 1.5, steel, faces: .all); m.box(-5.5, 1.0, -0.6, -3.5, 1.3, 0.6, dark, faces: .all); m.box(3.5, 1.0, -0.6, 5.5, 1.3, 0.6, dark, faces: .all)
            m.box(-2, 1.8, -0.8, 2, 2.4, 0.8, light, faces: .all); m.box(-1, 2.4, -0.4, 1, 2.7, 0.4, color, faces: .all)
            for x in [Float(-2.6), 2.0] { m.box(x, 0.2, -0.4, x + 0.6, 0.6, 0.4, glow, faces: .all) }
        } else if kind.hasSuffix("frame") || def?.size == .large {
            m.box(-0.7, 0, -0.35, -0.15, 1.5, 0.35, steel, faces: .all); m.box(0.15, 0, -0.35, 0.7, 1.5, 0.35, steel, faces: .all)
            m.box(-0.8, 1.5, -0.45, 0.8, 2.7, 0.45, dark, faces: .all); m.box(-1.25, 2.3, -0.5, 1.25, 3.0, 0.5, color, faces: .all)
            m.box(-1.6, 1.3, -0.3, -1.1, 2.6, 0.3, steel, faces: .all); m.box(1.1, 1.3, -0.3, 1.6, 2.6, 0.3, steel, faces: .all)
            m.box(-0.4, 3.0, -0.35, 0.4, 3.7, 0.35, light, faces: .all); m.box(-0.25, 3.3, 0.35, 0.25, 3.45, 0.4, RGBA(120, 255, 200), faces: .all)
            m.box(1.7, 0.6, -0.08, 1.85, 4.2, 0.08, RGBA(255, 120, 90), faces: .all)
        } else if def?.layer.air == true {
            m.box(-0.2, 0, -1.4, 0.2, 0.35, 1.4, steel, faces: .all); m.box(-1.4, 0.1, -0.3, 1.4, 0.22, 0.5, color, faces: .all); m.box(-0.5, 0.1, 1.0, 0.5, 0.2, 1.4, dark, faces: .all)
        } else if def?.layer == .sea || def?.layer == .underwater {
            m.box(-2.2, 0, -0.6, 2.2, 0.7, 0.6, def?.layer == .underwater ? ink : steel, faces: .all); m.box(-0.5, 0.7, -0.35, 0.5, 1.3, 0.35, color, faces: .all)
        } else if def?.size == .vehicle {
            m.box(-0.9, 0.15, -1.2, 0.9, 0.75, 1.2, dark, faces: .all); m.box(-0.55, 0.75, -0.6, 0.55, 1.15, 0.5, color, faces: .all)
            m.box(-0.08, 0.9, -1.9, 0.08, 1.05, -0.6, steel, faces: .all); m.box(-1.05, 0, -1.25, -0.9, 0.5, 1.25, ink, faces: .all); m.box(0.9, 0, -1.25, 1.05, 0.5, 1.25, ink, faces: .all)
        } else {
            for (x, z) in [(Float(-0.6), Float(-0.4)), (0, -0.6), (0.6, -0.4), (-0.35, 0.3), (0.35, 0.3), (0, 0.8)] {
                m.box(x - 0.14, 0, z - 0.1, x + 0.14, 0.6, z + 0.1, color, faces: .all); m.box(x - 0.11, 0.6, z - 0.1, x + 0.11, 0.82, z + 0.1, RGBA(240, 210, 180), faces: .all)
            }
        }
        return m
    }

    /// An outside elevator's car: a floor, four corner posts, a roof and glass sides, its corner at the
    /// origin, w x d tiles, 1.7 tall. The glass is a pale blue frame: you see the car going up and down.
    /// A glass lift car's frame: a polished floor with a light strip round it, slim steel posts at the corners,
    /// a roof with a ring of light under it, and a hand rail inside at waist height. (The glass is `liftGlass`.)
    public static func liftCar(w: Float, d: Float) -> Mesh3D {
        var m = Mesh3D()
        let steel = RGBA(196, 202, 214), deck = RGBA(230, 226, 214), light = RGBA(250, 246, 220), dark = RGBA(80, 86, 98)
        m.box(0, -0.12, 0, w, 0, d, deck, faces: .all)
        m.box(-0.03, -0.16, -0.03, w + 0.03, -0.12, d + 0.03, dark, faces: .all)
        m.box(0, 2.0, 0, w, 2.14, d, steel, faces: .all)                                // the roof
        m.box(0.12, 1.96, 0.12, w - 0.12, 2.0, d - 0.12, light, faces: .all)             // its light panel
        for (x, z) in [(Float(0), Float(0)), (w - 0.08, 0), (0, d - 0.08), (w - 0.08, d - 0.08)] { m.box(x, 0, z, x + 0.08, 2.0, z + 0.08, steel, faces: .all) }
        // a steel hand rail inside, at waist height, on three sides
        m.box(0.08, 0.95, 0.08, w - 0.08, 1.0, 0.13, steel, faces: .all)
        m.box(0.08, 0.95, 0.08, 0.13, 1.0, d - 0.08, steel, faces: .all)
        m.box(w - 0.13, 0.95, 0.08, w - 0.08, 1.0, d - 0.08, steel, faces: .all)
        return m
    }

    /// The glass of a lift car: a pane on each side from the floor to the roof, seen from outside and from
    /// inside (each face twice, once each way), so a rider looks out through it.
    public static func liftGlass(w: Float, d: Float, h: Float = 2.0) -> Mesh3D {
        var m = Mesh3D()
        let g = RGBA(200, 236, 250)
        func pane(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ dd: SIMD3<Float>) { m.face(a, b, c, dd, g); m.face(dd, c, b, a, g) }
        pane([0, 0, 0], [w, 0, 0], [w, h, 0], [0, h, 0])
        pane([w, 0, d], [0, 0, d], [0, h, d], [w, h, d])
        pane([0, 0, d], [0, 0, 0], [0, h, 0], [0, h, d])
        pane([w, 0, 0], [w, 0, d], [w, h, d], [w, h, 0])
        return m
    }

    /// The glass shaft a lift runs in, one tile high (scaled to the shaft's height), a little wider than the car.
    public static func liftShaft(w: Float, d: Float) -> Mesh3D {
        let k: Float = 0.12
        var m = Mesh3D()
        let g = RGBA(190, 226, 244)
        func pane(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ dd: SIMD3<Float>) { m.face(a, b, c, dd, g); m.face(dd, c, b, a, g) }
        pane([-k, 0, -k], [w + k, 0, -k], [w + k, 1, -k], [-k, 1, -k])
        pane([w + k, 0, d + k], [-k, 0, d + k], [-k, 1, d + k], [w + k, 1, d + k])
        pane([-k, 0, d + k], [-k, 0, -k], [-k, 1, -k], [-k, 1, d + k])
        pane([w + k, 0, -k], [w + k, 0, d + k], [w + k, 1, d + k], [w + k, 1, -k])
        return m
    }

    /// A vehicle, centred on the origin, its length along +x (forward), its width along z, its wheels on y = 0.
    /// Its size is the vehicle's own (`VehicleSpec.length` and `deckW`), so what is drawn is what collides.
    public static func vehicle(_ k: VehicleKind, livery: RGBA = RGBA(200, 60, 50)) -> Mesh3D {
        var m = Mesh3D()
        let sp = k.spec
        let L = Float(sp.length), W = Float(max(0.5, sp.deckW + 0.2)), hl = L / 2, hw = W / 2
        let glass = RGBA(150, 200, 230), dark = RGBA(40, 42, 48), white = RGBA(235, 236, 240), steel = RGBA(150, 156, 170)
        func wheels(_ xs: [Float]) { for x in xs { for z in [-hw, hw - 0.12] { m.box(x - 0.15, 0, z, x + 0.15, 0.3, z + 0.12, dark, faces: .all) } } }
        switch k {
        case .car:
            // a car is modelled with curved surfaces (Luxury.swift: `car`), an ordinary saloon in the livery
            _ = glass
            return car(.saloon, paint: String(format: "#%02x%02x%02x", livery.r, livery.g, livery.b))
        case .bus:
            m.box(-hl, 0.2, -hw, hl, 1.5, hw, livery, faces: .all)
            m.box(-hl + 0.1, 0.85, -hw - 0.01, hl - 0.3, 1.25, hw + 0.01, glass, faces: .all)
            m.box(hl - 0.05, 0.7, -hw + 0.08, hl + 0.01, 1.35, hw - 0.08, glass, faces: .all)
            wheels([-hl * 0.65, hl * 0.65])
        case .truck:
            m.box(hl - 0.7, 0.25, -hw, hl, 1.3, hw, livery, faces: .all)
            m.box(hl - 0.05, 0.8, -hw + 0.1, hl + 0.01, 1.2, hw - 0.1, glass, faces: .all)
            m.box(-hl, 0.35, -hw, hl - 0.75, 1.7, hw, steel, faces: .all)
            wheels([-hl * 0.7, -hl * 0.3, hl * 0.7])
        case .train, .hsr:
            let body = k == .hsr ? white : livery
            m.box(-hl, 0.25, -hw, hl - (k == .hsr ? 0.8 : 0), 1.5, hw, body, faces: .all)
            if k == .hsr { m.box(hl - 0.8, 0.25, -hw + 0.1, hl, 1.0, hw - 0.1, body, faces: .all); m.box(hl - 0.8, 1.0, -hw + 0.2, hl - 0.2, 1.3, hw - 0.2, glass, faces: .all) }
            m.box(-hl + 0.1, 0.95, -hw - 0.01, hl - 1, 1.25, hw + 0.01, glass, faces: .all)
            m.box(-hl, 0.25, -hw - 0.02, hl - 1, 0.4, hw + 0.02, livery, faces: .all)        // the stripe
            m.box(-hl, 0, -hw + 0.1, hl, 0.25, hw - 0.1, dark, faces: .all)
        case .fighter:
            // a grey dart: a slim fuselage, a delta wing, two fins, the canopy, one engine at the tail
            let grey = RGBA(118, 126, 136)
            m.box(-hl, 0.5, -0.22, hl - 0.4, 0.9, 0.22, grey, faces: .all)
            m.box(hl - 0.4, 0.55, -0.14, hl, 0.8, 0.14, grey, faces: .all)
            m.box(hl - 1.0, 0.85, -0.13, hl - 0.45, 1.05, 0.13, glass, faces: .all)
            m.box(-hl + 0.3, 0.62, -1.3, 0.2, 0.72, 1.3, grey, faces: .all)                  // the wing
            m.box(-hl + 0.2, 0.62, -0.6, -hl + 0.7, 0.68, 0.6, grey, faces: .all)            // tailplane
            for z in [Float(-0.3), 0.3] { m.box(-hl, 0.9, z - 0.04, -hl + 0.5, 1.6, z + 0.04, livery, faces: .all) }
            m.box(-hl - 0.15, 0.55, -0.16, -hl, 0.85, 0.16, dark, faces: .all)
            m.box(hl - 0.6, 0, -0.05, hl - 0.45, 0.5, 0.05, dark, faces: .all); for z in [Float(-0.35), 0.35] { m.box(-0.4, 0, z - 0.05, -0.2, 0.5, z + 0.05, dark, faces: .all) }
        case .airliner, .cargoPlane, .turboprop, .regionalJet, .widebody:
            // one shape, sized by the type: span and fuselage from its length; a wide-body has four engines,
            // a turboprop propellers on a high wing, a regional jet its engines at the tail
            let span: Float = k == .widebody ? 3.6 : (k == .turboprop ? 2.0 : (k == .regionalJet ? 2.1 : 2.5))
            let fh: Float = k == .widebody ? 1.2 : (k == .turboprop ? 0.7 : 0.9), fw: Float = k == .widebody ? 0.65 : (k == .turboprop ? 0.35 : 0.45)
            let body = k == .cargoPlane ? steel : white
            m.box(-hl, 0.6, -fw, hl - 0.6, 0.6 + fh, fw, body, faces: .all)
            m.box(hl - 0.6, 0.7, -fw * 0.75, hl, 0.6 + fh * 0.85, fw * 0.75, body, faces: .all)
            m.box(hl - 0.55, 0.6 + fh * 0.6, -fw * 0.65, hl - 0.2, 0.6 + fh * 0.85, fw * 0.65, glass, faces: .all)
            let wingY: Float = k == .turboprop ? 0.6 + fh : 0.85
            m.box(-0.6, wingY, -span, 0.6, wingY + 0.15, span, steel, faces: .all)                  // the wings
            m.box(-hl, 0.6 + fh, -0.08, -hl + 0.7, 1.7 + fh, 0.08, livery, faces: .all)              // the fin
            m.box(-hl, 0.4 + fh, -0.9, -hl + 0.5, 0.5 + fh, 0.9, steel, faces: .all)
            m.box(-hl + 0.2, 0.62, -fw - 0.01, hl - 0.8, 0.75, fw + 0.01, livery, faces: .all)       // the cheat line
            switch k {
            case .turboprop:
                for z in [Float(-1.0), 1.0] { m.box(0.2, wingY - 0.2, z - 0.15, 0.8, wingY + 0.05, z + 0.15, dark, faces: .all); m.box(0.8, wingY - 0.45, z - 0.04, 0.85, wingY + 0.3, z + 0.04, dark, faces: .all) }
            case .regionalJet:
                for z in [Float(-0.55), 0.55] { m.box(-hl + 0.5, 0.6 + fh * 0.6, z - 0.15, -hl + 1.2, 0.6 + fh * 0.95, z + 0.15, dark, faces: .all) }
            case .widebody:
                for z in [Float(-1.2), -2.4, 1.2, 2.4] { m.box(-0.2, 0.5, z - 0.25, 0.7, 0.85, z + 0.25, dark, faces: .all) }
            default:
                for z in [Float(-1.2), 1.2] { m.box(-0.2, 0.55, z - 0.2, 0.6, 0.85, z + 0.2, dark, faces: .all) }
            }
            m.box(hl - 0.8, 0, -0.08, hl - 0.6, 0.6, 0.08, dark, faces: .all); m.box(-0.3, 0, -0.5, 0, 0.6, -0.3, dark, faces: .all); m.box(-0.3, 0, 0.3, 0, 0.6, 0.5, dark, faces: .all)
        case .ferry, .liner, .freighter:
            m.box(-hl, -0.5, -hw, hl - 0.4, 0.6, hw, k == .freighter ? RGBA(60, 70, 90) : white, faces: .all)
            m.box(hl - 0.4, -0.5, -hw + 0.3, hl, 0.6, hw - 0.3, k == .freighter ? RGBA(60, 70, 90) : white, faces: .all)
            m.box(-hl, -0.5, -hw - 0.01, hl - 0.4, -0.2, hw + 0.01, livery, faces: .all)
            switch k {
            case .freighter:
                m.box(-hl + 0.2, 0.6, -hw + 0.1, -hl + 1.4, 2.2, hw - 0.1, white, faces: .all)
                for i in 0..<4 { let x = -hl + 1.7 + Float(i) * 0.95; m.box(x, 0.6, -hw + 0.15, x + 0.85, 1.4, hw - 0.15, [livery, steel, RGBA(70, 120, 90), RGBA(200, 150, 60)][i], faces: .all) }
            default:
                m.box(-hl + 0.3, 0.6, -hw + 0.15, hl - 0.8, 1.6, hw - 0.15, white, faces: .all)
                m.box(-hl + 0.4, 1.1, -hw + 0.14, hl - 0.9, 1.4, hw - 0.14, glass, faces: .all)
                if k == .liner { m.box(-hl + 0.6, 1.6, -hw + 0.3, hl - 1.4, 2.4, hw - 0.3, white, faces: .all) }
                m.box(-0.2, 1.6, -0.25, 0.3, 2.5, 0.25, livery, faces: .all)              // funnel
            }
        }
        return m
    }

    /// The moon: a pale disc (a flat-faced block), seen from far below.
    public static func moon() -> Mesh3D {
        var m = Mesh3D()
        m.box(-6, -6, -1, 6, 6, 1, RGBA(240, 238, 220), faces: .all)
        m.box(-3, 1, -1.2, 0, 4, -1, RGBA(205, 205, 195), faces: .all)          // a few darker seas
        m.box(1, -3, -1.2, 4, 0, -1, RGBA(215, 213, 200), faces: .all)
        return m
    }

    /// Stars: small bright points over a dome round the origin, above the horizon, always the same for a seed.
    public static func starDome(seed: Int, count: Int = 260, radius: Float = 300) -> Mesh3D {
        var m = Mesh3D()
        var r = RNG(seed: seed)
        for _ in 0..<count {
            let az = Float(r.unit()) * 2 * .pi, el = Float(0.08 + r.unit() * 1.4)
            let x = cos(az) * cos(el) * radius, y = sin(el) * radius, z = sin(az) * cos(el) * radius
            let s: Float = (r.unit() < 0.15 ? 1.1 : 0.6) * radius / 300
            let tint = UInt8(200 + r.int(0, 55))
            m.box(x - s, y - s, z - s, x + s, y + s, z + s, RGBA(tint, tint, 255), faces: .all)
        }
        return m
    }

    /// A bridge or viaduct deck, one tile long (along x) and wide, with railings; set at the deck's height.
    public static func deck(rail: Bool) -> Mesh3D {
        var m = Mesh3D()
        let top = RGBA(120, 122, 128), side = RGBA(90, 92, 98)
        m.box(0, -0.35, 0, 1, 0, 1, rail ? RGBA(110, 100, 90) : top, faces: .all)
        m.box(0, 0, 0, 1, 0.45, 0.06, side, faces: .all); m.box(0, 0, 0.94, 1, 0.45, 1, side, faces: .all)
        if rail { for z in [Float(0.3), 0.66] { m.box(0, 0, z, 1, 0.08, z + 0.05, RGBA(200, 205, 215), faces: .all) } }
        return m
    }

    /// A bridge pier from the water or ground up to under the deck (one tile tall, scaled).
    public static func pier() -> Mesh3D {
        var m = Mesh3D()
        m.box(0.3, 0, 0.3, 0.7, 1, 0.7, RGBA(120, 116, 110), faces: .all)
        return m
    }

    /// One guide rail of an elevator shaft, one tile tall from y = 0 (scaled to the shaft's height).
    public static func liftRail() -> Mesh3D {
        var m = Mesh3D()
        m.box(0, 0, 0, 0.14, 1, 0.14, RGBA(90, 96, 110), faces: .all)
        return m
    }

    public static func plate(color: RGBA, w: Float = 1, d: Float = 1, h: Float = 0.08) -> Mesh3D {
        var m = Mesh3D()
        m.box(0, 0, 0, w, h, d, color, faces: .all)
        return m
    }
}
