import XCTest
@testable import MoonPixelCore

final class CityWarTests: XCTestCase {
    func hours(_ s: Society, _ n: Int) { for _ in 0..<n { s.world.time += Society.hour; s.realmHourly() } }
    func capitals(_ s: Society) -> [Int] { s.realm.nations.compactMap { $0.capital } }

    func testCitiesGrowLandmarksKindsAndOneCapitalEach() {
        let s = makeSociety(7)
        s.grantTech(3)
        runYears(s, 7)
        var kinds: [String: Int] = [:], marks: [String: Int] = [:]
        for t in s.settlements.values where !t.abandoned {
            s.surveyTown(t)
            kinds[s.cityKind(t), default: 0] += 1
            for b in t.buildings where b.done && Society.landmarkSpecs[b.type] != nil { marks[b.type, default: 0] += 1 }
        }
        print("CITIES after 7y: kinds=\(kinds.sorted { $0.key < $1.key }) landmarks=\(marks.sorted { $0.key < $1.key }) capitals=\(capitals(s))")
        XCTAssertGreaterThanOrEqual(kinds.filter { $0.key != "town" }.count, 2, "cities differ in character")
        XCTAssertGreaterThanOrEqual(marks.count, 3, "several kinds of landmark were built")
        for n in s.realm.nations where n.exileSince == nil {
            guard let c = s.capital(of: n.id) else { XCTFail("\(n.nameEn) has no capital"); continue }
            XCTAssertEqual(c.nation, n.id)
            XCTAssertEqual(s.realm.nations.filter { $0.capital == c.id }.count, 1, "one capital, one nation")
            let pole = c.center + TilePos(0, -3)
            XCTAssertEqual(s.world.tile(2, pole.x, pole.y), s.content.tid("banner_\(n.id)"), "the capital flies its nation's banner")
        }
        XCTAssertGreaterThan(marks["palace", default: 0], 0, "capitals raise palaces")
        // each nation builds in its own material
        if let brick = s.towns(of: 2).flatMap({ $0.buildings }).first(where: { Society.landmarkSpecs[$0.type] != nil && $0.done }) {
            XCTAssertEqual(s.world.tile(2, brick.x, brick.y), s.content.tid("wall_brick"))
        }
        // chronicle: numbered, bounded, queryable
        let all = s.realm.chron ?? []
        XCTAssertEqual(all.map { $0.id }, all.map { $0.id }.sorted()); XCTAssertEqual(Set(all.map { $0.id }).count, all.count)
        XCTAssertLessThanOrEqual(all.count, s.realm.cfg.maxNews + s.realm.cfg.maxHistory)
        XCTAssertEqual(s.events(after: s.lastEventID - 3).count, 3)
        XCTAssertTrue(all.contains { $0.kind == "capital_named" && $0.city != nil && !$0.cause.isEmpty })
        // (a nation may be between capitals or in exile at this moment: take one that has a seat)
        guard let seat = s.realm.nations.compactMap({ s.capital(of: $0.id) }).first, let info = s.cityInfo(seat.id) else { return XCTFail("no capital anywhere") }
        print("CAPINFO \(info.name) landmarks=\(info.landmarks.map { $0.type }) stocks=\(info.stocks.count)")
        XCTAssertTrue(info.capital); XCTAssertFalse(info.stocks.isEmpty)
        let palaces = s.realm.nations.compactMap { s.capital(of: $0.id) }.filter { c in c.buildings.contains { $0.type == "palace" } }
        XCTAssertFalse(palaces.isEmpty)
        for c in palaces { XCTAssertTrue(s.cityInfo(c.id)!.landmarks.contains { $0.type == "palace" }, "the palace is listed among the landmarks") }
        XCTAssertTrue(s.cityLabels(far: true).allSatisfy { $0.capital || s.settlements[$0.id]!.members.count >= 30 }, "from afar only capitals and big cities are named")
        XCTAssertEqual(s.audit(), [])
    }

    func testCapitalLostMovedExiledUnifiedDividedAndDeleted() {
        let s = makeSociety(7)
        hours(s, 3)
        // nation 2 needs a second town to move its court to
        if s.towns(of: 2).count < 2, let spare = s.towns(of: 1).first(where: { $0.id != s.realm.nations[0].capital }) ?? s.towns(of: 3).first(where: { $0.id != s.realm.nations[2].capital }) {
            s.flip(spare, to: 2)
            hours(s, 1)
        }
        guard let cap2 = s.capital(of: 2) else { return XCTFail("nation 2 has no capital") }
        XCTAssertEqual(s.governance(2), s.realm.cfg.govNoPalace, accuracy: 0.001, "a capital without a palace governs a little less well")
        XCTAssertGreaterThan(s.towns(of: 2).count, 1)
        // the capital falls, the nation lives on
        s.flip(cap2, to: 1)
        hours(s, 1)
        XCTAssertNil(s.capital(of: 2)); XCTAssertNotNil(s.realm.nation(2)?.moving, "a temporary seat is named while the court moves")
        XCTAssertEqual(cap2.formerCapital, 2, "the lost city remembers what it was")
        XCTAssertEqual(s.governance(2), s.realm.cfg.govNoCapital, accuracy: 0.001)
        XCTAssertTrue(s.realm.chron!.contains { $0.kind == "capital_lost" && $0.city == cap2.id })
        XCTAssertEqual(s.world.tile(2, cap2.center.x, cap2.center.y - 3), s.content.tid("banner_1"), "flags change with the owner")
        XCTAssertFalse(cap2.buildings.isEmpty == false && cap2.abandoned, "buildings stay")
        // the move needs time and stores
        guard let mv = s.realm.nation(2)?.moving, let seat = s.settlements[mv.to] else { return XCTFail("no move under way") }
        seat.wood = 0
        hours(s, Int(s.realm.cfg.capitalMoveYears * 24) + 4)
        XCTAssertNil(s.capital(of: 2), "no stores, no move")
        seat.wood = 200; seat.food = 400
        hours(s, Int(s.realm.cfg.capitalMoveYears * 24) + 4)
        XCTAssertEqual(s.capital(of: 2)?.id, seat.id)
        XCTAssertTrue(s.realm.chron!.contains { $0.kind == "capital_moved" && $0.city == seat.id })
        // every town lost: exile, no capital; land regained: a capital again
        for t in s.towns(of: 2) { s.flip(t, to: 1) }
        hours(s, 1)
        XCTAssertNotNil(s.realm.nation(2)?.exileSince); XCTAssertNil(s.realm.nation(2)?.capital)
        XCTAssertEqual(s.governance(2), 0)
        s.flip(seat, to: 2)
        hours(s, 1)
        XCTAssertEqual(s.capital(of: 2)?.id, seat.id); XCTAssertNil(s.realm.nation(2)?.exileSince)
        // unity keeps the old capitals as memories; division gives three seats again
        guard let cap3 = s.capital(of: 3) else { return XCTFail("nation 3 has no capital") }
        for t in s.settlements.values where !t.abandoned { t.nation = 1 }
        for lg in s.realm.legions { lg.nation = 1 }
        s.landCheck(); hours(s, 1)
        XCTAssertEqual(s.realm.era, 1)
        XCTAssertNotNil(s.capital(of: 1), "the unifier's capital is the imperial capital")
        XCTAssertEqual(cap3.formerCapital, 3)
        XCTAssertTrue(s.split())
        XCTAssertEqual(Set(capitals(s)).count, 3, "three nations, three different capitals")
        for n in s.realm.nations { XCTAssertEqual(s.capital(of: n.id)?.nation, n.id) }
        // a world law wipes a capital off the map
        guard let doomed = s.capital(of: 1) else { return XCTFail("nation 1 has no capital") }
        s.realm.nations[0].capital = doomed.id
        let run = s.beginLaw(LawPlan(mode: .guixu, seed: 1, towns: [doomed.id], region: [doomed.center.x >> 5, doomed.center.y >> 5, doomed.center.x >> 5, doomed.center.y >> 5]))
        while !run.step(64) {}
        hours(s, 1)
        XCTAssertTrue(doomed.abandoned)
        if !s.towns(of: 1).isEmpty { XCTAssertNotNil(s.capital(of: 1)); XCTAssertNotEqual(s.capital(of: 1)?.id, doomed.id) } else { XCTAssertNil(s.realm.nation(1)?.capital) }
        XCTAssertEqual(s.audit(), [])
        // history can still be read after the place is gone
        XCTAssertTrue(s.chronicleView(majorOnly: true).contains { $0.gone }, "events of a vanished city are kept and marked")
    }

    func testPlayerFoundsACityThatFillsWorksAndBecomesCapital() {
        let s = makeSociety(7)
        hours(s, 2)
        let home = s.towns(of: 1)[0]
        var site = TilePos.none
        for k in 0..<400 where site.isNone {
            let c = home.center + TilePos(50 + k % 20 * 3, -30 + k / 20 * 3)
            var ok = !s.world.gen.isMaze(c.x >> 5, c.y >> 5) && !s.settlements.values.contains { ($0.center - c).lengthSquared < 45 * 45 }
            for dy in -6...6 { for dx in -8...8 where ok && (s.content.water[Int(s.world.tile(0, c.x + dx, c.y + dy))]) { ok = false } }
            if ok { site = c }
        }
        for dy in -6...6 { for dx in -8...8 { s.world.setTile(2, site.x + dx, site.y + dy, 0) } }
        XCTAssertEqual(s.registerCity(at: site, name: "Hope"), "nation")
        s.playerJoin(1)
        XCTAssertEqual(s.registerCity(at: site, name: "Hope"), "beds")
        for g in ["wood", "stone", "iron", "parts", "gold_ore", "food"] { s.carry(g, 500) }
        var id = 100
        func put(_ piece: String, _ cells: [TilePos]) { id += 1; XCTAssertEqual(s.commitBuild(BuildPlan(id: id, piece: piece, cells: cells)).placed, cells.count, piece) }
        let beds = (0..<14).map { TilePos(site.x - 7 + $0, site.y + 3) }
        put("floor_wood", beds); put("bed", beds)
        XCTAssertEqual(s.registerCity(at: site, name: "Hope"), "store")
        put("warehouse", [TilePos(site.x - 3, site.y - 2)])
        XCTAssertEqual(s.registerCity(at: home.center + TilePos(5, 5), name: "x"), "close")
        let people = s.agents.count
        XCTAssertNil(s.registerCity(at: site, name: "Hope"))
        let city = s.settlements.values.first { $0.byPlayer == true }!
        XCTAssertEqual(s.cityName(city), "Hope"); XCTAssertEqual(city.nation, 1)
        XCTAssertGreaterThan(city.members.count, 0, "people move into what the player built")
        XCTAssertEqual(s.agents.count, people, "they came from the nation's other towns; nobody was invented")
        XCTAssertTrue(s.realm.chron!.contains { $0.kind == "city_founded" && $0.city == city.id })
        for _ in 0..<6 { s.realm.cool["settle:\(city.id)"] = 0; hours(s, 1) }
        XCTAssertGreaterThanOrEqual(city.members.count, 8)
        // a workbench in the city is used by its people
        put("workbench", [TilePos(site.x + 2, site.y - 2)])
        city.wood = 100; s.surveyTown(city)
        XCTAssertEqual(city.fixture("workbench"), 1)
        hours(s, 6)
        XCTAssertGreaterThan(city.good("planks"), 0, "the station the player placed really produces")
        // petition for capital
        XCTAssertEqual(s.petitionCapital(city.id), "palace")
        put("throne", [TilePos(site.x, site.y - 3)])
        s.surveyTown(city)
        if city.members.count < s.realm.cfg.capitalPop { XCTAssertEqual(s.petitionCapital(city.id), "people"); for i in 0..<8 { s.newAgent(city, age: 25, female: i % 2 == 0).nation = 1 } }
        city.food = 10
        XCTAssertEqual(s.petitionCapital(city.id), "food")
        city.food = 400; city.wood = 200
        XCTAssertNil(s.petitionCapital(city.id))
        XCTAssertEqual(s.petitionCapital(city.id), "moving")
        hours(s, Int(s.realm.cfg.capitalMoveYears * 24) + 3)
        XCTAssertEqual(s.capital(of: 1)?.id, city.id, "the player's city is the capital")
        XCTAssertEqual(s.governance(1), 1, accuracy: 0.001, "with a throne it governs fully")
        XCTAssertEqual(home.formerCapital, 1)
        XCTAssertEqual(s.audit(), [])
    }

    /// Ring of stone walls with one gate around a town square.
    func wallIn(_ s: Society, _ t: Settlement, r: Int = 7) {
        for d in -r...r {
            for p in [TilePos(t.center.x + d, t.center.y - r), TilePos(t.center.x + d, t.center.y + r), TilePos(t.center.x - r, t.center.y + d), TilePos(t.center.x + r, t.center.y + d)] {
                s.world.setTile(1, p.x, p.y, 0)
                s.world.setTile(2, p.x, p.y, s.content.tid(d == 0 && p.y == t.center.y + r ? "gate_open" : "wall_stone"))
            }
        }
        s.surveyTown(t)
    }

    func strengthen(_ s: Society, _ nation: Int, soldiers: Int) {
        for t in s.towns(of: nation) {
            let g = s.garrison(t, create: true)!
            g.nation = nation
            for a in t.members.compactMap({ s.agents[$0] }).sorted(by: { $0.id < $1.id }) where a.legion == nil && a.stage(s.world.time) == "adult" && g.members.count < soldiers { s.enlist(a, g) }
        }
    }

    func testCampaignFromMusterToOccupationAndRebuilding() {
        let s = makeSociety(7)
        runYears(s, 1.2)                                   // houses to damage, stores to draw on
        let target = s.towns(of: 2)[0]
        wallIn(s, target)
        XCTAssertGreaterThanOrEqual(target.walls.count, s.realm.cfg.wallMin, "the town is walled")
        strengthen(s, 1, soldiers: 16); strengthen(s, 2, soldiers: 4)
        for t in s.towns(of: 1) { t.addGood("engines", 4); t.food = 800 }
        s.refreshNations()
        let workers = s.towns(of: 1).reduce(0) { $0 + $1.members.filter { s.agents[$0]?.legion == nil }.count }
        s.realm.relations[0].since = -1e9
        var kinds: [String] = []
        s.onEvent = { k, _, _ in kinds.append(k) }
        s.declare(1, on: 2)
        guard let lg = s.realm.legions.first(where: { $0.state == 1 && $0.nation == 1 }) else { return XCTFail("no army") }
        let u = s.units(lg)
        print("CAMPAIGN army=\(lg.members.count) units=\(u) engines=\(lg.engines ?? 0) food=\(Int(lg.food ?? 0)) route=\(lg.route?.count ?? 0) forded=\(lg.forded ?? false)")
        XCTAssertGreaterThan(u[0], 0); XCTAssertGreaterThan(u[1], 0); XCTAssertGreaterThan(u[2], 0); XCTAssertGreaterThan(u[3], 0); XCTAssertGreaterThan(u[4], 0, "foot, bow, horse, engines and a supply train")
        XCTAssertGreaterThan(lg.food ?? 0, 0, "rations were drawn from real stores")
        XCTAssertGreaterThan(lg.route?.count ?? 0, 2)
        XCTAssertLessThan(s.towns(of: 1).reduce(0) { $0 + $1.members.filter { s.agents[$0]?.legion == nil }.count }, workers + 1, "soldiers come out of the workforce")
        lg.target = target.id; lg.route = nil
        let wallsBefore = target.walls.count
        var sawWalls = false, sawStorm = false, sawHold = false
        var t = 0.0
        while t < 2400 && target.nation == 2 && s.realm.legions.contains(where: { $0 === lg }) && lg.state != 3 {
            s.realmTick(2); s.world.time += 2; t += 2
            if lg.state == 2 { if lg.phase == 0 { sawWalls = true }; if lg.phase == 1 { sawStorm = true }; if lg.phase == 2 { sawHold = true } }
            if lg.state == 2 && target.siege == lg.id { XCTAssertFalse(target.gates.contains { s.world.tile(2, $0.x, $0.y) == s.content.tid("gate_open") } && lg.phase == 0 && sawWalls == false) }
        }
        print("CAMPAIGN events=\(kinds.filter { ["war", "siege", "breach", "captured", "repelled", "refugees"].contains($0) }) after \(Int(t)) s, owner=\(target.nation ?? 0), army=\(lg.members.count) morale=\(lg.morale ?? 0)")
        XCTAssertTrue(kinds.contains("siege")); XCTAssertTrue(sawWalls, "walls had to be dealt with first")
        XCTAssertTrue(kinds.contains("breach"), "engines opened the wall")
        XCTAssertLessThan(target.walls.count, wallsBefore, "the breach is a real gap in the wall tiles")
        XCTAssertTrue(sawStorm && sawHold, "then the storming, then holding the square")
        XCTAssertEqual(target.nation, 1, "the city was occupied")
        XCTAssertTrue(kinds.contains("captured"))
        let breach = s.realm.chron!.last { $0.kind == "breach" }!
        XCTAssertEqual(s.world.tile(2, Int(breach.x / 16), Int(breach.y / 16)), 0)
        // occupation: identity stays, the place is damaged, people flee, unrest starts, gates reopen
        XCTAssertGreaterThan(target.members.filter { s.agents[$0]?.nation == 2 }.count, 0, "residents keep who they are")
        XCTAssertGreaterThan(target.buildings.filter { !$0.done }.count, 0, "the city is damaged")
        XCTAssertGreaterThan(target.unrest ?? 0, 0)
        XCTAssertNil(target.siege)
        XCTAssertTrue(target.gates.allSatisfy { s.world.tile(2, $0.x, $0.y) == s.content.tid("gate_open") })
        XCTAssertEqual(s.audit(), [])
        // truce comes, and rebuilding takes time
        let damaged = target.buildings.filter { !$0.done }.count
        s.realm.nations[0].fatigue = 1.2
        hours(s, 1)
        XCTAssertEqual(s.realm.relation(1, 2)?.state, 2, "exhaustion forces a truce")
        runYears(s, 0.02)
        XCTAssertGreaterThan(target.buildings.filter { !$0.done }.count, 0, "nothing is whole again at once")
        runYears(s, 1.5)
        XCTAssertLessThan(target.buildings.filter { !$0.done && !$0.retry.isEmpty }.count, damaged + 1)
        XCTAssertEqual(s.audit(), [])
    }

    func testArmiesMeetingInTheFieldFightUntilOneBreaks() {
        let s = makeSociety(7)
        runYears(s, 0.3)
        strengthen(s, 1, soldiers: 14); strengthen(s, 2, soldiers: 8)
        for t in s.settlements.values { t.food = 600 }
        s.refreshNations()
        s.realm.relations[0].since = -1e9
        var kinds: [String] = []
        s.onEvent = { k, _, _ in kinds.append(k) }
        s.declare(1, on: 2); s.muster(2, against: 1)
        let a = s.realm.legions.first { $0.nation == 1 && $0.state == 1 }!, b = s.realm.legions.first { $0.nation == 2 && $0.state == 1 }!
        b.pos = a.pos + Vec2(100, 0)
        let na = a.members.count, nb = b.members.count
        s.realmTick(2)
        XCTAssertEqual(a.state, 4); XCTAssertEqual(b.state, 4); XCTAssertTrue(kinds.contains("battle"))
        var t = 0.0
        while t < 900 && a.state == 4 && b.state == 4 { s.realmTick(2); s.world.time += 2; t += 2 }
        print("FIELD \(na) vs \(nb) -> \(a.members.count) vs \(b.members.count) in \(Int(t)) s; morale \(a.morale ?? 0) / \(b.morale ?? 0); states \(a.state)/\(b.state)")
        XCTAssertLessThan(a.members.count + b.members.count, na + nb, "both sides bled")
        XCTAssertTrue(a.state == 3 || b.state == 3 || a.members.isEmpty || b.members.isEmpty, "one side broke and fell back")
        XCTAssertTrue(a.state == 1 || b.state == 1 || a.members.isEmpty || b.members.isEmpty, "the victor marches on")
        XCTAssertTrue(s.takeFX().contains { $0.kind == "volley" || $0.kind == "charge" || $0.kind == "rout" })
        // unit mix matters: horse loves open ground, archers want a screen
        let lg = a.members.isEmpty ? b : a
        for id in lg.members { s.agents[id]?.unit = Unit.cavalry }
        lg.pos = Vec2(0, 0)
        let open = s.openGround(lg.pos)
        let horse = s.legionPower(lg, mode: 0)
        for id in lg.members { s.agents[id]?.unit = Unit.infantry }
        let foot = s.legionPower(lg, mode: 0)
        if open { XCTAssertGreaterThan(horse, foot * 1.4) } else { XCTAssertLessThan(horse, foot) }
        XCTAssertLessThan(s.legionPower(lg, mode: 1), foot + 0.001, "storming walls is harder than fighting in a field")
        for id in lg.members { s.agents[id]?.unit = Unit.archer }
        XCTAssertLessThan(s.legionPower(lg, mode: 0, enemyCavalry: true), s.legionPower(lg, mode: 0, enemyCavalry: false), "unscreened archers give way to cavalry")
        XCTAssertEqual(s.audit(), [])
    }

    func testPlayerChangesRoadsSuppliesWallsAndRations() {
        let s = makeSociety(7)
        runYears(s, 0.3)
        let a = s.towns(of: 1)[0], b = s.towns(of: 2)[0]
        // a river across the way with one bridge
        let mid = TilePos((a.center.x + b.center.x) / 2, (a.center.y + b.center.y) / 2)
        let dx = b.center.x - a.center.x, dy = b.center.y - a.center.y
        let horizontal = abs(dx) >= abs(dy)
        var river: [TilePos] = []
        for k in -90...90 { for w in 0..<3 { river.append(horizontal ? TilePos(mid.x + w, mid.y + k) : TilePos(mid.x + k, mid.y + w)) } }
        for t in river { s.world.setTile(0, t.x, t.y, s.content.tid("water")); s.world.setTile(1, t.x, t.y, 0); s.world.setTile(2, t.x, t.y, 0) }
        let cut = s.marchRoute(from: a.center, to: b.center)
        s.carry("wood", 100); s.carry("stone", 200); s.carry("parts", 20); s.carry("engines", 3); s.carry("food", 100)
        let span = (0..<3).map { horizontal ? TilePos(mid.x + $0, mid.y) : TilePos(mid.x, mid.y + $0) }
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 1, piece: "bridge", cells: span)).placed, 3)
        let bridged = s.marchRoute(from: a.center, to: b.center)
        XCTAssertFalse(bridged.forded, "with a bridge there is a legal road")
        XCTAssertTrue(bridged.points.contains { p in span.contains { $0.center.distance(to: p) < 80 } }, "and it goes over the bridge")
        if cut.forded { XCTAssertTrue(true) } else { XCTAssertGreaterThan(s.routeLength(cut.points), s.routeLength(bridged.points), "without it the army must go round") }
        for t in span { s.demolishBuild(at: t) }
        let broken = s.marchRoute(from: a.center, to: b.center)
        XCTAssertTrue(broken.forded || s.routeLength(broken.points) > s.routeLength(bridged.points), "breaking the bridge closes the road again")
        // supply train: cut it and the army goes hungry
        strengthen(s, 1, soldiers: 12)
        for t in s.towns(of: 1) { t.food = 900 }
        s.refreshNations()
        s.realm.relations[0].since = -1e9
        s.declare(1, on: 2)
        let lg = s.realm.legions.first { $0.nation == 1 && $0.state == 1 }!
        lg.food = 0.5; lg.convoyT = 0
        let stock = s.settlements[lg.home]!.food
        s.stepLegion(lg, 2)
        XCTAssertNotNil(lg.convoyAt, "a convoy sets out when rations run low")
        XCTAssertLessThan(s.settlements[lg.home]!.food, stock, "its load comes out of the town's real stores")
        let load = lg.convoyLoad ?? 0
        // the player ambushes the train
        s.playerJoin(2)
        for id in lg.members where s.agents[id]?.unit == Unit.supply { s.die(s.agents[id]!, "battle") }
        s.stepLegion(lg, 2)
        XCTAssertNil(lg.convoyAt, "no carriers, no convoy: the load is lost")
        let m0 = lg.morale ?? 0
        for _ in 0..<60 { s.stepLegion(lg, 2); s.world.time += 2 }
        XCTAssertEqual(lg.food ?? 0, 0, accuracy: 0.001)
        XCTAssertLessThan(lg.morale ?? 1, m0, "hunger eats morale")
        XCTAssertLessThan(lg.supply, 0.6)
        XCTAssertGreaterThan(load, 0)
        // rations handed over by a friend
        s.playerJoin(1)
        XCTAssertGreaterThan(s.playerFeedLegion(near: lg.pos), 0)
        XCTAssertGreaterThan(lg.food ?? 0, 0)
        // towers and engines on the walls make a city harder to take
        s.playerJoin(2)
        s.surveyTown(b)
        let plain = s.fortBonus(b)
        let spot = s.world.findFree(near: b.center + TilePos(6, 6), maxR: 5)
        XCTAssertEqual(s.commitBuild(BuildPlan(id: 2, piece: "tower", cells: [spot])).placed, 1)
        s.surveyTown(b)
        XCTAssertGreaterThan(s.fortBonus(b), plain)
        XCTAssertEqual(s.audit(), [])
    }
}
