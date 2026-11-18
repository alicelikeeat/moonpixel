import XCTest
@testable import MoonPixelCore

/// Pillar jumping, materials in one go, time of day, and the anime look.
final class CreativeTests: XCTestCase {
    func testABlockUnderYourFeetLiftsYouAStoreyEachTimeAndCosts() {
        let s = makeSociety(4, villages: 2, per: 10)
        let t = s.world.findFree(near: TilePos(200, 200), maxR: 20)
        for l in 1...3 { s.world.setTile(l, t.x, t.y, 0) }
        let g = WorldGround(s)
        s.realm.player.body = Body(at: t.center, z: g.floor(0, t) ?? 0, depth: 0)
        s.carry("stone", 3)
        XCTAssertNil(s.pillarUp(with: "stone"))
        XCTAssertEqual(s.realm.player.body!.depth, OpenWorld.storeyBase + 1)
        XCTAssertEqual(s.world.tile(2, t.x, t.y), s.content.tid("wall_stone"), "the block is under the feet")
        XCTAssertTrue(s.supported(t, onStorey: 1), "and it holds the floor up, by the usual rule")
        let z1 = s.realm.player.body!.z
        XCTAssertNil(s.pillarUp(with: "stone")); XCTAssertNil(s.pillarUp(with: "stone"))
        XCTAssertEqual(s.realm.player.body!.depth, OpenWorld.storeyBase + 3)
        XCTAssertEqual(s.realm.player.body!.z, z1 + 4, accuracy: 1e-6, "two tiles a storey")
        XCTAssertEqual(s.carried("stone"), 0, accuracy: 1e-9, "one block each")
        XCTAssertEqual(s.pillarUp(with: "stone"), "none left")
        XCTAssertEqual(s.pillarUp(with: "food"), "not a block")
        // standing still on the new top works with the body's own rules (no fall)
        var b = s.realm.player.body!
        let r = Motion.advance(&b, dt: 1, wish: .zero, jump: false, ground: g)
        XCTAssertEqual(b.depth, OpenWorld.storeyBase + 3); XCTAssertFalse(r.landed && r.damage > 0)
        // a ceiling stops it: a floor already above
        s.carry("planks", 2)
        s.storeyWorld(4).setTile(0, t.x, t.y, s.content.tid("wood_floor"))
        XCTAssertEqual(s.pillarUp(with: "planks"), "ceiling")
        XCTAssertEqual(s.carried("planks"), 2, "nothing taken when refused")
    }

    func testMaterialsInOneGoFillOnlyWhatThePackCarries() {
        let s = makeSociety(4, villages: 2, per: 10)
        let given = s.supplyPack()
        XCTAssertGreaterThan(given["stone"] ?? 0, 0)
        XCTAssertLessThanOrEqual(s.packWeight(), s.invCfg.capacity + 1e-6)
        XCTAssertEqual(s.realm.player.cheated, true, "marked like any cheat")
        let again = s.supplyPack()
        XCTAssertLessThanOrEqual(again.values.reduce(0, +), 7, "a full pack takes (almost) nothing more")
        XCTAssertLessThanOrEqual(s.packWeight(), s.invCfg.capacity + 1e-6)
    }

    func testTheClockOnlyMovesForwardToTheHourAsked() {
        let s = makeSociety(4, villages: 2, per: 10)
        let t0 = s.world.time
        let skipped = s.advanceTo(hour: 22)
        XCTAssertGreaterThan(skipped, 0)
        XCTAssertEqual(s.world.hour, 22, accuracy: 0.01)
        XCTAssertEqual(s.world.dayPhase, .night)
        XCTAssertTrue(s.world.isNight)
        s.advanceTo(hour: 12)
        XCTAssertEqual(s.world.dayPhase, .day)
        XCTAssertEqual(s.world.clockText, "12:00")
        XCTAssertGreaterThan(s.world.time, t0)
        let t1 = s.world.time
        s.advanceTo(hour: 12)
        XCTAssertEqual(s.world.time - t1, MP.daySeconds, accuracy: 1e-6, "asking for the hour it is now waits a whole day, never goes back")
    }

    func testTheAnimeLookIsSmoothOutlinedAndKeepsShapes() {
        // a red disc on transparency
        var b = Bitmap(16, 16)
        b.disc(8, 8, 5, RGBA(200, 40, 40))
        let a = b.anime()
        XCTAssertEqual(a.w, 32); XCTAssertEqual(a.h, 32)
        func px(_ m: Bitmap, _ x: Int, _ y: Int) -> RGBA { m.at(x, y) }
        XCTAssertEqual(px(a, 0, 0).a, 0, "transparent stays transparent")
        XCTAssertEqual(px(a, 16, 16).a, 255, "the inside is still there")
        // the rim is inked: darker than the inside
        var rim: RGBA?
        for x in 0..<32 where px(a, x, 16).a != 0 { rim = px(a, x, 16); break }
        XCTAssertLessThan(Int(rim!.r), Int(px(a, 16, 16).r))
        // the same input always gives the same picture
        XCTAssertEqual(a.px, b.anime().px)
        // grading keeps size and transparency
        let g = b.animeGraded()
        XCTAssertEqual(g.w, 16); XCTAssertEqual(g.px.enumerated().filter { $0.offset % 4 == 3 }.map { $0.element }, b.px.enumerated().filter { $0.offset % 4 == 3 }.map { $0.element })
    }
}
