import XCTest
@testable import MoonPixelCore

final class MigrationTests: XCTestCase {
    /// Remove every key a v1.2 save did not have, at any depth.
    func strip(_ v: Any, _ keys: Set<String>) -> Any {
        if let d = v as? [String: Any] { var o: [String: Any] = [:]; for (k, x) in d where !keys.contains(k) { o[k] = strip(x, keys) }; return o }
        if let a = v as? [Any] { return a.map { strip($0, keys) } }
        return v
    }

    func testAVersion12SaveOpensAndFillsTheNewParts() throws {
        let s = makeSociety(7)
        runYears(s, 0.5)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s.snapshot()))
        // everything added in 1.3: goods, stations, city names and capitals, the chronicle, campaigns, unit types, player pack
        let new: Set<String> = ["goods", "work", "pause", "cityName", "byPlayer", "formerCapital", "siege", "flagOf", "capital", "moving", "everCapital",
                                "chron", "nextEvent", "unit", "morale", "food", "engines", "wallHP", "phase", "hold", "foe", "leader", "routeI", "forded",
                                "convoyT", "convoyAt", "convoyLoad", "wallsAtStart", "route", "plans", "craft", "depth", "crafted"]
        var old = strip(json, new) as! [String: Any]
        // `food` and `leader` are also v1.2 field names in other places: put those back where they belong
        if var realm = old["realm"] as? [String: Any], var nations = realm["nations"] as? [[String: Any]] {
            for i in nations.indices { nations[i]["leader"] = s.realm.nations[i].leader; nations[i]["food"] = s.realm.nations[i].food }
            realm["nations"] = nations; old["realm"] = realm
            if var p = realm["player"] as? [String: Any] { p["food"] = s.realm.player.food; realm["player"] = p; old["realm"] = realm }
        }
        if var towns = old["settlements"] as? [[String: Any]] {
            let sorted = s.settlements.values.sorted { $0.id < $1.id }
            for i in towns.indices { towns[i]["food"] = sorted[i].food }
            old["settlements"] = towns
        }
        let data = try JSONSerialization.data(withJSONObject: old)
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("\"chron\""))
        let snap = try JSONDecoder().decode(Society.Snapshot.self, from: data)
        let w = OpenWorld(seed: 7, budget: MemoryBudget(overrideMB: 256))
        w.restore(s.world.snapshot())
        let t = Society(world: w, seed: 7)
        t.restore(snap)
        XCTAssertEqual(t.agents.count, s.agents.count, "people kept")
        XCTAssertEqual(t.settlements.count, s.settlements.count, "towns kept")
        XCTAssertEqual(t.realm.nations.map { $0.techCount }, s.realm.nations.map { $0.techCount }, "knowledge kept")
        XCTAssertEqual(t.audit(), [])
        // the new parts appear by themselves
        for _ in 0..<2 { t.world.time += Society.hour; t.realmHourly() }
        for n in t.realm.nations where n.exileSince == nil { XCTAssertNotNil(t.capital(of: n.id), "\(n.nameEn) gets a capital") }
        XCTAssertGreaterThan(t.lastEventID, 0, "the chronicle starts")
        XCTAssertTrue(t.settlements.values.allSatisfy { $0.flagOf == $0.nation || $0.abandoned })
        runYears(t, 0.5)
        XCTAssertEqual(t.audit(), [])
    }

    func testDamagedSaveIsRejectedNotGuessed() {
        XCTAssertThrowsError(try JSONDecoder().decode(Society.Snapshot.self, from: Data("{\"agents\": 3}".utf8)))
    }

    func testGuixuAndGenesisReachUnderground() {
        let dir = tempDir("lawunder")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = makeSociety(7, dir: dir)
        let u = s.underworld()
        let t = TilePos(4000, 4000)
        u.setTile(2, t.x, t.y, 0); u.saveAll()
        XCTAssertGreaterThan(u.storedSize(MP.chunkKey(t.x >> 5, t.y >> 5)), 0)
        var o = LawOptions(); o.radius = 0
        var plan = s.planLaw(.guixu, options: o, seed: 1)
        plan.region = [t.x >> 5, t.y >> 5, t.x >> 5, t.y >> 5]; plan.chunks = [ChunkRef(cx: t.x >> 5, cy: t.y >> 5)]; plan.towns = []; plan.buildings = []; plan.props = []
        let run = s.beginLaw(plan); while !run.step(16) {}
        XCTAssertEqual(u.storedSize(MP.chunkKey(t.x >> 5, t.y >> 5)), 0, "the dug-out underground returns to rock too")
        u.setTile(2, t.x, t.y, 0); u.saveAll()
        let g = Society.genesis(old: s, plan: s.planLaw(.genesis, seed: 2), villages: 3, per: 6, startTech: 0)
        XCTAssertEqual(u.storedChunks.count, 0, "genesis leaves no underground behind")
        let left = (try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("chunks_d1").path)) ?? []
        XCTAssertEqual(left.count, 0)
        XCTAssertEqual(g.society.audit(), [])
    }
}
