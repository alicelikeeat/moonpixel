import XCTest
@testable import MoonPixelCore

/// Ten character models (five of the sea floor), the maps of the worlds below, and going to a city.
final class CharacterTests: XCTestCase {
    func testTenModelsFiveOfThemTheSeaFloorsOwn() {
        XCTAssertEqual(CharacterModels.all.count, 10)
        XCTAssertEqual(CharacterModels.seaOnly.count, 5)
        XCTAssertEqual(Set(CharacterModels.all.map { $0.key }).count, 10)
        for i in 0..<200 { if let k = CharacterModels.landPick(UInt32(i) &* 2_654_435_761) { XCTAssertFalse(CharacterModels.of(k)!.sea, "villagers of the land never wear the sea's") } }
        for i in 0..<50 { XCTAssertTrue(CharacterModels.of(CharacterModels.resident(UInt32(i) &* 97, sea: true).look.model)!.sea) }
    }

    func testEveryModelIsDrawnIn2DAnd3DAndDiffersFromTheEverydayFigure() {
        var plain = Look(); plain.shirt = "#4a9a5a"
        let base = AnimeArt.character(plain, dir: "down", frame: 0, held: "", child: false, female: false)
        let base3 = Figure3D.human(plain, frame: 0, held: "", child: false, female: false)
        for m in CharacterModels.all {
            var l = plain; l.model = m.key
            for dir in ["down", "up", "side"] {
                let b = AnimeArt.character(l, dir: dir, frame: 1, held: "", child: false, female: true)
                XCTAssertEqual(b.w, base.w); XCTAssertEqual(b.h, base.h)
            }
            let b = AnimeArt.character(l, dir: "down", frame: 0, held: "", child: false, female: false)
            var diff = 0
            for y in 0..<b.h { for x in 0..<b.w where b.get(x, y) != base.get(x, y) { diff += 1 } }
            XCTAssertGreaterThan(diff, 200, "\(m.key) looks like itself")
            let px = PixelArt.character(l, dir: "down", frame: 0, held: "", child: true, female: false)
            XCTAssertEqual(px.w, PixelArt.charW)
            let mesh = Figure3D.human(l, frame: 2, held: "", child: false, female: false)
            XCTAssertFalse(mesh.positions.isEmpty)
            XCTAssertNotEqual(mesh.positions.count, base3.positions.count, "\(m.key) in 3D")
            XCTAssertGreaterThanOrEqual(mesh.positions.map { $0.y }.min() ?? -1, -0.01, "\(m.key) stands on the ground")
        }
    }

    func testTheMapsBelowShowTheUnderlandsAndTheirCities() {
        let s = makeSociety(11)
        let c = s.civ; c.underNations = true
        let n = c.newPolity(origin: "undersea", near: nil); c.polities[n]!.undersea = true
        var r = CivRegion(); r.rx = 1; r.ry = 1; r.land = 0; r.water = 1; c.regions[r.key] = r
        let city = c.newCity(at: r.key, nation: n, people: CivPeople(adults: 60), firstCount: true, sea: true)
        city.underAt = (12, 12); city.dug = 96
        c.polities[n]!.capital = city.id
        let map = WorldMap()
        map.layer = .seaFloor; map.political = true
        let (img, marks) = map.render(s, centre: TilePos(12 * 32, 12 * 32), reach: 10, zh: true)
        XCTAssertGreaterThan(img.w, 0)
        XCTAssertTrue(marks.contains { $0.kind == .capital && $0.name.hasPrefix(city.name(zh: true)) && $0.name.contains("人") }, "its city by name, with its people")
        XCTAssertTrue(marks.contains { $0.kind == .nation }, "its nation by name")
        map.layer = .underground
        XCTAssertFalse(map.render(s, centre: TilePos(12 * 32, 12 * 32), reach: 10, zh: true).1.contains { $0.kind == .capital }, "the underground map has only the underground's")
        // going there: its plaza below, and the people of the sea floor walk its roads
        let gate = s.cityGate(city.id)!
        XCTAssertTrue(gate.below)
        let at = s.teleportBelow(to: gate.tile)
        XCTAssertEqual(s.realm.player.depth, 1)
        XCTAssertFalse(s.underworld().blocked(at.tile.x, at.tile.y))
        let folk = s.underFolk(center: at, halfW: 600, halfH: 600)
        XCTAssertFalse(folk.isEmpty)
        XCTAssertTrue(folk.allSatisfy { CharacterModels.of($0.look.model)?.sea == true }, "the sea floor's own people")
    }

    func testHigherDetailCutsCurvesFiner() {
        defer { Figure3D.detail = 1 }
        var l = Look(); l.model = "knight"
        Figure3D.detail = 1
        let one = Figure3D.human(l, frame: 0, held: "sword", child: false, female: false).triangles
        Figure3D.detail = 2
        let two = Figure3D.human(l, frame: 0, held: "sword", child: false, female: false).triangles
        Figure3D.detail = 3
        let three = Figure3D.human(l, frame: 0, held: "sword", child: false, female: false).triangles
        XCTAssertGreaterThan(Double(two), Double(one) * 3, "high: about four times the faces")
        XCTAssertGreaterThan(Double(three), Double(two) * 1.8, "very high: more again")
        Figure3D.detail = 2
        let fish = Figure3D.animal(Species.all.first { $0.key == "whale" } ?? Species.all[0], frame: 0)
        XCTAssertFalse(fish.isEmpty)
        let car = Figure3D.vehicle(.carrier)
        XCTAssertFalse(car.isEmpty, "vehicles are built at the same detail")
    }
}
