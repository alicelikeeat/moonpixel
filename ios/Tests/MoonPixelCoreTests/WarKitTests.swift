import XCTest
@testable import MoonPixelCore

/// Armies take to war the machines of their age, and each is drawn where it is in the column.
final class WarKitTests: XCTestCase {
    func testTheKitFollowsTheAge() {
        XCTAssertTrue(WarKit.kit(era: 1, members: 40).isEmpty, "before industry: swords, bows, horse and siege engines")
        let ind = Set(WarKit.kit(era: 2, members: 40).map { $0.kind })
        XCTAssertEqual(ind, ["apc", "humvee"])
        let modern = Dictionary(uniqueKeysWithValues: WarKit.kit(era: 3, members: 40).map { ($0.kind, $0.count) })
        for k in ["tank", "humvee", "apc", "rocket", "fighter"] { XCTAssertGreaterThan(modern[k] ?? 0, 0, k) }
        XCTAssertNil(modern["drone"])
        let ai = Dictionary(uniqueKeysWithValues: WarKit.kit(era: 5, members: 40).map { ($0.kind, $0.count) })
        XCTAssertEqual(Set(ai.keys), Set(WarKit.order))
        XCTAssertGreaterThan(ai["drone"]!, 3)
        XCTAssertGreaterThan(WarKit.kit(era: 3, members: 80).first { $0.kind == "tank" }!.count, modern["tank"]!, "a bigger army, more tanks")
    }

    func testTheColumnMarchesTanksInFrontRocketsBehindAircraftAbove() {
        let s = makeSociety(41)
        let lg = Legion()
        lg.id = 77; lg.nation = 9999; lg.state = 1; lg.members = Array(1...40); lg.pos = Vec2(5000, 5000)
        lg.route = [Vec2(5000, 9000)]; lg.routeI = 0                     // marching south (+y)
        s.realm.legions.append(lg)
        let ms = s.warMachines(center: lg.pos, reach: 2000)
        let kinds = Set(ms.map { $0.kind })
        for k in ["tank", "humvee", "apc", "rocket", "fighter"] { XCTAssertTrue(kinds.contains(k), k) }
        let tanks = ms.filter { $0.kind == "tank" }, rockets = ms.filter { $0.kind == "rocket" }
        XCTAssertTrue(tanks.allSatisfy { $0.pos.y > lg.pos.y }, "tanks lead")
        XCTAssertTrue(rockets.allSatisfy { $0.pos.y < lg.pos.y }, "rockets at the back")
        XCTAssertTrue(ms.filter { $0.kind == "fighter" }.allSatisfy { $0.z > 20 }, "fighters high above")
        XCTAssertEqual(Set(ms.map { $0.id }).count, ms.count, "each machine once")
        let info = s.legionInfos().first { $0.id == 77 }
        XCTAssertEqual(info?.kit.count, 5, "the war panel lists the kit")
        // a garrison stays at home with its machines put away
        lg.state = 0
        XCTAssertTrue(s.warMachines(center: lg.pos, reach: 2000).isEmpty)
    }

    func testEveryMachineIsModelledAndDrawnFromAbove() {
        for k in WarKit.order {
            let m = Figure3D.warMachine(k, color: "#c03030")
            XCTAssertFalse(m.isEmpty, k)
            let len = (m.positions.map { $0.x }.max() ?? 0) - (m.positions.map { $0.x }.min() ?? 0)
            XCTAssertGreaterThan(len, 1, "\(k) has a length")
            let top = AnimeArt.warMachineTop(k, color: "#c03030")
            XCTAssertGreaterThan(top.w, top.h / 2, k)
        }
        // life-sized: a tank (8 m) is about four tiles long, a Humvee (4.6 m) a little over two
        let tank = Figure3D.warMachine("tank", color: "#fff"), hum = Figure3D.warMachine("humvee", color: "#fff")
        let tl = (tank.positions.map { $0.x }.max()! - tank.positions.map { $0.x }.min()!), hl = (hum.positions.map { $0.x }.max()! - hum.positions.map { $0.x }.min()!)
        XCTAssertEqual(Double(hl), 2.3, accuracy: 0.3)
        XCTAssertGreaterThan(tl, 4.0, "the gun reaches out beyond the hull")
    }
}
