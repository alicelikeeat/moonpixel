import XCTest
@testable import MoonPixelCore

final class BattleTests: XCTestCase {
    func stress(_ total: Int, seed: Int = 21) -> (Society, Legion, Legion) {
        let s = makeSociety(seed)
        let (a, b) = s.stageFieldBattle(perSide: total / 2)!
        return (s, s.realm.legion(a)!, s.realm.legion(b)!)
    }

    func testTiersDrawOnlyRealSoldiersAndCountTheRestAtTheirArmy() {
        for total in [50, 100, 200, 400] {
            let (s, a, b) = stress(total)
            for _ in 0..<5 { s.tick(0.5) }                       // let the ranks form
            let c = (a.pos + b.pos) * 0.5
            for limit in RenderBudget.tiers {
                let v = s.battleView(center: c, halfW: 700, halfH: 500, limit: limit)
                XCTAssertLessThanOrEqual(v.shown.count, limit)
                XCTAssertEqual(v.shown.count, min(limit, v.onScreen), "\(total)/\(limit): the budget is used, not wasted")
                for x in v.shown {
                    XCTAssertNotNil(s.agents[x.id], "a living resident")
                    XCTAssertTrue(x.legion == a.id || x.legion == b.id, "a member of an army in the field")
                    XCTAssertTrue((s.realm.legion(x.legion!)?.members ?? []).contains(x.id))
                }
                XCTAssertEqual(Set(v.shown.map { $0.id }).count, v.shown.count, "nobody drawn twice")
                let hidden = v.masses.reduce(0) { $0 + $1.hidden }
                XCTAssertEqual(v.shown.count + hidden, v.onScreen, "drawn + counted = everyone in view")
                for m in v.masses {
                    let lg = s.realm.legion(m.legion)!
                    XCTAssertEqual(m.pos, lg.pos, "the rest are shown at the battlefield, not at home")
                }
            }
            // the civilian crowd leaves field soldiers to the battle view
            XCTAssertTrue(s.crowdSplit(center: c, halfW: 700, halfH: 500, limit: 400, soldiersApart: true).shown.allSatisfy { $0.legion == nil || s.realm.legion($0.legion!)?.state == 0 })
        }
    }

    func testBigArmiesStandInRealRanksNotOnePile() {
        let (s, a, _) = stress(400)
        for _ in 0..<20 { s.tick(0.5) }
        let spots = Set(a.members.compactMap { s.agents[$0] }.map { TilePos(Int($0.pos.x / 4), Int($0.pos.y / 4)) })
        XCTAssertGreaterThan(spots.count, a.members.count * 6 / 10, "most soldiers have a place of their own")
    }

    func testFrontLineFirstAndNoFlicker() {
        let (s, a, b) = stress(400)
        for _ in 0..<10 { s.tick(0.5) }
        let c = (a.pos + b.pos) * 0.5
        let v1 = s.battleView(center: c, halfW: 700, halfH: 500, limit: 50)
        // the drawn soldiers stand nearer the enemy than the army's average
        func meanFoe(_ xs: [Agent]) -> Double { xs.map { $0.pos.distance(to: $0.legion == a.id ? b.pos : a.pos) }.reduce(0, +) / Double(max(1, xs.count)) }
        let all = (a.members + b.members).compactMap { s.agents[$0] }
        XCTAssertLessThan(meanFoe(v1.shown), meanFoe(all))
        s.tick(0.5)
        let v2 = s.battleView(center: c + Vec2(12, 0), halfW: 700, halfH: 500, limit: 50, previous: Set(v1.shown.map { $0.id }))
        let kept = Set(v1.shown.map { $0.id }).intersection(v2.shown.map { $0.id }).count
        XCTAssertGreaterThanOrEqual(kept, 45, "a small step and a tick change very few of the drawn soldiers")
    }

    /// The same battle, watched up close, from far away and not at all, gives the same dead and the same world.
    func testResultsDoNotDependOnTheCameraAndTheLedgerIsTheTruth() {
        func run(_ watch: Int) -> (String, CasualtyLedger, Int) {
            let (s, a, b) = stress(200)
            let battle0 = s.stats.captured ?? 0
            for i in 0..<240 {
                switch watch {
                case 0: s.viewer = (a.pos + b.pos) * 0.5
                    _ = s.battleView(center: s.viewer!, halfW: 600, halfH: 400, limit: [50, 100, 200, 400][i % 4])
                case 1: s.viewer = Vec2(-40000, -40000)
                default: s.viewer = nil
                }
                s.tick(0.5)
            }
            let l = s.realm.ledger
            // nobody is killed in war: every soldier lost is a prisoner, and each is in the ledger once
            XCTAssertEqual(l.total, (s.stats.captured ?? 0) - battle0 + 0, "every prisoner is in the ledger once")
            XCTAssertEqual(s.stats.battle ?? 0, 0, "nobody died in battle")
            for lg in [a, b] {
                let gone = lg.startN - lg.members.filter { s.agents[$0] != nil }.count
                let key = "field:\(min(a.id, b.id))-\(max(a.id, b.id))"
                let inLedger = l.battles.first { $0.key == key }?.losses["\(lg.nation)"] ?? 0
                XCTAssertLessThanOrEqual(inLedger, gone)
                XCTAssertGreaterThan(inLedger, 0, "people fell on both sides")
            }
            return (snapshotJSON(s), l, s.agents.count)
        }
        let near = run(0), far = run(1), none = run(2)
        XCTAssertEqual(near.1, far.1); XCTAssertEqual(far.1, none.1)
        XCTAssertEqual(near.2, none.2)
        XCTAssertEqual(near.0, none.0, "watching changes nothing in the world")
        XCTAssertEqual(far.0, none.0)
    }

    func testDecorationGoesBeforeSoldiersAndComesBackSlowly() {
        var b = RenderBudget()
        XCTAssertEqual(b.soldiers, 400); XCTAssertEqual(b.effectCap, 120)
        var seen: [(Int, Int)] = []
        for _ in 0..<400 { b.update(p95: 30, dt: 0.1); if seen.last.map({ $0 != (b.soldiers, b.effectCap) }) ?? true { seen.append((b.soldiers, b.effectCap)) } }
        XCTAssertEqual(seen.map { $0.1 }.prefix(3), [120, 80, 40], "effects are cut first")
        XCTAssertTrue(seen.prefix(3).allSatisfy { $0.0 == 400 }, "while every soldier is still drawn")
        XCTAssertEqual(b.soldiers, 50)
        // frames alternate good / bad: nothing changes
        let held = b
        for i in 0..<100 { b.update(p95: i % 2 == 0 ? 25 : 10, dt: 0.1) }
        XCTAssertEqual(b.level, held.level)
        // good frames: back up one level every few seconds, never a jump
        b.update(p95: 10, dt: 3.7); XCTAssertEqual(b.level, held.level)
        b.update(p95: 10, dt: 0.4); XCTAssertEqual(b.level, held.level + 1)
        b.pin(soldiers: 200); XCTAssertEqual(b.soldiers, 200)
    }

    func testOldSavesWithoutALedgerLoadAndTheLedgerIsSaved() throws {
        let (s, _, _) = stress(100)
        for _ in 0..<120 { s.tick(0.5) }
        XCTAssertGreaterThan(s.realm.ledger.total, 0)
        let data = try JSONEncoder().encode(s.realm)
        let back = try JSONDecoder().decode(Realm.self, from: data)
        XCTAssertEqual(back.ledger, s.realm.ledger)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj["ledgerBox"] = nil
        let old = try JSONDecoder().decode(Realm.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(old.ledger.total, 0)
    }

    /// Real timings of picking what to draw and simulating, per tier (on whatever machine runs the tests).
    func testStressTimings() {
        var lines: [String] = []
        for total in [50, 100, 200, 400] {
            let (s, a, b) = stress(total)
            for _ in 0..<4 { s.tick(0.5) }
            let c = (a.pos + b.pos) * 0.5
            var prev = Set<Int>()
            let t0 = Date()
            for _ in 0..<60 { prev = Set(s.battleView(center: c, halfW: 700, halfH: 500, limit: total, previous: prev).shown.map { $0.id }) }
            let pick = Date().timeIntervalSince(t0) / 60 * 1000
            let t1 = Date()
            for _ in 0..<60 { s.tick(1.0 / 60) }
            let tick = Date().timeIntervalSince(t1) / 60 * 1000
            lines.append(String(format: "STRESS soldiers=%d pick=%.3fms tick=%.3fms", total, pick, tick))
        }
        print(lines.joined(separator: "\n"))
    }
}
