import XCTest
@testable import MoonPixelCore

final class WorldTests: XCTestCase {
    func world(_ seed: Int, mb: Int = 96) -> OpenWorld { OpenWorld(seed: seed, budget: MemoryBudget(overrideMB: mb)) }

    func tmp(_ name: String) -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("mp_\(name)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testContentLoads() {
        let c = Content.shared
        XCTAssertEqual(c.tid("grass"), 5)
        XCTAssertEqual(c.tid("tree_oak"), 40)
        XCTAssertEqual(c.tid("wall_wood"), 60)
        XCTAssertEqual(c.biomes.count, 10)
        XCTAssertTrue(c.solid[Int(c.tid("water"))])
    }

    func testMemoryBudget() {
        let auto = MemoryBudget()
        XCTAssertGreaterThan(auto.physicalMB, 0)
        XCTAssertGreaterThanOrEqual(auto.budgetMB, MemoryBudget.minMB)
        XCTAssertLessThanOrEqual(auto.budgetMB, auto.physicalMB)
        XCTAssertGreaterThan(MemoryBudget(overrideMB: 2048).maxChunks, MemoryBudget(overrideMB: 96).maxChunks)
        XCTAssertGreaterThan(MemoryBudget.usedMB(), 0)
    }

    func testDeterministicAnyOrderAnyCoordinate() {
        let a = world(42), b = world(42)
        let coords = [(0, 0), (-1, -1), (-500, 320), (100000, -100000), (7, -3)]
        var first: [[[UInt8]]] = []
        for c in coords { first.append(a.chunk(c.0, c.1).layers) }
        for (i, c) in coords.enumerated().reversed() { XCTAssertEqual(b.chunk(c.0, c.1).layers, first[i]) }
        XCTAssertNotEqual(world(43).chunk(3, 3).layers[0], a.chunk(3, 3).layers[0])
        XCTAssertEqual(MP.keyCX(MP.chunkKey(-500, 320)), -500)
        XCTAssertEqual(MP.keyCY(MP.chunkKey(-500, 320)), 320)
    }

    func testBiomeVariety() {
        let w = world(7)
        var seen = Set<Int>()
        var land = 0, total = 0
        for y in stride(from: -6000, through: 6000, by: 60) { for x in stride(from: -6000, through: 6000, by: 60) {
            let b = w.gen.biome(x, y)
            seen.insert(b); total += 1
            if b != Biome.ocean { land += 1 }
        } }
        for b in [Biome.grass, Biome.forest, Biome.snow, Biome.desert, Biome.wetland, Biome.ocean] { XCTAssertTrue(seen.contains(b), "biome \(b)") }
        let share = Double(land) / Double(total)
        XCTAssertTrue(share > 0.45 && share < 0.92, "land share \(share)")
    }

    func testNegativeTiles() {
        let w = world(5)
        let grass = Content.shared.tid("grass")
        w.setTile(0, -1, -1, grass)
        w.setTile(0, -33, 40, grass)
        XCTAssertEqual(w.tile(0, -1, -1), grass)
        XCTAssertEqual(w.chunk(-1, -1).layers[0][31 * 32 + 31], grass)
        XCTAssertEqual(w.chunk(-2, 1).layers[0][8 * 32 + 31], grass)
    }

    func testCacheBudgetPinsAndDiskBackedEdits() {
        let w = world(9)
        w.open(directory: tmp("cache"))
        w.budget.maxChunks = 300
        w.pin(0, 0)
        let wall = Content.shared.tid("wall_wood")
        w.setTile(2, 70, 70, wall)
        for i in 0..<900 { w.chunk(100 + i % 60, 100 + i / 60); if i % 50 == 0 { w.maintain() } }
        w.maintain()
        XCTAssertLessThanOrEqual(w.cache.count, 300)
        XCTAssertTrue(w.loaded(0, 0))
        XCTAssertFalse(w.loaded(2, 2))
        XCTAssertEqual(w.tile(2, 70, 70), wall)
        w.chunk(100, 100)
        let before = w.cache.count
        let dropped = w.purge(keep: [MP.chunkKey(100, 100)])
        XCTAssertEqual(dropped, before - w.cache.count, "everything not pinned or kept is dropped")
        XCTAssertLessThanOrEqual(w.cache.count, 2 + 1)
        XCTAssertTrue(w.loaded(0, 0) && w.loaded(100, 100))
        // memory-only worlds keep unsaved edits
        let m = world(10)
        m.setTile(2, 5, 5, wall)
        m.chunk(9, 9)
        m.purge()
        XCTAssertTrue(m.loaded(0, 0) && !m.loaded(9, 9))
    }

    func testSurveyAndSnapshot() {
        let w = world(13)
        let before = w.cache.count
        var total = 0
        for _ in 0..<20 { total += w.survey(center: TilePos(0, 0), count: 50) }
        XCTAssertEqual(total, 1000)
        XCTAssertEqual(w.cache.count, before)
        XCTAssertNotEqual(w.known(-10, 10), 0)
        XCTAssertEqual(w.known(5000, 5000), 0)
        let data = try! JSONEncoder().encode(w.snapshot())
        let w2 = world(13)
        w2.restore(try! JSONDecoder().decode(OpenWorld.Snapshot.self, from: data))
        XCTAssertEqual(w2.surveyed, 1000)
        XCTAssertEqual(w2.known(-10, 10), w.known(-10, 10))
    }

    func testCropsGrowWhileEvicted() {
        let w = world(14)
        w.open(directory: tmp("grow"))
        let c = Content.shared
        w.setTile(0, 3, 3, c.tid("farmland"))
        w.setTile(2, 3, 3, c.tid("wheat_0"))
        w.purge()
        XCTAssertFalse(w.loaded(0, 0))
        w.time += 1000
        XCTAssertEqual(w.tile(2, 3, 3), c.tid("wheat_2"))
    }
}
