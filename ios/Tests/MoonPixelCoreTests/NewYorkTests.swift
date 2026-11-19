import XCTest
@testable import MoonPixelCore

/// Build `kind` in the district: on the planner's site, or else the nearest free block by the centre.
@discardableResult func nycPut(_ s: Society, _ d: District, _ kind: String) -> Int? {
    let def = CityKind.byKey[kind]!
    if let site = s.findSite(d, w: def.w, h: def.d), let id = s.placeCityBuilding(d, kind: kind, at: site) { return id }
    for r in stride(from: 0, through: 120, by: 4) { for dy in stride(from: -r, through: r, by: 4) { for dx in stride(from: -r, through: r, by: 4) where max(abs(dx), abs(dy)) == r {
        let o = TilePos(d.center.x + dx, d.center.y + dy)
        if d.buildings.contains(where: { $0.x < o.x + def.w + 2 && o.x < $0.x + $0.w + 2 && $0.y < o.y + def.d + 2 && o.y < $0.y + $0.d + 2 }) { continue }
        if let id = s.placeCityBuilding(d, kind: kind, at: o) { return id }
    } } }
    return nil
}

final class NewYorkTests: XCTestCase {
    func rich(_ s: Society, near p: TilePos) -> District {
        let o = s.world.findFree(near: p, maxR: 40)
        return s.foundDistrict(name: "Midtown", at: o, nation: 1, money: 1_000_000,
                               store: ["stone": 50_000, "iron": 20_000, "parts": 20_000, "planks": 20_000])
    }

    func testSetbackProfilesStepInAndEndInASpire() {
        for (kind, side, n) in [("deco", 15, 64), ("crown", 13, 56), ("supertall", 13, 94)] {
            let insets = (0..<n).map { Skyline.inset(kind, level: $0, of: n, side: side) }
            XCTAssertEqual(insets.first, 0, "\(kind) rises straight from the street")
            XCTAssertEqual(insets.last, (side - 1) / 2, "\(kind) ends in a one-tile spire")
            XCTAssertEqual(insets, insets.sorted(), "\(kind) only ever steps in")
            XCTAssertGreaterThanOrEqual(Set(insets).count, 4, "\(kind) has several setbacks")
            XCTAssertTrue(Skyline.coreFits(inset: insets[n / 2], side: side), "\(kind): the core reaches the middle floors")
        }
        XCTAssertEqual(Set((0..<60).map { Skyline.inset("pencil", level: $0, of: 60, side: 9) }), [0], "the slim tower goes straight up")
    }

    func testEachTowerIsRealOnEveryFloorWithACoreLiftAndStairs() {
        let s = makeSociety(5)
        let d = rich(s, near: TilePos(-300, 260))
        for kind in ["deco", "crown", "supertall", "pencil"] {
            let def = CityKind.byKey[kind]!
            guard let id = nycPut(s, d, kind), let b = d.building(id) else { return XCTFail("\(kind) built") }
            let n = b.floors.count, side = b.w
            XCTAssertEqual(n, def.storeys)
            // the street floor fills the block; its door is there
            XCTAssertEqual(s.world.tile(2, b.entrance.x, b.entrance.y), s.content.tid("door_wood"), "\(kind): a street door")
            // every floor has walls on its setback line and a floor inside
            for level in 1..<n {
                let w = s.storeyWorld(level), i = Skyline.inset(kind, level: level, of: n, side: side)
                let mat = Skyline.walls(kind, level: level, of: n, side: side)
                let corner = w.tile(2, b.x + i, b.y + i)
                XCTAssertTrue([s.content.tid(mat.wall), s.content.tid(mat.window)].contains(corner), "\(kind) floor \(level): its wall at inset \(i)")
                if i > 0 { XCTAssertEqual(w.tile(2, b.x + i - 1, b.y + i - 1), 0, "\(kind) floor \(level): nothing outside the setback") }
                XCTAssertNotEqual(w.tile(0, b.x + i, b.y + i), 0, "\(kind) floor \(level): a floor under the wall")
            }
            // a roof terrace where it steps in
            if let l = (1..<n).first(where: { Skyline.inset(kind, level: $0, of: n, side: side) > Skyline.inset(kind, level: $0 - 1, of: n, side: side) }) {
                let below = Skyline.inset(kind, level: l - 1, of: n, side: side)
                let w = s.storeyWorld(l)
                XCTAssertNotEqual(w.tile(0, b.x + below, b.y + below), 0, "\(kind): a terrace on floor \(l)")
                XCTAssertEqual(w.tile(2, b.x + below, b.y + below), 0, "\(kind): open to the sky")
            }
            // the top is the spire
            if kind != "pencil" { XCTAssertEqual(s.storeyWorld(n - 1).tile(2, b.x + side / 2, b.y + side / 2), s.content.tid("spire_steel"), "\(kind): the spire") }
            // the core: a lift with a stop on every floor it reaches, and stairs between those floors
            let reach = (0..<n).filter { Skyline.coreFits(inset: Skyline.inset(kind, level: $0, of: n, side: side), side: side) }
            guard let lift = b.lift.flatMap({ s.lift($0) }) else { return XCTFail("\(kind): a core lift") }
            XCTAssertEqual(lift.stops.count, reach.count, "\(kind): the lift stops on every floor of the core")
            XCTAssertGreaterThanOrEqual(reach.count, n * 3 / 4, "\(kind): the core reaches most of the tower")
            let core = Skyline.core(x: b.x, y: b.y, side: side)
            XCTAssertEqual(lift.x, core.shaft.x); XCTAssertEqual(lift.y, core.shaft.y)
            for level in reach.dropLast() where reach.contains(level + 1) {
                let st = core.stairs[level % 2]
                let w = level == 0 ? s.world : s.storeyWorld(level)
                XCTAssertEqual(w.tile(2, st.x, st.y), s.content.tid("stairs_up"), "\(kind): stairs up from floor \(level)")
                XCTAssertEqual(s.storeyWorld(level + 1).tile(2, st.x, st.y), s.content.tid("stairs_down"), "\(kind): stairs arrive on floor \(level + 1)")
            }
        }
        XCTAssertEqual(s.audit(), [])
    }

    func testTheLiftCarriesYouToTheTopFloorOfTheCore() {
        let s = makeSociety(5)
        let d = rich(s, near: TilePos(-300, 260))
        guard let id = nycPut(s, d, "deco"), let b = d.building(id),
              let lift = b.lift.flatMap({ s.lift($0) }) else { return XCTFail("built") }
        let top = lift.stops.last!
        XCTAssertGreaterThan(top.level, 50, "the core reaches above floor 50")
        // the landing up there is a real floor, inside the walls
        XCTAssertNotNil(WorldGround(s).floor(OpenWorld.storeyBase + top.level, top.door))
    }

    func testBigDistrictsChooseNewYorkTowersAndBrownstones() {
        let s = makeSociety(5)
        let d = rich(s, near: TilePos(-300, 260))
        let commerce = ["shops", "offices", "mall", "skyscraper", "crown", "deco", "supertall"]
        XCTAssertEqual(s.nextKind(d, commerce, 3000), "supertall", "a big city builds its tallest first")
        XCTAssertEqual(s.nextKind(d, commerce, 1200), "crown")
        XCTAssertEqual(s.nextKind(d, commerce, 200), "shops", "a small one builds low")
        XCTAssertEqual(s.nextKind(d, ["flats", "terrace", "brownstone", "tower", "highrise", "pencil"], 120), "brownstone")
        XCTAssertEqual(s.nextKind(d, ["flats", "terrace", "brownstone", "tower", "highrise", "pencil"], 250), "tower", "apartment towers from 200 people")
        XCTAssertEqual(Society.facade("brownstone").wall, "wall_brownstone")
    }

    func testTheSkylineIsDrawnWholeFromAfar() {
        let s = makeSociety(5)
        let d = rich(s, near: TilePos(-300, 260))
        var ids: [Int] = []
        for kind in ["deco", "supertall"] {
            if let id = nycPut(s, d, kind) { ids.append(id) }
        }
        XCTAssertEqual(ids.count, 2)
        let blocks = s.skylineBlocks(near: d.center, radius: 200)
        for id in ids {
            let b = d.building(id)!
            let mine = blocks.filter { $0.building == id }
            XCTAssertEqual(mine.first?.from, 0); XCTAssertEqual(mine.last?.to, b.floors.count, "tiers cover every floor")
            XCTAssertEqual(mine.first?.w, b.w, "the base fills the block")
            XCTAssertEqual(mine.last?.w, 1, "the spire")
            XCTAssertEqual(zip(mine, mine.dropFirst()).filter { $0.0.to != $0.1.from }.count, 0, "tiers stack without gaps")
        }
        let mesh = Mesh3D.skyline(blocks)
        let tallest = blocks.map { $0.y($0.to) }.max()!
        XCTAssertGreaterThanOrEqual(mesh.bounds.max.y, tallest, "as tall as the towers are")
        XCTAssertGreaterThan(tallest - blocks[0].y(0), 150, "a 94-floor tower is about 190 tiles tall")
        let skip = Mesh3D.skyline(blocks, skipBelow: 30)
        XCTAssertLessThan(skip.triangles, mesh.triangles, "the near floors are left to the real tiles")
        XCTAssertGreaterThan(skip.bounds.min.y, blocks[0].y(29))
    }
}

extension Anime3DPreviewTests {
    /// A Manhattan-like block of towers, drawn as the 3D view draws them from afar (docs/nyc-skyline.png).
    func testPreviewSkyline() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        let s = makeSociety(5)
        let o = s.world.findFree(near: TilePos(-300, 260), maxR: 40)
        let d = s.foundDistrict(name: "Midtown", at: o, nation: 1, money: 10_000_000, store: ["stone": 500_000, "iron": 200_000, "parts": 200_000, "planks": 200_000])
        for kind in ["deco", "supertall", "crown", "pencil", "skyscraper", "crown", "highrise", "deco", "pencil", "brownstone", "brownstone", "tower"] {
            nycPut(s, d, kind)
        }
        let blocks = s.skylineBlocks(near: d.center, radius: 300)
        var sheet = Bitmap(1600, 900, fill: RGBA(255, 255, 255))
        let x0 = blocks.map { $0.x }.min()!, x1 = blocks.map { $0.x + $0.w }.max()!, z0 = blocks.map { $0.y }.min()!, z1 = blocks.map { $0.y + $0.d }.max()!
        let top = blocks.map { $0.y($0.to) }.max()!, base = blocks.map { $0.y(0) }.min()!
        let c = SIMD3<Float>(Float(x0 + x1) / 2, (top + base) / 2 + 8, Float(z0 + z1) / 2)
        for (k, anime) in [false, true].enumerated() {
            var mesh = Mesh3D.skyline(blocks, anime: anime)
            // the streets: asphalt with pale kerbs round each block
            var ground = Mesh3D(); ground.cel = anime
            ground.box(Float(x0 - 12), base - 0.4, Float(z0 - 12), Float(x1 + 12), base - 0.05, Float(z1 + 12), RGBA(70, 72, 78))
            for b in blocks where b.from == 0 { ground.box(Float(b.x - 1), base - 0.05, Float(b.y - 1), Float(b.x + b.w + 1), base, Float(b.y + b.d + 1), RGBA(190, 186, 176)) }
            if anime { mesh = mesh.inked(width: 0.08) }
            let pal = anime ? Palette3D.bitmap.animeGraded() : Palette3D.bitmap
            let span = max(Float(x1 - x0), Float(z1 - z0)) * 1.2
            let scale = min(780 / span, 860 / (top - base + 20))
            let img = render([(ground, Tex(b: pal), false, .zero, 0), (mesh, Tex(b: pal), false, .zero, 0)], size: (800, 900), yaw: 0.6, pitch: 0.18, scale: scale, centre: c)
            sheet.blit(img, sx: 0, sy: 0, sw: 800, sh: 900, dx: k * 800, dy: 0, blend: false)
        }
        var data = Data("\(sheet.w) \(sheet.h)\n".utf8); data.append(contentsOf: sheet.px)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("nyc-skyline.rgba"))
    }
}
