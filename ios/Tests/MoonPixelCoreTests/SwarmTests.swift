import XCTest
@testable import MoonPixelCore

final class SwarmTests: XCTestCase {
    private func buffer(_ n: Int, _ fill: (UnsafeMutableBufferPointer<SIMD4<Float>>) -> Void) -> [SIMD4<Float>] {
        var a = [SIMD4<Float>](repeating: .zero, count: n)
        a.withUnsafeMutableBufferPointer { fill($0) }
        return a
    }

    func testTheSwarmIsAPowerLikeAnyOther() {
        let p = Power.byKey["nano"]
        XCTAssertNotNil(p)
        XCTAssertEqual(Power.all.last?.key, "nano", "added last: nothing before it moved")
        XCTAssertEqual(p?.fx, "swarm"); XCTAssertEqual(p?.shape, Power.Shape.blast); XCTAssertEqual(p?.tier, 5)
        XCTAssertEqual(Set(Power.all.map { $0.key }).count, Power.all.count, "keys stay unique")
        XCTAssertEqual(SwarmShapes.sizes.last, 1 << 20, "the full swarm is 1 048 576 points")
        XCTAssertEqual(SwarmShapes.size(forMemoryGB: 8), 1 << 20); XCTAssertEqual(SwarmShapes.size(forMemoryGB: 4), 262_144); XCTAssertEqual(SwarmShapes.size(forMemoryGB: 2), 65_536)
    }

    func testColoursSurviveBeingPackedIntoAFloat() {
        for hex in ["#000000", "#ffffff", "#59d8ff", "#ff6fa8", "#010203"] {
            let c = RGBA(hex: hex)
            XCTAssertEqual(SwarmShapes.unpack(SwarmShapes.pack(c)), c)
        }
    }

    func testShapesAreWhereTheyShouldBeAndTheSameEveryTime() {
        let n = 20_000
        let ball = buffer(n) { SwarmShapes.sphere(into: $0) }
        XCTAssertEqual(ball, buffer(n) { SwarmShapes.sphere(into: $0) }, "same seed, same swarm")
        for p in ball {
            let d = (p.x * p.x + (p.y - 2.2) * (p.y - 2.2) + p.z * p.z).squareRoot()
            XCTAssertTrue(d > 1.55 && d < 1.75, "on the shell of the ball")
        }
        let helix = buffer(n) { SwarmShapes.helix(into: $0) }
        var strands = 0
        for p in helix {
            XCTAssertTrue(p.y > 0 && p.y < 6, "the helix stands on the ground")
            let r = (p.x * p.x + p.z * p.z).squareRoot()
            XCTAssertLessThan(r, 1.5)
            if r > 1.2 { strands += 1 }
        }
        XCTAssertGreaterThan(strands, n * 7 / 10, "most points are on the two strands, the rest on the rungs")

        // the caster as a giant: every point lies on the figure, three times life size, in the figure's colours
        var look = Look(); look.shirt = "#e8504a"
        let fig = Figure3D.human(look, frame: 3, held: "sword", child: false, female: false)
        let giant = buffer(n) { SwarmShapes.mesh(fig, into: $0, scale: 3) }
        let b = fig.bounds
        var red = 0, lowHalf = 0
        for p in giant {
            XCTAssertTrue(p.x >= b.min.x * 3 - 0.01 && p.x <= b.max.x * 3 + 0.01 && p.y >= -0.01 && p.y <= b.max.y * 3 + 0.01 && p.z >= b.min.z * 3 - 0.01 && p.z <= b.max.z * 3 + 0.01)
            let c = SwarmShapes.unpack(p.w)
            if c.r > 150 && c.g < 110 && c.b < 110 { red += 1 }
            if p.y < b.max.y * 1.5 { lowHalf += 1 }
        }
        XCTAssertGreaterThan(red, n / 12, "the red shirt is there")
        XCTAssertTrue(lowHalf > n / 4 && lowHalf < n * 3 / 4, "points are spread over the whole figure by area, not bunched")
        // an empty mesh does not crash: everything gathers at the origin
        XCTAssertEqual(buffer(8) { SwarmShapes.mesh(Mesh3D(), into: $0) }.map { $0.x }, [Float](repeating: 0, count: 8))
        let dust = buffer(n) { SwarmShapes.dust(into: $0) }
        for p in dust { XCTAssertTrue(p.y >= 0 && p.y < 0.6 && p.w >= 0 && p.w < 1) }
    }

    func testTheShowMovesThroughItsShapesInOrder() {
        XCTAssertEqual(SwarmShapes.stage(at: 0).to, 0)
        XCTAssertEqual(SwarmShapes.stage(at: 1.9).to, 0)
        let s = SwarmShapes.stage(at: 2.3)
        XCTAssertEqual(s.from, 0); XCTAssertEqual(s.to, 1); XCTAssertTrue(s.blend > 0 && s.blend < 1, "on the way from the ball to the giant")
        XCTAssertEqual(SwarmShapes.stage(at: 3.5).blend, 1)
        XCTAssertEqual(SwarmShapes.stage(at: 5).to, 2); XCTAssertEqual(SwarmShapes.stage(at: 7.5).to, 3)
        XCTAssertEqual(SwarmShapes.stage(at: 100).to, 3)
        var last: Float = -1
        for i in 0...40 { let b = SwarmShapes.stage(at: 2 + Float(i) * 0.025).blend; XCTAssertGreaterThanOrEqual(b, last); last = b }
        XCTAssertLessThan(SwarmShapes.scatterAt, SwarmShapes.showLength)
    }

    func testAMillionPointsAreSampledQuickly() {
        let n = SwarmShapes.sizes[3]
        let fig = Figure3D.human(Look(), frame: 0, held: "", child: false, female: false)
        let t0 = Date()
        var a = [SIMD4<Float>](repeating: .zero, count: n)
        a.withUnsafeMutableBufferPointer { SwarmShapes.mesh(fig, into: $0) }
        a.withUnsafeMutableBufferPointer { SwarmShapes.helix(into: $0) }
        let took = Date().timeIntervalSince(t0)
        print("SWARM 2 shapes x \(n) points: \(String(format: "%.2f", took)) s")
        XCTAssertLessThan(took, 6, "preparing the full swarm stays a short wait (done off the main thread)")
    }

    func testTheSwarmSizeFollowsHeatMemoryAndFrameTime() {
        let big = SwarmShapes.sizes[3], s = SwarmShapes.sizes
        XCTAssertEqual(SwarmShapes.tier(base: big, last: nil, availableMB: 4000, thermal: 0, lastWorstMs: nil), big)
        XCTAssertEqual(SwarmShapes.tier(base: big, last: nil, availableMB: 4000, thermal: 2, lastWorstMs: nil), s[2], "hot: one smaller")
        XCTAssertEqual(SwarmShapes.tier(base: big, last: nil, availableMB: 4000, thermal: 3, lastWorstMs: nil), s[1], "critical: two smaller")
        XCTAssertEqual(SwarmShapes.tier(base: big, last: nil, availableMB: 60, thermal: 0, lastWorstMs: nil), s[1], "six buffers must fit in half of what is left")
        XCTAssertEqual(SwarmShapes.tier(base: big, last: big, availableMB: 4000, thermal: 0, lastWorstMs: 40), s[2], "a slow last show: smaller")
        XCTAssertEqual(SwarmShapes.tier(base: big, last: s[2], availableMB: 4000, thermal: 0, lastWorstMs: 8), big, "a quick one: back up")
        XCTAssertEqual(SwarmShapes.tier(base: s[1], last: s[1], availableMB: 4000, thermal: 0, lastWorstMs: 5), s[1], "never above what memory allows")
        XCTAssertEqual(SwarmShapes.tier(base: big, last: nil, availableMB: 1, thermal: 3, lastWorstMs: 90), s[0], "always something")
        XCTAssertEqual(SwarmShapes.fallbacks(from: s[2]), [s[2], s[1], s[0]])
    }
}
