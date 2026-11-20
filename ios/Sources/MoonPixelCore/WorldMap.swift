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
    public enum Kind: String { case player, town, capital, city, district, airport, maze, army, ufo, volcano, building, monument, underCity
        case nation, port, occupied, pass, oil, gold }
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
    /// The Nations view (地形｜国土): land in its holder's colour, borders, occupied land hatched.
    public var political = false
    /// Which world the map shows: the surface, the underground (the underground nations' underlands) or the
    /// sea floor (the sea-floor nations' underlands, under the oceans).
    public enum Layer: String, CaseIterable { case surface, underground, seaFloor, sky }
    public var layer = Layer.surface
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

    /// A town's buildings by name (English, Chinese).
    public static let townBuildingNames: [String: (String, String)] = [
        "house": ("House", "房屋"), "farm": ("Farm", "农田"), "well": ("Well", "水井"), "lights": ("Lantern square", "灯火广场"),
        "granary": ("Granary", "粮仓"), "market": ("Market", "集市"), "warehouse": ("Warehouse", "仓库"), "mine": ("Mine", "矿井"),
        "workshop": ("Workshop", "工坊"), "tavern": ("Tavern", "酒馆"), "school": ("School", "学堂"), "factory": ("Factory", "工厂"),
        "lab": ("Laboratory", "研究所"), "ai_center": ("AI centre", "人工智能中心"), "windmill": ("Windmill", "风车磨坊"),
        "palace": ("Palace", "王宫"), "church": ("Church", "教堂"), "fortress": ("Fortress", "要塞"), "barracks": ("Barracks", "兵营"), "watchtower": ("Watchtower", "瞭望塔"),
    ]

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
        if layer != .surface { return renderBelow(s, centre: centre, reach: reach, ppc: want, zh: zh) }
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
        if political { paintNations(s.civ, &img) }
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
        var volcanoes = Set<TilePos>()
        for y in 0..<side { for x in 0..<side where world.known(origin.x + x, origin.y + y) != 0 {
            let cx = origin.x + x, cy = origin.y + y
            if world.gen.isUnderCity(cx, cy) && world.gen.volcano(near: cx * 32 + 16, cy * 32 + 16, radius: 40) == nil && !world.gen.isUfoPort(cx, cy) {
                add(.underCity, zh ? "地下城入口" : "Underground city", "#c08aff", TilePos(cx * 32 + 16, cy * 32 + 22))
            }
            if s.ufoPortOpen(cx, cy) { add(.ufo, zh ? "UFO 机场" : "UFO airport", "#6af0ff", TilePos(cx * 32 + 15, cy * 32 + 13)) }
            if let v = world.gen.volcano(near: cx * 32 + 16, cy * 32 + 16, radius: 23), volcanoes.insert(TilePos(v.x, v.y)).inserted {
                add(.volcano, zh ? "火山" : "Volcano", "#ff5a1a", TilePos(v.x, v.y))
            }
        } }
        for m in s.realm.monuments ?? [] { add(.monument, m.title(zh: zh) + (s.realm.nation(m.nation).map { " · " + $0.name(zh: zh) } ?? ""), "#ffd25a", m.center) }
        // a detailed map (a few pixels a tile) names every building at its door: tap a name to go there
        if ppc >= 64 {
            for d in s.net.districts { for b in d.buildings where b.state == .open {
                add(.building, b.def.name(zh: zh), "#f2e6c8", b.front)
            } }
            for t in s.settlements.values where !t.abandoned { for b in t.buildings where b.done {
                let n = WorldMap.townBuildingNames[b.type].map { zh ? $0.1 : $0.0 } ?? Society.text[b.type].map { zh ? $0.1 : $0.0 } ?? b.type
                add(.building, n, "#e8d8b0", b.door)
            } }
        }
        if political { nationMarkers(s.civ, zh: zh, add: add) }
        for lg in s.realm.legions where lg.state != 0 { add(.army, zh ? "军队" : "Army", s.realm.nation(lg.nation)?.color ?? "#ffffff", lg.pos.tile) }
        add(.player, zh ? "你" : "You", "#7fe6ff", centre)
        return (img, marks)
    }

    // MARK: the Nations view

    /// Land in the colour of the nation holding it (the sea left blue: it is everyone's), a solid line where
    /// the owners by right differ, and land held by someone other than its owner hatched in the owner's colour.
    public func paintNations(_ civ: Civ, _ img: inout Bitmap) {
        let rcs = max(1, civ.cfg.regionTiles / 32)            // chunks a region
        let w = max(1, ppc / 5)
        func owner(_ rx: Int, _ ry: Int) -> Int? { civ.regions[MP.chunkKey(rx, ry)].flatMap { civ.isSea($0) ? nil : $0.legal } }
        for cy in 0..<side { for cx in 0..<side {
            let x = origin.x + cx, y = origin.y + cy
            let rx = OpenWorld.floorDiv(x, rcs), ry = OpenWorld.floorDiv(y, rcs)
            guard let r = civ.regions[MP.chunkKey(rx, ry)], !civ.isSea(r) else { continue }
            let h = civ.holder(r), l = r.legal
            guard let shown = h ?? l else { continue }
            let hc = RGBA(hex: civ.polities[shown]?.color ?? "#cccccc")
            let lc = l.map { RGBA(hex: civ.polities[$0]?.color ?? "#cccccc") } ?? hc
            let contested = l != nil && h != nil && l != h
            for py in 0..<ppc { for px in 0..<ppc {
                let X = cx * ppc + px, Y = cy * ppc + py
                var c = img.get(X, Y).lerp(hc, 0.4)
                if contested && (X + Y) % 6 < 2 { c = lc.darkened(0.15) }
                img.set(X, Y, c)
            } }
            let lx = x - rx * rcs, ly = y - ry * rcs
            // a vassal keeps its own colour inside; its border is drawn in its suzerain's colour
            let line = (l.flatMap { civ.suzerain(of: $0) }.flatMap { civ.polities[$0] }).map { RGBA(hex: $0.color) } ?? lc.darkened(0.5)
            if lx == 0 && owner(rx - 1, ry) != l { img.rect(cx * ppc, cy * ppc, w, ppc, line) }
            if lx == rcs - 1 && owner(rx + 1, ry) != l { img.rect(cx * ppc + ppc - w, cy * ppc, w, ppc, line) }
            if ly == 0 && owner(rx, ry - 1) != l { img.rect(cx * ppc, cy * ppc, ppc, w, line) }
            if ly == rcs - 1 && owner(rx, ry + 1) != l { img.rect(cx * ppc, cy * ppc + ppc - w, ppc, w, line) }
        } }
        // trade routes: a dotted line from region to region, in the seller's colour (gold over the sea, brown by land)
        let rc = Double(civ.cfg.regionTiles), tpp = tilesPerPixel
        func px(_ k: Int64) -> (Double, Double)? {
            civ.regions[k].map { ((Double($0.rx) * rc + rc / 2 - Double(origin.x * 32)) / tpp, (Double($0.ry) * rc + rc / 2 - Double(origin.y * 32)) / tpp) }
        }
        for r in civ.tradeRoutes where r.active {
            let col = r.sea ? RGBA(250, 210, 80) : RGBA(170, 110, 60)
            let dot = max(1, ppc / 6)
            for (a, b) in zip(r.path, r.path.dropFirst()) {
                guard let p0 = px(a), let p1 = px(b) else { continue }
                let n = max(1, Int(max(abs(p1.0 - p0.0), abs(p1.1 - p0.1)) / Double(dot * 3)))
                for i in 0...n {
                    let f = Double(i) / Double(n), x = p0.0 + (p1.0 - p0.0) * f, y = p0.1 + (p1.1 - p0.1) * f
                    if x >= 0, y >= 0, Int(x) < img.w, Int(y) < img.h { img.rect(Int(x), Int(y), dot, dot, col) }
                }
            }
        }
    }

    /// In the Nations view: each nation's name in the middle of its land, its capital, its ports and passes,
    /// and a flag where a city is held by someone other than its owner.
    func nationMarkers(_ civ: Civ, zh: Bool, add: (MapMarker.Kind, String, String, TilePos) -> Void) {
        let rc = civ.cfg.regionTiles
        func mid(_ k: Int64) -> TilePos? { civ.regions[k].map { TilePos($0.rx * rc + rc / 2, $0.ry * rc + rc / 2) } }
        let bodies = civ.waterBodies()
        for id in civ.polities.keys.sorted() {
            guard let p = civ.polities[id], p.status == .active else { continue }
            let land = civ.territory(of: id, legal: true)
            guard !land.isEmpty else { continue }
            let xs = land.compactMap { civ.regions[$0] }
            let cx = xs.map { Double($0.rx) }.reduce(0, +) / Double(xs.count), cy = xs.map { Double($0.ry) }.reduce(0, +) / Double(xs.count)
            add(.nation, p.name(zh: zh), p.color, TilePos(Int((cx + 0.5) * Double(rc)), Int((cy + 0.5) * Double(rc))))
            if let cap = p.capital.flatMap({ civ.cities[$0] }), cap.detail == nil { add(.capital, cap.name(zh: zh), p.color, TilePos(cap.rx * rc + rc / 2, cap.ry * rc + rc / 2)) }
            for k in land where civ.cities.values.contains(where: { $0.regionKey == k && $0.nation == civ.controller(k) }) && civ.portSite(k, bodies: bodies) != nil {
                if let t = mid(k) { add(.port, zh ? "港口" : "Port", p.color, TilePos(t.x, t.y + rc / 4)) }
            }
            for t in civ.traits(of: id, bodies: bodies) where t.kind == .basin {
                for k in t.places { if let m = mid(k) { add(.pass, zh ? "关" : "Pass", civ.polities[civ.controller(k) ?? id]?.color ?? p.color, m) } }
            }
        }
        // oil and gold: where they lie in owned land (the richest first, a handful)
        let rich = civ.regions.values.filter { $0.legal != nil && ($0.oil > 0.3 || $0.gold > 0.3) }
            .sorted { max($0.oil, $0.gold) != max($1.oil, $1.gold) ? max($0.oil, $0.gold) > max($1.oil, $1.gold) : $0.key < $1.key }.prefix(40)
        for r in rich {
            let t = TilePos(r.rx * rc + rc / 3, r.ry * rc + rc * 2 / 3)
            if r.oil > 0.3 { add(.oil, zh ? "油田" : "Oil", "#202020", t) }
            if r.gold > 0.3 { add(.gold, zh ? "金矿" : "Gold", "#f2c230", TilePos(t.x + rc / 4, t.y)) }
        }
        for k in civ.occupied() {
            guard let r = civ.regions[k], r.city != nil, let h = civ.controller(k), let t = mid(k) else { continue }
            add(.occupied, zh ? "占领" : "Occupied", civ.polities[h]?.color ?? "#ffffff", TilePos(t.x + rc / 6, t.y - rc / 6))
        }
    }

    // MARK: the worlds below

    /// The underground or the sea floor: rock (or the sea bed under the oceans) and, where a nation has dug its
    /// underland, open land with its roads, in the nation's colour in the Nations view; each city by name and
    /// each nation's name over its cities.
    func renderBelow(_ s: Society, centre: TilePos, reach: Int, ppc want: Int?, zh: Bool) -> (Bitmap, [MapMarker]) {
        if layer == .sky { return renderSky(s, centre: centre, reach: reach, ppc: want, zh: zh) }
        let gen = s.world.gen
        let civ = s.civ
        let sea = layer == .seaFloor
        let ext = min(120, max(6, reach))
        side = ext * 2 + 1
        ppc = want ?? max(2, min(16, 1600 / side))
        let pc = TilePos(OpenWorld.floorDiv(centre.x, 32), OpenWorld.floorDiv(centre.y, 32))
        origin = TilePos(pc.x - ext, pc.y - ext)
        var img = Bitmap(side * ppc, side * ppc, fill: WorldMap.fog)
        // which chunk belongs to which underland (one pass over each zone's square)
        let zones = s.underlandZones().filter { $0.sea == sea }
        var owner: [Int64: UnderlandZone] = [:]
        for z in zones {
            let r = Int(z.r.rounded(.up))
            for y in (z.cy - r)...(z.cy + r) { for x in (z.cx - r)...(z.cx + r) where z.contains(x, y) && x >= origin.x && y >= origin.y && x < origin.x + side && y < origin.y + side {
                if owner[MP.chunkKey(x, y)] == nil { owner[MP.chunkKey(x, y)] = z }
            } }
        }
        let rock = RGBA(52, 46, 56), rockSea = RGBA(36, 48, 70), seabed = RGBA(26, 58, 100), seabedDeep = RGBA(16, 38, 76), landAbove = RGBA(30, 30, 36)
        let grass = RGBA(110, 160, 86), sand = RGBA(220, 200, 146), road = RGBA(236, 228, 210), glass = RGBA(160, 220, 240)
        for cy in 0..<side { for cx in 0..<side {
            let x = origin.x + cx, y = origin.y + cy
            let e = gen.elevation(x * 32 + 16, y * 32 + 16)
            var base: RGBA
            if sea { base = e < Biome.sea ? (e < Biome.sea - 0.08 ? seabedDeep : seabed) : landAbove }
            else { base = e < Biome.sea ? rockSea : rock }
            if let z = owner[MP.chunkKey(x, y)] {
                var land = z.sea ? sand : grass
                if political { land = land.lerp(RGBA(hex: civ.polities[z.nation]?.color ?? "#cccccc"), 0.5) }
                img.rect(cx * ppc, cy * ppc, ppc, ppc, land)
                // its roads, and a glass rim where it meets the rock
                if ppc >= 4 {
                    let m = ppc / 2
                    img.rect(cx * ppc + m, cy * ppc, max(1, ppc / 8), ppc, road)
                    img.rect(cx * ppc, cy * ppc + m, ppc, max(1, ppc / 8), road)
                }
                let edge = max(1, ppc / 8)
                let rim = z.sea || gen.seaAbove(x * 32 + 16, y * 32 + 16) ? glass : land.darkened(0.35)
                if owner[MP.chunkKey(x - 1, y)] == nil { img.rect(cx * ppc, cy * ppc, edge, ppc, rim) }
                if owner[MP.chunkKey(x + 1, y)] == nil { img.rect(cx * ppc + ppc - edge, cy * ppc, edge, ppc, rim) }
                if owner[MP.chunkKey(x, y - 1)] == nil { img.rect(cx * ppc, cy * ppc, ppc, edge, rim) }
                if owner[MP.chunkKey(x, y + 1)] == nil { img.rect(cx * ppc, cy * ppc + ppc - edge, ppc, edge, rim) }
            } else {
                img.rect(cx * ppc, cy * ppc, ppc, ppc, base)
                if !sea, ppc >= 4, MP.h2(gen.seed &+ 77, x, y) % 5 == 0 { img.rect(cx * ppc + ppc / 3, cy * ppc + ppc / 3, max(1, ppc / 4), max(1, ppc / 4), base.lightened(0.12)) }
            }
        } }
        var marks: [MapMarker] = []
        func add(_ k: MapMarker.Kind, _ n: String, _ c: String, _ t: TilePos) {
            let (fx, fy) = fraction(t)
            guard fx >= 0, fy >= 0, fx <= 1, fy <= 1 else { return }
            marks.append(MapMarker(kind: k, name: n, color: c, tile: t, fx: fx, fy: fy))
        }
        // the cities below, and each nation's name over the middle of its cities
        var byNation: [Int: [TilePos]] = [:]
        for c in civ.cities.values.sorted(by: { $0.id < $1.id }) where (sea ? c.sea == true : c.under == true) {
            guard let (ux, uy) = c.underAt, let p = civ.polities[c.nation], p.status == .active else { continue }
            let t = s.cityGate(c.id)?.tile ?? TilePos(ux * 32 + 16, uy * 32 + 18)
            add(p.capital == c.id ? .capital : .city, c.name(zh: zh), p.color, t)
            byNation[c.nation, default: []].append(t)
        }
        for (n, ts) in byNation.sorted(by: { $0.key < $1.key }) {
            guard let p = civ.polities[n] else { continue }
            let mx = ts.map { $0.x }.reduce(0, +) / ts.count, my = ts.map { $0.y }.reduce(0, +) / ts.count
            add(.nation, p.name(zh: zh), p.color, TilePos(mx, my - 96))
        }
        // where to go down from the surface
        for y in 0..<side { for x in 0..<side where s.world.known(origin.x + x, origin.y + y) != 0 {
            let cx = origin.x + x, cy = origin.y + y
            if !sea && gen.isUnderCity(cx, cy) && gen.volcano(near: cx * 32 + 16, cy * 32 + 16, radius: 40) == nil && !gen.isUfoPort(cx, cy) {
                add(.underCity, zh ? "入口" : "Way down", "#c08aff", TilePos(cx * 32 + 16, cy * 32 + 22))
            }
            if sea && gen.isSeaCity(cx, cy) { add(.underCity, zh ? "珍珠穹顶入口" : "Pearl dome (way down)", "#7fe6ff", TilePos(cx * 32 + 16, cy * 32 + 17)) }
        } }
        add(.player, zh ? "你" : "You", "#7fe6ff", centre)
        return (img, marks)
    }

    /// The sky: the world below as a pale haze, and the sky cities' islands (grass, roads, the runway and the
    /// UFO pad), each by name.
    func renderSky(_ s: Society, centre: TilePos, reach: Int, ppc want: Int?, zh: Bool) -> (Bitmap, [MapMarker]) {
        let gen = s.world.gen
        let ext = min(120, max(6, reach))
        side = ext * 2 + 1
        ppc = want ?? max(2, min(16, 1600 / side))
        let pc = TilePos(OpenWorld.floorDiv(centre.x, 32), OpenWorld.floorDiv(centre.y, 32))
        origin = TilePos(pc.x - ext, pc.y - ext)
        var img = Bitmap(side * ppc, side * ppc, fill: RGBA(150, 190, 230))
        let haze = RGBA(170, 205, 236), grass = RGBA(120, 186, 96), road = RGBA(240, 236, 224), runway = RGBA(70, 72, 80), pad = RGBA(120, 230, 255), fence = RGBA(140, 110, 80)
        for cy in 0..<side { for cx in 0..<side {
            let x = origin.x + cx, y = origin.y + cy
            let e = gen.elevation(x * 32 + 16, y * 32 + 16)
            // the ground far below, faded into the sky's blue
            let below = e < Biome.sea ? WorldMap.sea : RGBA(110, 150, 100)
            img.rect(cx * ppc, cy * ppc, ppc, ppc, below.lerp(haze, 0.72))
            guard let c = gen.skyIsland(x, y) else { continue }
            img.rect(cx * ppc, cy * ppc, ppc, ppc, grass)
            if x == c.0 + 1 && y == c.1 {
                img.rect(cx * ppc, cy * ppc + ppc * 6 / 32, ppc, max(1, ppc * 4 / 32), runway)
                img.rect(cx * ppc + ppc * 19 / 32, cy * ppc + ppc * 20 / 32, max(1, ppc * 8 / 32), max(1, ppc * 6 / 32), pad)
            } else if ppc >= 4 {
                img.rect(cx * ppc + ppc / 2, cy * ppc, max(1, ppc / 8), ppc, road)
                img.rect(cx * ppc, cy * ppc + ppc / 2, ppc, max(1, ppc / 8), road)
            }
            let e2 = max(1, ppc / 10)
            if gen.skyIsland(x - 1, y).map({ $0 != c }) ?? true { img.rect(cx * ppc, cy * ppc, e2, ppc, fence) }
            if gen.skyIsland(x + 1, y).map({ $0 != c }) ?? true { img.rect(cx * ppc + ppc - e2, cy * ppc, e2, ppc, fence) }
            if gen.skyIsland(x, y - 1).map({ $0 != c }) ?? true { img.rect(cx * ppc, cy * ppc, ppc, e2, fence) }
            if gen.skyIsland(x, y + 1).map({ $0 != c }) ?? true { img.rect(cx * ppc, cy * ppc + ppc - e2, ppc, e2, fence) }
        } }
        var marks: [MapMarker] = []
        func add(_ k: MapMarker.Kind, _ n: String, _ col: String, _ t: TilePos) {
            let (fx, fy) = fraction(t)
            guard fx >= 0, fy >= 0, fx <= 1, fy <= 1 else { return }
            marks.append(MapMarker(kind: k, name: n, color: col, tile: t, fx: fx, fy: fy))
        }
        for c in s.skyCities(near: centre, within: ext + 3, zh: zh) {
            add(.city, c.name, "#fff4c0", Society.skyArrival(c.cx, c.cy, by: .sky))
            add(.airport, zh ? "空港" : "Airport", "#9fd3ff", Society.skyArrival(c.cx, c.cy, by: .airport))
            add(.ufo, zh ? "UFO 停机坪" : "UFO pad", "#6af0ff", Society.skyArrival(c.cx, c.cy, by: .ufo))
        }
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
        if let v = gen.volcano(near: t.x, t.y, radius: 26) {
            let d = Int(Double((v.x - t.x) * (v.x - t.x) + (v.y - t.y) * (v.y - t.y)).squareRoot())
            return d < 4 ? (zh ? "火山口（熔岩）" : "Volcano crater (lava)") : (zh ? "火山坡" : "Volcano slope")
        }
        if let m = (s.realm.monuments ?? []).first(where: { t.x >= $0.x && t.x < $0.x + $0.w && t.y >= $0.y && t.y < $0.y + $0.d }) { return m.grave.map { $0.lines(zh: zh).dropFirst().prefix(3).joined(separator: " · ") }.map { m.title(zh: zh) + "：" + $0 } ?? m.title(zh: zh) }
        let ccx = OpenWorld.floorDiv(t.x, 32), ccy = OpenWorld.floorDiv(t.y, 32)
        if gen.isUnderCity(ccx, ccy) && gen.volcano(near: ccx * 32 + 16, ccy * 32 + 16, radius: 40) == nil && !gen.isUfoPort(ccx, ccy) {
            let dx = t.x - (ccx * 32 + 16), dy = t.y - (ccy * 32 + 16)
            if dx * dx + dy * dy <= 121 { return zh ? "地下城入口（门楼里有楼梯下去）" : "Underground city entrance (stairs down in the gatehouse)" }
        }
        if s.ufoPortOpen(OpenWorld.floorDiv(t.x, 32), OpenWorld.floorDiv(t.y, 32)) { return zh ? "UFO 机场" : "UFO airport" }
        if e > Biome.mountainLevel + 0.12 { return zh ? "高山" : "High mountains" }
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
