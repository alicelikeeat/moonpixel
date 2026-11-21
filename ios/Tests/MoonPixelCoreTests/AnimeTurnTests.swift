import XCTest
import Foundation
@testable import MoonPixelCore

/// The anime figures turn all the way round (16 angles), not only front, back and side.
final class AnimeTurnTests: XCTestCase {
    func look(_ i: Int) -> Look {
        var l = Look()
        let c = [("#f2c8a4", "#5a3a22", "#5a8ae8", "#4a4a5a"), ("#ffe0c8", "#f0a0c0", "#ffffff", "#e05a7a"), ("#e8b890", "#202838", "#d84a4a", "#30304a"), ("#f8d8c0", "#f0d060", "#60c080", "#5a4a3a")][i % 4]
        l.skin = c.0; l.hair = c.1; l.shirt = c.2; l.pants = c.3; l.style = i % 4
        return l
    }

    func testTheCameraSeesTheRightTurn() {
        // seen from above: looking south is the face, east the right side, north the back, west the left
        XCTAssertEqual(AnimeArt.turnStep(facing: Vec2(0, 1)), 0)
        XCTAssertEqual(AnimeArt.turnStep(facing: Vec2(1, 0)), 6)
        XCTAssertEqual(AnimeArt.turnStep(facing: Vec2(0, -1)), 12)
        XCTAssertEqual(AnimeArt.turnStep(facing: Vec2(-1, 0)), 18)
        XCTAssertEqual(AnimeArt.turnStep(facing: Vec2(1, 1)), 3, "half way between the face and the side")
        // in 3D the camera's own direction counts: a camera looking east sees the face of someone looking west
        XCTAssertEqual(AnimeArt.turnStep(facing: Vec2(-1, 0), toward: Vec2(1, 0), right: Vec2(0, 1)), 0)
        XCTAssertEqual(AnimeArt.turnDir(25), "t1")
    }

    func testEveryTurnIsADifferentDrawingAndTurnsAreMirrorImagesOfTheirOpposites() {
        for kind in AnimeArt.Figure.allCases {
            AnimeArt.figure = kind
            defer { AnimeArt.figure = .moe }
            var seen: [[UInt8]] = []
            for step in 0..<AnimeArt.turnSteps {
                let b = AnimeArt.character(look(1), dir: AnimeArt.turnDir(step), frame: 0, held: "", child: false, female: true)
                XCTAssertEqual(b.w, AnimeArt.charW * AnimeArt.figureScale)
                let ink = stride(from: 3, to: b.px.count, by: 4).filter { b.px[$0] > 0 }.count
                XCTAssertGreaterThan(ink, b.w * b.h / 8, "\(kind) turn \(step) is drawn")
                XCTAssertFalse(seen.contains(b.px), "\(kind) turn \(step) differs from the others")
                seen.append(b.px)
            }
            // the figure is symmetric enough that turning left and right are near mirror images: most of the
            // opaque pixels of turn 4 have a partner in the mirror of turn 12 (a style ornament may differ)
            let r = AnimeArt.character(look(0), dir: "t6", frame: 0, held: "", child: false, female: true)
            let l = AnimeArt.mirrored(AnimeArt.character(look(0), dir: "t18", frame: 0, held: "", child: false, female: true))
            var both = 0, either = 0
            for i in stride(from: 3, to: r.px.count, by: 4) { let a = r.px[i] > 128, b = l.px[i] > 128; if a || b { either += 1 }; if a && b { both += 1 } }
            XCTAssertGreaterThan(Double(both) / Double(max(1, either)), 0.8, "\(kind): the two sides match")
        }
    }

    func testTheFaceShowsInFrontAndTheBackOfTheHeadBehind() {
        // the eyes' white shows from the front and not from behind
        let front = AnimeArt.character(look(2), dir: "t0", frame: 0, held: "", child: false, female: false)
        let back = AnimeArt.character(look(2), dir: "t12", frame: 0, held: "", child: false, female: false)
        func whites(_ b: Bitmap) -> Int { stride(from: 0, to: b.px.count, by: 4).filter { b.px[$0] > 240 && b.px[$0 + 1] > 240 && b.px[$0 + 2] > 245 && b.px[$0 + 3] > 200 }.count }
        XCTAssertGreaterThan(whites(front), whites(back) + 20)
        // a model figure turns too: its body at every angle (all different), what it wears from the nearest view;
        // a round little creature is the same all round (the nearest view, mirrored on the left)
        var m = look(0); m.model = CharacterModels.all.first { !$0.round }!.key
        let turns = (0..<AnimeArt.turnSteps).map { AnimeArt.character(m, dir: AnimeArt.turnDir($0), frame: 0, held: "", child: false, female: false).px }
        XCTAssertEqual(Set(turns.map { $0.hashValue }).count, AnimeArt.turnSteps, "a model's every turn is drawn")
        var r = look(0); r.model = CharacterModels.all.first { $0.round }!.key
        XCTAssertEqual(AnimeArt.character(r, dir: "t18", frame: 0, held: "", child: false, female: false).px,
                       AnimeArt.mirrored(AnimeArt.character(r, dir: "side", frame: 0, held: "", child: false, female: false)).px)
    }

    /// Writes a sheet of every turn (MP_PREVIEW set to a directory): rows moe girl, moe boy, angel, hero.
    func testPreviewSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        let cw = AnimeArt.charW * AnimeArt.figureScale, ch = AnimeArt.charH * AnimeArt.figureScale
        var sheet = Bitmap(cw * 24, ch * 5, fill: RGBA(200, 220, 235))
        let rows: [(AnimeArt.Figure, Int, Bool, Int)] = [(.moe, 1, true, 0), (.moe, 2, false, 0), (.angel, 0, true, 0), (.hero, 3, false, 0), (.moe, 1, true, 1)]
        for (r, row) in rows.enumerated() {
            AnimeArt.figure = row.0
            for s in 0..<24 {
                var l = look(row.1)
                if r == 4 { l.model = CharacterModels.all.first { !$0.round }!.key }      // (the last row: a character model)
                let b = AnimeArt.character(l, dir: AnimeArt.turnDir(s), frame: row.3, held: "", child: false, female: row.2)
                sheet.blit(b, sx: 0, sy: 0, sw: b.w, sh: b.h, dx: s * cw, dy: r * ch, blend: true)
            }
        }
        AnimeArt.figure = .moe
        var d = Data("\(sheet.w) \(sheet.h)\n".utf8); d.append(contentsOf: sheet.px)
        try d.write(to: URL(fileURLWithPath: dir).appendingPathComponent("turns.rgba"))
    }
}
