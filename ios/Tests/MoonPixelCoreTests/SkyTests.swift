import XCTest
@testable import MoonPixelCore

final class SkyTests: XCTestCase {
    func body(_ k: SkyBody.Kind, _ t: Double) -> SkyBody { Sky.bodies(time: t).first { $0.kind == k }! }

    func testTheSunCrossesTheSkyByDayAndIsDownAtNight() {
        let noon = 12.75 / 24 * MP.daySeconds, midnight = 0.0, dawn = 6.0 / 24 * MP.daySeconds, dusk = 19.5 / 24 * MP.daySeconds
        XCTAssertGreaterThan(body(.sun, noon).dir.y, 0.8, "high at noon")
        XCTAssertLessThan(body(.sun, midnight).dir.y, -0.3, "down at midnight")
        XCTAssertGreaterThan(body(.sun, dawn).dir.x, 0.8, "rises in the east")
        XCTAssertLessThan(body(.sun, dusk).dir.x, -0.8, "sets in the west")
        XCTAssertGreaterThan(body(.sun, noon).dir.z, 0.2, "crosses the southern sky")
    }

    func testTheMoonRunsThroughItsPhasesAndIsFullOppositeTheSun() {
        var seen = Set<Int>()
        for d in 0..<8 { seen.insert(Sky.phaseIndex(body(.moon, Double(d) * MP.daySeconds).phase)) }
        XCTAssertEqual(seen.count, 8, "eight phases in eight days")
        // full moon: four days in; at midnight the full moon is up while the sun is down
        let t = 4 * MP.daySeconds + 0.5 / 24 * MP.daySeconds
        XCTAssertEqual(Sky.phaseIndex(body(.moon, t).phase), 4)
        XCTAssertTrue(body(.moon, t).up); XCTAssertFalse(body(.sun, t).up)
    }

    func testThePlanetsWanderAndEveryBodyHasAModel() {
        let a = body(.ringed, 0), b = body(.ringed, MP.daySeconds * 0.3)
        XCTAssertNotEqual(a.dir, b.dir, "the planets move across the sky")
        for b in Sky.bodies(time: 1234) { XCTAssertFalse(Figure3D.skyBody(b).isEmpty, "\(b.kind) has a model") }
        for k in 0..<8 { XCTAssertFalse(Figure3D.moon(phase: k).isEmpty) }
        XCTAssertEqual(Sky.starlight(daylight: 0), 1); XCTAssertEqual(Sky.starlight(daylight: 1), 0)
    }

    func testUfoPortsVolcanoesAndUndergroundCitiesAreSparse() {
        let g = Generator(seed: 9)
        var ufo = 0, under = 0
        for cy in -40..<40 { for cx in -40..<40 { if g.isUfoPort(cx, cy) { ufo += 1 }; if g.isUnderCity(cx, cy) { under += 1 } } }
        // 80 x 80 chunks (2.5 km square): one port in each 14 x 14 block at most, one city in each 10 x 10 at most
        XCTAssertLessThanOrEqual(ufo, 49); XCTAssertLessThanOrEqual(under, 81)
        XCTAssertGreaterThan(under, 10, "still some to find")
        var volcanoes = Set<Int>()
        for y in stride(from: -1280, to: 1280, by: 64) { for x in stride(from: -1280, to: 1280, by: 64) {
            if let v = g.volcano(near: x, y, radius: 48) { volcanoes.insert(v.x * 100_000 + v.y) }
        } }
        XCTAssertLessThanOrEqual(volcanoes.count, 25, "a volcano in about one block of 512 m in eight")
    }

    func testAnUndergroundCityEntranceIsAPlazaRingedWithBeaconsAndAGatehouse() {
        let w = OpenWorld(seed: 9, budget: MemoryBudget(overrideMB: 256))
        let s = Society(world: w, seed: 9)
        guard let t = s.nearestUnderCity(cx: 0, cy: 0) else { return XCTFail("an underground city within reach") }
        XCTAssertEqual(w.tile(2, t.x, t.y), s.content.tid("stairs_down"), "the stairway down in the gatehouse")
        XCTAssertEqual(w.tile(2, t.x, t.y + 4), s.content.tid("gate_open"), "the gatehouse's open gate")
        var beacons = 0
        for y in (t.y - 12)...(t.y + 12) { for x in (t.x - 12)...(t.x + 12) where w.tile(2, x, y) == s.content.tid("lamp_on") { beacons += 1 } }
        XCTAssertGreaterThanOrEqual(beacons, 8, "beacons round the plaza")
        XCTAssertEqual(WorldMap.describe(s, TilePos(t.x, t.y + 6), zh: true), "地下城入口（门楼里有楼梯下去）")
    }
}

extension Anime3DPreviewTests {
    /// MP_PREVIEW: the sun, the moon in its eight phases and the three planets (docs/sky.png).
    func testPreviewSky() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        var sheet = Bitmap(1600, 600, fill: RGBA(14, 18, 44))
        let tex = Tex(b: Palette3D.bitmap.animeGraded())
        func cell(_ m: Mesh3D, _ x: Int, _ y: Int, _ w: Int, _ h: Int, span: Float) {
            let img = render([(m, tex, false, .zero, 0)], size: (w, h), yaw: .pi, pitch: 0, scale: Float(min(w, h)) / span, centre: .zero)
            for yy in 0..<h { for xx in 0..<w { let c = img.get(xx, yy); if c.a > 0 && !(c.r == 255 && c.g == 255 && c.b == 255) { sheet.set(x + xx, y + yy, c) } } }
        }
        cell(Figure3D.sun(), 0, 0, 400, 400, span: 160)
        cell(Figure3D.ringedPlanet(), 400, 0, 500, 400, span: 240)
        cell(Figure3D.redPlanet(), 900, 100, 200, 200, span: 40)
        cell(Figure3D.bluePlanet(), 1120, 60, 280, 280, span: 56)
        for k in 0..<8 { cell(Figure3D.moon(phase: k), k * 200, 400, 200, 200, span: 64) }
        var data = Data("\(sheet.w) \(sheet.h)\n".utf8); data.append(contentsOf: sheet.px)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("sky-a.rgba"))
    }
}
