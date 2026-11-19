import Foundation

// When the last person who held to a nation is gone, the nation passes into history, and a great national
// cemetery is laid out where its seat last stood: a walled ground 96 m by 80 m with an open gate, an avenue,
// rows of graves (one for every few of its dead), a plaza with an obelisk in the nation's colour, a memorial
// wall, and a hall of records with its books. Its records are kept there: when it was first seen and when it
// passed away, its greatest number of people, towns and soldiers, those born to it and those who died, its
// wars, and how far it knew.

public struct NationRecord: Codable, Equatable {
    public static let w = 48, d = 40
    public var nation = 0
    public var nameEn = "", nameZh = "", color = "#ffffff"
    public var founded = 0.0, ended = 0.0
    public var peakPop = 0, peakTowns = 0, peakSoldiers = 0
    public var born = 0, died = 0, wars = 0, techCount = 0, landmarks = 0
    public init() {}
    public func name(zh: Bool) -> String { zh ? nameZh : nameEn }

    /// Years it stood (a game year is MP.year).
    public var years: Double { max(0, ended - founded) / MP.year }

    /// The record as lines, as it is cut into the memorial wall.
    public func lines(zh: Bool) -> [String] {
        zh ? [
            "\(nameZh) 国家公墓",
            String(format: "存续 %.1f 年（第 %.1f 年 — 第 %.1f 年）", years, founded / MP.year, ended / MP.year),
            "人口最多 \(peakPop) 人 · 城镇最多 \(peakTowns) 座 · 士兵最多 \(peakSoldiers) 人",
            "出生 \(born) 人 · 去世 \(died) 人 · 经历战争 \(wars) 场",
            "科技 \(techCount) 项 · 地标 \(landmarks) 座",
            "最后一位认同它的人离世后，它成为历史。",
        ] : [
            "National Cemetery of \(nameEn)",
            String(format: "Stood %.1f years (year %.1f to year %.1f)", years, founded / MP.year, ended / MP.year),
            "At most \(peakPop) people · \(peakTowns) towns · \(peakSoldiers) soldiers",
            "Born \(born) · died \(died) · wars \(wars)",
            "Knew \(techCount) arts · raised \(landmarks) landmarks",
            "It passed into history when the last who held to it was gone.",
        ]
    }

    /// How many graves the ground shows: one for every few of its dead, as many as the rows hold.
    public var graves: Int { min(NationRecord.graveSlots, max(12, died / 3)) }
    static let graveSlots = 18 * 7
}

extension Society {
    /// Once a day: a nation with no land and nobody left who holds to it passes into history, and its grave is laid out.
    func nationsPassDay() {
        guard realm.era != 2 else { return }
        for k in realm.nations.indices {
            let n = realm.nations[k]
            guard (n.status ?? 0) != 2, n.regional != true, n.exileSince != nil, n.towns == 0,
                  !agents.values.contains(where: { $0.nation == n.id }) else { continue }
            realm.nations[k].status = 2
            for r in realm.relations.indices where realm.relations[r].a == n.id || realm.relations[r].b == n.id { realm.relations[r].pact = false }
            var rec = NationRecord()
            rec.nation = n.id; rec.nameEn = n.nameEn; rec.nameZh = n.nameZh; rec.color = n.color
            rec.founded = n.founded ?? 0; rec.ended = world.time
            rec.peakPop = n.peakPop ?? n.pop; rec.peakTowns = n.peakTowns ?? n.towns; rec.peakSoldiers = n.peakSoldiers ?? n.soldiers
            rec.born = n.born ?? 0; rec.died = n.died ?? 0; rec.wars = n.wars ?? 0; rec.techCount = n.techCount
            rec.landmarks = (realm.monuments ?? []).filter { ($0.builder ?? $0.nation) == n.id && $0.kind != .cemetery }.count
            let seat = n.lastSeat ?? settlements.values.filter { !$0.abandoned }.min { $0.id < $1.id }?.center ?? TilePos(0, 0)
            let m = raiseMonument(.cemetery, around: seat, town: 0, nation: n.id, grave: rec)
            emit("extinct", [n.name(zh: zh), "\(rec.peakPop)", "\(rec.died)"], (m?.center ?? seat).center, nations: [n.id], cause: "no one left", result: "history")
        }
    }

    /// The national cemeteries laid out so far.
    public var cemeteries: [Monument] { (realm.monuments ?? []).filter { $0.kind == .cemetery } }

    /// The tiles of a national cemetery.
    func carveCemetery(_ m: Monument) {
        let T = { (k: String) in self.content.tid(k) }
        let W = m.w, D = m.d, cx = W / 2
        let grass = T("grass"), stone = T("stone_floor"), wall = T("wall_stone")
        func set(_ x: Int, _ y: Int, ground: UInt8? = nil, obj: UInt8? = nil, decor: UInt8? = nil) {
            if let g = ground { world.setTile(0, m.x + x, m.y + y, g) }
            if let o = obj { world.setTile(2, m.x + x, m.y + y, o) }
            if let d = decor { world.setTile(3, m.x + x, m.y + y, d) }
        }
        for y in 0..<D { for x in 0..<W {
            let edge = x == 0 || y == 0 || x == W - 1 || y == D - 1
            set(x, y, ground: grass, obj: edge ? (y == D - 1 && abs(x - cx) <= 1 ? (x == cx ? T("gate_open") : 0) : wall) : 0)
        } }
        // the avenue from the gate, the plaza with the obelisk
        for y in 1..<(D - 1) { for x in (cx - 1)...(cx + 1) { set(x, y, ground: stone) } }
        for y in 17..<25 { for x in (cx - 5)...(cx + 4) { set(x, y, ground: stone) } }
        set(cx, 20, obj: T("statue"))
        // the hall of records at the north, its books and its sign
        for y in 2..<9 { for x in (cx - 6)..<(cx + 6) {
            let e = y == 2 || y == 8 || x == cx - 6 || x == cx + 5
            set(x, y, ground: T("wood_floor"), obj: e ? (y == 8 && x == cx ? T("door_wood") : wall) : 0)
        } }
        for x in [cx - 4, cx - 3, cx + 2, cx + 3] { set(x, 3, obj: T("bookshelf")) }
        set(cx, 4, obj: T("table")); set(cx + 2, 9, obj: T("sign"))
        // the graves, row on row either side of the avenue
        let n = m.grave?.graves ?? 24
        var placed = 0
        for row in 0..<7 { for col in 0..<18 where placed < n {
            let x = col < 9 ? 3 + col * 2 : cx + 4 + (col - 9) * 2
            let y = 12 + row * 4
            guard x < W - 2, y < D - 3, !(y >= 17 && y < 25 && abs(x - cx) <= 6) else { continue }
            set(x, y, obj: T("grave"), decor: (row + col) % 3 == 0 ? T("flower_red") : nil)
            placed += 1
        } }
        // cypresses along the wall, lamps by the gate
        for x in stride(from: 2, to: W - 2, by: 4) { set(x, 1, obj: T("tree_pine")) }
        for y in stride(from: 10, to: D - 2, by: 5) { set(1, y, obj: T("tree_pine")); set(W - 2, y, obj: T("tree_pine")) }
        set(cx - 3, D - 2, obj: T("lantern_post")); set(cx + 3, D - 2, obj: T("lantern_post"))
        keepClear(TilePos(m.x + cx, m.y + D))
    }
}

extension Figure3D {
    /// A national cemetery: the obelisk banded in the nation's colour, the memorial wall, the gate arch, the hall
    /// of records with its roof.
    public static func cemeteryPieces(_ r: NationRecord?) -> [MonumentPiece] {
        let W = Float(NationRecord.w), D = Float(NationRecord.d)
        return [MonumentPiece(key: "cemetery-\(r?.color ?? "-")", x: 0, z: 0, w: W, d: D) { cemetery(r) }]
    }

    public static func cemetery(_ r: NationRecord?) -> Mesh3D {
        var m = Mesh3D()
        let W = Float(NationRecord.w), D = Float(NationRecord.d), cx = W / 2 + 0.5
        let granite = RGBA(150, 150, 158), light = RGBA(214, 212, 206), band = RGBA(hex: r?.color ?? "#888888")
        // the obelisk on its stepped base, in the plaza
        let oz: Float = 20.5
        m.box(cx - 3, -4, oz - 3, cx + 3, 0.6, oz + 3, light, faces: .all)
        m.box(cx - 2.2, 0.6, oz - 2.2, cx + 2.2, 1.4, oz + 2.2, light.darkened(0.05), faces: .all)
        m.frustum(SIMD3(cx, 1.4, oz), SIMD3(cx, 19, oz), 1.6, 0.9, granite, seg: 4)
        m.frustum(SIMD3(cx, 12, oz), SIMD3(cx, 13.2, oz), 1.32, 1.27, band, seg: 4)
        m.frustum(SIMD3(cx, 19, oz), SIMD3(cx, 21.5, oz), 0.9, 0.02, light, seg: 4)
        // the memorial wall behind it, its records cut in as bands
        m.box(cx - 8, -4, 15, cx + 8, 4, 15.8, granite.darkened(0.1), faces: .all)
        for k in 0..<5 { let y = 0.8 + Float(k) * 0.6; m.box(cx - 7, y, 15.82, cx + 7, y + 0.25, 15.9, light, faces: .all) }
        m.box(cx - 8.4, 4, 14.8, cx + 8.4, 4.4, 16, light, faces: .all)
        // the gate arch
        m.box(cx - 3, -4, D - 1, cx - 2, 5, D, granite, faces: .all)
        m.box(cx + 1, -4, D - 1, cx + 2, 5, D, granite, faces: .all)
        m.box(cx - 3.4, 5, D - 1.2, cx + 2.4, 6.2, D + 0.2, light, faces: .all)
        m.box(cx - 1.5, 6.2, D - 1, cx + 0.5, 6.8, D, band, faces: .all)
        // the hall of records
        m.box(cx - 6.5, -4, 2, cx + 5.5, 3.5, 9, light, faces: .all)
        m.hipRoof(cx - 6.5, 2, cx + 5.5, 9, y0: 3.5, h: 2.2, o: 0.7, granite.darkened(0.15))
        for x in stride(from: cx - 6, through: cx + 5, by: 2) { m.frustum(SIMD3(x, 0, 9.2), SIMD3(x, 3.5, 9.2), 0.25, 0.22, light.lightened(0.05), seg: 8) }
        return m
    }
}

extension MonumentArt {
    static func cemeterySprites(_ r: NationRecord?) -> [MonumentSprite] {
        [MonumentSprite(key: "cemetery-\(r?.color ?? "-")", x: Float(NationRecord.w) / 2 + 0.5, z: 24, w: 18, h: 23) { ppt in cemeteryPicture(r, ppt: ppt) }]
    }

    /// The obelisk and the memorial wall seen from the south.
    public static func cemeteryPicture(_ r: NationRecord?, ppt: Double) -> Bitmap {
        let s = ppt, W = Int(18 * s), H = Int(23 * s)
        var c = Canvas(max(2, W), max(2, H), scale: 1)
        let gh = Double(H), cx = Double(W) / 2
        let granite = RGBA(150, 150, 158), light = RGBA(214, 212, 206), band = RGBA(hex: r?.color ?? "#888888")
        c.inkColor = ink
        c.rect(cx - 8 * s, gh - 4 * s, 16 * s, 4 * s, granite.darkened(0.1), ink: 1)
        for k in 0..<5 { c.rect(cx - 7 * s, gh - (0.8 + Double(k) * 0.6 + 0.25) * s, 14 * s, 0.25 * s, light) }
        c.rect(cx - 3 * s, gh - 0.6 * s, 6 * s, 0.6 * s, light, ink: 0.8)
        c.poly([(cx - 1.6 * s, gh - 1.4 * s), (cx + 1.6 * s, gh - 1.4 * s), (cx + 0.9 * s, gh - 19 * s), (cx - 0.9 * s, gh - 19 * s)], granite, ink: 1, shade: Shade(shadow: 0.15, light: 0.2))
        c.rect(cx - 1.3 * s, gh - 13.2 * s, 2.6 * s, 1.2 * s, band)
        c.poly([(cx - 0.9 * s, gh - 19 * s), (cx + 0.9 * s, gh - 19 * s), (cx, gh - 21.5 * s)], light, ink: 0.8)
        return c.image()
    }
}
