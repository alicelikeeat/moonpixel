import XCTest
@testable import MoonPixelCore

/// The sea has its creatures: they appear in open water and swim only in water.
final class SeaLifeTests: XCTestCase {
    func testTheSeaFillsWithItsCreaturesAndTheyStayInTheWater() {
        let s = makeSociety(7)
        s.realm.fauna.animals = []
        let o = TilePos(9000, 9000)
        let deep = s.content.tid("deep_water")
        for dy in -60...60 { for dx in -60...60 { s.world.setTile(0, o.x + dx, o.y + dy, deep); for l in 1...3 { s.world.setTile(l, o.x + dx, o.y + dy, 0) } } }
        // an island in the middle, where the viewer floats
        let viewer = o.center
        for _ in 0..<600 { _ = s.faunaTick(0.5, viewer: viewer, mazeHere: false) }
        let sea = s.realm.fauna.animals.filter { $0.species.aquatic }
        XCTAssertGreaterThan(sea.count, 3, "the sea fills with life")
        XCTAssertTrue(s.realm.fauna.animals.allSatisfy { $0.species.aquatic }, "nothing of the land comes up in open sea")
        let kinds = Set(sea.map { $0.species.key })
        XCTAssertTrue(kinds.isSubset(of: Set(Species.deepSea)), "deep water has its own: \(kinds)")
        for a in sea { XCTAssertTrue(s.content.water[Int(s.world.tile(0, a.pos.tile.x, a.pos.tile.y))], "\(a.species.key) is in the water") }
        // a whale by the shore never comes onto land
        let shore = TilePos(o.x + 61, o.y)
        for dx in 61...80 { s.world.setTile(0, o.x + dx, o.y, s.content.tid("grass")) }
        let id = s.spawnAnimal("whale", at: TilePos(o.x + 58, o.y).center)
        for i in s.realm.fauna.animals.indices where s.realm.fauna.animals[i].id == id { s.realm.fauna.animals[i].to = shore.center + Vec2(200, 0); s.realm.fauna.animals[i].think = 100 }
        for _ in 0..<40 { _ = s.faunaTick(0.25, viewer: viewer + Vec2(2000, 0), mazeHere: false) }
        if let w = s.realm.fauna.animals.first(where: { $0.id == id }) { XCTAssertTrue(s.content.water[Int(s.world.tile(0, w.pos.tile.x, w.pos.tile.y))], "the whale stays in the sea") }
        // every sea creature has a picture
        for sp in Species.all where sp.aquatic {
            let b = PixelArt.animal(sp, frame: 0, tame: false)
            var ink = 0
            for y in 0..<b.h { for x in 0..<b.w where b.get(x, y).a > 0 { ink += 1 } }
            XCTAssertGreaterThan(ink, 20, sp.key)
            XCTAssertGreaterThan(Figure3D.animal(sp, frame: 0).positions.count, 0, sp.key)
        }
    }
}
