import XCTest
@testable import MoonPixelCore

/// Anything can be broken; who may break what (task book: 全物品与方块破坏).
final class DamageTests: XCTestCase {
    func patch(_ s: Society, at o: TilePos, size: Int = 10) {
        let grass = s.content.tid("grass")
        for dy in 0..<size { for dx in 0..<size {
            s.world.setTile(0, o.x + dx, o.y + dy, grass)
            for l in 1...3 { s.world.setTile(l, o.x + dx, o.y + dy, 0) }
        } }
    }

    func testThePlayerBreaksATreeARockAWallAndGetsItsMaterialsOnce() {
        let s = makeSociety(7)
        let o = TilePos(5000, 5000)
        patch(s, at: o)
        let tree = o, rock = TilePos(o.x + 2, o.y), wall = TilePos(o.x + 4, o.y)
        s.world.setTile(2, tree.x, tree.y, s.content.tid("tree_oak"))
        s.world.setTile(2, rock.x, rock.y, s.content.tid("rock"))
        s.world.setTile(2, wall.x, wall.y, s.content.tid("wall_stone"))
        let wood0 = s.realm.player.wood, stone0 = s.realm.player.stone
        // a tree: four bare-hand hits; each wears it, the last fells it
        var r = s.hitTile(tree, by: .player)
        XCTAssertEqual(r.material, .wood)
        XCTAssertFalse(r.broke); XCTAssertLessThan(r.left, 1)
        var hits = 1
        while !r.broke && hits < 20 { r = s.hitTile(tree, by: .player); hits += 1 }
        XCTAssertTrue(r.broke)
        XCTAssertEqual(s.world.tile(2, tree.x, tree.y), 0, "gone")
        // stone takes longer than wood; metal longer still
        var rh = 0
        while s.world.tile(2, rock.x, rock.y) != 0 && rh < 50 { s.hitTile(rock, by: .player); rh += 1 }
        XCTAssertEqual(rh, Int(Material.stone.durability))
        XCTAssertEqual(s.realm.player.stone - stone0, 3, "a rock gives its stone once")
        // a wall of a building: the player may
        var wh = 0
        while s.world.tile(2, wall.x, wall.y) != 0 && wh < 50 { s.hitTile(wall, by: .player); wh += 1 }
        XCTAssertEqual(s.world.tile(2, wall.x, wall.y), 0, "a hole in the wall")
        XCTAssertFalse(s.world.blocked(wall.x, wall.y), "and one can walk through it")
        // hitting the empty spot again breaks the ground (grass to dirt) and gives nothing twice for the wall
        let stone1 = s.realm.player.stone
        _ = s.hitTile(wall, power: 100, by: .player)
        XCTAssertEqual(s.content.tile(s.world.tile(0, wall.x, wall.y))?.key, "dirt")
        XCTAssertEqual(s.realm.player.stone - stone1, 1, "the earth gives a little; the wall nothing more")
        _ = wood0
    }

    func testWearIsSavedWithTheChunk() {
        let s = makeSociety(7)
        let o = TilePos(5200, 5000)
        patch(s, at: o)
        s.world.setTile(2, o.x, o.y, s.content.tid("wall_stone"))
        for _ in 0..<3 { s.hitTile(o, by: .player) }
        let ch = s.world.chunk(o.x >> 5, o.y >> 5)
        let back = Chunk.decode(ch.encoded())!
        XCTAssertEqual(back.wear, ch.wear, "half-broken stays half-broken across a save")
        XCTAssertFalse(back.wear.isEmpty)
    }

    /// A world run until its towns have finished a building.
    func grown() -> Society {
        let s = makeSociety(7)
        var n = 0
        while !s.settlements.values.contains(where: { $0.buildings.contains { $0.done } }) && n < 20000 { s.tick(2); n += 1 }
        return s
    }

    func testABuilderClearsOnlyItsGroundAndGoesRoundBuildings() {
        let s = grown()
        guard let town = s.settlements.values.sorted(by: { $0.id < $1.id }).first(where: { !$0.buildings.isEmpty }),
              let b = town.buildings.first else { return XCTFail("no town building") }
        let inBuilding = TilePos(b.x, b.y)
        let o = TilePos(5400, 5000)
        patch(s, at: o)
        for i in 0..<3 { s.world.setTile(2, o.x + i, o.y, s.content.tid("tree_pine")) }
        s.world.setTile(2, o.x + 5, o.y, s.content.tid("tree_pine"))             // not in the clearing
        let road: Set<TilePos> = [TilePos(o.x, o.y), TilePos(o.x + 1, o.y), TilePos(o.x + 2, o.y), inBuilding]
        let wood0 = s.settlements.values.reduce(0) { $0 + $1.wood }
        for t in road.sorted(by: { $0.x < $1.x }) { for _ in 0..<10 { s.hitTile(t, by: .builder(clearing: road)) } }
        for i in 0..<3 { XCTAssertEqual(s.world.tile(2, o.x + i, o.y), 0, "the trees on the road are felled") }
        XCTAssertNotEqual(s.world.tile(2, o.x + 5, o.y), 0, "the wood round it stands")
        XCTAssertEqual(s.hitTile(TilePos(o.x + 5, o.y), by: .builder(clearing: road)).refused, "not_cleared")
        XCTAssertEqual(s.hitTile(inBuilding, by: .builder(clearing: road)).refused, "protected", "a building on the way: refused, goes round")
        XCTAssertEqual(s.settlements.values.reduce(0) { $0 + $1.wood }, wood0 + 9, accuracy: 1e-9, "the timber of three trees goes into a town's stores")
    }

    func testAWarStrikesOnlyItsTargetAndStopsAtTheTruce() {
        let s = grown()
        s.civHourly()
        let c = s.civ
        guard let city = c.cities.values.sorted(by: { $0.id < $1.id }).first(where: { $0.detail != nil && s.settlements[$0.detail!]?.buildings.contains { $0.done } == true }),
              let town = s.settlements[city.detail!] else { return XCTFail("no detailed city with a building") }
        let attacker = c.newPolity(origin: "first", near: nil)
        c.declare(attacker, on: city.nation)
        let wid = c.startTargetWar(attacker, on: city.nation, target: city.id, kind: "city", envoy: nil)!
        let w = c.targetWars.first { $0.id == wid }!
        let targets = s.warTargets(w)
        let b = town.buildings.first { $0.done }!
        XCTAssertTrue(targets.contains(TilePos(b.x, b.y)) && targets.contains(TilePos(b.x + b.w - 1, b.y + b.h - 1)), "the mark covers every block of a building")
        let spot = targets.sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }.first { t in [1, 2].contains { s.world.tile($0, t.x, t.y) != 0 } }
        if let t = spot { XCTAssertNil(s.hitTile(t, by: .war(attacker: attacker, targetWar: wid)).refused, "a marked building may be struck") }
        let elsewhere = TilePos(5600, 5000)
        patch(s, at: elsewhere)
        s.world.setTile(2, elsewhere.x, elsewhere.y, s.content.tid("wall_stone"))
        XCTAssertEqual(s.hitTile(elsewhere, by: .war(attacker: attacker, targetWar: wid)).refused, "not_a_target", "nothing outside the target")
        // the truce: no more strikes, even on the target
        c.makePeace(attacker, city.nation)
        if let t = spot { XCTAssertEqual(s.hitTile(t, by: .war(attacker: attacker, targetWar: wid)).refused, "no_war") }
    }
}
