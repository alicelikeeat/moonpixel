import XCTest
@testable import MoonPixelBridge
import MoonPixelCore

/// The C library: a world made, run and read through the handles, as the PC front end does it.
final class BridgeTests: XCTestCase {
    func testTheCLayoutOfAPerson() {
        XCTAssertEqual(MemoryLayout<MPPerson>.size, 88, "as moonpixel.h lays it out")
        XCTAssertEqual(MemoryLayout<MPPerson>.offset(of: \MPPerson.flags), 20)
        XCTAssertEqual(MemoryLayout<MPPerson>.offset(of: \MPPerson.style), 44)
        XCTAssertEqual(MemoryLayout<MPPerson>.offset(of: \MPPerson.model), 48)
        XCTAssertEqual(MemoryLayout<MPPerson>.offset(of: \MPPerson.held), 72)
    }

    func testAWorldThroughTheCLibrary() {
        XCTAssertEqual(String(cString: mp_version()), "3.4.0")
        let w = mp_world_create(7, 2, 12)
        XCTAssertNotNil(w)
        defer { mp_world_destroy(w) }
        XCTAssertGreaterThan(mp_world_population(w), 10)
        let t0 = mp_world_time(w)
        mp_world_tick(w, 3)
        XCTAssertEqual(mp_world_time(w) - t0, 3, accuracy: 0.01)
        // the people round the first village
        var people = [MPPerson](repeating: MPPerson(), count: 64)
        let n = people.withUnsafeMutableBytes { mp_people_near(w, 0, 0, 200, 200, $0.baseAddress, 64) }
        XCTAssertGreaterThan(n, 5)
        let p = people[0]
        XCTAssertNotEqual(p.skin, 0)
        // a chunk's model and its ground picture
        let m = mp_chunk_mesh(w, 0, 0, 0)
        XCTAssertNotNil(m)
        var vc: Int32 = 0, ic: Int32 = 0
        mp_mesh_counts(m, &vc, &ic)
        XCTAssertGreaterThan(vc, 100); XCTAssertEqual(ic % 3, 0)
        var pos = [Float](repeating: 0, count: Int(vc) * 3), nor = pos, uv = [Float](repeating: 0, count: Int(vc) * 2)
        var idx = [UInt32](repeating: 0, count: Int(ic))
        mp_mesh_copy(m, &pos, &nor, &uv, &idx)
        XCTAssertLessThan(idx.max()!, UInt32(vc))
        XCTAssertTrue(uv.allSatisfy { $0 >= 0 && $0 <= 1 })
        mp_mesh_free(m)
        let side = mp_chunk_ground_rgba(w, 0, 0, nil, 0)
        XCTAssertEqual(side, 1024, "the anime ground: 32 pixels a tile")
        // a person's model as glTF
        let size = withUnsafeBytes(of: &people[0]) { mp_person_glb($0.baseAddress, nil, 0) }
        if read(p.model).isEmpty {
            XCTAssertGreaterThan(size, 10_000)
            var glb = [UInt8](repeating: 0, count: Int(size))
            _ = withUnsafeBytes(of: &people[0]) { mp_person_glb($0.baseAddress, &glb, size) }
            XCTAssertEqual(Array(glb[0..<4]), Array("glTF".utf8))
        }
        // a person posed in a clip, coloured; the ground under them
        let pm = withUnsafeBytes(of: &people[0]) { mp_person_mesh($0.baseAddress, "walk", 0.25, 1) }
        XCTAssertNotNil(pm, "every person can be drawn (a character model not rigged yet as the everyday figure)")
        var pv: Int32 = 0, pi: Int32 = 0
        mp_mesh_counts(pm, &pv, &pi)
        var cols = [UInt8](repeating: 0, count: Int(pv) * 4)
        mp_mesh_colors(pm, &cols)
        XCTAssertGreaterThan(Set(stride(from: 0, to: cols.count, by: 4).map { Int(cols[$0]) << 16 | Int(cols[$0 + 1]) << 8 | Int(cols[$0 + 2]) }).count, 8, "in many colours")
        mp_mesh_free(pm)
        let gy = mp_ground_y(w, p.x, p.z)
        XCTAssertTrue(gy.isFinite)
        let pal = mp_palette_rgba(nil, 0)
        XCTAssertEqual(pal >> 16, 1024); XCTAssertEqual(pal & 0xFFFF, 64)
    }
}
