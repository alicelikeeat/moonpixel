import XCTest
@testable import MoonPixelCore

/// Ways, clearing, bridges, tunnels and the choice of how to cross (task section 4).
final class NetworkTests: XCTestCase {
    func testThePreviewShowsWhatIsFelledAndTheWoodGoesToWhoeverPays() {
        let sc = TransportScene()
        let s = sc.s
        let p = s.planWay(.street, from: sc.t(36, 30), to: sc.t(60, 30))
        XCTAssertTrue(p.ok, p.reason)
        XCTAssertEqual(p.fell.count, TransportScene.forest.count, "every tree in its way, and only those")
        XCTAssertEqual(p.wood, Double(TransportScene.forest.count) * 4)
        XCTAssertTrue(p.spans.isEmpty)
        // nothing is felled by a preview
        XCTAssertEqual(s.world.tile(2, sc.t(45, 30).x, sc.t(45, 30).y), s.content.tid("tree_oak"))
        sc.give(p.cost, .pack)
        let wood0 = s.carried("wood")
        let id = s.startWay(p, payer: .pack)!
        XCTAssertEqual(s.carried("stone"), 0, accuracy: 1e-9, "paid once, in full, before work starts")
        // worked tile by tile: after a little time only part of it is done
        s.workSites(hours: 0.2)
        let site = s.realm.transport.sites.first { $0.id == id }!
        XCTAssertTrue(site.cells.contains { !$0.done } && site.cells.contains { $0.done })
        s.finishSite(id)
        for x in TransportScene.forest {
            let t = sc.t(x, 30)
            XCTAssertEqual(s.world.tile(2, t.x, t.y), 0, "felled")
            XCTAssertEqual(s.wayKind(at: t), .street)
            XCTAssertFalse(s.canPlant(t), "nothing is planted on a way")
            XCTAssertTrue(s.isCorridor(t))
        }
        XCTAssertEqual(s.carried("wood") - wood0, p.wood, accuracy: 1e-9, "the wood the preview promised, to the payer")
        XCTAssertTrue(s.realm.transport.ledger.contains { $0.note == "clearing" && $0.key == "wood" })
        // a plan the payer cannot afford takes nothing
        let q = s.planWay(.street, from: sc.t(36, 40), to: sc.t(60, 40))
        let stone0 = s.carried("stone")
        XCTAssertNil(s.startWay(q, payer: .pack))
        XCTAssertEqual(s.carried("stone"), stone0)
    }

    func testARiverIsCrossedOnlyByABridgeAndTakingItDownCutsTheWay() {
        var sc = TransportScene()
        sc.cities()
        let s = sc.s
        let car = Profile(mode: .road)
        XCTAssertNil(s.route(from: NetNode(sc.t(30, 60).x, sc.t(30, 60).y, 0), to: NetNode(sc.t(100, 60).x, sc.t(100, 60).y, 0), car), "no way across before a road is built")
        let p = sc.lay(.street, sc.t(36, 60), sc.t(90, 60), payer: .district(sc.a.id))
        XCTAssertEqual(p.spans.count, 1)
        XCTAssertEqual(p.spans[0].count, TransportScene.river.count, "a span over exactly the water")
        let br = s.realm.transport.bridges[0]
        XCTAssertEqual(br.kind, .road); XCTAssertEqual(br.hp, 1)
        let r = s.route(from: NetNode(sc.t(30, 60).x, sc.t(30, 60).y, 0), to: NetNode(sc.t(100, 60).x, sc.t(100, 60).y, 0), car)
        XCTAssertNotNil(r)
        XCTAssertTrue(r!.contains { $0.l == 1 }, "over the deck")
        XCTAssertFalse(r!.contains { $0.l == 0 && s.waterDepth($0.tile) > 0 }, "never on the water")
        // take it down: no way any more (and no road invented round it)
        s.demolishBridge(br.id)
        XCTAssertNil(s.route(from: NetNode(sc.t(30, 60).x, sc.t(30, 60).y, 0), to: NetNode(sc.t(100, 60).x, sc.t(100, 60).y, 0), car))
        for x in TransportScene.river { XCTAssertEqual(s.world.tile(1, sc.t(x, 60).x, sc.t(x, 60).y), 0, "the deck is gone") }
    }

    func testAViaductCarriesAHighwayOverAStreetWithoutJoiningIt() {
        let sc = TransportScene()
        let s = sc.s
        sc.lay(.street, sc.t(100, 20), sc.t(100, 40))                 // north-south street
        let p = sc.lay(.highway, sc.t(92, 30), sc.t(110, 30))          // east-west highway across it
        XCTAssertEqual(p.spans.count, 1)
        let v = s.realm.transport.bridges.first!
        XCTAssertEqual(v.kind, .viaduct)
        XCTAssertEqual(s.wayKind(at: sc.t(100, 30)), .street, "the street stays below")
        let car = Profile(mode: .road)
        // along the street under it, and along the highway over it, but not from one to the other there
        let under = s.route(from: NetNode(sc.t(100, 22).x, sc.t(100, 22).y, 0), to: NetNode(sc.t(100, 38).x, sc.t(100, 38).y, 0), car)!
        XCTAssertTrue(under.allSatisfy { $0.l == 0 })
        let over = s.route(from: NetNode(sc.t(93, 30).x, sc.t(93, 30).y, 0), to: NetNode(sc.t(109, 30).x, sc.t(109, 30).y, 0), car)!
        XCTAssertTrue(over.contains { $0.l == 1 && $0.x == sc.t(100, 30).x })
        let turn = s.route(from: NetNode(sc.t(93, 30).x, sc.t(93, 30).y, 0), to: NetNode(sc.t(100, 38).x, sc.t(100, 38).y, 0), car)
        XCTAssertNil(turn, "no junction where the roads cross at different levels")
    }

    func testTheChoiceOfCrossingWeighsDetourClearingBridgeAndFerry() {
        var sc = TransportScene()
        sc.cities()
        let s = sc.s
        // across the forest only (no river): clearing wins, no bridge is offered
        let f = s.crossingOptions(from: sc.t(36, 20), to: sc.t(66, 20))
        XCTAssertTrue(f.first { $0.how == "clear" }!.feasible)
        XCTAssertFalse(f.first { $0.how == "detour" }!.feasible, "there is no road round")
        XCTAssertEqual(s.chooseCrossing(f)?.how, "clear")
        // across the river: clearing alone cannot do it; a bridge or a ferry can
        let r = s.crossingOptions(from: sc.t(36, 60), to: sc.t(90, 60))
        XCTAssertFalse(r.first { $0.how == "clear" }!.feasible, "no way through water without a bridge")
        XCTAssertTrue(r.first { $0.how == "bridge" }!.feasible)
        let choice = s.chooseCrossing(r)!
        XCTAssertTrue(["bridge", "ferry"].contains(choice.how))
        // once a bridge exists the detour (driving over it) is free and is chosen
        sc.lay(.street, sc.t(36, 60), sc.t(90, 60), payer: .district(sc.a.id))
        let again = s.crossingOptions(from: sc.t(30, 60), to: sc.t(100, 60))
        XCTAssertEqual(s.chooseCrossing(again)?.how, "detour")
    }

    func testATunnelGoesUnderRockAndBuildingsAreNeverCrossed() {
        let sc = TransportScene()
        let s = sc.s
        let cliff = s.content.tid("cliff")
        for y in 0..<TransportScene.h { for x in 120..<126 { s.world.setTile(1, sc.t(x, y).x, sc.t(x, y).y, cliff) } }
        let p = sc.lay(.rail, sc.t(110, 90), sc.t(135, 90))
        XCTAssertEqual(p.tunnels.count, 1)
        XCTAssertEqual(p.tunnels[0].count, 6)
        let train = Profile(mode: .rail)
        let r = s.route(from: NetNode(sc.t(111, 90).x, sc.t(111, 90).y, 0), to: NetNode(sc.t(134, 90).x, sc.t(134, 90).y, 0), train)!
        XCTAssertEqual(r.filter { $0.l == -1 }.count, 6)
        // a house in the way: the way goes round it, never through
        s.raiseHouse(at: sc.t(100, 108), storeys: 1, w: 5, d: 5)
        let q = s.planWay(.street, from: sc.t(95, 110), to: sc.t(110, 110))
        XCTAssertTrue(q.ok)
        for t in q.cells { XCTAssertFalse(t.x >= sc.t(100, 108).x && t.x < sc.t(105, 108).x && t.y >= sc.t(100, 108).y && t.y < sc.t(100, 113).y, "\(t) is inside the house") }
    }

    func testAnOpeningBridgeStopsTrafficAndRisesOnlyWithAnEmptyDeck() {
        var sc = TransportScene()
        sc.cities()
        let s = sc.s
        sc.lay(.street, sc.t(60, 80), sc.t(95, 80), payer: .district(sc.a.id), bridge: .opening)
        let br = s.realm.transport.bridges.first { $0.kind == .opening }!
        XCTAssertEqual(br.clearance, br.deckZ - 0.5)
        // a car on the deck when the ship asks
        let car = s.buildVehicle(.car, at: br.cells[3], heading: 0, payer: .district(sc.a.id), nation: 1, level: 1)!
        car.control = .manual
        s.requestOpening(br.id)
        sc.run(10)
        XCTAssertEqual(s.realm.transport.bridges.first { $0.id == br.id }!.state, .stopping, "not rising with a car on it")
        // nothing may come on while the barriers are down
        XCTAssertFalse(s.passable(NetNode(br.cells[0].x, br.cells[0].y, 1), Profile(mode: .road)))
        // the car drives off; then it rises, opens, and a tall ship can pass
        car.input.throttle = 1
        sc.run(8) { car.level == 0 }
        car.input = Controls(); car.input.brake = 1
        sc.run(30) { s.realm.transport.bridges.first { $0.id == br.id }!.state == .open }
        XCTAssertEqual(s.realm.transport.bridges.first { $0.id == br.id }!.state, .open)
        let tall = Profile(mode: .water, draft: 4, airDraft: 5)
        XCTAssertTrue(s.passable(NetNode(br.cells[2].x, br.cells[2].y, 0), tall))
        XCTAssertFalse(s.passable(NetNode(br.cells[2].x, br.cells[2].y, 1), Profile(mode: .road)), "no road while it is up")
    }

    func testShipsAreKeptToWaterDeepEnoughAndUnderBridgesHighEnough() {
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        let under = NetNode(sc.t(77, 60).x, sc.t(77, 60).y, 0)
        XCTAssertTrue(s.passable(under, Profile(mode: .water, draft: 1.5, airDraft: 2.5)), "a ferry passes under the road bridge")
        XCTAssertFalse(s.passable(under, Profile(mode: .water, draft: 4, airDraft: 5)), "a freighter's masts do not")
        XCTAssertFalse(s.passable(NetNode(sc.t(70, 60).x, sc.t(70, 60).y, 0), Profile(mode: .water, draft: 1)), "no ship on land")
        let shallow = s.content.tid("shallow_water")
        s.world.setTile(0, sc.t(77, 100).x, sc.t(77, 100).y, shallow)
        XCTAssertFalse(s.passable(NetNode(sc.t(77, 100).x, sc.t(77, 100).y, 0), Profile(mode: .water, draft: 1.5)))
    }
}
