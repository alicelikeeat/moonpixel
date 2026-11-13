import XCTest
@testable import MoonPixelCore

final class LawTests: XCTestCase {
    func finish(_ run: LawRun) -> LawResult { var guardN = 0; while !run.step(16) { guardN += 1; XCTAssertLessThan(guardN, 100000) }; return run.result }

    func testThanosDeletesHalfDeterministicallyAndHoldsNewcomers() {
        let a = makeSociety(4), b = makeSociety(4)
        runYears(a, 0.3); runYears(b, 0.3)
        let n = a.agents.count
        let plan = a.planLaw(.thanos, seed: 99)
        XCTAssertEqual(plan.agents.count, n / 2, "exactly half, rounded down")
        XCTAssertEqual(plan, a.planLaw(.thanos, seed: 99), "same state and seed: same plan")
        XCTAssertEqual(plan, b.planLaw(.thanos, seed: 99), "an identical world plans identically")
        XCTAssertNotEqual(plan.agents, a.planLaw(.thanos, seed: 100).agents)
        let people = a.storageBreakdown()["people"]!
        let run = a.beginLaw(plan)
        XCTAssertFalse(run.step(8), "large deletions run in batches")
        XCTAssertGreaterThan(run.progress, 0); XCTAssertLessThan(run.progress, 1)
        let res = finish(run)
        XCTAssertEqual(res.agents, n / 2)
        XCTAssertEqual(a.agents.count, n - n / 2)
        XCTAssertTrue(plan.agents.allSatisfy { a.agents[$0] == nil })
        XCTAssertEqual(a.audit(), [], "families, homes, armies and tasks were mended")
        XCTAssertTrue(a.agents.values.allSatisfy { $0.partner == 0 || a.agents[$0.partner] != nil })
        XCTAssertLessThan(a.storageBreakdown()["people"]!, people * 2 / 3, "the save really shrinks")
        // the population floor must not refill the world straight away
        a.minPopulation = 500
        let immigrants = a.stats.immigrants
        runYears(a, 0.8)
        XCTAssertEqual(a.stats.immigrants, immigrants, "nobody is brought in during the hold")
        runYears(a, 0.5)
        XCTAssertGreaterThan(a.stats.immigrants, immigrants, "the floor works again afterwards")
        XCTAssertEqual(a.audit(), [])
    }

    func worldWithStoredChunks(_ seed: Int) -> (Society, URL) {
        let dir = tempDir("laws")
        let s = makeSociety(seed, dir: dir)
        runYears(s, 0.4)
        // player-placed objects far from any town: stored, unpinned chunks
        for i in 0..<12 { s.world.addProp(key: i % 2 == 0 ? "asset_a" : "asset_b", at: Vec2(Double(9000 + i * 700), Double(-9000 - i * 300))) }
        s.world.saveAll()
        s.world.purge()
        return (s, dir)
    }

    func testAnnihilationByRatioAndBySpace() {
        let (s, dir) = worldWithStoredChunks(6)
        defer { try? FileManager.default.removeItem(at: dir) }
        let n = s.agents.count, b = s.settlements.values.reduce(0) { $0 + $1.buildings.count }
        var o = LawOptions(); o.ratio = 0.5
        let plan = s.planLaw(.annihilation, options: o, seed: 5)
        XCTAssertEqual(plan, s.planLaw(.annihilation, options: o, seed: 5))
        XCTAssertEqual(plan.agents.count, n / 2); XCTAssertEqual(plan.buildings.count, b / 2); XCTAssertEqual(plan.props.count, 6)
        XCTAssertGreaterThan(plan.chunks.count, 0)
        let disk = s.world.diskBytes
        let res = finish(s.beginLaw(plan))
        XCTAssertEqual(res.agents, n / 2); XCTAssertEqual(res.buildings, b / 2)
        XCTAssertEqual(s.settlements.values.reduce(0) { $0 + $1.buildings.count }, b - b / 2)
        XCTAssertLessThan(s.world.diskBytes, disk, "chunk files were really deleted")
        XCTAssertEqual(res.freed, disk - s.world.diskBytes)
        XCTAssertEqual(s.audit(), [])
        runYears(s, 0.3)                       // the world keeps running on what is left
        XCTAssertEqual(s.audit(), [])
        // weights: zero means that kind is never touched
        var only = LawOptions(); only.ratio = 1; only.wResidents = 0; only.wBuildings = 0; only.wProps = 0; only.wChunks = 0; only.wHistory = 1
        let h = s.planLaw(.annihilation, options: only, seed: 1)
        XCTAssertTrue(h.agents.isEmpty && h.buildings.isEmpty && h.chunks.isEmpty)
        XCTAssertEqual(h.logLines, s.log.count)
        _ = finish(s.beginLaw(h))
        XCTAssertEqual(s.log.count, 0)
        // space target: delete until roughly that much is planned, deterministically
        let (t, dir2) = worldWithStoredChunks(6)
        defer { try? FileManager.default.removeItem(at: dir2) }
        var sp = LawOptions(); sp.spaceTarget = 20_000
        let p1 = t.planLaw(.annihilation, options: sp, seed: 8), p2 = t.planLaw(.annihilation, options: sp, seed: 8)
        XCTAssertEqual(p1, p2)
        XCTAssertGreaterThanOrEqual(p1.estimate, 20_000)
        XCTAssertLessThan(p1.agents.count, t.agents.count, "it stops when the target is reached")
        let before = t.storageBreakdown().values.reduce(0, +) + t.world.diskBytes
        _ = finish(t.beginLaw(p1))
        XCTAssertLessThan(t.storageBreakdown().values.reduce(0, +) + t.world.diskBytes, before - 10_000)
        XCTAssertEqual(t.audit(), [])
    }

    func testGuixuRestoresNatureAndRemovesWholeBuildings() {
        let (s, dir) = worldWithStoredChunks(8)
        defer { try? FileManager.default.removeItem(at: dir) }
        runYears(s, 2.0)        // let them build
        s.world.saveAll()
        var o = LawOptions(); o.radius = 0
        // find seeds for both situations: a town inside the region, and a region that only clips a building
        var whole: LawPlan?, clip: LawPlan?
        for seed in 1...400 {
            let p = s.planLaw(.guixu, options: o, seed: seed)
            if whole == nil && !p.towns.isEmpty { whole = p }
            if clip == nil && p.towns.isEmpty && !p.buildings.isEmpty { clip = p }
            if whole != nil && clip != nil { break }
        }
        guard let wp = whole else { return XCTFail("no region with a town") }
        if let cp = clip {
            XCTAssertEqual(cp, s.planLaw(.guixu, options: o, seed: cp.seed))
            let ref = cp.buildings[0]
            let town = s.settlements[ref.sid]!, b = town.building(ref.bid)!
            let foot = (0..<b.h).flatMap { dy in (0..<b.w).map { dx in TilePos(b.x + dx, b.y + dy) } }
            let x0 = cp.region[0] * 32, y0 = cp.region[1] * 32
            let outside = foot.filter { $0.x < x0 || $0.x >= x0 + 32 || $0.y < y0 || $0.y >= y0 + 32 }
            let res = finish(s.beginLaw(cp))
            XCTAssertNil(town.building(ref.bid), "the building is gone as a whole")
            XCTAssertGreaterThanOrEqual(res.buildings, 1)
            let gen = Generator(seed: s.world.seed)
            for t in foot {
                let nat = gen.generate(t.x >> 5, t.y >> 5)
                let i = OpenWorld.idx(t.x, t.y)
                for l in 0..<3 { XCTAssertEqual(s.world.tile(l, t.x, t.y), nat.layers[l][i], "tile \(t) layer \(l) is natural again (outside part: \(outside.contains { $0 == t }))") }
            }
            XCTAssertEqual(s.audit(), [])
        }
        let town = s.settlements[wp.towns[0]]!
        let people = s.agents.count, residents = town.members.count
        let plan = s.planLaw(.guixu, options: o, seed: wp.seed)      // re-plan on the current state
        let res = finish(s.beginLaw(plan))
        if plan.towns.contains(town.id) {
            XCTAssertTrue(town.abandoned)
            XCTAssertEqual(res.displaced, residents)
            XCTAssertEqual(s.agents.count, people, "guixu removes works, not people")
            XCTAssertEqual(s.refugeeCount + s.agents.values.filter { $0.legion != nil }.count >= residents, true)
            // the square is wilderness again
            let gen = Generator(seed: s.world.seed)
            let nat = gen.generate(town.center.x >> 5, town.center.y >> 5)
            XCTAssertEqual(s.world.tile(2, town.center.x, town.center.y), nat.layers[2][OpenWorld.idx(town.center.x, town.center.y)])
        }
        XCTAssertEqual(s.world.storedSize(MP.chunkKey(plan.chunks[0].cx, plan.chunks[0].cy)), 0)
        XCTAssertEqual(s.audit(), [])
        s.refreshNations()
        runYears(s, 0.5)
        XCTAssertEqual(s.audit(), [])
    }

    func testGenesisKeepsNothingOfTheOldWorld() {
        let (s, dir) = worldWithStoredChunks(10)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertGreaterThan(s.world.storedChunks.count, 0)
        let plan = s.planLaw(.genesis, seed: 3)
        XCTAssertNotEqual(plan.newSeed, s.world.seed)
        var same = LawOptions(); same.newSeed = false
        XCTAssertEqual(s.planLaw(.genesis, options: same, seed: 3).newSeed, s.world.seed)
        let oldPeople = s.agents.count
        let g = Society.genesis(old: s, plan: plan, villages: 4, per: 20, startTech: 0)
        XCTAssertEqual(g.result.agents, oldPeople)
        XCTAssertEqual(g.world.seed, plan.newSeed)
        XCTAssertEqual(g.world.storedChunks.count, 0, "every old chunk file is gone")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("chunks").path)) ?? []
        XCTAssertEqual(files.count, 0)
        XCTAssertEqual(g.society.agents.count, 80)
        XCTAssertEqual(g.society.realm.nations.filter { $0.exileSince == nil }.count, 3)
        XCTAssertEqual(g.society.realm.counts, RealmCounts(), "history starts over")
        XCTAssertEqual(g.society.audit(), [])
    }

    func testInterruptedLawIsFinishedFromItsJournal() {
        let dir = tempDir("journal")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = makeSociety(12, dir: dir)
        runYears(s, 0.2)
        let saved = snapshotJSON(s)                       // what is on disk before the law
        let plan = s.planLaw(.thanos, seed: 77)
        XCTAssertTrue(LawJournal.write(plan, dir))
        let run = s.beginLaw(plan)
        run.step(10)                                      // ... and the app is killed here
        XCTAssertFalse(run.done)
        // next launch: old save, journal present
        let w2 = OpenWorld(seed: 12, budget: MemoryBudget(overrideMB: 256)); w2.open(directory: dir)
        w2.restore(s.world.snapshot())
        let s2 = Society(world: w2, seed: 12)
        s2.restore(try! JSONDecoder().decode(Society.Snapshot.self, from: saved.data(using: .utf8)!))
        guard let j = LawJournal.read(dir) else { return XCTFail("journal missing") }
        XCTAssertEqual(j.plan, plan)
        let r2 = finish(s2.beginLaw(j.plan))
        LawJournal.clear(dir)
        XCTAssertEqual(r2.agents, plan.agents.count)
        XCTAssertTrue(plan.agents.allSatisfy { s2.agents[$0] == nil })
        XCTAssertEqual(s2.audit(), [])
        XCTAssertNil(LawJournal.read(dir), "no copy of the deleted data is kept once the law is committed")
        // a plan that was already carried out does nothing when replayed
        let again = finish(s2.beginLaw(plan))
        XCTAssertEqual(again.agents, 0)
        // a damaged journal is ignored rather than trusted
        try? "{broken".data(using: .utf8)!.write(to: LawJournal.url(dir))
        XCTAssertNil(LawJournal.read(dir))
    }

    func testSharedAssetsSurviveUnsharedOnesAreFreed() {
        let s = makeSociety(13)
        let ids = s.agents.keys.sorted()
        s.agents[ids[0]]!.look.face = "face_shared"; s.agents[ids[1]]!.look.face = "face_shared"
        s.agents[ids[2]]!.look.portrait = "portrait_solo"; s.agents[ids[2]]!.look.anim = "anim_solo_n4"
        s.world.addProp(key: "asset_tree", at: Vec2(100, 100))
        var mine = Look(); mine.face = "face_player"
        var refs = s.referencedAssets(extra: [mine])
        XCTAssertEqual(refs, ["face_shared", "portrait_solo", "anim_solo_n4", "asset_tree", "face_player"])
        s.erase(s.agents[ids[0]]!); s.erase(s.agents[ids[2]]!)
        refs = s.referencedAssets(extra: [mine])
        XCTAssertEqual(refs, ["face_shared", "asset_tree", "face_player"], "still-used shared assets stay, orphaned ones can be deleted")
    }

    func testEveryoneGoneMeansAnExplicitRestart() {
        let s = makeSociety(14)
        var all = LawOptions(); all.ratio = 1; all.wBuildings = 0; all.wProps = 0; all.wChunks = 0; all.wHistory = 0; all.wResidents = 5
        let res = finish(s.beginLaw(s.planLaw(.annihilation, options: all, seed: 2)))
        XCTAssertEqual(s.agents.count, 0); XCTAssertTrue(res.restart)
        XCTAssertEqual(s.realm.era, 2, "the world says it is restarting")
        XCTAssertTrue(s.realm.legions.isEmpty)
        runYears(s, 0.15)
        XCTAssertEqual(s.agents.count, 0, "nobody is conjured while the restart is pending")
        runYears(s, 0.4)
        XCTAssertGreaterThan(s.agents.count, 0, "settlers begin again")
        XCTAssertEqual(s.realm.era, 0)
        XCTAssertEqual(s.realm.nations.filter { $0.exileSince == nil }.count, 3)
        XCTAssertEqual(s.audit(), [])
    }

    func testStoragePolicyOnlyDestroysWhenThePlayerChoseIt() {
        var p = StoragePolicy()
        XCTAssertNil(p.decide(used: 99, limit: 100, clock: 0), "cache-first never deletes the world")
        p.mode = .autoAnnihilation
        XCTAssertNil(p.decide(used: 50, limit: 100, clock: 0), "below the high-water mark")
        let d = p.decide(used: 90, limit: 100, clock: 10)
        XCTAssertEqual(d?.0, .annihilation); XCTAssertEqual(d?.1.spaceTarget, 20)
        XCTAssertNil(p.decide(used: 95, limit: 100, clock: 100), "cooling down")
        XCTAssertNotNil(p.decide(used: 95, limit: 100, clock: 10 + p.cooldown))
        var q = StoragePolicy(); q.mode = .regionCycle
        XCTAssertEqual(q.decide(used: 90, limit: 100, clock: 0)?.0, .guixu)
    }

    /// Laws over and over: nothing piles up.
    func testRepeatedLawsDoNotGrowResources() {
        let dir = tempDir("repeat")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = makeSociety(15, dir: dir)
        runYears(s, 0.5)
        s.world.saveAll()
        var sizes: [Int] = [], caches: [Int] = []
        for round in 0..<6 {
            _ = finish(s.beginLaw(s.planLaw(round % 2 == 0 ? .thanos : .guixu, seed: 40 + round)))
            s.realm.immigrationHold = 0
            runYears(s, 0.4)
            s.world.saveAll(); s.world.maintain()
            sizes.append(s.storageBreakdown().values.reduce(0, +) + s.world.diskBytes)
            caches.append(s.world.cache.count)
            XCTAssertEqual(s.audit(), [], "round \(round)")
            XCTAssertLessThanOrEqual(s.log.count, s.realm.cfg.maxLog)
            XCTAssertLessThan(s.realm.legions.count, 40)
            XCTAssertLessThan(s.realm.mods.count, 30)
        }
        print("REPEAT sizes=\(sizes) cache=\(caches)")
        XCTAssertLessThan(sizes.last!, sizes.first! * 3 / 2 + 200_000)
        XCTAssertLessThanOrEqual(caches.max()!, s.world.budget.maxChunks)
    }
}

final class PlayerTests: XCTestCase {
    func testRoadsBridgesAndDepotsChangeSupply() {
        let s = makeSociety(7)
        let a = s.towns(of: 1)[0], b = s.towns(of: 2)[0]
        let base = s.supply(from: a.center, to: b.center, nation: 1)
        s.realm.player.stone = 9999; s.realm.player.wood = 9999
        // pave the whole way
        let dx = Double(b.center.x - a.center.x), dy = Double(b.center.y - a.center.y)
        let dist = (dx * dx + dy * dy).squareRoot()
        var laid: [TilePos] = []
        for i in 0...Int(dist) {
            let t = TilePos(Int((Double(a.center.x) + dx * Double(i) / dist).rounded()), Int((Double(a.center.y) + dy * Double(i) / dist).rounded()))
            let kind = s.content.water[Int(s.world.tile(0, t.x, t.y))] ? "bridge" : "road"
            if s.playerBuild(kind, at: t) == nil { laid.append(t) }
        }
        XCTAssertGreaterThan(laid.count, Int(dist) / 2)
        XCTAssertLessThan(s.realm.player.stone, 9999, "building costs what the player carries")
        let paved = s.supply(from: a.center, to: b.center, nation: 1)
        XCTAssertGreaterThan(paved, base + 0.1, "roads and bridges improve supply")
        let mid = TilePos((a.center.x + b.center.x) / 2 + 3, (a.center.y + b.center.y) / 2 + 3)
        let spot = s.world.findFree(near: mid, maxR: 6)
        s.realm.player.nation = 1
        XCTAssertNil(s.playerBuild("depot", at: spot))
        let withDepot = s.supply(from: a.center, to: b.center, nation: 1)
        XCTAssertEqual(withDepot, min(s.realm.cfg.supplyMax, paved + s.realm.cfg.supplyDepot), accuracy: 0.001)
        XCTAssertEqual(s.supply(from: a.center, to: b.center, nation: 2), paved, accuracy: 0.001, "a depot serves its own nation only")
        // sabotage
        XCTAssertEqual(s.playerDemolish(at: spot), "depot")
        for t in laid { _ = s.playerDemolish(at: t) }
        XCTAssertEqual(s.supply(from: a.center, to: b.center, nation: 1), base, accuracy: 0.03, "breaking them takes the advantage away")
        XCTAssertNotNil(s.playerBuild("road", at: TilePos(a.center.x, a.center.y)), "cannot build on an occupied tile")
        // supply decides battles: the same army is weaker on a poor line
        s.realm.relations[0].since = -1e9
        for _ in 0..<40 { s.realmHourly() }               // raise garrisons
        s.declare(1, on: 2)
        guard let lg = s.realm.legions.first(where: { $0.state == 1 && $0.nation == 1 }) else { return XCTFail("no army marched") }
        lg.supply = 0.3; let weak = s.legionPower(lg, defending: false)
        lg.supply = 1.0; let strong = s.legionPower(lg, defending: false)
        XCTAssertGreaterThan(strong, weak * 2)
    }

    func testFightingGivingAndShelteringMatter() {
        let s = makeSociety(7)
        for _ in 0..<40 { s.realmHourly() }
        s.playerJoin(1)
        XCTAssertEqual(s.realm.player.nation, 1)
        // an enemy soldier
        guard let foeLegion = s.realm.legions.first(where: { $0.nation == 2 && !$0.members.isEmpty }), let foe = s.agents[foeLegion.members[0]] else { return XCTFail("no soldiers") }
        let strength = foeLegion.members.count
        foe.pos = Vec2(60000, 60000)                     // a duel away from the crowd
        let me = foe.pos + Vec2(-14, 0)
        let relBefore = s.realm.relation(1, 2)!.value
        var clock = 0.0
        let first = s.playerStrike(from: me, dir: Vec2(1, 0), weapon: "sword", clock: clock)
        XCTAssertEqual(first.hits.count, 1); XCTAssertFalse(first.hits[0].dead)
        XCTAssertEqual(foe.hp!, s.realm.cfg.soldierHP - 48, accuracy: 0.001)
        XCTAssertTrue(s.playerStrike(from: me, dir: Vec2(1, 0), weapon: "sword", clock: clock + 0.1).onCooldown, "weapons have a cooldown")
        var dead = false
        for _ in 0..<5 where !dead { clock += 0.6; dead = s.playerStrike(from: me, dir: Vec2(1, 0), weapon: "sword", clock: clock).hits.first?.dead ?? false }
        XCTAssertTrue(dead); XCTAssertNil(s.agents[foe.id])
        XCTAssertEqual(foeLegion.members.count, strength - 1, "the army is really one soldier weaker")
        XCTAssertLessThan(s.realm.relation(1, 2)!.value, relBefore, "attacking in peacetime sours relations")
        XCTAssertLessThan(s.realm.nation(2)!.rep, 0)
        XCTAssertGreaterThan(s.realm.nation(2)!.fatigue, 0)
        // no friendly fire
        let friend = s.agents.values.filter { s.side(of: $0) == 1 }.sorted { $0.id < $1.id }[0]
        friend.pos = Vec2(60000, -60000)
        clock += 1
        let ff = s.playerStrike(from: friend.pos + Vec2(-10, 0), dir: Vec2(1, 0), weapon: "sword", clock: clock)
        XCTAssertTrue(ff.hits.isEmpty); XCTAssertGreaterThanOrEqual(ff.spared, 1)
        // arrows and blasts reach further
        let far = s.agents.values.filter { s.side(of: $0) == 3 }.sorted { $0.id < $1.id }[0]
        far.pos = Vec2(-60000, 60000)
        clock += 2
        XCTAssertEqual(s.playerStrike(from: far.pos + Vec2(0, -120), dir: Vec2(0, 1), weapon: "bow", clock: clock).hits.first?.id, far.id)
        // at war, enemy soldiers hurt the player; dying sends them home
        s.realm.relations[0].state = 1
        let other = s.agents[foeLegion.members[0]]!
        other.pos = Vec2(-60000, -60000)
        var died = false
        for _ in 0..<200 where !died { died = s.playerThreat(at: other.pos, dt: 0.5).died }
        XCTAssertTrue(died)
        XCTAssertEqual(s.realm.player.deaths, 1)
        let home = s.spawnPoint(near: other.pos)
        XCTAssertEqual(s.town(near: home)?.nation, 1, "respawn in the player's own nation")
        XCTAssertEqual(s.playerThreat(at: home, dt: 0.5).attackers, 0)
        s.realm.relations[0].state = 0
        // giving
        let town = s.towns(of: 3)[0]
        s.realm.player.food = 60
        let food = town.food, rep = s.realm.nation(3)!.rep, rel = s.realm.relation(1, 3)!.value
        XCTAssertEqual(s.playerDonate(sid: town.id, kind: "food", amount: 100), 60, "only what is carried")
        XCTAssertEqual(town.food, food + 60, accuracy: 0.001)
        XCTAssertGreaterThan(s.realm.nation(3)!.rep, rep); XCTAssertGreaterThan(s.realm.relation(1, 3)!.value, rel)
        XCTAssertEqual(s.realm.player.food, 0)
        // harvesting fills the pack
        if let tree = town.trees.first {
            clock += 2
            let r = s.playerStrike(from: tree.center + Vec2(-16, 0), dir: Vec2(1, 0), weapon: "axe", clock: clock)
            if r.hits.isEmpty { XCTAssertEqual(r.gained, "wood"); XCTAssertEqual(s.realm.player.wood, 3) }
        }
        // refugees
        let src = s.towns(of: 2)[0], dst = s.towns(of: 1)[0]
        let fled = s.flee(src, share: 0.4, from: 2, captor: 1)
        XCTAssertGreaterThan(fled, 0); XCTAssertEqual(s.refugeeCount, fled)
        let before = dst.members.count
        let taken = s.playerAcceptRefugees(sid: dst.id, limit: 5)
        XCTAssertEqual(taken, min(5, fled)); XCTAssertEqual(dst.members.count, before + taken)
        XCTAssertEqual(s.refugeeCount, fled - taken)
        XCTAssertEqual(s.audit(), [])
    }
}
