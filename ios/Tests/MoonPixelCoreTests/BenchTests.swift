import XCTest
@testable import MoonPixelCore

final class BenchTests: XCTestCase {
    func testBench() {
        let w = OpenWorld(seed: 7, budget: MemoryBudget(overrideMB: 256))
        let s = Society(world: w, seed: 7)
        s.bootstrap(origin: TilePos(0, 0), villages: 4, per: 30)
        let v = s.settlements[1]!
        var t0 = Date()
        var n = 0
        for i in 0..<2000 { n += v.nav!.path(from: TilePos(48, 50), to: TilePos(10 + i % 70, 12 + (i * 7) % 70)).count }
        print("BENCH 2000 paths: \(Date().timeIntervalSince(t0)) s (\(n))")
        PathGrid.calls = 0; PathGrid.fails = 0; PathGrid.expanded = 0
        t0 = Date()
        for _ in 0..<600 { s.tick(1.0) }
        print("BENCH 600 ticks: \(Date().timeIntervalSince(t0)) s calls=\(PathGrid.calls) fails=\(PathGrid.fails) expanded=\(PathGrid.expanded)")
        print("BENCH fails by act: \(Society.failActs)")
        for v2 in s.settlements.values.sorted(by: { $0.id < $1.id }) {
            let c = v2.center - v2.origin
            var fail = 0, tot = 0
            for dy in -8...8 { for dx in -8...8 {
                let t = TilePos(c.x + dx, c.y + dy)
                if v2.nav!.solid[t.y * 96 + t.x] { continue }
                tot += 1
                if v2.nav!.path(from: TilePos(c.x, c.y + 3), to: t).isEmpty { fail += 1 }
            } }
            print("BENCH village \(v2.id) center \(c) local fails \(fail)/\(tot)")
        }
        t0 = Date()
        var k = 0
        for i in 0..<200000 { if w.blocked(i % 90, (i / 90) % 90) { k += 1 } }
        print("BENCH 200k blocked: \(Date().timeIntervalSince(t0)) s \(k)")
    }
}
