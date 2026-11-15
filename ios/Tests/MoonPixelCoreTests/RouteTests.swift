import XCTest
@testable import MoonPixelCore

final class RouteTests: XCTestCase {
    /// A big empty field far from everything; the test then draws obstacles into it.
    func field(_ s: Society, at o: TilePos = TilePos(6000, 6000), w: Int = 180, h: Int = 120) -> TilePos {
        let grass = s.content.tid("grass")
        for y in 0..<h { for x in 0..<w {
            s.world.setTile(0, o.x + x, o.y + y, grass)
            for l in 1...3 { s.world.setTile(l, o.x + x, o.y + y, 0) }
        } }
        return o
    }
    func put(_ s: Society, _ key: String, _ cells: [TilePos], layer: Int = 2) { for c in cells { s.world.setTile(layer, c.x, c.y, s.content.tid(key)) } }
    func water(_ s: Society, _ cells: [TilePos], deep: Bool = true) { for c in cells { s.world.setTile(0, c.x, c.y, s.content.tid(deep ? "water" : "shallow_water")) } }

    /// Walk every segment in 1-pixel steps: no point may be on deep water, cliff or a wall.
    func legal(_ s: Society, _ pts: [Vec2], file: StaticString = #filePath, line: UInt = #line) -> Bool {
        for (p, q) in zip(pts, pts.dropFirst()) {
            let n = max(1, Int(p.distance(to: q)))
            for i in 0...n {
                let t = (p + (q - p) * (Double(i) / Double(n))).tile
                let g = s.ground(t.x, t.y)
                if g == .deep || g == .cliff || g == .wall { XCTFail("route crosses \(g) at \(t)", file: file, line: line); return false }
            }
        }
        return true
    }

    func testLShapedWallIsWalkedAroundNotThrough() {
        let s = makeSociety(7)
        let o = field(s)
        // an L: a long wall across the direct line, closed at one end
        put(s, "wall_stone", (0..<60).map { TilePos(o.x + 80, o.y + 10 + $0) })
        put(s, "wall_stone", (0..<30).map { TilePos(o.x + 50 + $0, o.y + 70) })
        let p = s.planMarch(from: TilePos(o.x + 60, o.y + 40), to: TilePos(o.x + 110, o.y + 40))
        XCTAssertEqual(p.status, .complete)
        XCTAssertTrue(legal(s, p.points))
        XCTAssertLessThan(p.points.count, 20, "straight stretches are simplified")
    }

    func testDiagonalPinchIsNotSqueezedThrough() {
        let s = makeSociety(7)
        let o = field(s)
        // a diagonal staircase wall: tiles touch only at corners
        put(s, "wall_stone", (0..<50).map { TilePos(o.x + 40 + $0, o.y + 10 + $0) })
        let p = s.planMarch(from: TilePos(o.x + 70, o.y + 20), to: TilePos(o.x + 50, o.y + 40))
        XCTAssertTrue(legal(s, p.points))
        // between consecutive points the line never steps diagonally between two wall tiles
        for (a, b) in zip(p.points, p.points.dropFirst()) {
            let n = max(1, Int(a.distance(to: b)))
            var prev = a.tile
            for i in 1...n {
                let t = (a + (b - a) * (Double(i) / Double(n))).tile
                if t.x != prev.x && t.y != prev.y {
                    let side1 = s.ground(t.x, prev.y), side2 = s.ground(prev.x, t.y)
                    XCTAssertFalse(side1 == .wall && side2 == .wall, "squeezed between \(TilePos(t.x, prev.y)) and \(TilePos(prev.x, t.y))")
                }
                prev = t
            }
        }
    }

    func testWindingBridgeIsTheOnlyWayOverDeepWater() {
        let s = makeSociety(7)
        let o = field(s)
        water(s, (0..<120).flatMap { y in (0..<9).map { TilePos(o.x + 80 + $0, o.y + y) } })
        // a bridge that zig-zags across
        let bridge = [TilePos(o.x + 80, o.y + 30), TilePos(o.x + 81, o.y + 30), TilePos(o.x + 82, o.y + 30), TilePos(o.x + 82, o.y + 31), TilePos(o.x + 82, o.y + 32),
                      TilePos(o.x + 83, o.y + 32), TilePos(o.x + 84, o.y + 32), TilePos(o.x + 85, o.y + 32), TilePos(o.x + 85, o.y + 33), TilePos(o.x + 86, o.y + 33),
                      TilePos(o.x + 87, o.y + 33), TilePos(o.x + 88, o.y + 33)]
        put(s, "bridge_wood", bridge, layer: 1)
        let p = s.planMarch(from: TilePos(o.x + 60, o.y + 60), to: TilePos(o.x + 110, o.y + 60))
        XCTAssertEqual(p.status, .complete)
        XCTAssertTrue(legal(s, p.points), "every step over the water is on the bridge")
        // take one plank away: no legal way left in this field
        s.world.setTile(1, o.x + 84, o.y + 32, 0)
        let q = s.planMarch(from: TilePos(o.x + 60, o.y + 60), to: TilePos(o.x + 110, o.y + 60), margin: 20)
        XCTAssertEqual(q.status, .needsBridge, "deep water is what stands in the way")
        XCTAssertTrue(legal(s, q.points), "the route goes as far as the shore and no further")
    }

    func testShallowWaterIsFordedButAvoidedWhenPossible() {
        let s = makeSociety(7)
        let o = field(s)
        water(s, (0..<120).flatMap { y in (0..<3).map { TilePos(o.x + 80 + $0, o.y + y) } }, deep: false)
        let p = s.planMarch(from: TilePos(o.x + 60, o.y + 60), to: TilePos(o.x + 110, o.y + 60))
        XCTAssertEqual(p.status, .complete); XCTAssertGreaterThan(p.wades, 0, "a ford is allowed and counted")
        // a road bridge a little way off is preferred to wading
        put(s, "bridge_wood", (0..<3).map { TilePos(o.x + 80 + $0, o.y + 64) }, layer: 1)
        let q = s.planMarch(from: TilePos(o.x + 60, o.y + 60), to: TilePos(o.x + 110, o.y + 60))
        XCTAssertEqual(q.wades, 0)
    }

    func testRoadDetourIsTakenWhenCheaper() {
        let s = makeSociety(7)
        let o = field(s)
        // rough ground (cost 1.4) 60 rows deep across the direct line; straight through costs about 104
        put(s, "rock", (0..<60).flatMap { y in (0..<60).map { TilePos(o.x + 60 + $0, o.y + 30 + y) } })
        // a road (cost 0.6) round the bottom: 34 + 80 + 34 tiles, about 89
        let road = (0..<80).map { TilePos(o.x + 50 + $0, o.y + 92) } + (0..<34).map { TilePos(o.x + 50, o.y + 58 + $0) } + (0..<35).map { TilePos(o.x + 129, o.y + 58 + $0) }
        put(s, "cobble_road", road, layer: 1)
        let p = s.planMarch(from: TilePos(o.x + 50, o.y + 58), to: TilePos(o.x + 129, o.y + 58))
        XCTAssertEqual(p.status, .complete)
        XCTAssertTrue(p.points.contains { $0.y > Double((o.y + 90) * 16) }, "the cheaper road round the rough ground is used")
    }

    func testClosedCityNeedsASiegeAndTheRouteStopsAtTheWalls() {
        let s = makeSociety(7)
        let o = field(s)
        let c = TilePos(o.x + 120, o.y + 60)
        for d in -8...8 { for p in [TilePos(c.x + d, c.y - 8), TilePos(c.x + d, c.y + 8), TilePos(c.x - 8, c.y + d), TilePos(c.x + 8, c.y + d)] {
            put(s, d == 0 && p.y == c.y + 8 ? "gate" : "wall_stone", [p])
        } }
        let p = s.planMarch(from: TilePos(o.x + 30, o.y + 60), to: c)
        XCTAssertEqual(p.status, .needsSiege)
        XCTAssertTrue(legal(s, p.points), "no step through the wall or the closed gate")
        XCTAssertLessThan(p.points.last!.distance(to: c.center), 14 * 16, "it ends at the walls")
        // open the gate: now there is a way in
        s.world.setTile(2, c.x, c.y + 8, s.content.tid("gate_open"))
        XCTAssertEqual(s.planMarch(from: TilePos(o.x + 30, o.y + 60), to: c).status, .complete)
    }

    func testBudgetRunsOutGivesAPartialLegalRouteNotAStraightLine() {
        let s = makeSociety(7)
        let o = field(s)
        put(s, "wall_stone", (0..<100).map { TilePos(o.x + 90, o.y + 5 + $0) })
        let p = s.planMarch(from: TilePos(o.x + 20, o.y + 60), to: TilePos(o.x + 160, o.y + 60), budget: 300)
        XCTAssertEqual(p.status, .partial, "running out of budget is not mistaken for unreachable")
        XCTAssertTrue(legal(s, p.points))
    }

    func testMapEdgeOfTheSearchIsNeverCrossed() {
        let s = makeSociety(7)
        let o = field(s)
        // a wall longer than the search box: the box edge is the end of the world for this search
        put(s, "wall_stone", (0..<120).map { TilePos(o.x + 90, o.y + $0) })
        let p = s.planMarch(from: TilePos(o.x + 70, o.y + 60), to: TilePos(o.x + 110, o.y + 60), margin: 10)
        XCTAssertNotEqual(p.status, .complete)
        XCTAssertTrue(legal(s, p.points))
        XCTAssertTrue(p.points.allSatisfy { $0.x >= Double((o.x + 60) * 16) && $0.x <= Double((o.x + 121) * 16) }, "inside the search box")
    }

    /// A legion on the march notices a broken bridge and a closed gate, re-plans, waits, and gives up in the end.
    func testLegionReplansAfterChangesAndNeverLoopsForever() {
        let s = makeSociety(7)
        let o = field(s)
        water(s, (0..<120).flatMap { y in (0..<5).map { TilePos(o.x + 80 + $0, o.y + y) } })
        let span = (0..<5).map { TilePos(o.x + 80 + $0, o.y + 60) }
        put(s, "bridge_wood", span, layer: 1)
        let lg = Legion()
        lg.id = 999; lg.nation = 1; lg.state = 1; lg.pos = TilePos(o.x + 40, o.y + 60).center
        let goal = TilePos(o.x + 140, o.y + 60)
        s.replan(lg, to: goal)
        XCTAssertEqual(lg.routeStatus, Society.RouteStatus.complete.rawValue)
        XCTAssertFalse(s.routeStale(lg))
        XCTAssertFalse(s.needsRoute(lg, to: goal))
        s.world.setTile(1, span[2].x, span[2].y, 0)                       // the bridge is broken
        XCTAssertTrue(s.routeStale(lg), "the change along the route is noticed")
        XCTAssertTrue(s.needsRoute(lg, to: goal))
        s.replan(lg, to: goal)
        XCTAssertNotEqual(lg.routeStatus, Society.RouteStatus.complete.rawValue)
        XCTAssertTrue(legal(s, lg.route!))
        XCTAssertFalse(s.needsRoute(lg, to: goal), "a blocked army waits before it looks again")
        s.world.time += s.realm.cfg.routeRetry + 1
        XCTAssertTrue(s.needsRoute(lg, to: goal))
        put(s, "bridge_wood", [span[2]], layer: 1)                         // mended
        s.replan(lg, to: goal)
        XCTAssertEqual(lg.routeStatus, Society.RouteStatus.complete.rawValue, "the mended bridge is used again")
        // an army that never finds a way gives up after a bounded number of tries
        s.realm.legions.append(lg)
        let home = s.towns(of: 1)[0]
        lg.home = home.id
        lg.routeFails = 0
        for _ in 0..<50 { s.blocked(lg, home: home) }
        XCTAssertEqual(lg.routeFails, 1, "waiting many steps at the end of one failed route counts once")
        XCTAssertEqual(lg.state, 1)
        for _ in 1..<s.realm.cfg.routeMaxFails { s.world.time += 1; s.replan(lg, to: TilePos(o.x + 82, o.y + 20)); s.blocked(lg, home: home) }
        XCTAssertEqual(lg.state, 3, "the attack is called off")
        XCTAssertEqual(lg.routeFails, 0)
    }
}
