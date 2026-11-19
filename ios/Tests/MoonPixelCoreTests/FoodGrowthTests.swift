import XCTest
@testable import MoonPixelCore

final class FoodGrowthProbe: XCTestCase {
    /// MP_PROBE=1: a world's towns found districts; days pass (24 planning hours each, works finished at once);
    /// the people, food and buildings are printed every few days.
    func testGrowthCurve() throws {
        guard ProcessInfo.processInfo.environment["MP_PROBE"] != nil else { throw XCTSkip("probe") }
        let s = makeSociety(7)
        let days = Int(ProcessInfo.processInfo.environment["MP_DAYS"] ?? "60") ?? 60
        for day in 0..<days {
            for _ in 0..<24 {
                s.cityGrowthHour()
                for site in s.realm.transport.sites where site.finished == nil { s.finishSite(site.id) }
                for _ in 0..<10 { s.liftsStep(5) }       // the lifts carry food up, as every game tick does
            }
            s.districtsDay()
            s.cityGrowthDay()
            if day % 5 == 4 || day == days - 1 {
                let ds = s.net.districts
                print("GROW day \(day + 1) total \(s.totalPopulation) districts", ds.map { d in
                    "\(d.name): pop \(d.population)/\(d.homes) food \(Int(d.store["food"] ?? 0)) made \(Int(d.foodMade ?? 0)) cap \(Int(s.foodCapacity(d))) plenty \(String(format: "%.2f", s.plenty(d))) short \(Int(d.foodShort)) hungry \(d.buildings.flatMap { b in b.floors.enumerated().filter { $0.element.hungry > 0 }.map { "\(b.kind)#\(b.id)f\($0.offset):\($0.element.residents)/\(Int($0.element.food))" } }.prefix(6)) money \(Int(d.money)) r \(d.radius) farms \(d.buildings.filter { $0.def.use == .agricultural && $0.state == .open }.map { $0.kind }) busy \(d.buildings.filter { $0.state != .open && $0.state != .burnt }.map { "\($0.kind):\($0.state)" })"
                })
            }
        }
        for d in s.net.districts { print("GROW events", d.name, d.events.suffix(15)); print("GROW ledger", d.name, "short", d.foodShort, "eaten", d.foodEaten, "happy", d.happiness, d.ledger, "floors", d.buildings.filter { $0.residents > 0 }.map { b in b.floors.map { "\($0.residents)/\(Int($0.food))h\($0.hungry)" } }, "lift", d.buildings.map { $0.lift ?? -1 }); print("GROW svc", d.name, d.services.mapValues { "\(Int($0.capacity))/\(Int($0.demand))" }, "staff", d.staffing, "store", d.store.mapValues { Int($0) }, "b", d.buildings.map { "\($0.id) \($0.kind) \($0.state) j\($0.jobs)" }) }
    }
}

final class FoodGrowthTests: XCTestCase {
    func district(_ s: Society, store: [String: Double] = [:]) -> District {
        let o = s.world.findFree(near: TilePos(-300, 260), maxR: 40)
        var st: [String: Double] = ["stone": 50_000, "iron": 20_000, "parts": 20_000, "planks": 20_000, "food": 500]
        for (k, v) in store { st[k] = v }
        return s.foundDistrict(name: "Fields", at: o, nation: 1, money: 1_000_000, store: st)
    }

    func testGrowthIsFullSpeedUntilTenThousandThenSlowsSteeply() {
        XCTAssertEqual(Society.growthBrake(500), 1)
        XCTAssertEqual(Society.growthBrake(9_999), 1)
        XCTAssertEqual(Society.growthBrake(12_600), 0.5, accuracy: 0.01)
        XCTAssertLessThan(Society.growthBrake(21_600), 0.1)
    }

    func testADistrictBuildsLargeFarmsAndRanchesAheadOfItsPeople() {
        let s = makeSociety(5)
        let d = district(s)
        XCTAssertEqual(s.foodToBuild(d), "farm", "a new district starts with a small farm")
        // a district of 400 with one small farm needs far more food: large farms and ranches in turn
        nycPut(s, d, "farm"); nycPut(s, d, "farm")
        d.buildings.append({ var b = CityBuilding(); b.id = 999; b.kind = "highrise"; b.state = .open; b.floors = (0..<20).map { _ in var f = CityFloor(); f.residents = 20; return f }; return b }())
        XCTAssertEqual(s.foodToBuild(d), "bigfarm")
        nycPut(s, d, "bigfarm")
        XCTAssertEqual(s.foodToBuild(d), "ranch", "then a ranch")
        XCTAssertGreaterThan(s.foodCapacity(d), 300)
    }

    func testARanchIsFencedPastureWithAHerdAndALargeFarmIsFieldsOfCrops() {
        let s = makeSociety(5)
        let d = district(s)
        guard let rid = nycPut(s, d, "ranch"), let r = d.building(rid) else { return XCTFail("ranch") }
        XCTAssertEqual(s.world.tile(2, r.x, r.y), s.content.tid("fence"))
        XCTAssertEqual(s.world.tile(0, r.x + 10, r.y + 8), s.content.tid("grass"), "pasture")
        let herd = s.realm.fauna.animals.filter { a in let t = a.pos.tile; return t.x > r.x && t.y > r.y && t.x < r.x + r.w && t.y < r.y + r.d }
        XCTAssertGreaterThanOrEqual(herd.count, 6, "cows and sheep inside the fence")
        XCTAssertTrue(herd.allSatisfy { $0.tame && ["cow", "sheep"].contains($0.species.key) })
        guard let fid = nycPut(s, d, "bigfarm"), let f = d.building(fid) else { return XCTFail("big farm") }
        var crops = Set<String>()
        for y in f.y..<(f.y + f.d) { for x in f.x..<(f.x + f.w) { if let k = s.content.tile(s.world.tile(2, x, y))?.key, k.hasSuffix("_2") { crops.insert(k) } } }
        XCTAssertEqual(crops, ["wheat_2", "carrot_2"], "strips of grain and vegetables")
        XCTAssertEqual(s.audit(), [])
    }

    func testFarmsAreStaffedBeforeShopsAndTheFirstOfEachServiceFirst() {
        let s = makeSociety(5)
        let d = district(s)
        for k in ["power", "power", "waterworks", "shops", "farm"] { nycPut(s, d, k) }
        d.buildings.append({ var b = CityBuilding(); b.id = 999; b.kind = "flats"; b.state = .open; b.floors = (0..<4).map { _ in var f = CityFloor(); f.residents = 12; f.food = 36; return f }; return b }())
        s.districtDay(d)          // 48 people: about 29 workers (the district grew from no town)
        let staff = { (k: String) in d.buildings.filter { $0.kind == k }.map { d.staffing[$0.id] ?? 0 } }
        XCTAssertEqual(staff("waterworks").first ?? 0, 1, accuracy: 0.01, "the waterworks before a second power station")
        XCTAssertGreaterThan(staff("farm").first ?? 0, 0.3, "the farm before the shops")
        XCTAssertEqual(staff("shops").first ?? 0, 0, accuracy: 0.01)
    }

    func testUpperFloorsAreFedWithoutALiftAndMissingMaterialsAreBought() {
        let s = makeSociety(5)
        let d = district(s, store: ["iron": 0, "parts": 0])
        guard let id = nycPut(s, d, "farm") else { return XCTFail("farm") }
        _ = id
        var b = CityBuilding(); b.id = 998; b.kind = "tower"; b.state = .open
        b.floors = (0..<12).map { _ in var f = CityFloor(); f.residents = 10; return f }
        d.buildings.append(b)
        s.distributeFood(d)
        let f = d.building(998)!.floors
        XCTAssertTrue(f.allSatisfy { $0.food >= Double($0.residents) - 1e-9 }, "a day's food up the stairs on every floor, the 12th too")
        // a project short of iron and parts buys them in with its money
        let money = d.money
        s.buyShortfall(d, ["iron": 40, "parts": 20], keep: 0)
        XCTAssertEqual(d.store["iron"] ?? 0, 40, accuracy: 1e-6); XCTAssertEqual(d.store["parts"] ?? 0, 20, accuracy: 1e-6)
        XCTAssertEqual(money - d.money, 40 * 8 + 20 * 12, accuracy: 1e-6)
    }
}
