import XCTest
@testable import MoonPixelCore

/// The battle of the twin ports (task book, final demonstration), on fixed seeds.
final class TwinPortsTests: XCTestCase {
    /// Seeds fixed for the demonstration: the envoy is accepted with the first, refused with the others. With the
    /// frames dropped on the east port, it falls under `fallSeed` while the giantess carries its people west, and
    /// holds under `holdSeed` while she guards it (her watch halves the attackers' ratio).
    static let acceptSeed = 2, fallSeed = 8, holdSeed = 1

    func testAcceptedTheSmallNationKeepsItsColoursAndPaysTribute() {
        let t = TwinPorts(seed: TwinPortsTests.acceptSeed)
        let colour = t.c.polities[t.small]!.color
        XCTAssertFalse(t.envoy(), "seed \(TwinPortsTests.acceptSeed): the envoy is accepted")
        XCTAssertEqual(t.c.suzerain(of: t.small), t.great)
        XCTAssertEqual(t.c.polities[t.small]!.color, colour, "it keeps its colour")
        XCTAssertEqual(t.c.polities[t.small]!.capital, t.east.id, "and its capital")
        t.c.advance(to: t.c.time + 3 * MP.daySeconds)
        XCTAssertGreaterThan(t.c.vassals.first { $0.vassal == t.small }!.paid, 0, "tribute is paid")
        XCTAssertTrue(t.c.chronicle.contains { $0.kind == "vassal" })
    }

    func testRefusedTheEastPortFallsAndTheNextReckoningHasTheTanksAshore() throws {
        let t = TwinPorts(seed: TwinPortsTests.fallSeed)
        XCTAssertTrue(t.envoy(), "seed \(TwinPortsTests.fallSeed): the envoy is refused")
        XCTAssertEqual(t.c.targetWars.last?.target, t.east.id, "the war is for the east port (the capital's port)")
        t.opening(giant: .carryWest)
        XCTAssertTrue(t.c.fights.contains { $0.kind == "launch" } || t.c.chronicle.contains { $0.kind == "landing" }, "the carrier's fighters went up and the tanks came ashore")
        let w0 = t.c.targetWars.last!
        XCTAssertTrue(t.c.attack(on: w0).lines.contains { $0.contains("still on the ships") }, "the quay takes only so many: the rest wait on the ships")
        t.skyDrop(.eastPort)
        // saved while the frames fall: opened again, still two frames, landing once each
        let copy = try JSONDecoder().decode(Civ.self, from: try JSONEncoder().encode(t.c))
        XCTAssertEqual(copy.drops.count, 2)
        t.finish()
        XCTAssertEqual(t.c.units.values.filter { $0.kind == "frame" }.count, 2, "two frames, never more")
        XCTAssertEqual(t.east.nation, t.great, "the east port fell")
        XCTAssertEqual(t.c.legalOwner(t.east.regionKey), t.great, "the truce cedes it")
        XCTAssertEqual(t.c.relation(t.great, t.small)?.state, 2)
        // the next reckoning: through the port now held, tanks land as fast as the great power's own quay takes
        // them, and the west port is reached by land from it (no landing)
        XCTAssertEqual(t.c.landingRound(t.great, at: t.east).intake, 6000, accuracy: 1e-9)
        XCTAssertNotNil(t.c.route(from: t.east.regionKey, to: t.west.regionKey, size: .person), "the west port is reached by land now")
        let report = t.c.warLines(t.c.targetWars.last!, zh: true)
        XCTAssertTrue(report.head.contains("失守"), report.head)
        XCTAssertTrue(report.details.contains { $0.contains("比值") }, "the report lets the ratio be traced")
        XCTAssertEqual(t.c.audit(), [])
    }

    func testRefusedTheEastPortHoldsAndTheSmallNationKeepsItsWayToTheSea() {
        let t = TwinPorts(seed: TwinPortsTests.holdSeed)
        XCTAssertTrue(t.envoy(), "seed \(TwinPortsTests.holdSeed): the envoy is refused")
        t.opening(giant: .guardEast)
        t.skyDrop(.eastPort)
        t.finish()
        XCTAssertEqual(t.east.nation, t.small, "the east port held")
        XCTAssertEqual(t.c.targetWars.last?.stage, .truce, "withdrawal, then a truce")
        XCTAssertTrue(t.c.chronicle.contains { $0.kind == "kept_the_sea" }, "the small nation keeps its way to the sea")
        XCTAssertNotNil(t.c.seaAccess(t.small))
        XCTAssertTrue(t.c.warLines(t.c.targetWars.last!, zh: true).head.contains("守住"))
    }

    func testFramesOnThePlatformCloseTheRoadBetweenThePorts() {
        let t = TwinPorts(seed: TwinPortsTests.holdSeed)
        _ = t.envoy()
        XCTAssertNotNil(t.c.landRoute(for: t.small, from: t.west.regionKey, to: t.east.regionKey), "the road over the platform is open")
        t.opening(giant: .carryWest)
        t.skyDrop(.platform)
        for _ in 0..<4 { t.c.advance(to: t.c.time + MP.daySeconds / 24) }
        XCTAssertEqual(t.c.heldPasses[t.platform], t.great, "frames on the platform hold it")
        XCTAssertNil(t.c.landRoute(for: t.small, from: t.west.regionKey, to: t.east.regionKey), "and the road between the ports is closed")
        XCTAssertTrue(t.c.chronicle.contains { $0.kind == "pass_held" })
        // the giantess carried people west: a rescue, not a watch
        let g = t.c.giants.first!
        XCTAssertEqual(g.rescued, 60); XCTAssertEqual(g.guardHours, 0)
    }

    func testTheSameSeedAndChoicesGiveTheSameChronicle() {
        func play() -> [CivEvent] {
            let t = TwinPorts(seed: TwinPortsTests.fallSeed)
            t.envoy(); t.opening(giant: .guardEast); t.skyDrop(.platform); t.finish()
            return t.c.chronicle
        }
        let a = play(), b = play()
        XCTAssertFalse(a.isEmpty)
        XCTAssertEqual(a, b, "a war can be replayed from its seed and orders")
    }
}
