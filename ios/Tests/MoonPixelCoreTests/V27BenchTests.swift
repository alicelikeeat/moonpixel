import XCTest
import Foundation
@testable import MoonPixelCore

/// Costs of the v2.7 transport paths, on whatever machine runs it (MP_BENCH=1). Not a phone measurement.
final class V27BenchTests: XCTestCase {
    func ms(_ f: () -> Void) -> Double { let t = DispatchTime.now().uptimeNanoseconds; f(); return Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6 }

    func testBench() throws {
        guard ProcessInfo.processInfo.environment["MP_BENCH"] != nil else { throw XCTSkip("set MP_BENCH") }
        var out: [String] = []
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        // routing: across the forest and the river (150 tiles), and planning a way with a bridge
        var route: [NetNode]?
        let r = ms { route = s.route(from: NetNode(sc.t(4, 60).x, sc.t(4, 60).y, 0), to: NetNode(sc.t(160, 60).x, sc.t(160, 60).y, 0), Profile(mode: .road)) }
        out.append(String(format: "BENCH27 car route 156 tiles over a bridge: %.2f ms (%d nodes)", r, route?.count ?? 0))
        let p = ms { _ = s.planWay(.rail, from: sc.t(4, 90), to: sc.t(160, 90)) }
        out.append(String(format: "BENCH27 plan a railway 156 tiles (forest, river): %.2f ms", p))
        // 200 vehicles running far from the traveller (moved along their ways), and 20 near (physics)
        s.realm.player.body = Body(at: sc.t(15, 700).center, z: 0, depth: 0)          // out of physics range of all of them
        let a = s.addStop(.busStop, at: sc.t(6, 60), name: "W", nation: 1, district: sc.a.id)!
        let b = s.addStop(.busStop, at: sc.t(160, 60), name: "E", nation: 1, district: sc.b.id)!
        let line = s.addLine(.bus, stops: [a.id, b.id], name: "L", headway: 30, nation: 1, payer: .district(sc.a.id))!
        sc.a.store["iron"] = 1e6; sc.a.store["parts"] = 1e6; sc.a.store["fuel"] = 1e7
        for k in 0..<200 { if let v = s.buildVehicle(.bus, at: sc.t(6 + (k % 28), 60), payer: .district(sc.a.id), nation: 1) { s.assign(v, to: line) } }
        let farSteps = 600
        let far = ms { for _ in 0..<farSteps { s.transportTick(1.0 / 30); s.world.time += 1.0 / 30 } }
        out.append(String(format: "BENCH27 %d buses, all far: %.3f ms per 1/30 s step", s.net.vehicles.count, far / Double(farSteps)))
        s.realm.player.body = Body(at: sc.t(60, 60).center, z: 0, depth: 0)
        let near = s.net.vehicles.filter { $0.pos.distance(to: s.realm.player.body!.pos) <= 96 * 16 }.count
        let nearT = ms { for _ in 0..<300 { s.transportTick(1.0 / 30); s.world.time += 1.0 / 30 } }
        out.append(String(format: "BENCH27 same, %d of them near (physics at 60 Hz): %.3f ms per 1/30 s step", near, nearT / 300))
        // a trip plan over a network of 30 stops
        for k in 0..<28 { _ = s.addStop(.busStop, at: sc.t(8 + k * 5, 60), name: "S\(k)", nation: 1) }
        let tp = ms { for _ in 0..<20 { _ = s.planTrip(from: sc.t(5, 62), to: sc.t(158, 62), nation: 1) } }
        out.append(String(format: "BENCH27 trip plan over %d stops: %.3f ms", s.net.stops.count, tp / 20))
        // a day of an imported metro district
        let m = Metro(seed: 1, worldSeed: 7); m.layOutDemo(); for _ in 0..<240 { m.step() }
        let s2 = makeSociety(7, villages: 2, per: 10)
        let imp = ms { _ = s2.importMetro(m, nation: 1) }
        let d = s2.net.districts[0]
        let day = ms { for _ in 0..<10 { s2.districtDay(d) } }
        out.append(String(format: "BENCH27 metro import (%d people, %d buildings): %.2f ms; a district day: %.3f ms", d.population, d.buildings.count, imp, day / 10))
        let data = try JSONEncoder().encode(s.snapshot())
        let enc = ms { _ = try? JSONEncoder().encode(s.snapshot()) }
        out.append(String(format: "BENCH27 save of the society with %d vehicles: %.1f ms, %d KB", s.net.vehicles.count, enc, data.count / 1024))
        for l in out { print(l) }
    }
}
