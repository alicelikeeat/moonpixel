import XCTest
import Foundation
@testable import MoonPixelCore

/// Writes the anime pictures beside the pixel ones as raw RGBA files when MP_PREVIEW is set (a directory).
final class AnimePreviewTests: XCTestCase {
    func write(_ b: Bitmap, _ name: String, _ dir: String) {
        var d = Data("\(b.w) \(b.h)\n".utf8); d.append(contentsOf: b.px)
        try? d.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".rgba"))
    }
    func testPreview() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        var looks: [Look] = []
        for (i, (skin, hair, shirt, pants)) in [("#f2c8a4", "#5a3a22", "#5a8ae8", "#4a4a5a"), ("#ffe0c8", "#f0a0c0", "#ffffff", "#e05a7a"), ("#e8b890", "#202838", "#d84a4a", "#30304a"), ("#f8d8c0", "#f0d060", "#60c080", "#5a4a3a")].enumerated() {
            var l = Look(); l.skin = skin; l.hair = hair; l.shirt = shirt; l.pants = pants; l.style = i; looks.append(l)
        }
        // a sheet: rows = looks (female, male alternating), columns = down, side, up, walk, act; pixel above anime
        let cw = AnimeArt.charW, ch = AnimeArt.charH
        var sheet = Bitmap(cw * 5 * 2 + 20, ch * 4 + 10, fill: RGBA(200, 220, 235))
        for (r, l) in looks.enumerated() {
            let female = r % 2 == 1
            let poses: [(String, Int)] = [("down", 0), ("side", 0), ("up", 0), ("down", 1), ("side", 3)]
            for (k, p) in poses.enumerated() {
                let a = AnimeArt.character(l, dir: p.0, frame: p.1, held: k == 4 ? "sword" : "", child: false, female: female)
                sheet.blit(a, sx: 0, sy: 0, sw: a.w, sh: a.h, dx: k * cw, dy: r * ch, blend: true)
                let px = PixelArt.character(l, dir: p.0, frame: p.1, held: k == 4 ? "sword" : "", child: false, female: female).scaled(to: cw, ch)
                sheet.blit(px, sx: 0, sy: 0, sw: px.w, sh: px.h, dx: cw * 5 + 20 + k * cw, dy: r * ch, blend: true)
            }
        }
        write(sheet, "characters", dir)
        write(AnimeArt.atlas, "atlas-anime", dir)
        write(PixelArt.atlas, "atlas-pixel", dir)
        let s = makeSociety(7)
        let c = s.settlements[1]!.center
        let ch0 = s.world.chunk(c.x >> 5, c.y >> 5)
        write(AnimeArt.bakeChunk(layers: ch0.layers), "chunk-anime", dir)
        write(PixelArt.bakeChunk(layers: ch0.layers), "chunk-pixel", dir)
        let t0 = Date()
        _ = AnimeArt.bakeChunk(layers: ch0.layers)
        print("PREVIEW chunk bake ms", Date().timeIntervalSince(t0) * 1000)
        let t1 = Date()
        for _ in 0..<20 { _ = AnimeArt.character(looks[1], dir: "down", frame: 1, held: "", child: false, female: true) }
        print("PREVIEW character ms", Date().timeIntervalSince(t1) * 1000 / 20)
    }
}

/// The anime look is drawn in code: sizes the renderers rely on, every pose drawn, ground without holes, and the same picture every time.
final class AnimeArtTests: XCTestCase {
    func testCharactersAreDrawnInEveryPoseAtTwiceThePixels() {
        var l = Look(); l.hair = "#f0a0c0"
        for dir in ["down", "side", "up"] { for f in 0...3 { for female in [false, true] {
            let a = AnimeArt.character(l, dir: dir, frame: f, held: f == 3 ? "sword" : "", child: false, female: female)
            XCTAssertEqual(a.w, AnimeArt.charW); XCTAssertEqual(a.h, AnimeArt.charH)
            let p = PixelArt.character(l, dir: dir, frame: f, held: "", child: false, female: female)
            XCTAssertEqual(a.w, p.w * 2); XCTAssertEqual(a.h, p.h * 2)
            let opaque = stride(from: 3, to: a.px.count, by: 4).filter { a.px[$0] > 200 }.count
            XCTAssertGreaterThan(opaque, a.w * a.h / 8, "\(dir) \(f) drawn")
        } } }
        let c = AnimeArt.character(l, dir: "down", frame: 0, held: "", child: true, female: true)
        XCTAssertEqual(c.w, AnimeArt.charW)
        // drawn, not converted: deterministic, and different from the scaled pixel sprite
        let a1 = AnimeArt.character(l, dir: "down", frame: 1, held: "", child: false, female: true)
        let a2 = AnimeArt.character(l, dir: "down", frame: 1, held: "", child: false, female: true)
        XCTAssertEqual(a1.px, a2.px)
        XCTAssertNotEqual(a1.px, PixelArt.character(l, dir: "down", frame: 1, held: "", child: false, female: true).anime().px)
    }

    func testGroundIsSolidAndTwiceThePixelSize() {
        let s = makeSociety(7)
        let c = s.settlements[1]!.center
        let ch = s.world.chunk(c.x >> 5, c.y >> 5)
        let a = AnimeArt.bakeChunk(layers: ch.layers), p = PixelArt.bakeChunk(layers: ch.layers)
        XCTAssertEqual(a.w, p.w * 2); XCTAssertEqual(a.h, p.h * 2)
        let g = AnimeArt.bakeGround(layers: ch.layers)
        XCTAssertEqual(g.w, 1024)
        // the ground has no see-through pixels
        XCTAssertFalse(stride(from: 3, to: g.px.count, by: 4).contains { g.px[$0] < 255 })
        XCTAssertEqual(AnimeArt.bakeChunk(layers: ch.layers).px, a.px)
    }
}
