import XCTest
@testable import MoonPixelCore

/// Sky cities, the air network (planes and saucers), and the teleport centre.
final class SkyTests: XCTestCase {
    func firstSky(_ s: Society) -> (name: String, cx: Int, cy: Int) {
        let list = s.skyCities(near: TilePos(0, 0), within: 60, zh: true)
        XCTAssertFalse(list.isEmpty)
        return list[0]
    }

    func testASkyCityFloatsOnItsStoreyWithAPlazaAnAirportAndAWayDown() {
        let s = makeSociety(21)
        let c = firstSky(s)
        XCTAssertTrue(s.world.gen.isSkyCity(c.cx, c.cy))
        let w = s.skyWorld()
        let ct = s.content
        let home = w.chunk(c.cx, c.cy)
        XCTAssertEqual(home.layers[2][16 * 32 + 16], ct.tid("glass_lift"), "the glass elevator down in its plaza")
        XCTAssertTrue(home.layers[0].contains(ct.tid("marble_floor")), "a marble plaza")
        let port = w.chunk(c.cx + 1, c.cy)
        XCTAssertTrue(port.layers[1].contains(ct.tid("runway")), "a runway")
        XCTAssertTrue(port.layers[0].contains(ct.tid("ufo_pad")), "a UFO pad")
        // the edge of the island is fenced; beyond it, open air
        let far = w.chunk(c.cx + 4, c.cy)
        XCTAssertTrue(far.layers[0].allSatisfy { $0 == 0 }, "open air off the island")
        var fenced = false
        for y in 0..<32 { for x in 0..<32 where w.chunk(c.cx + 2, c.cy).layers[2][y * 32 + x] == ct.tid("sky_rail") { fenced = true } }
        XCTAssertTrue(fenced, "a balustrade round its edge")
        XCTAssertFalse(s.skyFolk(center: Vec2(Double(c.cx * 32) * 16, Double(c.cy * 32) * 16), halfW: 1200, halfH: 1200).isEmpty, "its people")
        // the glass elevator down comes out on the ground right below
        _ = s.place(at: TilePos(c.cx * 32 + 16, c.cy * 32 + 17), depth: SkyTune.depth)
        XCTAssertEqual(s.realm.player.depth, SkyTune.depth)
        let down = s.rideLift(at: TilePos(c.cx * 32 + 16, c.cy * 32 + 16), to: 0)
        XCTAssertEqual(s.realm.player.depth, 0)
        XCTAssertLessThan(abs((down?.tile.x ?? 0) - (c.cx * 32 + 16)), 30)
    }

    func testPlanesAndSaucersFlyBetweenAirportsUfoPortsAndSkyCities() {
        let s = makeSociety(22)
        let c = firstSky(s)
        let hubs = s.airHubs(around: TilePos(0, 0), within: 60, zh: true)
        XCTAssertTrue(hubs.contains { $0.kind == .sky })
        let ufo = hubs.first { $0.kind == .ufo }
        // away from every airport: no flight
        _ = s.place(at: TilePos(c.cx * 32 + 16, c.cy * 32 + 18), depth: SkyTune.depth)
        _ = s.place(at: TilePos(5000, 5000), depth: 0)
        if s.airHubHere(zh: true) == nil { XCTAssertNil(s.airTravel(to: hubs[0], by: .ufo, zh: true)) }
        // from the sky city's airport: by plane to an airfield or by saucer to a UFO airport
        _ = s.place(at: Society.skyArrival(c.cx, c.cy, by: .airport), depth: SkyTune.depth)
        guard let here = s.airHubHere(zh: true) else { return XCTFail("the sky city's airport is a place of the network") }
        XCTAssertEqual(here.kind, .sky)
        if let u = ufo {
            XCTAssertNil(s.airTravel(to: u, by: .plane, zh: true), "no runway at a UFO airport")
            let r = s.airTravel(to: u, by: .ufo, zh: true)
            XCTAssertNotNil(r)
            XCTAssertEqual(r?.depth, 0)
            XCTAssertEqual(s.realm.player.depth, 0)
            XCTAssertGreaterThan(r?.km ?? 0, 0)
            // and back up by saucer to the sky city's pad
            let back = s.airTravel(to: hubs.first { $0.kind == .sky && $0.name.hasPrefix(c.name) }!, by: .ufo, zh: true)
            XCTAssertEqual(back?.depth, SkyTune.depth)
            XCTAssertEqual(s.skyWorld().tile(0, back!.pos.tile.x, back!.pos.tile.y), s.content.tid("ufo_pad"))
        }
    }

    func testTeleportAnywhereFromAnyLayerAndRememberPlaces() {
        let s = makeSociety(23)
        let c = firstSky(s)
        let targets = s.teleportTargets(from: TilePos(0, 0), zh: true)
        for g in [TeleportTarget.Group.city, .sky, .air] { XCTAssertTrue(targets.contains { $0.group == g }, "\(g)") }
        let sky = targets.first { $0.group == .sky }!
        XCTAssertNotNil(s.teleport(to: sky))
        XCTAssertEqual(s.realm.player.depth, SkyTune.depth)
        s.saveWaypoint("云上")
        // from the sky straight underground, then to the surface
        XCTAssertNotNil(s.teleport(to: TeleportTarget(group: .under, name: "下", tile: TilePos(c.cx * 32, c.cy * 32 + 600), depth: 1, detail: "")))
        XCTAssertEqual(s.realm.player.depth, 1)
        let town = targets.first { $0.group == .city }!
        XCTAssertNotNil(s.teleport(to: town))
        XCTAssertEqual(s.realm.player.depth, 0)
        let again = s.teleportTargets(from: TilePos(0, 0), zh: true)
        XCTAssertEqual(again.first { $0.group == .saved }?.name, "云上")
        XCTAssertEqual(again.filter { $0.group == .recent }.count, 3, "the last places, newest first")
        XCTAssertEqual(again.first { $0.group == .recent }?.name, town.name)
        // saved places survive saving
        let data = try! JSONEncoder().encode(s.realm)
        let back = try! JSONDecoder().decode(Realm.self, from: data)
        XCTAssertEqual(back.waypoints?.first?.name, "云上")
    }

    func testTheIslandIsRoundWithWingedMarbleHousesAndARockyUnderside() {
        let s = makeSociety(24)
        let c = firstSky(s)
        let w = s.skyWorld(), ct = s.content, gen = s.world.gen
        // the coast is a curve, not the edge of chunks: along a row through the middle, land then air, and the
        // reach differs from one direction to another
        var reach: [Int] = []
        for a in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 4) {
            var d = 0
            while d < 100 {
                let x = c.cx * 32 + 16 + Int((Double(d) * cos(a)).rounded()), y = c.cy * 32 + 16 + Int((Double(d) * sin(a)).rounded())
                if w.tile(0, x, y) == 0 { break }
                d += 1
            }
            reach.append(d)
        }
        XCTAssertTrue(reach.allSatisfy { $0 > 40 && $0 < 70 }, "\(reach)")
        XCTAssertGreaterThan(Set(reach).count, 2, "bays and headlands")
        // houses of white marble with an angel's wing on each side
        var walls = 0, wingsE = 0, wingsW = 0, rails = 0
        for cy in (c.cy - 2)...(c.cy + 2) { for cx in (c.cx - 2)...(c.cx + 2) {
            let l = w.chunk(cx, cy).layers[2]
            walls += l.filter { $0 == ct.tid("marble_wall") }.count
            wingsE += l.filter { $0 == ct.tid("wing_e") }.count; wingsW += l.filter { $0 == ct.tid("wing_w") }.count
            rails += l.filter { $0 == ct.tid("sky_rail") }.count
        } }
        XCTAssertGreaterThan(walls, 50, "marble houses")
        XCTAssertGreaterThan(wingsE, 2); XCTAssertEqual(wingsE, wingsW, "a wing on each side of every house")
        XCTAssertGreaterThan(rails, 150, "a balustrade all round the coast")
        // every wing stands outside a wall (east wing: the wall to its west)
        for cy in (c.cy - 2)...(c.cy + 2) { for cx in (c.cx - 2)...(c.cx + 2) {
            for i in 0..<MP.chunkArea where w.chunk(cx, cy).layers[2][i] == ct.tid("wing_e") {
                XCTAssertEqual(w.tile(2, cx * 32 + i % 32 - 1, cy * 32 + i / 32), ct.tid("marble_wall"))
            }
        } }
        // the 3D island has a deep underside of rock under its middle, shallow at the coast
        let mid = Mesher3D.build(ChunkInput3D(world: w, cx: c.cx, cy: c.cy), gen: gen)
        let lowest = mid.solid.positions.map { $0.y }.min() ?? 0
        let floor = mid.heights[16 * 32 + 16]
        XCTAssertLessThan(lowest, floor - 12, "a deep underside under the middle")
        // 2D: under the coast the underside hangs in the open air; elsewhere the ground below is washed blue
        // (the chunk with the south coast: island at the top, air below it)
        let south = (c.cx, c.cy + 2)
        let ch = w.chunk(south.0, south.1)
        XCTAssertTrue(ch.layers[0].contains(0) && ch.layers[0].contains(where: { $0 != 0 }))
        let sky = SkyBackdrop(north: w.chunk(south.0, south.1 - 1).layers[0], cx: south.0, cy: south.1, seed: s.world.seed)
        let pic = PixelArt.bakeSky(layers: ch.layers, ground: s.world.chunk(south.0, south.1).layers, sky: sky)
        XCTAssertEqual(pic.w, MP.chunkPx + 16)
        var earthy = 0
        for tx in 0..<32 {
            // the first tile of air under the coast in this column
            guard let ty = (1..<32).first(where: { ch.layers[0][$0 * 32 + tx] == 0 && ch.layers[0][($0 - 1) * 32 + tx] != 0 }) else { continue }
            let p = pic.get(tx * 16 + 8 + 8, ty * 16 + 24 + 8)
            if p.r > p.b { earthy += 1 }
        }
        XCTAssertGreaterThan(earthy, 10, "the underside hangs below the coast")
        let corner = pic.get(500, 500)
        XCTAssertGreaterThan(Int(corner.b), Int(corner.r), "blue air below")
        // the wings and marble are drawn in both looks and as solids
        for key in ["wing_e", "wing_w", "marble_wall", "sky_rail"] {
            let t = ct.tiles[Int(ct.tid(key))]!
            XCTAssertGreaterThan(AnimeArt.tile(t).px.count, 0)
        }
    }

    /// A picture of a whole sky island (MP_PREVIEW set to a directory): 6 x 6 chunks in the anime look, halved.
    func testPreviewIsland() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        let s = makeSociety(24)
        let c = firstSky(s)
        let w = s.skyWorld()
        let n = 6, cw = MP.chunkPx
        var sheet = Bitmap(cw * n, cw * n)
        for j in 0..<n { for i in 0..<n {
            let cx = c.cx - 3 + i, cy = c.cy - 3 + j
            let sky = SkyBackdrop(north: w.chunk(cx, cy - 1).layers[0], cx: cx, cy: cy, seed: s.world.seed)
            let pic = AnimeArt.bakeSky(layers: w.chunk(cx, cy).layers, ground: s.world.chunk(cx, cy).layers, sky: sky)
            for y in 0..<cw { for x in 0..<cw { sheet.set(i * cw + x, j * cw + y, pic.get((x + 8) * 2, (y + 24) * 2)) } }
        } }
        var d = Data("\(sheet.w) \(sheet.h)\n".utf8); d.append(contentsOf: sheet.px)
        try d.write(to: URL(fileURLWithPath: dir).appendingPathComponent("island.rgba"))
    }

    func testSkyHousesHaveRoofsAndTheIslandsAreSeenFromBelow() {
        let s = makeSociety(24)
        let c = firstSky(s)
        let w = s.skyWorld(), gen = s.world.gen
        // a chunk with a house: its mesh rises above the walls (the roof and its little gold dome)
        var roofed = false
        for cy in (c.cy - 1)...(c.cy + 1) { for cx in (c.cx - 1)...(c.cx + 1) where w.chunk(cx, cy).layers[2].contains(s.content.tid("marble_wall")) {
            let mesh = Mesher3D.build(ChunkInput3D(world: w, cx: cx, cy: cy), gen: gen)
            let floor = mesh.heights.filter { $0 > -999 }.max() ?? 0
            if (mesh.solid.positions.map { $0.y }.max() ?? 0) > floor + 2.2 { roofed = true }
        } }
        XCTAssertTrue(roofed, "roofs over the marble houses")
        // from far below: the whole island in one mesh, its floor at y 0 and its underside hanging under it
        let far = SkyIsland3D.far(gen: gen, centre: (c.cx, c.cy))
        XCTAssertFalse(far.isEmpty)
        XCTAssertLessThan(far.positions.map { $0.y }.min() ?? 0, -10)
        let xs = far.positions.map { $0.x }
        XCTAssertGreaterThan((xs.max() ?? 0) - (xs.min() ?? 0), 90, "as wide as the island")
    }
}
