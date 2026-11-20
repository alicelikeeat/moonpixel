import XCTest
@testable import MoonPixelCore

final class InventoryTests: XCTestCase {
    func setUpWorld() -> (Society, Body) {
        let s = makeSociety(6)
        let t = s.world.findFree(near: s.settlements.values.sorted { $0.id < $1.id }[0].center, maxR: 8)
        let b = Body(at: t.center, z: Double(Terrain3D.groundY(world: s.world, at: t.center)), depth: 0)
        s.realm.player.body = b
        return (s, b)
    }
    func total(_ s: Society) -> [String: Double] { s.ownedTotal() }

    func testEquipDropPickUpAndStoreAddUpAndACommandIsDoneOnce() {
        let (s, b) = setUpWorld()
        s.carry("weapons", 3); s.carry("armor", 1); s.carry("wood", 50)
        let t0 = total(s)
        XCTAssertTrue(s.inventory(1, .equip("weapons")).ok)
        XCTAssertEqual(s.carried("weapons"), 2, "the unit in hand left the pack")
        XCTAssertEqual(s.inventory(1, .equip("weapons")).amount, 1)
        XCTAssertEqual(s.carried("weapons"), 2, "the same command again changes nothing")
        XCTAssertTrue(s.inventory(2, .equip("tools")).reason == "none")
        s.carry("tools", 1)
        XCTAssertTrue(s.inventory(3, .equip("tools")).ok)
        XCTAssertEqual(s.inv.equipped["hand"], "tools"); XCTAssertEqual(s.carried("weapons"), 3, "the weapon went back to the pack")
        s.carry("tools", -0)
        let t1 = total(s); XCTAssertEqual(t1["weapons"], t0["weapons"]); XCTAssertEqual(t1["tools"], 1)
        // drop half the wood, pick it up again
        let d = s.inventory(4, .drop("wood", 20), at: b)
        XCTAssertTrue(d.ok); XCTAssertEqual(s.carried("wood"), 30)
        XCTAssertEqual(s.inv.dropped.count, 1)
        XCTAssertEqual(total(s)["wood"], 50, "dropped is still in the world, counted once")
        _ = s.inventory(4, .drop("wood", 20), at: b)
        XCTAssertEqual(s.inv.dropped.count, 1, "a repeated drop drops nothing more")
        var far = b; far.x += 400
        XCTAssertEqual(s.inventory(5, .pickUp(s.inv.dropped[0].id), at: far).reason, "out of reach")
        let p = s.inventory(6, .pickUp(s.inv.dropped[0].id), at: b)
        XCTAssertEqual(p.amount, 20); XCTAssertTrue(s.inv.dropped.isEmpty); XCTAssertEqual(s.carried("wood"), 50)
        XCTAssertEqual(s.inventory(6, .pickUp(99), at: b).amount, 20, "the first result is given back, nothing is picked twice")
        XCTAssertEqual(s.carried("wood"), 50)
        // a hotbar place is a pointer, not a copy
        _ = s.inventory(7, .bind(0, "wood"))
        XCTAssertEqual(s.inv.hotbar[0], "wood"); XCTAssertEqual(total(s)["wood"], 50)
        // and through a save
        let back = try! JSONDecoder().decode(PlayerState.self, from: JSONEncoder().encode(s.realm.player))
        XCTAssertEqual(back.invBox, s.realm.player.invBox)
    }

    func testAFullPackTakesOnlyWhatFitsAndSaysHowMuch() {
        let (s, b) = setUpWorld()
        s.carry("stone", (s.invCfg.capacity - 100 - s.packWeight()) / 1.5)    // 100 short of full
        let had = s.carried("stone")
        s.realm.player.invBox = InventoryState()
        var st = s.inv
        st.dropped = [Dropped(id: 1, key: "stone", amount: 100, x: b.x, y: b.y, depth: 0, t: 0)]; st.nextDrop = 2
        s.inv = st
        let r = s.inventory(1, .pickUp(1), at: b)
        XCTAssertTrue(r.ok); XCTAssertEqual(r.reason, "pack full")
        XCTAssertEqual(r.amount, 100.0 / 1.5, accuracy: 1e-6, "only what the weight allows")
        XCTAssertEqual(s.inv.dropped[0].amount, 100 - r.amount, accuracy: 1e-6, "the rest stays on the ground")
        XCTAssertEqual(s.carried("stone") + s.inv.dropped[0].amount, had + 100, accuracy: 1e-6)
    }

    func testNothingIsDroppedIntoTheAirOrIntoAWall() {
        let (s, b) = setUpWorld()
        s.carry("wood", 10)
        var air = b; air.depth = OpenWorld.storeyBase + 3                   // storey 3, nothing built there
        XCTAssertEqual(s.inventory(1, .drop("wood", 5), at: air).reason, "nowhere to put it")
        var carBody = b; carBody.platform = 7
        XCTAssertEqual(s.inventory(2, .drop("wood", 5), at: carBody).reason, "nowhere to put it")
        XCTAssertEqual(s.carried("wood"), 10, "nothing left the pack")
        // on a storey floor it lies on that storey, not on the ground beneath
        let o = s.world.findFree(near: b.pos.tile + TilePos(10, 0), maxR: 10)
        s.raiseHouse(at: o, storeys: 2)
        var up = Body(at: TilePos(o.x + 3, o.y + 3).center, z: 2, depth: OpenWorld.storeyBase + 1)
        XCTAssertTrue(s.inventory(3, .drop("wood", 4), at: up).ok)
        XCTAssertEqual(s.inv.dropped.last?.depth, OpenWorld.storeyBase + 1)
        up.depth = 0
        XCTAssertEqual(s.inventory(4, .pickUp(s.inv.dropped.last!.id), at: up).reason, "out of reach", "not from the ground floor below")
    }

    func testEatingIsWhatEndsHungerAndMealsSpoil() {
        let (s, _) = setUpWorld()
        s.realm.player.food = 0
        let h0 = s.inv.hunger
        for _ in 0..<24 { s.travellerHourly(); s.world.time += Society.hour }
        XCTAssertGreaterThanOrEqual(s.inv.hunger, min(1, h0 + 0.85), "a day without eating")
        XCTAssertEqual(s.inventory(1, .eat("food", 1)).reason, "none", "nothing to eat: hunger stays")
        XCTAssertGreaterThan(s.inv.hunger, 0.9)
        s.carry("meal", 4)
        let r = s.inventory(2, .eat("meal", 4))
        XCTAssertTrue(r.ok)
        XCTAssertEqual(s.inv.hunger, 0, accuracy: 1e-9)
        XCTAssertLessThan(r.amount, 4, "a full traveller stops eating")
        XCTAssertEqual(s.carried("meal"), 4 - r.amount, accuracy: 1e-9)
        XCTAssertEqual(s.inventory(3, .eat("meal", 1)).reason, "full")
        // starving hurts
        var st = s.inv; st.hunger = 1; s.inv = st
        let hp = s.realm.player.hp
        s.travellerHourly()
        XCTAssertLessThan(s.realm.player.hp, hp)
        // meals keep two days; grain a year (the traveller is kept alive meanwhile: dying halves the pack)
        s.realm.player.god = true
        s.carry("food", 100)
        let meals = s.carried("meal")
        for _ in 0..<(24 * 4 + 1) { s.world.time += Society.hour; s.travellerHourly() }
        XCTAssertLessThan(s.carried("meal"), meals * 0.1, "meals spoil (half a day for four days)")
        XCTAssertGreaterThan(s.carried("food"), 98.8, "grain keeps (a 360th a day)")
        XCTAssertGreaterThan(s.inv.spoiled["meal"] ?? 0, 0)
    }

    func testATownStoreTakesAndGivesAtomically() {
        let (s, b) = setUpWorld()
        let town = s.settlements.values.sorted { $0.id < $1.id }[0]
        s.playerJoin(town.nation ?? 0)
        s.carry("iron", 10)
        let had = town.good("iron")
        let r = s.inventory(1, .deposit("iron", 10, town: town.id), at: b)
        XCTAssertTrue(r.ok)
        XCTAssertEqual(town.good("iron") + s.carried("iron"), had + 10, accuracy: 1e-9)
        let w = s.inventory(2, .withdraw("iron", 4, town: town.id), at: b)
        XCTAssertEqual(w.amount, 4); XCTAssertEqual(town.good("iron") + s.carried("iron"), had + 10, accuracy: 1e-9)
        XCTAssertEqual(s.inventory(2, .withdraw("iron", 4, town: town.id), at: b).amount, 4)
        XCTAssertEqual(town.good("iron") + s.carried("iron"), had + 10, accuracy: 1e-9, "a repeated withdraw takes nothing more")
        // another nation's store is not ours to take from
        s.playerJoin(0)
        let other = s.realm.nations.map { $0.id }.first { $0 != town.nation }!
        s.playerJoin(other)
        XCTAssertEqual(s.inventory(3, .withdraw("iron", 1, town: town.id), at: b).reason, "not yours")
    }
}
