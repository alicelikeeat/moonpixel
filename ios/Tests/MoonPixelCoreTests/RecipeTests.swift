import XCTest
@testable import MoonPixelCore

final class RecipeTests: XCTestCase {
    func testOneSentenceChinese() {
        let r = WorldRecipe.parse("创建一个叫月光岛的冰雪海岛世界，200人，5个村庄，工业时代")
        XCTAssertEqual(r.name, "月光岛")
        XCTAssertTrue(r.tags.contains("snow") && r.tags.contains("island"))
        XCTAssertEqual(r.villages, 5); XCTAssertEqual(r.perVillage, 40); XCTAssertEqual(r.startTech, 5)
        XCTAssertLessThan(r.tempBias, -0.2); XCTAssertLessThan(r.elevBias, 0)
        XCTAssertEqual(r, WorldRecipe.parse("创建一个叫月光岛的冰雪海岛世界，200人，5个村庄，工业时代"), "deterministic")
    }

    func testOneSentenceEnglish() {
        let r = WorldRecipe.parse("A huge desert world named Dune Home with AI, seed 42")
        XCTAssertEqual(r.seed, 42); XCTAssertEqual(r.startTech, 9); XCTAssertEqual(r.villages, 7)
        XCTAssertTrue(r.tags.contains("desert")); XCTAssertEqual(r.name, "Dune")
        let plain = WorldRecipe.parse("a rainy mountain village, 3 villages, 60 people")
        XCTAssertEqual(plain.villages, 3); XCTAssertEqual(plain.perVillage, 20); XCTAssertEqual(plain.startTech, 0)
        XCTAssertFalse(WorldRecipe.parse("a plain world").tags.contains { $0.hasPrefix("era") }, "'ai' inside a word is not the AI era")
        let e = WorldRecipe.parse("")
        XCTAssertEqual(e.villages, 4); XCTAssertEqual(e.perVillage, 30)
        XCTAssertEqual(WorldRecipe.parse("三个村庄，一百多人的森林").villages, 3)
        XCTAssertEqual(WorldRecipe.parse("三个村庄，一百多人的森林").population, 99)
    }

    /// Every themed world must still be habitable and actually look like its theme.
    func testThemedWorldsAreHabitable() {
        for (text, biome) in [("沙漠世界", "desert"), ("冰雪世界", "snow"), ("海岛世界 60 人", ""), ("高山森林，未来", "")] {
            let r = WorldRecipe.parse(text)
            let w = OpenWorld(seed: r.seed, budget: MemoryBudget(overrideMB: 256))
            w.gen.tempBias = r.tempBias; w.gen.moistBias = r.moistBias; w.gen.elevBias = r.elevBias
            let s = Society(world: w, seed: r.seed)
            s.minPopulation = r.minPopulation
            s.grantTech(r.startTech)
            s.bootstrap(origin: TilePos(0, 0), villages: r.villages, per: r.perVillage)
            XCTAssertGreaterThanOrEqual(s.settlements.count, max(1, r.villages - 1), text)
            XCTAssertGreaterThanOrEqual(s.agents.count, (r.villages - 1) * r.perVillage, text)
            XCTAssertEqual(s.techCount, r.startTech)
            if !biome.isEmpty {
                var hit = 0, land = 0
                let names = biome == "snow" ? ["snow", "taiga"] : ["desert", "canyon"]
                for i in 0..<400 {
                    let x = (i % 20) * 37 - 370, y = (i / 20) * 37 - 370
                    let b = Content.shared.biomes[w.gen.biome(x, y)].key
                    if b == "ocean" { continue }
                    land += 1
                    if names.contains(b) { hit += 1 }
                }
                XCTAssertGreaterThan(Double(hit), Double(land) * 0.5, "\(text): \(hit)/\(land)")
            }
            for _ in 0..<600 { s.tick(0.5) }
            XCTAssertGreaterThan(s.agents.count, r.villages * r.perVillage / 2, "\(text) survives")
        }
    }

    func testAnimatedSpriteFromFrames() {
        // a bouncing figure on a flat backdrop
        var frames: [Bitmap] = []
        for i in 0..<20 {
            var f = Bitmap(120, 160, fill: RGBA(hex: "#8fb4d8"))
            let dy = i % 2 == 0 ? 0 : 6
            for y in 0..<160 { for x in 0..<120 {
                if abs(x - 60) < 18 && y > 60 + dy && y < 130 + dy { f.set(x, y, RGBA(hex: "#c83a5a")) }
                let dx = Double(x - 60), ddy = Double(y - 42 - dy)
                if dx * dx + ddy * ddy < 400 { f.set(x, y, RGBA(hex: "#f2c8a4")) }
            } }
            frames.append(f)
        }
        let out = AssetImporter.spriteFrames(frames, maxFrames: 8)
        XCTAssertEqual(out.count, 8)
        XCTAssertTrue(out.allSatisfy { $0.w == out[0].w && $0.h == out[0].h && $0.w <= 38 && $0.h <= 46 })
        XCTAssertEqual(out[0].get(0, 0).a, 0, "background removed")
        XCTAssertTrue(out[0].px != out[2].px, "frames differ: the animation is kept")
        let mid = out[0].get(out[0].w / 2, out[0].h * 2 / 3)
        XCTAssertLessThan(mid.dist(RGBA(hex: "#c83a5a")), 0.15, "body colour kept")
        let back = AssetImporter.unsheet(AssetImporter.sheet(out), count: 8)
        XCTAssertTrue(back.map { $0.px } == out.map { $0.px })
    }
}
