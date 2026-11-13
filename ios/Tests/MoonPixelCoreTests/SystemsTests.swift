import XCTest
@testable import MoonPixelCore

final class SystemsTests: XCTestCase {
    func testArsenalTreeIsRandomPerWorldButReproducibleAndComplete() {
        let a = ArsenalTree.generate(seed: 1), b = ArsenalTree.generate(seed: 1), c = ArsenalTree.generate(seed: 2)
        XCTAssertEqual(a, b); XCTAssertNotEqual(a, c, "another world, another tree")
        XCTAssertGreaterThanOrEqual(Power.all.count, 40)
        XCTAssertEqual(Set(Power.all.map { $0.school }), [0, 1, 2, 3, 4], "arms, energy, arcane, divine, words")
        for p in Power.all {
            let needs = a.needs[p.key] ?? ["?"]
            XCTAssertEqual(needs.isEmpty, p.tier == 1)
            for n in needs { XCTAssertEqual(Power.byKey[n]?.tier, p.tier - 1, "\(p.key) builds on the tier below") }
        }
        // everything can be learned eventually
        var known = Set<String>()
        var grew = true
        while grew { grew = false; for p in Power.all where !known.contains(p.key) && (a.needs[p.key] ?? []).allSatisfy({ known.contains($0) }) { known.insert(p.key); grew = true } }
        XCTAssertEqual(known.count, Power.all.count)
    }

    func testNationsResearchWeaponsAndArmiesGetStronger() {
        let s = makeSociety(7)
        XCTAssertEqual(s.arsenalBonus(1), 1)
        runYears(s, 6)
        let learned = s.realm.nations.map { $0.powers ?? [] }
        print("ARSENAL after 6y: \(learned.map { $0.count }) e.g. \(learned[0].prefix(6))")
        XCTAssertTrue(learned.allSatisfy { $0.count >= 3 }, "every nation learned something")
        XCTAssertNotEqual(Set(learned[0]), Set(learned[1]), "nations take different paths through the tree")
        let tree = s.arsenalTree()
        for n in s.realm.nations { for k in n.powers ?? [] { XCTAssertTrue((tree.needs[k] ?? []).allSatisfy { (n.powers ?? []).contains($0) }, "prerequisites respected") } }
        XCTAssertGreaterThan(s.arsenalBonus(1), 1)
        XCTAssertNotNil(s.signaturePower(1))
        XCTAssertFalse(s.playerPowers().isEmpty, "a traveller can use what the nations know")
    }

    func testCastingEveryKindOfPower() {
        let s = makeSociety(7)
        for _ in 0..<40 { s.realmHourly() }
        s.realm.player.artifacts = Power.all.map { $0.key }
        s.realm.player.nation = 1
        var clock = 100.0
        func foes(_ n: Int, at p: Vec2) -> [Agent] {
            let list = s.agents.values.filter { s.side(of: $0) == 2 && $0.legion == nil && $0.stage(s.world.time) == "adult" }.sorted { $0.id < $1.id }.prefix(n)
            for (i, a) in list.enumerated() { a.pos = p + Vec2(Double(i) * 12, 0); a.hp = nil }
            return Array(list)
        }
        let me = Vec2(70000, 70000)
        // a pistol shot hits the first body on the line and nobody else
        var f = foes(2, at: me + Vec2(60, 0))
        var r = s.playerCast("pistol", from: me, target: me + Vec2(100, 0), clock: clock)
        XCTAssertTrue(r.ok); XCTAssertEqual(r.hits.count, 1); XCTAssertEqual(r.hits[0].id, f[0].id)
        XCTAssertEqual(s.playerCast("pistol", from: me, target: me + Vec2(100, 0), clock: clock).reason, "cooldown")
        // a sniper round kills outright, a burst spends several rounds
        clock += 5
        r = s.playerCast("sniper", from: me, target: me + Vec2(100, 0), clock: clock)
        XCTAssertTrue(r.hits.first?.dead ?? false)
        f = foes(3, at: me + Vec2(60, 0))
        r = s.playerCast("mg", from: me, target: me + Vec2(100, 0), clock: clock)
        XCTAssertEqual(r.hits.count, 6)
        // blasts and sky strikes take everyone in the circle; a beam goes through the whole line
        f = foes(3, at: me + Vec2(0, 200))
        r = s.playerCast("fireball", from: me, target: f[1].pos, clock: clock)
        XCTAssertEqual(r.hits.count, 3)
        f = foes(3, at: me + Vec2(80, 0))
        r = s.playerCast("railgun", from: me, target: me + Vec2(300, 0), clock: clock)
        XCTAssertEqual(r.hits.count, 3); XCTAssertTrue(r.hits.allSatisfy { $0.dead })
        // lightning jumps from one to the next
        f = foes(3, at: me + Vec2(0, -150))
        r = s.playerCast("thunder", from: me, target: f[0].pos, clock: clock)
        XCTAssertEqual(r.hits.count, 3); XCTAssertEqual(r.path.count, 4)
        // words: Halt freezes, Perish kills, Grow ripens, Peace wins hearts
        f = foes(2, at: me + Vec2(0, 100))
        r = s.playerCast("halt", from: me, target: f[0].pos, clock: clock)
        XCTAssertEqual(r.stunned, 2)
        let before = f[0].pos
        for _ in 0..<5 { s.update(f[0], 0.5) }
        XCTAssertEqual(f[0].pos.x, before.x, "a halted villager does not move")
        r = s.playerCast("perish", from: me, target: f[0].pos, clock: clock)
        XCTAssertTrue(r.hits.first?.dead ?? false)
        s.realm.player.focus = 100
        let field = TilePos(4500, 4500)
        s.world.setTile(2, field.x, field.y, s.T["wheat_0"]!)
        _ = s.playerCast("grow", from: field.center, target: field.center, clock: clock)
        XCTAssertEqual(s.world.tile(2, field.x, field.y), s.T["wheat_2"])
        s.realm.player.focus = 100
        let rep = s.realm.nation(2)!.rep
        _ = foes(1, at: me + Vec2(30, 30))
        _ = s.playerCast("peace", from: me, target: me, clock: clock)
        XCTAssertGreaterThan(s.realm.nation(2)!.rep, rep)
        // healing, wards, blinking, focus
        s.realm.player.focus = 100
        s.realm.player.hp = 20
        r = s.playerCast("heal", from: me, target: me, clock: clock)
        XCTAssertEqual(s.realm.player.hp, 70, accuracy: 0.01)
        s.realm.player.focus = 100
        r = s.playerCast("blink", from: Vec2(100, 100), target: Vec2(300, 100), clock: clock)
        XCTAssertNotNil(r.blinkTo)
        XCTAssertLessThan(s.realm.player.focus ?? 100, 100, "magic costs focus")
        s.realm.player.focus = 0
        XCTAssertEqual(s.playerCast("meteor", from: me, target: me, clock: clock + 99).reason, "focus")
        s.playerRest(10)
        XCTAssertEqual(s.realm.player.focus ?? 0, 60, accuracy: 0.01)
        XCTAssertTrue(s.playerCast("pistol", from: me, target: me, clock: clock + 99).ok, "guns need no focus")
        // no friendly fire, and nothing the player has not learned
        let friend = s.agents.values.filter { s.side(of: $0) == 1 }.sorted { $0.id < $1.id }[0]
        friend.pos = me + Vec2(-60, 0)
        r = s.playerCast("blaster", from: me, target: friend.pos, clock: clock + 200)
        XCTAssertTrue(r.hits.isEmpty); XCTAssertGreaterThan(r.spared, 0)
        s.realm.player.artifacts = []
        s.realm.nations[0].powers = []
        XCTAssertEqual(s.playerCast("orbital", from: me, target: me, clock: clock + 300).reason, "unknown")
        XCTAssertEqual(s.audit(), [])
    }

    func testWeatherIsSeededChangesAndMatters() {
        func kinds(_ seed: Int) -> [Int] {
            let s = makeSociety(seed, villages: 3, per: 6)
            var out: [Int] = []
            for _ in 0..<600 { s.weatherHourly(); s.world.time += Society.hour; out.append(s.realm.weather.kind) }
            return out
        }
        let a = kinds(3)
        XCTAssertEqual(a, kinds(3))
        XCTAssertGreaterThanOrEqual(Set(a).count, 5, "all kinds of weather come round: \(Set(a))")
        XCTAssertGreaterThan(a.filter { $0 == 0 }.count, a.filter { $0 == 3 }.count, "fair weather is the rule, storms the exception")
        let s = makeSociety(5)
        runYears(s, 1.5)
        guard let town = s.settlements.values.first(where: { $0.count("farm", done: true) > 0 }) else { return XCTFail("no farm yet") }
        s.setWeather(2, hours: 100)
        let food = town.food
        s.weatherHourly()
        XCTAssertGreaterThan(town.food, food, "rain helps the farms")
        XCTAssertEqual(s.weather(at: town.center.center).fall >= 1, true)
        XCTAssertLessThan(s.marchWeather(), 1)
        s.setWeather(3, hours: 100)
        for _ in 0..<40 { s.weatherHourly() }
        XCTAssertTrue(s.takeFX().contains { $0.kind == "lightning" }, "storms throw lightning")
        XCTAssertTrue(s.takeFX().isEmpty, "effects do not pile up")
        XCTAssertTrue(s.weather(at: .zero).thunder)
    }

    func testAnimalsLiveAroundTheViewerCanBeHuntedAndTamed() {
        let s = makeSociety(7)
        let me = s.settlements[1]!.center.center + Vec2(0, 400)
        for _ in 0..<400 { _ = s.faunaTick(0.5, viewer: me, mazeHere: false) }
        let n = s.realm.fauna.animals.count
        XCTAssertGreaterThan(n, 4); XCTAssertLessThanOrEqual(n, s.realm.fauna.maxNear + 4)
        XCTAssertTrue(s.realm.fauna.animals.allSatisfy { $0.pos.distance(to: me) < 1600 })
        // walk far away: the old herd is forgotten, a new one gathers
        let far = me + Vec2(9000, 0)
        for _ in 0..<40 { _ = s.faunaTick(0.5, viewer: far, mazeHere: false) }
        XCTAssertTrue(s.realm.fauna.animals.allSatisfy { $0.pos.distance(to: far) < 1600 })
        // hunting
        s.realm.fauna.animals = []
        s.spawnAnimal("deer", at: Vec2(500, 500))
        s.realm.player.artifacts = ["sniper"]
        let food = s.realm.player.food
        let r = s.playerCast("sniper", from: Vec2(400, 500), target: Vec2(500, 500), clock: 1)
        XCTAssertEqual(r.beasts.count, 1); XCTAssertTrue(r.beasts.first?.dead ?? false)
        XCTAssertEqual(s.realm.player.food, food + 6)
        XCTAssertTrue(s.realm.fauna.animals.isEmpty)
        // taming
        s.spawnAnimal("sheep", at: Vec2(500, 500)); s.spawnAnimal("wolf", at: Vec2(5000, 5000))
        s.realm.player.food = 0
        XCTAssertEqual(s.playerTame(near: Vec2(510, 500)), "food")
        s.realm.player.food = 10
        XCTAssertNil(s.playerTame(near: Vec2(510, 500)))
        XCTAssertEqual(s.playerTame(near: Vec2(5010, 5000)), "wild")
        // put the pet on open ground by a town square and walk away from it
        let square = s.settlements[1]!.center.center
        if let i = s.realm.fauna.animals.firstIndex(where: { $0.tame }) { s.realm.fauna.animals[i].pos = square + Vec2(0, 20) }
        let goal = square + Vec2(0, 110)
        for _ in 0..<60 { _ = s.faunaTick(0.5, viewer: goal, mazeHere: false) }
        XCTAssertLessThan(s.realm.fauna.animals.first { $0.tame }?.pos.distance(to: goal) ?? 999, 60, "a tamed animal follows")
        // predators bite; a ward stops it
        s.realm.fauna.animals = []
        s.spawnAnimal("wolf", at: Vec2(100, 100))
        let bite = s.faunaTick(0.5, viewer: Vec2(108, 100), mazeHere: false)
        XCTAssertGreaterThan(bite, 0)
        var t = Society.Threat(); t.damage = bite
        let hp = s.realm.player.hp
        _ = s.harmPlayer(t)
        XCTAssertLessThan(s.realm.player.hp, hp)
        s.playerWarded = true
        XCTAssertEqual(s.harmPlayer(t).damage, 0)
    }

    func testRomanceLeisureAndCheats() {
        let s = makeSociety(7)
        let a = s.agents.values.filter { $0.partner == 0 && $0.age(s.world.time) >= 20 && $0.age(s.world.time) < 40 }.sorted { $0.id < $1.id }[0]
        XCTAssertEqual(s.playerPropose(a.id), "notyet")
        XCTAssertEqual(s.playerDate(a.id), "stranger")
        XCTAssertEqual(s.playerGift(a.id, "flower"), "flower")
        // pick flowers, give them, walk together, propose
        let t = TilePos(3000, 3000)
        s.world.setTile(3, t.x, t.y, s.content.tid("flower_red"))
        XCTAssertTrue(s.playerPick(at: t)); XCTAssertFalse(s.playerPick(at: t))
        s.realm.player.flowers = 6; s.realm.player.food = 10
        for _ in 0..<3 { XCTAssertNil(s.playerGift(a.id, "flower")) }
        XCTAssertNil(s.playerGift(a.id, "food"))
        XCTAssertNil(s.playerDate(a.id)); XCTAssertEqual(s.playerDate(a.id), "soon")
        s.viewer = a.pos + Vec2(200, 0)
        let d0 = a.pos.distance(to: s.viewer!)
        for _ in 0..<20 { s.update(a, 0.5) }
        XCTAssertLessThan(a.pos.distance(to: s.viewer!), d0, "on a date they walk with the player")
        for _ in 0..<2 { _ = s.playerGift(a.id, "flower") }
        XCTAssertGreaterThanOrEqual(s.affection(a.id), 0.85)
        XCTAssertNil(s.playerPropose(a.id))
        XCTAssertEqual(s.realm.player.partner, a.id)
        XCTAssertEqual(s.playerPropose(a.id), "married")
        s.erase(a); s.spouseHourly()
        XCTAssertNil(s.realm.player.partner, "a spouse who no longer exists is not kept as a reference")
        // villagers court before they marry, and still do marry
        let pairs = s.stats.pairs
        var keys = Set<String>()
        s.onEvent = { k, _, _ in keys.insert(k) }
        runYears(s, 4)
        XCTAssertTrue(keys.contains("courting")); XCTAssertGreaterThan(s.stats.pairs, pairs)
        XCTAssertTrue(keys.contains("festival"), "full stores mean a festival")
        print("LEISURE taverns=\(s.settlements.values.reduce(0) { $0 + $1.count("tavern", done: true) }) events=\(keys.sorted())")
        // dice: food only changes hands
        let b = s.agents.values.filter { $0.stage(s.world.time) == "adult" }.sorted { $0.id < $1.id }[0]
        let town = s.settlements[b.sid]!
        town.food = 100; s.realm.player.food = 20
        let r = s.playerDice(b.id, stake: 5)
        XCTAssertEqual(s.realm.player.food + town.food, 120, accuracy: 0.001)
        XCTAssertEqual(r.won, r.you > r.them ? 5 : (r.you < r.them ? -5 : 0))
        s.realm.player.food = 0
        XCTAssertEqual(s.playerDice(b.id).reason, "food")
        // cheats work and are recorded
        XCTAssertNil(s.realm.player.cheated)
        XCTAssertTrue(s.cheat("rich")); XCTAssertEqual(s.realm.player.cheated, true)
        XCTAssertEqual(s.realm.player.wood, 200)
        XCTAssertTrue(s.cheat("powers")); XCTAssertEqual(s.playerPowers().count, Power.all.count)
        XCTAssertTrue(s.cheat("god"))
        var th = Society.Threat(); th.damage = 50
        XCTAssertEqual(s.harmPlayer(th).damage, 0)
        XCTAssertTrue(s.cheat("weather:3")); XCTAssertEqual(s.realm.weather.kind, 3)
        let n = s.agents.count
        XCTAssertTrue(s.cheat("people", at: town.center.center)); XCTAssertEqual(s.agents.count, n + 10)
        XCTAssertTrue(s.cheat("animals", at: town.center.center)); XCTAssertEqual(s.realm.fauna.animals.filter { $0.tame }.count, 6)
        XCTAssertFalse(s.cheat("nonsense"))
        XCTAssertEqual(s.audit(), [])
        // everything new survives a save
        let json = snapshotJSON(s)
        let s2 = Society(world: OpenWorld(seed: 7, budget: MemoryBudget(overrideMB: 256)), seed: 7)
        s2.restore(try! JSONDecoder().decode(Society.Snapshot.self, from: json.data(using: .utf8)!))
        XCTAssertEqual(s2.realm.weather.kind, 3); XCTAssertEqual(s2.realm.fauna.animals.count, s.realm.fauna.animals.count)
        XCTAssertEqual(s2.realm.player.artifacts?.count, Power.all.count); XCTAssertEqual(s2.realm.arsenal, s.realm.arsenal)
    }

    func testMazesAreDeterministicSolvableAndHoldTreasure() {
        let w = OpenWorld(seed: 9, budget: MemoryBudget(overrideMB: 256))
        let s = Society(world: w, seed: 9)
        s.bootstrap(origin: TilePos(0, 0), villages: 3, per: 6)
        guard let m = s.nearestMaze(cx: 0, cy: 0) else { return XCTFail("no maze within reach") }
        XCTAssertEqual(m.0, s.nearestMaze(cx: 0, cy: 0)!.0)
        XCTAssertTrue(Generator(seed: 9).isMaze(m.0, m.1), "same seed, same mazes")
        for t in s.settlements.values { XCTAssertFalse(w.gen.isMaze(t.center.x >> 5, t.center.y >> 5), "no town is founded on a maze") }
        let ox = m.0 * 32, oy = m.1 * 32
        let chest = TilePos(ox + 15, oy + 15)
        XCTAssertEqual(w.tile(2, chest.x, chest.y), s.T["chest"])
        XCTAssertTrue(w.blocked(ox, oy), "walls")
        // breadth-first from the south gate to the tile beside the chest
        var seen = Set<TilePos>([TilePos(ox + 15, oy + 30)])
        var queue = [TilePos(ox + 15, oy + 30)]
        var found = false
        while !queue.isEmpty && !found {
            let c = queue.removeFirst()
            for d in [TilePos(1, 0), TilePos(-1, 0), TilePos(0, 1), TilePos(0, -1)] {
                let n = c + d
                if n.x < ox || n.y < oy || n.x > ox + 30 || n.y > oy + 30 || seen.contains(n) { continue }
                if n == chest { found = true; break }
                if w.blocked(n.x, n.y) { continue }
                seen.insert(n); queue.append(n)
            }
        }
        XCTAssertTrue(found, "the treasure can be reached from the gate")
        XCTAssertGreaterThan(seen.count, 60, "and it takes some walking")
        let first = s.playerOpenChest(at: chest)
        XCTAssertTrue(first.ok); XCTAssertNotNil(first.power)
        XCTAssertGreaterThanOrEqual(first.power!.tier, 3)
        XCTAssertTrue(s.playerPowers().contains { $0.key == first.power!.key }, "the artifact is usable")
        XCTAssertEqual(s.realm.player.wood, 30)
        XCTAssertFalse(s.playerOpenChest(at: chest).ok, "a chest gives once")
        XCTAssertFalse(s.playerOpenChest(at: s.settlements[1]!.center + TilePos(-2, -2)).ok, "a town's chest is not treasure")
        // guardians
        for _ in 0..<20 { _ = s.faunaTick(0.5, viewer: TilePos(ox + 15, oy + 28).center, mazeHere: true) }
        XCTAssertTrue(s.realm.fauna.animals.contains { $0.species.key == "golem" })
    }
}
