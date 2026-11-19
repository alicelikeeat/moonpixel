import XCTest
@testable import MoonPixelCore

final class LandmarkTests: XCTestCase {
    func world(_ seed: Int = 9) -> (OpenWorld, Society) {
        let w = OpenWorld(seed: seed, budget: MemoryBudget(overrideMB: 256))
        return (w, Society(world: w, seed: seed))
    }

    func testUfoAirportsStandWhereTheMazesWereWithAPadBeaconsAndATower() {
        let (w, s) = world()
        guard let p = s.nearestUfoPort(cx: 0, cy: 0) else { return XCTFail("a UFO airport within reach") }
        XCTAssertTrue(Generator(seed: 9).isUfoPort(p.0, p.1), "same seed, same airports")
        let ox = p.0 * 32, oy = p.1 * 32
        XCTAssertEqual(w.tile(0, ox + 15, oy + 13), s.content.tid("ufo_pad"), "the landing pad")
        var lamps = 0
        for y in oy..<(oy + 32) { for x in ox..<(ox + 32) where w.tile(2, x, y) == s.content.tid("lamp_on") { lamps += 1 } }
        XCTAssertGreaterThanOrEqual(lamps, 12, "beacons round the pad")
        XCTAssertEqual(w.tile(2, ox + 1, oy + 25), s.content.tid("spire_steel"), "the control tower")
        XCTAssertEqual(w.tile(2, ox + 5, oy + 29), s.content.tid("antenna"))
    }

    func testSaucersRestLiftCircleAndLandOnARound() {
        let pad = Vec2(1000, 1000)
        var landed = 0, high = 0, beams = 0, far = 0.0
        for i in 0..<180 {
            let u = Society.ufoState(pad: pad, time: Double(i), saucer: 0, seed: 0)
            if u.landed { landed += 1 }
            if u.z > 10 { high += 1 }
            if u.beam { beams += 1 }
            far = max(far, u.pos.distance(to: pad) / 16)
        }
        XCTAssertGreaterThan(landed, 60, "rests on the pad a good part of the round")
        XCTAssertGreaterThan(high, 50, "flies high")
        XCTAssertGreaterThan(beams, 20, "beam on lifting off and landing")
        XCTAssertGreaterThan(far, 25, "circles wide")
        let a = Society.ufoState(pad: pad, time: 0, saucer: 0, seed: 0), b = Society.ufoState(pad: pad, time: Society.ufoRound, saucer: 0, seed: 0)
        XCTAssertEqual(a.pos, b.pos); XCTAssertEqual(a.z, b.z, accuracy: 1e-9, "a round comes back to where it began")
        // the two saucers keep half a round apart: never both resting
        for i in 0..<180 {
            let s0 = Society.ufoState(pad: pad, time: Double(i), saucer: 0, seed: 0), s1 = Society.ufoState(pad: pad, time: Double(i), saucer: 1, seed: 0)
            XCTAssertFalse(s0.landed && s1.landed, "one of the two is always up or on its way")
        }
        let (_, s) = world()
        guard let p = s.nearestUfoPort(cx: 0, cy: 0) else { return XCTFail("airport") }
        let here = Vec2(Double(p.0 * 32 + 16), Double(p.1 * 32 + 14)) * 16
        XCTAssertEqual(s.ufos(near: here, reach: 600).count, 2, "two saucers at an airport")
        let m = Figure3D.ufo()
        XCTAssertFalse(m.isEmpty)
        XCTAssertEqual(m.bounds.min.y, 0, accuracy: 0.05, "the saucer's legs touch the pad")
    }

    func testVolcanoesRiseWithACraterOfLavaAndBasaltSlopes() {
        let (w, s) = world()
        guard let v = s.nearestVolcano(near: TilePos(0, 0), within: 1400) else { return XCTFail("a volcano within reach") }
        let gen = w.gen
        // the cone: higher than the land around it; the crater lower than its rim
        let rim = Terrain3D.level(elevation: gen.elevation(v.x + 6, v.y)), foot = Terrain3D.level(elevation: gen.elevation(v.x + 30, v.y))
        let crater = Terrain3D.level(elevation: gen.elevation(v.x, v.y))
        XCTAssertGreaterThan(rim, foot + 12, "a tall cone: rim \(rim) foot \(foot)")
        XCTAssertLessThan(crater, rim, "a crater sunk in the top")
        XCTAssertEqual(w.tile(0, v.x, v.y), s.content.tid("lava"), "lava in the crater")
        XCTAssertTrue(w.blocked(v.x, v.y), "lava cannot be walked into")
        XCTAssertEqual(w.tile(0, v.x + 12, v.y + 1) == s.content.tid("basalt") || w.tile(0, v.x + 12, v.y + 1) == s.content.tid("lava"), true, "basalt slopes")
        var trees = 0
        for y in (v.y - 22)...(v.y + 22) { for x in (v.x - 22)...(v.x + 22) where (x - v.x) * (x - v.x) + (y - v.y) * (y - v.y) < 22 * 22 && s.content.tile(w.tile(2, x, y))?.big == true { trees += 1 } }
        XCTAssertEqual(trees, 0, "nothing grows on it")
        XCTAssertTrue(WorldMap.describe(s, TilePos(v.x, v.y), zh: false).contains("Volcano"))
    }

    func testMountainsAreHighAndTheLandRollsInHills() {
        let gen = Generator(seed: 9)
        var top = 0, rolling = 0
        var prev: Int?
        for x in stride(from: -2000, through: 2000, by: 8) {
            let lv = Terrain3D.level(elevation: gen.elevation(x, 333))
            if let p = prev, lv != p { rolling += 1 }
            prev = lv
        }
        for y in stride(from: -3000, through: 3000, by: 24) { for x in stride(from: -3000, through: 3000, by: 24) {
            top = max(top, Terrain3D.level(elevation: gen.elevation(x, y)))
        } }
        XCTAssertGreaterThan(top, 36, "high mountains (\(top) levels)")
        XCTAssertGreaterThan(rolling, 120, "the land rises and falls")
    }

    func testUndergroundCitiesHaveStreetsHousesASquareAVaultAndAStairway() {
        let (w, s) = world()
        var city: (Int, Int)?
        for y in -30...30 { for x in -30...30 where city == nil && w.gen.isUnderCity(x, y) && w.gen.volcano(near: x * 32 + 16, y * 32 + 16, radius: 40) == nil && !w.gen.isUfoPort(x, y) { city = (x, y) } }
        guard let c = city else { return XCTFail("an underground city") }
        let u = s.underworld()
        let ox = c.0 * 32, oy = c.1 * 32
        XCTAssertEqual(u.tile(2, ox + 15, oy + 14), s.content.tid("statue"), "the square's statue")
        XCTAssertEqual(u.tile(2, ox + 16, oy + 16), s.content.tid("stairs_up"), "the stairway up")
        XCTAssertEqual(w.tile(2, ox + 16, oy + 16), s.content.tid("stairs_down"), "the gatehouse's stairs on the surface above")
        var beds = 0, stalls = 0, lamps = 0
        for y in oy..<(oy + 32) { for x in ox..<(ox + 32) {
            let k = s.content.tile(u.tile(2, x, y))?.key
            if k == "bed" { beds += 1 }; if k == "market_stall" { stalls += 1 }; if k == "lantern_post" { lamps += 1 }
        } }
        XCTAssertGreaterThanOrEqual(beds, 10, "houses with beds"); XCTAssertEqual(stalls, 4, "a market"); XCTAssertGreaterThan(lamps, 6, "lit streets")
        // the vault gives an artifact, once
        let vault = TilePos(ox + 16, oy + 13)
        let first = s.playerOpenVault(at: vault)
        XCTAssertTrue(first.ok); XCTAssertNotNil(first.power)
        XCTAssertFalse(s.playerOpenVault(at: vault).ok, "a vault gives once")
        XCTAssertFalse(s.playerOpenVault(at: TilePos(ox + 5, oy + 5)).ok, "not any chest")
    }

    func testAPublicSwimmingPoolHasLanesAPaddlingPoolAndChangingRooms() {
        let s = makeSociety(5)
        let o = s.world.findFree(near: TilePos(-300, 260), maxR: 40)
        let d = s.foundDistrict(name: "Lido", at: o, nation: 1, money: 1_000_000, store: ["stone": 50_000, "iron": 20_000, "parts": 20_000, "planks": 20_000])
        guard let id = nycPut(s, d, "pool"), let b = d.building(id) else { return XCTFail("pool") }
        let water = s.content.tid("shallow_water")
        var wet = 0
        for y in b.y..<(b.y + b.d) { for x in b.x..<(b.x + b.w) where s.world.tile(0, x, y) == water { wet += 1 } }
        XCTAssertGreaterThan(wet, 60, "a big pool")
        XCTAssertEqual(s.world.tile(3, b.x + 2, b.y + 3), s.content.tid("lily_pad"), "lane ropes")
        XCTAssertEqual(s.world.tile(0, b.x + 3, b.y + 8), water, "a paddling pool")
        XCTAssertEqual(s.world.tile(2, b.x + b.w - 4, b.y + 8), s.content.tid("door_wood"), "changing rooms")
        XCTAssertEqual(s.world.tile(2, b.x, b.y), s.content.tid("fence"))
    }
}

extension Anime3DPreviewTests {
    /// MP_PREVIEW: the 3D view's terrain round a volcano, and a UFO airport with its saucers (docs/landmarks-3d.png).
    func testPreviewLandmarks3D() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        let w = OpenWorld(seed: 9, budget: MemoryBudget(overrideMB: 256))
        let s = Society(world: w, seed: 9)
        func scene(_ cx0: Int, _ cy0: Int, _ n: Int, extra: [(Mesh3D, SIMD3<Float>)]) -> [(Mesh3D, Tex?, Bool, SIMD3<Float>, Float)] {
            var parts: [(Mesh3D, Tex?, Bool, SIMD3<Float>, Float)] = []
            for cy in cy0..<(cy0 + n) { for cx in cx0..<(cx0 + n) {
                let input = ChunkInput3D(world: w, cx: cx, cy: cy)
                let mesh = Mesher3D.build(input, gen: w.gen, anime: true)
                let off = SIMD3<Float>(Float((cx - cx0) * 32), 0, Float((cy - cy0) * 32))
                parts.append((mesh.ground, Tex(b: AnimeArt.bakeGround(layers: input.layers, relief: mesh.relief)), false, off, 0))
                parts.append((mesh.solid, Tex(b: Palette3D.bitmap.animeGraded()), false, off, 0))
                parts.append((mesh.sprites, Tex(b: AnimeArt.atlas), true, off, 0))
            } }
            for (m, at) in extra { parts.append((m.inked(width: 0.04), Tex(b: Palette3D.bitmap.animeGraded()), false, at, 0)) }
            return parts
        }
        var sheet = Bitmap(1600, 700, fill: .white)
        if let v = s.nearestVolcano(near: TilePos(0, 0), within: 1400) {
            let cx0 = OpenWorld.floorDiv(v.x, 32) - 1, cy0 = OpenWorld.floorDiv(v.y, 32) - 1
            let base = Float(Terrain3D.level(elevation: w.gen.elevation(v.x, v.y + 24))) * Terrain3D.step
            let img = render(scene(cx0, cy0, 3, extra: []), size: (800, 700), yaw: 0.5, pitch: 0.32, scale: 9, centre: SIMD3(Float(v.x - cx0 * 32), base + 4, Float(v.y - cy0 * 32)))
            sheet.blit(img, sx: 0, sy: 0, sw: 800, sh: 700, dx: 0, dy: 0, blend: false)
        }
        if let p = s.nearestUfoPort(cx: 0, cy: 0) {
            let lv = Float(Terrain3D.level(elevation: w.gen.elevation(p.0 * 32 + 16, p.1 * 32 + 14))) * Terrain3D.step
            let pad = Vec2(Double(p.0 * 32 + 16), Double(p.1 * 32 + 14)) * 16
            var extra: [(Mesh3D, SIMD3<Float>)] = []
            for k in 0..<2 {
                let u = Society.ufoState(pad: pad, time: 60 + Double(k) * 10, saucer: k, seed: 0)
                extra.append((Figure3D.ufo(), SIMD3(Float(u.pos.x / 16) - Float(p.0 * 32), lv + Float(k == 0 ? 0 : 6), Float(u.pos.y / 16) - Float(p.1 * 32))))
            }
            let img = render(scene(p.0, p.1, 1, extra: extra), size: (800, 700), yaw: 0.55, pitch: 0.5, scale: 20, centre: SIMD3(16, lv + 1, 15))
            sheet.blit(img, sx: 0, sy: 0, sw: 800, sh: 700, dx: 800, dy: 0, blend: false)
        }
        var data = Data("\(sheet.w) \(sheet.h)\n".utf8); data.append(contentsOf: sheet.px)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("landmarks-3d.rgba"))
    }
}
