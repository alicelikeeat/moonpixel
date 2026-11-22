import XCTest
@testable import MoonPixelCore

/// Everyone of the same shape shares one model; each person brings a strip of their own colours, and the
/// shared model in a person's strip looks exactly like the person's own model.
final class SwatchTests: XCTestCase {
    static func randomLooks(_ n: Int, seed: Int = 3) -> [Look] {
        var r = RNG(seed: seed)
        func hex() -> String { String(format: "#%02x%02x%02x", r.index(256), r.index(256), r.index(256)) }
        return (0..<n).map { i in
            var l = Look(); l.skin = Society.skins[r.index(Society.skins.count)]; l.hair = hex(); l.shirt = hex(); l.pants = hex(); l.shoes = hex(); l.style = r.index(12)
            if i % 7 == 0 { l.hair = "#e0e0e8" }
            return l
        }
    }

    /// The colour each vertex shows: in the palette for a model of one's own, in the strip for a shared one.
    func shown(_ m: Mesh3D) -> [RGBA] { m.uvs.map { Palette3D.color(at: $0) } }
    func shown(_ m: Mesh3D, strip: Bitmap) -> [RGBA] {
        m.uvs.map { uv in
            let c = strip.get(Int(uv.x * Float(strip.w)), Int(uv.y * Float(strip.h)))
            return Palette3D.color(at: Palette3D.uv(c))           // through the same palette quantisation
        }
    }

    func testASharedModelInAPersonsColoursIsThePersonsOwnModel() {
        let rigs = AnimeRigs()
        var shared = 0, total = 0
        for (i, l) in SwatchTests.randomLooks(60).enumerated() {
            for kind in AnimeArt.Figure.allCases {
                let female = i % 2 == 0, child = i % 5 == 0, lite = i % 3 != 0
                let frame = i % 4, held = ["", "sword", "hammer", "cane"][i % 4]
                total += 1
                guard let sh = rigs.shape(l, frame: frame, held: held, child: child, female: female, kind: kind, lite: lite, ink: 0.025),
                      let mesh = sh.mesh,
                      let sw = rigs.swatches(l, child: child, female: female, kind: kind, lite: lite) else { continue }
                shared += 1
                let own = Figure3D.anime(l, frame: frame, held: held, child: child, female: female, kind: kind, lite: lite).inked(width: 0.025)
                XCTAssertEqual(mesh.positions, own.positions, "the same shape")
                XCTAssertEqual(mesh.indices, own.indices)
                let a = shown(own), b = shown(mesh, strip: SwatchBook.strip(sw.colors))
                let wrong = zip(a, b).filter { $0 != $1 }.count
                XCTAssertEqual(wrong, 0, "look \(i) \(kind) frame \(frame) \(held): \(wrong) of \(a.count) vertices in another colour")
            }
        }
        XCTAssertGreaterThan(shared, total * 97 / 100, "nearly everyone shares: \(shared) of \(total)")
    }

    func testACrowdNeedsFewModels() {
        let rigs = AnimeRigs()
        var keys = Set<String>()
        for (i, l) in SwatchTests.randomLooks(200).enumerated() {
            for frame in 0..<3 {
                if let k = rigs.shape(l, frame: frame, held: "", child: i % 6 == 0, female: i % 2 == 0, kind: .moe, lite: true, ink: nil, build: false)?.key { keys.insert(k) }
            }
        }
        XCTAssertLessThan(keys.count, 200, "two hundred people in three steps: \(keys.count) models, not 600")
        // a character model draws with its own
        var k = Look(); k.model = CharacterModels.all.first?.key
        XCTAssertNil(rigs.shape(k, frame: 0, held: "", child: false, female: false, kind: .moe, lite: true, ink: nil))
    }
}
