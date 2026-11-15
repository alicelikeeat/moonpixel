import XCTest
@testable import MoonPixelCore

final class CityIdentityTests: XCTestCase {
    func testEachKindOfCityLaysItselfOutItsOwnWay() {
        let s = makeSociety(9)
        let towns = s.settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        let t = towns[0]
        // soldiers' buildings face the nearest enemy town
        let enemy = towns.filter { $0.nation != t.nation }.min { ($0.center - t.center).lengthSquared < ($1.center - t.center).lengthSquared }!
        let e = Vec2(Double(enemy.center.x - t.center.x), Double(enemy.center.y - t.center.y)).normalized
        let mil = s.slotScore(t, "barracks")
        let slots = (-4...4).flatMap { y in (-4...4).map { TilePos($0, y) } }.filter { $0 != TilePos(0, 0) }
        let bestMil = slots.min { mil($0) < mil($1) }!
        XCTAssertGreaterThan(Double(bestMil.x) * e.x + Double(bestMil.y) * e.y, 0, "barracks go on the side facing the enemy")
        let house = s.slotScore(t, "house")
        XCTAssertEqual(slots.min { house($0) < house($1) }!.lengthSquared, 1, "houses fill in around the centre")
        let market = s.slotScore(t, "market")
        XCTAssertEqual(slots.min { market($0) < market($1) }!.lengthSquared, 1, "the market is on the square")
        // a farming town rings itself with fields
        if let farmTown = towns.first(where: { s.cityFocus($0) == "agricultural" }) {
            let f = s.slotScore(farmTown, "farm")
            XCTAssertGreaterThanOrEqual(slots.min { f($0) < f($1) }!.lengthSquared, 16)
        }
    }

    /// Every landmark, built for real: its door is on the wall facing the town, nothing blocks it, and the
    /// inside can be walked into: what is drawn is what you can walk.
    func testLandmarkEntrancesAreWhereTheArtIsAndCanBeUsed() {
        for (i, type) in Society.landmarkSpecs.keys.sorted().enumerated() {
            let s = makeSociety(30 + i)
            let t = s.settlements.values.sorted { $0.id < $1.id }[0]
            XCTAssertTrue(s.queue(t, type), type)
            let b = t.buildings.last!
            for c in b.cells { s.world.setTile(c.layer, b.x + c.dx, b.y + c.dy, c.key.isEmpty ? 0 : s.content.tid(c.key)) }
            let doorCell = b.cells.first { $0.key == "door_wood" }!
            let door = TilePos(b.x + doorCell.dx, b.y + doorCell.dy)
            XCTAssertTrue(doorCell.dx == 0 || doorCell.dy == 0 || doorCell.dx == b.w - 1 || doorCell.dy == b.h - 1, "\(type): the door is in the wall")
            let mid = TilePos(b.x + b.w / 2, b.y + b.h / 2)
            XCTAssertLessThan((door - t.center).lengthSquared, (mid - t.center).lengthSquared, "\(type): the door faces the town")
            XCTAssertFalse(s.world.blocked(b.door.x, b.door.y), "\(type): the step outside is free")
            // walk in from outside
            var seen: Set<TilePos> = [b.door], q = [b.door]
            while let p = q.popLast() {
                for d in [TilePos(1, 0), TilePos(-1, 0), TilePos(0, 1), TilePos(0, -1)] {
                    let n = TilePos(p.x + d.x, p.y + d.y)
                    if seen.contains(n) || abs(n.x - mid.x) > b.w + 2 || abs(n.y - mid.y) > b.h + 2 { continue }
                    if s.world.blocked(n.x, n.y) { continue }
                    seen.insert(n); q.append(n)
                }
            }
            let inside = (1..<(b.h - 1)).flatMap { y in (1..<(b.w - 1)).map { TilePos(b.x + $0, b.y + y) } }.filter { !s.world.blocked($0.x, $0.y) }
            XCTAssertFalse(inside.isEmpty)
            XCTAssertTrue(inside.allSatisfy { seen.contains($0) }, "\(type): every free cell inside can be reached through the door")
            // collision is the drawn walls: every wall cell blocks
            for c in b.cells where c.layer == 2 && c.key.hasPrefix("wall") { XCTAssertTrue(s.world.blocked(b.x + c.dx, b.y + c.dy)) }
        }
    }

    func testTownsNeverBuildOverWhatThePlayerBuilt() {
        let s = makeSociety(12)
        let t = s.settlements.values.sorted { $0.id < $1.id }[0]
        var mine: [(TilePos, Int, UInt8)] = []
        let o = t.center + TilePos(10, -12)
        for dy in 0..<5 { for dx in 0..<6 {
            let p = TilePos(o.x + dx, o.y + dy)
            let edge = dx == 0 || dy == 0 || dx == 5 || dy == 4
            let (layer, key) = edge ? (2, "wall_brick") : (0, "brick_floor")
            s.world.setTile(layer, p.x, p.y, s.content.tid(key)); mine.append((p, layer, s.content.tid(key)))
        } }
        for k in 0..<8 { let p = TilePos(t.center.x - 14 + k, t.center.y + 15); s.world.setTile(1, p.x, p.y, s.content.tid("cobble_road")); mine.append((p, 1, s.content.tid("cobble_road"))) }
        runYears(s, 1.0)
        for (p, l, id) in mine { XCTAssertEqual(s.world.tile(l, p.x, p.y), id, "player's tile at \(p) kept") }
        XCTAssertGreaterThan(t.buildings.filter { $0.done }.count, 2, "the town did keep building elsewhere")
    }

    func testConquestChangesTheFlagsFirstAndTheBuildingsKeepTheirStyle() {
        let s = makeSociety(14)
        runYears(s, 0.6)
        let t = s.settlements.values.filter { !$0.abandoned && $0.nation != nil }.sorted { $0.id < $1.id }[0]
        let old = t.nation!
        let new = s.realm.nations.map { $0.id }.first { $0 != old }!
        // a banner in town and a roofed building
        let pole = s.world.findFree(near: t.center + TilePos(2, -5), maxR: 4)
        s.world.setTile(2, pole.x, pole.y, s.content.tid("banner_\(old)"))
        let roofsBefore = s.roofs(minX: t.center.x - 60, minY: t.center.y - 60, maxX: t.center.x + 60, maxY: t.center.y + 60).filter { $0.town == t.id }
        let lg = Legion(); lg.id = s.realm.nextLegion; s.realm.nextLegion += 1; lg.nation = new; lg.home = t.id; lg.state = 2; lg.pos = t.center.center
        s.realm.legions.append(lg)
        s.capture(t, by: lg)
        XCTAssertEqual(s.world.tile(2, pole.x, pole.y), s.content.tid("banner_\(new)"), "the flag is the new owner's at once")
        XCTAssertEqual(t.flagOf, new)
        let after = s.roofs(minX: t.center.x - 60, minY: t.center.y - 60, maxX: t.center.x + 60, maxY: t.center.y + 60).filter { $0.town == t.id }
        for r in after where roofsBefore.contains(where: { $0.building == r.building }) { XCTAssertEqual(r.nation, old, "roofs stay as they were built") }
        XCTAssertTrue(s.gateCrests(minX: -100000, minY: -100000, maxX: 100000, maxY: 100000).filter { c in t.gates.contains(c.pos) }.allSatisfy { $0.nation == new })
    }

    func testTheThreeNationsLookDifferentNotOnlyInColour() {
        func mask(_ b: Bitmap) -> [Bool] {
            // brightness pattern, colour thrown away: what someone without colour vision still sees
            var out: [Bool] = []
            var i = 0
            while i + 2 < b.px.count {
                let r = Int(b.px[i]), g = Int(b.px[i + 1]), bl = Int(b.px[i + 2])
                let lum: Int = (r + g + bl) / 3
                out.append(lum > 140)
                i += 4
            }
            return out
        }
        let roofs = (1...3).map { mask(PixelArt.roof(nation: $0, w: 6, h: 5)) }
        let crests = (1...3).map { mask(PixelArt.gateCrest(nation: $0, color: "#808080")) }
        for i in 0..<3 { for j in (i + 1)..<3 {
            XCTAssertNotEqual(roofs[i], roofs[j], "roof patterns \(i + 1) and \(j + 1)")
            XCTAssertNotEqual(crests[i], crests[j], "gate crests \(i + 1) and \(j + 1) differ even in grey")
        } }
        // banners in the tile atlas
        let at = PixelArt.atlas
        func cell(_ key: String) -> [Bool] {
            let id = Int(Content.shared.tid(key)); var b = Bitmap(PixelArt.cell, PixelArt.cell)
            b.blit(at, sx: (id % 16) * PixelArt.cell, sy: (id / 16) * PixelArt.cell, sw: PixelArt.cell, sh: PixelArt.cell, dx: 0, dy: 0, blend: false)
            return mask(b)
        }
        let banners = (1...3).map { cell("banner_\($0)") }
        XCTAssertNotEqual(banners[0], banners[1]); XCTAssertNotEqual(banners[1], banners[2]); XCTAssertNotEqual(banners[0], banners[2])
        // walls differ by material
        let s = makeSociety(3)
        let ts = s.realm.nations.map { n in s.towns(of: n.id).first }.compactMap { $0 }
        if s.has("masonry") { XCTAssertGreaterThan(Set(ts.map { s.styledWall($0, "wall_wood") }).count, 1) }
    }
}
