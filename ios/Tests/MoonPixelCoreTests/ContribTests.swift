import XCTest
@testable import MoonPixelCore

final class ContribTests: XCTestCase {
    func kinds(_ s: Society) -> [String] { s.realm.contrib.list.map { $0.kind } }
    func strengthen(_ s: Society, _ nation: Int, soldiers: Int) {
        for t in s.towns(of: nation) {
            let g = s.garrison(t, create: true)!
            g.nation = nation
            for a in t.members.compactMap({ s.agents[$0] }).sorted(by: { $0.id < $1.id }) where a.legion == nil && a.stage(s.world.time) == "adult" && g.members.count < soldiers { s.enlist(a, g) }
        }
    }

    func cutByRiver(_ s: Society) -> (Settlement, Settlement, [TilePos]) {
        let a = s.towns(of: 1)[0], b = s.towns(of: 2)[0]
        let mid = TilePos((a.center.x + b.center.x) / 2, (a.center.y + b.center.y) / 2)
        let horizontal = abs(b.center.x - a.center.x) >= abs(b.center.y - a.center.y)
        for k in -500...500 { for w in 0..<3 {
            let t = horizontal ? TilePos(mid.x + w, mid.y + k) : TilePos(mid.x + k, mid.y + w)
            s.world.setTile(0, t.x, t.y, s.content.tid("water")); s.world.setTile(1, t.x, t.y, 0); s.world.setTile(2, t.x, t.y, 0)
        } }
        let span = (0..<3).map { horizontal ? TilePos(mid.x + $0, mid.y) : TilePos(mid.x, mid.y + $0) }
        return (a, b, span)
    }

    func testABridgeThatReopensTheRoadIsCreditedOnceWithWhatChanged() throws {
        let s = makeSociety(7)
        runYears(s, 0.2)
        let (a, b, span) = cutByRiver(s)
        XCTAssertNotEqual(s.planMarch(from: a.center, to: b.center, budget: 20000).status, .complete, "the river really cuts the road")
        s.carry("wood", 100); s.carry("stone", 100)
        let rep0 = s.realm.nation(a.nation!)!.rep
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 1, piece: "bridge", cells: span)).placed, 3)
        XCTAssertEqual(kinds(s), ["transport_restored"])
        let c = s.realm.contrib.list[0]
        XCTAssertNotEqual(c.before, c.after); XCTAssertTrue(c.after.hasPrefix("complete"))
        XCTAssertGreaterThan(s.realm.nation(a.nation!)!.rep, rep0)
        // the same plan sent again (a double tap, a replay) is refused before anything happens
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 1, piece: "bridge", cells: span)).reason, "duplicate")
        // break it and mend it in the same year: the road was restored once this year, so no second reward
        for t in span { s.demolishBuild(at: t) }
        s.carry("wood", 100)
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 2, piece: "bridge", cells: span)).placed, 3)
        XCTAssertEqual(kinds(s).count, 1)
        // after a save and reload the credit is still known
        let back = try JSONDecoder().decode(Realm.self, from: JSONEncoder().encode(s.realm))
        XCTAssertEqual(back.contrib, s.realm.contrib)
        // a bridge where no road was cut changes nothing and earns nothing
        let s2 = makeSociety(7); runYears(s2, 0.2); s2.carry("wood", 100)
        let far = s2.world.findFree(near: TilePos(4000, 4000), maxR: 8)
        _ = s2.commitBuild(BuildPlan(id: 1, piece: "bridge", cells: [far]))
        XCTAssertTrue(s2.realm.contrib.list.isEmpty)
    }

    func testFoodEndsAShortageOnlyWhenItReallyDoes() {
        let s = makeSociety(8)
        let t = s.towns(of: 1)[0]
        t.food = 0
        XCTAssertTrue(s.shortage(t))
        s.realm.player.food = 5
        s.playerDonate(sid: t.id, kind: "food", amount: 5)          // not enough: still short
        XCTAssertTrue(s.realm.contrib.list.isEmpty)
        s.realm.player.food = 1000
        s.playerDonate(sid: t.id, kind: "food", amount: 1000)
        XCTAssertEqual(kinds(s), ["shortage_relieved"])
        s.playerDonate(sid: t.id, kind: "food", amount: 0)
        // a town that was never short gets food: nothing to credit
        let u = s.towns(of: 2)[0]; u.food = 5000; s.realm.player.food = 50
        s.playerDonate(sid: u.id, kind: "food", amount: 50)
        XCTAssertEqual(kinds(s).count, 1)
        // short again in the same year: helped once already
        t.food = 0; s.realm.player.food = 1000; s.playerDonate(sid: t.id, kind: "food", amount: 1000)
        XCTAssertEqual(kinds(s).count, 1)
        // next year it counts again
        s.world.time += MP.year
        t.food = 0; s.realm.player.food = 1000; s.playerDonate(sid: t.id, kind: "food", amount: 1000)
        XCTAssertEqual(kinds(s), ["shortage_relieved", "shortage_relieved"])
    }

    func testRefugeesTakenInAreCreditedAndCannotBeTakenInTwice() {
        let s = makeSociety(9)
        let src = s.towns(of: 2)[0]
        let people = src.members.prefix(4).compactMap { s.agents[$0] }
        for a in people { a.refugee = s.world.time + 1e6 }
        let t = s.towns(of: 1)[0]
        let n = s.playerAcceptRefugees(sid: t.id)
        XCTAssertEqual(n, 4)
        XCTAssertEqual(kinds(s), ["refugees_taken_in"])
        XCTAssertEqual(s.playerAcceptRefugees(sid: t.id), 0)
        XCTAssertEqual(kinds(s).count, 1)
    }

    func testConvoysEscortedThroughDangerAndConvoysCutDown() {
        // a convoy of the player's nation, escorted most of the way, with an enemy army close by
        let s = makeSociety(7)
        strengthen(s, 1, soldiers: 12)
        for t in s.towns(of: 1) { t.food = 900 }
        s.refreshNations(); s.realm.relations[0].since = -1e9
        s.declare(1, on: 2)
        let lg = s.realm.legions.first { $0.nation == 1 && $0.state == 1 }!
        s.playerJoin(1)
        let enemy = Legion(); enemy.id = 900; enemy.nation = 2; enemy.state = 1; enemy.home = s.towns(of: 2)[0].id
        s.realm.legions.append(enemy)
        lg.food = 0.5; lg.convoyT = 0
        var steps = 0
        s.stepLegion(lg, 2)
        XCTAssertNotNil(lg.convoyAt)
        while lg.convoyAt != nil && steps < 600 {
            // the player rides with the train; an enemy army shadows it
            let h = s.settlements[lg.home]!.center.center
            let p = s.point(on: [h] + (lg.route ?? [lg.pos]).prefix(max(1, (lg.routeI ?? 0) + 1)) + [lg.pos], at: min(1, lg.convoyAt ?? 0))
            s.viewer = p; enemy.pos = p + Vec2(300, 0)
            s.stepLegion(lg, 2); s.world.time += 2; steps += 1
        }
        XCTAssertEqual(kinds(s).filter { $0 == "convoy_protected" }.count, 1, "delivered under threat with the player at its side")
        // a convoy nobody guarded is not the player's deed
        let s2 = makeSociety(7)
        strengthen(s2, 1, soldiers: 12)
        for t in s2.towns(of: 1) { t.food = 900 }
        s2.refreshNations(); s2.realm.relations[0].since = -1e9
        s2.declare(1, on: 2)
        let l2 = s2.realm.legions.first { $0.nation == 1 && $0.state == 1 }!
        s2.playerJoin(1); s2.viewer = Vec2(-90000, -90000)
        l2.food = 0.5; l2.convoyT = 0
        for _ in 0..<600 where l2.convoyAt != nil || steps == 0 { s2.stepLegion(l2, 2); s2.world.time += 2 }
        XCTAssertTrue(s2.realm.contrib.list.isEmpty)
        // the player (of the other side) cuts down the carriers: the convoy is lost and that is credited once
        let s3 = makeSociety(7)
        strengthen(s3, 1, soldiers: 12)
        for t in s3.towns(of: 1) { t.food = 900 }
        s3.refreshNations(); s3.realm.relations[0].since = -1e9
        s3.declare(1, on: 2)
        let l3 = s3.realm.legions.first { $0.nation == 1 && $0.state == 1 }!
        l3.food = 0.5; l3.convoyT = 0
        s3.stepLegion(l3, 2)
        XCTAssertNotNil(l3.convoyAt)
        s3.playerJoin(2)
        for id in l3.members where s3.agents[id]?.unit == Unit.supply { l3.raidT = s3.world.time; s3.die(s3.agents[id]!, "battle") }
        s3.stepLegion(l3, 2)
        XCTAssertNil(l3.convoyAt)
        XCTAssertEqual(kinds(s3), ["convoy_raided"])
        s3.stepLegion(l3, 2)
        XCTAssertEqual(kinds(s3).count, 1)
    }

    func testRetakingTheOldCapitalWithThePlayerThere() {
        let s = makeSociety(14)
        runYears(s, 0.3)
        let t = s.towns(of: 1)[0]
        t.nation = 2; t.formerCapital = 1
        s.playerJoin(1)
        s.viewer = t.center.center
        let lg = Legion(); lg.id = s.realm.nextLegion; s.realm.nextLegion += 1; lg.nation = 1; lg.home = t.id; lg.state = 2; lg.pos = t.center.center
        s.realm.legions.append(lg)
        s.capture(t, by: lg)
        XCTAssertEqual(kinds(s), ["capital_retaken"])
        XCTAssertEqual(s.realm.contrib.list[0].before, "owner 2"); XCTAssertEqual(s.realm.contrib.list[0].after, "owner 1")
        // lost and retaken again the same year: once
        t.nation = 2
        let lg2 = Legion(); lg2.id = s.realm.nextLegion; s.realm.nextLegion += 1; lg2.nation = 1; lg2.home = t.id; lg2.state = 2; lg2.pos = t.center.center
        s.realm.legions.append(lg2)
        s.capture(t, by: lg2)
        XCTAssertEqual(kinds(s).count, 1)
    }
}
