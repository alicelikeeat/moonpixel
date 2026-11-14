import XCTest
@testable import MoonPixelCore

func makeSociety(_ seed: Int, villages: Int = 4, per: Int = 30, dir: URL? = nil) -> Society {
    let w = OpenWorld(seed: seed, budget: MemoryBudget(overrideMB: 256))
    if let d = dir { w.open(directory: d) }
    let s = Society(world: w, seed: seed)
    s.bootstrap(origin: TilePos(0, 0), villages: villages, per: per)
    return s
}
func runYears(_ s: Society, _ years: Double, dt: Double = 2.0) { for _ in 0..<Int(years * MP.year / dt) { s.tick(dt) } }
func snapshotJSON(_ s: Society) -> String {
    let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
    return String(data: (try? e.encode(s.snapshot())) ?? Data(), encoding: .utf8) ?? ""
}
func tempDir(_ name: String) -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("mp-test-\(name)-\(UInt32.random(in: 0..<UInt32.max))")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

func firstDiff(_ a: String, _ b: String) -> String {
    let la = a.split(separator: "\n"), lb = b.split(separator: "\n")
    for i in 0..<min(la.count, lb.count) where la[i] != lb[i] { return "line \(i): \(la[i].prefix(200)) <> \(lb[i].prefix(200))" }
    return "lengths \(la.count) vs \(lb.count)"
}

final class RealmTests: XCTestCase {
    func testThreeNationsWithLandAndPressureFromFoodHousingJobsLand() {
        let s = makeSociety(11)
        XCTAssertEqual(s.realm.nations.count, 3)
        for n in s.realm.nations {
            XCTAssertGreaterThanOrEqual(n.towns, 1, "every nation holds land")
            XCTAssertNotEqual(n.leader, 0)
            XCTAssertEqual(s.agents[n.leader]?.nation, n.id)
        }
        XCTAssertTrue(s.agents.values.allSatisfy { $0.nation != nil })
        s.refreshNations()
        let before = s.realm.nations[0]
        // same head count, but no food and no homes: pressure must rise
        for t in s.towns(of: before.id) { t.food = 0 }
        s.refreshNations()
        XCTAssertGreaterThan(s.realm.nations[0].pressure, before.pressure + 0.2)
        XCTAssertEqual(s.realm.nations[0].pop, before.pop, "pressure is not just head count")
        XCTAssertEqual(s.realm.nations[0].pFood, 1, accuracy: 0.001)
        XCTAssertGreaterThan(s.realm.nations[0].pHousing, 0.5)
    }

    /// Development, war, truce, unification and division all happen without the player,
    /// and wars and truces never flip back and forth.
    func testThreeKingdomsCycleAndHysteresis() {
        let s = makeSociety(7)
        let cfg = s.realm.cfg
        var last = s.realm.relations.map { $0.state }
        var changes: [[(Double, Int)]] = [[], [], []]
        var sawUnity = false
        var keys = Set<String>()
        s.onEvent = { k, _, _ in keys.insert(k) }
        let dt = 2.0
        for _ in 0..<Int(34 * MP.year / dt) {
            s.tick(dt)
            for (i, r) in s.realm.relations.enumerated() where r.state != last[i] { changes[i].append((s.world.time, r.state)); last[i] = r.state }
            if s.realm.era == 1 { sawUnity = true }
        }
        let c = s.realm.counts
        print("CYCLE counts=\(c) pop=\(s.agents.count) towns=\(s.livingSettlements) tech=\(s.realm.nations.map { $0.techCount }) battle=\(s.stats.battle ?? 0)")
        XCTAssertGreaterThanOrEqual(c.wars, 2); XCTAssertGreaterThanOrEqual(c.truces, 2)
        XCTAssertGreaterThanOrEqual(c.captures, 1)
        XCTAssertGreaterThanOrEqual(c.unifications, 1, "a nation united the land at least once")
        XCTAssertTrue(sawUnity)
        // a unity that began long enough before the end must have broken apart by now
        if let u = (s.realm.chron ?? []).first(where: { $0.kind == "unified" })?.t, (s.world.time - u) / MP.year > cfg.unityMax + 0.5 {
            XCTAssertGreaterThanOrEqual(c.splits, 1, "and the united realm broke apart again")
        }
        XCTAssertGreaterThan(s.techCount, 3, "the world kept developing through it all")
        XCTAssertGreaterThan(s.agents.count, 60)
        XCTAssertTrue(keys.contains("war") && keys.contains("truce") && keys.contains("unified"))
        // hysteresis: after a truce a pair rests at least minTruce + peaceCooldown before the next war
        var wars = 0
        for list in changes {
            for (k, ch) in list.enumerated() where ch.1 == 1 {
                wars += 1
                if let prev = list[..<k].last(where: { $0.1 == 2 }) {
                    XCTAssertGreaterThanOrEqual((ch.0 - prev.0) / MP.year, cfg.minTruce + cfg.peaceCooldown - 0.1, "no war straight after a truce")
                }
            }
        }
        XCTAssertLessThan(Double(wars), 34.0 * 3 / (cfg.minTruce + cfg.peaceCooldown), "wars cannot follow each other faster than the rest periods allow")
        XCTAssertEqual(s.audit(), [], "no dangling references after wars, unification and division")
        // reload: the save comes back exactly as it was written
        let dir = tempDir("cycle")
        let json = snapshotJSON(s)
        let digest = s.digest()
        let w2 = OpenWorld(seed: 7, budget: MemoryBudget(overrideMB: 256))
        w2.open(directory: dir)
        w2.restore(s.world.snapshot())
        let s2 = Society(world: w2, seed: 7)
        s2.restore(try! JSONDecoder().decode(Society.Snapshot.self, from: json.data(using: .utf8)!))
        XCTAssertTrue(s2.digest() == digest, firstDiff(s2.digest(), digest))
        XCTAssertEqual(s2.audit(), [])
        runYears(s2, 0.3)
        XCTAssertEqual(s2.audit(), [])
    }

    func testUnificationKeepsIdentityAndEndsInThreeLandedNations() {
        let s = makeSociety(5)
        s.grantTech(3)
        runYears(s, 0.5)
        let identities = Dictionary(uniqueKeysWithValues: s.agents.values.map { ($0.id, $0.nation ?? 0) })
        let builtBefore = s.settlements.values.reduce(0) { $0 + $1.buildings.filter { $0.done }.count }
        for t in s.settlements.values where !t.abandoned { t.nation = 1 }
        for lg in s.realm.legions { lg.nation = 1 }
        s.landCheck()
        XCTAssertEqual(s.realm.era, 1); XCTAssertEqual(s.realm.unifier, 1)
        XCTAssertNotNil(s.realm.nation(2)?.exileSince)
        for (id, n) in identities { if let a = s.agents[id] { XCTAssertEqual(a.nation, n, "identity outlives the lost land") } }
        let immigrants = s.stats.immigrants
        var years = 0.0
        while s.realm.era == 1 && years < s.realm.cfg.unityMax + 1 { runYears(s, 0.25); years += 0.25 }
        XCTAssertEqual(s.realm.era, 0, "unity always ends by its time limit")
        XCTAssertGreaterThanOrEqual(years, s.realm.cfg.unityMin - 0.3)
        XCTAssertLessThanOrEqual(years, s.realm.cfg.unityMax + 0.3)
        s.refreshNations()
        for n in s.realm.nations { XCTAssertGreaterThanOrEqual(n.towns, 1, "\(n.nameEn) holds land again"); XCTAssertNil(n.exileSince) }
        XCTAssertEqual(s.stats.immigrants, immigrants, "division conjured nobody")
        XCTAssertTrue(s.realm.nations.allSatisfy { $0.techCount >= 3 }, "knowledge survives")
        XCTAssertGreaterThanOrEqual(s.settlements.values.reduce(0) { $0 + $1.buildings.filter { $0.done }.count }, builtBefore, "buildings survive")
        XCTAssertTrue(s.realm.relations.allSatisfy { $0.state == 2 }, "the new nations start with a truce")
        XCTAssertEqual(s.audit(), [])
    }

    func testEventsAreSeededConditionalAndCoolDown() {
        func trace(_ seed: Int) -> [(String, String, Double)] {
            let s = makeSociety(seed)
            var out: [(String, String, Double)] = []
            s.onEvent = { k, t, _ in out.append((k, t, s.world.time)) }
            runYears(s, 9)
            return out
        }
        let a = trace(3), b = trace(3)
        XCTAssertEqual(a.map { $0.1 }, b.map { $0.1 }, "same seed, same history")
        let cfg = RealmConfig()
        var kinds = Set<String>()
        for kind in ["harvest_good", "harvest_bad", "general", "breakthrough"] {
            let rule = cfg.events[kind]!
            var lastByText: [String: Double] = [:]
            for e in a where e.0 == kind {
                kinds.insert(kind)
                let who = kind == "general" ? String(e.1.suffix(8)) : e.1
                if let prev = lastByText[who] { XCTAssertGreaterThanOrEqual((e.2 - prev) / MP.year, rule.cooldown - 0.05, kind) }
                lastByText[who] = e.2
            }
        }
        XCTAssertGreaterThanOrEqual(kinds.count, 3, "several kinds of events happened: \(kinds)")
        // an event never hands a whole nation to another, and nobody appears from nowhere
        let s = makeSociety(3)
        let immigrants = s.stats.immigrants
        for _ in 0..<400 { s.events(0.05) }
        XCTAssertEqual(s.realm.counts.captures, 0); XCTAssertEqual(s.stats.immigrants, immigrants)
        XCTAssertTrue(s.realm.nations.allSatisfy { $0.exileSince == nil })
    }

    func testLeaderSuccession() {
        let s = makeSociety(9)
        let old = s.realm.nations[1].leader
        s.die(s.agents[old]!, "ill")
        let heir = s.realm.nations[1].leader
        XCTAssertNotEqual(heir, old); XCTAssertNotNil(s.agents[heir])
        XCTAssertTrue(s.log.contains { $0.text.contains(s.realm.nations[1].nameEn) })
    }

    /// Watching (or not watching) a battle never changes how it ends.
    func testCameraDoesNotChangeOutcome() {
        func play(_ watch: Bool) -> String {
            let s = makeSociety(21)
            runYears(s, 0.6)
            s.declare(1, on: 2)
            if s.realm.relations[0].state != 1 { s.realm.relations[0].since = -1e9; s.declare(1, on: 2) }
            for i in 0..<Int(1.2 * MP.year / 2) {
                s.tick(2)
                if watch, i % 3 == 0 {
                    let at = s.realm.legions.first { $0.state != 0 }?.pos ?? .zero
                    _ = s.crowdSplit(center: at, halfW: 400, halfH: 200, limit: 50)
                    _ = s.agent(near: at, radius: 300)
                    _ = s.nationInfos()
                }
            }
            return s.digest()
        }
        let a = play(true), b = play(false)
        XCTAssertTrue(a == b, firstDiff(a, b))
    }
}
