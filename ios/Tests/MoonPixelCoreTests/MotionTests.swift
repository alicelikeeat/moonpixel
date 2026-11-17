import XCTest
@testable import MoonPixelCore

/// A small world to move in: flat ground at 0, storeys every 2 tiles where `floors` says, walls where `walls` says.
final class TestGround: MotionGround {
    var floors: [Int: Set<TilePos>] = [:]          // storey number -> tiles with floor
    var walls: [Int: Set<TilePos>] = [:]           // depth -> solid tiles
    func floor(_ d: Int, _ t: TilePos) -> Double? {
        if d == 0 { return 0 }
        let n = d - OpenWorld.storeyBase
        return floors[n]?.contains(t) == true ? Double(n) * 2 : nil
    }
    func nominal(_ d: Int, _ t: TilePos) -> Double { d == 0 ? 0 : Double(d - OpenWorld.storeyBase) * 2 }
    func blocked(_ d: Int, _ t: TilePos) -> Bool { walls[d]?.contains(t) == true }
    func below(_ d: Int) -> Int? { d == 0 ? nil : (d - OpenWorld.storeyBase <= 1 ? 0 : d - 1) }
    func above(_ d: Int) -> Int? { d == 0 ? OpenWorld.storeyBase + 1 : d + 1 }
    func slab(_ n: Int, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) { for y in y0...y1 { for x in x0...x1 { floors[n, default: []].insert(TilePos(x, y)) } } }
}

final class MotionTests: XCTestCase {
    let cfg = MotionConfig()
    func at(_ tx: Int, _ ty: Int, z: Double = 0, depth: Int = 0) -> Body { Body(at: TilePos(tx, ty).center, z: z, depth: depth) }
    func storey(_ n: Int) -> Int { OpenWorld.storeyBase + n }

    /// Run until the body is on something again (or `limit` seconds), returning the highest point.
    func flight(_ b: inout Body, _ g: MotionGround, frames: [Double], platforms: (Double) -> [Platform] = { _ in [] }) -> (apex: Double, damage: Double, landings: Int) {
        var apex = b.z, dmg = 0.0, t = 0.0, k = 0
        _ = Motion.advance(&b, dt: 0, wish: .zero, jump: true, ground: g, platforms: platforms(0), cfg: cfg)
        while k < 4000 {
            let dt = frames[k % frames.count]; t += dt; k += 1
            let r = Motion.advance(&b, dt: dt, wish: .zero, jump: false, ground: g, platforms: platforms(t), cfg: cfg)
            apex = max(apex, b.z, r.peak); dmg += r.damage
            if r.landed { break }
        }
        return (apex, dmg, b.landings)
    }

    func testAJumpIsAsHighWhateverTheFrameRate() {
        let g = TestGround()
        var apexes: [Double] = []
        for frames in [[1.0 / 30], [1.0 / 60], [1.0 / 144], [0.004, 0.031, 0.017, 0.09], [0.2]] {
            var b = at(5, 5)
            apexes.append(flight(&b, g, frames: frames).apex)
            XCTAssertEqual(b.z, 0, accuracy: 1e-9, "back on the ground")
            XCTAssertEqual(b.state, .standing)
        }
        for a in apexes { XCTAssertEqual(a, apexes[0], accuracy: 1e-9, "the same steps whatever the frames") }
        XCTAssertEqual(apexes[0], cfg.jumpSpeed * cfg.jumpSpeed / (2 * cfg.gravity), accuracy: 0.05, "about v^2/2g")
    }

    func testNoJumpInTheAirButAPressJustBeforeLandingCounts() {
        let g = TestGround()
        var b = at(5, 5)
        _ = Motion.advance(&b, dt: 0, wish: .zero, jump: true, ground: g, cfg: cfg)
        _ = Motion.advance(&b, dt: 0.2, wish: .zero, jump: false, ground: g, cfg: cfg)
        let vz = b.vz
        _ = Motion.advance(&b, dt: 1.0 / 120, wish: .zero, jump: true, ground: g, cfg: cfg)       // high in the air: no second jump
        XCTAssertLessThan(b.vz, vz, "still slowing down, not jumping again")
        // fall until just before landing, press, and it jumps again as soon as the feet touch
        while b.z > 0.08 || b.vz > 0 { _ = Motion.advance(&b, dt: 1.0 / 120, wish: .zero, jump: false, ground: g, cfg: cfg) }
        _ = Motion.advance(&b, dt: 1.0 / 120, wish: .zero, jump: true, ground: g, cfg: cfg)
        var rose = false
        for _ in 0..<30 { _ = Motion.advance(&b, dt: 1.0 / 120, wish: .zero, jump: false, ground: g, cfg: cfg); if b.vz > 1 { rose = true } }
        XCTAssertTrue(rose, "the buffered press was used on landing")
    }

    func testALowCeilingStopsTheHeadAndIsNeverPassed() {
        let g = TestGround()
        g.slab(1, 0, 0, 20, 20)                                    // a floor above: ceiling at 2 - 0.25
        var b = at(5, 5)
        let f = flight(&b, g, frames: [1.0 / 60])
        XCTAssertLessThanOrEqual(f.apex + cfg.height, 2 - cfg.slab + 1e-9, "the head never goes into the slab")
        XCTAssertEqual(b.depth, 0, "still under it, not on top")
        XCTAssertEqual(f.damage, 0)
    }

    func testAFallFromTheFiftiethStoreyLandsOnTheGroundOnceAndHurtsOnce() {
        let g = TestGround()
        g.slab(50, 0, 0, 3, 3)
        var b = at(1, 1, z: 100, depth: storey(50))
        // walk off the edge
        var dmg = 0.0, lands = 0, steps = 0
        while steps < 2000 {
            let r = Motion.advance(&b, dt: 1.0 / 60, wish: Vec2(90, 0), jump: false, ground: g, cfg: cfg)
            dmg += r.damage; if r.landed { lands += 1 }
            if b.grounded && b.depth == 0 { break }
            steps += 1
        }
        XCTAssertEqual(b.depth, 0); XCTAssertEqual(b.z, 0, accuracy: 1e-9, "on the ground, not under it")
        XCTAssertEqual(lands, 1)
        XCTAssertGreaterThan(dmg, 0, "a hundred tiles down hurts")
        for _ in 0..<120 { dmg += Motion.advance(&b, dt: 1.0 / 60, wish: .zero, jump: false, ground: g, cfg: cfg).damage }
        XCTAssertEqual(b.landings, 1, "standing there does not land again")
        let once = dmg
        XCTAssertEqual(dmg, once)
        // a small drop does not hurt at all
        g.slab(1, 10, 0, 12, 3)
        var c = at(11, 1, z: 2, depth: storey(1))
        var d2 = 0.0
        for _ in 0..<200 { d2 += Motion.advance(&c, dt: 1.0 / 60, wish: Vec2(90, 0), jump: false, ground: g, cfg: cfg).damage }
        XCTAssertEqual(c.depth, 0); XCTAssertEqual(d2, 0, "one storey is not a hurt")
    }

    func testTheFloorTakenAwayUnderFootIsFallenThroughToTheOneBelow() {
        let g = TestGround()
        g.slab(1, 0, 0, 10, 10); g.slab(2, 0, 0, 10, 10)
        var b = at(5, 5, z: 4, depth: storey(2))
        _ = Motion.advance(&b, dt: 0.1, wish: .zero, jump: false, ground: g, cfg: cfg)
        XCTAssertEqual(b.state, .standing)
        g.floors[2]!.remove(TilePos(5, 5))
        var steps = 0
        while !(b.grounded && b.depth == storey(1)) && steps < 600 { _ = Motion.advance(&b, dt: 1.0 / 60, wish: .zero, jump: false, ground: g, cfg: cfg); steps += 1 }
        XCTAssertEqual(b.depth, storey(1)); XCTAssertEqual(b.z, 2, accuracy: 1e-9, "on storey 1, not through it")
    }

    func testWallsStopTheBodyAndAStepIsWalkedUp() {
        let g = TestGround()
        g.walls[0] = [TilePos(7, 5)]
        var b = at(5, 5)
        for _ in 0..<120 { _ = Motion.advance(&b, dt: 1.0 / 60, wish: Vec2(90, 0), jump: false, ground: g, cfg: cfg) }
        XCTAssertLessThan(b.x, Double(7 * 16), "the wall stops it")
        XCTAssertEqual(b.x, Double(7 * 16) - 1e-9, accuracy: 2, "right against it")
    }

    func car(_ t: Double, id: Int = 1, speed: Double = 2, from z0: Double = 0) -> Platform {
        let z = z0 + speed * t
        return Platform(id: id, minX: 64, minY: 64, maxX: 112, maxY: 112, floorZ: z, vz: speed, open: false, stopDepth: nil)
    }

    func testRidingACarAndJumpingInsideItLandsBackInTheCar() {
        let g = TestGround()
        var b = Body(at: Vec2(88, 88), z: 0, depth: 0)
        b.platform = 1; b.state = .riding
        var t = 0.0
        for _ in 0..<60 { t += 1.0 / 60; _ = Motion.advance(&b, dt: 1.0 / 60, wish: .zero, jump: false, ground: g, platforms: [car(t)], cfg: cfg) }
        XCTAssertEqual(b.z, car(t).floorZ, accuracy: 1e-9, "carried with the floor")
        XCTAssertEqual(b.vz, 2, accuracy: 1e-9, "at the car's speed, not more")
        // jump while it climbs
        let start = b.z
        _ = Motion.advance(&b, dt: 0, wish: .zero, jump: true, ground: g, platforms: [car(t)], cfg: cfg)
        var apexAbove = 0.0, landed = false
        for _ in 0..<400 {
            t += 1.0 / 60
            let r = Motion.advance(&b, dt: 1.0 / 60, wish: .zero, jump: false, ground: g, platforms: [car(t)], cfg: cfg)
            apexAbove = max(apexAbove, b.z - car(t).floorZ)
            if r.landed { landed = true; XCTAssertEqual(r.damage, 0, "a hop in a car does not hurt"); break }
        }
        XCTAssertTrue(landed); XCTAssertEqual(b.platform, 1, "back in the car"); XCTAssertEqual(b.state, .riding)
        XCTAssertEqual(apexAbove, cfg.jumpSpeed * cfg.jumpSpeed / (2 * cfg.gravity), accuracy: 0.08, "as high above the car as above the ground: its speed was added once")
        XCTAssertGreaterThan(b.z, start)
        for _ in 0..<30 { t += 1.0 / 60; _ = Motion.advance(&b, dt: 1.0 / 60, wish: .zero, jump: false, ground: g, platforms: [car(t)], cfg: cfg) }
        XCTAssertEqual(b.vz, 2, accuracy: 1e-9, "no speed piles up")
    }

    func testWalkingOutOfAnOpenCarOntoTheLanding() {
        let g = TestGround()
        g.slab(3, 0, 0, 20, 20)
        let stop = Platform(id: 1, minX: 64, minY: 64, maxX: 112, maxY: 112, floorZ: 6, vz: 0, open: true, stopDepth: storey(3))
        var b = Body(at: Vec2(100, 88), z: 6, depth: 0); b.platform = 1; b.state = .riding
        for _ in 0..<40 { _ = Motion.advance(&b, dt: 1.0 / 60, wish: Vec2(90, 0), jump: false, ground: g, platforms: [stop], cfg: cfg) }
        XCTAssertNil(b.platform); XCTAssertEqual(b.depth, storey(3)); XCTAssertEqual(b.z, 6, accuracy: 1e-9)
        XCTAssertGreaterThan(b.x, 112, "out on the landing")
        // a closed door keeps you in
        var c = Body(at: Vec2(100, 88), z: 6, depth: 0); c.platform = 1; c.state = .riding
        var shut = stop; shut.open = false
        for _ in 0..<40 { _ = Motion.advance(&c, dt: 1.0 / 60, wish: Vec2(90, 0), jump: false, ground: g, platforms: [shut], cfg: cfg) }
        XCTAssertEqual(c.platform, 1); XCTAssertLessThanOrEqual(c.x, 112)
    }

    func testAJumpSavedInTheAirGoesOnExactlyTheSame() throws {
        let g = TestGround()
        var a = at(5, 5)
        _ = Motion.advance(&a, dt: 0, wish: Vec2(40, 0), jump: true, ground: g, cfg: cfg)
        for _ in 0..<13 { _ = Motion.advance(&a, dt: 1.0 / 60, wish: Vec2(40, 0), jump: false, ground: g, cfg: cfg) }
        XCTAssertTrue(a.airborne)
        var b = try JSONDecoder().decode(Body.self, from: JSONEncoder().encode(a))
        var da = 0.0, db = 0.0
        for _ in 0..<120 {
            da += Motion.advance(&a, dt: 1.0 / 60, wish: Vec2(40, 0), jump: false, ground: g, cfg: cfg).damage
            db += Motion.advance(&b, dt: 1.0 / 60, wish: Vec2(40, 0), jump: false, ground: g, cfg: cfg).damage
        }
        XCTAssertEqual(a, b, "a save in mid-air lands in the same place")
        XCTAssertEqual(a.landings, 1); XCTAssertEqual(da, db)
    }

    func testImpossiblePlacesAreRecoveredWithAReason() {
        let g = TestGround()
        g.walls[0] = [TilePos(5, 5)]
        let free: (Int, TilePos) -> TilePos? = { d, t in d == 0 ? TilePos(t.x + 1, t.y) : nil }
        var b = at(5, 5)
        XCTAssertEqual(Motion.recover(b, ground: g, free: free)?.1, "inside something solid")
        b = at(9, 9); b.z = .nan
        let (r, why) = Motion.recover(b, ground: g, free: free)!
        XCTAssertEqual(why, "position was not a valid place")
        XCTAssertTrue(r.z.isFinite); XCTAssertEqual(r.state, .standing)
        b = at(9, 9); b.z = -3
        XCTAssertEqual(Motion.recover(b, ground: g, free: free)?.1, "below the floor")
        XCTAssertNil(Motion.recover(at(9, 9), ground: g, free: free), "a good place is left alone")
    }

    /// The real world: a house of three storeys; the floor under someone on its top storey is taken down.
    func testInARealHouseTheFloorGoesAndTheyFallToTheStoreyBelow() {
        let s = makeSociety(4)
        let o = s.world.findFree(near: TilePos(200, 200), maxR: 20)
        s.raiseHouse(at: o, storeys: 3, w: 7, d: 7)
        let g = WorldGround(s)
        let spot = TilePos(o.x + 3, o.y + 3)
        guard let f2 = g.floor(storey(2), spot), let f1 = g.floor(storey(1), spot) else { return XCTFail("no floors") }
        XCTAssertEqual(f2 - f1, Double(Float(Terrain3D.storeyLevels) * Terrain3D.step), accuracy: 1e-6, "storeys are one storey apart")
        var b = Body(at: spot.center, z: f2, depth: storey(2))
        _ = Motion.advance(&b, dt: 0.1, wish: .zero, jump: false, ground: g, cfg: cfg)
        XCTAssertEqual(b.state, .standing); XCTAssertEqual(b.z, f2, accuracy: 1e-6)
        s.storeyWorld(2).setTile(0, spot.x, spot.y, 0)
        for _ in 0..<200 { _ = Motion.advance(&b, dt: 1.0 / 60, wish: .zero, jump: false, ground: g, cfg: cfg) }
        XCTAssertEqual(b.depth, storey(1)); XCTAssertEqual(b.z, f1, accuracy: 1e-6)
        // the head meets the slab of the storey above when jumping on storey 1 under storey 2's floor
        let under = TilePos(o.x + 2, o.y + 3)
        var c = Body(at: under.center, z: f1, depth: storey(1))
        var apex = c.z
        _ = Motion.advance(&c, dt: 0, wish: .zero, jump: true, ground: g, cfg: cfg)
        for _ in 0..<200 { _ = Motion.advance(&c, dt: 1.0 / 60, wish: .zero, jump: false, ground: g, cfg: cfg); apex = max(apex, c.z) }
        XCTAssertLessThanOrEqual(apex + cfg.height, f2 - cfg.slab + 1e-6)
        XCTAssertEqual(c.depth, storey(1))
    }
}
