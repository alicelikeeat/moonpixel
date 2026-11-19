import XCTest
@testable import MoonPixelCore

final class AnnexationTests: XCTestCase {
    func capital(_ s: Society, _ n: Int) -> Settlement {
        if let c = s.capital(of: n) { return c }
        let t = s.settlements.values.filter { !$0.abandoned && $0.nation == n }.min { $0.id < $1.id } ?? s.settlements.values.min { $0.id < $1.id }!
        t.nation = n
        s.setCapital(n, t, kind: "test", cause: "test")
        return s.capital(of: n)!
    }

    /// A nation's own landmark: a design drawn from its seed, a tower of real floors with homes and sky farms,
    /// a lift with a landing on every floor, fields and an airstrip on its plaza.
    func testANationsOwnLandmarkHasFloorsALiftFarmsAndAnAirstrip() {
        let s = makeSociety(7)
        let n = s.realm.nations[0].id
        let cap = capital(s, n)
        let lifts = s.realm.lifts.count
        guard let m = s.raiseMonument(.fusion, near: cap, nation: n, seed: 4242) else { return XCTFail("no room") }
        guard let d = m.design else { return XCTFail("no design") }
        XCTAssertEqual(d, FusionDesign.make(seed: 4242), "the same seed, the same design")
        XCTAssertNotEqual(FusionDesign.make(seed: 4242), FusionDesign.make(seed: 4243))
        XCTAssertFalse(m.title(zh: true).isEmpty)
        let o = TilePos(m.x + FusionDesign.coreOrigin, m.y + FusionDesign.coreOrigin)
        XCTAssertEqual(s.world.tile(2, o.x + FusionDesign.core / 2, o.y + FusionDesign.core - 1), s.content.tid("door_wood"), "the tower's door")
        // floors all the way up, sky farms on some, beds on the others
        let top = s.storeyWorld(d.storeys - 1)
        XCTAssertNotEqual(top.tile(0, o.x + 5, o.y + 5), 0, "a floor on the top storey")
        XCTAssertEqual(s.storeyWorld(2).tile(0, o.x + 5, o.y + 5), s.content.tid("farmland"), "a sky farm")
        // the lift: a landing on every floor
        XCTAssertEqual(s.realm.lifts.count, lifts + 1)
        XCTAssertEqual(s.realm.lifts.last?.stops.count, d.storeys, "a landing on every floor")
        // the airstrip and the fields
        XCTAssertEqual(s.world.tile(0, m.x + 3, m.y + 20), s.content.tid("runway"))
        XCTAssertEqual(s.world.tile(0, m.x + 50, m.y + 8), s.content.tid("farmland"))
        // its model stands as tall as its floors and crown
        let mesh = Figure3D.monument(.fusion)
        XCTAssertFalse(mesh.isEmpty)
        let real = Figure3D.fusion(d)
        XCTAssertEqual(real.bounds.max.y, d.totalHeight, accuracy: 3)
        XCTAssertGreaterThan(MonumentArt.fusionPicture(d, ppt: 3).h, 10)
        XCTAssertEqual(MonumentArt.sprites(for: m).count, 1)
    }

    /// A suzerain over half the world may turn on its ally; going badly, it calls the annexation off and the
    /// two are allies again.
    func testASuzerainOverHalfTheWorldMayAnnexItsAllyAndCallsItOffWhenItGoesBadly() {
        let s = makeSociety(7)
        guard s.realm.nations.count >= 3 else { return XCTFail("three nations") }
        let a = s.realm.nations[0].id, b = s.realm.nations[1].id, c = s.realm.nations[2].id
        for (n, pop) in [(a, 1000), (b, 100), (c, 100)] { s.realm.nations[s.realm.ni(n)!].pop = pop; s.realm.nations[s.realm.ni(n)!].soldiers = 0 }
        guard let r = s.realm.ri(a, b) else { return XCTFail("relation") }
        s.realm.relations[r].pact = true; s.realm.relations[r].state = 0
        if let rc = s.realm.ri(a, c) { s.realm.relations[rc].state = 0 }
        var days = 0
        while s.realm.annexations == nil && days < 400 { s.annexationDay(); days += 1 }
        guard let ax = s.realm.annexations?.first else { return XCTFail("never annexed in \(days) days") }
        XCTAssertEqual(ax.suzerain, a); XCTAssertEqual(ax.target, b)
        XCTAssertFalse(s.realm.relations[r].pact, "the alliance torn up")
        XCTAssertEqual(s.realm.relations[r].state, 1, "and war")
        // not certain: a suzerain only a little stronger never tries
        let s2 = makeSociety(7)
        let a2 = s2.realm.nations[0].id, b2 = s2.realm.nations[1].id, c2 = s2.realm.nations[2].id
        for (n, pop) in [(a2, 260), (b2, 200), (c2, 10)] { s2.realm.nations[s2.realm.ni(n)!].pop = pop; s2.realm.nations[s2.realm.ni(n)!].soldiers = 0 }
        let r2 = s2.realm.ri(a2, b2)!
        s2.realm.relations[r2].pact = true; s2.realm.relations[r2].state = 0
        for _ in 0..<300 { s2.annexationDay() }
        XCTAssertNil(s2.realm.annexations, "1.3 times the ally is not enough to swallow it")
        XCTAssertTrue(s2.realm.relations[r2].pact)
        // the war goes badly: the suzerain tires; it calls it off and they are allies again
        s.realm.nations[s.realm.ni(a)!].fatigue = 0.9
        s.annexationDay()
        XCTAssertNil(s.realm.annexations)
        XCTAssertTrue(s.realm.relations[r].pact, "allied again")
        XCTAssertNotEqual(s.realm.relations[r].state, 1, "no longer at war")
        XCTAssertTrue((s.realm.chron ?? []).contains { $0.kind == "annex_off" })
    }

    /// A fallen ally rises again with its ally's help, long before it could alone, and raises a landmark.
    func testAnAllyHelpsAFallenAllyRiseAgainWithALandmark() {
        let s = makeSociety(7)
        let a = s.realm.nations[0].id, b = s.realm.nations[1].id
        guard let r = s.realm.ri(a, b) else { return XCTFail("relation") }
        s.realm.relations[r].pact = true; s.realm.relations[r].state = 0
        // b loses its land
        for t in s.settlements.values where t.nation == b { t.nation = a }
        s.realm.nations[s.realm.ni(b)!].exileSince = s.world.time
        let towns = s.settlements.values.filter { !$0.abandoned }.count
        let monuments = s.realm.monuments?.count ?? 0
        XCTAssertTrue(s.allyRebuild(b), "its ally lifts it up")
        XCTAssertNil(s.realm.nation(b)?.exileSince, "on its land again")
        XCTAssertEqual(s.settlements.values.filter { !$0.abandoned }.count, towns + 1, "in a new town")
        let nt = s.settlements.values.filter { !$0.abandoned && $0.nation == b }
        XCTAssertFalse(nt.isEmpty)
        XCTAssertEqual(s.realm.monuments?.count ?? 0, monuments + 1, "and raises a landmark of its own at once")
        XCTAssertEqual(s.realm.monuments?.last?.nation, b)
        XCTAssertTrue((s.realm.chron ?? []).contains { $0.kind == "ally_rebuild" })
    }

    /// Whoever holds a landmark's town holds the landmark; one taken from another nation doubles the taker's
    /// strength, and landmark towns keep the largest garrisons.
    func testATakenLandmarkDoublesTheTakersStrength() {
        let s = makeSociety(7)
        let a = s.realm.nations[0].id, b = s.realm.nations[1].id
        let cap = capital(s, a)
        guard let m = s.raiseMonument(.clock, near: cap, nation: a) else { return XCTFail("no room") }
        XCTAssertEqual(s.landmarkBonus(b), 1)
        XCTAssertTrue(s.landmarkTown(cap))
        cap.nation = b
        s.landmarkOwnersDay()
        let now = s.realm.monuments!.first { $0.id == m.id }!
        XCTAssertEqual(now.nation, b, "the landmark changes hands with its town")
        XCTAssertEqual(now.builder, a, "who raised it is remembered")
        XCTAssertEqual(s.landmarkBonus(b), 2, "twice the strength for the taker")
        XCTAssertEqual(s.landmarkBonus(a), 1)
        XCTAssertTrue((s.realm.chron ?? []).contains { $0.kind == "monument_taken" })
    }
}

extension Anime3DPreviewTests {
    /// MP_PREVIEW: eight landmarks of nations' own designs (docs/fusion-landmarks.png).
    func testPreviewFusionLandmarks() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        var sheet = Bitmap(2000, 1000, fill: RGBA(206, 226, 240))
        let tex = Tex(b: Palette3D.bitmap.animeGraded())
        for i in 0..<8 {
            let d = FusionDesign.make(seed: 101 + i * 37)
            var ground = Mesh3D()
            ground.box(0, -0.3, 0, 64, 0, 64, RGBA(170, 168, 160), faces: .all)
            ground.box(2, 0, 3, 6, 0.02, 61, RGBA(70, 72, 80), faces: .all)
            ground.box(44, 0, 4, 60, 0.05, 17, RGBA(200, 180, 90), faces: .all); ground.box(44, 0, 46, 60, 0.05, 59, RGBA(200, 180, 90), faces: .all)
            let m = Figure3D.fusion(d)
            let span = max(64 * 1.15, d.totalHeight * 1.15)
            let img = render([(ground, tex, false, .zero, 0), (m.inked(width: 0.05), tex, false, .zero, 0)], size: (500, 500), yaw: 0.65, pitch: 0.3, scale: 470 / span, centre: SIMD3(32, d.totalHeight * 0.42, 32))
            sheet.blit(img, sx: 0, sy: 0, sw: 500, sh: 500, dx: (i % 4) * 500, dy: (i / 4) * 500, blend: false)
            print("FUSION \(i): \(d.name(zh: true)) base \(d.base) body \(d.body) top \(d.top) storeys \(d.storeys)")
        }
        var data = Data("\(sheet.w) \(sheet.h)\n".utf8); data.append(contentsOf: sheet.px)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fusion-a.rgba"))
    }
}
