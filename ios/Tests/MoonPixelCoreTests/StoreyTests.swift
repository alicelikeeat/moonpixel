import XCTest
@testable import MoonPixelCore

/// Real storeys above the ground: air is not walked on, floors stand on walls below, stairs go up and down,
/// any number of storeys can be built, they are saved, and they are drawn at their height.
final class StoreyTests: XCTestCase {
    var nextPlan = 1
    func build(_ s: Society, _ piece: String, _ cells: [TilePos], on w: OpenWorld, file: StaticString = #file, line: UInt = #line) -> BuildResult {
        s.realm.player.wood = 1e6; s.realm.player.stone = 1e6
        nextPlan += 1
        return s.commitBuild(BuildPlan(id: nextPlan, piece: piece, cells: cells), in: w)
    }
    /// A clear patch of land near the first town.
    func site(_ s: Society) -> TilePos {
        let t = s.settlements.values.sorted { $0.id < $1.id }.first!.center
        return s.world.findSite(from: t, minR: 60, maxR: 140, salt: 4242, avoid: s.settlements.values.map { $0.center }, avoidDist: 30)
    }

    func testStairsGoUpToARealFloorAndAirIsNotWalkedOn() {
        let s = makeSociety(5)
        let o = site(s)
        let w = s.world
        // four walls round a room, a stair up inside
        let walls = (0...6).flatMap { [TilePos(o.x + $0, o.y), TilePos(o.x + $0, o.y + 6), TilePos(o.x, o.y + $0), TilePos(o.x + 6, o.y + $0)] }
        XCTAssertGreaterThan(build(s, "wall_stone", walls, on: w).placed, 10)
        let stair = TilePos(o.x + 3, o.y + 3)
        XCTAssertEqual(build(s, "stairs_up", [stair], on: w).placed, 1)
        s.realm.player.depth = 0
        guard let up = s.useStairs(at: stair.center) else { return XCTFail("the stair did not take us up") }
        XCTAssertEqual(up.depth, OpenWorld.storeyBase + 1)
        let s1 = s.storeyWorld(1)
        XCTAssertFalse(s1.blocked(up.pos.tile.x, up.pos.tile.y), "standing on the landing")
        XCTAssertEqual(s1.tile(2, stair.x, stair.y), s.content.tid("stairs_down"), "a stair back down where we came up")
        XCTAssertTrue(s1.blocked(o.x + 30, o.y + 30), "air far from any floor holds nobody")
        XCTAssertEqual(s.realm.storeyTop, 1)
        // back down
        guard let down = s.useStairs(at: stair.center) else { return XCTFail("no way down") }
        XCTAssertEqual(down.depth, 0)
        XCTAssertEqual(s.realm.player.depth, 0)
    }

    func testFloorsNeedSomethingUnderThemAndThingsNeedAFloor() {
        let s = makeSociety(5)
        let o = site(s)
        _ = build(s, "wall_stone", (0...4).map { TilePos(o.x + $0, o.y) }, on: s.world)
        _ = build(s, "stairs_up", [TilePos(o.x + 2, o.y + 1)], on: s.world)
        _ = s.useStairs(at: TilePos(o.x + 2, o.y + 1).center)
        let s1 = s.storeyWorld(1)
        XCTAssertEqual(s.placeProblem("wood_floor", layer: 0, onWater: false, at: TilePos(o.x + 2, o.y + 3), in: s1, nation: 0), "", "three tiles from the wall below: it holds")
        XCTAssertEqual(s.placeProblem("wood_floor", layer: 0, onWater: false, at: TilePos(o.x + 2, o.y + 9), in: s1, nation: 0), "unsupported", "too far out: nothing holds it")
        XCTAssertEqual(s.placeProblem("wall_wood", layer: 2, onWater: false, at: TilePos(o.x + 20, o.y + 20), in: s1, nation: 0), "no_floor", "no wall on thin air")
        _ = build(s, "floor_wood", (0...4).map { TilePos(o.x + $0, o.y + 2) }, on: s1)
        XCTAssertTrue((0...4).allSatisfy { s1.tile(0, o.x + $0, o.y + 2) != 0 }, "the floor reaches along the wall (the landing was already floor)")
        XCTAssertEqual(build(s, "bed", [TilePos(o.x + 1, o.y + 2)], on: s1).placed, 1, "a bed upstairs")
    }

    func testTenStoreysUpAndAllTheWayDownAgain() {
        let s = makeSociety(6)
        let o = site(s)
        var w = s.world
        s.realm.player.depth = 0
        for n in 0..<10 {
            // walls on this level carry the floor of the next; a stair leads up
            _ = build(s, "wall_stone", (0...4).map { TilePos(o.x + $0, o.y) }, on: w)
            // each stair up stands beside the stair that came up (on the landing), not on it
            let at = TilePos(o.x + 2, o.y + 1 + n % 2)
            XCTAssertEqual(build(s, "stairs_up", [at], on: w).placed, 1, "stair on level \(n)")
            guard let up = s.useStairs(at: at.center) else { return XCTFail("stuck on level \(n)") }
            XCTAssertEqual(up.depth, OpenWorld.storeyBase + n + 1)
            w = s.storeyWorld(n + 1)
            // a floor along the wall's line, for the next wall to stand on
            _ = build(s, "floor_wood", (0...4).map { TilePos(o.x + $0, o.y) }, on: w)
        }
        XCTAssertEqual(s.realm.storeyTop, 10)
        XCTAssertEqual(s.builtStoreys().count, 10)
        for n in stride(from: 10, through: 1, by: -1) {
            // the stair down on storey n is where the stair up of level n - 1 stood
            guard let d = s.useStairs(at: TilePos(o.x + 2, o.y + 1 + (n - 1) % 2).center) else { return XCTFail("cannot get down from \(n)") }
            XCTAssertEqual(d.depth, n == 1 ? 0 : OpenWorld.storeyBase + n - 1)
        }
        XCTAssertEqual(s.realm.player.depth, 0, "back on the ground")
    }

    func testStoreysAreSavedAndDrawnAtTheirHeight() {
        let dir = tempDir("storeys")
        let s = makeSociety(5, dir: dir)
        let o = site(s)
        _ = build(s, "wall_stone", (0...4).map { TilePos(o.x + $0, o.y) }, on: s.world)
        _ = build(s, "stairs_up", [TilePos(o.x + 2, o.y + 1)], on: s.world)
        let s1 = s.storeyWorld(1)
        _ = build(s, "floor_wood", (0...4).map { TilePos(o.x + $0, o.y + 2) }, on: s1)
        s.world.saveAll(); s1.saveAll()
        XCTAssertNoThrow(try s.world.store!.commit(index: Data("{}".utf8), meta: Data()), "one commit holds the ground and the storeys")
        // a fresh world on the same folder finds the storey again
        let w2 = OpenWorld(seed: s.world.seed, budget: MemoryBudget(overrideMB: 256))
        w2.open(directory: dir)
        let up2 = OpenWorld(seed: s.world.seed, budget: MemoryBudget(overrideMB: 256), depth: OpenWorld.storeyBase + 1)
        up2.open(store: w2.store!)
        XCTAssertEqual(up2.tile(0, o.x + 1, o.y + 2), s.content.tid("wood_floor"), "the floor upstairs was kept")
        XCTAssertEqual(up2.tile(2, o.x + 2, o.y + 1), s.content.tid("stairs_down"))
        // the storey's mesh: slabs only where there is floor, two tiles above the ground under it
        let cx = (o.x + 1) >> 5, cy = (o.y + 2) >> 5
        let mesh = Mesher3D.build(ChunkInput3D(world: s1, cx: cx, cy: cy), gen: s1.gen)
        let i = ((o.y + 2) & 31) * 32 + ((o.x + 1) & 31)
        let ground = Terrain3D.groundY(world: s.world, at: TilePos(o.x + 1, o.y + 2).center)
        XCTAssertEqual(mesh.heights[i], ground + Float(Terrain3D.storeyLevels) * Terrain3D.step, accuracy: 0.01, "one storey up")
        XCTAssertEqual(mesh.heights[((o.y + 20) & 31) * 32 + ((o.x + 20) & 31)], Mesher3D.air, "air elsewhere")
        XCTAssertFalse(mesh.ground.isEmpty); XCTAssertFalse(mesh.solid.isEmpty)
        XCTAssertLessThan(mesh.ground.positions.count, 4 * 40, "only the floors are drawn, not a whole plane of air")
    }

    func testAFourStoreyHouseStandsByTheRulesAndCanBeClimbed() {
        let s = makeSociety(5)
        let o = site(s)
        let stairs = s.raiseHouse(at: o, storeys: 4)
        XCTAssertEqual(stairs.count, 3)
        XCTAssertEqual(s.realm.storeyTop, 3)
        for n in 1...3 {
            let w = s.storeyWorld(n)
            for y in 0..<7 { for x in 0..<7 {
                let t = TilePos(o.x + x, o.y + y)
                XCTAssertNotEqual(w.tile(0, t.x, t.y), 0, "a floor across storey \(n)")
                XCTAssertTrue(s.supported(t, onStorey: n), "every floor of storey \(n) is carried")
            } }
            XCTAssertEqual(w.tile(2, o.x + 1, o.y + 1), s.content.tid("bed"), "beds on storey \(n)")
        }
        s.realm.player.depth = 0
        var at = stairs[0]
        for n in 1...3 {
            guard let r = s.useStairs(at: at.center) else { return XCTFail("stuck below storey \(n)") }
            XCTAssertEqual(r.depth, OpenWorld.storeyBase + n)
            if n < 3 { at = stairs[n] }
        }
    }

    func testTakingAwayWhatCarriesAFloorBringsItDown() {
        let s = makeSociety(5)
        let o = site(s)
        for dx in -1...9 { s.world.setTile(2, o.x + dx, o.y, 0); s.world.setTile(3, o.x + dx, o.y, 0) }   // clear ground
        XCTAssertEqual(build(s, "wall_stone", [TilePos(o.x, o.y)], on: s.world).placed, 1)
        XCTAssertEqual(build(s, "stairs_up", [TilePos(o.x + 8, o.y)], on: s.world).placed, 1)          // a way up, well away from the wall
        let s1 = s.storeyWorld(1)
        XCTAssertEqual(build(s, "floor_wood", [TilePos(o.x, o.y), TilePos(o.x + 1, o.y)], on: s1).placed, 2)
        _ = build(s, "bed", [TilePos(o.x + 1, o.y)], on: s1)
        XCTAssertNotNil(s.demolishBuild(at: TilePos(o.x, o.y), in: s.world), "the wall under it is taken down")
        XCTAssertEqual(s1.tile(0, o.x, o.y), 0, "the floor it carried fell")
        XCTAssertEqual(s1.tile(2, o.x + 1, o.y), 0, "with the bed on it")
        XCTAssertNotEqual(s1.tile(0, o.x + 8, o.y), 0, "the landing by the stair still stands")
        // the stair itself taken down: its landing and the stair down go too
        XCTAssertNotNil(s.demolishBuild(at: TilePos(o.x + 8, o.y), in: s.world))
        XCTAssertEqual(s1.tile(2, o.x + 8, o.y), 0)
        XCTAssertEqual(s1.tile(0, o.x + 8, o.y), 0)
    }

    func testATownShortOfHomesBuildsUpwardsAndFamiliesMoveUpstairs() {
        let s = makeSociety(7)
        runYears(s, 1.5)
        guard let town = s.settlements.values.filter({ !$0.abandoned }).max(by: { $0.buildings.filter { $0.type == "house" && $0.done }.count < $1.buildings.filter { $0.type == "house" && $0.done }.count }) else { return XCTFail("no town") }
        let houses = town.buildings.filter { $0.type == "house" && $0.done }
        guard houses.count >= 1 else { return XCTFail("no finished house") }
        town.wood = 100; town.stone = 100
        XCTAssertTrue(s.addStorey(town, houses), "a storey goes on")
        let b = houses.min { ($0.id) < ($1.id) }!
        let raised = houses.first { ($0.levels ?? 1) == 2 }!
        _ = b
        XCTAssertEqual(town.wood, 88); XCTAssertEqual(town.stone, 94)
        let s1 = s.storeyWorld(1)
        for dy in 0..<raised.h { for dx in 0..<raised.w {
            XCTAssertNotEqual(s1.tile(0, raised.x + dx, raised.y + dy), 0, "a real floor over the whole house")
            XCTAssertTrue(s.supported(TilePos(raised.x + dx, raised.y + dy), onStorey: 1))
        } }
        XCTAssertEqual(raised.cap, 8, "room for another family")
        // a family without a house takes the upper storey
        for other in houses where other !== raised { other.owner = other.owner ?? -999 }
        runYears(s, 0.3)
        XCTAssertEqual(s.audit(), [])
        if let up = raised.upstairs?.first { XCTAssertTrue(raised.residents.contains { s.agents[$0].map { s.household($0, s.world.time) } == up }, "they are residents of the house") }
    }
}
