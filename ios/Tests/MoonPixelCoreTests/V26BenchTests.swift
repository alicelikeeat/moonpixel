import XCTest
import Foundation
@testable import MoonPixelCore

/// Costs of the v2.6 paths, on whatever machine runs it (MP_BENCH=1). Not a phone measurement.
final class V26BenchTests: XCTestCase {
    func ms(_ f: () -> Void) -> Double { let t = DispatchTime.now().uptimeNanoseconds; f(); return Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6 }

    func testBench() throws {
        guard ProcessInfo.processInfo.environment["MP_BENCH"] != nil else { throw XCTSkip("set MP_BENCH") }
        var out: [String] = []
        let s = makeSociety(7)
        let g = WorldGround(s)
        // the body: a minute of walking at 60 fps, and a fall from storey 900
        var b = Body(at: s.settlements.values.sorted { $0.id < $1.id }[0].center.center, z: 0, depth: 0)
        b.z = g.floor(0, b.pos.tile) ?? 0
        let walk = ms { for i in 0..<3600 { _ = Motion.advance(&b, dt: 1.0 / 60, wish: Vec2(i % 600 < 300 ? 90 : -90, 0), jump: i % 120 == 0, ground: g) } }
        out.append(String(format: "BENCH26 body walk+jump 3600 frames: %.2f ms total, %.4f ms/frame", walk, walk / 3600))
        let o = s.world.findFree(near: TilePos(300, 300), maxR: 20)
        s.realm.standing = [StandingTower(tower: 1, city: 1, town: 1, x: o.x, y: o.y, w: 12, d: 10, levels: 1000)]
        s.raiseHouse(at: o, storeys: 2, w: 12, d: 10)
        var top = 0.0
        let first = ms { top = g.floor(OpenWorld.storeyBase + 999, TilePos(o.x + 5, o.y + 5)) ?? -1 }
        out.append(String(format: "BENCH26 first look at storey 999 of a 1000-level tower: %.3f ms, storeys made %d", first, s.storeys.count))
        var f = Body(at: TilePos(o.x - 2, o.y + 5).center, z: top + 10, depth: OpenWorld.storeyBase + 999)
        f.state = .falling
        var steps = 0
        let fall = ms { while !(f.grounded && f.depth == 0) && steps < 100000 { _ = Motion.advance(&f, dt: 1.0 / 60, wish: .zero, jump: false, ground: g); steps += 1 } }
        out.append(String(format: "BENCH26 fall from storey 999 to the ground: %d frames, %.2f ms (%.4f ms/frame), storeys made %d", steps, fall, fall / Double(max(1, steps)), s.storeys.count))
        let trimmed = s.trimStoreys(around: 0)
        out.append(String(format: "BENCH26 after housekeeping: %d storey layers let go, %d kept", trimmed, s.storeys.count))
        // twenty elevators running for a game hour
        let town = s.settlements.values.sorted { $0.id < $1.id }[0]
        for k in 0..<20 {
            let e = Elevator(); e.id = k + 1; e.town = town.id
            e.x = 2000 + k * 6; e.y = 2000; e.stops = (0..<30).map { LiftStop(level: $0, z: Double($0) * 2, door: TilePos(1999 + k * 6, 2000)) }
            e.z = 0; e.at = 0
            s.realm.lifts = s.realm.lifts + [e]
        }
        var calls = 0
        let lifts = ms { for i in 0..<3600 { if i % 30 == 0 { for e in s.realm.lifts { e.call((i / 30 + e.id) % 30, at: s.world.time); calls += 1 } }; s.liftsStep(1, powered: { _ in true }); s.world.time += 1 } }
        out.append(String(format: "BENCH26 20 elevators x 30 landings, 3600 one-second steps: %.2f ms (%.4f ms/step)", lifts, lifts / 3600))
        // inventory commands
        s.carry("wood", 100)
        let inv = ms { for i in 0..<2000 { _ = s.inventory(10_000 + i, i % 2 == 0 ? .drop("wood", 1) : .pickUp(s.inv.dropped.last?.id ?? 0), at: b) } }
        out.append(String(format: "BENCH26 2000 drop/pick-up commands: %.2f ms", inv))
        print(out.joined(separator: "\n"))
    }
}
