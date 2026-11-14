import XCTest
@testable import MoonPixelCore

final class BuildTests: XCTestCase {
    /// A patch of dry, empty ground far from any town.
    /// A patch of dry, empty ground far from any town (made, not searched for).
    var nextClearing = 0
    func clearing(_ s: Society, size: Int = 12) -> TilePos {
        nextClearing += 1
        let t = TilePos(4000 + nextClearing * 200, 4000)
        let grass = s.content.tid("grass")
        for dy in -2..<(size + 2) { for dx in -2..<(size + 2) {
            s.world.setTile(0, t.x + dx, t.y + dy, grass)
            for l in 1...3 { s.world.setTile(l, t.x + dx, t.y + dy, 0) }
        } }
        return t
    }

    func testPreviewCommitOnceDemolishAndRules() {
        let s = makeSociety(7)
        let o = clearing(s)
        s.carry("wood", 20)
        let line = (0..<6).map { TilePos(o.x + $0, o.y) }
        let plan = BuildPlan(id: 1, piece: "wall_wood", cells: line + [line[0]])
        let pre = s.previewBuild(plan)
        XCTAssertEqual(pre.cells.count, 6, "a dragged line counts each tile once")
        XCTAssertEqual(pre.cost["wood"], 12); XCTAssertTrue(pre.affordable)
        XCTAssertEqual(s.carried("wood"), 20, "a preview costs nothing")
        let r = s.commitBuild(plan)
        XCTAssertEqual(r.placed, 6); XCTAssertEqual(s.carried("wood"), 8)
        XCTAssertTrue(s.world.blocked(o.x + 2, o.y), "walls block the way")
        XCTAssertEqual(s.commitBuild(plan).reason, "duplicate"); XCTAssertEqual(s.carried("wood"), 8, "the same plan is never paid twice")
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 2, piece: "wall_wood", cells: line)).reason, "nothing", "occupied tiles are refused")
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 3, piece: "wall_stone", cells: [TilePos(o.x, o.y + 2)])).reason, "cost")
        // only valid tiles are charged
        let mixed = s.previewBuild(BuildPlan(id: 4, piece: "wall_wood", cells: [TilePos(o.x, o.y), TilePos(o.x, o.y + 3)]))
        XCTAssertEqual(mixed.valid, 1); XCTAssertEqual(mixed.cost["wood"], 2)
        XCTAssertEqual(mixed.cells.first { !$0.ok }?.reason, "occupied")
        // demolition returns half
        XCTAssertEqual(s.demolishBuild(at: TilePos(o.x + 2, o.y))?.key, "wall_wood")
        XCTAssertEqual(s.carried("wood"), 9); XCTAssertFalse(s.world.blocked(o.x + 2, o.y))
        XCTAssertNil(s.demolishBuild(at: TilePos(o.x + 2, o.y)))
        // bridges go on water, roads on land
        s.carry("wood", 30); s.carry("stone", 30)
        XCTAssertEqual(s.previewBuild(BuildPlan(id: 5, piece: "bridge", cells: [TilePos(o.x, o.y + 5)])).cells[0].reason, "land")
        s.world.setTile(0, o.x + 8, o.y + 5, s.content.tid("water"))
        XCTAssertTrue(s.world.blocked(o.x + 8, o.y + 5))
        XCTAssertEqual(s.previewBuild(BuildPlan(id: 6, piece: "road", cells: [TilePos(o.x + 8, o.y + 5)])).cells[0].reason, "water")
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 7, piece: "bridge", cells: [TilePos(o.x + 8, o.y + 5)])).placed, 1)
        XCTAssertFalse(s.world.blocked(o.x + 8, o.y + 5), "a bridge makes water passable")
        // nothing is built inside another nation's city; anyone standing where a wall goes is moved aside
        s.realm.player.nation = 1
        let foreign = s.towns(of: 2)[0]
        XCTAssertEqual(s.previewBuild(BuildPlan(id: 8, piece: "floor_wood", cells: [foreign.center + TilePos(6, 6)])).cells[0].reason, "foreign")
        let home = s.towns(of: 1)[0]
        let spot = s.world.findFree(near: home.center + TilePos(5, 5), maxR: 4)
        let a = s.agents[home.members[0]]!
        a.pos = spot.center
        let res = s.commitBuild(BuildPlan(id: 9, piece: "wall_wood", cells: [spot]), player: spot.center)
        XCTAssertEqual(res.placed, 1)
        XCTAssertNotEqual(a.pos.tile, spot); XCTAssertNotNil(res.moved)
        XCTAssertTrue(home.nav!.solid[(spot.y - home.origin.y) * Settlement.span + (spot.x - home.origin.x)], "the villagers' path grid sees the wall")
        XCTAssertEqual(s.audit(), [])
    }

    func testBedsOnFloorsHouseVillagers() {
        let s = makeSociety(7)
        let t = s.towns(of: 1)[0]
        s.realm.player.nation = 1
        s.plan(t)
        let before = t.members.filter { s.agents[$0]?.home == -1 }.count
        XCTAssertGreaterThan(before, 5, "a new town has homeless people")
        s.carry("wood", 200)
        var cells: [TilePos] = []
        var k = 0
        for dy in 8...16 { for dx in -8...8 where cells.count < 6 {
            let c = t.center + TilePos(dx, dy)
            if s.placeProblem("bed", layer: 2, onWater: false, at: c, in: s.world, nation: 1).isEmpty && !s.buildingTiles(t).contains(c) { cells.append(c); k += 1 }
        } }
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 20, piece: "floor_wood", cells: cells)).placed, 6)
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 21, piece: "bed", cells: cells)).placed, 6)
        s.surveyTown(t); s.plan(t)
        XCTAssertEqual(t.freeBeds.count, 6)
        XCTAssertEqual(t.members.filter { s.agents[$0]?.home == -2 }.count, 6, "villagers move into beds the player built")
        XCTAssertEqual(t.members.filter { s.agents[$0]?.home == -1 }.count, before - 6)
        // take the beds away again: they are homeless, not lost
        for c in cells { s.demolishBuild(at: c) }
        s.surveyTown(t); s.plan(t)
        XCTAssertEqual(t.members.filter { s.agents[$0]?.home == -2 }.count, 0)
        XCTAssertEqual(s.audit(), [])
    }

    func testSwitchNetworksAreConnectedAndBounded() {
        let s = makeSociety(7)
        let o = clearing(s, size: 14)
        s.carry("iron", 400); s.carry("wood", 50); s.carry("stone", 50)
        func put(_ id: Int, _ piece: String, _ cells: [TilePos]) { XCTAssertEqual(s.commitBuild(BuildPlan(id: id, piece: piece, cells: cells)).placed, cells.count, piece) }
        // lever - wire - wire - lamp, and an iron door on a branch
        put(30, "lever", [o])
        put(31, "wire", [TilePos(o.x + 1, o.y), TilePos(o.x + 2, o.y), TilePos(o.x + 2, o.y + 1)])
        put(32, "lamp", [TilePos(o.x + 3, o.y)])
        put(33, "door_iron", [TilePos(o.x + 2, o.y + 2)])
        put(34, "lamp", [TilePos(o.x + 8, o.y)])                       // not connected
        func key(_ t: TilePos) -> String { s.content.tile(s.world.tile(2, t.x, t.y))?.key ?? "" }
        XCTAssertEqual(key(TilePos(o.x + 3, o.y)), "lamp_off")
        XCTAssertEqual(s.interact(at: o), "lever_on")
        XCTAssertEqual(key(TilePos(o.x + 3, o.y)), "lamp_on"); XCTAssertEqual(key(TilePos(o.x + 2, o.y + 2)), "door_iron_open")
        XCTAssertFalse(s.world.blocked(o.x + 2, o.y + 2), "the powered door lets people through")
        XCTAssertEqual(key(TilePos(o.x + 8, o.y)), "lamp_off", "an unconnected lamp stays dark")
        XCTAssertEqual(s.interact(at: o), "lever_off")
        XCTAssertEqual(key(TilePos(o.x + 3, o.y)), "lamp_off"); XCTAssertTrue(s.world.blocked(o.x + 2, o.y + 2))
        // cutting the wire cuts the power
        s.interact(at: o)
        s.demolishBuild(at: TilePos(o.x + 1, o.y))
        XCTAssertEqual(key(TilePos(o.x + 3, o.y)), "lamp_off")
        // pressure plate and trap
        put(35, "plate", [TilePos(o.x, o.y + 5)]); put(36, "wire", [TilePos(o.x + 1, o.y + 5)]); put(37, "trap", [TilePos(o.x + 2, o.y + 5)])
        s.press(TilePos(o.x, o.y + 5), down: true)
        XCTAssertEqual(key(TilePos(o.x + 2, o.y + 5)), "trap_sprung"); XCTAssertEqual(s.takeSprung(), [TilePos(o.x + 2, o.y + 5)])
        s.press(TilePos(o.x, o.y + 5), down: false)
        XCTAssertEqual(key(TilePos(o.x + 2, o.y + 5)), "trap")
        // a closed loop of wire with two levers settles at once, and a huge net is cut off at the limit
        let q = clearing(s, size: 30)
        var ring: [TilePos] = []
        for i in 0..<6 { ring += [TilePos(q.x + i, q.y), TilePos(q.x + i, q.y + 5)] }
        for j in 1..<5 { ring += [TilePos(q.x, q.y + j), TilePos(q.x + 5, q.y + j)] }
        put(40, "wire", ring)
        put(41, "lever", [TilePos(q.x + 2, q.y - 1)]); put(42, "lamp", [TilePos(q.x + 3, q.y + 6)])
        s.interact(at: TilePos(q.x + 2, q.y - 1))
        XCTAssertEqual(key(TilePos(q.x + 3, q.y + 6)), "lamp_on", "power goes round a loop without running away")
        var big: [TilePos] = []
        for y in 8..<28 { for x in 0..<28 { big.append(TilePos(q.x + x, q.y + y)) } }
        put(43, "wire", big)
        let net = s.updateNetwork(around: TilePos(q.x, q.y + 8))
        XCTAssertLessThanOrEqual(net.tiles, s.realm.cfg.maxNetwork + 4, "one update never walks more than the limit")
        // gates open and close by hand
        put(44, "gate", [TilePos(o.x + 10, o.y + 10)])
        XCTAssertTrue(s.world.blocked(o.x + 10, o.y + 10))
        XCTAssertEqual(s.interact(at: TilePos(o.x + 10, o.y + 10)), "gate_open"); XCTAssertFalse(s.world.blocked(o.x + 10, o.y + 10))
    }

    func testUndergroundThereAndBackAgain() {
        let dir = tempDir("under")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = makeSociety(7, dir: dir)
        let o = clearing(s)
        s.carry("wood", 50); s.carry("stone", 50)
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 50, piece: "stairs", cells: [o])).placed, 1)
        let u = s.underworld()
        XCTAssertEqual(u.depth, 1)
        XCTAssertEqual(u.tile(2, o.x, o.y), s.content.tid("stairs_up"), "the stair has its partner directly below")
        guard let down = s.useStairs(at: o.center) else { return XCTFail("could not go down") }
        XCTAssertEqual(down.depth, 1); XCTAssertEqual(s.realm.player.depth, 1)
        XCTAssertFalse(u.blocked(down.pos.tile.x, down.pos.tile.y))
        // the underground has rock, ore, lakes and ruins, and is the same every time
        var kinds = Set<String>()
        for cy in -3...3 { for cx in -3...3 { let c = u.chunk((o.x >> 5) + cx, (o.y >> 5) + cy); for i in 0..<MP.chunkArea { kinds.insert(s.content.tile(c.layers[2][i])?.key ?? "open"); kinds.insert(s.content.tile(c.layers[0][i])?.key ?? "") } } }
        XCTAssertTrue(kinds.isSuperset(of: ["cave_wall", "open", "ore_iron", "ore_moon", "cave_water", "ruin_wall", "chest"]), "\(kinds)")
        let again = Generator(seed: 7); again.depth = 1
        XCTAssertEqual(again.generate(5, 5).layers[2], u.gen.generate(5, 5).layers[2])
        XCTAssertNotEqual(u.gen.generate(5, 5).layers[2], s.world.gen.generate(5, 5).layers[2], "it is a different layer, not a copy of the surface")
        // digging gives stone and ore
        let wallAt = (0..<400).map { TilePos(o.x - 10 + $0 % 20, o.y - 10 + $0 / 20) }.first { s.content.tile(u.tile(2, $0.x, $0.y))?.key == "cave_wall" }!
        XCTAssertEqual(s.playerDig(at: wallAt, in: u)?.good, "stone")
        XCTAssertFalse(u.blocked(wallAt.x, wallAt.y))
        // saved and reopened: the same map, the same hole
        u.saveAll(); s.world.saveAll()
        let u2 = OpenWorld(seed: 7, budget: MemoryBudget(overrideMB: 256), depth: 1); u2.open(directory: dir)
        XCTAssertEqual(u2.tile(2, wallAt.x, wallAt.y), 0); XCTAssertEqual(u2.tile(2, o.x, o.y), s.content.tid("stairs_up"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("chunks_d1").path), "its chunks are stored apart from the surface")
        // back up the stairs
        guard let up = s.useStairs(at: o.center) else { return XCTFail("could not come up") }
        XCTAssertEqual(up.depth, 0); XCTAssertFalse(s.world.blocked(up.pos.tile.x, up.pos.tile.y))
        // down again, then the entrance is demolished: there is still a way out
        _ = s.useStairs(at: o.center)
        s.demolishBuild(at: o)
        XCTAssertEqual(u.tile(2, o.x, o.y), 0, "the partner stair goes with it")
        XCTAssertNil(s.useStairs(at: o.center))
        let out = s.climbOut(from: o.center + Vec2(160, 0))
        XCTAssertEqual(s.realm.player.depth, 0); XCTAssertFalse(s.world.blocked(out.tile.x, out.tile.y))
        XCTAssertNotNil((0..<49).map { TilePos(out.tile.x - 3 + $0 % 7, out.tile.y - 3 + $0 / 7) }.first { s.world.tile(2, $0.x, $0.y) == s.content.tid("stairs_down") }, "climbing out leaves a new entrance")
        // ruins hold finished goods, once
        var ruin: TilePos?
        for cy in -6...6 { for cx in -6...6 where ruin == nil && u.gen.isUnderRuin(cx, cy) { ruin = TilePos(cx * 32 + 15, cy * 32 + 15) } }
        let loot = s.playerOpenRuin(at: ruin!)
        XCTAssertNotNil(loot); XCTAssertGreaterThan(s.carried("iron"), 0)
        XCTAssertNil(s.playerOpenRuin(at: ruin!))
    }

    func testFromOreToToolsWithExactBookkeeping() {
        let s = makeSociety(7)
        let o = clearing(s)
        s.carry("wood", 40); s.carry("stone", 20)
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 60, piece: "workbench", cells: [o])).placed, 1)
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 61, piece: "furnace", cells: [TilePos(o.x + 2, o.y)])).placed, 1)
        let me = TilePos(o.x + 1, o.y + 1).center
        XCTAssertEqual(s.playerCraft("iron", near: me), "input:iron_ore")
        XCTAssertEqual(s.playerCraft("tools", near: Vec2(0, 0)), "station:workbench")
        // mine ore
        for i in 0..<4 { s.world.setTile(2, o.x + 4 + i, o.y + 4, s.content.tid("ore_iron")); XCTAssertEqual(s.playerDig(at: TilePos(o.x + 4 + i, o.y + 4))?.good, "iron_ore") }
        XCTAssertEqual(s.carried("iron_ore"), 8)
        let wood = s.carried("wood")
        XCTAssertNil(s.playerCraft("iron", near: me))
        XCTAssertEqual(s.carried("iron_ore"), 6); XCTAssertEqual(s.carried("wood"), wood - 1, "inputs leave when the work starts")
        XCTAssertEqual(s.carried("iron"), 0, "and the product is not there yet")
        XCTAssertEqual(s.playerCraft("planks", near: me), "busy")
        s.world.time += 3 * Society.hour; s.craftTick(); s.craftTick()
        XCTAssertEqual(s.carried("iron"), 1, "one batch, delivered once")
        XCTAssertNil(s.playerCraft("planks", near: me)); s.world.time += Society.hour; s.craftTick()
        XCTAssertNil(s.playerCraft("tools", near: me)); s.world.time += Society.hour; s.craftTick()
        XCTAssertEqual(s.carried("tools"), 1); XCTAssertEqual(s.carried("planks"), 1); XCTAssertEqual(s.carried("iron"), 0)
        // --- a town doing the same on its own
        let t = s.towns(of: 1)[0]
        t.fixtures = ["furnace": 1, "workbench": 1, "anvil": 1, "chest": 1]; t.cityT = 1e12
        t.goods = ["iron_ore": 20]; t.wood = 200; t.stone = 50; t.food = 500
        func total(_ k: String) -> Double { t.good(k) }
        var made = 0
        for _ in 0..<60 { let c = s.stats.crafted ?? 0; s.economyHourly(); made += (s.stats.crafted ?? 0) - c }
        XCTAssertGreaterThan(total("iron") + total("tools") + total("weapons"), 0)
        XCTAssertGreaterThan(total("planks") + total("parts"), 0)
        XCTAssertGreaterThan(made, 5)
        // every unit of ore is accounted for: smelted two-for-one into iron that is either in store or inside goods
        let ironMade = (20 - total("iron_ore")) / 2
        let ironUsed = total("tools") * 1 + total("weapons") * 2 + total("armor") * 3 + total("engines") * 2
        XCTAssertEqual(total("iron") + ironUsed, ironMade, accuracy: 0.001, "nothing appeared or vanished between furnace and store")
        // stations wait when they lack input and say why; they carry on when it arrives
        t.goods?["iron_ore"] = 0
        for _ in 0..<12 { s.economyHourly() }
        XCTAssertEqual(t.pause?["furnace#0"], "input:iron_ore")
        let iron = total("iron")
        t.addGood("iron_ore", 4)
        for _ in 0..<5 { s.economyHourly() }
        XCTAssertGreaterThanOrEqual(total("iron") + total("weapons") * 2 + total("armor") * 3 + total("tools") + total("engines") * 2, iron)
        XCTAssertLessThan(total("iron_ore"), 4)
        // a full store stops the line
        t.goods?["planks"] = 0; t.fixtures["chest"] = 0; s.realm.cfg.storeBase = 1; s.realm.cfg.storePerChest = 0
        for _ in 0..<4 { s.economyHourly() }
        XCTAssertEqual(t.pause?["workbench#0"], "full")
        // gear makes soldiers count for more; tools fill baskets
        s.refreshNations()
        let plain = s.gearBonus(2)
        s.towns(of: 2)[0].addGood("weapons", 50); s.towns(of: 2)[0].addGood("armor", 50)
        XCTAssertGreaterThan(s.gearBonus(2), plain + 0.3)
    }

    func testVillagersBuildMinesAndWorkshopsThatProduce() {
        let s = makeSociety(7)
        s.grantTech(5)
        runYears(s, 5)
        let towns = s.settlements.values.filter { !$0.abandoned }
        let goods = towns.reduce(into: [String: Double]()) { acc, t in for (k, v) in t.goods ?? [:] { acc[k, default: 0] += v } }
        print("ECONOMY after 5y: crafted=\(s.stats.crafted ?? 0) goods=\(goods.mapValues { Int($0) }.sorted { $0.key < $1.key }) mines=\(towns.reduce(0) { $0 + $1.count("mine", done: true) }) workshops=\(towns.reduce(0) { $0 + $1.count("workshop", done: true) })")
        XCTAssertGreaterThan(towns.reduce(0) { $0 + $1.count("mine", done: true) }, 0)
        XCTAssertGreaterThan(s.stats.crafted ?? 0, 10, "stations really produce")
        XCTAssertGreaterThan(goods["iron_ore", default: 0] + goods["iron", default: 0] + goods["weapons", default: 0] + goods["tools", default: 0], 0)
        XCTAssertEqual(s.audit(), [])
    }
}
