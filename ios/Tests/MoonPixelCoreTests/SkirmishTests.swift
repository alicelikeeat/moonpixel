import XCTest
@testable import MoonPixelCore

final class SkirmishTests: XCTestCase {
    func make(_ seed: Int = 3, credits: Double = 3000) -> Skirmish {
        Skirmish(seed: seed, worldSeed: 7, player: ("Azure", "#4a8af0"), enemy: ("Crimson", "#e8504a"), credits: credits)
    }
    func run(_ s: Skirmish, _ seconds: Double) { for _ in 0..<Int(seconds * 20) { s.tick(1.0 / 20) } }
    let k = SkKind.named

    func testBothSidesStartWithABaseAndTheLandIsNotTheOpenWorld() {
        let s = make()
        for side in 0..<2 {
            XCTAssertEqual(s.kindCount(side, "hq"), 1); XCTAssertEqual(s.kindCount(side, "harvester"), 1); XCTAssertEqual(s.kindCount(side, "rifle"), 3)
            XCTAssertEqual(s.sides[side].credits, 3000)
        }
        XCTAssertTrue(abs(s.cx) >= 300 && abs(s.cy) >= 300, "far from where the villages are: \(s.cx), \(s.cy)")
        XCTAssertEqual(s.layers.count, 9)
        XCTAssertGreaterThan(s.ore.filter { $0 > 0 }.count, 60, "moonstone fields")
        // the two bases can reach each other
        let a = s.entities.values.first { $0.side == 0 && $0.def.key == "hq" }!, b = s.entities.values.first { $0.side == 1 && $0.def.key == "hq" }!
        let f = s.field(to: b.tile)
        let t = s.exit(of: a).tile
        XCTAssertLessThan(f[Skirmish.idx(t.x, t.y)], UInt16.max, "there is a way across")
        let again = make()
        XCTAssertEqual(again.summary, s.summary); XCTAssertEqual(again.blocked, s.blocked); XCTAssertEqual(again.cx, s.cx)
    }

    func testTheHarvesterBringsMoonstoneHome() {
        let s = make()
        s.setComputer(1, false)
        let ore0 = s.ore.reduce(0, +)
        run(s, 90)
        XCTAssertGreaterThan(s.sides[0].credits, 3000 + 400, "it mined and delivered without being told to")
        XCTAssertEqual(s.sides[0].credits - 3000, s.sides[0].mined, accuracy: 0.001)
        let carried = s.entities.values.filter { $0.def.key == "harvester" }.reduce(0) { $0 + $1.cargo }
        XCTAssertEqual(ore0 - s.ore.reduce(0, +), s.sides[0].mined + s.sides[1].mined + carried, accuracy: 0.01, "every bit taken from the ground is carried or banked")
    }

    func testBuildingNeedsMoneyOrderAndRoom() {
        let s = make()
        s.setComputer(1, false)
        XCTAssertFalse(s.available(0, k("refinery")), "a refinery needs a reactor first")
        XCTAssertFalse(s.queue(0, k("works")))
        XCTAssertTrue(s.queue(0, k("reactor")))
        XCTAssertEqual(s.sides[0].credits, 2700, "paid when ordered")
        XCTAssertFalse(s.queue(0, k("reactor")), "one structure at a time")
        XCTAssertTrue(s.cancel(0, line: 0)); XCTAssertEqual(s.sides[0].credits, 3000, "and paid back when cancelled")
        XCTAssertTrue(s.queue(0, k("reactor")))
        run(s, 9)
        XCTAssertEqual(s.sides[0].ready, k("reactor"))
        let hq = s.entities.values.first { $0.side == 0 && $0.def.key == "hq" }!
        XCTAssertFalse(s.placeReady(0, at: hq.tile), "not on top of the headquarters")
        XCTAssertFalse(s.placeReady(0, at: TilePos(hq.tile.x + 30, hq.tile.y - 30)), "not far from everything we own")
        XCTAssertTrue(s.placeReady(0, at: TilePos(hq.tile.x + 4, hq.tile.y - 3)))
        XCTAssertEqual(s.sides[0].powerMade, 100)
        XCTAssertTrue(s.available(0, k("refinery")) && s.available(0, k("barracks")))
        // a barracks trains riflemen; they come out next to it
        XCTAssertTrue(s.queue(0, k("barracks"))); run(s, 10)
        XCTAssertTrue(s.placeReady(0, at: TilePos(hq.tile.x - 4, hq.tile.y - 3)))
        XCTAssertTrue(s.queue(0, k("rifle")) && s.queue(0, k("rifle")) && s.queue(0, k("lancer")))
        XCTAssertEqual(s.sides[0].queued[1].count, 2)
        run(s, 16)
        XCTAssertEqual(s.kindCount(0, "rifle"), 5); XCTAssertEqual(s.kindCount(0, "lancer"), 1)
        // too little power: everything is made slowly
        XCTAssertTrue(s.queue(0, k("turret"))); run(s, 10); XCTAssertTrue(s.placeReady(0, at: TilePos(hq.tile.x + 4, hq.tile.y + 4)))
        XCTAssertTrue(s.queue(0, k("refinery"))); run(s, 15); XCTAssertTrue(s.placeReady(0, at: TilePos(hq.tile.x - 5, hq.tile.y + 5)))
        XCTAssertEqual(s.kindCount(0, "harvester"), 2, "a refinery comes with its harvester")
        XCTAssertFalse(s.sides[0].lowPower)
        XCTAssertTrue(s.queue(0, k("barracks"))); run(s, 10); XCTAssertTrue(s.placeReady(0, at: TilePos(hq.tile.x + 7, hq.tile.y - 3)))
        XCTAssertTrue(s.queue(0, k("turret"))); run(s, 10)
        _ = s.placeReady(0, at: TilePos(hq.tile.x + 6, hq.tile.y + 4))
        XCTAssertTrue(s.sides[0].lowPower, "120 used, 100 made")
        XCTAssertTrue(s.queue(0, k("rifle"))); run(s, 5)
        XCTAssertNotNil(s.sides[0].making[1], "at low power four seconds of work are not done in five")
    }

    func testOrdersMoveAndFight() {
        let s = make()
        s.setComputer(1, false)
        let mine = s.entities.values.filter { $0.side == 0 && $0.def.key == "rifle" }.map { $0.id }.sorted()
        let from = s.entities[mine[0]]!.pos
        let to = from + Vec2(120, -150)
        s.order(mine, move: to)
        run(s, 12)
        for id in mine { XCTAssertLessThan(s.entities[id]!.pos.distance(to: to), 30, "arrived, spread around the place") }
        XCTAssertEqual(Set(mine.map { "\(Int(s.entities[$0]!.pos.x / 6)),\(Int(s.entities[$0]!.pos.y / 6))" }).count, 3, "not on top of each other")
        XCTAssertEqual(s.units(of: 0, in: to - Vec2(40, 40), to + Vec2(40, 40)), mine, "a box picks them up")
        // attack: walk across the map to the enemy's riflemen and fight
        let foe = s.entities.values.filter { $0.side == 1 && $0.def.key == "rifle" }.map { $0.id }.sorted()
        s.order(mine, attack: foe[0])
        run(s, 120)
        XCTAssertGreaterThan(s.sides[0].killed + s.sides[1].killed, 0, "somebody fell")
        XCTAssertTrue(s.takeEvents().contains { $0.kind == "shot" })
        XCTAssertTrue(s.takeEvents().isEmpty, "events are handed over once")
    }

    func testAWholeBattleBetweenTwoComputersIsTheSameEveryTime() {
        var lines: [String] = []
        for _ in 0..<2 {
            let s = make(11)
            s.setComputer(0, true)
            var log: [String] = []
            for i in 0..<(1500 * 20) {
                s.tick(1.0 / 20)
                if i % (300 * 20) == 0 { log.append(s.summary) }
                if s.winner != nil { break }
            }
            log.append(s.summary)
            lines.append(log.joined(separator: "\n"))
            if lines.count == 1 {
                print("SKIRMISH\n" + log.joined(separator: "\n"))
                for side in 0..<2 {
                    XCTAssertGreaterThan(s.sides[side].mined, 3000, "both mined")
                    XCTAssertGreaterThan(s.sides[side].killed, 3, "both fought")
                }
                XCTAssertTrue(s.owns(0, "works") || s.owns(1, "works") || s.winner != nil, "bases grew to vehicles")
            }
        }
        XCTAssertEqual(lines[0], lines[1], "same seed, same battle")
    }

    func testLosingEveryStructureLosesTheBattle() {
        let s = make()
        s.setComputer(1, false)
        for e in s.entities.values where e.side == 1 && e.def.structure { s.hurt(e.id, 1e9, by: 0) }
        run(s, 0.2)
        XCTAssertEqual(s.winner, 0)
        let t = s.time
        run(s, 5)
        XCTAssertEqual(s.time, t, "the battle is over: nothing moves on")
        XCTAssertFalse(s.queue(0, k("reactor")))
    }

    func testEveryKindHasAPicture() {
        for d in SkKind.all where d.structure || d.armor == .vehicle {
            let b = PixelArt.skirmish(d, color: RGBA(hex: "#4a8af0"))
            XCTAssertGreaterThan(b.px.enumerated().filter { $0.offset % 4 == 3 && $0.element > 0 }.count, 60, d.key)
            if d.structure { XCTAssertEqual(b.w, d.w * 16) }
        }
        XCTAssertEqual(Set(SkKind.all.map { $0.key }).count, SkKind.all.count)
        for d in SkKind.all { for n in d.needs { XCTAssertNotNil(SkKind.index[n], "\(d.key) needs something that exists") } }
    }
}
