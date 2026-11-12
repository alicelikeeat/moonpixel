import XCTest
@testable import MoonPixelCore

final class SocietyTests: XCTestCase {
    func make(_ seed: Int, villages: Int, per: Int) -> Society {
        let w = OpenWorld(seed: seed, budget: MemoryBudget(overrideMB: 256))
        let s = Society(world: w, seed: seed)
        s.bootstrap(origin: TilePos(0, 0), villages: villages, per: per)
        return s
    }

    func run(_ s: Society, years: Double) { for _ in 0..<Int(years * MP.year) { s.tick(1.0) } }

    func testPathGrid() {
        let g = PathGrid(size: 16)
        for y in 0..<15 { g.solid[y * 16 + 8] = true }
        let p = g.path(from: TilePos(2, 2), to: TilePos(13, 2))
        XCTAssertFalse(p.isEmpty)
        XCTAssertEqual(p.first, TilePos(2, 2)); XCTAssertEqual(p.last, TilePos(13, 2))
        XCTAssertTrue(p.contains(TilePos(8, 15)), "must walk around the wall")
        for t in p { XCTAssertFalse(g.solid[t.y * 16 + t.x]) }
        for y in 0..<16 { g.solid[y * 16 + 8] = true }
        XCTAssertTrue(g.path(from: TilePos(2, 2), to: TilePos(13, 2)).isEmpty)
    }

    func testBootstrapAndInteraction() {
        let s = make(7, villages: 4, per: 30)
        XCTAssertGreaterThanOrEqual(s.agents.count, 100)
        XCTAssertEqual(s.settlements.count, 4)
        let a = s.agents.values.sorted { $0.id < $1.id }[3]
        let info = s.talk(a.id)
        XCTAssertNotNil(info)
        XCTAssertFalse(info!.name.isEmpty || info!.line.isEmpty)
        a.hunger = 0.9
        XCTAssertTrue(s.giftFood(a.id))
        XCTAssertLessThan(a.hunger, 0.5)
        XCTAssertGreaterThan(a.rel[0] ?? 0, 0)
    }

    func testSocietyLivesBuildsBreedsAndDies() {
        let s = make(7, villages: 4, per: 30)
        run(s, years: 5)
        let st = s.stats
        print("after 5 years: pop=\(s.agents.count) births=\(st.births) deaths=\(st.deaths) pairs=\(st.pairs) buildings=\(st.buildings) tiles=\(st.tilesPlaced) villages=\(s.livingSettlements) surveyed=\(s.world.surveyed)")
        XCTAssertGreaterThan(st.births, 0)
        XCTAssertGreaterThan(st.deaths, 0)
        XCTAssertGreaterThan(st.pairs, 0)
        XCTAssertGreaterThanOrEqual(st.buildings, 8)
        XCTAssertGreaterThan(st.tilesPlaced, 500)
        XCTAssertGreaterThanOrEqual(s.agents.count, 100)
        XCTAssertGreaterThan(s.world.surveyed, 1000)
        let c = Content.shared
        var walls = 0
        for v in s.settlements.values { for b in v.buildings where b.type == "house" && b.done {
            for dy in 0..<b.h { for dx in 0..<b.w {
                let o = s.world.tile(2, b.x + dx, b.y + dy)
                if o == c.tid("wall_wood") || o == c.tid("wall_stone") { walls += 1 }
            } }
        } }
        XCTAssertGreaterThanOrEqual(walls, 14)
        for a in s.agents.values {
            if a.partner != 0, let p = s.agents[a.partner] { XCTAssertEqual(p.partner, a.id) }
            let t = a.pos.tile
            XCTAssertTrue(!s.world.blocked(t.x, t.y) || a.travelling, "nobody stuck in a wall")
        }
        XCTAssertGreaterThan(s.agents.values.filter { $0.mother != 0 }.count, 0)
    }

    func testSaveLoadRoundtrip() throws {
        let s = make(21, villages: 2, per: 20)
        run(s, years: 0.5)
        let data = try JSONEncoder().encode(s.snapshot())
        let wdata = try JSONEncoder().encode(s.world.snapshot())
        let w2 = OpenWorld(seed: 21, budget: MemoryBudget(overrideMB: 256))
        w2.restore(try JSONDecoder().decode(OpenWorld.Snapshot.self, from: wdata))
        let s2 = Society(world: w2, seed: 21)
        s2.restore(try JSONDecoder().decode(Society.Snapshot.self, from: data))
        XCTAssertEqual(s2.agents.count, s.agents.count)
        XCTAssertEqual(s2.settlements.count, s.settlements.count)
        XCTAssertEqual(s2.stats.tilesPlaced, s.stats.tilesPlaced)
        let a = s.agents.values.sorted { $0.id < $1.id }[0]
        XCTAssertEqual(s2.agents[a.id]?.nameEn, a.nameEn)
        XCTAssertEqual(s2.agents[a.id]?.partner, a.partner)
        run(s2, years: 0.1)
        XCTAssertGreaterThan(s2.agents.count, 0)
    }

    func testImmigrationKeepsWorldPopulated() {
        let s = make(5, villages: 1, per: 12)
        run(s, years: 1.5)
        XCTAssertGreaterThan(s.stats.immigrants, 0)
        XCTAssertGreaterThan(s.agents.count, 12)
    }
}
