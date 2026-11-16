import XCTest
@testable import MoonPixelCore

/// Commands: the same command twice is done once; cancelling gives back what was held; a command on a
/// changed city is refused; a command for a later step runs then and once; all of it survives a save.
final class CommandTests: XCTestCase {
    func setUpWorld() -> (Civ, Int, CivCity, CivCity) {
        let c = Civ(seed: 3)
        for x in 0...3 { var r = CivRegion(); r.rx = x; r.land = 1; r.fertility = 0.6; r.ore = 0.5; r.coal = 0.5; c.regions[r.key] = r }
        let n = c.newPolity(origin: "first", near: nil)
        c.polities[n]!.techs = CivTech.all.map { $0.key }; c.polities[n]!.ai = false; c.polities[n]!.builds = false
        func town(_ x: Int) -> CivCity {
            let t = c.newCity(at: MP.chunkKey(x, 0), nation: n, people: CivPeople(adults: 800, children: 200, elders: 100), firstCount: true)
            t.facilities = ["farm": 300, "house": 250, "well": 40, "frame_works": 1, "barracks": 1, "plant": 4, "fusion_plant": 1]
            t.stock = ["grain": 40000, "timber": 500, "stone": 500, "steel": 100, "armor": 30]
            c.totals.add(\.found, "grain", 40000)
            return t
        }
        return (c, n, town(0), town(3))
    }

    func testTheSameCommandTwiceIsDoneOnce() {
        let (c, n, a, b) = setUpWorld()
        let order = WorldCommand(id: "tap-1", issuer: n, .order(city: a.id, kind: "frame"))
        let r1 = c.execute(order), r2 = c.execute(order)
        XCTAssertTrue(r1.ok); XCTAssertTrue(r2.repeated); XCTAssertEqual(r1.ref, r2.ref)
        XCTAssertEqual(c.projects.count, 1, "one machine on order, not two")
        let timber = a.stock["timber"]!
        let build = WorldCommand(id: "tap-2", issuer: n, .build(city: a.id, facility: "house"))
        c.execute(build); c.execute(build); c.execute(build)
        XCTAssertEqual(a.stock["timber"]!, timber - 10, "paid once")
        XCTAssertEqual(a.builds.count, 1)
        let ship = WorldCommand(id: "tap-3", issuer: n, .ship(from: a.id, to: b.id, goods: ["grain": 500]))
        c.execute(ship); c.execute(ship)
        XCTAssertEqual(c.trips.count, 1, "one convoy")
        XCTAssertEqual(c.audit(), [])
    }

    func testCancellingGivesBackWhatWasHeldAndHalfOfWhatWasUsed() {
        let (c, n, a, _) = setUpWorld()
        let pid = c.execute(WorldCommand(id: "o", issuer: n, .order(city: a.id, kind: "frame"))).ref!
        XCTAssertEqual(a.reserved["steel"], 60, "the first stage's steel is held aside at once")
        XCTAssertEqual(a.free("steel"), 40, "and nothing else can spend it")
        XCTAssertFalse(c.execute(WorldCommand(id: "b", issuer: n, .build(city: a.id, facility: "laboratory"))).ok, "a laboratory needs 30 steel the frame is holding... and parts it does not have")
        c.advance(to: c.time + MP.daySeconds)
        XCTAssertNil(a.reserved["steel"], "used, so no longer held")
        XCTAssertEqual(c.projects[pid]?.invested["steel"], 60)
        let steel = a.stock["steel"]!
        c.execute(WorldCommand(id: "x", issuer: n, .cancel(project: pid)))
        XCTAssertNil(c.projects[pid])
        XCTAssertEqual(a.stock["steel"]!, steel + 30, accuracy: 1e-9, "half comes back")
        XCTAssertEqual(c.totals.lost["steel"] ?? 0, 30, accuracy: 1e-9, "the rest is booked as lost, not made to vanish")
        XCTAssertTrue(a.reserved.isEmpty)
        XCTAssertEqual(c.audit(), [])
    }

    func testACommandOnAChangedCityIsRefusedAndOthersCannotGiveOrders() {
        let (c, n, a, _) = setUpWorld()
        let seen = a.rev
        XCTAssertTrue(c.execute(WorldCommand(id: "1", issuer: n, expect: seen, .build(city: a.id, facility: "house"))).ok)
        let r = c.execute(WorldCommand(id: "2", issuer: n, expect: seen, .build(city: a.id, facility: "house")))
        XCTAssertFalse(r.ok); XCTAssertEqual(r.reason, "stale", "decided on a city that has since changed")
        let other = c.newPolity(origin: "first", near: nil)
        XCTAssertEqual(c.execute(WorldCommand(id: "3", issuer: other, .ration(city: a.id, policy: .emergency))).reason, "not_yours")
    }

    func testACommandForALaterStepRunsThenAndOnceAndSurvivesASave() throws {
        let (c, n, a, _) = setUpWorld()
        let at = c.step + 5
        let cmd = WorldCommand(id: "later", issuer: n, step: at, .build(city: a.id, facility: "house"))
        XCTAssertEqual(c.execute(cmd).reason, "queued")
        XCTAssertEqual(a.builds.count, 0)
        // saved while it waits, and loaded again: it still runs, once
        let back = try JSONDecoder().decode(Civ.self, from: JSONEncoder().encode(c))
        let a2 = back.cities[a.id]!
        for _ in 0..<4 { back.advance(to: back.time + MP.daySeconds / 24) }
        XCTAssertEqual(a2.builds.count, 0, "not before its step")
        for _ in 0..<3 { back.advance(to: back.time + MP.daySeconds / 24) }
        XCTAssertEqual(a2.builds.count, 1, "at its step")
        // the same command sent again after the save: remembered, not done twice
        XCTAssertTrue(back.execute(cmd).repeated)
        back.advance(to: back.time + MP.daySeconds / 24)
        XCTAssertEqual(a2.builds.count + a2.has("house") - 250, 1)
        XCTAssertEqual(back.audit(), [])
    }

    func testAConvoyWhoseDestinationFallsGoesBackAndNothingIsCountedTwice() {
        let (c, n, a, b) = setUpWorld()
        let grain = c.foodHeld()["grain"]!
        guard let tid = c.execute(WorldCommand(id: "s", issuer: n, .ship(from: a.id, to: b.id, goods: ["grain": 1000]))).ref else { return XCTFail("no convoy") }
        XCTAssertEqual(a.stock["grain"]!, 39000, "taken from the store at once")
        XCTAssertEqual(c.trips[tid]!.cargo["grain"], 1000, "and on the road, not in both places")
        // the destination is lost to another nation while the convoy is on the road
        let foe = c.newPolity(origin: "first", near: nil)
        c.transfer(b, to: foe)
        c.advance(to: c.time + 6 * MP.daySeconds)
        XCTAssertNil(c.trips[tid])
        XCTAssertEqual(b.yesterday.cameIn["grain"] ?? 0, 0, "the new masters of the town do not get the grain")
        XCTAssertGreaterThan(a.ledger.cameIn["grain"] ?? 0, 999, "it came back home")
        XCTAssertEqual(c.foodHeld()["grain"]!, c.foodExpected()["grain"]!, accuracy: 1e-6, "every grain is somewhere, once")
        XCTAssertEqual(c.audit(), [])
        _ = grain
    }
}
