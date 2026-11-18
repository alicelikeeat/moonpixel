import XCTest
@testable import MoonPixelCore

final class CityGrowthProbe: XCTestCase {
    func testProbe() throws {
        guard ProcessInfo.processInfo.environment["MP_PROBE"] != nil else { throw XCTSkip("probe") }
        let s = makeSociety(7)
        let towns = s.settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        print("PROBE towns", towns.map { "\($0.id):\($0.members.count) n\($0.nation ?? -1)" }, "civ", s.realm.civBox != nil)
        Society.urbanizeAt = 1
        for day in 0..<80 {
            s.districtsDay()
            s.cityGrowthDay()
            for site in s.realm.transport.sites where site.finished == nil { s.finishSite(site.id) }
            s.carErrands()
            if day % 10 == 9 {
                for d in s.net.districts { print("PROBE day", day, d.name, "pop", d.population, "money", Int(d.money), "b", d.buildings.map { "\($0.kind):\($0.state)" }, "store", d.store.mapValues { Int($0) }) }
            }
        }
        for d in s.net.districts { print("PROBE first", d.name, d.events.prefix(14), "works", d.works ?? [:], "tried", d.tried ?? [], "svc", d.services.mapValues { "\(Int($0.capacity))/\(Int($0.demand))" }, "staff", d.staffing); print("PROBE events", d.name, d.events.suffix(12)) }
        if let d = s.net.districts.first(where: { $0.name.hasPrefix("Oakrest") }) {
            var why: [String: Int] = [:]
            let towns = s.settlements.values.filter { !$0.abandoned }
            for y in stride(from: d.center.y - 48, through: d.center.y + 42, by: 2) { for x in stride(from: d.center.x - 48, through: d.center.x + 42, by: 2) {
                let o = TilePos(x, y)
                if towns.contains(where: { $0.inArea(o) }) { why["town", default: 0] += 1; continue }
                if s.waterDepth(o) > 0 { why["water", default: 0] += 1; continue }
                if s.isCorridor(o) { why["corridor", default: 0] += 1; continue }
                if s.world.tile(1, x, y) != 0 { why["layer1", default: 0] += 1; continue }
                if let def = s.content.tile(s.world.tile(2, x, y)), !def.natural { why["built", default: 0] += 1; continue }
                if !s.nearRoad(TilePos(x + 3, y + 6), 30) { why["noroad", default: 0] += 1; continue }
                why["ok", default: 0] += 1
            } }
            print("PROBE oak", d.center, why, "spine cells", s.realm.transport.sites.first { $0.id == d.works?["spine"] }?.cells.prefix(3).map { "\($0.t) \(String(describing: s.wayKind(at: $0.t)))" } ?? [])
        }
        let before = Dictionary(uniqueKeysWithValues: s.realm.transport.vehicles.map { ($0.id, $0.pos) })
        let pop0 = s.net.districts.map { $0.population }
        for _ in 0..<7200 { s.tick(0.5) }
        print("PROBE moved", s.realm.transport.vehicles.map { "\($0.kind.rawValue)\($0.id): \(Int(($0.pos.distance(to: before[$0.id] ?? $0.pos)) / 16)) tiles \($0.halted ?? "")" }, "pop", pop0, "->", s.net.districts.map { $0.population })
        for v in s.realm.transport.vehicles where v.kind != .car {
            let l = v.task.line.flatMap { s.net.line($0) }
            let st = l?.stops.compactMap { s.net.stop($0) } ?? []
            let r = st.count == 2 ? s.route(from: NetNode(st[0].tile.x, st[0].tile.y, 0), to: NetNode(st[1].tile.x, st[1].tile.y, 0), s.profile(v.kind)) : nil
            print("PROBE veh", v.kind, v.id, "next", l?.nextDepart ?? [], "now", s.world.time, "susp", l?.suspended ?? "-", "tile", v.tile, "stops", st.map { "\($0.tile) \(String(describing: s.wayKind(at: $0.tile)))" }, "task", v.task.at, v.task.standing, v.task.dwell, "path", v.path.count, v.pathI, "route", r?.count ?? -1, "ctl", v.control, "speed", v.speed, "fuel", v.fuel, "halt", v.halted ?? "")
        }
        for d in s.net.districts { for (tag, id) in d.works ?? [:] where tag.hasPrefix("rail") {
            guard let site = s.realm.transport.sites.first(where: { $0.id == id }) else { continue }
            let p = s.profile(.train)
            var bad: [String] = []
            for (i, c) in site.cells.enumerated() {
                let lv = s.bridge(at: c.t) != nil ? 1 : (s.tunnel(at: c.t) != nil ? -1 : 0)
                if !s.passable(NetNode(c.t.x, c.t.y, lv), p) { bad.append("\(i):\(c.t) on \(s.content.tile(s.world.tile(2, c.t.x, c.t.y))?.key ?? "-") \(String(describing: s.wayKind(at: c.t))) lv\(lv) done\(c.done)") }
                if i > 0 {
                    let pr = site.cells[i - 1].t
                    let plv = s.bridge(at: pr) != nil ? 1 : (s.tunnel(at: pr) != nil ? -1 : 0)
                    let ns = s.neighbours(NetNode(pr.x, pr.y, plv), p)
                    if !ns.contains(where: { $0.tile == c.t }) { bad.append("link\(i): \(pr) lv\(plv) -> \(c.t) lv\(lv) has \(ns.map { "\($0.tile.x),\($0.tile.y),\($0.l)" })") }
                }
            }
            print("PROBE rail", d.name, tag, site.cells.count, "finished", site.finished != nil, "bad", bad.prefix(8))
        } }
        print("PROBE lines", s.realm.transport.lines.map { "\($0.kind) \($0.name) v\($0.vehicles)" }, "cars", s.realm.transport.vehicles.filter { $0.kind == .car }.count, "lifts", s.realm.lifts.count)
    }
}

/// Towns grow into districts by themselves, and the districts build their own streets, bus lines, cars and
/// railways; every tall building gets its lift; buildings come in more kinds, bigger, with windows and rooms.
final class CityGrowthTests: XCTestCase {
    override func tearDown() { Society.urbanizeAt = 30 }

    func grown(_ seed: Int, days: Int) -> Society {
        let s = makeSociety(seed)
        Society.urbanizeAt = 1
        for _ in 0..<days {
            s.districtsDay()
            s.cityGrowthDay()
            for site in s.realm.transport.sites where site.finished == nil { s.finishSite(site.id) }
        }
        return s
    }

    func testTownsFoundDistrictsThatBuildTheirOwnTransportAndRunIt() {
        let s = grown(7, days: 80)
        let ds = s.net.districts.filter { $0.fromTown != nil }
        XCTAssertGreaterThanOrEqual(ds.count, 2, "big towns founded districts of their own")
        for d in ds {
            XCTAssertFalse(s.settlements.values.contains { !$0.abandoned && $0.inArea(d.center) }, "\(d.name) stands outside every town")
            XCTAssertGreaterThan(d.population, 0, "\(d.name) has people")
            XCTAssertNotNil(d.works?["spine"].flatMap { id in s.realm.transport.sites.first { $0.id == id }?.finished }, "\(d.name) laid its main street")
            XCTAssertNotNil(d.works?["town"], "\(d.name) built a street to its home town")
            let lines = s.realm.transport.lines.filter { $0.payer == .district(d.id) }
            XCTAssertTrue(lines.contains { $0.kind == .bus && !$0.vehicles.isEmpty }, "\(d.name) runs a bus")
            XCTAssertTrue(lines.contains { $0.kind == .train && !$0.vehicles.isEmpty }, "\(d.name) runs a train to another district")
            XCTAssertGreaterThanOrEqual(s.realm.transport.vehicles.filter { $0.kind == .car && $0.owner == .district(d.id) }.count, 1, "\(d.name)'s residents own cars")
            for b in d.buildings where b.state == .open && b.floors.count >= 3 { XCTAssertNotNil(b.lift, "\(d.name): building \(b.id) (\(b.kind), \(b.floors.count) floors) has a lift") }
        }
        // every line can be run: a route between its stations
        for l in s.realm.transport.lines {
            let st = l.stops.compactMap { s.net.stop($0) }
            XCTAssertNotNil(s.route(from: NetNode(st[0].tile.x, st[0].tile.y, 0), to: NetNode(st[1].tile.x, st[1].tile.y, 0), s.profile(l.kind)), "\(l.name) has a way between its stops")
        }
        // every bridge is straight (its ramps in line at both ends)
        for b in s.realm.transport.bridges where b.cells.count > 1 {
            XCTAssertTrue(b.cells.allSatisfy { $0.x == b.cells[0].x } || b.cells.allSatisfy { $0.y == b.cells[0].y }, "bridge \(b.id) is straight")
        }
        // and they run: trains and buses make trips, residents drive about
        let start = Dictionary(uniqueKeysWithValues: s.realm.transport.vehicles.map { ($0.id, $0.pos) })
        var driven: [Int: Double] = [:]
        var last = start
        let trips0 = Dictionary(uniqueKeysWithValues: s.realm.transport.lines.map { ($0.id, $0.trips) })
        for k in 0..<6000 {
            s.tick(0.5)
            if k % 20 == 0 { for v in s.realm.transport.vehicles { driven[v.id, default: 0] += v.pos.distance(to: last[v.id] ?? v.pos); last[v.id] = v.pos } }
        }
        for l in s.realm.transport.lines where !l.vehicles.isEmpty { XCTAssertGreaterThan(l.trips, trips0[l.id] ?? 0, "\(l.name) made trips") }
        for v in s.realm.transport.vehicles where v.kind == .car { XCTAssertGreaterThan(driven[v.id] ?? 0, 30 * 16, "car \(v.id) was driven about") }
        XCTAssertFalse(s.realm.transport.vehicles.contains { $0.halted == "no way" }, "no vehicle is stuck with nowhere to go")
    }

    func testBiggerKindsAreChosenAsADistrictGrowsAndEachStreetVaries() {
        let s = makeSociety(3)
        let d = s.foundDistrict(name: "T", at: TilePos(400, 400), nation: 1)
        XCTAssertEqual(s.nextKind(d, ["flats", "terrace", "tower", "highrise"], 50), "terrace", "small: low homes, the kind it has fewest of (ties: the later)")
        XCTAssertEqual(s.nextKind(d, ["flats", "terrace", "tower", "highrise"], 1200), "highrise")
        XCTAssertEqual(s.nextKind(d, ["shops", "offices", "mall", "skyscraper"], 2000), "skyscraper")
        XCTAssertEqual(s.nextKind(d, ["shops", "offices", "mall", "skyscraper"], 10), "shops", "a village-sized district builds no tower")
    }

    func testASkyscraperHasGlassWallsRoomsStairsAndALift() {
        let s = makeSociety(5)
        let o = s.world.findFree(near: TilePos(-300, 260), maxR: 40)
        let d = s.foundDistrict(name: "Glass", at: o, nation: 1, money: 100_000, store: ["stone": 5000, "iron": 2000, "parts": 2000, "planks": 2000])
        let site = s.findSite(d, w: 12, h: 12) ?? TilePos(o.x + 4, o.y + 4)
        guard let id = s.placeCityBuilding(d, kind: "skyscraper", at: site), let b = d.building(id) else { return XCTFail("built") }
        XCTAssertEqual(b.floors.count, 30)
        let f5 = s.storeyWorld(5)
        let edge = (0..<b.w).map { f5.tile(2, b.x + $0, b.y) }
        XCTAssertTrue(edge.contains(s.content.tid("wall_glass")), "a glass curtain wall")
        XCTAssertEqual(f5.tile(2, b.x, b.y), s.content.tid("wall_concrete"), "concrete corners")
        XCTAssertEqual(f5.tile(2, b.x + b.w / 2, b.y + 1), s.content.tid("wall_concrete"), "the floor is split into rooms")
        XCTAssertTrue((0..<b.d).contains { y in (0..<b.w).contains { x in f5.tile(2, b.x + x, b.y + y) == s.content.tid("stairs_up") } }, "stairs up from floor 5")
        XCTAssertNotNil(b.lift, "a lift up the outside")
        XCTAssertEqual(b.lift.flatMap { s.lift($0) }?.stops.count, 30, "it stops at every floor")
    }

    func testStandingTowersAndTallHousesGetLiftsAndWindows() {
        let s = makeSociety(4)
        let o = s.world.findFree(near: TilePos(300, 300), maxR: 20)
        s.realm.standing = [StandingTower(tower: 2, city: 1, town: 1, x: o.x, y: o.y, w: 16, d: 12, levels: 40)]
        s.raiseHouse(at: o, storeys: 2, w: 16, d: 12)
        s.realm.storeyTop = 39
        XCTAssertTrue(s.realm.lifts.isEmpty)
        s.fitLifts()
        let lift = s.realm.lifts.first { $0.tower == 2 }
        XCTAssertNotNil(lift, "the tower's shaft has its car")
        XCTAssertEqual(lift?.stops.count, Society.autoLiftLevels, "up to the auto-fitted lift's top")
        s.fitLifts()
        XCTAssertEqual(s.realm.lifts.count, 1, "never a second one")
        let w = s.storeyWorld(10)
        let edge = (0..<16).map { w.tile(2, o.x + $0, o.y + 11) }
        XCTAssertTrue(edge.contains(s.content.tid("wall_glass")), "windows on the tower's storeys")
    }

    func testTownsNeverBuildOnAWayAndWaysCrossBridgesStraight() {
        let s = makeSociety(7)
        let t = s.settlements.values.filter { !$0.abandoned }.min { $0.id < $1.id }!
        var p = s.planWay(.street, from: TilePos(t.center.x - 12, t.center.y + 9), to: TilePos(t.center.x + 12, t.center.y + 9))
        if !p.ok { p = s.planWay(.street, from: TilePos(t.center.x - 12, t.center.y - 9), to: TilePos(t.center.x + 12, t.center.y - 9)) }
        XCTAssertTrue(p.ok, p.reason)
        s.realm.player.body?.pos = t.center.center
        s.pack.change("stone", 500)
        guard let id = s.startWay(p, payer: .pack) else { return XCTFail("paid") }
        s.finishSite(id)
        let c = p.cells[p.cells.count / 2]
        XCTAssertFalse(s.footprintOK(t, c.x - 1, c.y - 1, 3, 3), "no house on the street")
    }
}
