import XCTest
import Foundation
@testable import MoonPixelCore

/// People in the anime look are real 3D models (not cards): the right height, a painted face, ink outlines
/// round the body but not over the face, wings and a halo for an angel.
final class AnimeModelTests: XCTestCase {
    static func looks() -> [Look] {
        var a = Look(); a.hair = "#f0a0c0"; a.shirt = "#ffffff"; a.pants = "#3a4a8a"; a.style = 3
        var b = Look(); b.hair = "#5a3a22"; b.shirt = "#5a8ae8"; b.style = 0
        var c = Look(); c.hair = "#f0d060"; c.shirt = "#60c080"; c.style = 2
        var d = Look(); d.hair = "#30304a"; d.shirt = "#e06060"; d.style = 1
        return [a, b, c, d]
    }

    func testAnimeFiguresAreModelsAsTallAsPeopleWithAPaintedFace() {
        for kind in AnimeArt.Figure.allCases {
            for (i, l) in AnimeModelTests.looks().enumerated() {
                let m = Figure3D.anime(l, frame: 0, held: "", child: false, female: i % 2 == 0, kind: kind)
                XCTAssertTrue(m.cel)
                XCTAssertGreaterThan(m.triangles, 1500, "a model, not a card")
                let bb = m.bounds
                XCTAssertGreaterThan(bb.max.y, Figure3D.adultHeight * 0.92, "\(kind) as tall as a grown-up")
                XCTAssertLessThan(bb.max.y, Figure3D.adultHeight * 1.35)
                XCTAssertLessThan(bb.min.y, 0.02, "feet on the ground")
                XCTAssertGreaterThan(bb.max.z - bb.min.z, 0.2, "round, not flat")
                // the face is painted after the outlined parts and gets no ink shell
                let end = try! XCTUnwrap(m.inkEnd)
                XCTAssertLessThan(end, m.positions.count)
                let inked = m.inked(width: 0.025)
                XCTAssertEqual(inked.positions.count, m.positions.count + end)
                // the whites of the eyes are on the front of the face
                let white = Palette3D.uv(RGBA(255, 255, 255))
                let front = (end..<m.positions.count).filter { m.uvs[$0] == white && m.positions[$0].z > 0.1 }
                XCTAssertFalse(front.isEmpty, "eyes")
            }
        }
        let child = Figure3D.anime(AnimeModelTests.looks()[0], frame: 0, held: "", child: true, female: true, kind: .moe)
        XCTAssertLessThan(child.bounds.max.y, Figure3D.adultHeight * 0.85)
    }

    func testAnAngelHasWingsAndAHaloAndAWalkMovesTheLegs() {
        let l = AnimeModelTests.looks()[1]
        let plain = Figure3D.anime(l, frame: 0, held: "", child: false, female: true, kind: .moe)
        let angel = Figure3D.anime(l, frame: 0, held: "", child: false, female: true, kind: .angel)
        XCTAssertGreaterThan(angel.bounds.max.y, plain.bounds.max.y + 0.03, "the halo")
        XCTAssertGreaterThan(angel.bounds.max.x - angel.bounds.min.x, (plain.bounds.max.x - plain.bounds.min.x) * 1.5, "the wings")
        let step = Figure3D.anime(l, frame: 1, held: "", child: false, female: true, kind: .moe)
        XCTAssertNotEqual(step.positions, plain.positions)
        let sword = Figure3D.anime(l, frame: 3, held: "sword", child: false, female: true, kind: .hero)
        XCTAssertGreaterThan(sword.bounds.max.y, Figure3D.adultHeight * 1.0, "the raised sword")
    }
}

extension Anime3DPreviewTests {
    func testPreviewAnime3D() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
                let pal = Tex(b: Palette3D.bitmap.animeGraded())
        var sheet = Bitmap(1600, 900, fill: RGBA(255, 255, 255))
        for (row, kind) in [AnimeArt.Figure.moe, .hero, .angel].enumerated() {
            for (i, l) in AnimeModelTests.looks().enumerated() {
                let m = Figure3D.anime(l, frame: i == 3 ? 3 : 0, held: i == 3 ? "sword" : "", child: false, female: i % 2 == 0, kind: kind).inked(width: 0.025)
                for (j, yaw) in [Float(0.0), 0.8, 2.6].enumerated() {
                    let img = render([(m, pal, false, SIMD3<Float>(0, 0, 0), Float(0))], size: (130, 300), yaw: yaw, pitch: j == 2 ? 0.7 : 0.12, scale: 300, centre: SIMD3(0, 0.5, 0))
                    sheet.blit(img, sx: 0, sy: 0, sw: 130, sh: 300, dx: (i * 3 + j) * 133, dy: row * 300, blend: false)
                }
            }
        }
        var d = Data("\(sheet.w) \(sheet.h)\n".utf8); d.append(contentsOf: sheet.px)
        try d.write(to: URL(fileURLWithPath: dir).appendingPathComponent("anime3d.rgba"))
    }
}
