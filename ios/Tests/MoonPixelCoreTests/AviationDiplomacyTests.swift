import XCTest
@testable import MoonPixelCore

/// Districts build their own airports and fly real routes, at home and abroad, with the aircraft their
/// cities need; the biggest builds the nation's airbase and its fighters patrol. Nations of like strength
/// keep the peace, warm to each other, cooperate and feed each other's hungry towns.
final class AviationDiplomacyTests: XCTestCase {
    override func tearDown() { Society.urbanizeAt = 30 }

    func grow(_ s: Society, days: Int, residents: Int? = nil, life: Bool = true) {
        for _ in 0..<days {
            if let n = residents {
                for d in s.net.districts {
                    for (k, v) in ["stone": 400.0, "iron": 120, "parts": 120, "moonsteel": 30, "planks": 200, "fuel": 600] where (d.store[k] ?? 0) < v { d.add(k, v) }
                    d.money = max(d.money, 40000)
                    for bi in d.buildings.indices where d.buildings[bi].state == .open && d.buildings[bi].homes > 0 {
                        for k in d.buildings[bi].floors.indices where d.buildings[bi].floors[k].residents < n {
                            d.ledger.imported += n - d.buildings[bi].floors[k].residents; d.buildings[bi].floors[k].residents = n; d.buildings[bi].floors[k].food = 400
                        }
                    }
                }
            }
            if life { s.districtsDay() }
            s.cityGrowthDay()
            for site in s.realm.transport.sites where site.finished == nil { s.finishSite(site.id) }
        }
    }

    func testDistrictsBuildAirportsAndFlyRoutesAtHomeAndAbroad() {
        let s = makeSociety(7)
        Society.urbanizeAt = 1
        grow(s, days: 30)
        grow(s, days: 40, residents: 40)
        let ds = s.net.districts.filter { $0.fromTown != nil }
        for d in ds {
            guard let (pax, cargo) = s.airport(d) else { XCTFail("\(d.name) built an airport: pop \(d.population) open \(d.buildings.filter { $0.state == .open }.count) money \(Int(d.money)) tried \(d.tried ?? []) works \(d.works ?? [:]) \(d.events.suffix(10))"); continue }
            XCTAssertEqual(s.wayKind(at: pax.tile), .runway); XCTAssertEqual(s.wayKind(at: cargo.tile), .runway, "\(d.name) cargo \(cargo.tile) runway1 \(d.works?["runway1"].flatMap { id in s.realm.transport.sites.first { $0.id == id } }.map { s.paved($0).map { "\($0.x),\($0.y)" }.joined(separator: " ") } ?? "-") all \(d.works ?? [:])")
            // the stands are the two ends of the runway's paved middle row
            XCTAssertEqual(s.runwayAxis(at: pax.tile), 0, accuracy: 1e-9, "the passenger stand is at the western end")
        }
        let air = s.realm.transport.lines.filter { $0.kind.mode == .air }
        XCTAssertGreaterThanOrEqual(air.filter { !$0.freight }.count, 2, "passenger routes")
        XCTAssertTrue(air.contains { s.net.stop($0.stops[0])?.nation != s.net.stop($0.stops[1])?.nation }, "an international route between nations at peace")
        // they fly: every route makes trips, every aircraft takes off and lands, nothing crashes
        let trips0 = Dictionary(uniqueKeysWithValues: air.map { ($0.id, $0.trips) })
        var off: [Int: Int] = [:], down: [Int: Int] = [:]
        var seen = s.vehicleEvents.count
        for _ in 0..<12000 {
            s.tick(0.5)
            let ev = s.vehicleEvents
            for e in ev.suffix(max(0, min(ev.count, ev.count - seen + (ev.count >= 200 ? 50 : 0)))) where e.what == "took off" || e.what == "landed" { if e.what == "took off" { off[e.vehicle, default: 0] += 1 } else { down[e.vehicle, default: 0] += 1 } }
            seen = ev.count
        }
        for l in air { XCTAssertGreaterThanOrEqual(l.trips - (trips0[l.id] ?? 0), 3, "\(l.name) made trips") }
        for v in s.realm.transport.vehicles where v.flight == .crashed { print("CRASH", v.kind.rawValue, v.id, v.halted ?? "", v.tile, "line", v.task.line.flatMap { s.net.line($0)?.name } ?? "-", "phase", v.task.phase ?? "-", "evs", s.vehicleEvents.filter { $0.vehicle == v.id }.suffix(5).map { $0.what }) }
        XCTAssertTrue(air.allSatisfy { !$0.vehicles.isEmpty }, "every route has its aircraft (bought the day it opened, or the next)")
        XCTAssertEqual(s.realm.transport.stats.crashes, 0, "no aircraft crashed")
        XCTAssertFalse(s.realm.transport.vehicles.contains { $0.flight == .crashed })
    }

    func testTheAircraftFitTheRoute() {
        XCTAssertEqual(Society.aircraft(forDistance: 150, people: 120), .turboprop)
        XCTAssertEqual(Society.aircraft(forDistance: 400, people: 120), .regionalJet)
        XCTAssertEqual(Society.aircraft(forDistance: 300, people: 1200), .airliner)
        XCTAssertEqual(Society.aircraft(forDistance: 900, people: 500), .widebody)
        XCTAssertEqual(Society.aircraft(forDistance: 200, people: 4000), .widebody)
        // bigger aircraft carry more, need more runway and cost more
        let ks = VehicleKind.civilAircraft
        for i in 1..<ks.count { XCTAssertGreaterThan(ks[i].spec.seats, ks[i - 1].spec.seats); XCTAssertGreaterThanOrEqual(ks[i].spec.vr, ks[i - 1].spec.vr) }
        XCTAssertEqual(VehicleKind.fighter.mode, .air)
        XCTAssertGreaterThan(VehicleKind.fighter.spec.maxSpeed, VehicleKind.widebody.spec.maxSpeed)
    }

    func testTheBiggestDistrictBuildsAnAirbaseAndItsFightersPatrol() {
        let s = makeSociety(7)
        Society.urbanizeAt = 1
        grow(s, days: 30)
        grow(s, days: 40, residents: 60, life: false)
        let withBase = s.net.districts.filter { $0.works?["base1"] != nil }
        XCTAssertFalse(withBase.isEmpty, "a military airbase was built")
        for d in withBase {
            XCTAssertEqual(d.id, s.net.districts.filter { $0.nation == d.nation }.max { ($0.population, -$0.id) < ($1.population, -$1.id) }?.id, "by the nation's biggest district")
            XCTAssertFalse(s.net.stops.contains { $0.kind == .airport && $0.district == d.id && s.paved(s.realm.transport.sites.first { $0.id == d.works!["base1"] }!).contains($0.tile) }, "no airline uses the airbase")
        }
        let fighters = s.realm.transport.vehicles.filter { $0.kind == .fighter }
        XCTAssertGreaterThanOrEqual(fighters.count, 2, "the air force has its fighters")
        XCTAssertTrue(s.realm.transport.lines.allSatisfy { $0.kind != .fighter }, "fighters fly no airline route")
        var off: Set<Int> = [], down: Set<Int> = []
        for _ in 0..<8000 {
            s.tick(0.5)
            for e in s.vehicleEvents.suffix(20) where fighters.contains(where: { $0.id == e.vehicle }) { if e.what == "took off" { off.insert(e.vehicle) }; if e.what == "landed" { down.insert(e.vehicle) } }
        }
        XCTAssertEqual(off.count, fighters.count, "every fighter flew a sortie")
        XCTAssertEqual(down.count, fighters.count, "and came back to land")
        XCTAssertFalse(fighters.contains { $0.flight == .crashed })
    }

    func testNationsOfLikeStrengthKeepThePeaceAndCooperate() {
        let s = makeSociety(7)
        var wars = 0, coop = 0
        s.onEvent = { k, _, _ in if k == "war" { wars += 1 }; if k == "cooperation" { coop += 1 } }
        runYears(s, 6)
        XCTAssertEqual(wars, 0, "no war between nations of like strength")
        XCTAssertGreaterThan(coop, 0, "they signed cooperation agreements")
        XCTAssertTrue(s.realm.relations.contains { $0.value >= s.realm.cfg.coopTrust })
    }

    func testWarOnlyAgainstAFarWeakerNation() {
        let s = makeSociety(7)
        guard s.realm.nations.count >= 2 else { return XCTFail("two nations") }
        let a = s.realm.nations[0].id, b = s.realm.nations[1].id
        if let r = s.realm.ri(a, b) { s.realm.relations[r].since = -1e9 }
        s.realm.nations[0].soldiers = 10; s.realm.nations[0].pop = 100; s.realm.nations[0].fatigue = 0
        s.realm.nations[1].soldiers = 10; s.realm.nations[1].pop = 100
        XCTAssertFalse(s.canDeclare(a, on: b), "equals: no war")
        s.realm.nations[1].pop = 30; s.realm.nations[1].soldiers = 2
        XCTAssertTrue(s.canDeclare(a, on: b), "more than three times stronger: war is possible")
        XCTAssertFalse(s.canDeclare(b, on: a), "and never the weak on the strong")
    }

    func testCooperatingNationsFeedEachOthersHungryTowns() {
        let s = makeSociety(7)
        let live = s.settlements.values.filter { !$0.abandoned && $0.nation != nil }.sorted { $0.id < $1.id }
        guard let hungry = live.first, let giver = live.first(where: { $0.nation != hungry.nation }), let r = s.realm.ri(hungry.nation!, giver.nation!) else { return XCTFail("two nations") }
        s.realm.relations[r].value = 0.9; s.realm.relations[r].state = 0
        hungry.food = 0; giver.food = Double(giver.members.count) * 40
        let total = hungry.food + giver.food
        s.cooperate(0.1)
        XCTAssertGreaterThan(hungry.food, 0, "food arrived")
        XCTAssertEqual(hungry.food + giver.food, total, accuracy: 1e-6, "moved, not made")
        XCTAssertGreaterThanOrEqual(giver.food, Double(giver.members.count) * 10, "the giver keeps enough for itself")
    }
}
