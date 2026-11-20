import XCTest
@testable import MoonPixelCore

/// A bigger pack, made bigger again from its own materials; and what is put down lies in a supply box.
final class SupplyBoxTests: XCTestCase {
    func standing(_ s: Society) -> Body {
        let t = s.world.findFree(near: TilePos(4, 4), maxR: 20)
        var b = Body(); b.x = t.center.x; b.y = t.center.y; b.depth = 0
        b.z = WorldGround(s).floor(0, t) ?? 0
        s.realm.player.body = b
        // clear round the traveller so there is room for a box
        for dy in -2...2 { for dx in -2...2 where dx != 0 || dy != 0 { s.world.setTile(2, t.x + dx, t.y + dy, 0) } }
        return b
    }

    func testThePackCarriesWhatACarrierTakesAndGrowsFromItsOwnMaterials() {
        let s = makeSociety(31)
        XCTAssertGreaterThanOrEqual(s.invCfg.capacity, 400 * 1.5 + 200 + 30 * 1.2, "iron, parts and moonsteel for an aircraft carrier fit in the first pack")
        XCTAssertEqual(s.upgradePack(), "need iron")
        s.carry("wood", 80); s.carry("iron", 30)
        XCTAssertNil(s.upgradePack())
        XCTAssertEqual(s.realm.player.packLevel, 1)
        XCTAssertEqual(s.invCfg.capacity, PackTune.capacity[1])
        XCTAssertEqual(s.carried("wood"), 0, accuracy: 1e-9, "made from what the pack held")
        for _ in 2..<PackTune.capacity.count { for (k, v) in PackTune.cost(from: s.realm.player.packLevel!) { s.carry(k, v) }; XCTAssertNil(s.upgradePack()) }
        XCTAssertEqual(s.upgradePack(), "largest")
    }

    func testWhatIsPutDownLiesInASupplyBoxThatATapOpens() {
        let s = makeSociety(32)
        let b = standing(s)
        let box = s.content.tid("supply_box")
        s.carry("iron", 50); s.carry("wood", 20)
        XCTAssertTrue(s.inventory(1, .drop("iron", 30)).ok)
        guard let d = s.inv.dropped.first, let x = d.bx, let y = d.by else { return XCTFail("a box") }
        XCTAssertEqual(s.world.tile(2, x, y), box, "a block on the tile beside the traveller")
        XCTAssertNotEqual(TilePos(x, y), b.pos.tile, "not under the traveller's feet")
        // more of the same joins its stack; another kind shares the box
        XCTAssertTrue(s.inventory(2, .drop("iron", 10)).ok)
        XCTAssertTrue(s.inventory(3, .drop("wood", 20)).ok)
        XCTAssertEqual(s.boxContents(TilePos(x, y), depth: 0).count, 2)
        XCTAssertEqual(s.boxContents(TilePos(x, y), depth: 0).first { $0.key == "iron" }?.amount ?? 0, 40, accuracy: 1e-9)
        // a tap opens it: everything back in the pack, the box goes
        let r = s.inventory(4, .openBox(x, y, depth: 0))
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.amount, 60, accuracy: 1e-9)
        XCTAssertEqual(s.carried("iron"), 50, accuracy: 1e-9)
        XCTAssertEqual(s.world.tile(2, x, y), 0, "an empty box goes")
        XCTAssertTrue(s.inv.dropped.isEmpty)
    }
}
