import XCTest
@testable import MoonPixelCore

final class CemeteryUfoTests: XCTestCase {
    /// A nation with no land and nobody left who holds to it passes into history; its cemetery is laid out with
    /// its records and a grave for every few of its dead.
    func testAFallenNationWithNoOneLeftGetsANationalCemeteryWithItsRecords() {
        let s = makeSociety(7)
        runYears(s, 0.3)
        guard let n = s.realm.nations.first else { return XCTFail("nations") }
        let k = s.realm.ni(n.id)!
        XCTAssertNotNil(s.realm.nations[k].founded, "records kept while it lives")
        XCTAssertGreaterThan(s.realm.nations[k].peakPop ?? 0, 0)
        // it loses every town and every last one who held to it
        let other = s.realm.nations[1].id
        for t in s.settlements.values where t.nation == n.id { t.nation = other }
        for a in s.agents.values where a.nation == n.id { a.nation = other }
        s.realm.nations[k].towns = 0
        s.realm.nations[k].exileSince = s.world.time
        s.realm.nations[k].died = 90; s.realm.nations[k].born = 120; s.realm.nations[k].wars = 3
        s.nationsPassDay()
        XCTAssertEqual(s.realm.nations[k].status, 2, "passed into history")
        guard let m = s.cemeteries.first else { return XCTFail("no cemetery") }
        XCTAssertEqual(m.w * 2, 96, "96 m across"); XCTAssertEqual(m.d * 2, 80)
        guard let r = m.grave else { return XCTFail("no record") }
        XCTAssertEqual(r.nation, n.id); XCTAssertEqual(r.died, 90); XCTAssertEqual(r.born, 120); XCTAssertEqual(r.wars, 3)
        XCTAssertGreaterThan(r.peakPop, 0)
        XCTAssertTrue(r.lines(zh: true)[0].contains("国家公墓"))
        XCTAssertTrue(m.title(zh: true).hasSuffix("国家公墓"))
        var graves = 0
        for y in m.y..<(m.y + m.d) { for x in m.x..<(m.x + m.w) where s.world.tile(2, x, y) == s.content.tid("grave") { graves += 1 } }
        XCTAssertEqual(graves, r.graves, "a grave for every few of its dead (30)")
        XCTAssertEqual(s.world.tile(2, m.x + m.w / 2, m.y + m.d - 1), s.content.tid("gate_open"), "its gate open")
        XCTAssertTrue((s.realm.chron ?? []).contains { $0.kind == "extinct" })
        XCTAssertEqual(s.capturedLandmarks(other).count, 0, "a grave is no landmark to take")
        XCTAssertGreaterThan(Figure3D.cemetery(r).bounds.max.y, 20, "the obelisk stands tall")
        // only once
        s.nationsPassDay()
        XCTAssertEqual(s.cemeteries.count, 1)
        XCTAssertTrue(WorldMap.describe(s, TilePos(m.x + 10, m.y + 10), zh: true).contains("国家公墓"))
    }

    /// The nations' cards show their allies and their overall strength.
    func testAlliesAndOverallStrengthOnTheNationCards() {
        let s = makeSociety(7)
        runYears(s, 0.2)
        let a = s.realm.nations[0].id, b = s.realm.nations[1].id
        let r = s.realm.ri(a, b)!
        s.realm.relations[r].pact = true; s.realm.relations[r].state = 0
        let info = s.nationInfos()
        let ia = info.first { $0.id == a }!
        XCTAssertEqual(ia.allies.map { $0.name }, [s.realm.nation(b)!.name(zh: s.zh)])
        XCTAssertGreaterThan(ia.composite, 0)
        XCTAssertEqual(ia.composite, s.compositePower(a))
        // more soldiers, more strength
        let before = s.compositePower(a)
        s.realm.nations[s.realm.ni(a)!].soldiers += 10
        XCTAssertGreaterThan(s.compositePower(a), before)
    }

    /// Board a saucer resting on its pad, ride it up on its round, and jump out with a parachute: a slow fall
    /// and a landing that does no harm.
    func testRideASaucerAndJumpWithAParachute() {
        let w = OpenWorld(seed: 9, budget: MemoryBudget(overrideMB: 256))
        let s = Society(world: w, seed: 9)
        guard let p = s.nearestUfoPort(cx: 0, cy: 0) else { return XCTFail("a UFO airport") }
        let pad = Vec2(Double(p.0 * 32 + 16), Double(p.1 * 32 + 14)) * 16
        // wait for a moment a saucer rests
        var t = 0.0
        while t < Society.ufoRound && !s.ufos(near: pad, reach: 200).contains(where: { $0.landed }) { s.world.time += 1; t += 1 }
        guard let u = s.ufos(near: pad, reach: 200).first(where: { $0.landed }) else { return XCTFail("none resting") }
        let g = WorldGround(s)
        s.realm.player.body = Body(at: u.pos + Vec2(16, 0), z: g.floor(0, u.pos.tile) ?? 0, depth: 0)
        XCTAssertNotNil(s.landedUfo(near: s.realm.player.body!.pos))
        XCTAssertTrue(s.boardUfo())
        // it lifts off with the traveller on it
        var high = 0.0
        for _ in 0..<Int(Society.ufoRound) {
            s.world.time += 1; s.ufoRideStep()
            if let r = s.ridingUfo, r.z > 10 { high = s.realm.player.body!.z - (g.floor(0, r.pos.tile) ?? 0); break }
        }
        XCTAssertGreaterThan(high, 10, "carried up into the sky")
        // and jumps: under the parachute the fall is slow and the landing harmless
        XCTAssertTrue(s.jumpFromUfo())
        XCTAssertNil(s.realm.player.ufo)
        var b = s.realm.player.body!
        XCTAssertEqual(b.chute, true)
        var damage = 0.0, maxFall = 0.0, steps = 0
        while b.airborne && steps < 4000 {
            let r = Motion.advance(&b, dt: 1.0 / 30, wish: Vec2(20, 0), jump: false, ground: g, platforms: [])
            damage += r.damage; maxFall = max(maxFall, -b.vz); steps += 1
        }
        XCTAssertFalse(b.airborne, "landed")
        XCTAssertEqual(damage, 0, "no harm from the landing")
        XCTAssertLessThanOrEqual(maxFall, Motion.chuteFall + 1e-9, "a slow fall")
        XCTAssertNil(b.chute, "the parachute packed away on landing")
    }
}

extension Anime3DPreviewTests {
    /// MP_PREVIEW: a national cemetery and a parachute (docs/national-cemetery.png).
    func testPreviewCemetery() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        var r = NationRecord(); r.color = "#c0392b"; r.died = 300
        var ground = Mesh3D()
        ground.box(0, -0.3, 0, 48, 0, 40, RGBA(110, 160, 90), faces: .all)
        ground.box(23, 0, 0, 26, 0.02, 40, RGBA(190, 188, 180), faces: .all)
        for row in 0..<7 { for col in 0..<18 {
            let x = Float(col < 9 ? 3 + col * 2 : 28 + (col - 9) * 2), z = Float(12 + row * 4)
            if z >= 17 && z < 25 && abs(x - 24) <= 6 { continue }
            ground.box(x + 0.3, 0, z + 0.4, x + 0.7, 0.9, z + 0.6, RGBA(170, 170, 176), faces: .all)
        } }
        for x in stride(from: Float(0), to: 48, by: 1) { ground.box(x, 0, 0, x + 1, 1.5, 0.5, RGBA(150, 150, 158), faces: .all); ground.box(x, 0, 39.5, x + 1, 1.5, 40, RGBA(150, 150, 158), faces: .all) }
        let tex = Tex(b: Palette3D.bitmap.animeGraded())
        let img = render([(ground, tex, false, .zero, 0), (Figure3D.cemetery(r).inked(width: 0.05), tex, false, .zero, 0)], size: (900, 600), yaw: 0.6, pitch: 0.42, scale: 13, centre: SIMD3(24, 5, 20))
        let chute = render([(Figure3D.parachute().inked(width: 0.03), tex, false, .zero, 0)], size: (300, 300), yaw: 0.4, pitch: 0.2, scale: 70, centre: SIMD3(0, -0.4, 0))
        var sheet = Bitmap(1200, 600, fill: .white)
        sheet.blit(img, sx: 0, sy: 0, sw: 900, sh: 600, dx: 0, dy: 0, blend: false)
        sheet.blit(chute, sx: 0, sy: 0, sw: 300, sh: 300, dx: 900, dy: 150, blend: false)
        var data = Data("\(sheet.w) \(sheet.h)\n".utf8); data.append(contentsOf: sheet.px)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("cem-a.rgba"))
    }
}
