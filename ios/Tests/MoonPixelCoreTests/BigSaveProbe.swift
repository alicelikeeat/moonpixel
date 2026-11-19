import XCTest
@testable import MoonPixelCore

/// MP_PROBE=bigsave: grow a world, save it, open it again; print sizes, times and peak memory at each step.
final class BigSaveProbe: XCTestCase {
    func rss() -> (now: Int, peak: Int) {
        let s = (try? String(contentsOfFile: "/proc/self/status", encoding: .utf8)) ?? ""
        func v(_ k: String) -> Int { Int(s.split(separator: "\n").first { $0.hasPrefix(k) }?.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first ?? "0") ?? 0 }
        return (v("VmRSS:") / 1024, v("VmHWM:") / 1024)
    }

    func testProbeBigSave() throws {
        guard ProcessInfo.processInfo.environment["MP_PROBE"] == "bigsave" else { throw XCTSkip("set MP_PROBE=bigsave") }
        let years = Double(ProcessInfo.processInfo.environment["MP_YEARS"] ?? "20") ?? 20
        let dir = tempDir("bigsave")
        let st = WorldStore(directory: dir)
        let w = OpenWorld(seed: 7, budget: MemoryBudget(overrideMB: 1024))
        w.open(store: st)
        let s = Society(world: w, seed: 7)
        s.grantTech(6)
        s.bootstrap(origin: TilePos(0, 0), villages: 4, per: 30)
        var t0 = Date()
        for y in 0..<Int(years) {
            runYears(s, 1)
            if y % 5 == 4 { print("PROBE year \(y + 1): chunks cached \(w.cache.count) rss \(rss()) people \(s.totalPopulation) monuments \(s.realm.monuments?.count ?? 0) districts \(s.net.districts.count)") }
        }
        print("PROBE grew in \(Date().timeIntervalSince(t0)) s")
        w.saveAll()
        let idx = try JSONEncoder().encode(s.snapshot())
        let wsnap = try JSONEncoder().encode(w.snapshot())
        try st.commit(index: idx + wsnap, meta: Data("{}".utf8))
        print("PROBE saved: society index \(idx.count / 1024) KB, world snapshot \(wsnap.count / 1024) KB, chunk files \(st.chunks(depth: 0).count) disk \(st.diskBytes() / 1024) KB, rss \(rss())")
        // open it again, as the app does
        t0 = Date()
        let st2 = WorldStore(directory: dir)
        let w2 = OpenWorld(seed: 7, budget: MemoryBudget(overrideMB: 1024))
        w2.open(store: st2)
        let s2 = Society(world: w2, seed: 7)
        w2.restore(try JSONDecoder().decode(OpenWorld.Snapshot.self, from: wsnap))
        s2.restore(try JSONDecoder().decode(Society.Snapshot.self, from: idx))
        print("PROBE reopened in \(Date().timeIntervalSince(t0)) s rss \(rss())")
        // the first day after opening (daily growth, monuments, lifts)
        t0 = Date()
        for k in 0..<12 { let a = Date(); runYears(s2, 1.0 / 12); let dt = Date().timeIntervalSince(a); if dt > 1 { print("PROBE slow step \(k): \(dt) s rss \(rss())") } }
        print("PROBE first day after opening: \(Date().timeIntervalSince(t0)) s rss \(rss()) cached \(w2.cache.count)")
    }
}
