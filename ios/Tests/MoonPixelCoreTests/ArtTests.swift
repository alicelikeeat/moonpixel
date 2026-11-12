import XCTest
@testable import MoonPixelCore

final class ArtTests: XCTestCase {
    func close(_ a: RGBA, _ b: RGBA, _ eps: Double = 0.12) -> Bool { a.dist(b) < eps }

    func portrait(skin: RGBA, hair: RGBA, shirt: RGBA) -> Bitmap {
        var img = Bitmap(240, 320, fill: RGBA(hex: "#8fb4d8"))
        for y in 0..<320 { for x in 0..<240 {
            let dx = Double(x - 120) / 62, dy = Double(y - 120) / 78
            if y > 215 && abs(Double(x - 120)) < 60 + Double(y - 215) * 0.9 { img.set(x, y, shirt) }
            if abs(x - 120) < 22 && y > 180 && y < 222 { img.set(x, y, skin.darkened(0.08)) }
            let hx = Double(x - 120) / 72, hy = Double(y - 100) / 84
            if hx * hx + hy * hy < 1 && y < 150 { img.set(x, y, hair) }
            if dx * dx + dy * dy < 1 && y > 70 { img.set(x, y, skin) }
        } }
        return img
    }

    func testChibiCharacterParts() {
        var look = Look()
        look.skin = "#f2c8a4"; look.hair = "#5a3a22"; look.shirt = "#3a6ac8"; look.pants = "#4a4a5a"; look.shoes = "#5a3a2a"
        let img = PixelArt.character(look, dir: "down", frame: 0, held: "", child: false, female: false)
        XCTAssertEqual(img.w, 32); XCTAssertEqual(img.h, 40)
        XCTAssertTrue(close(img.get(15, 10), RGBA(hex: "#5a3a22")), "hair")
        XCTAssertTrue(close(img.get(15, 18), RGBA(hex: "#f2c8a4")), "face")
        XCTAssertTrue(close(img.get(12, 16), RGBA(hex: "#2a2233")) && close(img.get(19, 16), RGBA(hex: "#2a2233")), "eyes")
        XCTAssertEqual(img.get(11, 15), .white, "eye highlight")
        XCTAssertTrue(close(img.get(14, 28), RGBA(hex: "#3a6ac8")), "torso")
        XCTAssertTrue(close(img.get(9, 30), RGBA(hex: "#f2c8a4")) && close(img.get(22, 30), RGBA(hex: "#f2c8a4")), "hands")
        XCTAssertTrue(close(img.get(13, 34), RGBA(hex: "#4a4a5a")), "legs")
        XCTAssertTrue(close(img.get(12, 37), RGBA(hex: "#5a3a2a")) && close(img.get(19, 37), RGBA(hex: "#5a3a2a")), "feet")
        XCTAssertEqual(img.get(6, 15), PixelArt.outline)
        let bare = img
        for held in PixelArt.held where !held.isEmpty {
            let h = PixelArt.character(look, dir: "down", frame: 0, held: held, child: false, female: false)
            var extra = 0
            for y in 0..<40 { for x in 0..<32 where h.get(x, y).a > 0 && bare.get(x, y).a == 0 { extra += 1 } }
            XCTAssertGreaterThanOrEqual(extra, 10, held)
        }
        for dir in ["down", "up", "side"] { for f in 0..<4 {
            let b = PixelArt.character(look, dir: dir, frame: f, held: "staff", child: f == 1, female: true)
            XCTAssertTrue(b.px.contains { $0 != 0 })
        } }
    }

    func testTilesAndChunkBake() {
        XCTAssertEqual(PixelArt.atlas.w, 512)
        let w = OpenWorld(seed: 3, budget: MemoryBudget(overrideMB: 96))
        let img = PixelArt.bakeChunk(w.chunk(0, 0))
        XCTAssertEqual(img.w, 528); XCTAssertEqual(img.h, 536)
        XCTAssertEqual(img.get(8 + 100, 24 + 100).a, 255, "ground is opaque")
    }

    func testPhotoToLook() {
        let skin = RGBA(hex: "#c98a62"), hair = RGBA(hex: "#2b1d16"), shirt = RGBA(hex: "#2f9e6a")
        let out = AssetImporter.photoToLook(portrait(skin: skin, hair: hair, shirt: shirt))
        XCTAssertTrue(close(RGBA(hex: out.look.skin), skin, 0.15), out.look.skin)
        XCTAssertTrue(close(RGBA(hex: out.look.hair), hair, 0.2), out.look.hair)
        XCTAssertTrue(close(RGBA(hex: out.look.shirt), shirt, 0.2), out.look.shirt)
        XCTAssertEqual(out.face.w, 10); XCTAssertEqual(out.face.h, 8)
        let f = out.faceRect
        XCTAssertTrue(f.0 <= 32 && f.0 + f.2 >= 32 && f.1 <= 26 && f.1 + f.3 >= 26, "face box \(f)")
        PixelArt.faces["t"] = out.face
        var look = out.look
        look.face = "t"
        let img = PixelArt.character(look, dir: "down", frame: 0, held: "", child: false, female: false)
        XCTAssertEqual(img.get(15, 17), out.face.get(4, 3))
    }

    func testPixelize() {
        var pic = Bitmap(200, 160, fill: RGBA(hex: "#eeeee6"))
        for y in 0..<160 { for x in 0..<200 {
            let dx = Double(x - 100) / 55, dy = Double(y - 95) / 42
            if dx * dx + dy * dy < 1 { pic.set(x, y, dy > -0.2 ? RGBA(hex: "#bf4033") : RGBA(hex: "#d95947")) }
        } }
        let img = AssetImporter.pixelize(pic, maxSide: 32, colors: 8)
        XCTAssertLessThanOrEqual(max(img.w, img.h), 32)
        XCTAssertEqual(img.get(0, 0).a, 0)
        XCTAssertGreaterThan(img.get(img.w / 2, img.h * 6 / 10).a, 0)
        var cols = Set<String>()
        for y in 0..<img.h { for x in 0..<img.w { let c = img.get(x, y); if c.a > 0 { cols.insert(c.hex) } } }
        XCTAssertTrue(cols.count >= 1 && cols.count <= 8, "\(cols.count) colours")
        XCTAssertLessThanOrEqual(AssetImporter.pixelize(pic, maxSide: 500).w, AssetImporter.maxSprite)
    }
}
