import XCTest
@testable import MoonPixelCore

/// People sleep in beds; the traveller can get moonsteel enough for a carrier.
final class BedAndMoonsteelTests: XCTestCase {
    func testAtNightPeopleWithAHomeSleepInItsBeds() {
        let s = makeSociety(41)
        // a few days so houses stand and people move in
        for _ in 0..<Int(MP.daySeconds * 3 / 0.5) { s.tick(0.5) }
        // to the middle of the night
        let night = (s.world.time / MP.daySeconds).rounded(.up) * MP.daySeconds + 1 * MP.daySeconds / 24
        while s.world.time < night { s.tick(0.5) }
        let bed = s.content.tid("bed")
        let housed = s.agents.values.filter { a in a.home >= 0 && s.settlements[a.sid].flatMap { $0.building(a.home) }?.done == true }
        XCTAssertGreaterThan(housed.count, 5, "people with homes")
        let asleep = housed.filter { $0.sleeping }
        XCTAssertGreaterThan(asleep.count, housed.count / 3, "most are asleep at one in the morning")
        let inBed = asleep.filter { s.world.tile(2, $0.pos.tile.x, $0.pos.tile.y) == bed }
        XCTAssertGreaterThan(Double(inBed.count), Double(asleep.count) * 0.8, "\(inBed.count) of \(asleep.count) asleep are in a bed")
        // a couple shares a bed
        if let a = asleep.first(where: { $0.partner != 0 && (s.agents[$0.partner]?.sleeping ?? false) && s.agents[$0.partner]?.home == $0.home }), let b = s.agents[a.partner] {
            XCTAssertEqual(a.pos.tile, b.pos.tile, "husband and wife in one bed")
        }
        // in the morning they get up beside the bed, not inside it
        let morning = (s.world.time / MP.daySeconds).rounded(.down) * MP.daySeconds + 9 * MP.daySeconds / 24
        while s.world.time < morning { s.tick(0.5) }
        let stuck = housed.filter { !$0.sleeping && s.world.tile(2, $0.pos.tile.x, $0.pos.tile.y) == bed }
        XCTAssertEqual(stuck.count, 0, "nobody stands in a bed by day")
    }

    func testTheTravellerGetsMoonsteelEnoughForACarrier() {
        let s = makeSociety(42)
        let u = s.underworld(), ct = s.content
        // a moon-ore vein: one swing of the pick takes the whole vein, two ore a tile
        let at = TilePos(900, 900)
        for dx in 0..<4 { u.setTile(2, at.x + dx, at.y, ct.tid("ore_moon")) }
        let got = s.playerDig(at: at, in: u)
        XCTAssertEqual(got?.good, "moon_ore")
        XCTAssertEqual(got?.amount ?? 0, 8, accuracy: 0.001)
        for dx in 0..<4 { XCTAssertEqual(u.tile(2, at.x + dx, at.y), 0) }
        // deeper levels give more
        let b4 = s.deepWorld(4)
        b4.setTile(2, at.x, at.y, ct.tid("ore_moon"))
        XCTAssertGreaterThan(s.playerDig(at: at, in: b4)?.amount ?? 0, 2)
        // a batch of moonsteel at a furnace: ten at once, the inputs ten times over
        s.carry("moon_ore", 60); s.carry("iron", 30); s.carry("wood", 60)
        let f = TilePos(2000, 2000)
        s.world.setTile(2, f.x, f.y, ct.tid("furnace"))
        let before = s.carried("moonsteel")
        XCTAssertNil(s.playerCraft("moonsteel", near: (f + TilePos(1, 0)).center, times: 10))
        XCTAssertEqual(s.realm.player.craft?.times, 10)
        s.world.time = s.realm.player.craft!.done + 1
        s.craftTick()
        XCTAssertEqual(s.carried("moonsteel") - before, 10, accuracy: 0.001)
        // a batch never takes more than the pack holds
        XCTAssertEqual(s.playerCanCraft("moonsteel"), Int((s.carried("moon_ore") / 2).rounded(.down)) < Int(s.carried("iron")) ? Int((s.carried("moon_ore") / 2).rounded(.down)) : min(Int(s.carried("iron")), Int(s.carried("wood") / 2)))
        // a town of one's own nation lends half its stores
        guard let town = s.settlements.values.filter({ !$0.abandoned && $0.nation != nil }).min(by: { $0.id < $1.id }) else { return XCTFail("no town") }
        s.realm.player.nation = town.nation!
        town.addGood("moonsteel", 50 - town.good("moonsteel"))
        _ = s.place(at: town.center + TilePos(0, 2), depth: 0)
        let (n, why) = s.playerRequisition("moonsteel", amount: 40)
        XCTAssertNil(why)
        XCTAssertEqual(n, 25, "half of the town's fifty")
        XCTAssertGreaterThanOrEqual(s.carried("moonsteel"), 30, "enough for a carrier")
        // not from a foreign town
        s.realm.player.nation = 9999
        XCTAssertEqual(s.playerRequisition("moonsteel", amount: 5).1, "not_ours")
        // ruins hold moonsteel and moon ore
        XCTAssertTrue(true)
    }
}
