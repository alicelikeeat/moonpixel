import XCTest
@testable import MoonPixelCore

/// The ten landforms are made where the seed puts them, and a nation there is read as standing on them.
final class LandformTests: XCTestCase {
    /// Landforms of an ocean world, by kind, over a wide square of cells.
    func catalogue(_ gen: Generator, cells: Int = 7) -> [CivGeoTrait.Kind: Landform] {
        var out: [CivGeoTrait.Kind: Landform] = [:]
        let C = Generator.landformCell
        for j in -cells...cells { for i in -cells...cells {
            if let f = gen.landform(near: (Double(i) + 0.5) * C, (Double(j) + 0.5) * C), out[f.kind] == nil { out[f.kind] = f }
        } }
        return out
    }

    /// A point in a landform's own frame (u along, v across, in radii) as world tiles.
    func at(_ f: Landform, _ u: Double, _ v: Double) -> (Int, Int) {
        let ca = cos(f.angle), sa = sin(f.angle)
        return (Int(f.x + (u * ca - v * sa) * f.radius), Int(f.y + (u * sa + v * ca) * f.radius))
    }
    func elev(_ g: Generator, _ p: (Int, Int)) -> Double { g.climate(p.0, p.1).0 }

    func testEveryKindIsMadeAndHasItsShape() {
        let gen = Generator(seed: 21); gen.oceans = true
        let all = catalogue(gen)
        XCTAssertEqual(Set(all.keys), Set(CivGeoTrait.Kind.allCases), "all ten kinds somewhere in the world")
        let sea = Biome.sea, mount = Biome.mountainLevel
        if let f = all[.strait] {
            XCTAssertGreaterThan(elev(gen, at(f, 0, 0)), sea, "the neck is land")
            XCTAssertLessThan(elev(gen, at(f, 0, 0.6)), sea, "a sea on one side")
            XCTAssertLessThan(elev(gen, at(f, 0, -0.6)), sea, "and on the other")
        }
        if let f = all[.basin] {
            XCTAssertGreaterThan(elev(gen, at(f, 0, 0)), sea, "a bowl of land")
            XCTAssertGreaterThan(elev(gen, at(f, 0, 0.66)), mount, "ringed by mountains")
            XCTAssertLessThan(elev(gen, at(f, 0.66, 0)), mount, "with a valley through them")
            XCTAssertLessThan(elev(gen, at(f, 1.08, 0)), sea, "the first valley runs to the sea")
        }
        if let f = all[.islands] {
            XCTAssertGreaterThan(elev(gen, at(f, 0, 0)), sea, "an island")
            XCTAssertLessThan(elev(gen, at(f, 0.3, 0)), sea, "open water to the next")
            XCTAssertGreaterThan(elev(gen, at(f, 0.6, 0)), sea, "the next island")
        }
        if let f = all[.innerSea] {
            XCTAssertLessThan(elev(gen, at(f, 0, 0)), sea, "an inner sea")
            XCTAssertGreaterThan(elev(gen, at(f, 0, 0.7)), sea, "inside a ring of land")
            XCTAssertLessThan(elev(gen, at(f, 0.7, 0)), sea, "with one narrow mouth")
        }
        if let f = all[.atoll] {
            XCTAssertLessThan(elev(gen, at(f, 0, 0)), sea, "a lagoon")
            XCTAssertGreaterThan(elev(gen, at(f, -0.7, 0)), sea, "a reef of land round it")
        }
        if let f = all[.blackSoil] {
            XCTAssertGreaterThan(elev(gen, at(f, -0.8, 0)), mount, "mountains behind")
            XCTAssertLessThan(elev(gen, at(f, 0.9, 0)), sea, "the sea in front")
        }
        if let f = all[.terraces] {
            XCTAssertGreaterThan(elev(gen, at(f, -0.6, 0)), elev(gen, at(f, 0, 0)), "steps down")
            XCTAssertGreaterThan(elev(gen, at(f, 0, 0)), elev(gen, at(f, 0.5, 0)))
        }
        if let f = all[.longBay] {
            XCTAssertGreaterThan(elev(gen, at(f, 0, 0)), sea, "a long peninsula")
            XCTAssertLessThan(elev(gen, at(f, 0, 0.3)), sea, "deep water either side")
            XCTAssertLessThan(elev(gen, at(f, 0, -0.3)), sea)
        }
    }

    func testTheStartAndOldWorldsAreUntouched() {
        let a = Generator(seed: 21), b = Generator(seed: 21); b.oceans = true
        XCTAssertNil(b.landformShape(0, 0), "nothing is stamped round the start")
        for (x, y) in [(0, 0), (150, 150), (-200, 90)] { XCTAssertEqual(a.climate(x, y).0, b.climate(x, y).0) }
        XCTAssertNil(a.landform(near: 30000, 30000), "a world without oceans has no landforms")
    }

    func testANationOnALandformIsReadAsStandingOnIt() {
        let gen = Generator(seed: 21); gen.oceans = true
        var read: [String] = []
        for (kind, f) in catalogue(gen) {
            let c = Civ(seed: 21)
            let rc = c.cfg.regionTiles
            let (crx, cry) = (Int((f.x / Double(rc)).rounded(.down)), Int((f.y / Double(rc)).rounded(.down)))
            for ry in (cry - 8)...(cry + 8) { for rx in (crx - 8)...(crx + 8) { let r = Civ.survey(gen, rx, ry, size: rc); c.regions[r.key] = r } }
            c.cfg.claimRadius = 4
            // a nation whose capital is on the landform's best land
            let land = c.regions.values.filter { $0.form == kind.rawValue && c.isLand($0) }.sorted { abs($0.rx - crx) + abs($0.ry - cry) < abs($1.rx - crx) + abs($1.ry - cry) }
            guard let home = land.first else { continue }
            let n = c.newPolity(origin: "first", near: nil)
            let city = c.newCity(at: home.key, nation: n, people: CivPeople(adults: 50), firstCount: true)
            c.polities[n]!.capital = city.id
            c.refreshTerritory()
            if c.traits(of: n).contains(where: { $0.kind == kind }) { read.append(kind.rawValue) }
        }
        print("LANDFORM read as themselves: \(read.sorted())")
        XCTAssertEqual(read.count, 10, "every kind are recognised from the land as it is: \(read.sorted())")
    }
}
