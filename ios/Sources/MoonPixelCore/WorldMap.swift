import Foundation

// The world map: a painted picture of what has been explored, at several pixels per chunk, and the places on
// it as markers with their exact tiles (the app draws their names over the picture).
//
// Each chunk is painted once and kept: from its real tiles when it is in memory (roads, fields, buildings and
// trees as they are), from the generator otherwise (land and water by elevation, rivers, forest by climate,
// mountains with snow), with hill shading from the elevation, coasts outlined, and fog where nobody has been.
// Ways (streets, railways, runways) and the footprints of towns and districts are drawn over it, exactly where
// they are. A pixel of the picture is a known square of tiles, so a tap on it names one tile.

public struct MapMarker: Equatable {
    public enum Kind: String { case player, town, capital, city, district, airport, maze, army }
    public var kind: Kind
    public var name: String
    public var color: String               // hex
    public var tile: TilePos
    public var fx: Double, fy: Double      // where on the picture (0...1)
}

public final class WorldMap {
    public private(set) var origin = TilePos(0, 0)        // the north-west chunk shown
    public private(set) var side = 0                      // chunks across (and down)
    public private(set) var ppc = 8                       // pixels per chunk
    private var tiles: [String: Bitmap] = [:]             // painted chunks, by chunk, scale and what they were made from
    public init() {}

    /// Tiles per pixel of the picture.
    public var tilesPerPixel: Double { 32 / Double(ppc) }

    /// The tile under a point of the picture (fractions 0...1 across and down): exact to the pixel's square.
    public func tile(fx: Double, fy: Double) -> TilePos {
        let x = Double(origin.x * 32) + fx * Double(side * 32), y = Double(origin.y * 32) + fy * Double(side * 32)
        return TilePos(Int(x.rounded(.down)), Int(y.rounded(.down)))
    }

    /// Where a tile is on the picture (fractions), the middle of the tile.
    public func fraction(_ t: TilePos) -> (Double, Double) {
        ((Double(t.x - origin.x * 32) + 0.5) / Double(side * 32), (Double(t.y - origin.y * 32) + 0.5) / Double(side * 32))
    }

    // MARK: colours

    static let deep = RGBA(38, 86, 150), sea = RGBA(64, 128, 196), shallow = RGBA(110, 176, 222), coast = RGBA(28, 58, 104)
    static let fog = RGBA(22, 24, 34)

    /// A tile's colour on the map: its ground, then what stands on it.
    static func colour(ground g: UInt8, way w: UInt8, thing o: UInt8) -> RGBA {
        let c = Content.shared
        if o != 0, let t = c.tile(o) {
            if t.built { return t.artKind == "wall" || t.artKind == "door" ? RGBA(hex: t.c1).darkened(0.35) : RGBA(hex: t.c1).darkened(0.15) }
            if ["tree", "pine", "leaves"].contains(t.artKind) { return RGBA(hex: t.c1).darkened(0.25) }
        }
        if w != 0, let t = c.tile(w), !c.bridge[Int(w)] || true { return RGBA(hex: t.c1).lightened(0.05) }
        guard let t = c.tile(g) else { return fog }
        if c.water[Int(g)] { return t.key == "deep_water" ? deep : (t.key == "shallow_water" ? shallow : sea) }
        return RGBA(hex: t.c1)
    }

    /// One chunk painted at `ppc` pixels a side.
    func paint(_ world: OpenWorld, _ cx: Int, _ cy: Int) -> Bitmap {
        var b = Bitmap(ppc, ppc, fill: WorldMap.fog)
        let known = world.known(cx, cy)
        guard known != 0 || world.loaded(cx, cy) else {
            // fog with a faint diagonal hatch, so the edge of the explored world reads clearly
            for y in 0..<ppc { for x in 0..<ppc where (x + y + cx * ppc + cy * ppc) % 4 == 0 { b.set(x, y, RGBA(30, 33, 46)) } }
            return b
        }
        let step = 32 / ppc
        let gen = world.gen
        let real = world.loaded(cx, cy) ? world.chunk(cx, cy) : nil
        let biomes = Content.shared.biomes
        for py in 0..<ppc { for px in 0..<ppc {
            let tx = cx * 32 + px * step + step / 2, ty = cy * 32 + py * step + step / 2
            var col: RGBA
            let e = gen.elevation(tx, ty)
            if e < Biome.sea {
                col = e < Biome.sea - 0.08 ? WorldMap.deep : (e < Biome.sea - 0.025 ? WorldMap.sea : WorldMap.shallow)
            } else if gen.isRiver(tx, ty, e) {
                col = WorldMap.sea
            } else {
                let bi = gen.biome(tx, ty)
                col = RGBA(hex: biomes[min(biomes.count - 1, max(0, bi))].color)
                if e > Biome.mountainLevel { col = e > Biome.mountainLevel + 0.08 ? RGBA(240, 242, 248) : RGBA(150, 132, 112) }
            }
            // what people made, where the chunk is known tile by tile: fields, roads, buildings
            if let ch = real {
                let i = (py * step + step / 2) * 32 + px * step + step / 2
                let c = Content.shared
                let g = ch.layers[0][i], w = ch.layers[1][i], o = ch.layers[2][i]
                if o != 0, let t = c.tile(o), t.built { col = RGBA(hex: t.c1).darkened(0.25) }
                else if w != 0, let t = c.tile(w), !c.water[Int(w)] { col = RGBA(hex: t.c1).lightened(0.1) }
                else if let t = c.tile(g), t.built || t.key == "farmland" { col = RGBA(hex: t.c1) }
            }
            // hill shading: lit from the north-west
            if e >= Biome.sea {
                let d = gen.elevation(tx - 2 * step, ty - 2 * step) - gen.elevation(tx + 2 * step, ty + 2 * step)
                let k = max(-0.14, min(0.14, d * 3.2))
                col = k > 0 ? col.lightened(k) : col.darkened(-k)
            }
            b.set(px, py, col)
        } }
        // coasts: a dark line where water meets land
        for py in 0..<ppc { for px in 0..<ppc {
            let tx = cx * 32 + px * step + step / 2, ty = cy * 32 + py * step + step / 2
            let water = gen.elevation(tx, ty) < Biome.sea
            guard water else { continue }
            let landNear = [(step, 0), (-step, 0), (0, step), (0, -step)].contains { gen.elevation(tx + $0.0, ty + $0.1) >= Biome.sea }
            if landNear { b.set(px, py, WorldMap.coast) }
        } }
        return b
    }

    /// Paint the map round `centre` (a tile): every explored chunk within `reach` chunks (at most 200), with
    /// `ppc` pixels a chunk (chosen to keep the picture near 1600 pixels when not given). Returns the picture
    /// and the markers on it.
    public func render(_ s: Society, centre: TilePos, reach: Int, ppc want: Int? = nil, zh: Bool) -> (Bitmap, [MapMarker]) {
        let world = s.world
        let ext = min(200, max(6, reach))
        side = ext * 2 + 1
        ppc = want ?? max(2, min(16, 1600 / side))
        let pc = TilePos(OpenWorld.floorDiv(centre.x, 32), OpenWorld.floorDiv(centre.y, 32))
        origin = TilePos(pc.x - ext, pc.y - ext)
        var img = Bitmap(side * ppc, side * ppc, fill: WorldMap.fog)
        for cy in 0..<side { for cx in 0..<side {
            let x = origin.x + cx, y = origin.y + cy
            let key = "\(x),\(y),\(ppc),\(world.known(x, y)),\(world.loaded(x, y) ? world.revision(x, y) : -1)"
            let b = tiles[key] ?? { let p = paint(world, x, y); tiles[key] = p; return p }()
            img.blit(b, sx: 0, sy: 0, sw: ppc, sh: ppc, dx: cx * ppc, dy: cy * ppc, blend: false)
        } }
        if tiles.count > 40000 { tiles = [:] }
        let tpp = 32.0 / Double(ppc)
        func px(_ t: TilePos) -> (Int, Int) { (Int((Double(t.x - origin.x * 32) / tpp).rounded(.down)), Int((Double(t.y - origin.y * 32) / tpp).rounded(.down))) }
        // towns and districts: their buildings in their roofs' colours, the town's ground lightly tinted
        for t in s.settlements.values where !t.abandoned {
            let col = s.realm.nation(t.nation ?? 0).map { RGBA(hex: $0.color) } ?? RGBA(230, 200, 90)
            for b in t.buildings where b.done {
                let (x0, y0) = px(TilePos(b.x, b.y)), (x1, y1) = px(TilePos(b.x + b.w, b.y + b.h))
                img.rect(x0, y0, max(1, x1 - x0), max(1, y1 - y0), col.darkened(0.2))
            }
        }
        for d in s.net.districts {
            for b in d.buildings where b.state == .open {
                let (x0, y0) = px(TilePos(b.x, b.y)), (x1, y1) = px(TilePos(b.x + b.w, b.y + b.d))
                img.rect(x0, y0, max(1, x1 - x0), max(1, y1 - y0), RGBA(196, 200, 214))
            }
        }
        // ways, exactly where they run
        if let tr = s.realm.transportBox {
            for site in tr.sites where site.finished != nil {
                for c in site.cells where c.bridge != -1 {
                    let (x, y) = px(c.t)
                    let col: RGBA
                    switch c.kind.mode {
                    case .rail: col = RGBA(70, 60, 64)
                    case .air: col = RGBA(110, 112, 120)
                    default: col = c.kind == .highway ? RGBA(250, 200, 80) : RGBA(250, 246, 236)
                    }
                    img.rect(x, y, max(1, Int(1 / tpp)), max(1, Int(1 / tpp)), col)
                }
            }
        }
        // markers
        var marks: [MapMarker] = []
        func add(_ k: MapMarker.Kind, _ n: String, _ c: String, _ t: TilePos) {
            let (fx, fy) = fraction(t)
            guard fx >= 0, fy >= 0, fx <= 1, fy <= 1 else { return }
            marks.append(MapMarker(kind: k, name: n, color: c, tile: t, fx: fx, fy: fy))
        }
        let capitals = Set(s.realm.nations.compactMap { $0.capital })
        for t in s.settlements.values.sorted(by: { $0.id < $1.id }) where !t.abandoned {
            let col = s.realm.nation(t.nation ?? 0)?.color ?? "#e6c85a"
            add(capitals.contains(t.id) ? .capital : .town, t.name(zh: zh), col, t.center)
        }
        let civ = s.civ
        let rc = civ.cfg.regionTiles
        for c in civ.cities.values.sorted(by: { $0.id < $1.id }) where c.detail == nil {
            add(.city, c.name(zh: zh), civ.polities[c.nation]?.color ?? "#cccccc", TilePos(c.rx * rc + rc / 2, c.ry * rc + rc / 2))
        }
        for d in s.net.districts { add(.district, d.name, "#dfe6f2", d.center) }
        for st in s.net.stops where st.kind == .airport && st.name.contains(zh ? "机场" : "Airport") && !st.name.contains(zh ? "货运" : "Cargo") { add(.airport, st.name, "#9fd3ff", st.tile) }
        for y in 0..<side { for x in 0..<side where world.known(origin.x + x, origin.y + y) != 0 && world.gen.isMaze(origin.x + x, origin.y + y) {
            add(.maze, zh ? "迷宫" : "Maze", "#c86eff", TilePos((origin.x + x) * 32 + 15, (origin.y + y) * 32 + 33))
        } }
        for lg in s.realm.legions where lg.state != 0 { add(.army, zh ? "军队" : "Army", s.realm.nation(lg.nation)?.color ?? "#ffffff", lg.pos.tile) }
        add(.player, zh ? "你" : "You", "#7fe6ff", centre)
        return (img, marks)
    }

    /// What is at a tile, in a few words, for the map's pick card.
    public static func describe(_ s: Society, _ t: TilePos, zh: Bool) -> String {
        if let town = s.settlements.values.first(where: { !$0.abandoned && $0.inArea(t) }) { return (zh ? "城镇 " : "Town ") + town.name(zh: zh) }
        if let d = s.net.districts.first(where: { $0.center.distance2(t) < $0.radius * $0.radius }) { return (zh ? "城区 " : "District ") + d.name }
        let gen = s.world.gen
        let e = gen.elevation(t.x, t.y)
        if e < Biome.sea { return zh ? "水面（会落在最近的岸边）" : "Water (you land on the nearest shore)" }
        if gen.isRiver(t.x, t.y, e) { return zh ? "河边" : "Riverside" }
        if e > Biome.mountainLevel { return zh ? "山地" : "Mountains" }
        let b = Content.shared.biomes[min(Content.shared.biomes.count - 1, max(0, gen.biome(t.x, t.y)))]
        return zh ? b.nameZh : b.nameEn
    }
}

extension Society {
    /// Where the traveller lands for a chosen tile: the tile itself if free, else the nearest free ground (a
    /// maze is entered by its south gate). Returns nil where there is no ground within 40 tiles.
    public func teleportSpot(for t: TilePos) -> (spot: TilePos, off: Int)? {
        let maze = world.gen.isMaze(OpenWorld.floorDiv(t.x, 32), OpenWorld.floorDiv(t.y, 32))
        let goal = maze ? TilePos(OpenWorld.floorDiv(t.x, 32) * 32 + 15, OpenWorld.floorDiv(t.y, 32) * 32 + 33) : t
        for r in [2, 6, 14, 40] {
            let f = world.findFree(near: goal, maxR: r)
            if !world.blocked(f.x, f.y) { return (f, Int(Double(f.distance2(goal)).squareRoot().rounded())) }
        }
        return nil
    }
}
