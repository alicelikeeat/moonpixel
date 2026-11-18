import XCTest
@testable import MoonPixelCore

/// A regional tower standing in a town is as tall as the tower is, and nothing about it costs more
/// because it is tall: only the storeys someone is on, looks at or changed are made.
final class TallTowerTests: XCTestCase {
    func stand(_ s: Society, levels: Int, at o: TilePos) {
        s.realm.standing = [StandingTower(tower: 1, city: 1, town: 1, x: o.x, y: o.y, w: 12, d: 10, levels: levels)]
        s.raiseHouse(at: o, storeys: 2, w: 12, d: 10)
        s.realm.storeyTop = levels - 1
    }

    func testTheTopOfA400LevelTowerIsRealAndNothingUnderItIsMade() {
        let s = makeSociety(4)
        let o = s.world.findFree(near: TilePos(300, 300), maxR: 20)
        stand(s, levels: 400, at: o)
        let built0 = s.builtStoreys().count
        let top = s.storeyWorld(399)
        XCTAssertEqual(top.tile(0, o.x + 5, o.y + 5), s.content.tid("wood_floor"), "a floor on the 400th level")
        XCTAssertEqual(top.tile(2, o.x, o.y), s.content.tid(Society.towerFacade(1).wall), "walls round it (the tower's own material)")
        XCTAssertFalse(top.blocked(o.x + 5, o.y + 5), "you can stand there")
        XCTAssertTrue(top.blocked(o.x - 3, o.y + 5), "beside the tower is open air")
        let down = Society.towerStair(s.realm.standing![0], level: 398)
        XCTAssertEqual(top.tile(2, down.x, down.y), s.content.tid("stairs_down"), "the stair down is there")
        XCTAssertLessThanOrEqual(s.storeys.count, 2, "storeys 2...398 were never made (v2.5 built 40 levels and no more)")
        XCTAssertEqual(s.builtStoreys().count, built0, "looking is not building: no storey was added to the saved set")
        XCTAssertEqual(s.storeysNear(399, span: 6).count, 7, "what is drawn round you does not grow with the height")
        XCTAssertEqual(s.storeysNear(200, span: 6), Array(194...206))
        // the middle storeys exist too, each by itself
        XCTAssertEqual(s.storeyWorld(250).tile(0, o.x + 5, o.y + 5), s.content.tid("wood_floor"))
        XCTAssertEqual(s.storeyWorld(400).tile(0, o.x + 5, o.y + 5), 0, "nothing above the top")
    }

    func testAChangeHighUpIsKeptAndTheSavedSetStaysSparse() throws {
        let u = tempDir("tall")
        let s = makeSociety(4, dir: u)
        let o = s.world.findFree(near: TilePos(300, 300), maxR: 20)
        stand(s, levels: 1000, at: o)
        let w = s.storeyWorld(700)
        w.setTile(2, o.x + 4, o.y + 4, s.content.tid("chest"))
        XCTAssertEqual(s.builtStoreys().filter { $0 > 2 }, [700], "storey 700 is in the set; 3...699 are not")
        for n in s.builtStoreys() { s.storeyWorld(n).saveAll() }
        s.world.saveAll()
        try s.world.store!.commit(index: try JSONEncoder().encode(s.snapshot()), meta: Data())
        // reopen
        let w2 = OpenWorld(seed: 4, budget: MemoryBudget(overrideMB: 256)); w2.open(directory: u)
        let back = try JSONDecoder().decode(Society.Snapshot.self, from: w2.store!.readIndex()!)
        let s2 = Society(world: w2, seed: 4); s2.restore(back)
        XCTAssertEqual(s2.realm.standing, s.realm.standing)
        XCTAssertEqual(s2.storeyWorld(700).tile(2, o.x + 4, o.y + 4), s.content.tid("chest"), "the change on storey 700 is still there")
        XCTAssertEqual(s2.storeyWorld(701).tile(0, o.x + 5, o.y + 5), s.content.tid("wood_floor"), "the storey above is still the tower's own")
        XCTAssertLessThan(s2.builtStoreys().count, 10)
    }

    func testTheTowerGrowsAndShrinksFromTheRegionalCount() {
        let s = makeSociety(5)
        let c = s.civ
        let home = Blueprint.plan(use: .home, w: 12, d: 10, layout: 0, seed: 1)
        c.towerIndex.plans[home.key] = home
        let t = Tower(base: Cell3(0, 0, 0)); t.id = c.towerIndex.nextTower; c.towerIndex.nextTower += 1
        t.floors = (0..<60).map { var f = TowerFloor(z: Int64($0 * 4), plan: home.key); f.stage = .inUse; return f }
        c.towerIndex.towers[t.id] = t
        let o = s.world.findFree(near: TilePos(300, 300), maxR: 20)
        s.realm.standing = [StandingTower(tower: t.id, city: 1, town: 1, x: o.x, y: o.y, w: 12, d: 10, levels: 60)]
        XCTAssertNotEqual(s.storeyWorld(59).tile(0, o.x + 5, o.y + 5), 0)
        XCTAssertEqual(s.storeyWorld(75).tile(0, o.x + 5, o.y + 5), 0)
        t.floors += (60..<80).map { var f = TowerFloor(z: Int64($0 * 4), plan: home.key); f.stage = .inUse; return f }
        s.refreshStanding(c)
        XCTAssertEqual(s.realm.standing?[0].levels, 80)
        XCTAssertNotEqual(s.storeyWorld(75).tile(0, o.x + 5, o.y + 5), 0, "the new floors are there (v2.5 never went past 40)")
        let st = Society.towerStair(s.realm.standing![0], level: 59)
        XCTAssertEqual(s.storeyWorld(59).tile(2, st.x, st.y), s.content.tid("stairs_up"), "the old top now has a stair up")
    }

    func testGuixuTakesAStandingTowerAwayAllTheWayUp() {
        let s = makeSociety(4)
        let o = s.world.findFree(near: TilePos(300, 300), maxR: 20)
        stand(s, levels: 300, at: o)
        XCTAssertNotEqual(s.storeyWorld(250).tile(0, o.x + 5, o.y + 5), 0)
        var plan = LawPlan(mode: .guixu, seed: 1)
        plan.chunks = [ChunkRef(cx: o.x >> 5, cy: o.y >> 5)]
        if (o.x + 11) >> 5 != o.x >> 5 { plan.chunks.append(ChunkRef(cx: (o.x + 11) >> 5, cy: o.y >> 5)) }
        if (o.y + 9) >> 5 != o.y >> 5 { plan.chunks += plan.chunks.map { ChunkRef(cx: $0.cx, cy: (o.y + 9) >> 5) } }
        let run = s.beginLaw(plan); while !run.step(64) {}
        XCTAssertNil(s.realm.standing, "the tower is gone from the record")
        XCTAssertEqual(s.storeyWorld(250).tile(0, o.x + 5, o.y + 5), 0, "nothing is left hanging in the air on storey 250")
        XCTAssertEqual(s.storeyWorld(1).tile(0, o.x + 5, o.y + 5), 0)
    }

    func testStoreysPassedThroughAreLetGoButBuiltOnesAreKept() {
        let s = makeSociety(4)
        let o = s.world.findFree(near: TilePos(300, 300), maxR: 20)
        stand(s, levels: 200, at: o)
        for n in stride(from: 1, to: 200, by: 1) { _ = s.storeyWorld(n).tile(0, o.x + 5, o.y + 5) }
        s.storeyWorld(150).setTile(2, o.x + 4, o.y + 4, s.content.tid("chest"))
        XCTAssertEqual(s.storeys.count, 199)
        s.trimStoreys(around: 0, span: 8)
        XCTAssertLessThanOrEqual(s.storeys.count, 8 + 1 + 2, "near ones, and storey 150 which holds a change")
        XCTAssertNotNil(s.storeys[150])
        XCTAssertEqual(s.storeyWorld(120).tile(0, o.x + 5, o.y + 5), s.content.tid("wood_floor"), "a let-go storey is made again the same")
        XCTAssertEqual(s.storeyWorld(150).tile(2, o.x + 4, o.y + 4), s.content.tid("chest"))
    }
}
