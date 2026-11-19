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
        for kind in MonumentKind.allCases {
            guard let m = s.raiseMonument(kind, near: cap, nation: nation) else { XCTFail("no room for \(kind)"); continue }
            XCTAssertEqual(m.w, kind.size.w); XCTAssertEqual(m.d, kind.size.d)
            XCTAssertFalse(cap.inArea(m.center), "\(kind) stands beside the town, not on it")
            var objs = 0
            for y in m.y..<(m.y + m.d) { for x in m.x..<(m.x + m.w) where s.world.tile(2, x, y) != 0 { objs += 1 } }
            XCTAssertGreaterThan(objs, 4, "\(kind) has walls, gates and things on its ground")
            XCTAssertFalse(Figure3D.monument(kind).isEmpty, "\(kind) has a 3D model")
            XCTAssertEqual(Figure3D.monument(kind).bounds.min.y, 0, accuracy: 0.05, "\(kind) stands on the ground")
            let pic = MonumentArt.picture(kind)
            XCTAssertGreaterThan(pic.w, 0)
        }
        let ms = s.realm.monuments ?? []
        XCTAssertEqual(ms.count, MonumentKind.allCases.count)
        XCTAssertEqual(Set(ms.map { $0.id }).count, ms.count, "ids are unique")
        // none overlaps another
        for a in ms { for b in ms where a.id < b.id {
            XCTAssertFalse(a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.d && b.y < a.y + a.d, "\(a.kind) and \(b.kind) overlap")
        } }
        // the palace: a moat, red walls, a gate, a throne in each of the three halls
        let p = ms.first { $0.kind == .palace }!
        XCTAssertEqual(s.world.tile(0, p.x, p.y + 5), s.content.tid("shallow_water"), "the moat")
        XCTAssertEqual(s.world.tile(2, p.x + 1, p.y + 5), s.content.tid("wall_brick"), "the red wall")
        XCTAssertEqual(s.world.tile(2, p.x + p.w / 2, p.y + p.d - 2), s.content.tid("gate_open"), "the south gate")
        var thrones = 0
        for y in p.y..<(p.y + p.d) { for x in p.x..<(p.x + p.w) where s.world.tile(2, x, y) == s.content.tid("throne") { thrones += 1 } }
        XCTAssertEqual(thrones, 3, "three great halls")
        // the statue on its island
        let l = ms.first { $0.kind == .liberty }!
        XCTAssertEqual(s.world.tile(2, l.center.x, l.center.y), s.content.tid("statue"))
        XCTAssertEqual(s.world.tile(0, l.x, l.y), s.content.tid("shallow_water"), "water round the island")
        // the map marks them
        let marks = WorldMap().render(s, centre: cap.center, reach: 6, zh: true).1.filter { $0.kind == .monument }
        XCTAssertGreaterThanOrEqual(marks.count, ms.count)
        XCTAssertTrue(marks.contains { $0.name == "宫城" })
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
    }
}

extension Anime3DPreviewTests {
    /// MP_PREVIEW: the six monuments modelled in 3D (docs/capital-monuments.png).
    func testPreviewMonuments() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        var sheet = Bitmap(1500, 1000, fill: RGBA(206, 226, 240))
        for (i, kind) in MonumentKind.allCases.enumerated() {
            let (w, d) = kind.size
            var ground = Mesh3D()
            ground.box(0, -0.2, 0, Float(w), 0, Float(d), kind == .liberty ? RGBA(90, 150, 190) : RGBA(120, 170, 96), faces: .all)
            let m = Figure3D.monument(kind)
            let top = m.bounds.max.y
            let parts: [(Mesh3D, Tex?, Bool, SIMD3<Float>, Float)] = [
                (ground, Tex(b: Palette3D.bitmap.animeGraded()), false, .zero, 0),
                (m.inked(width: 0.05), Tex(b: Palette3D.bitmap.animeGraded()), false, .zero, 0),
            ]
            let span = max(Float(max(w, d)) * 1.3, top * 1.25)
            let img = render(parts, size: (500, 500), yaw: 0.6, pitch: 0.38, scale: 440 / span, centre: SIMD3(Float(w) / 2, top * 0.42, Float(d) / 2))
            sheet.blit(img, sx: 0, sy: 0, sw: 500, sh: 500, dx: (i % 3) * 500, dy: (i / 3) * 500, blend: false)
        }
        var data = Data("\(sheet.w) \(sheet.h)\n".utf8); data.append(contentsOf: sheet.px)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("monuments-a.rgba"))
    }
}
