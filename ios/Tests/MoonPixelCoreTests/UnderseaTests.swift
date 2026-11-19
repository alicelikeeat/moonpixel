import XCTest
@testable import MoonPixelCore

/// The nations of the sea floor: their cities look like the sea's, and they refuse war.
final class UnderseaTests: XCTestCase {
    func firstSeaCity(_ gen: Generator) -> (Int, Int)? {
        for r in 1...40 { for cy in -r...r { for cx in -r...r where max(abs(cx), abs(cy)) == r && gen.isSeaCity(cx * 4, cy * 4) { return (cx * 4, cy * 4) } } }
        for cy in -160...160 { for cx in -160...160 where gen.isSeaCity(cx, cy) { return (cx, cy) } }
        return nil
    }

    func testASeaCityIsBuiltOfCoralPearlAndKelpOnTheSeaFloor() {
        let gen = Generator(seed: 11); gen.oceans = true
        guard let (cx, cy) = firstSeaCity(gen) else { return XCTFail("no sea city in reach") }
        XCTAssertFalse(Generator(seed: 11).isSeaCity(cx, cy), "old worlds have none")
        let ch = gen.generate(cx, cy)
        let c = Content.shared
        func count(_ layer: Int, _ key: String) -> Int { ch.layers[layer].filter { $0 == c.tid(key) }.count }
        XCTAssertGreaterThan(count(0, "seabed"), 400, "a seabed plaza")
        XCTAssertGreaterThan(count(2, "coral_wall"), 60, "coral walls and coral houses")
        XCTAssertGreaterThan(count(2, "pearl_dome"), 10, "a pearl dome at its heart")
        XCTAssertGreaterThan(count(3, "kelp"), 8, "kelp gardens")
        XCTAssertGreaterThan(count(2, "pearl_lamp"), 6, "pearl lamps")
        XCTAssertTrue(c.water[Int(c.tid("seabed"))], "the plaza is under water: its people breathe it")
    }

    func testSeaNationsAreFoundAndRefuseWar() {
        let gen = Generator(seed: 11); gen.oceans = true
        guard let (cx, cy) = firstSeaCity(gen) else { return XCTFail("no sea city in reach") }
        let c = Civ(seed: 11); c.underNations = true
        c.discover(around: TilePos(cx * 32 + 16, cy * 32 + 16), radius: 1, gen: gen)
        guard let city = c.seaCities().first else { return XCTFail("no sea nation") }
        let n = city.nation
        XCTAssertEqual(c.polities[n]?.undersea, true)
        XCTAssertEqual(c.regions[city.regionKey]?.seaCity, city.id)
        XCTAssertNotEqual(c.regions[city.regionKey]?.city, city.id)
        let other = c.newPolity(origin: "first", near: nil)
        c.declare(other, on: n); c.declare(n, on: other)
        XCTAssertFalse(c.atWar(other, n), "no war can be declared on them, nor by them")
        XCTAssertEqual(c.envoyBlocked(other, n), "refuses_war")
        let pop0 = city.pop
        c.advance(to: c.time + 30 * MP.daySeconds)
        XCTAssertGreaterThan(city.pop, 0, "they live on")
        XCTAssertEqual(c.audit(), [])
        _ = pop0
    }
}
