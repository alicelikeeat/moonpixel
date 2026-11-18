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

    func testRoofsAreTwiceThePixelSizeOpaqueAndDifferByNation() {
        for n in [1, 2, 3, 9] {
            let a = AnimeArt.roof(nation: n, w: 6, h: 4), p = PixelArt.roof(nation: n, w: 6, h: 4)
            XCTAssertEqual(a.w, p.w * 2); XCTAssertEqual(a.h, p.h * 2)
            XCTAssertFalse(stride(from: 3, to: a.px.count, by: 4).contains { a.px[$0] < 255 }, "no holes in roof \(n)")
        }
        XCTAssertNotEqual(AnimeArt.roof(nation: 1, w: 4, h: 4).px, AnimeArt.roof(nation: 2, w: 4, h: 4).px)
    }

    func testEveryObjectIsPaintedNoneFallsBackToThePixelTile() {
        // the fallback is the pixel tile through the filter: a painted object differs from it
        for t in Content.shared.tiles.compactMap({ $0 }) where t.layer >= 2 && !t.artKind.isEmpty {
            var px = Bitmap(PixelArt.cell, PixelArt.cell); PixelArt.drawTile(&px, 0, 0, t)
            XCTAssertNotEqual(AnimeArt.tile(t).px, px.anime().px, "\(t.key) (\(t.artKind)) is painted")
        }
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

/// The anime look in 3D: plants become the 2D pictures on crossed cut-outs, solid things are cel-shaded in
/// two tones and outlined in ink, and characters are cards turned to the camera with the right drawing.
final class Anime3DTests: XCTestCase {
    func forest() -> (ChunkInput3D, Generator) {
        let gen = Generator(seed: 3)
        var layers = [[UInt8]](repeating: [UInt8](repeating: 0, count: MP.chunkArea), count: 4)
        let c = Content.shared
        for i in 0..<MP.chunkArea { layers[0][i] = c.tid("grass") }
        for k in 0..<40 { layers[2][k * 23 % MP.chunkArea] = c.tid(k % 2 == 0 ? "tree_oak" : "bush") }
        layers[2][500] = c.tid("wall_stone"); layers[2][501] = c.tid("wall_stone"); layers[2][502] = c.tid("chest")
        return (ChunkInput3D(cx: 0, cy: 0, depth: 0, layers: layers), gen)
    }

    func testPlantsBecomeCutOutsAndSolidsAreCelShadedAndInked() {
        let (input, gen) = forest()
        let pixel = Mesher3D.build(input, gen: gen), anime = Mesher3D.build(input, gen: gen, anime: true)
        XCTAssertTrue(pixel.sprites.isEmpty, "the pixel look keeps its voxel trees")
        XCTAssertEqual(anime.sprites.triangles, 40 * 4 * 2, "every tree and bush: two crossed quads, both sides")
        // the sprites read the atlas cell of their tile (u, v within that cell)
        let oak = Content.shared.tid("tree_oak")
        let u0 = Float(Int(oak) % 16) / 16
        XCTAssertTrue(anime.sprites.uvs.contains { abs($0.x - u0) < 1e-6 })
        // fewer voxel boxes (the trees are gone from the solid mesh) but every quad has its ink shell
        let pixelNoTrees = pixel.solid.triangles
        XCTAssertLessThan(anime.solid.triangles / 2, pixelNoTrees, "the trees left the solid mesh")
        XCTAssertEqual(anime.solid.triangles % 4, 0)
        let inkUV = Palette3D.uv(Mesh3D.ink)
        let inkQuads = stride(from: 0, to: anime.solid.uvs.count, by: 4).filter { anime.solid.uvs[$0] == inkUV }.count
        XCTAssertEqual(inkQuads * 2, anime.solid.positions.count / 4, "one ink shell for each quad")
        // two tones: the lit top and at most two shadow tones per colour, never the six graded ones
        var m = Mesh3D(); m.cel = true
        m.box(0, 0, 0, 1, 1, 1, RGBA(200, 120, 80), faces: .all)
        XCTAssertLessThanOrEqual(Set(m.uvs.map { "\($0)" }).count, 3)
        var p = Mesh3D(); p.box(0, 0, 0, 1, 1, 1, RGBA(200, 120, 80), faces: .all)
        XCTAssertEqual(Set(p.uvs.map { "\($0)" }).count, 6)
    }

    func testTheInkShellSitsJustOutsideAndFacesIn() {
        var m = Mesh3D()
        m.box(0, 0, 0, 1, 1, 1, RGBA(200, 120, 80), faces: [.top])
        let k = m.inked(width: 0.05)
        XCTAssertEqual(k.positions.count, 8)
        XCTAssertEqual(k.normals[4], SIMD3<Float>(0, -1, 0), "facing in")
        XCTAssertTrue(k.positions[4...].allSatisfy { abs($0.y - 1.05) < 1e-5 }, "a hair above the top")
        XCTAssertTrue(k.positions[4...].allSatisfy { $0.x < 0 || $0.x > 1 }, "and a little larger")
    }

    func testCharactersShowTheDrawingTheCameraWouldSee() {
        let fwd = Vec2(0, -1), right = Vec2(1, 0)          // camera looking north
        XCTAssertEqual(AnimeArt.cardView(facing: Vec2(0, 1), toward: fwd, right: right).dir, "down", "walking south: the face")
        XCTAssertEqual(AnimeArt.cardView(facing: Vec2(0, -1), toward: fwd, right: right).dir, "up", "walking north: the back")
        let e = AnimeArt.cardView(facing: Vec2(1, 0), toward: fwd, right: right), w = AnimeArt.cardView(facing: Vec2(-1, 0), toward: fwd, right: right)
        XCTAssertEqual(e.dir, "side"); XCTAssertFalse(e.mirrored)
        XCTAssertEqual(w.dir, "side"); XCTAssertTrue(w.mirrored, "walking left: the side drawing mirrored")
        // turn the camera round: what was the face is now the back
        XCTAssertEqual(AnimeArt.cardView(facing: Vec2(0, 1), toward: Vec2(0, 1), right: Vec2(-1, 0)).dir, "up")
        let card = AnimeArt.cardMesh(height: 2), flip = AnimeArt.cardMesh(height: 2, mirrored: true)
        XCTAssertEqual(card.triangles, 2)
        XCTAssertEqual(card.uvs[0].x, 0); XCTAssertEqual(flip.uvs[0].x, 1)
        let b = card.bounds
        XCTAssertEqual(b.max.y - b.min.y, 2, accuracy: 1e-5)
        XCTAssertEqual((b.max.x - b.min.x) / 2, Float(AnimeArt.charW) / Float(AnimeArt.charH), accuracy: 1e-5)
    }
}

/// A small software renderer for looking at the 3D meshes off the device (MP_PREVIEW): orthographic camera,
/// depth buffer, back faces culled like RealityKit, the three materials the app uses (ground picture,
/// palette, cut-out atlas) and character cards. Pixel and anime side by side.
final class Anime3DPreviewTests: XCTestCase {
    struct Tex { let b: Bitmap; func at(_ u: Float, _ v: Float) -> RGBA {
        let x = min(b.w - 1, max(0, Int(u * Float(b.w)))), y = min(b.h - 1, max(0, Int((Mesher3D.flipV ? 1 - v : v) * Float(b.h))))
        return b.get(x, y) } }

    func render(_ parts: [(Mesh3D, Tex?, Bool, SIMD3<Float>, Float)], size: (Int, Int), yaw: Float, pitch: Float, scale: Float, centre: SIMD3<Float>) -> Bitmap {
        var img = Bitmap(size.0, size.1, fill: RGBA(170, 210, 240))
        var depth = [Float](repeating: -1e9, count: size.0 * size.1)
        func view(_ p: SIMD3<Float>) -> SIMD3<Float> {
            let q = p - centre
            let x1 = q.x * cos(yaw) - q.z * sin(yaw), z1 = q.x * sin(yaw) + q.z * cos(yaw)
            let y2 = q.y * cos(pitch) - z1 * sin(pitch), z2 = q.y * sin(pitch) + z1 * cos(pitch)
            return SIMD3(x1, y2, z2)
        }
        for (m, tex, cutout, offset, turn) in parts {
            for t in stride(from: 0, to: m.indices.count, by: 3) {
                let ids = (0..<3).map { Int(m.indices[t + $0]) }
                func rot(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(v.x * cos(turn) + v.z * sin(turn), v.y, -v.x * sin(turn) + v.z * cos(turn)) }
                let n = view(rot(m.normals[ids[0]]) + centre)
                if n.z <= 0.0001 { continue }                         // facing away: culled
                let p = ids.map { view(rot(m.positions[$0]) + offset) }, uv = ids.map { m.uvs[$0] }
                let sx = p.map { $0.x * scale + Float(size.0) / 2 }, sy = p.map { -$0.y * scale + Float(size.1) / 2 }
                let minX = max(0, Int(sx.min()!)), maxX = min(size.0 - 1, Int(sx.max()!) + 1)
                let minY = max(0, Int(sy.min()!)), maxY = min(size.1 - 1, Int(sy.max()!) + 1)
                let area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0])
                if abs(area) < 1e-6 || minX > maxX || minY > maxY { continue }
                for y in minY...maxY { for x in minX...maxX {
                    let px = Float(x) + 0.5, py = Float(y) + 0.5
                    let w0 = ((sx[1] - px) * (sy[2] - py) - (sx[2] - px) * (sy[1] - py)) / area
                    let w1 = ((sx[2] - px) * (sy[0] - py) - (sx[0] - px) * (sy[2] - py)) / area
                    let w2 = 1 - w0 - w1
                    if w0 < 0 || w1 < 0 || w2 < 0 { continue }
                    let z = w0 * p[0].z + w1 * p[1].z + w2 * p[2].z
                    if z <= depth[y * size.0 + x] { continue }
                    let u = w0 * uv[0].x + w1 * uv[1].x + w2 * uv[2].x, v = w0 * uv[0].y + w1 * uv[1].y + w2 * uv[2].y
                    let c = tex.map { $0.at(u, v) } ?? Palette3D.color(at: SIMD2(u, v))
                    if cutout && c.a < 128 { continue }
                    depth[y * size.0 + x] = z
                    img.set(x, y, RGBA(c.r, c.g, c.b))
                } }
            }
        }
        return img
    }

    func testPreview3D() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        // the chunk near a town with the most trees and bushes (a green seed)
        let s = makeSociety(Int(ProcessInfo.processInfo.environment["MP_SEED"] ?? "11") ?? 11)
        let c0 = s.settlements.values.min { $0.id < $1.id }!.center
        let oak = s.content.tid("tree_oak"), pine = s.content.tid("tree_pine"), bush = s.content.tid("bush")
        var best = (0, c0.x >> 5, c0.y >> 5)
        for dy in -6...6 { for dx in -6...6 {
            let ch = s.world.chunk((c0.x >> 5) + dx, (c0.y >> 5) + dy)
            var n = 0
            for v in ch.layers[2] where v == oak || v == pine || v == bush { n += 1 }
            if n > best.0 { best = (n, (c0.x >> 5) + dx, (c0.y >> 5) + dy) }
        } }
        let input = ChunkInput3D(world: s.world, cx: best.1, cy: best.2)
        let looks: [Look] = { var a = Look(); a.hair = "#f0a0c0"; a.shirt = "#ffffff"; var b = Look(); b.hair = "#5a3a22"; b.shirt = "#5a8ae8"; var d = Look(); d.hair = "#f0d060"; d.shirt = "#60c080"; return [a, b, d] }()
        var sheet = Bitmap(1600, 600, fill: RGBA(255, 255, 255))
        for (k, anime) in [false, true].enumerated() {
            let mesh = Mesher3D.build(input, gen: s.world.gen, anime: anime)
            let ground = Tex(b: anime ? AnimeArt.bakeGround(layers: input.layers) : PixelArt.bakeGround(layers: input.layers))
            let palette = anime ? Palette3D.bitmap.animeGraded() : Palette3D.bitmap
            var solid = mesh.solid
            // the palette the app uses is graded in the anime look: the same lookup on the graded picture
            let pal = Tex(b: palette)
            _ = pal
            let base = mesh.heights[16 * 32 + 16]
            var parts: [(Mesh3D, Tex?, Bool, SIMD3<Float>, Float)] = [(mesh.ground, ground, false, .zero, 0), (solid, Tex(b: palette.flippedForPalette()), false, .zero, 0)]
            if anime { parts.append((mesh.sprites, Tex(b: AnimeArt.atlas), true, .zero, 0)) }
            let yaw: Float = 0.65, pitch: Float = 0.62
            // three people standing near the middle: cards turned to the camera (anime), figures (pixel)
            for (i, l) in looks.enumerated() {
                let at = SIMD3<Float>(14 + Float(i) * 2, base, 18)
                if anime {
                    let pic = AnimeArt.character(l, dir: ["down", "side", "up"][i], frame: 0, held: "", child: false, female: i == 0)
                    parts.append((AnimeArt.cardMesh(height: 1.9, mirrored: false), Tex(b: pic), true, at, yaw))
                } else {
                    parts.append((Figure3D.human(l, frame: 0, held: "", child: false, female: i == 0), Tex(b: palette.flippedForPalette()), false, at, 0))
                }
            }
            solid = Mesh3D()
            let img = render(parts, size: (800, 600), yaw: yaw, pitch: pitch, scale: 40, centre: SIMD3(16, base, 17))
            sheet.blit(img, sx: 0, sy: 0, sw: 800, sh: 600, dx: k * 800, dy: 0, blend: false)
        }
        var d = Data("\(sheet.w) \(sheet.h)\n".utf8); d.append(contentsOf: sheet.px)
        try d.write(to: URL(fileURLWithPath: dir).appendingPathComponent("3d-compare.rgba"))
    }
}

extension Bitmap {
    /// The palette picture as `Palette3D.color(at:)` reads it (rows counted from the top), for `Tex`.
    func flippedForPalette() -> Bitmap { self }
}

final class RoofPreviewTests: XCTestCase {
    func testRoofs() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        var sheet = Bitmap(4 * 7 * 32 + 60, 6 * 32 + 30, fill: RGBA(120, 170, 110))
        for n in 0..<4 { let r = AnimeArt.roof(nation: n + 1 == 4 ? 7 : n + 1, w: 7, h: 5); sheet.blit(r, sx: 0, sy: 0, sw: r.w, sh: r.h, dx: 10 + n * (7 * 32 + 12), dy: 10, blend: true) }
        var d = Data("\(sheet.w) \(sheet.h)\n".utf8); d.append(contentsOf: sheet.px)
        try d.write(to: URL(fileURLWithPath: dir).appendingPathComponent("roofs.rgba"))
    }
}
