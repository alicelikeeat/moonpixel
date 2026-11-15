import XCTest
import Foundation
@testable import MoonPixelCore

/// Same file for the baseline and the current tree: only APIs both have.
final class ZBenchTests: XCTestCase {
    func ms(_ f: () -> Void) -> Double { let t = DispatchTime.now().uptimeNanoseconds; f(); return Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6 }
    func pct(_ xs: [Double], _ q: Double) -> Double { let s = xs.sorted(); return s[min(s.count - 1, Int(Double(s.count - 1) * q))] }

    func testBench() throws {
        guard ProcessInfo.processInfo.environment["MP_BENCH"] != nil else { throw XCTSkip("set MP_BENCH") }
        var out: [String] = []
        for seed in [7, 11, 21] {
            let s = makeSociety(seed)
            runYears(s, 0.5)
            // steady stepping at the 16x step (0.25 s)
            var ticks: [Double] = []
            for _ in 0..<2400 { ticks.append(ms { s.tick(0.25) }) }
            // every town due at once, as right after a load
            var burst: [Double] = []
            for _ in 0..<20 {
                for t in s.settlements.values { t.planT = 0; t.resT = 0 }
                var worst = 0.0
                for _ in 0..<8 { worst = max(worst, ms { s.tick(0.25) }) }
                burst.append(worst)
            }
            // on-screen crowd query around each town
            let towns = s.settlements.values.filter { !$0.abandoned }.map { $0.center.center }
            var crowd: [Double] = []
            for _ in 0..<50 { for c in towns { crowd.append(ms { _ = s.crowdSplit(center: c, halfW: 420, halfH: 900, limit: 50) }) } }
            // march routes between towns
            let ts = s.settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
            var route: [Double] = []
            for a in ts { for b in ts where a.id < b.id { route.append(ms { _ = s.marchRoute(from: a.center, to: b.center) }) } }
            out.append(String(format: "BENCH seed=%d agents=%d tick p50=%.3f p99=%.3f max=%.3f | burstWorstTick p50=%.3f max=%.3f | crowd p50=%.4f p99=%.4f | route n=%d p50=%.2f max=%.2f",
                              seed, s.agents.count, pct(ticks, 0.5), pct(ticks, 0.99), ticks.max()!, pct(burst, 0.5), burst.max()!, pct(crowd, 0.5), pct(crowd, 0.99), route.count, route.isEmpty ? 0 : pct(route, 0.5), route.max() ?? 0))
        }
        print(out.joined(separator: "\n"))
    }
}
