import XCTest
@testable import MoonPixelCore

final class FrameTests: XCTestCase {
    func testFixedStepsDoNotDependOnHowFramesFall() {
        // the same 10 game seconds in steady 60 fps frames and in ragged frames
        var a = SimClock(step: 0.25, maxBacklog: 100), b = SimClock(step: 0.25, maxBacklog: 100)
        var sa: [Double] = [], sb: [Double] = []
        for _ in 0..<600 { a.add(real: 1.0 / 60, speed: 1); a.run({ true }) { sa.append($0) } }
        var rng = RNG(seed: 3), left = 10.0
        while left > 1e-9 { let d = min(left, rng.range(0.001, 0.09)); left -= d; b.add(real: d, speed: 1); b.run({ true }) { sb.append($0) } }
        XCTAssertEqual(sa.count, sb.count)
        XCTAssertTrue(Set(sa + sb) == [0.25], "never a variable or oversized step")
        XCTAssertEqual(a.simulated, b.simulated, accuracy: 1e-9)
    }

    func testBacklogIsBoundedAndDropsAreCounted() {
        var c = SimClock(step: 0.25, maxBacklog: 2)
        c.add(real: 1, speed: 64)                         // 64 game seconds asked for in one frame
        XCTAssertEqual(c.backlog, 2); XCTAssertEqual(c.dropped, 62, accuracy: 1e-9)
        var n = 0
        c.run({ n < 3 }) { _ in n += 1 }                  // the frame budget allows only three steps
        XCTAssertEqual(c.steps, 3); XCTAssertEqual(c.backlog, 1.25, accuracy: 1e-9)
        c.clear(); XCTAssertEqual(c.backlog, 0)
        XCTAssertFalse(c.take())
    }

    func testStaleBakesAreDroppedAndRequestsDeduplicated() {
        let q = BakeQueue(maxInFlight: 2)
        func k(_ c: Int64, _ r: Int, world: Int = 1, epoch: Int = 0, depth: Int = 0) -> BakeKey { BakeKey(world: world, epoch: epoch, depth: depth, chunk: c, revision: r) }
        q.want(k(1, 1), priority: 5); q.want(k(2, 1), priority: 1); q.want(k(3, 1), priority: 3)
        q.want(k(2, 1), priority: 1)                      // asked again: no second job
        XCTAssertEqual(q.deduped, 1)
        let first = q.next()
        XCTAssertEqual(first.map { $0.chunk }, [2, 3], "nearest first")
        XCTAssertTrue(q.next().isEmpty, "never more than two at a time")
        q.want(k(2, 1), priority: 0)                      // the same revision is already being baked
        XCTAssertEqual(q.wanted.count, 1)
        // chunk 3 changed while it was baking: the old result must not be shown
        XCTAssertFalse(q.finished(k(3, 1), current: k(3, 2)))
        XCTAssertTrue(q.finished(k(2, 1), current: k(2, 1)))
        // another world was opened (or Genesis wiped the map, or the player went underground)
        XCTAssertFalse(q.finished(k(1, 1), current: k(1, 1, world: 2)))
        XCTAssertFalse(k(1, 1).slot == k(1, 1, epoch: 1).slot)
        XCTAssertFalse(k(1, 1).slot == k(1, 1, depth: 1).slot)
        XCTAssertEqual(q.stale, 2); XCTAssertEqual(q.applied, 1)
        q.dropAll(); XCTAssertEqual(q.wanted.count, 0)
    }

    func testByteBudgetEvictsLeastRecentlyUsedButNeverWhatIsOnScreen() {
        let c = ByteLRU<Int, String>(budget: 300)
        c.put(1, "a", bytes: 100); c.put(2, "b", bytes: 100); c.put(3, "c", bytes: 100)
        _ = c.get(1)                                      // 1 was used again
        c.put(4, "d", bytes: 100, keep: [2])
        XCTAssertTrue(c.contains(1)); XCTAssertTrue(c.contains(2)); XCTAssertFalse(c.contains(3)); XCTAssertTrue(c.contains(4))
        XCTAssertEqual(c.bytes, 300)
        c.trim(to: 100, keep: [4])                        // memory warning
        XCTAssertEqual(c.bytes, 100); XCTAssertTrue(c.contains(4))
    }

    func testRevisionsChangeWithEveryVisibleChangeAndGenesisStartsANewEpoch() {
        let s = makeSociety(7)
        let w = s.world
        let r0 = w.revision(300, 300)
        w.setTile(2, 300 * 32 + 3, 300 * 32 + 3, s.content.tid("rock"))
        let r1 = w.revision(300, 300)
        XCTAssertGreaterThan(r1, r0)
        let id = w.addProp(key: "asset:x", at: Vec2(300 * 512 + 40, 300 * 512 + 40))
        XCTAssertGreaterThan(w.revision(300, 300), r1)
        let r2 = w.revision(300, 300)
        w.removeProp(id: id, cx: 300, cy: 300)
        XCTAssertGreaterThan(w.revision(300, 300), r2)
        let e = w.mapEpoch
        w.wipe()
        XCTAssertEqual(w.mapEpoch, e + 1)
    }

    func testOnScreenQueryWithTheIndexMatchesTheFullScan() {
        let s = makeSociety(11)
        runYears(s, 0.3)
        for t in s.settlements.values.prefix(4) {
            for (hw, hh) in [(200.0, 300.0), (600, 900), (60, 60)] {
                let a = s.crowdSplit(center: t.center.center, halfW: hw, halfH: hh, limit: 50)
                let b = s.crowdSplit(center: t.center.center, halfW: hw, halfH: hh, limit: 50, useGrid: false)
                XCTAssertEqual(a.shown.map { $0.id }, b.shown.map { $0.id })
                XCTAssertEqual(a.badges, b.badges)
            }
        }
        // after a step and after people die the index is rebuilt, never stale
        runYears(s, 0.01)
        if let v = s.agents.values.first { s.die(v, "test") }
        let c = s.settlements.values.first!.center.center
        XCTAssertEqual(s.crowdSplit(center: c, halfW: 400, halfH: 400).shown.map { $0.id }, s.crowdSplit(center: c, halfW: 400, halfH: 400, useGrid: false).shown.map { $0.id })
    }

    func testHeavyTownWorkIsSpreadOutDeterministicallyAndNobodyStarves() {
        func run() -> (maxHeavy: Int, deferredSeen: Bool, hash: String, plannedAll: Bool) {
            let s = makeSociety(5)
            for t in s.settlements.values { t.planT = 0; t.resT = 0 }       // everybody due at once, as after a load
            var mx = 0, deferred = false
            let towns = s.settlements.values.filter { !$0.abandoned }.count
            var planned = Set<Int>()
            for _ in 0..<40 {
                s.tick(0.25)
                mx = max(mx, s.heavyLast); if s.heavyDeferred > 0 { deferred = true }
                for t in s.settlements.values where t.planT > 5 { planned.insert(t.id) }
            }
            let snap = try! JSONEncoder().encode(s.snapshot())
            return (mx, deferred, "\(snap.count)-\(s.agents.count)-\(s.world.time)", planned.count >= towns)
        }
        let a = run(), b = run()
        XCTAssertLessThanOrEqual(a.maxHeavy, 2 + 1, "a burst of due towns is spread over steps")
        XCTAssertTrue(a.deferredSeen || a.maxHeavy <= 3)
        XCTAssertTrue(a.plannedAll, "every town got its plan within ten seconds")
        XCTAssertEqual(a.hash, b.hash, "same seed, same steps, same world")
    }
}
