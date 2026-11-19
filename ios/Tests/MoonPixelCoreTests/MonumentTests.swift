import XCTest
@testable import MoonPixelCore

final class MonumentTests: XCTestCase {
    func capitalSociety() -> (Society, Settlement, Int) {
        let s = makeSociety(7)
        if let n = s.realm.nations.first(where: { s.capital(of: $0.id) != nil }) { return (s, s.capital(of: n.id)!, n.id) }
        let n = s.realm.nations.first { $0.exileSince == nil }!
        let t = s.settlements.values.filter { !$0.abandoned && $0.nation == n.id }.min { $0.id < $1.id } ?? s.settlements.values.min { $0.id < $1.id }!
        t.nation = n.id
        s.setCapital(n.id, t, kind: "test", cause: "test")
        return (s, s.capital(of: n.id)!, n.id)
    }

    func testEveryKindStandsOnRealTilesBesideTheCapital() {
        let (s, cap, nation) = capitalSociety()
        for kind in MonumentKind.classic {
            guard let m = s.raiseMonument(kind, near: cap, nation: nation) else { XCTFail("no room for \(kind)"); continue }
            XCTAssertEqual(m.w, kind.size.w); XCTAssertEqual(m.d, kind.size.d)
            XCTAssertFalse(cap.inArea(m.center), "\(kind) stands beside the town, not on it")
            var objs = 0
            for y in m.y..<(m.y + m.d) { for x in m.x..<(m.x + m.w) where s.world.tile(2, x, y) != 0 { objs += 1 } }
            XCTAssertGreaterThan(objs, 4, "\(kind) has walls, gates and things on its ground")
            let mesh = Figure3D.monument(kind)
            XCTAssertFalse(mesh.isEmpty, "\(kind) has a 3D model")
            let top = mesh.bounds.max.y
            XCTAssertEqual(Double(top), kind.height, accuracy: max(2, kind.height * 0.08), "\(kind) stands its real height")
            XCTAssertGreaterThanOrEqual(mesh.bounds.min.x, -4); XCTAssertLessThanOrEqual(mesh.bounds.max.x, Float(m.w) + 4, "\(kind) within its ground")
            for sp in MonumentArt.sprites(kind) { XCTAssertGreaterThan(sp.draw(4).w, 0) }
        }
        let ms = s.realm.monuments ?? []
        XCTAssertEqual(ms.count, MonumentKind.classic.count)
        XCTAssertEqual(Set(ms.map { $0.id }).count, ms.count, "ids are unique")
        // none overlaps another
        for a in ms { for b in ms where a.id < b.id {
            XCTAssertFalse(a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.d && b.y < a.y + a.d, "\(a.kind) and \(b.kind) overlap")
        } }
        // the palace at its real size: 753 m by 961 m inside a moat 52 m wide, red walls, gates, the halls
        let p = ms.first { $0.kind == .palace }!
        XCTAssertEqual(p.w * 2, 856); XCTAssertEqual((p.d - 2 * Palace.moat) * 2, 960)
        XCTAssertEqual(s.world.tile(0, p.x + 5, p.y + 200), s.content.tid("shallow_water"), "the moat")
        XCTAssertEqual(s.world.tile(2, p.x + Palace.wallW + 1, p.y + 200), s.content.tid("wall_brick"), "the red wall")
        XCTAssertEqual(s.world.tile(2, p.x + Palace.cx, p.y + Palace.wallS - 3), s.content.tid("gate_open"), "the south gate")
        XCTAssertEqual(s.world.tile(0, p.x + Palace.cx, p.y + p.d - 4), s.content.tid("stone_floor"), "the bridge over the moat")
        var thrones = 0
        for y in p.y..<(p.y + p.d) { for x in p.x..<(p.x + p.w) where s.world.tile(2, x, y) == s.content.tid("throne") { thrones += 1 } }
        XCTAssertEqual(thrones, 6, "three great halls in the outer court, three in the inner")
        XCTAssertGreaterThan(Palace.courts.count, 40, "the courtyard houses of the east and west palaces")
        let pieces = Figure3D.monumentPieces(.palace)
        XCTAssertGreaterThan(pieces.count, 80, "built piece by piece, each on its own ground")
        let hall = Figure3D.hall(w: 36, d: 22, terrace: 4, col: 6.5, roof: 6.2, double: true)
        XCTAssertEqual(Double(hall.bounds.max.y), 4 + 6.5 + 0.8 + 6.2, accuracy: 1.5, "the great hall: 35 m to its ridge")
        // its ground is levelled: the halls and walls stand level however the land lay
        let g = s.world.gen
        XCTAssertEqual(g.elevation(p.x + 40, p.y + 60), g.elevation(p.x + p.w - 40, p.y + p.d - 60), accuracy: 1e-9)
        XCTAssertEqual(g.elevation(p.x + 40, p.y + 60), p.ground ?? -1, accuracy: 1e-9)
        XCTAssertEqual(g.elevation(p.x - 200, p.y - 200), g.naturalElevation(p.x - 200, p.y - 200), accuracy: 1e-9, "the land further off as it was")
        // the statue on its island; the iron tower's 330 m
        let l = ms.first { $0.kind == .liberty }!
        XCTAssertEqual(s.world.tile(2, l.center.x - 1, l.center.y - 2), s.content.tid("statue"))
        XCTAssertEqual(s.world.tile(0, l.x, l.y), s.content.tid("shallow_water"), "water round the island")
        XCTAssertEqual(Double(Figure3D.monument(.ironTower).bounds.max.y) * 2, 330, accuracy: 6)
        // the map marks them
        let marks = WorldMap().render(s, centre: cap.center, reach: 40, zh: true).1.filter { $0.kind == .monument }
        XCTAssertGreaterThanOrEqual(marks.count, ms.count)
        XCTAssertTrue(marks.contains { $0.name.hasPrefix("宫城") }, "named, with the nation that holds it")
    }

    func testCapitalsRaiseMonumentsInTurnFromTheirOwnStoneAndWood() {
        let (s, cap, nation) = capitalSociety()
        cap.stone = 0; cap.wood = 0
        s.monumentDay()
        XCTAssertTrue((s.realm.monuments ?? []).filter { $0.town == cap.id }.isEmpty, "nothing without stone and wood")
        cap.stone = 1000; cap.wood = 1000
        s.monumentDay()
        let first = (s.realm.monuments ?? []).filter { $0.town == cap.id }
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.kind, MonumentKind.order(nation: nation).first, "each nation its own first monument")
        let k = MonumentKind.order(nation: nation)[0].cost
        XCTAssertEqual(cap.stone, 1000 - k.stone, accuracy: 1e-9, "paid from the capital's stone")
        XCTAssertEqual(cap.wood, 1000 - k.wood, accuracy: 1e-9)
        s.monumentDay()
        XCTAssertEqual((s.realm.monuments ?? []).filter { $0.town == cap.id }.count, 1, "a pause between monuments")
        s.world.time += 3 * MP.daySeconds
        s.monumentDay()
        let n = (s.realm.monuments ?? []).filter { $0.town == cap.id }.count
        XCTAssertEqual(n, min(2, Society.monumentsAllowed(cap.members.count)), "the next one, as the town's size allows")
        XCTAssertEqual(Society.monumentsAllowed(0), 1); XCTAssertEqual(Society.monumentsAllowed(1000), 4)
        // saved and loaded with the realm
        let data = try! JSONEncoder().encode(s.realm)
        let back = try! JSONDecoder().decode(Realm.self, from: data)
        XCTAssertEqual(back.monuments, s.realm.monuments)
        let flats = s.world.gen.flats
        s.world.gen.flats = []
        s.realm = back; s.syncFlats()
        XCTAssertEqual(s.world.gen.flats, flats, "the levelled ground comes back with a saved game")
    }
}

extension Anime3DPreviewTests {
    /// MP_PREVIEW: the six monuments modelled in 3D (docs/capital-monuments.png).
    func testPreviewMonuments() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        var sheet = Bitmap(2000, 1000, fill: RGBA(206, 226, 240))
        let tex = Tex(b: Palette3D.bitmap.animeGraded())
        func panel(_ i: Int, _ kind: MonumentKind, yaw: Float, pitch: Float, span: Float? = nil, centre: SIMD3<Float>? = nil) {
            let (w, d) = kind.size
            var ground = Mesh3D()
            ground.box(-10, -0.3, -10, Float(w) + 10, 0, Float(d) + 10, kind == .liberty ? RGBA(90, 150, 190) : RGBA(120, 170, 96), faces: .all)
            let m = Figure3D.monument(kind)
            let top = m.bounds.max.y
            let parts: [(Mesh3D, Tex?, Bool, SIMD3<Float>, Float)] = [(ground, tex, false, .zero, 0), (m.inked(width: 0.06), tex, false, .zero, 0)]
            let sp = span ?? max(Float(max(w, d)) * 1.25, top * 1.2)
            let img = render(parts, size: (500, 500), yaw: yaw, pitch: pitch, scale: 470 / sp, centre: centre ?? SIMD3(Float(w) / 2, top * 0.42, Float(d) / 2))
            sheet.blit(img, sx: 0, sy: 0, sw: 500, sh: 500, dx: (i % 4) * 500, dy: (i / 4) * 500, blend: false)
        }
        panel(0, .palace, yaw: 0.35, pitch: 0.6)
        let oc = Palace.outerCourt
        panel(1, .palace, yaw: 0.5, pitch: 0.32, span: 120, centre: SIMD3(Float(Palace.cx), 8, Float(oc.z + oc.d - 20)))
        for (i, k) in [MonumentKind.liberty, .clock, .ironTower, .pyramid, .pagoda].enumerated() { panel(i + 2, k, yaw: 0.6, pitch: 0.3) }
        // all side by side at one scale (the flat view's pictures, 1.7 px a tile), with a 1.8 m person
        var cmp = Bitmap(500, 500, fill: RGBA(236, 240, 246))
        var x = 6
        let pics: [Bitmap] = [MonumentArt.hallPicture(w: 32, base: 4, terrace: 1, col: 6.5, roof: 6.2, double: true, ppt: 1.7)]
            + [MonumentKind.liberty, .clock, .ironTower, .pyramid, .pagoda].map { MonumentArt.picture($0, ppt: 1.7) }
        for (i, pic) in pics.enumerated() {
            let most = i == 1 ? 60 : 110
            let crop = pic.w > most ? (pic.w - most) / 2 : 0, cw = min(pic.w, most)
            cmp.blit(pic, sx: crop, sy: 0, sw: cw, sh: pic.h, dx: x, dy: 470 - pic.h, blend: true)
            x += cw + 4
        }
        for y in 470..<500 { for xx in 0..<500 { cmp.set(xx, y, RGBA(120, 170, 96)) } }
        for y in 468..<470 { cmp.set(3, y, RGBA(20, 20, 20)) }
        sheet.blit(cmp, sx: 0, sy: 0, sw: 500, sh: 500, dx: 1500, dy: 500, blend: false)
        var data = Data("\(sheet.w) \(sheet.h)\n".utf8); data.append(contentsOf: sheet.px)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("monuments-c.rgba"))
    }
}

final class MonumentSafetyTests: XCTestCase {
    /// Looking for a palace's site must not make the land it looks at (a search over kilometres would generate
    /// thousands of chunks on the main thread): only the chunks it is finally built on are made.
    func testSearchingForASiteGeneratesNoLand() {
        let s = makeSociety(7)
        let t = s.settlements.values.min { $0.id < $1.id }!
        let before = Set(s.world.cache.keys)
        guard let m = s.raiseMonument(.palace, near: t, nation: 1) else { return XCTFail("no room") }
        let made = Set(s.world.cache.keys).subtracting(before)
        let under = (OpenWorld.floorDiv(m.x, 32)...OpenWorld.floorDiv(m.x + m.w, 32)).count * (OpenWorld.floorDiv(m.y, 32)...OpenWorld.floorDiv(m.y + m.d, 32)).count
        XCTAssertLessThanOrEqual(made.count, under + 4, "only the palace's own ground was made (\(made.count) chunks, \(under) under it)")
    }

    /// The 3D view reads the ground's height on other threads while the game levels ground or loads a world.
    func testGroundHeightCanBeReadWhileTheLevelledGroundChanges() {
        let g = Generator(seed: 3)
        let flats = (0..<20).map { i in Generator.Flat(x0: i * 50, y0: 0, x1: i * 50 + 40, y1: 40, e: 0.6) }
        DispatchQueue.concurrentPerform(iterations: 8) { k in
            for i in 0..<4000 {
                if k == 0 && i % 10 == 0 { g.flats = i % 20 == 0 ? flats : [] }
                else { _ = g.elevation((i * 7 + k) % 1000, i % 60) }
            }
        }
        g.flats = flats
        XCTAssertEqual(g.elevation(20, 20), 0.6, accuracy: 1e-9)
    }
}
