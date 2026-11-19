import XCTest
@testable import MoonPixelCore

final class LuxuryTests: XCTestCase {
    func rich(_ s: Society) -> District {
        let o = s.world.findFree(near: TilePos(-300, 260), maxR: 40)
        return s.foundDistrict(name: "Hills", at: o, nation: 1, money: 1_000_000,
                               store: ["stone": 50_000, "iron": 20_000, "parts": 20_000, "planks": 20_000, "fuel": 5_000])
    }

    func testAVillaHasAGardenAPoolATwoStoreyHouseAndALuxuryCar() {
        let s = makeSociety(5)
        let d = rich(s)
        guard let id = nycPut(s, d, "villa"), let b = d.building(id) else { return XCTFail("villa") }
        XCTAssertEqual(b.floors.count, 2)
        XCTAssertEqual(s.world.tile(2, b.x, b.y), s.content.tid("fence"), "a fenced garden")
        XCTAssertEqual(s.world.tile(2, b.entrance.x, b.entrance.y), s.content.tid("fence_gate"))
        XCTAssertEqual(s.world.tile(0, b.x + 11, b.y + 7), s.content.tid("shallow_water"), "a pool")
        XCTAssertEqual(s.world.tile(0, b.x + 1, b.y + 8), s.content.tid("grass"), "a lawn")
        XCTAssertEqual(s.world.tile(2, b.x + 2, b.y + 1), s.content.tid("wall_limestone"), "a stone house")
        var flowers = 0
        for y in b.y..<(b.y + b.d) { for x in b.x..<(b.x + b.w) where s.content.tile(s.world.tile(3, x, y))?.key.hasPrefix("flower") == true { flowers += 1 } }
        XCTAssertGreaterThan(flowers, 4, "flower beds")
        let up = s.storeyWorld(1)
        XCTAssertEqual(up.tile(2, b.x + 3, b.y + 2), s.content.tid("bed"), "bedrooms upstairs")
        XCTAssertEqual(up.tile(2, b.x + 2, b.y + 6), s.content.tid("fence"), "a balcony railing")
        let cars = s.realm.transport.vehicles.filter { $0.model != nil && $0.tile.x >= b.x && $0.tile.x < b.x + b.w && $0.tile.y >= b.y && $0.tile.y < b.y + b.d }
        XCTAssertEqual(cars.count, 1, "its luxury car on the drive")
        XCTAssertTrue(CarModel.luxury.contains(cars[0].carModel))
        XCTAssertNotNil(cars[0].paint)
        XCTAssertNil(cars[0].showcase, "the owners drive it")
        XCTAssertEqual(s.audit(), [])
    }

    func testVillasFormAQuarterAndEightOfThemBringAShowroomWithSixCarsOnShow() {
        let s = makeSociety(5)
        let d = rich(s)
        XCTAssertNil(s.luxuryToBuild(d), "no villas in a small town")
        d.buildings.append({ var b = CityBuilding(); b.id = 900; b.kind = "highrise"; b.state = .open; b.floors = (0..<20).map { _ in var f = CityFloor(); f.residents = 20; return f }; return b }())
        XCTAssertEqual(s.luxuryToBuild(d), "pool", "400 people: first a public swimming pool")
        XCTAssertNotNil(nycPut(s, d, "pool"))
        XCTAssertEqual(s.luxuryToBuild(d), "villa", "then villas")
        var ids: [Int] = []
        for _ in 0..<8 { if let id = nycPut(s, d, "villa") { ids.append(id) } }
        XCTAssertEqual(ids.count, 8)
        XCTAssertEqual(s.luxuryToBuild(d), "showroom")
        guard let sid = nycPut(s, d, "showroom"), let sh = d.building(sid) else { return XCTFail("showroom") }
        let shown = s.realm.transport.vehicles.filter { $0.showcase == true && $0.tile.x >= sh.x && $0.tile.x < sh.x + sh.w && $0.tile.y >= sh.y && $0.tile.y < sh.y + sh.d }
        XCTAssertEqual(shown.count, 6, "six cars on show")
        XCTAssertEqual(Set(shown.map { $0.carModel }), Set(CarModel.luxury), "every luxury model")
        XCTAssertEqual(s.world.tile(2, sh.x + 1, sh.y), s.content.tid("wall_glass"), "a glass hall")
        // the cars on show never leave; the villa owners' cars go about town
        s.carErrands()
        XCTAssertTrue(shown.allSatisfy { $0.task.goal == nil })
    }

    func testEveryCarModelHasItsOwnDrawingAndShape() {
        var tops: [[UInt8]] = [], meshes: [Int] = []
        for m in CarModel.allCases {
            let b = CarArt.top(m, paint: m.paints[0])
            XCTAssertEqual(b.w, 32); XCTAssertEqual(b.h, 20)
            XCTAssertGreaterThan(stride(from: 3, to: b.px.count, by: 4).filter { b.px[$0] > 200 }.count, b.w * b.h / 2, "\(m) drawn")
            tops.append(b.px)
            let mesh = Figure3D.car(m, paint: m.paints[0])
            XCTAssertFalse(mesh.isEmpty)
            let bb = mesh.bounds
            XCTAssertEqual(Double(bb.max.x - bb.min.x), VehicleKind.car.spec.length * (m == .limousine ? 1.25 : 1), accuracy: 0.1, "\(m): the car's own length")
            XCTAssertGreaterThan(bb.max.x - bb.min.x, (bb.max.z - bb.min.z) * 1.6, "\(m): a car's proportions, long and narrow")
            meshes.append(mesh.triangles)
        }
        XCTAssertEqual(Set(tops.map { $0.hashValue }).count, CarModel.allCases.count, "each model looks different from above")
        XCTAssertGreaterThan(Figure3D.car(.suv, paint: "#202020").bounds.max.y, Figure3D.car(.supercar, paint: "#202020").bounds.max.y + 0.3, "an SUV stands taller than a supercar")
    }
}

extension Anime3DPreviewTests {
    /// MP_PREVIEW: a villa quarter with a showroom from above (anime), every car model drawn from above, and
    /// the 3D car shapes side by side (docs/villas-and-cars.png).
    func testPreviewVillasAndCars() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        let s = makeSociety(5)
        let o = s.world.findFree(near: TilePos(-300, 260), maxR: 40)
        let d = s.foundDistrict(name: "Hills", at: o, nation: 1, money: 1_000_000, store: ["stone": 50_000, "iron": 20_000, "parts": 20_000, "planks": 20_000, "fuel": 5_000])
        var placed: [CityBuilding] = []
        for k in ["villa", "villa", "villa", "villa", "showroom"] { if let id = nycPut(s, d, k), let b = d.building(id) { placed.append(b) } }
        let x0 = placed.map { $0.x }.min()! - 2, y0 = placed.map { $0.y }.min()! - 2
        let x1 = placed.map { $0.x + $0.w }.max()! + 2, y1 = placed.map { $0.y + $0.d }.max()! + 2
        // bake the chunks under the quarter and cut it out
        let cell = AnimeArt.bakeChunk(layers: s.world.chunk(x0 >> 5, y0 >> 5).layers).w / 32     // pixels a tile in the baked ground
        var map = Bitmap((x1 - x0) * cell, (y1 - y0) * cell, fill: RGBA(120, 160, 90))
        for cy in (y0 >> 5)...((y1 - 1) >> 5) { for cx in (x0 >> 5)...((x1 - 1) >> 5) {
            let img = AnimeArt.bakeChunk(layers: s.world.chunk(cx, cy).layers)
            map.blit(img, sx: 0, sy: 0, sw: img.w, sh: img.h, dx: (cx * 32 - x0) * cell, dy: (cy * 32 - y0) * cell, blend: false)
        } }
        // the cars on top, from above, at their places
        for v in s.realm.transport.vehicles where v.kind == .car {
            let top = CarArt.top(v.carModel, paint: v.paint ?? "#d84038", len: v.spec.length, wid: max(0.5, v.spec.deckW + 0.2), ppt: Double(cell))
            map.blit(top, sx: 0, sy: 0, sw: top.w, sh: top.h, dx: Int(v.x / 16 * Double(cell)) - x0 * cell - top.w / 2, dy: Int(v.y / 16 * Double(cell)) - y0 * cell - top.h / 2, blend: true)
        }
        // every model and paint, larger
        var cars = Bitmap(5 * 140, 5 * 90, fill: RGBA(236, 236, 240))
        for (i, m) in CarModel.allCases.enumerated() { for (j, p) in m.paints.prefix(5).enumerated() {
            let b = CarArt.top(m, paint: p, len: 1.0, wid: 0.62, ppt: 128)
            cars.blit(b, sx: 0, sy: 0, sw: b.w, sh: b.h, dx: j * 140 + 6, dy: i * 90 + 4, blend: true)
        } }
        // 3D shapes
        var parts: [(Mesh3D, Tex?, Bool, SIMD3<Float>, Float)] = []
        for (i, m) in CarModel.allCases.enumerated() { parts.append((Figure3D.car(m, paint: m.paints[0]).inked(width: 0.012), Tex(b: Palette3D.bitmap.animeGraded()), false, SIMD3(Float(i) * 1.6, 0, 0), 0)) }
        let shapes = render(parts, size: (900, 260), yaw: 0.35, pitch: 0.42, scale: 95, centre: SIMD3(3.2, 0.3, 0))
        var sheet = Bitmap(max(map.w, cars.w), map.h + cars.h + shapes.h, fill: .white)
        sheet.blit(map, sx: 0, sy: 0, sw: map.w, sh: map.h, dx: 0, dy: 0, blend: false)
        sheet.blit(cars, sx: 0, sy: 0, sw: cars.w, sh: cars.h, dx: 0, dy: map.h, blend: false)
        sheet.blit(shapes, sx: 0, sy: 0, sw: shapes.w, sh: shapes.h, dx: 0, dy: map.h + cars.h, blend: false)
        var data = Data("\(sheet.w) \(sheet.h)\n".utf8); data.append(contentsOf: sheet.px)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("villas-and-cars.rgba"))
    }
}

extension Anime3DPreviewTests {
    /// MP_PREVIEW: people modelled in 3D (curved shapes), several looks and poses (docs/people-3d.png).
    func testPreviewPeople3D() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        var looks: [Look] = []
        for (i, (skin, hair, shirt, pants)) in [("#f2c8a4", "#5a3a22", "#5a8ae8", "#4a4a5a"), ("#ffe0c8", "#f0a0c0", "#ffffff", "#e05a7a"), ("#e8b890", "#202838", "#d84a4a", "#30304a"), ("#f8d8c0", "#f0d060", "#60c080", "#5a4a3a")].enumerated() {
            var l = Look(); l.skin = skin; l.hair = hair; l.shirt = shirt; l.pants = pants; l.shoes = "#3a2a22"; l.style = i; looks.append(l)
        }
        var parts: [(Mesh3D, Tex?, Bool, SIMD3<Float>, Float)] = []
        let pal = Tex(b: Palette3D.bitmap)
        for (i, l) in looks.enumerated() {
            for (j, f) in [0, 1, 3].enumerated() {
                let mesh = Figure3D.human(l, frame: f, held: f == 3 ? "hammer" : "", child: false, female: i % 2 == 1)
                parts.append((mesh, pal, false, SIMD3(Float(i) * 1.2 - 1.8, 0, Float(j) * 1.4 - 1.4), 0))
            }
        }
        parts.append((Figure3D.human(looks[1], frame: 0, held: "", child: true, female: true), pal, false, SIMD3(3.0, 0, 0), 0))
        print("PEOPLE triangles per adult", Figure3D.human(looks[0], frame: 0, held: "", child: false, female: false).triangles)
        let img = render(parts, size: (1100, 640), yaw: 0.3, pitch: 0.28, scale: 150, centre: SIMD3(0.3, 0.9, 0))
        var data = Data("\(img.w) \(img.h)\n".utf8); data.append(contentsOf: img.px)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("people-3d.rgba"))
    }
}
