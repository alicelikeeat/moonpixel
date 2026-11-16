import XCTest
@testable import MoonPixelCore

/// The pressure matrix: many nations, many people, many machines. Prints the cost of a simulated day;
/// asserts only that the books stay right. Numbers are for the machine the tests run on, not a phone.
final class CivStressTests: XCTestCase {
    func world(nations: Int, people: Int) -> Civ {
        let c = Civ(seed: 1)
        let side = Int(Double(nations * 4).squareRoot().rounded(.up)) + 2
        for y in 0..<side { for x in 0..<side {
            var r = CivRegion(); r.rx = x; r.ry = y; r.land = 1; r.fertility = 0.6; r.forest = 0.5; r.ore = 0.4; r.coal = 0.4; r.river = true
            c.regions[r.key] = r
        } }
        let perCity = max(40, people / (nations * 4))
        var k = 0
        for _ in 0..<nations {
            let n = c.newPolity(origin: "first", near: nil)
            c.polities[n]!.techs = CivTech.all.map { $0.key }
            for _ in 0..<4 {
                let x = k % side, y = k / side; k += 1
                let city = c.newCity(at: MP.chunkKey(x, y), nation: n, people: CivPeople(adults: perCity * 6 / 10, children: perCity * 3 / 10, elders: perCity / 10), firstCount: true)
                city.facilities = ["farm": perCity / 4, "house": perCity / 5, "well": perCity / 30 + 1, "granary": 1, "clinic": perCity / 150 + 1, "school": 1]
                city.stock = ["grain": Double(perCity) * 40, "timber": 500, "stone": 500]
                c.totals.add(\.found, "grain", Double(perCity) * 40)
                city.cropDue = 3; city.cropPlots = perCity / 4
            }
        }
        return c
    }

    func army(_ c: Civ, units n: Int) {
        let ids = c.activePolities().map { $0.id }
        let kinds = ["infantry", "armour", "artillery", "air_defence", "frame", "fighter", "carrier", "sky_carrier", "escort", "drone"]
        for i in 0..<n {
            let nation = ids[i % 2]
            let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = nation; f.region = MP.chunkKey(1 + i % 2, 1)
            var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = kinds[i % kinds.count]; u.nation = nation; u.force = f.id
            u.hp = u.def.hp; u.ammo = u.def.ammoCap; u.fuel = u.def.fuelCap; u.energy = u.def.energyPerDay * 2
            for p in u.def.parts { u.parts[p] = 1 }
            if u.def.carrierBased && u.def.hangar == 0 { u.air = .airborne; u.at = f.region; u.target = MP.chunkKey(1 + (i + 1) % 2, 1); u.aloft = 8 }
            f.layer = u.def.layer == .lowAir || u.def.layer == .highAir ? .highAir : u.def.layer
            c.units[u.id] = u; f.units = [u.id]; f.crew = CivPeople(adults: u.def.crew); c.totals.newly += u.def.crew
            f.food = ["ration": 500]; c.totals.add(\.found, "ration", 500)
            c.forces[f.id] = f
        }
        c.polities[ids[0]]!.techs.append("radio"); c.polities[ids[1]]!.techs.append("radio")
        c.declare(ids[0], on: ids[1])
    }

    func testThePressureMatrix() {
        var lines: [String] = []
        for (nations, people) in [(10, 10_000), (50, 100_000), (100, 1_000_000)] {
            let c = world(nations: nations, people: people)
            let t0 = Date()
            c.advance(to: 10 * MP.daySeconds)
            let perDay = Date().timeIntervalSince(t0) / 10 * 1000
            XCTAssertEqual(c.audit(), [])
            let e0 = Date(); let data = try! JSONEncoder().encode(c); let save = Date().timeIntervalSince(e0) * 1000
            lines.append(String(format: "%3d nations, %8d people (%d cities): %.1f ms per day, save %.0f ms, %.1f MB", nations, c.people, c.cities.count, perDay, save, Double(data.count) / 1_048_576))
        }
        for n in [50, 200, 400] {
            let c = world(nations: 10, people: 10_000)
            army(c, units: n)
            let t0 = Date()
            for _ in 0..<48 { c.advance(to: c.time + MP.daySeconds / 24) }
            let perHour = Date().timeIntervalSince(t0) / 48 * 1000
            XCTAssertEqual(c.audit(), [])
            let kinds = Set(c.fights.map { $0.kind })
            lines.append(String(format: "%3d machines in one battle (frames, carriers, aircraft, sky carriers): %.2f ms per hour; events %@", n, perHour, kinds.sorted().joined(separator: ",")))
        }
        print("STRESS\n" + lines.joined(separator: "\n"))
    }
}
