import XCTest
@testable import MoonPixelCore

/// The battle of the twin ports made in a player's own world, and played hour by hour on its clock.
final class WorldDemoTests: XCTestCase {
    func oceanWorld(_ seed: Int) -> Society {
        let w = OpenWorld(seed: seed, budget: MemoryBudget(overrideMB: 256))
        w.gen.oceans = true
        let s = Society(world: w, seed: seed)
        s.bootstrap(origin: TilePos(0, 0), villages: 3, per: 20)
        return s
    }

    func play(_ s: Society, days: Int) {
        let hour = MP.daySeconds / 24
        for _ in 0..<(days * 24) {
            s.world.time += hour
            s.civHourly()
            if s.realm.worldDemo?.done == true { break }
        }
    }

    func testTheBattleIsMadeInTheWorldAndPlayedToItsEnd() {
        let s = oceanWorld(21)
        let r = s.startWorldDemo(refuse: true, drop: .eastPort, giant: .guardEast)
        XCTAssertNil(r.error, r.error ?? "")
        guard let st = s.realm.worldDemo, let watch = r.watch else { return XCTFail("no demonstration") }
        let c = s.civ
        // the place is in the world: two ports of the small nation on the strait, the great power over the sea
        XCTAssertEqual(c.cities[st.west]?.nation, st.small); XCTAssertEqual(c.cities[st.east]?.nation, st.small)
        XCTAssertEqual(c.cities[st.capital]?.nation, st.great)
        XCTAssertEqual(c.regions[st.platform]?.legal, st.small, "the platform between the ports is theirs")
        XCTAssertEqual(c.units.values.filter { $0.kind == "frame" && $0.nation == st.great }.count, 2)
        XCTAssertTrue(c.giants.contains { $0.nation == st.small })
        XCTAssertTrue(abs(watch.x) + abs(watch.y) > 0, "a place to watch from")
        // played on the world's clock, step by step
        play(s, days: 40)
        let done = s.realm.worldDemo!
        XCTAssertTrue(done.done, "the battle reaches its end: \(done.log)")
        XCTAssertTrue(done.log.contains { $0.contains("refused") })
        XCTAssertTrue(done.log.contains { $0.contains("frames") })
        let kinds = Set(c.chronicle.map { $0.kind })
        XCTAssertTrue(kinds.contains("landing") && kinds.contains("sky_drop_eastPort") && kinds.contains("frame_landed"), "\(kinds.sorted())")
        XCTAssertTrue(kinds.contains("kept_the_sea") || kinds.contains("port_lost"), "an outcome is recorded")
        XCTAssertFalse(s.worldDemoLines(zh: true).isEmpty)
        XCTAssertEqual(c.audit(), [])
    }

    func testSubmissionInTheWorld() {
        let s = oceanWorld(21)
        XCTAssertNil(s.startWorldDemo(refuse: false, drop: .platform, giant: .carryWest).error)
        XCTAssertEqual(s.startWorldDemo(refuse: false, drop: .platform, giant: .carryWest).error, "running", "one at a time")
        play(s, days: 30)
        let st = s.realm.worldDemo!
        XCTAssertTrue(st.done)
        XCTAssertEqual(s.civ.suzerain(of: st.small), st.great, "the small nation submitted")
    }

    func testAnOldWorldHasNoStraitToFightOver() {
        let s = makeSociety(7)
        XCTAssertEqual(s.startWorldDemo(refuse: true, drop: .eastPort, giant: .guardEast).error, "needs_oceans")
    }
}
