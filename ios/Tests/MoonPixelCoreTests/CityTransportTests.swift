import XCTest
@testable import MoonPixelCore

/// Every city has its buses, its airport, its railway and its high-speed line (once it has a neighbour).
final class CityTransportTests: XCTestCase {
    override func tearDown() { Society.urbanizeAt = 30 }

    func grow(_ s: Society, days: Int, residents: Int? = nil) {
        for _ in 0..<days {
            if let n = residents {
                for d in s.net.districts {
                    for (k, v) in ["stone": 400.0, "iron": 120, "parts": 120, "moonsteel": 30, "planks": 200, "fuel": 600] where (d.store[k] ?? 0) < v { d.add(k, v) }
                    d.money = max(d.money, 60000)
                    for bi in d.buildings.indices where d.buildings[bi].state == .open && d.buildings[bi].homes > 0 {
                        for k in d.buildings[bi].floors.indices where d.buildings[bi].floors[k].residents < n {
                            d.ledger.imported += n - d.buildings[bi].floors[k].residents; d.buildings[bi].floors[k].residents = n; d.buildings[bi].floors[k].food = 400
                        }
                    }
                }
            }
            s.districtsDay()
            s.cityGrowthDay()
            for site in s.realm.transport.sites where site.finished == nil { s.finishSite(site.id) }
        }
    }

    func testEveryCityGetsBusesAnAirportRailAndHighSpeedRail() {
        let s = makeSociety(7)
        Society.urbanizeAt = 1
        grow(s, days: 30)
        grow(s, days: 50, residents: 40)
        let ds = s.net.districts.filter { $0.fromTown != nil }
        XCTAssertGreaterThanOrEqual(ds.count, 2)
        let lines = s.realm.transport.lines
        for d in ds {
            let mine = lines.filter { l in l.stops.contains { id in s.net.stop(id)?.district == d.id } }
            XCTAssertTrue(mine.contains { $0.kind == .bus }, "\(d.name): buses")
            XCTAssertNotNil(s.airport(d), "\(d.name): an airport")
            XCTAssertTrue(mine.contains { $0.kind == .train }, "\(d.name): a railway \(d.tried ?? [])")
            XCTAssertTrue(mine.contains { $0.kind == .hsr }, "\(d.name): a high-speed line \(d.tried ?? []) \(d.events.suffix(6))")
        }
        XCTAssertTrue(s.realm.transport.vehicles.contains { $0.kind == .hsr }, "a high-speed train runs")
    }
}
