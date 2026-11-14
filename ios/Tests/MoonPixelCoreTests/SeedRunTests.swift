import XCTest
@testable import MoonPixelCore

/// Long runs over many fixed seeds. Off by default; set MP_SEEDS (e.g. "1-30" or "4,9")
/// and optionally MP_YEARS and MP_OUT (file to append one line per seed to).
final class SeedRunTests: XCTestCase {
    func testManySeeds() throws {
        let env = ProcessInfo.processInfo.environment
        guard let spec = env["MP_SEEDS"] else { throw XCTSkip("set MP_SEEDS to run") }
        var seeds: [Int] = []
        for part in spec.split(separator: ",") {
            let r = part.split(separator: "-").compactMap { Int($0) }
            if r.count == 2 { seeds += Array(r[0]...r[1]) } else if r.count == 1 { seeds.append(r[0]) }
        }
        let years = Int(env["MP_YEARS"] ?? "50") ?? 50
        let out = env["MP_OUT"].map { URL(fileURLWithPath: $0) }
        for seed in seeds {
            let started = Date()
            let s = makeSociety(seed)
            var pops: [Int] = [], towns: [Int] = []
            var lastState = s.realm.relations.map { $0.state }
            var flips: [[(Double, Int)]] = [[], [], []]
            var unityStart: Double? = nil, longestUnity = 0.0
            var emptyYears = 0, auditFails = 0
            for y in 1...years {
                for _ in 0..<Int(MP.year / 2) {
                    s.tick(2)
                    for (i, r) in s.realm.relations.enumerated() where r.state != lastState[i] { flips[i].append((s.world.time, r.state)); lastState[i] = r.state }
                    if s.realm.era == 1 { if unityStart == nil { unityStart = s.world.time } } else if let u = unityStart { longestUnity = max(longestUnity, (s.world.time - u) / MP.year); unityStart = nil }
                }
                if s.agents.isEmpty { emptyYears += 1 }
                if y % 10 == 0 {
                    pops.append(s.agents.count); towns.append(s.livingSettlements)
                    let issues = s.audit()
                    if !issues.isEmpty { auditFails += 1; print("SEEDAUDIT seed=\(seed) year=\(y) \(issues.prefix(4))") }
                }
            }
            if let u = unityStart { longestUnity = max(longestUnity, (s.world.time - u) / MP.year) }
            // shortest gap between a truce and the next war of the same pair
            var minGap = 999.0
            for list in flips { for (k, e) in list.enumerated() where e.1 == 1 { if let t = list[..<k].last(where: { $0.1 == 2 }) { minGap = min(minGap, (e.0 - t.0) / MP.year) } } }
            let c = s.realm.counts
            let landed = s.realm.nations.filter { $0.exileSince == nil }.count
            let caps = s.realm.nations.filter { s.capital(of: $0.id) != nil }.count
            let line = String(format: "seed=%d years=%d wars=%d truces=%d unify=%d split=%d captures=%d defect=%d battleDead=%d pop10y=%@ towns10y=%@ landed=%d capitals=%d era=%d longestUnity=%.1f minTruceToWar=%.1f empty=%d audit=%d tech=%@ secs=%.0f",
                              seed, years, c.wars, c.truces, c.unifications, c.splits, c.captures, c.defections, s.stats.battle ?? 0,
                              pops.map(String.init).joined(separator: "/"), towns.map(String.init).joined(separator: "/"), landed, caps, s.realm.era, longestUnity, minGap,
                              emptyYears, auditFails, s.realm.nations.map { String($0.techCount) }.joined(separator: "/"), Date().timeIntervalSince(started))
            print("SEEDRUN " + line)
            if let o = out {
                if let h = try? FileHandle(forWritingTo: o) { h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close() }
                else { try? (line + "\n").write(to: o, atomically: true, encoding: .utf8) }
            }
            XCTAssertLessThanOrEqual(longestUnity, s.realm.cfg.unityMax + 0.5, "seed \(seed): unity never locks")
            if minGap < 999 { XCTAssertGreaterThanOrEqual(minGap, s.realm.cfg.minTruce + s.realm.cfg.peaceCooldown - 0.1, "seed \(seed): no war right after a truce") }
            XCTAssertEqual(auditFails, 0, "seed \(seed): references stay whole")
        }
    }
}
