import XCTest
@testable import MoonPixelCore

final class CivTests: XCTestCase {
    func make(_ seed: Int, villages: Int = 4, per: Int = 30) -> Society {
        let w = OpenWorld(seed: seed, budget: MemoryBudget(overrideMB: 256))
        let s = Society(world: w, seed: seed)
        s.bootstrap(origin: TilePos(0, 0), villages: villages, per: per)
        return s
    }
    func run(_ s: Society, years: Double) { for _ in 0..<Int(years * MP.year) { s.tick(1.0) } }

    func testTechnologyDevelopsByItselfUpToAI() {
        let s = make(7)
        XCTAssertEqual(s.techCount, 0)
        XCTAssertFalse(s.has("ai"))
        run(s, years: 6)
        print("CIV after 6y: techs=\(s.techCount) (\(s.techName(s.techCount - 1))) rate=\(s.researchRate)")
        XCTAssertGreaterThanOrEqual(s.techCount, 3, "early technologies discovered without the player")
        XCTAssertTrue(s.has("farming") && s.has("masonry"))
        XCTAssertTrue(s.log.contains { $0.text.contains(s.techName(0)) } || s.techCount > 0)
        run(s, years: 24)
        let types = Set(s.settlements.values.flatMap { $0.buildings.filter { $0.done }.map { $0.type } })
        print("CIV after 30y: techs=\(s.techCount) pop=\(s.agents.count) buildings=\(types.sorted())")
        XCTAssertTrue(s.has("manufacturing"), "advanced manufacturing reached")
        XCTAssertTrue(s.has("ai"), "artificial intelligence reached")
        XCTAssertTrue(types.contains("school"))
        XCTAssertTrue(types.contains("factory"), "factories were built")
        XCTAssertTrue(types.contains("ai_center"), "an AI centre was built")
        // the signature equipment really stands in the world
        let c = Content.shared
        var cores = 0
        for v in s.settlements.values { for b in v.buildings where b.type == "ai_center" && b.done {
            for dy in 0..<b.h { for dx in 0..<b.w where s.world.tile(2, b.x + dx, b.y + dy) == c.tid("ai_core") { cores += 1 } }
        } }
        XCTAssertGreaterThan(cores, 0)
        XCTAssertGreaterThanOrEqual(s.agents.count, 100)
    }

    func testEveryFamilyGetsItsOwnHouse() {
        let s = make(11, villages: 2, per: 24)
        run(s, years: 4)
        let now = s.world.time
        var housed = 0, total = 0
        for v in s.settlements.values where !v.abandoned {
            var byHouse: [Int: Set<Int>] = [:]
            for id in v.members {
                guard let a = s.agents[id], !a.travelling else { continue }
                total += 1
                if a.home >= 0 { housed += 1; byHouse[a.home, default: []].insert(s.household(a, now)) }
            }
            for (home, hh) in byHouse { XCTAssertEqual(hh.count, 1, "house \(home) holds exactly one family") }
            let owners = v.buildings.filter { $0.type == "house" }.compactMap { $0.owner }
            XCTAssertEqual(owners.count, Set(owners).count, "no family owns two houses")
        }
        print("CIV housing: \(housed)/\(total) housed")
        XCTAssertGreaterThan(Double(housed) / Double(max(1, total)), 0.85, "nearly everyone lives in their family's house")
        for a in s.agents.values where a.partner != 0 {
            if let p = s.agents[a.partner], a.home >= 0, p.home >= 0, a.sid == p.sid { XCTAssertEqual(a.home, p.home, "couples live together") }
        }
    }

    func testAtMostFiftyCharactersAndTheRestAreCounted() {
        let s = make(13, villages: 1, per: 90)
        run(s, years: 0.02)
        let v = s.settlements[1]!
        let center = v.center.center
        let split = s.crowdSplit(center: center, halfW: 2000, halfH: 2000, limit: 50)
        XCTAssertEqual(split.shown.count, 50)
        let counted = split.badges.values.reduce(0, +)
        XCTAssertEqual(split.shown.count + counted, s.agents.count, "everyone is either drawn or counted on a building")
        XCTAssertFalse(split.badges.isEmpty)
        let small = s.crowdSplit(center: center, halfW: 2000, halfH: 2000, limit: 200)
        XCTAssertEqual(small.shown.count + small.badges.values.reduce(0, +), s.agents.count)
    }

    func testMapSizeIsMonitoredAndCapped() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mp_cap_\(UUID().uuidString)")
        let w = OpenWorld(seed: 3, budget: MemoryBudget(overrideMB: 96))
        w.open(directory: dir)
        XCTAssertEqual(w.diskBytes, 0)
        XCTAssertEqual(w.diskLimitBytes, 5 * 1024 * 1024 * 1024, "default cap is 5 GB")
        let wall = Content.shared.tid("wall_wood")
        w.pin(0, 0)
        w.setTile(2, 5, 5, wall)
        for i in 1...40 { w.setTile(2, i * 32 + 5, 5, wall) }
        w.saveAll()
        let full = w.diskBytes
        XCTAssertGreaterThan(full, 40 * 4000, "size on disk is tracked (\(full) bytes)")
        var onDisk = 0
        for f in try! FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("chunks").path) {
            onDisk += ((try! FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("chunks/\(f)").path)[.size]) as! NSNumber).intValue
        }
        XCTAssertEqual(full, onDisk, "tracked size matches the real files")
        w.purge()
        w.diskLimitBytes = full / 2
        let removed = w.enforceDiskLimit()
        XCTAssertGreaterThan(removed, 10)
        XCTAssertLessThanOrEqual(w.diskBytes, full / 2)
        XCTAssertEqual(w.tile(2, 5, 5), wall, "the pinned (inhabited) chunk is never pruned")
        // a fresh world over the same directory sees the same size
        let w2 = OpenWorld(seed: 3, budget: MemoryBudget(overrideMB: 96))
        w2.open(directory: dir)
        XCTAssertEqual(w2.diskBytes, w.diskBytes)
    }
}
