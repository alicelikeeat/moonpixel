import Foundation

// Landmarks are lived in, built onto, and can be taken down in part (v3.0).
//
// * Homes: a landmark's rooms have beds (the palace city's courtyard houses, a keeper's lodge at each of the
//   others, and every house built inside it later). People of its town who have no home move into a free bed:
//   they live there (sleep in that bed) and stay townsfolk; their home is the landmark (`home` -3).
// * Building inside: the landmark's town keeps building on the open ground within it, every third day while it
//   has the wood and stone: houses (four beds, a table, a kitchen) most of all, and a workshop, a tavern and a
//   market stall now and then; up to sixteen in the palace city, a few in the others.
// * Taking part of it down: a part (a hall, a gate tower, a courtyard house, a stretch of gallery...) or a
//   building put up inside it is taken down whole: its walls and things are cleared, its 3D model goes, the
//   beds in it with it (those who slept there are homeless again), and a share of its stone comes back.
//   The landmark itself stands as long as anything of it does.

public struct MonumentAnnex: Codable, Equatable {
    public var kind: String              // house, workshop, tavern, market
    public var x: Int, y: Int, w: Int, d: Int
}

extension Monument {
    /// A part's own name (its key and corner: pieces built alike share a key).
    public static func partID(_ p: MonumentPiece) -> String { "\(p.key)@\(Int(p.x)),\(Int(p.z))" }
}

extension Figure3D {
    /// The parts of a monument still standing (those taken down are left out).
    public static func livePieces(for m: Monument) -> [MonumentPiece] {
        let gone = Set(m.removed ?? [])
        return monumentPieces(for: m).filter { !gone.contains(Monument.partID($0)) }
    }

    /// The flat pictures of a monument, without those of the parts taken down.
    public static func liveSprites(for m: Monument) -> [MonumentSprite] {
        let gone = monumentPieces(for: m).filter { (m.removed ?? []).contains(Monument.partID($0)) }
        guard !gone.isEmpty else { return MonumentArt.sprites(for: m) }
        return MonumentArt.sprites(for: m).filter { sp in
            let cx = Float(sp.x) + Float(sp.w) / 2, cz = Float(sp.z)
            return !gone.contains { cx >= $0.x && cx < $0.x + $0.w && cz >= $0.z - 1 && cz <= $0.z + $0.d + 1 }
        }
    }
}

extension Society {
    static let annexNames: [String: (String, String)] = ["house": ("house", "民居"), "workshop": ("workshop", "作坊"), "tavern": ("tavern", "酒馆"), "market": ("market", "集市")]
    /// How many buildings a landmark's town puts up inside it.
    static func annexCap(_ k: MonumentKind) -> Int { k == .palace ? 16 : (k == .cemetery ? 0 : 4) }
    /// The keep-out round a one-piece landmark's structure (tiles from its middle).
    static func keepOut(_ k: MonumentKind) -> Int { [.liberty: 16, .clock: 10, .pagoda: 12, .fusion: 30][k] ?? 0 }

    // MARK: beds and residents

    /// The beds standing in a landmark's grounds now (read once from its tiles, then kept).
    func landmarkBeds(_ i: Int) -> [TilePos] {
        guard var list = realm.monuments, list.indices.contains(i) else { return [] }
        if let b = list[i].beds { return b.map { TilePos($0[0], $0[1]) } }
        let m = list[i], bed = content.tid("bed")
        var out: [[Int]] = []
        for y in m.y..<(m.y + m.d) { for x in m.x..<(m.x + m.w) where world.tile(2, x, y) == bed { out.append([x, y]) } }
        list[i].beds = out
        realm.monuments = list
        return out.map { TilePos($0[0], $0[1]) }
    }

    /// Homeless people of a landmark's town move into its free beds (once a day).
    func landmarkHomesDaily() {
        guard var list = realm.monuments, !list.isEmpty else { return }
        for i in list.indices {
            let beds = landmarkBeds(i)
            list = realm.monuments!
            guard let s = settlements[list[i].town], !s.abandoned else { continue }
            // those who left (moved, died, went to war) give their bed back
            var res = (list[i].residents ?? []).filter { id in agents[id].map { $0.alive && $0.sid == s.id && $0.home == -3 } ?? false }
            let taken = Set(res.compactMap { agents[$0]?.bedAt.map { TilePos($0[0], $0[1]) } })
            var free = beds.filter { !taken.contains($0) && world.tile(2, $0.x, $0.y) == content.tid("bed") }
            for id in s.members.sorted() where !free.isEmpty {
                guard let a = agents[id], a.home == -1, a.legion == nil, a.captiveOf == nil, a.stage(world.time) != "child" || a.mother == 0 else { continue }
                let b = free.removeFirst()
                a.home = -3; a.bedAt = [b.x, b.y]
                res.append(a.id)
                a.think(world.time, "t_home")
                // the family moves in with them (children and a spouse without a home)
                for k in [a.partner] + a.children {
                    guard let r = agents[k], r.sid == s.id, r.home == -1, !free.isEmpty else { continue }
                    let rb = free.removeFirst()
                    r.home = -3; r.bedAt = [rb.x, rb.y]; res.append(r.id)
                }
            }
            list[i].residents = res
            realm.monuments = list
        }
    }

    /// The people living in a landmark, and its beds.
    public func landmarkLiving(_ m: Monument) -> (residents: Int, beds: Int) {
        ((m.residents ?? []).filter { agents[$0]?.home == -3 }.count, m.beds?.count ?? 0)
    }

    // MARK: building inside

    /// Every third day a landmark's town puts up a building on the open ground within it.
    func landmarkBuildDaily() {
        guard var list = realm.monuments, !list.isEmpty else { return }
        let day = Int(world.time / MP.daySeconds)
        for i in list.indices where (day + list[i].id) % 3 == 0 {
            let m = list[i]
            guard (m.annexes ?? []).count < Society.annexCap(m.kind), let s = settlements[m.town], !s.abandoned, s.wood >= 30, s.stone >= 10 else { continue }
            let n = (m.annexes ?? []).count
            let kind = n % 5 == 3 ? ["workshop", "tavern", "market"][(n / 5) % 3] : "house"
            guard let spot = annexSite(m, w: 8, d: 6) else { continue }
            buildAnnex(kind, at: spot, in: &list[i])
            s.wood -= 20; s.stone -= 10
            realm.monuments = list
            emit("built", [s.name(zh: zh), m.title(zh: zh) + (zh ? "里的" : ": a ") + (zh ? Society.annexNames[kind]!.1 : Society.annexNames[kind]!.0)], TilePos(spot.x + 4, spot.y + 3).center)
        }
    }

    /// Open ground inside a landmark for a building: dry, level ground with nothing standing on it, clear of
    /// the landmark's solid parts and of what was built there before.
    func annexSite(_ m: Monument, w: Int, d: Int) -> TilePos? {
        let solid = Figure3D.livePieces(for: m).filter { p in !["pgal", "pwall", "pgarden"].contains(where: { p.key.hasPrefix($0) }) && (p.w < Float(m.w) || p.d < Float(m.d)) }
        let ko = Society.keepOut(m.kind), cx = m.w / 2, cy = m.d / 2
        let water = content.water
        for gy in stride(from: 4, through: m.d - d - 4, by: 7) { for gx in stride(from: 4, through: m.w - w - 4, by: 9) {
            let x0 = m.x + gx, y0 = m.y + gy
            if ko > 0 && abs(gx + w / 2 - cx) < ko + w / 2 && abs(gy + d / 2 - cy) < ko + d / 2 { continue }
            if solid.contains(where: { Float(gx + w) > $0.x && Float(gx) < $0.x + $0.w && Float(gy + d) > $0.z && Float(gy) < $0.z + $0.d }) { continue }
            if (m.annexes ?? []).contains(where: { x0 < $0.x + $0.w + 2 && $0.x < x0 + w + 2 && y0 < $0.y + $0.d + 2 && $0.y < y0 + d + 2 }) { continue }
            var ok = true
            check: for y in (y0 - 1)...(y0 + d) { for x in (x0 - 1)...(x0 + w) {
                let o = world.tile(2, x, y)
                if water[Int(world.tile(0, x, y))] || world.tile(1, x, y) != 0 || (o != 0 && content.tile(o)?.natural != true) { ok = false; break check }
            } }
            if ok { return TilePos(x0, y0) }
        } }
        return nil
    }

    /// A building inside a landmark: brick walls, a wooden floor, a door on the south side, and what its kind
    /// keeps inside (beds for a house).
    func buildAnnex(_ kind: String, at o: TilePos, in m: inout Monument) {
        let T = { (k: String) in self.content.tid(k) }
        let w = 8, d = 6
        for y in 0..<d { for x in 0..<w {
            let t = TilePos(o.x + x, o.y + y)
            world.setTile(0, t.x, t.y, T("wood_floor")); world.setTile(3, t.x, t.y, 0)
            let edge = x == 0 || y == 0 || x == w - 1 || y == d - 1
            world.setTile(2, t.x, t.y, edge ? (y == d - 1 && x == w / 2 ? T("door_wood") : ((x + y) % 3 == 1 && !(x == 0 || x == w - 1) ? T("wall_glass") : T("wall_brick"))) : 0)
        } }
        var beds: [[Int]] = []
        func put(_ x: Int, _ y: Int, _ k: String) { world.setTile(2, o.x + x, o.y + y, T(k)); if k == "bed" { beds.append([o.x + x, o.y + y]) } }
        switch kind {
        case "workshop": put(1, 1, "anvil"); put(3, 1, "workbench"); put(6, 1, "furnace")
        case "tavern": put(1, 1, "barrel"); put(3, 2, "table"); put(4, 2, "chair"); put(6, 1, "kitchen")
        case "market": put(1, 1, "market_stall"); put(3, 1, "market_stall"); put(5, 1, "market_stall"); put(6, 3, "chest")
        default: put(1, 1, "bed"); put(2, 1, "bed"); put(5, 1, "bed"); put(6, 1, "bed"); put(3, 3, "table"); put(1, 3, "kitchen")
        }
        keepClear(TilePos(o.x + w / 2, o.y + d))
        var a = m.annexes ?? []
        a.append(MonumentAnnex(kind: kind, x: o.x, y: o.y, w: w, d: d))
        m.annexes = a
        m.beds = (m.beds ?? []) + beds
    }

    // MARK: taking part of it down

    /// Take down the part of a landmark at a tile: a building put up inside it, or one of its own parts (a hall,
    /// a gate, a courtyard house...). Not a one-piece landmark's structure. Returns what came down, or nil.
    @discardableResult public func demolishLandmarkPart(at t: TilePos) -> String? {
        guard var list = realm.monuments, let i = list.firstIndex(where: { t.x >= $0.x && t.x < $0.x + $0.w && t.y >= $0.y && t.y < $0.y + $0.d }) else { return nil }
        var m = list[i]
        // a building inside it first
        if let k = (m.annexes ?? []).firstIndex(where: { t.x >= $0.x && t.x < $0.x + $0.w && t.y >= $0.y && t.y < $0.y + $0.d }) {
            let a = m.annexes![k]
            clearPart(x: a.x, y: a.y, w: a.w, d: a.d, in: &m)
            m.annexes!.remove(at: k)
            list[i] = m; realm.monuments = list
            return m.title(zh: zh) + (zh ? "里的" : ": the ") + (zh ? Society.annexNames[a.kind]?.1 ?? a.kind : Society.annexNames[a.kind]?.0 ?? a.kind)
        }
        // one of its own parts (the smallest standing part under the tile); never the whole of a one-piece landmark
        let lx = Float(t.x - m.x), lz = Float(t.y - m.y)
        let parts = Figure3D.livePieces(for: m).filter { lx >= $0.x && lx < $0.x + $0.w && lz >= $0.z && lz < $0.z + $0.d && ($0.w < Float(m.w) || $0.d < Float(m.d)) }
        guard let p = parts.min(by: { $0.w * $0.d < $1.w * $1.d }) else { return nil }
        clearPart(x: m.x + Int(p.x), y: m.y + Int(p.z), w: Int(p.w.rounded(.up)), d: Int(p.d.rounded(.up)), in: &m)
        m.removed = (m.removed ?? []) + [Monument.partID(p)]
        list[i] = m; realm.monuments = list
        return m.title(zh: zh) + (zh ? "的" : ": ") + Society.partName(p.key, zh: zh)
    }

    /// Clear a part's walls and things (its floor stays), its beds with it (those who slept there are homeless
    /// again); a share of its stone comes back to the traveller.
    func clearPart(x: Int, y: Int, w: Int, d: Int, in m: inout Monument) {
        var cleared = 0
        for yy in y..<(y + d) { for xx in x..<(x + w) {
            let o = world.tile(2, xx, yy)
            if o != 0, content.tile(o)?.natural != true { world.setTile(2, xx, yy, 0); cleared += 1 }
        } }
        let inside: ([Int]) -> Bool = { $0[0] >= x && $0[0] < x + w && $0[1] >= y && $0[1] < y + d }
        m.beds = (m.beds ?? []).filter { !inside($0) }
        for id in m.residents ?? [] { if let a = agents[id], let b = a.bedAt, inside(b) { a.home = -1; a.bedAt = nil } }
        m.residents = (m.residents ?? []).filter { agents[$0]?.home == -3 }
        carry("stone", min(roomFor("stone"), Double(cleared) * 0.5))
        for cy in OpenWorld.floorDiv(y, 32)...OpenWorld.floorDiv(y + d, 32) { for cx in OpenWorld.floorDiv(x, 32)...OpenWorld.floorDiv(x + w, 32) { world.bump(cx, cy) } }
    }

    /// A part's name, for the news.
    static func partName(_ key: String, zh: Bool) -> String {
        let names: [(String, String, String)] = [("pouter", "Hall of Supreme Harmony and its terrace", "外朝三大殿及台基"), ("pinner", "inner court halls", "内廷宫殿"),
            ("pcourt", "courtyard house", "四合院"), ("pgal", "galleries", "回廊"), ("pwall", "palace wall", "宫墙"), ("ptower", "corner tower", "角楼"),
            ("pmeridian", "Meridian Gate", "午门"), ("pnorthgate", "north gate", "北门"), ("psidegate", "side gate", "侧门"),
            ("pharmonygate", "Gate of Harmony", "太和门"), ("ppuritygate", "Gate of Heavenly Purity", "乾清门"), ("pgarden", "imperial garden", "御花园")]
        if let n = names.first(where: { key.hasPrefix($0.0) }) { return zh ? n.2 : n.1 }
        return zh ? "一部分" : "a part"
    }
}
