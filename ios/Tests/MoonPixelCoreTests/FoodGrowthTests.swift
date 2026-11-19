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
