import XCTest
@testable import MoonPixelCore

final class MetroTests: XCTestCase {
    func run(_ m: Metro, days: Int) { for _ in 0..<days { m.step() } }
    let s = MetroService.index

    func testLandIsFarFromTheVillagesAndTheSameForASeed() {
        let a = Metro(seed: 1, worldSeed: 7), b = Metro(seed: 1, worldSeed: 7)
        XCTAssertTrue(abs(a.cx) >= 320 && abs(a.cy) >= 320)
        XCTAssertEqual(a.blocked, b.blocked); XCTAssertEqual(a.cx, b.cx)
        XCTAssertGreaterThan(a.blocked.filter { !$0 }.count, Metro.size * Metro.size / 2, "most of it can be built on")
        XCTAssertEqual(a.population, 0); XCTAssertEqual(a.money, 70000)
        XCTAssertEqual(a.demand.r, 100, "an empty town wants homes")
    }

    func testRoadsCostMoneyAndAvoidWater() {
        let m = Metro(seed: 1, worldSeed: 7)
        let land = (0..<(Metro.size * Metro.size)).first { i in !m.blocked[i] && i % Metro.size < 40 && (0..<20).allSatisfy { k in !m.blocked[i + k] } }!
        let a = TilePos(land % Metro.size, land / Metro.size), b = TilePos(a.x + 19, a.y)
        let plan = m.roadPlan(a, b, .street)
        XCTAssertTrue(plan.ok); XCTAssertEqual(plan.tiles.count, 20); XCTAssertEqual(plan.cost, 20 * MetroRoad.street.cost)
        XCTAssertTrue(m.buildRoad(a, b, .street))
        XCTAssertEqual(m.money, 70000 - 1400, accuracy: 0.001)
        XCTAssertEqual(m.roadPlan(a, b, .street).cost, 0, "already there")
        XCTAssertFalse(m.roadPlan(a, b, .avenue).ok, "avenues come later")
        XCTAssertEqual(Metro.path(TilePos(2, 2), TilePos(5, 4)).count, 6, "along x, then along y")
        if let w = m.blocked.firstIndex(of: true) {
            XCTAssertFalse(m.roadPlan(TilePos(w % Metro.size, w / Metro.size), TilePos(w % Metro.size, w / Metro.size), .street).ok, "not over water")
        }
    }

    func testATownGrowsWithRoadsPowerWaterAndDemand() {
        let m = Metro(seed: 1, worldSeed: 7)
        m.layOutDemo()
        let start = m.money
        XCTAssertGreaterThan(m.services.count, 4)
        XCTAssertGreaterThan(m.zone.filter { $0 == 1 }.count, 50)
        run(m, days: 240)
        print("METRO after 240 days: \(m.summary) happy \(m.happiness.enumerated().filter { m.level[$0.offset] > 0 }.map { $0.element }.reduce(0, +) / Float(max(1, m.level.filter { $0 > 0 }.count)))")
        XCTAssertGreaterThan(m.population, 300, "people moved in")
        XCTAssertGreaterThan(m.jobs.c, 20); XCTAssertGreaterThan(m.jobs.i, 40)
        XCTAssertGreaterThan(m.income, 0)
        XCTAssertTrue(m.level.contains(2), "some buildings levelled up")
        XCTAssertGreaterThan(m.peak, 249); XCTAssertTrue(m.unlocked(s["police"]!), "the police station unlocks at 250 people")
        XCTAssertTrue(m.load.contains { $0 > 0 }, "people drive to work")
        XCTAssertNotEqual(m.money, start)
        // the same city the same way every time
        let again = Metro(seed: 1, worldSeed: 7); again.layOutDemo(); run(again, days: 240)
        XCTAssertEqual(again.summary, m.summary)
    }

    func testNothingGrowsWithoutPowerAndWater() {
        let m = Metro(seed: 1, worldSeed: 7)
        m.layOutDemo()
        let ws = m.services.filter { ["power", "water"].contains($0.def.effect) }
        for b in ws { m.bulldoze(TilePos(b.x, b.y), TilePos(b.x, b.y)) }
        run(m, days: 60)
        XCTAssertEqual(m.population, 0, "no power, no water: nobody moves in")
        XCTAssertFalse(m.powered.contains(true))
    }

    func testCutOffNeighbourhoodsLoseServiceAndEmpty() {
        let m = Metro(seed: 1, worldSeed: 7)
        m.layOutDemo()
        run(m, days: 150)
        let homes = m.level.indices.filter { m.zone[$0] == 1 && m.level[$0] > 0 }
        XCTAssertFalse(homes.isEmpty)
        XCTAssertGreaterThan(Double(homes.filter { m.powered[$0] }.count), Double(homes.count) * 0.85, "nearly every home has power (the town is outgrowing its plants)")
        // take away the plants: power is gone at once and homes are left within a month or so
        for b in m.services where b.def.effect == "power" { m.bulldoze(TilePos(b.x, b.y), TilePos(b.x, b.y)) }
        XCTAssertFalse(m.powered.contains(true))
        let before = m.population
        run(m, days: 40)
        XCTAssertLessThan(m.population, before / 2, "unhappy people leave: \(before) -> \(m.population)")
        XCTAssertTrue(m.abandoned.contains { $0 > 0 } || m.level.filter { $0 > 0 }.count < homes.count)
    }

    func testTrafficJamsAndAvenuesHelp() {
        let m = Metro(seed: 1, worldSeed: 7)
        m.layOutDemo()
        run(m, days: 200)
        let worst = m.road.indices.filter { m.road[$0] != 0 }.max { m.load[$0] < m.load[$1] }!
        XCTAssertGreaterThan(m.load[worst], 0)
        let jam = m.load[worst] / Float(MetroRoad.street.capacity)
        // avenues: unlocked at 900 people; give the town that, then widen the busiest road
        let x = worst % Metro.size, y = worst / Metro.size
        let r = m.roadPlan(TilePos(x, y), TilePos(x, y), .avenue)
        if m.avenueUnlocked {
            XCTAssertTrue(r.ok)
            m.buildRoad(TilePos(x, y), TilePos(x, y), .avenue)
            XCTAssertLessThan(m.load[worst] / Float(MetroRoad.avenue.capacity), jam, "the same cars on a wider road")
        } else {
            XCTAssertFalse(r.ok, "not before 900 people")
        }
    }

    func testIndustryPollutesAndLowersLandValue() {
        let m = Metro(seed: 1, worldSeed: 7)
        m.layOutDemo()
        run(m, days: 200)
        let ind = m.level.indices.filter { m.zone[$0] == 3 && m.level[$0] > 0 }
        let res = m.level.indices.filter { m.zone[$0] == 1 && m.level[$0] > 0 }
        XCTAssertFalse(ind.isEmpty); XCTAssertFalse(res.isEmpty)
        let pi = ind.map { m.pollution[$0] }.reduce(0, +) / Float(ind.count), pr = res.map { m.pollution[$0] }.reduce(0, +) / Float(res.count)
        XCTAssertGreaterThan(pi, pr + 10, "industry is dirtier than the homes across town")
        let vi = ind.map { m.landValue[$0] }.reduce(0, +) / Float(ind.count), vr = res.map { m.landValue[$0] }.reduce(0, +) / Float(res.count)
        XCTAssertLessThan(vi, vr, "and land there is worth less")
        // a park raises the value around it
        let before = m.landValue
        let open = (0..<(Metro.size * Metro.size)).first { i in
            let x = i % Metro.size, y = i / Metro.size
            return x < Metro.size - 2 && y < Metro.size - 2 && m.canPlace(self.s["park"]!, at: TilePos(x, y)) && m.access[i] >= 0
        }!
        XCTAssertTrue(m.placeService(s["park"]!, at: TilePos(open % Metro.size, open / Metro.size)))
        XCTAssertGreaterThan(m.landValue[open], before[open])
    }

    func testTaxesFillTheTillButCoolDemand() {
        let a = Metro(seed: 1, worldSeed: 7), b = Metro(seed: 1, worldSeed: 7)
        a.layOutDemo(); b.layOutDemo()
        run(a, days: 150); run(b, days: 150)
        b.setTax(0, 0.2); b.setTax(1, 0.2); b.setTax(2, 0.2)
        a.step(); b.step()
        XCTAssertGreaterThan(b.income, a.income, "higher taxes, more income today")
        XCTAssertLessThan(b.demand.r, a.demand.r, "but fewer want to move in")
        b.setTax(0, 0.9); XCTAssertEqual(b.taxes[0], 0.25, "taxes stay between 1 and 25 per cent")
        XCTAssertEqual(a.expense, a.road.filter { $0 == 1 }.count == 0 ? a.expense : a.expense, "expenses are paid daily")
    }

    func testServicesNeedPopulationMoneyAndRoom() {
        let m = Metro(seed: 1, worldSeed: 7)
        let open = (0..<(Metro.size * Metro.size)).first { i in let x = i % Metro.size, y = i / Metro.size; return x < Metro.size - 3 && y < Metro.size - 3 && m.canPlace(self.s["wind"]!, at: TilePos(x, y)) }!
        let t = TilePos(open % Metro.size, open / Metro.size)
        XCTAssertFalse(m.canPlace(s["police"]!, at: t), "police come at 250 people")
        XCTAssertFalse(m.canPlace(s["tower"]!, at: t))
        XCTAssertTrue(m.placeService(s["wind"]!, at: t))
        XCTAssertFalse(m.canPlace(s["wind"]!, at: t), "the place is taken")
        XCTAssertEqual(m.money, 70000 - 3200, accuracy: 0.01)
        XCTAssertTrue(m.describe(t.x, t.y, zh: false).contains { $0.contains("not on a road") })
        XCTAssertEqual(m.bulldoze(t, t), 1)
        XCTAssertTrue(m.services.isEmpty)
    }

    func testSavingAndLoadingGivesTheSameCity() throws {
        let m = Metro(seed: 4, worldSeed: 7, name: "Harbor")
        m.layOutDemo()
        run(m, days: 120)
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(Metro.self, from: data)
        XCTAssertEqual(back.summary, m.summary); XCTAssertEqual(back.name, "Harbor")
        XCTAssertEqual(back.road, m.road); XCTAssertEqual(back.services, m.services); XCTAssertEqual(back.layers, m.layers, "trees cleared under buildings stay cleared")
        run(m, days: 30); run(back, days: 30)
        XCTAssertEqual(back.summary, m.summary, "and it goes on the same way")
        print("METRO save: \(data.count / 1024) KB")
        XCTAssertLessThan(data.count, 400_000)
        XCTAssertThrowsError(try JSONDecoder().decode(Metro.self, from: Data("{\"v\":2}".utf8)))
    }

    func testOverlaysAndPictures() {
        let m = Metro(seed: 1, worldSeed: 7)
        m.layOutDemo(); run(m, days: 60)
        for k in ["traffic", "pollution", "value", "happiness", "power", "water", "police"] {
            let o = m.overlay(k)
            XCTAssertEqual(o.count, Metro.size * Metro.size, k)
            XCTAssertTrue(o.allSatisfy { $0 <= 1.0001 }, k)
        }
        for z in 1...3 { for lv in 1...3 { for ab in [false, true] {
            let b = PixelArt.metro(zone: z, level: lv, variant: z * 5 + lv, abandoned: ab)
            XCTAssertEqual(b.w, 16); XCTAssertGreaterThanOrEqual(b.h, 16)
            XCTAssertGreaterThan(b.px.enumerated().filter { $0.offset % 4 == 3 && $0.element > 0 }.count, 100)
        } } }
        for s in MetroService.all { let b = PixelArt.metroService(s); XCTAssertEqual(b.w, s.w * 16) }
        for mask in 0..<16 { XCTAssertEqual(PixelArt.metroRoad(mask: mask, avenue: mask % 2 == 0).w, 16) }
        XCTAssertFalse(m.describe(Metro.size / 2, Metro.size / 2, zh: true).isEmpty)
    }
}
