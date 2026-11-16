import XCTest
@testable import MoonPixelCore

/// Content as data: the built-in pack is sound, a pack adds a works, a recipe and a variant of a
/// machine without touching the rules, and every kind of bad content is refused with its key and field.
final class RegistryTests: XCTestCase {
    override func tearDown() { ContentRegistry.shared = ContentRegistry.builtin() }

    func testTheBuiltInContentIsSound() {
        let r = ContentRegistry.builtin()
        XCTAssertEqual(r.validate(), [])
        XCTAssertEqual(ContentKey.canonical("moonpixel:frame"), "frame")
        XCTAssertEqual(ContentKey.full("frame"), "moonpixel:frame")
        XCTAssertEqual(ContentKey.canonical("example:barge"), "example:barge")
        // capabilities, not names: the carrier and the sky carrier share the hangar bay, differ in layer and power
        let carrier = r.unitsByKey["carrier"]!, sky = r.unitsByKey["sky_carrier"]!
        XCTAssertNotNil(carrier.hangarBay); XCTAssertNotNil(sky.hangarBay)
        XCTAssertNotNil(carrier.fuelTank); XCTAssertNil(carrier.power)
        XCTAssertNil(sky.fuelTank); XCTAssertNotNil(sky.power)
        XCTAssertNil(r.unitsByKey["infantry"]!.hangarBay, "only what a thing has is stored")
    }

    static let goodPack = """
    {
      "schemaVersion": 1, "namespace": "example",
      "foods": [{"key": "example:canned_fish", "en": "Canned fish", "zh": "鱼罐头", "nutrition": 1.6, "shelfDays": 700, "tech": "preserving"}],
      "facilities": [{"key": "example:cannery", "en": "Cannery", "zh": "罐头厂", "tech": "preserving", "cost": {"timber": 10, "stone": 10}, "workers": 4, "energy": 0}],
      "recipes": [{"key": "example:can_fish", "facility": "example:cannery", "inputs": {"fish": 4, "timber": 1}, "outputs": {"example:canned_fish": 3}, "hours": 4, "energy": 0, "tech": "preserving"}],
      "variants": [{"key": "example:great_carrier", "base": "moonpixel:carrier", "en": "Great carrier", "zh": "巨型航母",
                    "hangarBay": {"capacity": 20, "deckPerHour": 6}, "crewing": {"people": 600, "upkeep": 30},
                    "build": {"tech": ["carrier_ops"], "facility": "deep_yard", "stages": [{"steel": 300, "engine": 12}, {"armor": 40, "parts": 60}, {"electronics": 40, "weapons": 8}], "hours": 120}}]
    }
    """

    func testAPackAddsAWorksARecipeAndAVariantThatTheRulesUseAsTheyAre() throws {
        // the example pack shipped in the repository is the one tested
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../content/packs/example-cannery.json")
        let r = try ContentRegistry.builtin().adding(try Data(contentsOf: file))
        ContentRegistry.shared = r
        XCTAssertNotNil(CivFacility.byKey["example:cannery"]); XCTAssertNotNil(CivUnitDef.byKey["example:great_carrier"])
        XCTAssertEqual(CivUnitDef.byKey["example:great_carrier"]!.hangar, 20)
        XCTAssertEqual(CivUnitDef.byKey["example:great_carrier"]!.layer, .sea, "everything not changed comes from the base")
        // a city with a cannery and fish cans it; the cans are food people eat
        let c = Civ(seed: 1)
        var reg = CivRegion(); reg.land = 0.6; reg.water = 0.5; reg.deep = 0.5; reg.fertility = 0.6; c.regions[reg.key] = reg
        let n = c.newPolity(origin: "first", near: nil)
        c.polities[n]!.techs = CivTech.all.map { $0.key }; c.polities[n]!.ai = false; c.polities[n]!.builds = false
        let t = c.newCity(at: reg.key, nation: n, people: CivPeople(adults: 900, children: 200, elders: 100), firstCount: true)
        t.facilities = ["farm": 300, "house": 250, "well": 40, "example:cannery": 2, "fishery": 6, "deep_yard": 1, "aircraft_works": 1, "steelworks": 10, "factory": 10, "fab": 10, "mine": 10, "plant": 10]
        t.stock = ["grain": 50000, "timber": 2000, "stone": 2000, "steel": 2000, "engine": 40, "armor": 200, "parts": 400, "electronics": 400, "weapons": 40, "fuel": 2000, "ammo": 1000]
        c.totals.add(\.found, "grain", 50000)
        XCTAssertNotNil(c.order("example:great_carrier", nation: n, city: t.id))
        for _ in 0..<40 { c.advance(to: c.time + MP.daySeconds) }
        XCTAssertGreaterThan(t.ledger.made["example:canned_fish"] ?? 0, 0, "the new works made the new food")
        XCTAssertEqual(c.audit(), [])
        let held = c.foodHeld(), want = c.foodExpected()
        XCTAssertEqual(held["example:canned_fish"] ?? 0, want["example:canned_fish"] ?? 0, accuracy: 1e-6, "and it is in the books like any food")
        guard let ship = c.units.values.first(where: { $0.kind == "example:great_carrier" }), let fid = c.deploy(ship.id) else { return XCTFail("the variant was not built") }
        XCTAssertEqual(c.hangarRoom(c.forces[fid]!), 20, "its bigger hangar is the one the rules use")
    }

    func bad(_ json: String) -> [ContentIssue] {
        do { _ = try ContentRegistry.builtin().adding(Data(json.utf8)); return [] }
        catch let e as ContentError { return e.issues } catch { return [ContentIssue(kind: "?", key: "?", field: "?", problem: "\(error)")] }
    }
    func pack(_ body: String, version: Int = 1, ns: String = "example") -> String { "{\"schemaVersion\": \(version), \"namespace\": \"\(ns)\", \(body)}" }

    func testBadContentIsRefusedWithItsKeyAndField() {
        func expect(_ issues: [ContentIssue], _ key: String, _ field: String, file: StaticString = #file, line: UInt = #line) {
            XCTAssertTrue(issues.contains { ContentKey.full($0.key) == ContentKey.full(key) && $0.field.hasPrefix(field) }, "\(key).\(field) in \(issues)", file: file, line: line)
        }
        let fac = "{\"key\": \"example:works\", \"en\": \"W\", \"zh\": \"W\", \"cost\": {\"timber\": 1}, \"workers\": 1, \"energy\": 0}"
        expect(bad(pack("\"recipes\": [{\"key\": \"example:r\", \"facility\": \"example:nowhere\", \"inputs\": {\"grain\": 1}, \"outputs\": {\"bread\": 1}, \"hours\": 1, \"energy\": 0}]")), "example:r", "facility")
        expect(bad(pack("\"facilities\": [\(fac)], \"recipes\": [{\"key\": \"example:r\", \"facility\": \"example:works\", \"inputs\": {\"unobtainium\": 1}, \"outputs\": {\"bread\": 1}, \"hours\": 1, \"energy\": 0}]")), "example:r", "inputs")
        expect(bad(pack("\"facilities\": [\(fac)], \"recipes\": [{\"key\": \"example:r\", \"facility\": \"example:works\", \"inputs\": {\"grain\": -2}, \"outputs\": {\"bread\": 1}, \"hours\": 1, \"energy\": 0}]")), "example:r", "inputs")
        // grain -> bread -> grain, ending with more than it started: a free source
        expect(bad(pack("\"facilities\": [\(fac)], \"recipes\": [{\"key\": \"example:unbake\", \"facility\": \"example:works\", \"inputs\": {\"bread\": 1}, \"outputs\": {\"grain\": 2}, \"hours\": 1, \"energy\": 0}]")), "example:unbake", "outputs")
        expect(bad(pack("\"techs\": [{\"key\": \"example:a\", \"en\": \"A\", \"zh\": \"A\", \"branch\": \"x\", \"era\": 0, \"needs\": [\"example:b\"], \"cost\": 1, \"lab\": 0}, {\"key\": \"example:b\", \"en\": \"B\", \"zh\": \"B\", \"branch\": \"x\", \"era\": 0, \"needs\": [\"example:a\"], \"cost\": 1, \"lab\": 0}]")), "example:a", "needs")
        expect(bad(pack("\"facilities\": [\(fac), \(fac)]")), "example:works", "key")
        expect(bad(pack("\"variants\": [{\"key\": \"example:v\", \"base\": \"carrier\", \"hangarBay\": {\"capacity\": 0, \"deckPerHour\": 4}}]")), "example:v", "hangarBay")
        expect(bad(pack("\"variants\": [{\"key\": \"example:v\", \"base\": \"infantry\", \"weaponKeys\": [\"beam_rifle\"]}]")), "example:v", "power")
        expect(bad(pack("\"variants\": [{\"key\": \"example:v\", \"base\": \"frame\", \"art\": \"no-such-picture\"}]")), "example:v", "art")
        expect(bad(pack("\"variants\": [{\"key\": \"example:v\", \"base\": \"moonpixel:nothing\"}]")), "example:v", "base")
        expect(bad(pack("\"facilities\": [{\"key\": \"stolen\", \"en\": \"W\", \"zh\": \"W\", \"cost\": {}, \"workers\": 1, \"energy\": 0}]")), "stolen", "key")
        expect(bad(pack("\"foods\": []", version: 9)), "example", "schemaVersion")
        expect(bad(pack("\"foods\": []", ns: "moonpixel")), "moonpixel", "namespace")
        XCTAssertEqual(ContentRegistry.shared.validate(), [], "a refused pack changes nothing")
        XCTAssertNil(CivFacility.byKey["example:works"])
    }
}
